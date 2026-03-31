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


/* Keys & Flags */
.global key_port, key_root, key_upstream_ip, key_upstream_port
.global flag_p, flag_d, flag_c, flag_x, flag_h, flag_v, flag_silent
.global flag_port_long, flag_dir_long, flag_conf_long, flag_proxy_long, flag_help_long, flag_vers_long, flag_silent_long
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
.global ext_html, ext_css, ext_js, ext_png, ext_jpg
.global ext_json, ext_svg, ext_ico, ext_xml, ext_txt, ext_pdf, ext_py
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
    flag_proxy_long:.asciz "--proxy"
    flag_help_long: .asciz "--help"
    flag_vers_long: .asciz "--version"
    flag_silent_long:.asciz "--silent"
    flag_daemon_long:.asciz "--daemon"

    /* Messages */
    msg_port:       .ascii " \x1b[1;32m[LISTEN]\x1b[0m Port: \x1b[1;33m"
    len_msg_port = . - msg_port
    
    msg_root:       .ascii "\x1b[0m\n \x1b[1;32m[CONFIG]\x1b[0m Root: \x1b[1;35m"
    len_msg_root = . - msg_root
    
    msg_workers:    .ascii "\x1b[0m\n \x1b[1;32m[WORKER]\x1b[0m Spawning \x1b[1m64\x1b[0m worker processes...\n"
    len_msg_workers = . - msg_workers
    
    msg_workers_prefix: .ascii "\x1b[0m\n \x1b[1;32m[WORKER]\x1b[0m Spawning \x1b[1m"
    len_msg_workers_prefix = . - msg_workers_prefix
    
    msg_workers_suffix: .ascii "\x1b[0m worker processes...\n"
    len_msg_workers_suffix = . - msg_workers_suffix
    
    .global msg_workers_prefix, len_msg_workers_prefix
    .global msg_workers_suffix, len_msg_workers_suffix
    
    msg_daemon:     .ascii " \x1b[1;36m[SYSTEM]\x1b[0m Running in background (Daemon)...\n"
    len_msg_daemon = . - msg_daemon

    msg_newline:    .ascii "\x1b[0m\n"
    slash_newline:  .ascii "/\r\n\r\n"
    len_slash_nl = . - slash_newline

    log_info_prefix:.asciz "\x1b[1;36m[ACCESS]\x1b[0m"
    col_green:      .asciz "\x1b[32m"
    col_red:        .asciz "\x1b[31m"
    col_yellow:     .asciz "\x1b[33m"
    col_reset:      .asciz "\x1b[0m"
    txt_arrow:      .asciz " -> "
    is_silent:      .word 0
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
    key_worker_processes: .asciz "worker_processes="
    key_keepalive_timeout: .asciz "keepalive_timeout="
    key_client_max_body: .asciz "client_max_body_size="
    key_server_tokens: .asciz "server_tokens="
    key_autoindex:  .asciz "autoindex="
    key_gzip_static: .asciz "gzip_static="
    key_error_page_dir: .asciz "error_page_dir="
    key_cache_control: .asciz "cache_control="
    key_index:      .asciz "index="
    key_sendfile:   .asciz "sendfile="
    key_tcp_nopush: .asciz "tcp_nopush="
    key_tcp_nodelay:.asciz "tcp_nodelay="
    key_proxy_set_header: .asciz "proxy_set_header="
    key_add_header: .asciz "add_header="
    str_on:         .asciz "on"
    str_off:        .asciz "off"
    
    .global key_worker_processes, key_keepalive_timeout, key_client_max_body
    .global key_server_tokens, key_autoindex, key_gzip_static, key_error_page_dir
    .global key_cache_control, key_index, key_sendfile, key_tcp_nopush, key_tcp_nodelay
    .global key_proxy_set_header, key_add_header, str_on, str_off
    
    pid_file_path: .asciz "server.pid"
    
    .global flag_daemon, flag_daemon_long, is_daemon, msg_daemon, len_msg_daemon
    .global pid_file_path

    /* HTTP Headers & Error Pages */
    http_server_hdr: .ascii "Server: ANX/4.1\r\n"
    len_server_hdr = . - http_server_hdr
    
    http_server_hdr_hidden: .ascii "Server: ANX\r\n"
    len_server_hdr_hidden = . - http_server_hdr_hidden
    
    http_status_200: .ascii "HTTP/1.1 200 OK\r\n"
    len_status_200 = . - http_status_200
    
    http_status_206: .ascii "HTTP/1.1 206 Partial Content\r\n"
    len_status_206 = . - http_status_206
    
    http_resp_405: .ascii "HTTP/1.1 405 Method Not Allowed\r\nContent-Length: 0\r\nAllow: GET, HEAD, POST\r\nConnection: close\r\n\r\n"
    len_resp_405 = . - http_resp_405
    
    http_resp_413: .ascii "HTTP/1.1 413 Payload Too Large\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    len_resp_413 = . - http_resp_413
    
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
    
    http_accept_ranges: .ascii "Accept-Ranges: bytes\r\n"
    len_accept_ranges = . - http_accept_ranges
    
    http_content_range_start: .ascii "Content-Range: bytes "
    len_content_range_start = . - http_content_range_start
    
    http_cache_control_start: .ascii "Cache-Control: "
    len_cache_control_start = . - http_cache_control_start
    
    http_last_modified: .ascii "Last-Modified: "
    len_last_modified = . - http_last_modified
    
    http_x_forwarded_for: .ascii "X-Forwarded-For: "
    len_x_forwarded_for = . - http_x_forwarded_for
    
    http_x_real_ip: .ascii "X-Real-IP: "
    len_x_real_ip = . - http_x_real_ip
    
    http_vary: .ascii "Vary: Accept-Encoding\r\n"
    len_vary = . - http_vary
    
    http_content_encoding_gzip: .ascii "Content-Encoding: gzip\r\n"
    len_content_encoding_gzip = . - http_content_encoding_gzip
    
    http_cache_static: .ascii "Cache-Control: public, max-age=86400\r\n"
    len_cache_static = . - http_cache_static
    
    http_cache_dynamic: .ascii "Cache-Control: no-cache\r\n"
    len_cache_dynamic = . - http_cache_dynamic
    
    str_range_hdr: .asciz "Range: bytes="
    str_if_range:  .asciz "If-Range: "
    str_head_method: .asciz "HEAD"
    
    .global http_status_200, len_status_200
    .global http_status_206, len_status_206
    .global http_resp_405, len_resp_405
    .global http_resp_413, len_resp_413
    .global http_conn_ka, len_conn_ka
    .global http_conn_close_hdr, len_conn_close_hdr
    .global http_etag_start, len_etag_start
    .global http_quote_newline, len_quote_newline
    .global etag_buffer
    .global http_accept_ranges, len_accept_ranges
    .global http_content_range_start, len_content_range_start
    .global http_cache_control_start, len_cache_control_start
    .global http_last_modified, len_last_modified
    .global http_x_forwarded_for, len_x_forwarded_for
    .global http_x_real_ip, len_x_real_ip
    .global http_vary, len_vary
    .global http_content_encoding_gzip, len_content_encoding_gzip
    .global http_cache_static, len_cache_static
    .global http_cache_dynamic, len_cache_dynamic
    .global str_range_hdr, str_if_range, str_head_method
    .global http_server_hdr_hidden, len_server_hdr_hidden
    
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

    str_debug_log:  .asciz "LOGREQ\n"
    .global str_debug_log

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

    dotdot:         .asciz ".."
    str_get:        .asciz "GET"
    str_post:       .asciz "POST"
    str_head:       .asciz "HEAD"
    str_unknown:    .asciz "REQ"
    str_conn_close: .asciz "Connection: close"

    /* Health check endpoint path and response */
    path_health:    .asciz "/health"
    http_health_resp:
        .ascii "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 15\r\nConnection: close\r\n\r\n"
        .ascii "{\"status\":\"ok\"}"
    len_health_resp = . - http_health_resp
    .global path_health, http_health_resp, len_health_resp


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

    /* Additional MIME Types */
    mime_gif:       .asciz "image/gif"
    len_mime_gif = . - mime_gif
    mime_webp:      .asciz "image/webp"
    len_mime_webp = . - mime_webp
    mime_avif:      .asciz "image/avif"
    len_mime_avif = . - mime_avif
    mime_bmp:       .asciz "image/bmp"
    len_mime_bmp = . - mime_bmp
    mime_mp4:       .asciz "video/mp4"
    len_mime_mp4 = . - mime_mp4
    mime_webm:      .asciz "video/webm"
    len_mime_webm = . - mime_webm
    mime_mp3:       .asciz "audio/mpeg"
    len_mime_mp3 = . - mime_mp3
    mime_wav:       .asciz "audio/wav"
    len_mime_wav = . - mime_wav
    mime_ogg:       .asciz "audio/ogg"
    len_mime_ogg = . - mime_ogg
    mime_flac:      .asciz "audio/flac"
    len_mime_flac = . - mime_flac
    mime_woff:      .asciz "font/woff"
    len_mime_woff = . - mime_woff
    mime_woff2:     .asciz "font/woff2"
    len_mime_woff2 = . - mime_woff2
    mime_ttf:       .asciz "font/ttf"
    len_mime_ttf = . - mime_ttf
    mime_otf:       .asciz "font/otf"
    len_mime_otf = . - mime_otf
    mime_wasm:      .asciz "application/wasm"
    len_mime_wasm = . - mime_wasm
    mime_zip:       .asciz "application/zip"
    len_mime_zip = . - mime_zip
    mime_gzip:      .asciz "application/gzip"
    len_mime_gzip = . - mime_gzip
    mime_tar:       .asciz "application/x-tar"
    len_mime_tar = . - mime_tar
    mime_csv:       .asciz "text/csv"
    len_mime_csv = . - mime_csv
    mime_md:        .asciz "text/markdown"
    len_mime_md = . - mime_md
    mime_yaml:      .asciz "text/yaml"
    len_mime_yaml = . - mime_yaml
    mime_map:       .asciz "application/json"
    len_mime_map = . - mime_map

    .global mime_gif, len_mime_gif, mime_webp, len_mime_webp, mime_avif, len_mime_avif
    .global mime_bmp, len_mime_bmp, mime_mp4, len_mime_mp4, mime_webm, len_mime_webm
    .global mime_mp3, len_mime_mp3, mime_wav, len_mime_wav, mime_ogg, len_mime_ogg
    .global mime_flac, len_mime_flac, mime_woff, len_mime_woff, mime_woff2, len_mime_woff2
    .global mime_ttf, len_mime_ttf, mime_otf, len_mime_otf, mime_wasm, len_mime_wasm
    .global mime_zip, len_mime_zip, mime_gzip, len_mime_gzip, mime_tar, len_mime_tar
    .global mime_csv, len_mime_csv, mime_md, len_mime_md, mime_yaml, len_mime_yaml
    .global mime_map, len_mime_map

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

    ext_gif:        .asciz ".gif"
    ext_webp:       .asciz ".webp"
    ext_avif:       .asciz ".avif"
    ext_bmp:        .asciz ".bmp"
    ext_mp4:        .asciz ".mp4"
    ext_webm:       .asciz ".webm"
    ext_mp3:        .asciz ".mp3"
    ext_wav:        .asciz ".wav"
    ext_ogg:        .asciz ".ogg"
    ext_flac:       .asciz ".flac"
    ext_woff:       .asciz ".woff"
    ext_woff2:      .asciz ".woff2"
    ext_ttf:        .asciz ".ttf"
    ext_otf:        .asciz ".otf"
    ext_wasm:       .asciz ".wasm"
    ext_zip:        .asciz ".zip"
    ext_gz:         .asciz ".gz"
    ext_tar:        .asciz ".tar"
    ext_csv:        .asciz ".csv"
    ext_md:         .asciz ".md"
    ext_yaml:       .asciz ".yaml"
    ext_yml:        .asciz ".yml"
    ext_map:        .asciz ".map"

    .global ext_htm, ext_jpeg, ext_mjs
    .global ext_gif, ext_webp, ext_avif, ext_bmp
    .global ext_mp4, ext_webm, ext_mp3, ext_wav, ext_ogg, ext_flac
    .global ext_woff, ext_woff2, ext_ttf, ext_otf
    .global ext_wasm, ext_zip, ext_gz, ext_tar
    .global ext_csv, ext_md, ext_yaml, ext_yml, ext_map

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
    client_ip_str:  .skip 32
    time_buffer:    .skip 32
    epoll_events:   .skip 512
    iovec_buffer:   .skip 256
    range_buffer:   .skip 128
    cache_ctrl_val: .skip 128
    index_name:     .skip 128
    error_page_path: .skip 256
    gzip_path_buf:  .skip 2048
    
    .align 8
    last_log_sec:   .skip 8
    timespec:       .skip 16
    
    .align 4
    act:            .skip 152
    content_len_str: .skip 32
    etag_buffer:    .skip 64
    sendfile_offset: .skip 8
    current_status: .skip 4
    access_log_path: .skip 256
    env_buffer:     .skip 4096
    req_method:     .skip 16
    
    /* Configuration variables */
    worker_count:   .skip 4
    keepalive_timeout_val: .skip 8
    client_max_body_val: .skip 8
    server_tokens_flag: .skip 4
    autoindex_flag: .skip 4
    gzip_static_flag: .skip 4
    is_head_request: .skip 4
    range_start:    .skip 8
    range_end:      .skip 8
    has_range:      .skip 4
    response_size:  .skip 8
    tcp_nopush_flag: .skip 4
    tcp_nodelay_flag: .skip 4
    
    .global current_status
    .global access_log_path
    .global query_string
    .global env_buffer
    .global log_fd
    .global key_access_log
    .global req_method
    .global worker_count, keepalive_timeout_val, client_max_body_val
    .global server_tokens_flag, autoindex_flag, gzip_static_flag
    .global is_head_request, range_start, range_end, has_range
    .global response_size, range_buffer, gzip_path_buf
    .global cache_ctrl_val, index_name, error_page_path
    .global tcp_nopush_flag, tcp_nodelay_flag

.data
    log_fd:         .word 1     /* Default to stdout (1) */
    
    /* Default configuration values */
    default_worker_count: .word 4       /* Default 4 workers */
    default_keepalive_timeout: .quad 65 /* Default 65 seconds (nginx default) */
    default_client_max_body: .quad 1048576 /* Default 1MB */
    default_server_tokens: .word 1      /* on by default */
    default_autoindex: .word 1          /* on by default */
    default_gzip_static: .word 0        /* off by default */
    default_tcp_nopush: .word 0
    default_tcp_nodelay: .word 1
    
    .global default_worker_count, default_keepalive_timeout, default_client_max_body
    .global default_server_tokens, default_autoindex, default_gzip_static
    .global default_tcp_nopush, default_tcp_nodelay
