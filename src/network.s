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
    
    /* 3.5 TCP_DEFER_ACCEPT */
    mov x0, x19
    mov x1, IPPROTO_TCP
    mov x2, TCP_DEFER_ACCEPT
    ldr x3, =optval
    mov x4, #4
    mov x8, SYS_SETSOCKOPT
    svc #0
    
    /* 4. Listen */
    mov x0, x19
    mov x1, #4096           /* Max backlog */
    mov x8, SYS_LISTEN
    svc #0
    
    mov x0, x19             /* Return listen_fd */
    
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

/* accept_loop(listen_fd) */
accept_loop:
    mov x19, x0             /* x19 = listen_fd */
    
    /* PREFORK CONFIGURATION */
    mov x20, #64            /* Number of workers */
    
spawn_workers:
    cmp x20, #0
    beq monitor_children    /* All workers spawned, parent waits */
    
    /* Fork Worker */
    mov x0, SIGCHLD_FLAG
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov x8, SYS_CLONE
    svc #0
    
    cmp x0, #0
    beq worker_routine      /* Child jumps to work */
    
    /* Parent continues spawning */
    sub x20, x20, #1
    b spawn_workers

monitor_children:
    /* Parent Process: Monitor and Respawn Workers */
    
    /* wait4(-1, NULL, 0, NULL) -> pid */
    mov x0, #-1             /* -1 = wait for any child */
    mov x1, #0              /* status = NULL */
    mov x2, #0              /* options = 0 */
    mov x3, #0              /* rusage = NULL */
    mov x8, SYS_WAIT4
    svc #0
    
    cmp x0, #0
    ble monitor_children    /* If error or spurious wake, loop */
    
    /* A child died (pid in x0). Respawn it! */
    mov x20, #1             /* x20 = workers to spawn */
    b spawn_workers

worker_routine:
    /* 1. Create Epoll Instance */
    mov x0, #0              /* flags = 0 */
    mov x8, SYS_EPOLL_CREATE1
    svc #0
    cmp x0, #0
    blt worker_exit         /* Fatal error */
    mov x21, x0             /* x21 = epoll_fd */
    
    /* 2. Add Listen Socket to Epoll with EPOLLEXCLUSIVE */
    sub sp, sp, #16
    ldr w0, =EPOLLEXCLUSIVE
    orr w0, w0, #EPOLLIN
    str w0, [sp]            /* events */
    str x19, [sp, #8]       /* data.fd = listen_fd */
    
    mov x0, x21             /* epfd */
    mov x1, EPOLL_CTL_ADD   /* op */
    mov x2, x19             /* fd */
    mov x3, sp              /* event ptr */
    mov x8, SYS_EPOLL_CTL
    svc #0
    
    add sp, sp, #16         /* restore stack */
    
epoll_loop:
    /* 3. Epoll Wait */
    mov x0, x21             /* epfd */
    ldr x1, =epoll_events   /* events buffer */
    mov x2, #32             /* maxevents */
    mov x3, #-1             /* timeout = infinite */
    mov x4, #0              /* sigmask = NULL */
    mov x5, #0              /* sigsetsize = 0 */
    mov x8, SYS_EPOLL_WAIT
    svc #0
    
    cmp x0, #0
    ble epoll_loop          /* Retry on error/timeout */
    
    mov x22, x0             /* x22 = num_events */
    ldr x23, =epoll_events  /* x23 = current event ptr */
    
process_events:
    cmp x22, #0
    beq epoll_loop
    
    /* Load event data.fd (offset 8) */
    ldr x24, [x23, #8]      /* x24 = event fd */
    
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
    mov x3, #0              /* flags */
    mov x8, SYS_ACCEPT4
    svc #0
    
    cmp x0, #0
    blt accept_fail
    
    mov x25, x0             /* x25 = client_fd */
    
    /* Capture IP */
    ldr w0, [sp, #20]
    ldr x1, =client_ip_str
    bl ip_to_str
    
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
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    
    /* Create Socket */
    mov x0, AF_INET
    mov x1, SOCK_STREAM
    mov x2, #0
    mov x8, SYS_SOCKET
    svc #0
    cmp x0, #0
    blt ctu_fail
    mov x19, x0     /* x19 = fd */
    
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
    ldp x29, x30, [sp], #16
    ret

ctu_close_fail:
    mov x0, x19
    mov x8, SYS_CLOSE
    svc #0
ctu_fail:
    mov x0, #-1
    ldp x29, x30, [sp], #16
    ret