/* src/data.s - Global Data */

.global default_port
.global default_root
.global server_port
.global server_root
.global sockaddr
.global optval
.global msg_start, len_start
.global msg_port, len_msg_port
.global msg_root, len_msg_root
.global msg_newline
.global msg_conf_read, len_conf_read
.global msg_config_fail, len_config_fail
.global key_port
.global key_root
.global flag_p
.global flag_d
.global flag_c
.global http_200, len_200
.global http_end
.global http_404, len_404
.global index_file
.global req_buffer
.global file_path
.global num_buffer
.global config_buffer

.data
    /* Defaults */
    default_port:   .hword 0x901f       /* 8080 (Big Endian) */
    default_root:   .asciz "./www"
    
    .align 4
    /* Runtime Config (Initialized with defaults) */
    server_port:    .hword 0x901f
    server_root:    .skip 256
    
    .align 4
    /* Socket Address */
    sockaddr:
        .hword 2                /* AF_INET */
        .hword 0                /* Port (filled at runtime) */
        .word 0                 /* INADDR_ANY */
        .quad 0

    optval: .word 1

    /* Strings */
    msg_start:      .ascii "[INFO] ANX Server starting...\n"
    len_start = . - msg_start
    msg_port:       .ascii "[INFO] Port: "
    len_msg_port = . - msg_port
    msg_root:       .ascii "[INFO] Root: "
    len_msg_root = . - msg_root
    msg_newline:    .ascii "\n"
    
    msg_conf_read:  .ascii "[DEBUG] Config read\n"
    len_conf_read = . - msg_conf_read
    
    msg_config_fail:.ascii "[DEBUG] Config file not found or unreadable\n"
    len_config_fail = . - msg_config_fail
    
    /* Config Keys */
    key_port:       .asciz "port="
    key_root:       .asciz "root="
    
    /* CLI Flags */
    flag_p:         .asciz "-p"
    flag_d:         .asciz "-d"
    flag_c:         .asciz "-c"

    /* HTTP Headers */
    http_200:       .ascii "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: "
    len_200 = . - http_200
    http_end:       .ascii "\r\n\r\n"
    
    http_404:       .ascii "HTTP/1.1 404 Not Found\r\nContent-Length: 13\r\nConnection: close\r\n\r\n404 Not Found"
    len_404 = . - http_404

    index_file:     .asciz "/index.html"

.bss
    .align 4
    req_buffer:     .skip 2048
    file_path:      .skip 512
    num_buffer:     .skip 32
    config_buffer:  .skip 4096
