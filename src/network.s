/* src/network.s - Network Setup */
/* Event-driven worker: accept_loop -> conn.s worker_event_loop */

.include "src/defs.s"

.global server_init
.global accept_loop
.global connect_to_upstream

.extern worker_event_loop

.text

/* server_init() -> listen_fd */
server_init:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!

    /* 1. Socket */
    mov x0, AF_INET
    mov x1, SOCK_STREAM
    mov x2, #0
    mov x8, SYS_SOCKET
    svc #0
    mov x19, x0             /* x19 = listen_fd */
    
    /* 2. Setsockopt SO_REUSEADDR */
    mov x0, x19
    mov x1, SOL_SOCKET
    mov x2, SO_REUSEADDR
    ldr x3, =optval
    mov x4, #4
    mov x8, SYS_SETSOCKOPT
    svc #0

    /* 2.5 Setsockopt SO_REUSEPORT (for multi-worker) */
    mov x0, x19
    mov x1, SOL_SOCKET
    mov x2, #15              /* SO_REUSEPORT = 15 */
    ldr x3, =optval
    mov x4, #4
    mov x8, SYS_SETSOCKOPT
    svc #0
    
    /* 3. Bind */
    ldr x1, =sockaddr
    ldr x2, =server_port
    ldrh w2, [x2]
    strh w2, [x1, #2]       /* Set port in sockaddr */
    
    mov x0, x19
    ldr x1, =sockaddr
    mov x2, #16
    mov x8, SYS_BIND
    svc #0
    
    cmp x0, #0
    blt bind_fail
    
    /* 3.5 TCP_DEFER_ACCEPT */
    mov x0, x19
    mov x1, IPPROTO_TCP
    mov x2, TCP_DEFER_ACCEPT
    ldr x3, =optval
    mov x4, #4
    mov x8, SYS_SETSOCKOPT
    svc #0
    
    /* 3.6 Ignore SIGPIPE */
    bl ignore_sigpipe

    /* 4. Listen */
    mov x0, x19
    mov x1, #4096           /* Max backlog */
    mov x8, SYS_LISTEN
    svc #0

    /* 5. Set Non-Blocking (Removed for stability check) */
    /* mov x0, x19 */
    /* bl set_nonblocking */
    
    mov x0, x19             /* Return listen_fd */
    
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

bind_fail:
    mov x0, STDOUT
    ldr x1, =msg_bind_fail
    ldr x2, =len_bind_fail
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, #1
    mov x8, SYS_EXIT
    svc #0

/* accept_loop(listen_fd) */
accept_loop:
    mov x19, x0             /* x19 = listen_fd */
    /* Thin shim: the worker body lives in worker_routine below */
    b worker_routine

worker_routine:
    /* Worker process starts here after fork() */
    /* sp is already set to the private stack top by clone() */

    /* Die if the master dies (PR_SET_PDEATHSIG=SIGKILL). An orphaned worker
     * still holding the SO_REUSEPORT listen socket would silently steal
     * connections from the next instance started on the same port. */
    mov x0, #PR_SET_PDEATHSIG  /* option */
    mov x1, #SIGKILL           /* signal */
    mov x8, SYS_PRCTL
    svc #0
    /* Master could have died in the window between clone() and prctl(). */
    mov x8, SYS_GETPPID
    svc #0
    cmp x0, #1                 /* ppid == init => master already gone */
    bne 1f
    mov x0, #0
    mov x8, SYS_EXIT
    svc #0
1:

    /* Set up stack frame */
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    /* Check access_log_path */
    ldr x0, =access_log_path
    ldrb w1, [x0]
    cbz w1, wr_run

    /* Open Log File */
    mov x0, AT_FDCWD
    ldr x1, =access_log_path
    ldr x2, =O_WRONLY
    ldr x3, =O_CREAT
    orr x2, x2, x3
    ldr x3, =O_APPEND
    orr x2, x2, x3
    mov x3, #420            /* 0644 */
    mov x8, SYS_OPENAT
    svc #0

    cmp x0, #0
    blt wr_run

    /* Store in log_fd */
    ldr x1, =log_fd
    str w0, [x1]

wr_run:
    /* Hand off to the event-driven loop in conn.s (never returns) */
    mov x0, x19             /* x0 = listen_fd */
    b worker_event_loop

/* connect_to_upstream() -> upstream_fd or -1 */
connect_to_upstream:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    str x19, [sp, #16]
    
    /* Create Socket */
    mov x0, AF_INET
    mov x1, SOCK_STREAM
    mov x2, #0
    mov x8, SYS_SOCKET
    svc #0
    cmp x0, #0
    blt ctu_fail
    mov x19, x0     /* x19 = fd */
    
    /* Set Timeouts */
    mov x0, x19
    mov x1, SOL_SOCKET
    mov x2, SO_RCVTIMEO
    ldr x3, =timeout_tv
    mov x4, #16
    mov x8, SYS_SETSOCKOPT
    svc #0
    
    mov x0, x19
    mov x1, SOL_SOCKET
    mov x2, SO_SNDTIMEO
    ldr x3, =timeout_tv
    mov x4, #16
    mov x8, SYS_SETSOCKOPT
    svc #0
    
    /* Setup sockaddr */
    ldr x1, =upstream_addr
    ldr x2, =upstream_ip
    ldr w2, [x2]
    str w2, [x1, #4]  /* IP */
    
    ldr x2, =upstream_port
    ldrh w2, [x2]
    strh w2, [x1, #2] /* Port */
    
    /* Connect */
    mov x0, x19
    ldr x1, =upstream_addr
    mov x2, #16
    mov x8, SYS_CONNECT
    svc #0
    
    cmp x0, #0
    bne ctu_close_fail
    
    mov x0, x19
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

ctu_close_fail:
    mov x0, x19
    mov x8, SYS_CLOSE
    svc #0
ctu_fail:
    mov x0, #-1
    ldr x19, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

/* ignore_sigpipe() */
ignore_sigpipe:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    
    /* struct sigaction setup */
    mov x0, SIG_IGN
    str x0, [sp, #16]       /* sa_handler */
    str xzr, [sp, #24]      /* flags / restorer / mask */
    
    /* rt_sigaction(SIGPIPE, &act, NULL, 8) */
    mov x0, SIGPIPE
    add x1, sp, #16         /* &act */
    mov x2, #0              /* NULL */
    mov x3, #8              /* sigsetsize */
    mov x8, SYS_RT_SIGACTION
    svc #0
    
    ldp x29, x30, [sp], #32
    ret
