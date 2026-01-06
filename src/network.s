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

    /* 0. Ignore SIGCHLD to prevent zombies */
    ldr x0, =act
    mov x1, #1              /* SIG_IGN */
    str x1, [x0]            /* sa_handler */
    mov x1, #0              /* flags (0) */
    str x1, [x0, #8]        /* sa_flags */
    str xzr, [x0, #16]      /* sa_restorer */
    str xzr, [x0, #24]      /* sa_mask */
    
    mov x0, SIGCHLD
    ldr x1, =act
    mov x2, #0              /* oldact */
    mov x3, #8              /* sigsetsize */
    mov x8, SYS_RT_SIGACTION
    svc #0
    
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
    
    /* 4. Listen */
    mov x0, x19
    mov x1, #1024           /* Increased backlog */
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
    /* Parent Process: Just wait for signals (or implement restart logic later) */
    /* For now, just pause forever to keep container alive */
    mov x0, #0
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x8, SYS_WAIT4
    svc #0
    b monitor_children

worker_routine:
    /* Worker Process: Infinite Accept Loop */
    
worker_accept:
    /* Allocate space for sockaddr */
    sub sp, sp, #32
    mov w2, #16
    str w2, [sp]            /* addrlen = 16 */
    
    mov x0, x19             /* listen_fd */
    add x1, sp, #16         /* sockaddr ptr */
    mov x2, sp              /* addrlen ptr */
    mov x8, SYS_ACCEPT
    svc #0
    
    cmp x0, #0
    blt worker_accept_fail
    
    mov x20, x0             /* x20 = client_fd */
    
    /* Capture IP (Worker local) */
    ldr w0, [sp, #20]
    ldr x1, =client_ip_str  /* NOTE: In prefork, this is safe unless threaded (we are process) */
    bl ip_to_str
    
    add sp, sp, #32         /* Restore stack */
    
    /* Handle Client (Blocking) */
    mov x0, x20
    bl handle_client
    
    /* Close Client */
    /* handle_client already closes fd? Check http.s logic. */
    /* http.s hc_close does close(client_fd). So we are good. */
    
    /* Loop back to accept next connection */
    b worker_accept

worker_accept_fail:
    add sp, sp, #32
    /* If error is interrupt, retry. If fatal, maybe exit? Just retry for now */
    b worker_accept

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