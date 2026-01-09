/* src/data.s - Global Data */

.global default_port
.global default_root
.global server_port
.global server_root
.global upstream_ip
.global upstream_port
.global upstream_addr
.global sockaddr
.global optval

.global msg_start, len_start
.global msg_port, len_msg_port
.global msg_root, len_msg_root
.global msg_newline
.global slash_newline, len_slash_nl
.global log_info_prefix, len_log_info
.global col_green
.global col_red
.global col_yellow
.global col_reset
.global txt_arrow
.global msg_conf_read, len_conf_read
.global msg_config_fail, len_config_fail

.global key_port
.global key_root
.global key_upstream_ip
.global key_upstream_port

.global flag_p
.global flag_d
.global flag_c
.global flag_x
.global flag_h
.global flag_v
.global flag_port_long
.global flag_dir_long
.global flag_conf_long
.global flag_proxy_long
.global flag_help_long
.global flag_vers_long

.global msg_help_1, len_help_1
.global msg_version, len_version

.global http_200_start, len_200_start
.global http_content_len, len_content_len
.global http_end
.global http_400, len_400
.global http_301_start, len_301_start
.global http_403, len_403
.global http_404, len_404
.global http_502, len_502

.global index_file
.global req_buffer
.global file_path
.global num_buffer
.global config_buffer
.global stat_buffer
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
.global tr_start, len_tr_start
.global tr_mid, len_tr_mid
.global tr_mid_2, len_tr_mid_2
.global tr_end, len_tr_end
.global dir_label, len_dir_label
.global str_get
.global str_post
.global str_head
.global str_unknown
.global flag_silent
.global flag_silent_long
.global is_silent

.global dotdot

.global msg_start, len_start
.global msg_port, len_msg_port
.global msg_root, len_msg_root
.global msg_newline
.global slash_newline, len_slash_nl
.global log_info_prefix, len_log_info
.global col_green
.global col_red
.global col_yellow
.global col_reset
.global txt_arrow
.global log_buffer
.global client_ip_str
.global time_buffer
.global timespec
.global last_log_sec
.global epoll_events
.global iovec_buffer
.global act

