/* src/network.s - Network Setup */

.include "src/defs.s"

.global server_init
.global accept_loop
.global connect_to_upstream

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
    
    /* 2. Setsockopt */
    mov x0, x19
    mov x1, SOL_SOCKET
    mov x2, SO_REUSEADDR
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
    mov x20, #1             /* x20 = worker count (1 worker for stability) */

spawn_workers:
    cmp x20, #0
    beq monitor_children

    /* Fork Worker */
    mov x0, SIGCHLD_FLAG
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov x8, SYS_CLONE
    svc #0
    
    cmp x0, #0
    beq worker_routine
    
    /* Parent continues spawning */
    sub x20, x20, #1
    b spawn_workers

monitor_children:
    /* Parent Process: Monitor and Respawn Workers */
    
    /* wait4(-1, NULL, 0, NULL) -> pid */
    mov x0, #-1
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x8, SYS_WAIT4
    svc #0
    
    cmp x0, #0
    blt monitor_children
    
    /* A child died. Respawn it! */
    mov x20, #1
    b spawn_workers

worker_routine:
    /* Check access_log_path */
    ldr x0, =access_log_path
    ldrb w1, [x0]
    cbz w1, epoll_init
    
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
    blt epoll_init
    
    /* Store in log_fd */
    ldr x1, =log_fd
    str w0, [x1]

epoll_init:
    /* 1. Create Epoll Instance */
    mov x0, #0
    mov x8, SYS_EPOLL_CREATE1
    svc #0
    cmp x0, #0
    blt worker_exit
    mov x21, x0             /* x21 = epoll_fd */
    
    /* 2. Add Listen Socket to Epoll with EPOLLEXCLUSIVE */
    sub sp, sp, #16
    ldr w0, =EPOLLEXCLUSIVE
    orr w0, w0, #EPOLLIN
    str w0, [sp]
    str x19, [sp, #8]
    
    mov x0, x21
    mov x1, EPOLL_CTL_ADD
    mov x2, x19
    mov x3, sp
    mov x8, SYS_EPOLL_CTL
    svc #0
    
    add sp, sp, #16
    
epoll_loop:
    /* 3. Epoll Wait */
    mov x0, x21
    ldr x1, =epoll_events
    mov x2, #32
    mov x3, #-1             /* timeout = infinite */
    mov x4, #0
    mov x5, #0
    mov x8, SYS_EPOLL_WAIT
    svc #0
    
    cmp x0, #0
    beq epoll_loop          /* No events, retry */
    cmp x0, #-EINTR
    beq epoll_loop          /* EINTR, retry */
    
    mov x22, x0             /* num_events */
    ldr x23, =epoll_events
    
process_events:
    cmp x22, #0
    beq epoll_loop
    
    /* Load event data.fd (offset 8) */
    ldr x24, [x23, #8]
    
    /* Check if it is listen_fd */
    cmp x24, x19
    beq do_accept
    
    /* Otherwise it is client_fd -> Handle Request */
    mov x0, x24
    bl handle_client
    b event_done

do_accept:
    /* Accept Loop using accept4 */
    sub sp, sp, #32
    mov w2, #16
    str w2, [sp]            /* addrlen */
    
    mov x0, x19             /* listen_fd */
    add x1, sp, #16         /* sockaddr */
    mov x2, sp              /* addrlen ptr */
    
    /* Enable CloExec on new socket (Blocking I/O + Timeouts) */
    ldr x3, =SOCK_CLOEXEC
    /* ldr x4, =SOCK_NONBLOCK */
    /* orr x3, x3, x4 */     /* Removed Non-Blocking */
    
    mov x8, SYS_ACCEPT4
    svc #0
    
    cmp x0, #0
    blt accept_fail

    mov x25, x0             /* client_fd */

    /* Set SO_RCVTIMEO (30s) */
    mov x0, x25
    mov x1, SOL_SOCKET
    mov x2, SO_RCVTIMEO
    ldr x3, =timeout_tv
    mov x4, #16             /* sizeof(struct timeval) */
    mov x8, SYS_SETSOCKOPT
    svc #0
    
    /* Set SO_SNDTIMEO (30s) */
    mov x0, x25
    mov x1, SOL_SOCKET
    mov x2, SO_SNDTIMEO
    ldr x3, =timeout_tv
    mov x4, #16
    mov x8, SYS_SETSOCKOPT
    svc #0

    /* Capture IP */
    /*
    ldr w0, [sp, #20]
    ldr x1, =client_ip_str
    bl ip_to_str
    */

    add sp, sp, #32         /* Restore stack */

    /* Add Client to Epoll */
    sub sp, sp, #16
    mov w0, EPOLLIN
    str w0, [sp]
    str x25, [sp, #8]       /* data.fd = client_fd */

    mov x0, x21             /* epfd */
    mov x1, EPOLL_CTL_ADD
    mov x2, x25             /* fd */
    mov x3, sp              /* event ptr */
    mov x8, SYS_EPOLL_CTL
    svc #0

    add sp, sp, #16
    b event_done

accept_fail:
    add sp, sp, #32
    /* Fallthrough to event_done */

event_done:
    add x23, x23, #16       /* Next event */
    sub x22, x22, #1
    b process_events

worker_exit:
    mov x0, #1
    mov x8, SYS_EXIT
    svc #0

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
