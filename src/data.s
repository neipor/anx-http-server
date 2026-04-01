/* src/data.s - Global Data */

.include "src/defs.s"

.global default_port
.global default_root
.global server_port
.global server_root
.global upstream_ip
.global upstream_port
.global upstream_addr
.global sockaddr
.global optval

/* Messages */
.global msg_port, len_msg_port
.global msg_root, len_msg_root
.global msg_workers, len_msg_workers
.global msg_newline
.global slash_newline, len_slash_nl
.global log_info_prefix
.global col_green, col_red, col_yellow, col_reset
.global txt_arrow
.global msg_conf_read, len_conf_read
.global msg_config_fail, len_config_fail
.global msg_bind_fail, len_bind_fail
.global timeout_tv
.global http_server_hdr, len_server_hdr
.global http_content_type, len_content_type
.global str_conn_close
.global http_date_buffer
.global http_date_hdr_prefix, len_date_hdr_prefix
.global day_names, month_names
.global msg_epoll_create_fail, len_epoll_create_fail
.global msg_epoll_ctl_fail, len_epoll_ctl_fail


/* Keys & Flags */
.global key_port, key_root, key_upstream_ip, key_upstream_port
.global flag_p, flag_d, flag_c, flag_n, flag_x, flag_h, flag_v, flag_silent
.global flag_port_long, flag_dir_long, flag_conf_long, flag_nginx_long, flag_proxy_long, flag_help_long, flag_vers_long, flag_silent_long
.global is_silent

/* HTTP Headers */
.global http_200_start, len_200_start
.global http_200_close, len_200_close
.global http_content_len, len_content_len
.global http_end
.global http_400, len_400
.global http_301_start, len_301_start
.global http_403, len_403
.global http_404, len_404
.global http_502, len_502

/* Methods & Mime */
.global dotdot
.global str_get, str_post, str_head, str_unknown
.global mime_html, mime_css, mime_js, mime_png, mime_jpg, mime_plain
.global len_mime_html, len_mime_css, len_mime_js, len_mime_png, len_mime_jpg, len_mime_plain
.global mime_json, mime_svg, mime_ico, mime_xml, mime_txt, mime_pdf
.global len_mime_json, len_mime_svg, len_mime_ico, len_mime_xml, len_mime_txt, len_mime_pdf
.global mime_bin, len_mime_bin
.global ext_html, ext_htm, ext_css, ext_js, ext_mjs, ext_png, ext_jpg, ext_jpeg
.global ext_json, ext_svg, ext_ico, ext_xml, ext_txt, ext_pdf, ext_py
.global ext_sh, ext_cgi, ext_gif, ext_webp, ext_woff, ext_woff2, ext_ttf, ext_eot
.global ext_mp4, ext_webm, ext_mp3, ext_wav, ext_zip, ext_gz, ext_tar, ext_wasm, ext_map
.global mime_gif, mime_webp, mime_woff, mime_woff2, mime_ttf, mime_eot
.global mime_mp4, mime_webm, mime_mp3, mime_wav, mime_zip, mime_gzip, mime_tar, mime_wasm
.global index_file

/* HTML Templates */
.global html_head, len_html_head
.global html_row_start, len_html_row_start
.global html_row_mid1, len_html_row_mid1
.global html_row_mid2, len_html_row_mid2
.global html_row_mid3, len_html_row_mid3
.global html_row_end, len_html_row_end
.global html_tail, len_html_tail
.global html_parent_row, len_html_parent_row

/* Buffers */
.global req_buffer
.global req_path
.global path_buffer
.global file_path
.global content_len_str
.global num_buffer
.global config_buffer
.global stat_buffer
.global log_buffer
.global client_ip_str
.global time_buffer
.global timespec
.global last_log_sec
.global epoll_events
.global iovec_buffer
.global act
    .global sendfile_offset
    .global epoll_fd

