/* 
 * ANX AArch64 Pure Assembly High-Performance HTTP Server v2.1
 * Features: SO_REUSEADDR, GET parsing, File serving, itoa
 */

.equ SYS_WRITE, 64
.equ SYS_READ, 63
.equ SYS_OPENAT, 56
.equ SYS_CLOSE, 57
.equ SYS_EXIT, 93
.equ SYS_SOCKET, 198
.equ SYS_BIND, 200
.equ SYS_LISTEN, 201
.equ SYS_ACCEPT, 202
.equ SYS_SETSOCKOPT, 208

.equ AF_INET, 2
.equ SOCK_STREAM, 1
.equ SOL_SOCKET, 1
.equ SO_REUSEADDR, 2
.equ AT_FDCWD, -100
.equ O_RDONLY, 0

.data
    sockaddr:
        .hword AF_INET
        .hword 0x901f       /* Port 8080 */
        .word 0             /* INADDR_ANY */
        .quad 0

    optval: .word 1         /* For setsockopt */

    msg_start:      .ascii "[INFO] ANX ASM Server v2.1 starting on port 8080...\n"
    len_start = . - msg_start
    msg_ok:         .ascii "[INFO] Server is up and running.\n"
    len_ok = . - msg_ok
    msg_err_sock:   .ascii "[ERROR] Socket creation failed\n"
    len_err_sock = . - msg_err_sock
    msg_err_bind:   .ascii "[ERROR] Bind failed (Port in use?)\n"
    len_err_bind = . - msg_err_bind

    file_name:      .asciz "index.html"
    
    http_200_head:  .ascii "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: "
    len_200_head = . - http_200_head
    http_end_head:  .ascii "\r\nConnection: close\r\n\r\n"
    len_end_head = . - http_end_head
    http_404:
        .ascii "HTTP/1.1 404 Not Found\r\nContent-Length: 13\r\nConnection: close\r\n\r\n404 Not Found"
    len_404 = . - http_404

    req_get_root:   .ascii "GET / "
    len_req_root = . - req_get_root

.bss
    .align 4
    req_buffer:     .skip 1024
    file_buffer:    .skip 4096
    num_buffer:     .skip 16

.text
.global _start

_start:
    /* Startup Log */
    mov x0, #1
    ldr x1, =msg_start
    mov x2, len_start
    mov x8, SYS_WRITE
    svc #0

    /* 1. Create socket */
    mov x0, AF_INET
    mov x1, SOCK_STREAM
    mov x2, #0
    mov x8, SYS_SOCKET
    svc #0
    cmp x0, #0
    blt err_socket
    mov x19, x0             /* x19 = listen_fd */

    /* 2. Set SO_REUSEADDR */
    mov x0, x19
    mov x1, SOL_SOCKET
    mov x2, SO_REUSEADDR
    ldr x3, =optval
    mov x4, #4
    mov x8, SYS_SETSOCKOPT
    svc #0

    /* 3. Bind */
    mov x0, x19
    ldr x1, =sockaddr
    mov x2, #16
    mov x8, SYS_BIND
    svc #0
    cmp x0, #0
    blt err_bind

    /* 4. Listen */
    mov x0, x19
    mov x1, #128
    mov x8, SYS_LISTEN
    svc #0

    /* Success Log */
    mov x0, #1
    ldr x1, =msg_ok
    mov x2, len_ok
    mov x8, SYS_WRITE
    svc #0

accept_loop:
    mov x0, x19
    mov x1, #0
    mov x2, #0
    mov x8, SYS_ACCEPT
    svc #0
    cmp x0, #0
    blt accept_loop
    mov x20, x0             /* x20 = client_fd */

    /* Read Request */
    mov x0, x20
    ldr x1, =req_buffer
    mov x2, #1024
    mov x8, SYS_READ
    svc #0
    cmp x0, #0
    ble close_client

    /* Parse "GET / " */
    ldr x1, =req_buffer
    ldr x2, =req_get_root
    mov x3, len_req_root
    bl memcmp
    cmp x0, #0
    bne serve_404

serve_index:
    mov x0, AT_FDCWD
    ldr x1, =file_name
    mov x2, O_RDONLY
    mov x8, SYS_OPENAT
    svc #0
    cmp x0, #0
    blt serve_404
    mov x21, x0             /* x21 = file_fd */

    mov x0, x21
    ldr x1, =file_buffer
    mov x2, #4096
    mov x8, SYS_READ
    svc #0
    mov x22, x0             /* x22 = file_size */

    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0

    /* Header Part 1 */
    mov x0, x20
    ldr x1, =http_200_head
    mov x2, len_200_head
    mov x8, SYS_WRITE
    svc #0

    /* Content-Length */
    mov x0, x22
    ldr x1, =num_buffer
    bl itoa
    mov x23, x0
    mov x0, x20
    ldr x1, =num_buffer
    mov x2, x23
    mov x8, SYS_WRITE
    svc #0

    /* Header End */
    mov x0, x20
    ldr x1, =http_end_head
    mov x2, len_end_head
    mov x8, SYS_WRITE
    svc #0

    /* File Content */
    mov x0, x20
    ldr x1, =file_buffer
    mov x2, x22
    mov x8, SYS_WRITE
    svc #0
    b close_client

serve_404:
    mov x0, x20
    ldr x1, =http_404
    mov x2, len_404
    mov x8, SYS_WRITE
    svc #0

close_client:
    mov x0, x20
    mov x8, SYS_CLOSE
    svc #0
    b accept_loop

err_socket:
    mov x0, #1
    ldr x1, =msg_err_sock
    mov x2, len_err_sock
    mov x8, SYS_WRITE
    svc #0
    b exit

err_bind:
    mov x0, #1
    ldr x1, =msg_err_bind
    mov x2, len_err_bind
    mov x8, SYS_WRITE
    svc #0
    b exit

exit:
    mov x0, #1
    mov x8, SYS_EXIT
    svc #0

/* Utilities */
memcmp:
    mov x4, #0
mc_loop:
    cmp x4, x3
    bge mc_eq
    ldrb w5, [x1, x4]
    ldrb w6, [x2, x4]
    cmp w5, w6
    bne mc_ne
    add x4, x4, #1
    b mc_loop
mc_eq: mov x0, #0
    ret
mc_ne: mov x0, #1
    ret

itoa:
    mov x2, x1
    mov x3, x0
    mov x4, #0
    mov x5, #10
    cmp x3, #0
    bne it_loop
    mov w6, #'0'
    strb w6, [x2]
    mov x0, #1
    ret
it_loop:
    cmp x3, #0
    beq it_rev
    udiv x6, x3, x5
    msub x7, x6, x5, x3
    add w7, w7, #'0'
    strb w7, [x2, x4]
    add x4, x4, #1
    mov x3, x6
    b it_loop
it_rev:
    mov x0, x4
    mov x8, #0
    sub x9, x4, #1
rv_loop:
    cmp x8, x9
    bge rv_dn
    ldrb w10, [x2, x8]
    ldrb w11, [x2, x9]
    strb w11, [x2, x8]
    strb w10, [x2, x9]
    add x8, x8, #1
    sub x9, x9, #1
    b rv_loop
rv_dn: ret