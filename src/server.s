/* 
 * ANX AArch64 Pure Assembly High-Performance HTTP Server
 * No C standard library, no runtime, just pure syscalls.
 */

.data
    /* Socket Address Structure: sockaddr_in (16 bytes) */
    /* sin_family (2), sin_port (2), sin_addr (4), sin_zero (8) */
    sockaddr:
        .hword 2                /* AF_INET = 2 */
        .hword 0x901f           /* Port 8080 (in big-endian, 8080 = 0x1F90 -> 0x901F) */
        .word 0                 /* INADDR_ANY = 0 */
        .quad 0                 /* Padding */

    msg_start:      .ascii "[INFO] ANX ASM Server listening on port 8080...\n"
    len_start = . - msg_start

    msg_accept:     .ascii "[INFO] Connection accepted\n"
    len_accept = . - msg_accept

    http_response:
        .ascii "HTTP/1.1 200 OK\r\n"
        .ascii "Content-Type: text/plain\r\n"
        .ascii "Content-Length: 26\r\n"
        .ascii "Connection: close\r\n"
        .ascii "\r\n"
        .ascii "Hello from Pure ASM Server!"
    len_response = . - http_response

.text
.global _start

_start:
    /* 1. Print startup message */
    mov x0, #1
    ldr x1, =msg_start
    mov x2, len_start
    mov x8, #64             /* write */
    svc #0

    /* 2. Create socket: socket(AF_INET, SOCK_STREAM, 0) */
    mov x0, #2              /* AF_INET */
    mov x1, #1              /* SOCK_STREAM */
    mov x2, #0
    mov x8, #198            /* socket */
    svc #0
    
    cmp x0, #0
    blt exit_error
    mov x19, x0             /* x19 = listen_fd */

    /* 3. Bind: bind(listen_fd, &sockaddr, 16) */
    mov x0, x19
    ldr x1, =sockaddr
    mov x2, #16
    mov x8, #200            /* bind */
    svc #0
    
    cmp x0, #0
    blt exit_error

    /* 4. Listen: listen(listen_fd, 128) */
    mov x0, x19
    mov x1, #128
    mov x8, #201            /* listen */
    svc #0

accept_loop:
    /* 5. Accept: accept(listen_fd, NULL, NULL) */
    mov x0, x19
    mov x1, #0
    mov x2, #0
    mov x8, #202            /* accept */
    svc #0
    
    cmp x0, #0
    blt accept_loop
    mov x20, x0             /* x20 = client_fd */

    /* Log acceptance */
    mov x0, #1
    ldr x1, =msg_accept
    mov x2, len_accept
    mov x8, #64
    svc #0

    /* 6. Send Response: write(client_fd, http_response, len_response) */
    mov x0, x20
    ldr x1, =http_response
    mov x2, len_response
    mov x8, #64
    svc #0

    /* 7. Close client socket: close(client_fd) */
    mov x0, x20
    mov x8, #57             /* close */
    svc #0

    b accept_loop

exit_error:
    mov x0, #1              /* exit status 1 */
    mov x8, #93             /* exit */
    svc #0