.data
    /* Defaults */
    default_port:   .hword 0x901f
    default_root:   .asciz "."
    server_port:    .hword 0x901f
    server_root:    .skip 256
    upstream_ip:    .word 0
    upstream_port:  .hword 0x2d23
    
    .align 4
    sockaddr:       .hword 2, 0
                    .word 0         /* IP */
                    .quad 0         /* Padding */
    
    .align 4
    upstream_addr:  .hword 2, 0
                    .word 0
                    .quad 0
                    
    optval:         .word 1

    .align 4
    timeout_tv:
        .quad 30        /* tv_sec = 30 */
        .quad 0         /* tv_usec = 0 */

    /* Flags */
    flag_p:         .asciz "-p"
    flag_d:         .asciz "-d"
    flag_c:         .asciz "-c"
    flag_x:         .asciz "-x"
    flag_h:         .asciz "-h"
    flag_v:         .asciz "-v"
    flag_silent:    .asciz "-s"
    flag_daemon:    .asciz "-daemon"
    
    flag_port_long: .asciz "--port"
    flag_dir_long:  .asciz "--dir"
    flag_conf_long: .asciz "--config"
    flag_nginx_long:.asciz "--nginx-config"
    flag_n:         .asciz "-n"
    flag_proxy_long:.asciz "--proxy"
    flag_help_long: .asciz "--help"
    flag_vers_long: .asciz "--version"
    flag_silent_long:.asciz "--silent"
    flag_daemon_long:.asciz "--daemon"
    flag_t:         .asciz "-t"
    flag_test_long: .asciz "--test"
    is_test_mode:   .word 0
    .global flag_t, flag_test_long, is_test_mode

    /* Messages */
    msg_port:       .ascii " \x1b[1;32m[LISTEN]\x1b[0m Port: \x1b[1;33m"
    len_msg_port = . - msg_port
    
    msg_root:       .ascii "\x1b[0m\n \x1b[1;32m[CONFIG]\x1b[0m Root: \x1b[1;35m"
    len_msg_root = . - msg_root
    
    msg_workers_prefix: .ascii "\x1b[0m\n \x1b[1;32m[WORKER]\x1b[0m Spawning \x1b[1m"
    len_workers_prefix = . - msg_workers_prefix
    msg_workers_suffix: .ascii "\x1b[0m worker processes...\n"
    len_workers_suffix = . - msg_workers_suffix
    .global msg_workers_prefix, len_workers_prefix
    .global msg_workers_suffix, len_workers_suffix
    
    msg_daemon:     .ascii " \x1b[1;36m[SYSTEM]\x1b[0m Running in background (Daemon)...\n"
    len_msg_daemon = . - msg_daemon

    msg_test_ok:    .ascii "\x1b[1;32m[OK]\x1b[0m Configuration test successful\n"
    len_test_ok = . - msg_test_ok
    .global msg_test_ok, len_test_ok

    msg_newline:    .ascii "\x1b[0m\n"
    slash_newline:  .ascii "/\r\n\r\n"
    len_slash_nl = . - slash_newline

    log_info_prefix:.asciz "\x1b[1;36m[ACCESS]\x1b[0m"
    col_green:      .asciz "\x1b[32m"
    col_red:        .asciz "\x1b[31m"
    col_yellow:     .asciz "\x1b[33m"
    col_reset:      .asciz "\x1b[0m"
    txt_arrow:      .asciz " -> "
    is_silent:      .word 0     /* Logging enabled by default */
    is_daemon:      .word 0

    msg_conf_read:  .asciz "\x1b[1;33m[DEBUG]\x1b[0m Config read\n"
    len_conf_read = . - msg_conf_read
    msg_config_fail:.ascii "\x1b[1;31m[ERROR]\x1b[0m Config file not found or unreadable\n"
    len_config_fail = . - msg_config_fail
    
    msg_bind_fail:  .ascii "\x1b[1;31m[ERROR]\x1b[0m Failed to bind port. Check if the port is in use or requires sudo.\n"
    len_bind_fail = . - msg_bind_fail
    
    key_port:       .asciz "port="
    key_root:       .asciz "root="
    key_access_log: .asciz "access_log="
    key_upstream_ip: .asciz "upstream_ip="
    key_upstream_port: .asciz "upstream_port="
    
    cpu_online_path: .asciz "/sys/devices/system/cpu/online"
    
    pid_file_default: .asciz "server.pid"

    .global flag_daemon, flag_daemon_long, is_daemon, msg_daemon, len_msg_daemon
    .global pid_file_path, pid_file_default

    /* HTTP Headers & Error Pages */
    http_server_hdr: .ascii "Server: ANX/5.0\r\n"
    len_server_hdr = . - http_server_hdr
    
    http_date_hdr_prefix: .ascii "Date: "
    len_date_hdr_prefix = . - http_date_hdr_prefix
    
    /* Day and month name lookup tables (3 chars each) */
    day_names:
        .ascii "Sun" /* 0 */
        .ascii "Mon" /* 1 */
        .ascii "Tue" /* 2 */
        .ascii "Wed" /* 3 */
        .ascii "Thu" /* 4 */
        .ascii "Fri" /* 5 */
        .ascii "Sat" /* 6 */
    month_names:
        .ascii "Jan" /* 0 = January */
        .ascii "Feb"
        .ascii "Mar"
        .ascii "Apr"
        .ascii "May"
        .ascii "Jun"
        .ascii "Jul"
        .ascii "Aug"
        .ascii "Sep"
        .ascii "Oct"
        .ascii "Nov"
        .ascii "Dec"
    
    /* Error messages (replacing debug messages) */
    msg_epoll_create_fail: .ascii "[ERROR] epoll_create1 failed\n"
    len_epoll_create_fail = . - msg_epoll_create_fail
    msg_epoll_ctl_fail: .ascii "[ERROR] epoll_ctl failed\n"
    len_epoll_ctl_fail = . - msg_epoll_ctl_fail
    
    http_status_200: .ascii "HTTP/1.1 200 OK\r\n"
    len_status_200 = . - http_status_200

    /* http_status_404 is defined in error.s; just define the length alias */
    .equ len_status_404, 24

    http_conn_ka: .ascii "Connection: keep-alive\r\n"
    len_conn_ka = . - http_conn_ka
    
    http_conn_close_hdr: .ascii "Connection: close\r\n"
    len_conn_close_hdr = . - http_conn_close_hdr
    
    http_etag_start: .ascii "ETag: \""
    len_etag_start = . - http_etag_start
    
    http_quote_newline: .ascii "\"\r\n"
    len_quote_newline = . - http_quote_newline
    
    http_content_type: .ascii "Content-Type: "
    len_content_type = . - http_content_type
    
    .global http_status_200, len_status_200
    .global http_conn_ka, len_conn_ka
    .global http_conn_close_hdr, len_conn_close_hdr
    .global http_etag_start, len_etag_start
    .global http_quote_newline, len_quote_newline
    .global etag_buffer
    
    /* 304 Not Modified */
    http_304:
        .ascii "HTTP/1.1 304 Not Modified\r\nConnection: keep-alive\r\nServer: ANX/4.1\r\nContent-Length: 0\r\n\r\n"
    len_304 = . - http_304
    .global http_304, len_304
    
    http_200_close: .ascii "HTTP/1.1 200 OK\r\nConnection: close\r\nServer: ANX/4.1\r\nContent-Type: text/html\r\n\r\n"
    len_200_close = . - http_200_close
    .global len_200_close_val
    len_200_close_val: .word 63
    
    http_content_len: .ascii "\r\nContent-Length: "
    len_content_len = . - http_content_len
    .global len_content_len_val
    len_content_len_val: .word 18
    
    http_end:       .ascii "\r\n\r\n"
    .global len_http_end_val
    len_http_end_val: .word 4
    str_http_end:   .asciz "\r\n\r\n"
    .global str_http_end
    
    /* Gzip headers */
    http_content_encoding_gzip: .ascii "\r\nContent-Encoding: gzip"
    len_content_encoding_gzip = . - http_content_encoding_gzip
    .global http_content_encoding_gzip, len_content_encoding_gzip
    
    http_vary_encoding: .ascii "\r\nVary: Accept-Encoding"
    len_vary_encoding = . - http_vary_encoding
    .global http_vary_encoding, len_vary_encoding
    
    str_accept_gzip: .asciz "gzip"
    .global str_accept_gzip
    
    ext_gz_suffix: .asciz ".gz"
    .global ext_gz_suffix
    
    ext_html_suffix: .asciz ".html"
    .global ext_html_suffix

    /* 400 Bad Request */
    http_400:
        .ascii "HTTP/1.1 400 Bad Request\r\nContent-Type: text/html\r\nConnection: close\r\nContent-Length: 363\r\n\r\n"
        .ascii "<!DOCTYPE html><html><head><title>400 Bad Request</title><style>body{font-family:system-ui,sans-serif;color:#333;text-align:center;padding:50px}h1{font-size:3em;margin:0}hr{max-width:300px;margin:20px auto;border:0;border-top:1px solid #eee}span{font-size:0.8em;color:#999}</style></head><body><h1>400</h1><p>Bad Request</p><hr><span>ANX Server</span></body></html>"
    len_400 = . - http_400

    /* 301 Moved Permanently */
    http_301_start: .ascii "HTTP/1.1 301 Moved Permanently\r\nContent-Length: 0\r\nConnection: close\r\nLocation: "
    len_301_start = . - http_301_start

    /* 403 Forbidden */
    http_403:
        .ascii "HTTP/1.1 403 Forbidden\r\nContent-Type: text/html\r\nConnection: close\r\nContent-Length: 361\r\n\r\n"
        .ascii "<!DOCTYPE html><html><head><title>403 Forbidden</title><style>body{font-family:system-ui,sans-serif;color:#333;text-align:center;padding:50px}h1{font-size:3em;margin:0}hr{max-width:300px;margin:20px auto;border:0;border-top:1px solid #eee}span{font-size:0.8em;color:#999}</style></head><body><h1>403</h1><p>Forbidden</p><hr><span>ANX Server</span></body></html>"
    len_403 = . - http_403

    /* 404 Not Found */
    http_404:
        .ascii "HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\nConnection: close\r\nContent-Length: 361\r\n\r\n"
        .ascii "<!DOCTYPE html><html><head><title>404 Not Found</title><style>body{font-family:system-ui,sans-serif;color:#333;text-align:center;padding:50px}h1{font-size:3em;margin:0}hr{max-width:300px;margin:20px auto;border:0;border-top:1px solid #eee}span{font-size:0.8em;color:#999}</style></head><body><h1>404</h1><p>Not Found</p><hr><span>ANX Server</span></body></html>"
    len_404 = . - http_404

    /* 502 Bad Gateway */
    http_502:
        .ascii "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/html\r\nConnection: close\r\nContent-Length: 363\r\n\r\n"
        .ascii "<!DOCTYPE html><html><head><title>502 Bad Gateway</title><style>body{font-family:system-ui,sans-serif;color:#333;text-align:center;padding:50px}h1{font-size:3em;margin:0}hr{max-width:300px;margin:20px auto;border:0;border-top:1px solid #eee}span{font-size:0.8em;color:#999}</style></head><body><h1>502</h1><p>Bad Gateway</p><hr><span>ANX Server</span></body></html>"
    len_502 = . - http_502

    /* /server-status endpoint */
    path_server_status: .asciz "/server-status"
    .global path_server_status

    server_status_hdr:
        .ascii "Server: ANX/5.0\r\nContent-Type: application/json\r\nCache-Control: no-cache\r\n\r\n"
    len_server_status_hdr = . - server_status_hdr
    .global server_status_hdr, len_server_status_hdr

    server_status_json:
        .ascii "{\"server\":\"ANX/5.0\",\"status\":\"active\",\"architecture\":\"aarch64\",\"workers\":4}\n"
    len_server_status_json = . - server_status_json
    .global server_status_json, len_server_status_json

    /* OPTIONS Response */
    http_options_resp:
        .ascii "HTTP/1.1 200 OK\r\n"
        .ascii "Allow: GET, HEAD, POST, PUT, DELETE, OPTIONS, PATCH\r\n"
        .ascii "Access-Control-Allow-Origin: *\r\n"
        .ascii "Access-Control-Allow-Methods: GET, HEAD, POST, PUT, DELETE, OPTIONS, PATCH\r\n"
        .ascii "Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With\r\n"
        .ascii "Access-Control-Max-Age: 86400\r\n"
        .ascii "Server: ANX/5.0\r\n"
        .ascii "Content-Length: 0\r\n"
        .ascii "\r\n"
    len_options_resp = . - http_options_resp
    .global http_options_resp, len_options_resp

    /* 405 Method Not Allowed */
    http_405:
        .ascii "HTTP/1.1 405 Method Not Allowed\r\n"
        .ascii "Allow: GET, HEAD, POST, PUT, DELETE, OPTIONS, PATCH\r\n"
        .ascii "Content-Type: text/html\r\nConnection: close\r\nContent-Length: 381\r\n\r\n"
        .ascii "<!DOCTYPE html><html><head><title>405 Method Not Allowed</title><style>body{font-family:system-ui,sans-serif;color:#333;text-align:center;padding:50px}h1{font-size:3em;margin:0}hr{max-width:300px;margin:20px auto;border:0;border-top:1px solid #eee}span{font-size:0.8em;color:#999}</style></head><body><h1>405</h1><p>Method Not Allowed</p><hr><span>ANX Server</span></body></html>"
    len_405 = . - http_405
    .global http_405, len_405

    /* 429 Too Many Requests */
    http_429:
        .ascii "HTTP/1.1 429 Too Many Requests\r\n"
        .ascii "Content-Type: text/html\r\nConnection: close\r\nRetry-After: 1\r\nContent-Length: 367\r\n\r\n"
        .ascii "<!DOCTYPE html><html><head><title>429 Too Many Requests</title><style>body{font-family:system-ui,sans-serif;color:#333;text-align:center;padding:50px}h1{font-size:3em;margin:0}hr{max-width:300px;margin:20px auto;border:0;border-top:1px solid #eee}span{font-size:0.8em;color:#999}</style></head><body><h1>429</h1><p>Too Many Requests</p><hr><span>ANX Server</span></body></html>"
    len_429 = . - http_429
    .global http_429, len_429

    /* Accept-Ranges header */
    http_accept_ranges: .ascii "\r\nAccept-Ranges: bytes"
    len_accept_ranges = . - http_accept_ranges
    .global http_accept_ranges, len_accept_ranges

    /* Range request support */
    str_range_header: .asciz "Range: bytes="
    len_range_header = . - str_range_header
    .global str_range_header, len_range_header

    http_206: .ascii "HTTP/1.1 206 Partial Content\r\n"
    len_206 = . - http_206
    .global http_206, len_206

    /* Leading \r\n terminates the Content-Type value line */
    http_content_range: .ascii "\r\nContent-Range: bytes "
    len_content_range = . - http_content_range
    .global http_content_range, len_content_range

    http_416: .ascii "HTTP/1.1 416 Range Not Satisfiable\r\nContent-Length: 0\r\nContent-Range: bytes */0\r\n\r\n"
    len_416 = . - http_416
    .global http_416, len_416

    str_dash: .ascii "-"
    str_slash: .ascii "/"
    .global str_dash, str_slash

    dotdot:         .asciz ".."
    str_get:        .asciz "GET"
    str_post:       .asciz "POST"
    str_head:       .asciz "HEAD"
    str_unknown:    .asciz "REQ"
    str_conn_close: .asciz "Connection: close"


    /* Extended MIME Types */
    mime_html:      .asciz "text/html"
    len_mime_html = . - mime_html
    .global len_mime_html_val
    len_mime_html_val: .word len_mime_html
    mime_css:       .asciz "text/css"
    len_mime_css = . - mime_css
    .global len_mime_css_val
    len_mime_css_val: .word len_mime_css
    mime_js:        .asciz "application/javascript"
    len_mime_js = . - mime_js
    .global len_mime_js_val
    len_mime_js_val: .word len_mime_js
    mime_png:       .asciz "image/png"
    len_mime_png = . - mime_png
    .global len_mime_png_val
    len_mime_png_val: .word len_mime_png
    mime_jpg:       .asciz "image/jpeg"
    len_mime_jpg = . - mime_jpg
    .global len_mime_jpg_val
    len_mime_jpg_val: .word len_mime_jpg
    mime_plain:     .asciz "text/plain"
    len_mime_plain = . - mime_plain
    .global len_mime_plain_val
    len_mime_plain_val: .word len_mime_plain
    
    mime_json:      .asciz "application/json"
    len_mime_json = . - mime_json
    .global len_mime_json_val
    len_mime_json_val: .word len_mime_json
    mime_svg:       .asciz "image/svg+xml"
    len_mime_svg = . - mime_svg
    .global len_mime_svg_val
    len_mime_svg_val: .word len_mime_svg
    mime_ico:       .asciz "image/x-icon"
    len_mime_ico = . - mime_ico
    .global len_mime_ico_val
    len_mime_ico_val: .word len_mime_ico
    mime_xml:       .asciz "application/xml"
    len_mime_xml = . - mime_xml
    .global len_mime_xml_val
    len_mime_xml_val: .word len_mime_xml
    mime_txt:       .asciz "text/plain"
    len_mime_txt = . - mime_txt
    .global len_mime_txt_val
    len_mime_txt_val: .word len_mime_txt
    mime_pdf:       .asciz "application/pdf"
    len_mime_pdf = . - mime_pdf
    .global len_mime_pdf_val
    len_mime_pdf_val: .word len_mime_pdf
    mime_bin:       .asciz "application/octet-stream"
    len_mime_bin = . - mime_bin
    .global len_mime_bin_val
    len_mime_bin_val: .word len_mime_bin

    /* Additional MIME types */
    mime_gif:       .asciz "image/gif"
    mime_webp:      .asciz "image/webp"
    mime_woff:      .asciz "font/woff"
    .global len_mime_woff_val
    len_mime_woff_val: .word 9
    mime_woff2:     .asciz "font/woff2"
    .global len_mime_woff2_val
    len_mime_woff2_val: .word 10
    mime_ttf:       .asciz "font/ttf"
    .global len_mime_ttf_val
    len_mime_ttf_val: .word 8
    mime_eot:       .asciz "application/vnd.ms-fontobject"
    .global len_mime_eot_val
    len_mime_eot_val: .word 29
    mime_mp4:       .asciz "video/mp4"
    mime_webm:      .asciz "video/webm"
    mime_mp3:       .asciz "audio/mpeg"
    mime_wav:       .asciz "audio/wav"
    mime_zip:       .asciz "application/zip"
    mime_gzip:      .asciz "application/gzip"
    mime_tar:       .asciz "application/x-tar"
    .global len_mime_tar_val
    len_mime_tar_val: .word 17
    mime_wasm:      .asciz "application/wasm"
    .global len_mime_wasm_val
    len_mime_wasm_val: .word 16

    ext_html:       .asciz ".html"
    ext_htm:        .asciz ".htm"
    ext_css:        .asciz ".css"
    ext_js:         .asciz ".js"
    ext_mjs:        .asciz ".mjs"
    ext_png:        .asciz ".png"
    ext_jpg:        .asciz ".jpg"
    ext_jpeg:       .asciz ".jpeg"
    
    ext_json:       .asciz ".json"
    ext_svg:        .asciz ".svg"
    ext_ico:        .asciz ".ico"
    ext_xml:        .asciz ".xml"
    ext_txt:        .asciz ".txt"
    ext_pdf:        .asciz ".pdf"
    ext_py:         .asciz ".py"
    ext_sh:         .asciz ".sh"
    ext_cgi:        .asciz ".cgi"
    ext_gif:        .asciz ".gif"
    ext_webp:       .asciz ".webp"
    ext_woff:       .asciz ".woff"
    ext_woff2:      .asciz ".woff2"
    ext_ttf:        .asciz ".ttf"
    ext_eot:        .asciz ".eot"
    ext_mp4:        .asciz ".mp4"
    ext_webm:       .asciz ".webm"
    ext_mp3:        .asciz ".mp3"
    ext_wav:        .asciz ".wav"
    ext_zip:        .asciz ".zip"
    ext_gz:         .asciz ".gz"
    ext_tar:        .asciz ".tar"
    ext_wasm:       .asciz ".wasm"
    ext_map:        .asciz ".map"

    index_file:     .asciz "/index.html"

    /* CGI Environment Keys */
    cgi_env_method:  .asciz "REQUEST_METHOD="
    cgi_env_query:   .asciz "QUERY_STRING="
    cgi_env_path:    .asciz "PATH_INFO="
    cgi_env_proto:   .asciz "SERVER_PROTOCOL=HTTP/1.1"
    cgi_env_software:.asciz "SERVER_SOFTWARE=ANX/4.1"
    cgi_env_content_len: .asciz "CONTENT_LENGTH="
    cgi_env_content_type: .asciz "CONTENT_TYPE="
    str_content_len_h: .asciz "Content-Length: "
    str_content_type_h: .asciz "Content-Type: "

    .global cgi_env_method, cgi_env_query, cgi_env_path, cgi_env_proto, cgi_env_software
    .global cgi_env_content_len, cgi_env_content_type
    .global str_content_len_h, str_content_type_h

    /* Templates (Directory Listing) */
    html_head:
        .ascii "<!DOCTYPE html><html><head><meta charset='utf-8'><title>Index</title>"
        .ascii "<style>"
        .ascii ":root{--bg:#fff;--fg:#333;--acc:#0366d6;--brd:#eee;--hov:#f6f8fa}"
        .ascii "body{font-family:-apple-system,sans-serif;margin:0;padding:20px;max-width:900px;margin:0 auto}"
        .ascii "h1{font-weight:300;border-bottom:1px solid var(--brd);padding-bottom:10px}"
        .ascii "table{width:100%;border-collapse:collapse}"
        .ascii "th{text-align:left;padding:10px;cursor:pointer;border-bottom:2px solid var(--brd)}"
        .ascii "td{padding:10px;border-bottom:1px solid var(--brd)}"
        .ascii "tr:hover{background:var(--hov)}"
        .ascii "a{text-decoration:none;color:var(--acc);display:block}"
        .ascii ".r{text-align:right;font-family:monospace}"
        .ascii ".d{color:#666;font-size:0.9em}"
        .ascii "</style>"
        .ascii "<script>"
        .ascii "const F={s:b=>b<0?'DIR':(b<1024?b+' B':(b/1024).toFixed(1)+' KB'),d:t=>new Date(t*1000).toLocaleString()};"
        .ascii "function S(n){const t=document.getElementById('t'),b=t.tBodies[0],r=Array.from(b.rows);"
        .ascii "let a=t.dataset.a==='1';t.dataset.a=a?'0':'1';"
        .ascii "r.sort((x,y)=>{let u=x.cells[n].dataset.v||x.cells[n].innerText,v=y.cells[n].dataset.v||y.cells[n].innerText;"
        .ascii "return !isNaN(parseFloat(u))&&!isNaN(parseFloat(v))?(a?u-v:v-u):(a?u.localeCompare(v):v.localeCompare(u))});"
        .ascii "r.forEach(e=>b.appendChild(e))}"
        .ascii "window.onload=()=>{const r=document.getElementById('t').rows;"
        .ascii "for(let i=1;i<r.length;i++){let c=r[i].cells;c[1].innerText=F.d(c[1].dataset.v);c[2].innerText=F.s(c[2].dataset.v)}"
        .ascii "</script>"
        .ascii "</head><body><h1>Index</h1>"
        .ascii "<table id='t' data-a='0'><thead><tr><th onclick='S(0)'>Name</th><th onclick='S(1)'>Date</th><th onclick='S(2)' class='r'>Size</th></tr></thead><tbody>"
    len_html_head = . - html_head

    html_row_start: .ascii "<tr><td><a href=\""
    len_html_row_start = . - html_row_start

    html_row_mid1:  .byte 0x22, 0x3e
    len_html_row_mid1 = . - html_row_mid1
    
    html_row_mid2:  .ascii "</a></td><td class='d' data-v="
                    .byte 0x27
    len_html_row_mid2 = . - html_row_mid2

    html_row_mid3:  .byte 0x27, 0x3e
                    .ascii "</td><td class='r' data-v="
                    .byte 0x27
    len_html_row_mid3 = . - html_row_mid3

    html_row_end:   .byte 0x27, 0x3e
                    .ascii "</td></tr>"
    len_html_row_end = . - html_row_end

    html_tail:      .ascii "</tbody></table></body></html>"
    len_html_tail = . - html_tail

    html_parent_row: .ascii "<tr><td><a href=\"..\">..</a></td><td class='d'>-</td><td class='r'>DIR</td></tr>"
    len_html_parent_row = . - html_parent_row

