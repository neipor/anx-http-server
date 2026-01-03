/* src/network.s - Network Setup */

.include "src/defs.s"

.global server_init
.global accept_loop

.text

/* server_init() -> listen_fd */
server_init:
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
    mov x1, #128
    mov x8, SYS_LISTEN
    svc #0
    
    mov x0, x19             /* Return listen_fd */
    ret

/* accept_loop(listen_fd) */
accept_loop:
    mov x19, x0             /* Save listen_fd */
    
ac_loop_start:
    mov x0, x19
    mov x1, #0
    mov x2, #0
    mov x8, SYS_ACCEPT
    svc #0
    mov x20, x0             /* x20 = client_fd */
    
    /* Call HTTP handler */
    mov x0, x20
    bl handle_client
    
    b ac_loop_start
