/* src/conn.s - Event-driven connection layer (fast path)
 *
 * Replaces the blocking accept-mutex worker with an epoll_pwait loop:
 *   listen fd (EPOLLEXCLUSIVE) -> accept_storm -> conn slots
 *   client fd  -> conn_on_read (read + find header + conn_serve) / conn_on_write
 *
 * The "processing segment" (conn_serve, provided by http.s) runs synchronously
 * inside the event loop and is guaranteed non-blocking; only read/write/sendfile
 * are sliced into states.  Slow requests (proxy / CGI / POST / dynamic gzip)
 * fork a child that continues the original blocking code path in place.
 */

.include "src/defs.s"

/* ---- exported ---------------------------------------------------------- */
.global worker_event_loop
.global conn_sink_write
.global conn_on_read
.global conn_on_write
.global conn_close
.global conn_alloc
.global conn_lookup
.global conn_init
.global accept_storm
.global fork_slow_child
.global refresh_date
.global idle_scan

/* ---- imported ---------------------------------------------------------- */
.extern conn_serve              /* http.s: (x0=conn) -> 0/1/2/3           */
.extern fdc_put_slot           /* fdcache.s: return a borrow by slot        */
.extern get_http_date           /* utils.s: fills http_date_buffer         */
.extern http_date_buffer
.extern req_buffer
.extern keepalive_timeout       /* config_nginx.s (.word, may be 0)        */
.extern conn_pool
.extern conn_by_fd
.extern epoll_events_big
.extern slow_child_mode
.extern slow_write_failed
.extern slow_children
.extern date_buf_sec
.extern cur_conn

/* Local syscall / flag aliases not covered by defs.s */
.equ CLOCK_REALTIME,   0
.equ WNOHANG,          1
.equ SIG_DFL,          0
.equ SIGINT,           2
.equ SIGTERM,          15
.equ SIGHUP,           1
.equ SIGUSR1,          10
.equ REQ_BUF_MAX,      8191     /* req_buffer is 8192B incl. NUL           */
.equ EV_ERRMASK,       (EPOLLERR|EPOLLHUP)
.equ IDLE_DEFAULT,     65

/* Per-wakeup sendfile ceiling. cf_file pushes up to this many bytes per
 * conn_flush call, then yields to the event loop even if the socket could
 * take more. Keeps large transfers (>=256KB) from monopolizing a worker
 * between epoll wakeups, improving fairness under many concurrent conns.
 * 0 = unbounded (legacy single-shot behavior). */
.equ SF_CHUNK,        262144   /* 256 KB */

/* Fields local to conn.s, living in the reserved gap of the conn header
 * (offsets 96..127 are unused by the contract's layout). */
.equ CONN_SCAN_OFF,     96      /* u32 absolute read_buf scan cursor       */
.equ CONN_F_OUT_ARMED,  16      /* flags bit4: EPOLLOUT currently armed    */

.data
    .align 3
    listen_fd_global:   .quad 0     /* worker listen socket                */
    epoll_fd_global:    .quad 0     /* worker epoll instance               */
    accept_paused:      .word 0     /* 1 = listen fd removed from epoll    */
    spin_last_fd:       .word 0     /* diag: same-fd repeat detector       */
    spin_last_mask:     .word 0
    spin_same_cnt:      .word 0
    .align 3

.text

/* =========================================================================
 * worker_event_loop(x0 = listen_fd) - never returns
 * ========================================================================= */
worker_event_loop:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]

    mov x19, x0                     /* x19 = listen_fd */
    ldr x9, =listen_fd_global
    str x19, [x9]

    /* The listen socket must be non-blocking: accept4's SOCK_NONBLOCK only
     * applies to the accepted socket, so accept_storm would otherwise block
     * in the kernel on the iteration that drains the queue instead of
     * returning EAGAIN. */
    mov x0, x19
    mov x1, #F_GETFL
    mov x2, #0
    mov x8, SYS_FCNTL
    svc #0
    cmp x0, #0
    blt wel_nb_done
    orr x2, x0, #O_NONBLOCK
    mov x0, x19
    mov x1, #F_SETFL
    mov x8, SYS_FCNTL
    svc #0
wel_nb_done:

    /* epoll_create1(0) */
    mov x0, #0
    mov x8, SYS_EPOLL_CREATE1
    svc #0
    mov x20, x0                     /* x20 = epfd */
    ldr x9, =epoll_fd_global
    str x20, [x9]

    /* EPOLL_CTL_ADD(listen_fd, EPOLLIN|EPOLLEXCLUSIVE, data.fd=listen_fd) */
    mov x0, x19
    ldr w1, =(EPOLLIN|EPOLLEXCLUSIVE)
    bl ep_add

    bl w_setup_signals

    /* Prime the Date cache: the fast path serves http_date_buffer verbatim,
     * and the first responses would otherwise carry an empty header. */
    bl refresh_date

wel_loop:
    /* epoll_pwait(epfd, events, MAX_EVENTS, 1000ms, NULL, 0) */
    mov x0, x20
    ldr x1, =epoll_events_big
    mov x2, #MAX_EVENTS
    mov x3, #1000
    mov x4, #0
    mov x5, #0
    mov x8, SYS_EPOLL_PWAIT
    svc #0

    cmp x0, #0
    ble wel_tick                    /* error or timeout -> housekeeping */

    mov x21, x0                     /* x21 = n events */
    mov x22, #0                     /* x22 = index */
    ldr x23, =epoll_events_big      /* x23 = cursor */