.bss
    .align 4
    req_buffer:     .skip 8192
    req_path:       .skip 2048
    query_string:   .skip 2048
    path_buffer:    .skip 2048
    file_path:      .skip 512
    num_buffer:     .skip 32
    config_buffer:  .skip 8192
    stat_buffer:    .skip 128
    log_buffer:     .skip 512
    log_buffer2:    .skip 1024   /* nginx combined log format buffer */
    client_ip_str:  .skip 32
    time_buffer:    .skip 32
    epoll_events:   .skip 512
    iovec_buffer:   .skip 256
    
    .align 8
    last_log_sec:   .skip 8
    timespec:       .skip 16
    
    .align 4
    act:            .skip 152
    content_len_str: .skip 32
    etag_buffer:    .skip 64
    http_date_buffer: .skip 64
    sendfile_offset: .skip 8
    epoll_fd: .word 0
    current_status: .skip 4
    current_method: .skip 4
    access_log_path: .skip 256
    env_buffer:     .skip 4096
    worker_count:   .skip 4
    worker_pids:    .skip 256     /* Up to 64 worker PIDs (4 bytes each) */
    pid_file_path:  .skip 256
    client_accepts_gzip: .skip 4
    serving_gzip:   .skip 4
    gzip_path_buf:  .skip 2048
    matched_location: .skip 8
    reload_requested: .skip 4
    has_range_request: .skip 4
    .align 8
    range_start: .skip 8
    range_end: .skip 8
    .align 8
    accept_mutex_ptr: .skip 8   /* pointer to shared mmap region for accept mutex */
    gzip_chunk_buf: .skip 8192  /* 8KB chunk buffer for dynamic gzip output */
    gzip_pipe_fds: .skip 8      /* [read_fd, write_fd] for gzip pipe */

    .global accept_mutex_ptr
    .global current_status
    .global current_method
    .global access_log_path
    .global worker_count
    .global worker_pids
    .global cpu_online_path
    .global query_string
    .global env_buffer
    .global log_fd
    .global key_access_log
    .global worker_stack_end
    .global client_accepts_gzip, serving_gzip, gzip_path_buf
    .global reload_requested
    .global matched_location
    .global has_range_request, range_start, range_end
    .global log_buffer2
    .global gzip_chunk_buf, gzip_pipe_fds

.data
    log_combined_dash:  .asciz " - - ["
    log_combined_proto: .asciz " HTTP/1.1\" "
    log_combined_end:   .asciz " -\n"
    .global log_combined_dash, log_combined_proto, log_combined_end
    /* Dynamic gzip helpers */
    dgzip_ce_hdr:   .ascii "Content-Encoding: gzip\r\nTransfer-Encoding: chunked\r\n"
    dgzip_ce_len = . - dgzip_ce_hdr
    .global dgzip_ce_hdr, dgzip_ce_len
    dgzip_chunk_end: .ascii "\r\n"
    dgzip_final_chunk: .ascii "0\r\n\r\n"
    dgzip_final_len = . - dgzip_final_chunk
    .global dgzip_chunk_end, dgzip_final_chunk, dgzip_final_len
    gzip_bin:   .asciz "/bin/gzip"
    gzip_arg0:  .asciz "/bin/gzip"
    gzip_argc:  .asciz "-c"
    .global gzip_bin, gzip_arg0, gzip_argc
    log_fd:         .word 1     /* Default to stdout (1) */

/* Worker stack - each worker gets 64KB stack */
.bss
    .align 16
    worker_stack:   .skip 65536
    worker_stack_end:
