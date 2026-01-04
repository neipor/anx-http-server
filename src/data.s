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
.global http_200_start, len_200_start
.global http_content_len, len_content_len
.global http_end
.global http_404, len_404
.global index_file
.global req_buffer
.global file_path
.global num_buffer
.global config_buffer
.global act

.global mime_html
.global mime_css
.global mime_js
.global mime_png
.global mime_jpg
.global mime_plain

.global ext_html
.global ext_css
.global ext_js
.global ext_png
.global ext_jpg

.global dir_html_start, len_dir_start
.global dir_html_end, len_dir_end
.global li_start, len_li_start
.global li_mid, len_li_mid
.global li_end, len_li_end

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

    /* HTTP Headers Parts */
    http_200_start: .ascii "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: "
    len_200_start = . - http_200_start
    
    http_content_len: .ascii "\r\nContent-Length: "
    len_content_len = . - http_content_len
    
    http_end:       .ascii "\r\n\r\n"
    
    http_404:       .ascii "HTTP/1.1 404 Not Found\r\nContent-Length: 13\r\nConnection: close\r\n\r\n404 Not Found"
    len_404 = . - http_404

    /* MIME Types */
    mime_html:      .asciz "text/html"
    mime_css:       .asciz "text/css"
    mime_js:        .asciz "application/javascript"
    mime_png:       .asciz "image/png"
    mime_jpg:       .asciz "image/jpeg"
    mime_plain:     .asciz "text/plain"
    
    /* Extensions */
    ext_html:       .asciz ".html"
    ext_css:        .asciz ".css"
    ext_js:         .asciz ".js"
    ext_png:        .asciz ".png"
    ext_jpg:        .asciz ".jpg"

    /* Directory Listing */
    dir_html_start: .ascii "<html><head><title>Directory Listing</title></head><body><h1>Directory Listing</h1><ul>"
    len_dir_start = . - dir_html_start
    dir_html_end:   .ascii "</ul></body></html>"
    len_dir_end = . - dir_html_end
    
    li_start:       .ascii "<li><a href=\""
    len_li_start = . - li_start
    li_mid:         .ascii "\">"
    len_li_mid = . - li_mid
    li_end:         .ascii "</a></li>"
    len_li_end = . - li_end
    
    index_file:     .asciz "/index.html"

.bss
    .align 4
    req_buffer:     .skip 2048
    file_path:      .skip 512
    num_buffer:     .skip 32
    config_buffer:  .skip 4096
    
    .align 4
    act:            .skip 152   /* sizeof(struct sigaction) approx */