wel_ev:
    cmp x22, x21
    bge wel_tick

    ldr w24, [x23]                  /* w24 = events mask   (offset 0) */
    ldr w25, [x23, #8]              /* w25 = data.fd       (offset 8) */
    add x23, x23, #16
    add x22, x22, #1

    /* listen fd? */
    cmp w25, w19
    beq wel_accept

    /* conn = conn_by_fd[fd] */
    mov w0, w25
    bl conn_lookup
    cbz x0, wel_stray
    mov x26, x0                     /* x26 = conn */

    /* error/hangup first */
    tst w24, #EV_ERRMASK
    bne wel_err

    /* Dispatch on state, not on the event bits: with level-triggered epoll a
     * connection in WRITE_* can also report EPOLLIN (unread pipelined bytes).
     * Re-entering conn_on_read there would re-parse the same request. */
    ldr w9, [x26, #CONN_STATE_OFF]
    cmp w9, #CONN_READ_HEAD
    bne wel_do_write

    tst w24, #EPOLLIN
    beq wel_skip_cnt                /* useless wakeup: count it */
    ldr x9, =spin_same_cnt
    str wzr, [x9]
    mov x0, x26
    bl conn_on_read
    b wel_ev

wel_do_write:
    tst w24, #EPOLLOUT
    beq wel_skip_cnt                /* useless wakeup: count it */
    ldr x9, =spin_same_cnt
    str wzr, [x9]
    mov x0, x26
    bl conn_on_write
    b wel_ev

wel_skip_cnt:
    /* The dispatch would do zero work on this event (READ_HEAD woken without
     * EPOLLIN, or WRITE_* woken without EPOLLOUT): a mask/state divergence.
     * Self-heal in one shot by re-arming the mask the current state needs,
     * instead of looping forever on a level-triggered refire.  If it cannot
     * converge, ws_emergency_close drops the conn rather than spinning. */
    ldr w9, [x26, #CONN_STATE_OFF]
    cmp w9, #CONN_READ_HEAD
    bne ws_need_out
    mov w1, #EPOLLIN
    b ws_do_mod
ws_need_out:
    mov w1, #EPOLLOUT
ws_do_mod:
    mov x0, x25                     /* client fd */
    bl ep_mod
    ldr x9, =spin_same_cnt
    ldr w12, [x9]
    add w12, w12, #1
    str w12, [x9]
    cmp w12, #65536
    bge ws_emergency_close
    b wel_ev

ws_emergency_close:
    /* Self-heal failed to converge: drop the conn instead of spinning. */
    ldr x9, =spin_same_cnt
    str wzr, [x9]
    mov x0, x26
    bl conn_close
    b wel_ev

wel_err:
    mov x0, x26
    bl conn_close
    b wel_ev

wel_stray:
    /* No conn for this fd: stale registration, drop it. */
    mov w0, w25
    mov x8, SYS_CLOSE
    svc #0
    b wel_ev


wel_accept:
    bl accept_storm
    b wel_ev

wel_tick:
    /* Refresh the cached Date header; only when the second actually rolled
     * over is it worth walking the whole pool for idle connections. */
    bl refresh_date
    cbz x0, wel_loop
    bl idle_scan
    b wel_loop

/* =========================================================================
 * w_setup_signals - worker-local signal disposition
 *   SIGCHLD -> w_sigchld_handler (reap slow-path children)
 *   SIGINT/SIGTERM/SIGHUP/SIGUSR1 -> SIG_DFL (master's handlers are inherited
 *   through clone() and would otherwise run the master shutdown logic here)
 * struct sigaction on aarch64 is 24B: handler@0, flags@8, mask@16.
 * ========================================================================= */
w_setup_signals:
    stp x29, x30, [sp, #-48]!
    mov x29, sp

    /* act = sp+16 .. sp+40 (32B reserved, 24B used) */
    ldr x9, =w_sigchld_handler
    str x9, [sp, #16]               /* sa_handler */
    str xzr, [sp, #24]              /* sa_flags   */
    str xzr, [sp, #32]              /* sa_mask    */

    mov x0, #SIGCHLD
    add x1, sp, #16
    mov x2, #0
    mov x3, #8
    mov x8, SYS_RT_SIGACTION
    svc #0

    /* Reset the master-installed handlers back to default. */
    str xzr, [sp, #16]              /* SIG_DFL */
    str xzr, [sp, #24]
    str xzr, [sp, #32]

    mov x0, #SIGINT
    add x1, sp, #16
    mov x2, #0
    mov x3, #8
    mov x8, SYS_RT_SIGACTION
    svc #0

    mov x0, #SIGTERM
    add x1, sp, #16
    mov x2, #0
    mov x3, #8
    mov x8, SYS_RT_SIGACTION
    svc #0

    mov x0, #SIGHUP
    add x1, sp, #16
    mov x2, #0
    mov x3, #8
    mov x8, SYS_RT_SIGACTION
    svc #0

    mov x0, #SIGUSR1
    add x1, sp, #16
    mov x2, #0
    mov x3, #8
    mov x8, SYS_RT_SIGACTION
    svc #0

    ldp x29, x30, [sp], #48
    ret

/* =========================================================================
 * w_sigchld_handler - reap slow-path children
 * Signal context: no frame games, only caller-saved scratch.
 * SIGCHLD coalesces, so decrement slow_children once per reaped pid.
 * ========================================================================= */
w_sigchld_handler:
    sub sp, sp, #16
wsc_loop:
    mov x0, #-1
    mov x1, sp
    mov x2, #WNOHANG
    mov x3, #0
    mov x8, SYS_WAIT4
    svc #0
    cmp x0, #0
    ble wsc_done                    /* <0 = no children, 0 = none exited */

    /* slow_children-- (atomic; exclusive monitor may be cleared, so retry) */
    ldr x9, =slow_children
wsc_dec:
    ldxr w10, [x9]
    sub w10, w10, #1
    cmp w10, #0
    csel w10, wzr, w10, lt          /* clamp at 0 */
    stxr w11, w10, [x9]
    cbnz w11, wsc_dec
    b wsc_loop

wsc_done:
    add sp, sp, #16
    ret

/* =========================================================================
 * ep_add(x0 = fd, w1 = events) - EPOLL_CTL_ADD with data.fd = fd
 * ep_mod(x0 = fd, w1 = events) - EPOLL_CTL_MOD with data.fd = fd
 * ep_del(x0 = fd)              - EPOLL_CTL_DEL
 * epoll_event is 16B: events u32 @0, data (union) @8; we use data.fd.
 * Note: EPOLLEXCLUSIVE registrations may only be ADDed and DELeted; the
 * kernel rejects EPOLL_CTL_MOD on them with EINVAL, so the listen fd is
 * paused by removing it outright rather than by clearing EPOLLIN.
 * ========================================================================= */
ep_add:
    mov x9, #EPOLL_CTL_ADD
    b ep_ctl
ep_del:
    mov x9, #EPOLL_CTL_DEL
    mov w1, #0
    b ep_ctl
ep_mod:
    mov x9, #EPOLL_CTL_MOD
ep_ctl:
    sub sp, sp, #16
    str w1, [sp]                    /* events */
    str wzr, [sp, #4]
    str w0, [sp, #8]                /* data.fd */
    str wzr, [sp, #12]
    mov x3, sp                      /* event ptr */
    mov x2, x0                      /* fd */
    mov x1, x9                      /* op */
    ldr x0, =epoll_fd_global
    ldr x0, [x0]
    mov x8, SYS_EPOLL_CTL
    svc #0
    add sp, sp, #16
    ret

/* =========================================================================
 * now_secs() -> x0 = CLOCK_REALTIME seconds
 * ========================================================================= */
now_secs:
    sub sp, sp, #16
    mov x0, #CLOCK_REALTIME
    mov x1, sp
    mov x8, SYS_CLOCK_GETTIME
    svc #0
    ldr x0, [sp]
    add sp, sp, #16
    ret

/* =========================================================================
 * refresh_date() -> x0 = 1 if the cached Date was regenerated, else 0
 * ========================================================================= */
refresh_date:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]

    bl now_secs
    mov x19, x0
    ldr x9, =date_buf_sec
    ldr x10, [x9]
    cmp x10, x19
    beq rd_same

    bl get_http_date                /* writes http_date_buffer */
    ldr x9, =date_buf_sec
    str x19, [x9]
    mov x0, #1
    b rd_out

rd_same:
    mov x0, #0
rd_out:
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

/* =========================================================================
 * idle_scan() - close connections idle beyond keepalive_timeout (default 65s)
 * ========================================================================= */
idle_scan:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    str x23, [sp, #48]

    bl now_secs
    mov x19, x0                     /* x19 = now */

    ldr x9, =keepalive_timeout
    ldr w20, [x9]
    cmp w20, #0
    bgt is_have_to
    mov w20, #IDLE_DEFAULT
is_have_to:
    sxtw x20, w20                   /* x20 = threshold seconds */

    ldr x21, =conn_pool             /* x21 = slot cursor */
    mov x22, #0                     /* x22 = index */
    ldr x23, =CONN_SIZE

is_loop:
    cmp x22, #CONN_MAX
    bge is_done

    ldr w9, [x21, #CONN_STATE_OFF]
    cbz w9, is_next                 /* CONN_FREE */

    ldr x9, [x21, #CONN_LAST_ACT_OFF]
    sub x9, x19, x9
    cmp x9, x20
    ble is_next

    mov x0, x21
    bl conn_close

is_next:
    add x21, x21, x23
    add x22, x22, #1
    b is_loop

is_done:
    ldr x23, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

/* =========================================================================
 * conn_alloc() -> x0 = conn slot (zeroed) or 0 when the pool is exhausted
 * ========================================================================= */
conn_alloc:
    ldr x9, =conn_pool
    mov x10, #0
    ldr x11, =CONN_SIZE

ca_loop:
    cmp x10, #CONN_MAX
    bge ca_none
    ldr w12, [x9, #CONN_STATE_OFF]
    cbz w12, ca_found
    add x9, x9, x11
    add x10, x10, #1
    b ca_loop

ca_found:
    /* Zero the fixed header area (offsets 0..127); the 4K/16K buffers are
     * written before they are read, so clearing them would be wasted work. */
    mov x12, x9
    stp xzr, xzr, [x12, #0]
    stp xzr, xzr, [x12, #16]
    stp xzr, xzr, [x12, #32]
    stp xzr, xzr, [x12, #48]
    stp xzr, xzr, [x12, #64]
    stp xzr, xzr, [x12, #80]
    stp xzr, xzr, [x12, #96]
    stp xzr, xzr, [x12, #112]
    mov x0, x9
    ret

ca_none:
    mov x0, #0
    ret

/* =========================================================================
 * conn_lookup(x0 = fd) -> x0 = conn or 0
 * ========================================================================= */
conn_lookup:
    mov w9, w0
    cmp w9, #0
    blt cl_none
    ldr x10, =65536
    cmp x9, x10
    bge cl_none
    ldr x10, =conn_by_fd
    ldr x0, [x10, x9, lsl #3]
    ret
cl_none:
    mov x0, #0
    ret

/* =========================================================================
 * conn_init(x0 = conn, x1 = fd)
 * ========================================================================= */
conn_init:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    mov x20, x1

    /* TCP_NODELAY (once per connection): without it, Nagle + delayed-ACK
     * interplay stalls two-write responses (header + body) ~40ms on
     * loopback.  nginx sets it unconditionally too. */
    mov x0, x20
    mov x1, IPPROTO_TCP
    mov x2, TCP_NODELAY
    ldr x3, =optval
    mov x4, #4
    mov x8, SYS_SETSOCKOPT
    svc #0

    mov w9, #CONN_READ_HEAD
    str w9, [x19, #CONN_STATE_OFF]
    str w20, [x19, #CONN_FD_OFF]
    str wzr, [x19, #CONN_FLAGS_OFF]
    str wzr, [x19, #CONN_RLEN_OFF]
    str wzr, [x19, #CONN_RPOS_OFF]
    str wzr, [x19, #CONN_HLEN_OFF]
    str wzr, [x19, #CONN_STATUS_OFF]
    mov w9, #-1
    str w9, [x19, #CONN_FILE_FD_OFF]
    str xzr, [x19, #CONN_FILE_OFF_OFF]
    str xzr, [x19, #CONN_FILE_REM_OFF]
    str wzr, [x19, #CONN_OUT_LEN_OFF]
    str wzr, [x19, #CONN_OUT_POS_OFF]
    str xzr, [x19, #CONN_WPTR_OFF]
    str xzr, [x19, #CONN_WLEN_OFF]
    str xzr, [x19, #CONN_WPOS_OFF]

    bl now_secs
    str x0, [x19, #CONN_LAST_ACT_OFF]

    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

/* =========================================================================
 * accept_storm() - drain the listen queue until EAGAIN
 * ========================================================================= */
accept_storm:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    str x21, [sp, #32]

    ldr x9, =listen_fd_global
    ldr x19, [x9]                   /* x19 = listen_fd */

as_loop:
    mov x0, x19
    mov x1, #0
    mov x2, #0
    ldr w3, =(SOCK_NONBLOCK|SOCK_CLOEXEC)
    mov x8, SYS_ACCEPT4
    svc #0

    cmp x0, #0
    blt as_err
    mov x20, x0                     /* x20 = client fd */

    bl conn_alloc
    cbz x0, as_full
    mov x21, x0                     /* x21 = conn */

    mov x0, x21
    mov x1, x20
    bl conn_init

    /* conn_by_fd[fd] = conn */
    ldr x9, =conn_by_fd
    str x21, [x9, x20, lsl #3]

    mov x0, x20
    mov w1, #EPOLLIN
    bl ep_add
    /* shadow the live mask so cf_rearm can detect divergence cheaply */
    mov w1, #EPOLLIN
    str w1, [x21, #CONN_MASK_OFF]
    b as_loop

as_full:
    /* Pool exhausted: drop this connection and stop accepting until a slot
     * frees up, otherwise epoll would spin on the listen fd forever. */
    mov x0, x20
    mov x8, SYS_CLOSE
    svc #0

    ldr x9, =accept_paused
    ldr w10, [x9]
    cbnz w10, as_out
    mov w10, #1
    str w10, [x9]
    mov x0, x19
    bl ep_del
    b as_out

as_err:
    /* EAGAIN/EWOULDBLOCK -> queue drained; EINTR -> retry; else give up. */
    cmn x0, #EAGAIN
    beq as_out
    cmn x0, #EINTR
    beq as_loop

as_out:
    ldr x21, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

/* =========================================================================
 * conn_close(x0 = conn) - close fd, release the slot, resume accepting
 * ========================================================================= */
conn_close:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    str x21, [sp, #32]

    mov x19, x0
    cbz x19, cc_out

    /* An aborted FILE_BODY still owns the open file descriptor. A borrowed
     * fd must be RETURNED (decrement), never closed; an openat fd (or a
     * non-cache-managed fd like CGI/Range) is native-closed. */
    ldr w9, [x19, #CONN_FILE_FD_OFF]
    cmn w9, #1
    beq cc_no_file
    ldr w10, [x19, #CONN_FLAGS_OFF]
    tst w10, #CONN_F_FD_CACHED
    beq cc_native_close
    tst w10, #CONN_F_FD_BORROWED
    bne cc_borrow_put
cc_native_close:
    mov w0, w9
    mov x8, SYS_CLOSE
    svc #0
    b cc_no_file
cc_borrow_put:
    ldr w0, [x19, #CONN_FDC_SLOT_OFF]
    bl fdc_put_slot
cc_no_file:
    /* fd handled above (returned, closed, or never set): drop the fd-cache
     * intent so it cannot leak into the next request on this conn. */
    ldr w9, [x19, #CONN_FLAGS_OFF]
    bic w9, w9, #(CONN_F_FD_CACHED|CONN_F_FD_BORROWED)
    str w9, [x19, #CONN_FLAGS_OFF]
    mov w9, #-1
    str w9, [x19, #CONN_FILE_FD_OFF]
    mov w9, #-1
    str w9, [x19, #CONN_FDC_SLOT_OFF]
cc_no_file_done:

    /* conn_by_fd[fd] = 0 */
    cmp w20, #0
    blt cc_free
    ldr x9, =65536
    cmp x20, x9
    bge cc_free
    ldr x9, =conn_by_fd
    str xzr, [x9, x20, lsl #3]

cc_free:
    str wzr, [x19, #CONN_STATE_OFF] /* CONN_FREE */
    mov w9, #-1
    str w9, [x19, #CONN_FD_OFF]

    /* A slot is available again: re-arm the listen fd if we paused it. */
    ldr x9, =accept_paused
    ldr w10, [x9]
    cbz w10, cc_out
    str wzr, [x9]
    ldr x9, =listen_fd_global
    ldr x0, [x9]
    ldr w1, =(EPOLLIN|EPOLLEXCLUSIVE)
    bl ep_add

cc_out:
    ldr x21, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

/* =========================================================================
 * conn_on_read(x0 = conn) - EPOLLIN: parse buffered requests, read more
 * conn_on_write(x0 = conn) - EPOLLOUT: resume a suspended response
 *
 * Both funnel into conn_run / conn_flush so pipelined requests are drained
 * from the user-space buffer: level-triggered epoll only re-reports bytes
 * still sitting in the kernel, never ones we already copied into read_buf.
 * ========================================================================= */
conn_on_read:
    b conn_run

conn_on_write:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    mov x19, x0

    bl conn_flush
    cbnz x0, cow_out                /* 1 = suspended, 2 = closed */

    /* Response finished on a keepalive connection: there may already be a
     * pipelined request sitting in read_buf. */
    mov x0, x19
    bl conn_run

cow_out:
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

/* -------------------------------------------------------------------------
 * conn_run(x0 = conn) - scan / serve / flush loop until the socket drains
 * ------------------------------------------------------------------------- */
conn_run:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    str x25, [sp, #64]

    mov x19, x0                     /* x19 = conn */
    mov x25, #CONN_READ_BUF_OFF
    add x25, x19, x25               /* x25 = read_buf base */

cr_scan:
    /* start = max(scan_cursor, rpos), limit = rlen - 4 (signed) */
    ldr w20, [x19, #CONN_RPOS_OFF]
    ldr w9,  [x19, #CONN_SCAN_OFF]
    cmp w9, w20
    csel w20, w9, w20, hi           /* x20 = scan start */
    ldr w21, [x19, #CONN_RLEN_OFF]  /* x21 = rlen */
    sub w22, w21, #4                /* w22 = last valid start index */
    sxtw x20, w20
    sxtw x22, w22

    /* Branchless SIMD terminator search.  Each 16-byte window yields two
     * nibble-packed masks: shrn #4 turns a 16b cmpeq result (0x00/0xFF per
     * byte) into 16 nibbles with nibble i = 0xF iff byte i matched, so bit
     * (4i) of the fmov'd mask is byte i's match.  cand_i = cr[i] & lf[i+1]
     * & cr[i+2] & lf[i+3] falls out of four shifts; the lowest set bit is
     * the first terminator in the window.  Offsets 13..15 are covered by
     * the next window (base advances by 13, so windows overlap), and the
     * limit guard rejects any candidate whose bytes would pass rlen.
     * Warning: window loads at base = limit read up to 12 bytes past the
     * slot's read_buf; conn_pool carries a 16-byte .bss guard for this. */
cr_simd_loop:
    cmp x20, x22
    bgt cr_need_more
    add x0, x25, x20
    ld1 {v0.16b}, [x0]            /* window: bytes x20 .. x20+15 */

    movi v1.16b, #13              /* '\r' */
    cmeq v2.16b, v0.16b, v1.16b
    shrn v2.8b, v2.8h, #4
    movi v3.16b, #10              /* '\n' */
    cmeq v4.16b, v0.16b, v3.16b
    shrn v4.8b, v4.8h, #4

    fmov x1, d2                   /* m_cr: bit 4i = byte i == '\r' */
    fmov x2, d4                   /* m_lf: bit 4i = byte i == '\n' */

    lsr x3, x2, #4                /* lf[i+1] */
    lsr x5, x1, #8                /* cr[i+2] */
    and x0, x1, x3
    lsr x3, x2, #12               /* lf[i+3] */
    and x0, x0, x5
    and x0, x0, x3
    mov x5, #0xFFFFFFFFFFFFF      /* offsets 0..12 (13+ via overlap) */
    and x0, x0, x5
    cbz x0, cr_simd_adv

    /* first candidate: rbit moves the lowest set bit to bit 63, so
     * clz = 4*offset; prevents a body starting "\r\n" from being eaten */
    rbit x5, x0
    clz x5, x5
    lsr x5, x5, #2
    add x5, x20, x5               /* absolute index of leading '\r' */
    cmp x5, x22
    bgt cr_simd_adv               /* only stale data past rlen could match */
    mov x20, x5
    b cr_found
cr_simd_adv:
    add x20, x20, #13             /* overlapping windows cover straddles */
    b cr_simd_loop

cr_need_more:
    /* No terminator yet. Remember how far we scanned, backing off 3 bytes so
     * a "\r\n\r" / "\n" split across two reads is still matched. */
    ldr w9, [x19, #CONN_RPOS_OFF]
    sub w10, w21, #3
    cmp w10, w9
    csel w10, w10, w9, gt
    str w10, [x19, #CONN_SCAN_OFF]
    b cr_read

cr_found:
    /* hlen = (index + 4) - rpos */
    ldr w9, [x19, #CONN_RPOS_OFF]
    add w10, w20, #4
    sub w10, w10, w9
    mov w11, #REQ_BUF_MAX
    cmp w10, w11
    bgt cr_close                    /* request header too large */
    str w10, [x19, #CONN_HLEN_OFF]

    /* Copy every buffered byte from rpos (not just the header): the slow-path
     * child can no longer read the request body off the socket, it only sees
     * req_buffer.  n = min(rlen - rpos, REQ_BUF_MAX) */
    sub w22, w21, w9                /* w22 = available */
    mov w10, #REQ_BUF_MAX
    cmp w22, w10
    csel w22, w22, w10, ls          /* x22 = copy length */

    add x0, x25, w9, uxtw           /* src = read_buf + rpos */
    ldr x1, =req_buffer
    mov x2, #0
cr_copy:
    cmp x2, x22
    bge cr_copy_done
    ldrb w9, [x0, x2]
    strb w9, [x1, x2]
    add x2, x2, #1
    b cr_copy
cr_copy_done:
    strb wzr, [x1, x2]              /* NUL terminate */

    /* Publish the conn pointer for http.s (hc_close_final / fork points). */
    ldr x9, =cur_conn
    str x19, [x9]

    mov x0, x19
    bl conn_serve

    cmp x0, #3
    beq cr_out                      /* forked: slot already released */
    cmp x0, #2
    beq cr_out                      /* output already suspended by http.s */
    cmp x0, #1
    bne cr_flush

    /* Return code 1 = close after the response is on the wire.  Clearing the
     * keepalive bit is all conn_flush needs: finish closes when it is unset. */
    ldr w9, [x19, #CONN_FLAGS_OFF]
    and w9, w9, #~CONN_F_KEEPALIVE
    str w9, [x19, #CONN_FLAGS_OFF]

cr_flush:
    mov x0, x19
    bl conn_flush
    cbnz x0, cr_out                 /* suspended or closed */
    b cr_scan                       /* keepalive: drain pipelined requests */

cr_read:
    ldr w21, [x19, #CONN_RLEN_OFF]
    ldr x9, =CONN_READ_CAP
    cmp x21, x9
    bge cr_close                    /* buffer full without a complete header */

    mov x0, x19
    ldr w0, [x19, #CONN_FD_OFF]
    add x1, x25, w21, uxtw
    sub x2, x9, x21
    mov x8, SYS_READ
    svc #0

    cmp x0, #0
    beq cr_close                    /* peer closed */
    blt cr_read_err

    add w21, w21, w0
    str w21, [x19, #CONN_RLEN_OFF]
    bl now_secs
    str x0, [x19, #CONN_LAST_ACT_OFF]
    b cr_scan

cr_read_err:
    cmn x0, #EAGAIN
    beq cr_out                      /* drained; wait for the next EPOLLIN */
    cmn x0, #EINTR
    beq cr_read

cr_close:
    mov x0, x19
    bl conn_close

cr_out:
    ldr x25, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #80
    ret

/* -------------------------------------------------------------------------
 * conn_flush(x0 = conn) -> x0 = 0 finished (connection reusable)
 *                               1 suspended (EPOLLOUT armed)
 *                               2 connection closed
 * Drives out_buf, then the body (sendfile or a flat pointer), then finish.
 * ------------------------------------------------------------------------- */
conn_flush:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    str x23, [sp, #48]

    mov x19, x0
    ldr w20, [x19, #CONN_FD_OFF]

    /* A sink overflow means the response is already truncated garbage. */
    ldr w9, [x19, #CONN_FLAGS_OFF]
    tst w9, #CONN_F_ABORT
    bne cf_close

cf_head:
    ldr w21, [x19, #CONN_OUT_LEN_OFF]
    ldr w22, [x19, #CONN_OUT_POS_OFF]
    cmp w22, w21
    bge cf_body

    mov x0, x20
    mov x9, #CONN_OUT_BUF_OFF
    add x1, x19, x9
    add x1, x1, w22, uxtw
    sub w2, w21, w22
    uxtw x2, w2
    mov x8, SYS_WRITE
    svc #0

    cmp x0, #0
    ble cf_head_err
    add w22, w22, w0
    str w22, [x19, #CONN_OUT_POS_OFF]
    b cf_head

cf_head_err:
    cmn x0, #EINTR
    beq cf_head
    cmn x0, #EAGAIN
    bne cf_close
    mov w9, #CONN_WRITE_HEAD
    str w9, [x19, #CONN_STATE_OFF]
    b cf_suspend

cf_body:
    ldr w9, [x19, #CONN_FLAGS_OFF]
    tst w9, #CONN_F_FILE_BODY
/* ---- sendfile body ---- */
cf_file:
    ldr x21, [x19, #CONN_FILE_REM_OFF]
    cmp x21, #0
    ble cf_finish

    ldr w9, [x19, #CONN_FILE_FD_OFF]
    cmn w9, #1
    beq cf_finish

    /* Cap the per-wakeup count at SF_CHUNK so a large transfer yields to the
     * event loop after one chunk instead of draining the whole socket buffer
     * (and starving other conns). Smaller of (remaining, SF_CHUNK). */
    mov x3, x21                     /* count = remaining */
    mov x4, #SF_CHUNK
    cmp x21, x4
    bge cf_use_cap
    mov x3, x21
    b cf_send
cf_use_cap:
    mov x3, x4
cf_send:
    mov x0, x20                     /* out fd */
    mov w1, w9                      /* in fd  */
    mov x9, #CONN_FILE_OFF_OFF
    add x2, x19, x9                 /* &file_off, updated by the kernel */
    mov x8, SYS_SENDFILE
    svc #0

    cmp x0, #0
    ble cf_file_err
    sub x21, x21, x0
    str x21, [x19, #CONN_FILE_REM_OFF]
    b cf_file

cf_file_err:
    beq cf_finish                   /* 0 = EOF, nothing left to send */
    cmn x0, #EINTR
    beq cf_file
    cmn x0, #EAGAIN
    bne cf_close
    mov w9, #CONN_WRITE_BODY
    str w9, [x19, #CONN_STATE_OFF]
    b cf_suspend

/* ---- flat pointer body (directory listing) ---- */
cf_ptr:
    ldr x21, [x19, #CONN_WLEN_OFF]
    ldr x22, [x19, #CONN_WPOS_OFF]
    cmp x22, x21
    bge cf_finish

    ldr x23, [x19, #CONN_WPTR_OFF]
    cbz x23, cf_finish

    mov x0, x20
    add x1, x23, x22
    sub x2, x21, x22
    mov x8, SYS_WRITE
    svc #0

    cmp x0, #0
    ble cf_ptr_err
    add x22, x22, x0
    str x22, [x19, #CONN_WPOS_OFF]
    b cf_ptr

cf_ptr_err:
    cmn x0, #EINTR
    beq cf_ptr
    cmn x0, #EAGAIN
    bne cf_close
    mov w9, #CONN_WRITE_BODY
    str w9, [x19, #CONN_STATE_OFF]
    b cf_suspend

/* ---- arm EPOLLOUT and report "suspended" ----
 * Deliberately EPOLLOUT *only*, not EPOLLIN|EPOLLOUT as sketched in the
 * contract: the event loop dispatches on conn->state, so a suspended
 * connection ignores EPOLLIN.  Leaving EPOLLIN armed would make a
 * level-triggered readable socket (pipelined request, or a latched FIN)
 * wake the loop endlessly while we skip the event - a 100% CPU spin.
 * EPOLLERR/EPOLLHUP are reported regardless of the mask, and cf_rearm
 * restores EPOLLIN once the response completes. */
cf_suspend:
    ldr w9, [x19, #CONN_FLAGS_OFF]
    orr w9, w9, #CONN_F_OUT_ARMED
    str w9, [x19, #CONN_FLAGS_OFF]
    mov x0, x20
    mov w1, #EPOLLOUT
    bl ep_mod
    /* shadow the live mask so cf_rearm can detect divergence cheaply */
    mov w1, #EPOLLOUT
    str w1, [x19, #CONN_MASK_OFF]
    mov x0, #1                     /* suspended: resume on EPOLLOUT */
    b cf_out
cf_finish:
    /* fd-cache dispatch.
     *   - BORROWED  -> the conn holds a borrow (fdc_get hit, or an insert
     *     with borrow-back at the event-loop handoff): return it via
     *     fdc_put_slot (key-free). The cache keeps the fd.
     *   - FD_CACHED set, not borrowed -> openat-intent that was never
     *     inserted (or an insert the conn no longer uses): native close.
     *   - FD_CACHED clear -> non-cache fd: native close. */
    ldr w9, [x19, #CONN_FLAGS_OFF]
    tst w9, #CONN_F_FD_CACHED
    beq cf_close_file
    tst w9, #CONN_F_FD_BORROWED
    bne cf_borrow_return
    b cf_close_file
cf_borrow_return:
    ldr w0, [x19, #CONN_FILE_FD_OFF]
    cmn w0, #1
    beq cf_clear_fdc
    ldr w0, [x19, #CONN_FDC_SLOT_OFF]
    bl fdc_put_slot
cf_clear_fdc:
    ldr w9, [x19, #CONN_FLAGS_OFF]
    bic w9, w9, #(CONN_F_FD_CACHED|CONN_F_FD_BORROWED)
    str w9, [x19, #CONN_FLAGS_OFF]
    mov w9, #-1
    str w9, [x19, #CONN_FILE_FD_OFF]
    mov w9, #-1
    str w9, [x19, #CONN_FDC_SLOT_OFF]
    b cf_fin_nofile
cf_close_file:
    ldr w9, [x19, #CONN_FILE_FD_OFF]
    cmn w9, #1
    beq cf_fin_nofile
    mov w0, w9
    mov x8, SYS_CLOSE
    svc #0
    mov w9, #-1
    str w9, [x19, #CONN_FILE_FD_OFF]

cf_fin_nofile:
    ldr w9, [x19, #CONN_FLAGS_OFF]
    tst w9, #CONN_F_KEEPALIVE
    beq cf_close

    /* Consume the request we just answered. */
    ldr w21, [x19, #CONN_RPOS_OFF]
    ldr w10, [x19, #CONN_HLEN_OFF]
    add w21, w21, w10
    ldr w22, [x19, #CONN_RLEN_OFF]
    cmp w21, w22
    bcc cf_compact                  /* pipelined bytes remain */

    /* Nothing buffered: start clean and wait for the next request. */
    str wzr, [x19, #CONN_RLEN_OFF]
    str wzr, [x19, #CONN_RPOS_OFF]
    str wzr, [x19, #CONN_SCAN_OFF]
    b cf_rearm

cf_compact:
    /* memmove(read_buf, read_buf + rpos, rlen - rpos) */
    mov x9, #CONN_READ_BUF_OFF
    add x0, x19, x9                 /* dst = read_buf */
    add x1, x0, w21, uxtw           /* src = read_buf + rpos */
    sub w23, w22, w21               /* remaining */
    uxtw x23, w23
    mov x2, #0
cf_move:
    cmp x2, x23
    bge cf_move_done
    ldrb w9, [x1, x2]
    strb w9, [x0, x2]
    add x2, x2, #1
    b cf_move
cf_move_done:
    str w23, [x19, #CONN_RLEN_OFF]
    str wzr, [x19, #CONN_RPOS_OFF]
    /* The scan cursor is an absolute read_buf offset; rebase it. */
    ldr w9, [x19, #CONN_SCAN_OFF]
    subs w9, w9, w21
    csel w9, wzr, w9, lt
    str w9, [x19, #CONN_SCAN_OFF]

cf_rearm:
    /* The conn is settling to READ_HEAD: its mask MUST be EPOLLIN-only.  A
     * suspended write armed EPOLLOUT; if the mask was never restored, a
     * READ_HEAD conn with EPOLLOUT armed refires forever (100% CPU spin).
     * Steady state keeps EPOLLIN in the shadow, so skip the ep_mod syscall;
     * only a divergent conn is repaired.  This is on the keep-alive hot path. */
    ldr w9, [x19, #CONN_MASK_OFF]
    cmp w9, #EPOLLIN
    beq cf_reset
    mov x0, x20
    mov w1, #EPOLLIN
    bl ep_mod

cf_reset:
    mov w9, #CONN_READ_HEAD
    str w9, [x19, #CONN_STATE_OFF]
    str wzr, [x19, #CONN_HLEN_OFF]
    str wzr, [x19, #CONN_FLAGS_OFF]     /* clears KEEPALIVE for the next one */
    str wzr, [x19, #CONN_OUT_LEN_OFF]
    str wzr, [x19, #CONN_OUT_POS_OFF]
    str wzr, [x19, #CONN_STATUS_OFF]
    str xzr, [x19, #CONN_FILE_OFF_OFF]
    str xzr, [x19, #CONN_FILE_REM_OFF]
    str xzr, [x19, #CONN_WPTR_OFF]
    str xzr, [x19, #CONN_WLEN_OFF]
    str xzr, [x19, #CONN_WPOS_OFF]
    mov w9, #-1
    str w9, [x19, #CONN_FDC_SLOT_OFF]    /* fd-cache borrow slot: none */
    bl now_secs
    str x0, [x19, #CONN_LAST_ACT_OFF]
    mov x0, #0
    b cf_out

cf_close:
    mov x0, x19
    bl conn_close
    mov x0, #2

cf_out:
    ldr x23, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

/* =========================================================================
 * conn_sink_write(x0 = fd, x1 = src, x2 = len)
 *
 * Drop-in replacement for the ~91 `mov x8, SYS_WRITE; svc #0` sequences that
 * target the client socket.  Those call sites keep live values in x1-x18
 * across the write (add_header reuses x12, max-age uses x9, the stats counter
 * uses x10), so this routine must clobber NOTHING but x0.
 *
 * Hard rules, do not relax:
 *   - only x19-x24 are used for work, and they are saved/restored;
 *   - x1, x2 and x8 are saved/restored too (the syscalls below need them);
 *   - no `bl` to anything, and no x9-x18 scratch either: the inline memcpy
 *     borrows x19/x22 once they are dead, and globals go through `ldr =sym`
 *     literal pool loads into callee-saved registers.
 *
 * Returns x0 = len so that call sites doing `cmp x0, #0; ble ...` still see a
 * fully-successful write.
 * ========================================================================= */
conn_sink_write:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x1,  x2,  [sp, #64]         /* caller's x1/x2 */
    str x8,  [sp, #80]              /* caller's x8 (x30 lives at [sp,#8]) */

    mov x19, x0                     /* x19 = fd  */
    mov x20, x1                     /* x20 = src */
    mov x21, x2                     /* x21 = len */

    cmp x21, #0
    ble csw_ret

    /* Slow-path child: the socket is blocking again, write straight through. */
    ldr x22, =slow_child_mode
    ldr w22, [x22]
    cbnz w22, csw_direct

    /* Fast path: append to conn->out_buf. */
    cmp w19, #0
    blt csw_direct
    ldr x22, =65536
    cmp x19, x22
    bge csw_direct
    ldr x22, =conn_by_fd
    ldr x22, [x22, x19, lsl #3]     /* x22 = conn */
    cbz x22, csw_direct

    ldr w23, [x22, #CONN_OUT_LEN_OFF]
    add x24, x23, x21
    ldr x19, =CONN_OUT_CAP          /* fd is dead from here on */
    cmp x24, x19
    bls csw_append

    /* Header buffer overflow: the response can no longer be well-formed, so
     * mark it and let the flush stage drop the connection. */
    ldr w23, [x22, #CONN_FLAGS_OFF]
    orr w23, w23, #CONN_F_ABORT
    str w23, [x22, #CONN_FLAGS_OFF]
    b csw_ret

csw_append:
    add x19, x22, #CONN_OUT_BUF_OFF /* x19 = out_buf base */
    add x23, x19, w23, uxtw         /* x23 = dst = out_buf + out_len */
    str w24, [x22, #CONN_OUT_LEN_OFF]

    /* inline memcpy(x23, x20, x21): 16B stride, then 8/4/2/1 tail.
     * x19 (fd) and x22 (conn) are both dead now, so they serve as the load
     * temporaries - x9-x18 must stay exactly as the caller left them. */
    mov x24, x21                    /* x24 = remaining */
csw_cp16:
    cmp x24, #16
    blo csw_cp8
    ldp x19, x22, [x20], #16
    stp x19, x22, [x23], #16
    sub x24, x24, #16
    b csw_cp16
csw_cp8:
    tbz x24, #3, csw_cp4
    ldr x19, [x20], #8
    str x19, [x23], #8
csw_cp4:
    tbz x24, #2, csw_cp2
    ldr w19, [x20], #4
    str w19, [x23], #4
csw_cp2:
    tbz x24, #1, csw_cp1
    ldrh w19, [x20], #2
    strh w19, [x23], #2
csw_cp1:
    tbz x24, #0, csw_ret
    ldrb w19, [x20]
    strb w19, [x23]
    b csw_ret

/* ---- blocking write loop (slow-path child, or no conn for this fd) ---- */
csw_direct:
    ldr x22, =slow_write_failed
    ldr w22, [x22]
    cbnz w22, csw_ret               /* socket already gone, stay quiet */

    mov x22, #0                     /* x22 = written */
csw_dloop:
    cmp x22, x21
    bhs csw_ret

    mov x0, x19
    add x1, x20, x22
    sub x2, x21, x22
    mov x8, SYS_WRITE
    svc #0

    cmp x0, #0
    ble csw_derr
    add x22, x22, x0
    b csw_dloop

csw_derr:
    cmn x0, #EINTR
    beq csw_dloop
    /* EPIPE / ECONNRESET / EAGAIN on a blocking fd: give up for good. */
    ldr x23, =slow_write_failed
    mov w24, #1
    str w24, [x23]

csw_ret:
    mov x0, x21                     /* report a full write */
    ldr x8,  [sp, #80]             /* x8 saved at [sp,#80] (96B frame) */
    ldp x1,  x2,  [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

/* =========================================================================
 * fork_slow_child(x0 = conn, x1 = child_continue_addr)
 *
 *   child  -> branches to x1 with x0 = client_fd, running the original
 *             blocking code path (proxy / CGI / dynamic gzip) in place
 *   parent -> x0 = 3, connection closed and slot released
 *   error  -> x0 = -1, connection untouched (caller emits 429 / 502)
 *
 * aarch64 has no fork(2) - syscall 107 is timer_create - so this uses
 * clone(SIGCHLD, stack=0) like the rest of the tree (cgi.s, main.s).
 * ========================================================================= */
fork_slow_child:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    str x1, [sp, #64]               /* continuation address */

    mov x19, x0                     /* x19 = conn */
    ldr w20, [x19, #CONN_FD_OFF]    /* x20 = client fd */

    /* Reserve a slot under CONN_SLOW_MAX.  A signal can clear the exclusive
     * monitor between ldxr and stxr, so the store must be retried. */
    ldr x21, =slow_children
fsc_try:
    ldxr w22, [x21]
    cmp w22, #CONN_SLOW_MAX
    bge fsc_busy
    add w22, w22, #1
    stxr w23, w22, [x21]
    cbnz w23, fsc_try

    mov x24, #0                     /* retry counter for EINTR */

fsc_clone:
    mov x0, #SIGCHLD_FLAG
    mov x1, #0                      /* stack = 0: share/copy like fork() */
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov x8, SYS_CLONE
    svc #0

    cmp x0, #0
    beq fsc_child
    blt fsc_fail

/* ---- parent ---- */
    /* conn_close also releases the pool slot and, if the pool had filled up,
     * re-arms the listen fd; open-coding it here would deadlock accepting. */
    mov x0, x19
    bl conn_close
    mov x0, #3
    b fsc_out

fsc_fail:
    cmn x0, #EINTR
    bne fsc_undo
    cmp x24, #0
    bne fsc_undo
    mov x24, #1
    b fsc_clone

fsc_undo:
    ldr x21, =slow_children
fsc_undo_try:
    ldxr w22, [x21]
    subs w22, w22, #1
    csel w22, wzr, w22, lt
    stxr w23, w22, [x21]
    cbnz w23, fsc_undo_try
    mov x0, #-1
    b fsc_out

fsc_busy:
    clrex
    mov x0, #-1
    b fsc_out

/* ---- child: become a plain blocking server for this one connection ---- */
fsc_child:
    /* Drop the inherited event machinery; the parent keeps serving. */
    ldr x0, =epoll_fd_global
    ldr x0, [x0]
    mov x8, SYS_CLOSE
    svc #0
    ldr x0, =listen_fd_global
    ldr x0, [x0]
    mov x8, SYS_CLOSE
    svc #0

    /* Clear O_NONBLOCK first: the original code path expects blocking
     * semantics, and the flush below must not lose bytes to EAGAIN. */
    mov x0, x20
    mov x1, #F_GETFL
    mov x2, #0
    mov x8, SYS_FCNTL
    svc #0
    cmp x0, #0
    blt fsc_nb_done
    bic x2, x0, #O_NONBLOCK
    mov x0, x20
    mov x1, #F_SETFL
    mov x8, SYS_FCNTL
    svc #0

fsc_nb_done:
    /* Anything the processing segment already sinked into out_buf (response
     * headers, proxy preamble) must reach the socket before the blocking
     * code starts appending to it.  The fd blocks now, so a short write can
     * only mean a real error. */
    ldr w21, [x19, #CONN_OUT_LEN_OFF]
    ldr w22, [x19, #CONN_OUT_POS_OFF]
fsc_flush:
    cmp w22, w21
    bhs fsc_flushed
    mov x0, x20
    ldr x9, =CONN_OUT_BUF_OFF
    add x1, x19, x9
    add x1, x1, w22, uxtw
    sub w2, w21, w22
    uxtw x2, w2
    mov x8, SYS_WRITE
    svc #0
    cmp x0, #0
    ble fsc_flush_err
    add w22, w22, w0
    b fsc_flush
fsc_flush_err:
    cmn x0, #EINTR
    beq fsc_flush
    b fsc_flushed                   /* socket is gone; the child will notice */

fsc_flushed:
    str w22, [x19, #CONN_OUT_POS_OFF]

    /* Route every later sink call straight to the socket. */
    ldr x9, =slow_child_mode
    mov w10, #1
    str w10, [x9]
    ldr x9, =slow_write_failed
    str wzr, [x9]

    /* This child may itself fork (CGI, gzip) and must reap normally. */
    sub sp, sp, #32
    str xzr, [sp]                   /* SIG_DFL */
    str xzr, [sp, #8]               /* flags   */
    str xzr, [sp, #16]              /* mask    */
    mov x0, #SIGCHLD
    mov x1, sp
    mov x2, #0
    mov x3, #8
    mov x8, SYS_RT_SIGACTION
    svc #0
    add sp, sp, #32

    /* Hand control back to the caller's blocking code path. */
    ldr x9, [sp, #64]               /* continuation address */
    mov x0, x20                     /* x0 = client fd */
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #80
    br x9

fsc_out:
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #80
    ret