.data
    /* Defaults */
    default_port:   .hword 0x901f       /* 8080 (Big Endian) */
    default_root:   .asciz "."          /* Current directory */
    
    .align 4
    /* Runtime Config (Initialized with defaults) */
    server_port:    .hword 0x901f
    server_root:    .skip 256
    
    upstream_ip:    .word 0         /* 0 = disabled */
    upstream_port:  .hword 0x2d23   /* 9005 (Big Endian: 0x232d -> 2d23) */
    
    .align 4
    /* Socket Address */
    sockaddr:
        .hword 2                /* AF_INET */
        .hword 0                /* Port (filled at runtime) */
        .word 0                 /* INADDR_ANY */
        .quad 0
    
    /* Upstream Address */
    upstream_addr:
        .hword 2
        .hword 0
        .word 0
        .quad 0

    optval: .word 1

    /* CLI Flags */
    flag_p:         .asciz "-p"
    flag_d:         .asciz "-d"
    flag_c:         .asciz "-c"
    flag_x:         .asciz "-x"
    flag_h:         .asciz "-h"
    flag_v:         .asciz "-v"
    
    flag_port_long: .asciz "--port"
    flag_dir_long:  .asciz "--dir"
    flag_conf_long: .asciz "--config"
    flag_proxy_long:.asciz "--proxy"
    flag_help_long: .asciz "--help"
    flag_vers_long: .asciz "--version"
    flag_silent:    .asciz "-s"
    flag_silent_long:.asciz "--silent"

    /* Help & Version */
    msg_version:    .ascii "anx v4.1\n"
    len_version = . - msg_version

    msg_help_1:     .ascii "\033[1;32manx\033[0m - A high-performance AArch64 Assembly Web Server\n\n"
                    .ascii "\033[1mUSAGE:\033[0m\n    anx [OPTIONS] [serve-path]\n\n"
                    .ascii "\033[1mARGS:\033[0m\n    <serve-path>         Path to serve [default: ./www]\n\n"
                    .ascii "\033[1mOPTIONS:\033[0m\n"
                    .ascii "    -p, --port <port>    Port to listen on [default: 8080]\n"
                    .ascii "    -d, --dir <path>     Path to directory to serve\n"
                    .ascii "    -s, --silent         Disable access logging\n"
                    .ascii "    -c, --config <file>  Load configuration file\n"
                    .ascii "    -x, --proxy          Enable reverse proxy mode (to 127.0.0.1:9005)\n"
                    .ascii "    -h, --help           Print help information\n"
                    .ascii "    -v, --version        Print version information\n\n"
    len_help_1 = . - msg_help_1

    /* Log Messages */
    msg_start:      .ascii "\033[1;32m[INFO]\033[0m ANX Server starting...\n"
    len_start = . - msg_start
    msg_port:       .ascii "\033[1;34m[INFO]\033[0m Port: "
    len_msg_port = . - msg_port
    msg_root:       .ascii "\033[1;34m[INFO]\033[0m Root: "
    len_msg_root = . - msg_root
    msg_newline:    .ascii "\n"
    
    slash_newline:  .ascii "/\r\n\r\n"
    len_slash_nl = . - slash_newline

    /* Access Log Colors */
    log_info_prefix:.asciz "\033[1;36m[ACCESS]\033[0m"
    
    col_green:      .asciz "\033[32m"
    col_red:        .asciz "\033[31m"
    col_yellow:     .asciz "\033[33m"
    col_reset:      .asciz "\033[0m"
    
    txt_arrow:      .asciz " -> "
    
    /* Config for Silent Mode (0=Log, 1=Silent) */
    is_silent:      .word 0

    msg_conf_read:  .asciz "\033[1;33m[DEBUG]\033[0m Config read\n"
    len_conf_read = . - msg_conf_read
    
    msg_config_fail:.ascii "\033[1;31m[ERROR]\033[0m Config file not found or unreadable\n"
    len_config_fail = . - msg_config_fail
    
    /* Config Keys */
    key_port:       .asciz "port="
    key_root:       .asciz "root="
    key_upstream_ip: .asciz "upstream_ip="
    key_upstream_port: .asciz "upstream_port="

    /* HTTP Headers Parts */
    http_200_start: .ascii "HTTP/1.1 200 OK\r\nConnection: keep-alive\r\nContent-Type: "
    len_200_start = . - http_200_start
    
    http_content_len: .ascii "\r\nContent-Length: "
    len_content_len = . - http_content_len
    
    http_end:       .ascii "\r\n\r\n"
    
    http_400:       .ascii "HTTP/1.1 400 Bad Request\r\nContent-Length: 15\r\nConnection: close\r\n\r\n400 Bad Request"
    len_400 = . - http_400

    http_301_start: .ascii "HTTP/1.1 301 Moved Permanently\r\nContent-Length: 0\r\nConnection: close\r\nLocation: "
    len_301_start = . - http_301_start

    http_403:       .ascii "HTTP/1.1 403 Forbidden\r\nContent-Length: 13\r\nConnection: close\r\n\r\n403 Forbidden"
    len_403 = . - http_403

    http_404:       .ascii "HTTP/1.1 404 Not Found\r\nContent-Length: 13\r\nConnection: close\r\n\r\n404 Not Found"
    len_404 = . - http_404

    http_502:       .ascii "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 15\r\nConnection: close\r\n\r\n502 Bad Gateway"
    len_502 = . - http_502

    /* Methods & Security */
    dotdot:         .asciz ".."
    
    str_get:        .asciz "GET"
    str_post:       .asciz "POST"
    str_head:       .asciz "HEAD"
    str_unknown:    .asciz "REQ"

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
    dir_html_start: .ascii "<html><head><title>Directory Listing</title><meta charset=\"utf-8\"><style>"
                    .ascii "body{font-family:system-ui,-apple-system,sans-serif;max-width:900px;margin:3rem auto;padding:0 2rem;color:#333}"
                    .ascii "h1{font-size:1.5rem;border-bottom:1px solid #eaeaea;padding-bottom:1rem;margin-bottom:1.5rem}"
                    .ascii "table{width:100%;border-collapse:collapse;font-size:0.95rem}"
                    .ascii "th{text-align:left;padding:0.75rem 0;border-bottom:2px solid #eaeaea;color:#666;font-weight:600}"
                    .ascii "td{padding:0.75rem 0;border-bottom:1px solid #eaeaea}"
                    .ascii "a{text-decoration:none;color:#0070f3;font-weight:500}"
                    .ascii "a:hover{text-decoration:underline}"
                    .ascii ".size{text-align:right;color:#666;font-family:monospace}"
                    .ascii "</style></head><body><h1>Directory Listing</h1>"
                    .ascii "<table><thead><tr><th>Name</th><th class=\"size\">Size (Bytes)</th></tr></thead><tbody>"
    len_dir_start = . - dir_html_start
    dir_html_end:   .ascii "</tbody></table></body></html>"
    len_dir_end = . - dir_html_end
    
    tr_start:       .ascii "<tr><td><a href=\""
    len_tr_start = . - tr_start
    tr_mid:         .ascii "\">"
    len_tr_mid = . - tr_mid
    tr_mid_2:       .ascii "</a></td><td class=\"size\">"
    len_tr_mid_2 = . - tr_mid_2
    tr_end:         .ascii "</td></tr>"
    len_tr_end = . - tr_end
    
    dir_label:      .ascii " [DIR]"
    len_dir_label = . - dir_label
    
    index_file:     .asciz "/index.html"

.bss
    .align 4
    req_buffer:     .skip 2048
    file_path:      .skip 512
    num_buffer:     .skip 32
    config_buffer:  .skip 4096
    stat_buffer:    .skip 128
    
    log_buffer:     .skip 512       /* For atomic log lines */
    client_ip_str:  .skip 32        /* "XXX.XXX.XXX.XXX\0" */
    time_buffer:    .skip 32        /* "[HH:MM:SS] " */
    
    /* Connection Contexts */
    .align 4
    epoll_events:   .skip 512
    
    /* IOVEC for writev (Max 8 elements * 16 bytes = 128) */
    .align 4
    iovec_buffer:   .skip 128
    
    /* Connection State */
    keep_alive_flag: .skip 4

    /* Time Cache */
    .align 4
    last_log_sec:   .skip 8         /* Last cached timestamp seconds */

    .align 4
    timespec:       .skip 16        /* struct timespec { sec, nsec } */
    act:            .skip 152   /* sizeof(struct sigaction) approx */