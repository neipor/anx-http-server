/* src/http.s - Full Implementation */

.include "src/defs.s"

.global handle_client
.extern get_http_date

.text

/* ------------------------------------------------------------------------- */
/* handle_client(client_fd) */
/* ------------------------------------------------------------------------- */
handle_client:
    /* Stack Frame: 96 bytes */
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]

    mov x20, x0             /* Save client_fd */

    /* Resolve IP using getpeername */
    sub sp, sp, #32
    mov w0, #16
    str w0, [sp, #16]       /* addrlen */
    
    mov x0, x20             /* fd */
    mov x1, sp              /* sockaddr ptr */
    add x2, sp, #16         /* addrlen ptr */
    mov x8, SYS_GETPEERNAME
    svc #0
    
    cmp x0, #0
    bne ip_skip
    
    /* Convert IP (at sp + 4) */
    add x0, sp, #4
    ldr x1, =client_ip_str
    bl inet_ntoa

ip_skip:
    add sp, sp, #32

    mov x28, #1             /* x28 = keep_alive (1=true) */

hc_loop:
    /* 1. Read Request */
    mov x0, x20
    ldr x1, =req_buffer
    mov x2, #8191
    mov x8, SYS_READ
    svc #0

    cmp x0, #0
    ble hc_close_final
    strb wzr, [x1, x0]      /* Null terminate request */
    
    mov x25, x0             /* Save request length */

    /* Atomic request counter increment (shared stats page) */
    ldr x9, =stats_mmap_ptr
    ldr x9, [x9]
    cbz x9, hc_no_stats
hc_stats_inc:
    ldxr x10, [x9]
    add x10, x10, #1
    stxr w11, x10, [x9]
    cbnz w11, hc_stats_inc
hc_no_stats:

    /* Reset range flag for each new request */
    ldr x0, =has_range_request
    str wzr, [x0]

    /* 2. Parse Request */
    ldr x0, =req_buffer
    bl parse_request
    cmp x0, #0
    bne send_400

    /* 2.05 Detect HTTP Method */
    ldr x0, =req_buffer
    bl detect_method         /* returns method type in x0 */
    ldr x1, =current_method
    str w0, [x1]             /* save method type */
    
    /* Check for OPTIONS -> respond immediately */
    cmp w0, #METHOD_OPTIONS
    beq send_options
    
    /* Check for unsupported methods */
    cmp w0, #METHOD_UNKNOWN
    beq send_405

    /* Check /server-status */
    ldr x0, =req_path
    ldr x1, =path_server_status
    bl strcmp
    cmp x0, #0
    beq send_server_status

    /* 2.1 Check Proxy */
    ldr x0, =upstream_ip
    ldr w0, [x0]
    cbnz w0, handle_proxy   /* If upstream_ip != 0, proxy it */
    
    /* 2.5 Check Connection: close */
    ldr x0, =req_buffer
    ldr x1, =str_conn_close
    bl strstr
    cmp x0, #0
    beq check_trav
    mov x28, #0             /* Found Connection: close -> disable KA */

check_trav:
    /* 2.6 Detect Accept-Encoding: gzip */
    ldr x0, =req_buffer
    ldr x1, =str_accept_gzip
    bl strstr
    ldr x1, =client_accepts_gzip
    cmp x0, #0
    beq no_gzip_accept
    mov w2, #1
    str w2, [x1]
    b check_trav_real
no_gzip_accept:
    str wzr, [x1]

check_trav_real:
    /* 3. Security: Check Directory Traversal */
    ldr x0, =req_path
    bl check_traversal
    cmp x0, #0
    bne send_403
    
    /* 3.5 IP Access Control */
    ldr x0, =client_ip_str
    bl inet_aton             /* Convert IP string to network order */
    bl check_ip_access
    cbz x0, send_403        /* 0 = denied */
    
    /* 3.6 Rate Limiting */
    ldr x0, =client_ip_str
    bl inet_aton
    bl check_rate_limit
    cbz x0, send_429        /* 0 = rate limited */
    
    /* 3.65 Check server-level return directive */
    ldr x0, =return_code
    ldr w0, [x0]
    cbnz w0, send_redirect

    /* 3.7 Location Routing */
    ldr x0, =req_path
    bl match_location
    ldr x1, =matched_location
    str x0, [x1]            /* Save matched location (0 = none) */
    cbz x0, no_location_match
    
    /* Check if location has root override */
    ldr x1, [x1]
    add x2, x1, #64         /* LOC_ROOT_OFF */
    ldrb w3, [x2]
    cbz w3, loc_check_proxy /* No root override */
    
    /* Use location's root instead of server_root */
    ldr x0, =path_buffer
    mov x1, x2              /* location root */
    bl strcpy
    ldr x0, =path_buffer
    ldr x1, =req_path
    bl strcat
    b resolve_path
    
loc_check_proxy:
    /* Check if location has proxy_pass */
    ldr x1, =matched_location
    ldr x1, [x1]
    ldr w0, [x1, #320]      /* LOC_PROXY_IP_OFF */
    cbz w0, no_location_match
    
    /* Set upstream for this request */
    ldr x1, =upstream_ip
    str w0, [x1]
    ldr x1, =matched_location
    ldr x1, [x1]
    ldrh w0, [x1, #324]     /* LOC_PROXY_PORT_OFF */
    ldr x1, =upstream_port
    strh w0, [x1]
    b handle_proxy

no_location_match:

    /* 4. Resolve Path */
    /* Construct full path: server_root + req_path */
    ldr x27, =path_buffer
    
    ldr x0, =path_buffer    /* dst */
    ldr x1, =server_root    /* src */
    bl strcpy
    
    ldr x0, =path_buffer    /* dst */
    ldr x1, =req_path       /* src */
    bl strcat

resolve_path:
    ldr x27, =path_buffer

    /* 5. Stat File */
    mov x0, AT_FDCWD
    mov x1, x27             /* path_buffer */
    ldr x2, =stat_buffer
    mov x3, #0              /* flags */
    mov x8, SYS_NEWFSTATAT
    svc #0

    cmp x0, #0
    blt try_files_fallback   /* Not found -> try alternatives */

    /* 6. Check File Type */
    ldr x1, =stat_buffer
    ldr w2, [x1, #16]       /* st_mode */
    
    ldr w3, =S_IFMT
    and w3, w2, w3
    
    ldr w4, =S_IFDIR
    cmp w3, w4
    beq handle_dir
    
    ldr w4, =S_IFREG
    cmp w3, w4
    beq handle_file_load_size
    
    b send_403

/* ------------------------------------------------------------------------- */
/* try_files: Try $uri, $uri/index.html, then 404                           */
/* ------------------------------------------------------------------------- */
try_files_fallback:
    /* Try 1: $uri/index.html (common SPA/directory pattern) */
    ldr x0, =path_buffer
    ldr x1, =index_file       /* "/index.html" */
    bl strcat
    
    mov x0, AT_FDCWD
    ldr x1, =path_buffer
    ldr x2, =stat_buffer
    mov x3, #0
    mov x8, SYS_NEWFSTATAT
    svc #0
    cmp x0, #0
    bge handle_file_load_size  /* Found $uri/index.html */
    
    /* Try 2: Restore original path and try $uri.html */
    ldr x0, =path_buffer
    ldr x1, =server_root
    bl strcpy
    ldr x0, =path_buffer
    ldr x1, =req_path
    bl strcat
    ldr x0, =path_buffer
    ldr x1, =ext_html_suffix
    bl strcat
    
    mov x0, AT_FDCWD
    ldr x1, =path_buffer
    ldr x2, =stat_buffer
    mov x3, #0
    mov x8, SYS_NEWFSTATAT
    svc #0
    cmp x0, #0
    bge handle_file_load_size  /* Found $uri.html */
    
    /* Nothing found -> 404 */
    b send_404

/* ------------------------------------------------------------------------- */
/* Proxy Handling */
/* ------------------------------------------------------------------------- */
handle_proxy:
    bl connect_to_upstream
    cmp x0, #0
    blt send_502
    
    mov x21, x0             /* x21 = upstream_fd */
    
/* Forward Request with X-Forwarded-For */
    /* Find end of request line (first \r\n) */
    mov x0, x21
    ldr x1, =req_buffer
    ldr x2, =str_crlf
    /* Scan for \r\n */
    mov x3, x1              /* cursor */
xff_scan:
    ldrb w4, [x3]
    cbz w4, xff_fallback
    cmp w4, #0x0D
    bne xff_next
    ldrb w4, [x3, #1]
    cmp w4, #0x0A
    beq xff_found
xff_next:
    add x3, x3, #1
    b xff_scan
xff_found:
    add x3, x3, #2          /* past \r\n */
    /* Write request line (req_buffer .. x3) */
    mov x0, x21
    mov x1, x1              /* req_buffer */
    sub x2, x3, x1          /* bytes of first line + CRLF */
    mov x8, SYS_WRITE
    svc #0
    /* Write X-Forwarded-For header */
    mov x0, x21
    ldr x1, =hdr_x_fwd_for
    mov x2, #17             /* len_hdr_x_fwd_for */
    mov x8, SYS_WRITE
    svc #0
    mov x0, x21
    ldr x1, =client_ip_str
    bl strlen
    mov x2, x0
    mov x0, x21
    ldr x1, =client_ip_str
    mov x8, SYS_WRITE
    svc #0
    mov x0, x21
    ldr x1, =str_crlf
    mov x2, #2
    mov x8, SYS_WRITE
    svc #0
    /* Write rest of request (from x3 onwards) */
    mov x0, x21
    mov x1, x3
    ldr x4, =req_buffer
    sub x2, x25, x3
    add x2, x2, x4          /* remaining = total_len - (x3 - req_buffer) */
    cmp x2, #0
    ble xff_done
    mov x8, SYS_WRITE
    svc #0
    b xff_done
xff_fallback:
    /* Fallback: send whole request unmodified */
    mov x0, x21
    ldr x1, =req_buffer
    mov x2, x25
    mov x8, SYS_WRITE
    svc #0
xff_done:
    
    /* Relay Response Loop */
proxy_loop:
    mov x0, x21             /* upstream */
    ldr x1, =req_buffer     /* reuse buffer */
    mov x2, #8192
    mov x8, SYS_READ
    svc #0
    
    cmp x0, #0
    ble proxy_done          /* EOF or Error */
    
    mov x2, x0              /* bytes read */
    mov x25, x0             /* save len */
    
    mov x0, x20             /* client */
    ldr x1, =req_buffer
    mov x8, SYS_WRITE
    svc #0
    
    /* Check if upstream sent valid response and closed? */
    /* If upstream is HTTP/1.0 or sent Connection: close, it will close connection. */
    /* SYS_READ returns 0 on close, so checking ble proxy_done is correct. */
    /* Why did it hang? Maybe SYS_READ blocked? */
    /* The upstream (upstream_test server) might be keeping connection alive. */
    /* And we are in a loop reading from it. */
    /* If upstream keeps alive, it won't close. We wait for more data. */
    /* But the client (nc) might have closed its write end? */
    /* Ideally we should relay bidirectional or parse Content-Length. */
    /* Our simple proxy relies on upstream closing connection. */
    /* In the test: curl -H "Connection: close". Upstream sees this. */
    /* Upstream (ANX) sees "Connection: close", so it should close after sending response. */
    /* So upstream_fd read should return 0. */
    
    /* However, if upstream doesn't close, we hang here. */
    /* Let's verify if upstream actually closed. */
    /* If it hung, it means upstream is waiting for something or keeping alive. */
    
    b proxy_loop

proxy_done:
    /* Close Upstream */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    
    /* Log Proxy Access (Status 200? Or Unknown?) */
    ldr x0, =current_status
    mov w1, #0              /* 0 = Proxy */
    str w1, [x0]
    bl log_request  /* Uncommented logging */

    b hc_close_final

/* ------------------------------------------------------------------------- */
/* File Handling */
/* ------------------------------------------------------------------------- */
handle_file_load_size:
    ldr x1, =stat_buffer
    ldr x22, [x1, #48]      /* st_size */
    ldr x23, [x1, #88]      /* st_mtime */
    
    /* Generate ETag: Size(Hex)-Mtime(Hex) */
    ldr x26, =etag_buffer
    
    /* Size */
    mov x0, x22
    mov x1, x26
    bl itoa_hex
    add x26, x26, x0
    
    /* Dash */
    mov w2, #'-'
    strb w2, [x26], #1
    
    /* Mtime */
    mov x0, x23
    mov x1, x26
    bl itoa_hex
    add x26, x26, x0
    
    /* Null terminate */
    strb wzr, [x26]
    
    /* Calculate ETag Len */
    ldr x0, =etag_buffer
    sub x27, x26, x0         /* x27 = etag len */
    
    /* Check If-None-Match */
    ldr x0, =req_buffer
    ldr x1, =etag_buffer
    bl strstr
    cmp x0, #0
    beq serve_file          /* Not found */
    
    /* Found ETag string. Verify quotes around it? */
    /* x0 is match ptr. Check [x0-1] == '"' */
    ldrb w2, [x0, #-1]
    cmp w2, #'"'
    bne serve_file
    
    /* Check end quote [x0+x27] == '"' */
    add x0, x0, x27
    ldrb w2, [x0]
    cmp w2, #'"'
    bne serve_file
    
    /* Match! Send 304 */
    b send_304

handle_file:
    b serve_file

/* ------------------------------------------------------------------------- */
/* Directory Handling */
/* ------------------------------------------------------------------------- */
handle_dir:
    /* Check if index.html exists */
    ldr x0, =path_buffer
    ldr x1, =index_file
    bl strcat
    
    mov x0, AT_FDCWD
    ldr x1, =path_buffer
    ldr x2, =stat_buffer
    mov x3, #0
    mov x8, SYS_NEWFSTATAT
    svc #0
    
    cmp x0, #0
    beq handle_file_load_size         /* index.html exists -> serve it */
    
    /* Else -> Listing */
    ldr x0, =path_buffer    /* dst */
    ldr x1, =server_root    /* src */
    bl strcpy
    ldr x0, =path_buffer
    ldr x1, =req_path
    bl strcat
    
    mov x0, x20             /* client_fd */
    ldr x1, =path_buffer
    ldr x2, =req_path       /* relative path for links */
    bl serve_directory
    
    ldr x0, =current_status
    mov w1, #200
    str w1, [x0]
    bl log_request
    
    b hc_close_final

/* ------------------------------------------------------------------------- */
/* Serve File Logic */
/* ------------------------------------------------------------------------- */
serve_file:
    /* Parse Range header if present */
    ldr x0, =req_buffer
    ldr x1, =str_range_header
    bl strstr
    cbz x0, no_range_request

    /* x0 -> "Range: bytes=NNN-MMM", skip "Range: bytes=" (13 chars) */
    add x0, x0, #13
    mov x1, #0              /* start accumulator */
    mov x2, #10             /* decimal multiplier */
parse_range_start:
    ldrb w3, [x0], #1
    cmp w3, #'-'
    beq range_start_done
    sub w3, w3, #'0'
    cmp w3, #9
    bhi no_range_request    /* non-digit before '-': malformed */
    mul x1, x1, x2
    add x1, x1, x3
    b parse_range_start
range_start_done:
    ldr x4, =range_start
    str x1, [x4]

    /* Peek: if next char is \r or \n, it's an open-ended range */
    ldrb w3, [x0]
    cmp w3, #0x0d
    beq range_end_open
    cmp w3, #0x0a
    beq range_end_open
    cbz w3, range_end_open

    /* Parse end number */
    mov x1, #0
parse_range_end:
    ldrb w3, [x0], #1
    cmp w3, #0x0d
    beq range_end_done
    cmp w3, #0x0a
    beq range_end_done
    cbz w3, range_end_done
    sub w3, w3, #'0'
    cmp w3, #9
    bhi range_end_done      /* stop on non-digit */
    mul x1, x1, x2
    add x1, x1, x3
    b parse_range_end
    b range_end_done

range_end_open:
    mov x1, #-1             /* sentinel: "to end of file" */
range_end_done:
    ldr x4, =range_end
    str x1, [x4]
    mov w1, #1
    ldr x4, =has_range_request
    str w1, [x4]

no_range_request:
    /* Check gzip_static: if client accepts gzip, try file.gz */
    ldr x0, =client_accepts_gzip
    ldr w0, [x0]
    cbz w0, serve_file_direct
    
    /* Build path.gz */
    ldr x0, =gzip_path_buf
    ldr x1, =path_buffer
    bl strcpy
    ldr x0, =gzip_path_buf
    ldr x1, =ext_gz_suffix
    bl strcat
    
    /* Try to stat path.gz */
    mov x0, AT_FDCWD
    ldr x1, =gzip_path_buf
    ldr x2, =stat_buffer
    mov x3, #0
    mov x8, SYS_NEWFSTATAT
    svc #0
    cmp x0, #0
    bne serve_file_direct    /* .gz doesn't exist, serve normal */
    
    /* .gz exists! Open it instead */
    mov x0, AT_FDCWD
    ldr x1, =gzip_path_buf
    mov x2, O_RDONLY
    mov x3, #0
    mov x8, SYS_OPENAT
    svc #0
    cmp x0, #0
    blt serve_file_direct    /* Can't open .gz, fall through to normal */
    mov x21, x0             /* x21 = file_fd (gzipped version) */
    
    /* Get .gz file size */
    ldr x0, =stat_buffer
    ldr x22, [x0, #48]     /* st_size of .gz file */
    
    /* Set gzip flag */
    ldr x0, =serving_gzip
    mov w1, #1
    str w1, [x0]
    
    /* Still need MIME detection from original path */
    ldr x0, =path_buffer
    bl get_extension
    mov x19, x0
    cmp x19, #0
    beq set_mime_bin_gz
    b serve_file_mime
    
set_mime_bin_gz:
    ldr x25, =mime_bin
    mov x26, #24
    b send_response_gzip

serve_file_direct:
    /* Clear gzip flag */
    ldr x0, =serving_gzip
    str wzr, [x0]
    
    /* Open File */
    mov x0, AT_FDCWD
    ldr x1, =path_buffer
    mov x2, O_RDONLY
    mov x3, #0
    mov x8, SYS_OPENAT
    svc #0
    
    cmp x0, #0
    blt send_403
    mov x21, x0             /* x21 = file_fd */

    /* MIME Detection */
    ldr x0, =path_buffer
    bl get_extension
    mov x19, x0             /* x19 = ext ptr */
    
    cmp x19, #0
    beq set_mime_bin

serve_file_mime:
    /* Compare Extensions - full MIME type detection */
    mov x0, x19
    ldr x1, =ext_html
    bl strcmp
    cmp x0, #0
    beq set_mime_html

    mov x0, x19
    ldr x1, =ext_htm
    bl strcmp
    cmp x0, #0
    beq set_mime_html
    
    mov x0, x19
    ldr x1, =ext_css
    bl strcmp
    cmp x0, #0
    beq set_mime_css
    
    mov x0, x19
    ldr x1, =ext_js
    bl strcmp
    cmp x0, #0
    beq set_mime_js

    mov x0, x19
    ldr x1, =ext_mjs
    bl strcmp
    cmp x0, #0
    beq set_mime_js
    
    mov x0, x19
    ldr x1, =ext_json
    bl strcmp
    cmp x0, #0
    beq set_mime_json

    mov x0, x19
    ldr x1, =ext_png
    bl strcmp
    cmp x0, #0
    beq set_mime_png

    mov x0, x19
    ldr x1, =ext_jpg
    bl strcmp
    cmp x0, #0
    beq set_mime_jpg

    mov x0, x19
    ldr x1, =ext_jpeg
    bl strcmp
    cmp x0, #0
    beq set_mime_jpg

    mov x0, x19
    ldr x1, =ext_gif
    bl strcmp
    cmp x0, #0
    beq set_mime_gif

    mov x0, x19
    ldr x1, =ext_webp
    bl strcmp
    cmp x0, #0
    beq set_mime_webp

    mov x0, x19
    ldr x1, =ext_svg
    bl strcmp
    cmp x0, #0
    beq set_mime_svg

    mov x0, x19
    ldr x1, =ext_ico
    bl strcmp
    cmp x0, #0
    beq set_mime_ico

    mov x0, x19
    ldr x1, =ext_xml
    bl strcmp
    cmp x0, #0
    beq set_mime_xml

    mov x0, x19
    ldr x1, =ext_pdf
    bl strcmp
    cmp x0, #0
    beq set_mime_pdf

    mov x0, x19
    ldr x1, =ext_txt
    bl strcmp
    cmp x0, #0
    beq set_mime_txt

    mov x0, x19
    ldr x1, =ext_woff
    bl strcmp
    cmp x0, #0
    beq set_mime_woff

    mov x0, x19
    ldr x1, =ext_woff2
    bl strcmp
    cmp x0, #0
    beq set_mime_woff2

    mov x0, x19
    ldr x1, =ext_ttf
    bl strcmp
    cmp x0, #0
    beq set_mime_ttf

    mov x0, x19
    ldr x1, =ext_eot
    bl strcmp
    cmp x0, #0
    beq set_mime_eot

    mov x0, x19
    ldr x1, =ext_mp4
    bl strcmp
    cmp x0, #0
    beq set_mime_mp4

    mov x0, x19
    ldr x1, =ext_webm
    bl strcmp
    cmp x0, #0
    beq set_mime_webm

    mov x0, x19
    ldr x1, =ext_mp3
    bl strcmp
    cmp x0, #0
    beq set_mime_mp3

    mov x0, x19
    ldr x1, =ext_wav
    bl strcmp
    cmp x0, #0
    beq set_mime_wav

    mov x0, x19
    ldr x1, =ext_zip
    bl strcmp
    cmp x0, #0
    beq set_mime_zip

    mov x0, x19
    ldr x1, =ext_gz
    bl strcmp
    cmp x0, #0
    beq set_mime_gz

    mov x0, x19
    ldr x1, =ext_tar
    bl strcmp
    cmp x0, #0
    beq set_mime_tar

    mov x0, x19
    ldr x1, =ext_wasm
    bl strcmp
    cmp x0, #0
    beq set_mime_wasm

    mov x0, x19
    ldr x1, =ext_map
    bl strcmp
    cmp x0, #0
    beq set_mime_json

    /* Check .py / .sh / .cgi for CGI */
    mov x0, x19
    ldr x1, =ext_py
    bl strcmp
    cmp x0, #0
    beq invoke_cgi

    mov x0, x19
    ldr x1, =ext_sh
    bl strcmp
    cmp x0, #0
    beq invoke_cgi

    mov x0, x19
    ldr x1, =ext_cgi
    bl strcmp
    cmp x0, #0
    beq invoke_cgi
    
    /* Default: application/octet-stream */
    b set_mime_bin

invoke_cgi:
    mov x0, x20             /* client_fd */
    ldr x1, =path_buffer    /* script path */
    ldr x2, =req_buffer     /* request data */
    bl handle_cgi
    
    cmp x0, #0
    blt send_502
    
    /* Log CGI 200 */
    ldr x0, =current_status
    mov w1, #200
    str w1, [x0]
    bl log_request
    
    b hc_close_final

set_mime_html:
    ldr x25, =mime_html
    mov x26, #9
    b maybe_dynamic_gzip
set_mime_css:
    ldr x25, =mime_css
    mov x26, #8
    b maybe_dynamic_gzip
set_mime_js:
    ldr x25, =mime_js
    mov x26, #22
    b maybe_dynamic_gzip
set_mime_json:
    ldr x25, =mime_json
    mov x26, #16
    b maybe_dynamic_gzip
set_mime_png:
    ldr x25, =mime_png
    mov x26, #9
    b send_response
set_mime_jpg:
    ldr x25, =mime_jpg
    mov x26, #10
    b send_response
set_mime_gif:
    ldr x25, =mime_gif
    mov x26, #9
    b send_response
set_mime_webp:
    ldr x25, =mime_webp
    mov x26, #10
    b send_response
set_mime_svg:
    ldr x25, =mime_svg
    mov x26, #13
    b maybe_dynamic_gzip
set_mime_ico:
    ldr x25, =mime_ico
    mov x26, #12
    b send_response
set_mime_xml:
    ldr x25, =mime_xml
    mov x26, #15
    b maybe_dynamic_gzip
set_mime_pdf:
    ldr x25, =mime_pdf
    mov x26, #15
    b send_response
set_mime_txt:
    ldr x25, =mime_txt
    mov x26, #10
    b maybe_dynamic_gzip
set_mime_woff:
    ldr x25, =mime_woff
    mov x26, #17
    b send_response
set_mime_woff2:
    ldr x25, =mime_woff2
    mov x26, #13
    b send_response
set_mime_ttf:
    ldr x25, =mime_ttf
    mov x26, #9
    b send_response
set_mime_eot:
    ldr x25, =mime_eot
    mov x26, #39
    b send_response
set_mime_mp4:
    ldr x25, =mime_mp4
    mov x26, #9
    b send_response
set_mime_webm:
    ldr x25, =mime_webm
    mov x26, #10
    b send_response
set_mime_mp3:
    ldr x25, =mime_mp3
    mov x26, #10
    b send_response
set_mime_wav:
    ldr x25, =mime_wav
    mov x26, #9
    b send_response
set_mime_zip:
    ldr x25, =mime_zip
    mov x26, #15
    b send_response
set_mime_gz:
    ldr x25, =mime_gzip
    mov x26, #16
    b send_response
set_mime_tar:
    ldr x25, =mime_tar
    mov x26, #19
    b send_response
set_mime_wasm:
    ldr x25, =mime_wasm
    mov x26, #16
    b send_response
set_mime_bin:
    ldr x25, =mime_bin
    mov x26, #24
    b send_response

/* maybe_dynamic_gzip: called by text/* MIME types before send_response.
 * If client accepts gzip and no static .gz is being served, fork gzip.
 * Range requests always bypass dynamic gzip (go to send_response). */
maybe_dynamic_gzip:
    ldr x0, =has_range_request  /* Range takes priority */
    ldr w0, [x0]
    cbnz w0, send_response
    ldr x0, =client_accepts_gzip
    ldr w0, [x0]
    cbz w0, send_response
    ldr x0, =serving_gzip
    ldr w0, [x0]
    cbnz w0, send_response
    /* Check gzip_min_length: skip compression if file too small */
    ldr x0, =gzip_min_length
    ldr w0, [x0]
    cbz w0, mdgz_do          /* 0 = always gzip */
    cmp x22, x0
    blt send_response        /* file smaller than min_length */
mdgz_do:
    b serve_dynamic_gzip

send_response:
    /* Check if we're serving a gzip_static file */
    ldr x0, =serving_gzip
    ldr w0, [x0]
    cbnz w0, send_response_gzip

    /* Check for Range request (not supported for gzip_static) */
    ldr x0, =has_range_request
    ldr w0, [x0]
    cbnz w0, send_partial_content

    /* 1. Write HTTP header start (Status) */
    mov x0, x20
    ldr x1, =http_status_200
    ldr x2, =len_status_200
    mov x8, SYS_WRITE
    svc #0
    
    /* 1.2 Write Connection Header */
    cmp x28, #1
    beq send_ka
    ldr x1, =http_conn_close_hdr
    ldr x2, =len_conn_close_hdr
    b do_send_conn
send_ka:
    ldr x1, =http_conn_ka
    ldr x2, =len_conn_ka
do_send_conn:
    mov x0, x20
    mov x8, SYS_WRITE
    svc #0
    
    /* 1.5 Write Server Header (skip if server_tokens off) */
    ldr x0, =server_tokens
    ldr w0, [x0]
    cbz w0, sr_skip_server_hdr
    mov x0, x20
    ldr x1, =http_server_hdr
    ldr x2, =len_server_hdr
    mov x8, SYS_WRITE
    svc #0
sr_skip_server_hdr:

    /* 1.51 Write Date Header */
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl get_http_date
    ldp x29, x30, [sp], #16
    /* x0 = length of date string in http_date_buffer */
    mov x2, x0
    mov x0, x20
    ldr x1, =http_date_buffer
    mov x8, SYS_WRITE
    svc #0

    /* 1.55 Write ETag */
    mov x0, x20
    ldr x1, =http_etag_start
    ldr x2, =len_etag_start
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x20
    ldr x1, =etag_buffer
    mov x2, x27
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x20
    ldr x1, =http_quote_newline
    ldr x2, =len_quote_newline
    mov x8, SYS_WRITE
    svc #0

    /* 1.58 Emit custom add_header headers (format: Name: value\r\n) */
    /* Use x23/x24 as loop-persistent vars (callee-saved, already on handle_client's frame) */
    ldr x23, =add_headers_count
    ldr w23, [x23]           /* x23 = header count */
    cbz x23, sr_add_hdrs_done
    ldr x24, =add_headers_buf /* x24 = buffer base */
    mov x19, #0              /* x19 = loop index (callee-saved, safe across bl) */
sr_add_hdr_loop:
    cmp x19, x23
    bge sr_add_hdrs_done
    /* write name: strlen(slot+0) then write */
    lsl x12, x19, #8
    add x12, x24, x12        /* x12 = slot ptr */
    mov x0, x12              /* x0 = name ptr for strlen */
    bl strlen                /* x0 = name length; x19/x23/x24 preserved (callee-saved) */
    mov x2, x0               /* length */
    mov x0, x20              /* fd */
    lsl x12, x19, #8        /* recompute slot ptr (x12 may be clobbered by strlen) */
    add x12, x24, x12
    mov x1, x12              /* name ptr */
    mov x8, SYS_WRITE
    svc #0
    /* write ": " */
    mov x0, x20
    ldr x1, =str_header_sep
    mov x2, #2
    mov x8, SYS_WRITE
    svc #0
    /* write value: strlen(slot+64) then write */
    lsl x12, x19, #8
    add x12, x24, x12
    add x12, x12, #64        /* value offset */
    mov x0, x12              /* x0 = value ptr for strlen */
    bl strlen                /* x0 = value length */
    mov x2, x0
    mov x0, x20
    lsl x12, x19, #8        /* recompute slot ptr */
    add x12, x24, x12
    add x12, x12, #64
    mov x1, x12
    mov x8, SYS_WRITE
    svc #0
    /* write \r\n to terminate this header */
    mov x0, x20
    ldr x1, =str_crlf
    mov x2, #2
    mov x8, SYS_WRITE
    svc #0
    add x19, x19, #1
    b sr_add_hdr_loop
sr_add_hdrs_done:

    /* 1.6 Write Content-Type Label */
    mov x0, x20
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    mov x8, SYS_WRITE
    svc #0
    
    /* 2. Write MIME type */
    mov x0, x20
    mov x1, x25
    mov x2, x26
    mov x8, SYS_WRITE
    svc #0
    
    /* 3. Write Content-Length header */
    mov x0, x20
    ldr x1, =http_content_len
    mov x2, #18
    mov x8, SYS_WRITE
    svc #0
    
    /* 4. Write content length value */
    mov x0, x22
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    mov x8, SYS_WRITE
    svc #0
    
    /* 5. Write Accept-Ranges header */
    mov x0, x20
    ldr x1, =http_accept_ranges
    ldr x2, =len_accept_ranges
    mov x8, SYS_WRITE
    svc #0

    /* 5.2 Write Cache-Control header if expires_seconds set */
    ldr x0, =expires_seconds
    ldr x0, [x0]
    cmn x0, #1              /* cmp x0, #-1 */
    beq sr_no_cache_ctrl    /* -1 = disabled */
    cbnz x0, sr_cc_maxage
    /* 0 = no-cache */
    mov x0, x20
    ldr x1, =hdr_cache_no_cache
    mov x2, #52             /* len_hdr_cache_no_cache */
    mov x8, SYS_WRITE
    svc #0
    b sr_no_cache_ctrl
sr_cc_maxage:
    /* N = max-age=N */
    mov x9, x0              /* save seconds */
    mov x0, x20
    ldr x1, =hdr_cache_control
    mov x2, #25             /* len_hdr_cache_control */
    mov x8, SYS_WRITE
    svc #0
    mov x0, x9
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    mov x8, SYS_WRITE
    svc #0
sr_no_cache_ctrl:

    /* 5.5 Write header end */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0
    
    /* Check if HEAD request - skip body */
    ldr x0, =current_method
    ldr w0, [x0]
    cmp w0, #METHOD_HEAD
    beq head_skip_body

    /* 6. Send file content using sendfile (Loop) */
    ldr x0, =sendfile_offset
    str xzr, [x0]            /* offset = 0 */

sendfile_loop:
    cmp x22, #0
    ble sendfile_done

    mov x0, x20              /* out fd */
    mov x1, x21              /* in fd */
    ldr x2, =sendfile_offset /* offset ptr (updated by kernel) */
    mov x3, x22              /* count = remaining */
    mov x8, SYS_SENDFILE
    svc #0
    
    cmp x0, #0
    ble sendfile_done        /* Error (-1) or EOF (0) */
    
    sub x22, x22, x0         /* remaining -= sent */
    b sendfile_loop

head_skip_body:
sendfile_done:
    /* Close file */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    
    /* Log 200 */
    ldr x0, =current_status
    mov w1, #200
    str w1, [x0]
    bl log_request
    
    cmp x28, #1
    beq hc_loop
    b hc_close_final

/* =========================================================================
 * send_partial_content - Send 206 Partial Content response
 * Register conventions (same as send_response):
 *   x20 = client_fd, x21 = file_fd, x22 = total file_size
 *   x25 = mime ptr, x26 = mime len, x27 = etag len, x28 = keep-alive
 * ========================================================================= */
send_partial_content:
    /* Load and validate range bounds */
    ldr x9, =range_start
    ldr x9, [x9]
    ldr x10, =range_end
    ldr x10, [x10]
    mov x23, x22            /* x23 = total file size (callee-saved, preserved across bl calls) */

    /* Clamp range_end: if sentinel (-1) or >= file_size, use file_size - 1 */
    sub x11, x22, #1
    cmp x10, x22
    blt spc_range_end_ok
    mov x10, x11
spc_range_end_ok:
    /* 416 if range_start >= file_size */
    cmp x9, x22
    bge send_416
    /* 416 if range_end < range_start */
    cmp x10, x9
    blt send_416

    /* content_length = range_end - range_start + 1 */
    sub x22, x10, x9
    add x22, x22, #1

    /* --- Status line --- */
    mov x0, x20
    ldr x1, =http_206
    mov x2, #30             /* len("HTTP/1.1 206 Partial Content\r\n") */
    mov x8, SYS_WRITE
    svc #0

    /* --- Connection header --- */
    cmp x28, #1
    beq spc_ka
    ldr x1, =http_conn_close_hdr
    ldr x2, =len_conn_close_hdr
    b spc_conn
spc_ka:
    ldr x1, =http_conn_ka
    ldr x2, =len_conn_ka
spc_conn:
    mov x0, x20
    mov x8, SYS_WRITE
    svc #0

    /* --- Server header --- */
    mov x0, x20
    ldr x1, =http_server_hdr
    ldr x2, =len_server_hdr
    mov x8, SYS_WRITE
    svc #0

    /* --- Date header --- */
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl get_http_date
    ldp x29, x30, [sp], #16
    mov x2, x0
    mov x0, x20
    ldr x1, =http_date_buffer
    mov x8, SYS_WRITE
    svc #0

    /* --- Content-Type: label + MIME --- */
    mov x0, x20
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    mov x8, SYS_WRITE
    svc #0
    mov x0, x20
    mov x1, x25
    mov x2, x26
    mov x8, SYS_WRITE
    svc #0

    /* --- Content-Range: bytes START-END/TOTAL\r\n ---
     * http_content_range starts with "\r\n" which terminates Content-Type */
    mov x0, x20
    ldr x1, =http_content_range
    ldr x2, =len_content_range
    mov x8, SYS_WRITE
    svc #0

    /* Write range_start */
    mov x0, x9
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    mov x8, SYS_WRITE
    svc #0

    /* Write "-" */
    mov x0, x20
    ldr x1, =str_dash
    mov x2, #1
    mov x8, SYS_WRITE
    svc #0

    /* Write range_end */
    mov x0, x10
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    mov x8, SYS_WRITE
    svc #0

    /* Write "/" */
    mov x0, x20
    ldr x1, =str_slash
    mov x2, #1
    mov x8, SYS_WRITE
    svc #0

    /* Write total file size */
    mov x0, x23
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    mov x8, SYS_WRITE
    svc #0

    /* --- Content-Length: content_length ---
     * http_content_len starts with \r\n which terminates Content-Range line */
    mov x0, x20
    ldr x1, =http_content_len  /* "\r\nContent-Length: " */
    mov x2, #18
    mov x8, SYS_WRITE
    svc #0
    mov x0, x22
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    mov x8, SYS_WRITE
    svc #0

    /* --- Accept-Ranges: bytes + end of headers --- */
    mov x0, x20
    ldr x1, =http_accept_ranges  /* "\r\nAccept-Ranges: bytes" */
    ldr x2, =len_accept_ranges
    mov x8, SYS_WRITE
    svc #0
    mov x0, x20
    ldr x1, =http_end            /* "\r\n\r\n" */
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0

    /* Skip body for HEAD requests */
    ldr x0, =current_method
    ldr w0, [x0]
    cmp w0, #METHOD_HEAD
    beq spc_done

    /* --- Send partial body via sendfile with offset --- */
    ldr x0, =sendfile_offset
    str x9, [x0]            /* offset = range_start */
spc_sendfile_loop:
    cmp x22, #0
    ble spc_done
    mov x0, x20
    mov x1, x21
    ldr x2, =sendfile_offset
    mov x3, x22
    mov x8, SYS_SENDFILE
    svc #0
    cmp x0, #0
    ble spc_done
    sub x22, x22, x0
    b spc_sendfile_loop

spc_done:
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0

    ldr x0, =current_status
    mov w1, #206
    str w1, [x0]
    bl log_request

    cmp x28, #1
    beq hc_loop
    b hc_close_final

send_416:
    /* Close file before sending error response */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0

    mov x0, x20
    ldr x1, =http_416
    ldr x2, =len_416
    mov x8, SYS_WRITE
    svc #0

    ldr x0, =current_status
    mov w1, #416
    str w1, [x0]
    bl log_request
    b hc_close_final

/* =========================================================================
 * send_response_gzip - Send response with Content-Encoding: gzip
 * Uses same register conventions as send_response:
 *   x20 = client_fd, x21 = file_fd, x22 = file_size
 *   x25 = mime ptr, x26 = mime len, x27 = etag len, x28 = keep-alive
 * ========================================================================= */
send_response_gzip:
    /* Status line */
    mov x0, x20
    ldr x1, =http_status_200
    ldr x2, =len_status_200
    mov x8, SYS_WRITE
    svc #0
    
    /* Connection header */
    cmp x28, #1
    beq srg_ka
    ldr x1, =http_conn_close_hdr
    ldr x2, =len_conn_close_hdr
    b srg_conn
srg_ka:
    ldr x1, =http_conn_ka
    ldr x2, =len_conn_ka
srg_conn:
    mov x0, x20
    mov x8, SYS_WRITE
    svc #0
    
    /* Server header */
    mov x0, x20
    ldr x1, =http_server_hdr
    ldr x2, =len_server_hdr
    mov x8, SYS_WRITE
    svc #0
    
    /* Date header */
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl get_http_date
    ldp x29, x30, [sp], #16
    mov x2, x0
    mov x0, x20
    ldr x1, =http_date_buffer
    mov x8, SYS_WRITE
    svc #0
    
    /* Content-Type */
    mov x0, x20
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    mov x8, SYS_WRITE
    svc #0
    mov x0, x20
    mov x1, x25
    mov x2, x26
    mov x8, SYS_WRITE
    svc #0
    
    /* Content-Encoding: gzip */
    mov x0, x20
    ldr x1, =http_content_encoding_gzip
    ldr x2, =len_content_encoding_gzip
    mov x8, SYS_WRITE
    svc #0
    
    /* Content-Length */
    mov x0, x20
    ldr x1, =http_content_len
    mov x2, #18
    mov x8, SYS_WRITE
    svc #0
    mov x0, x22
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    mov x8, SYS_WRITE
    svc #0
    
    /* Vary: Accept-Encoding (important for caching) */
    mov x0, x20
    ldr x1, =http_vary_encoding
    ldr x2, =len_vary_encoding
    mov x8, SYS_WRITE
    svc #0
    
    /* End headers */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0
    
    /* Check HEAD */
    ldr x0, =current_method
    ldr w0, [x0]
    cmp w0, #METHOD_HEAD
    beq srg_done
    
    /* Sendfile loop */
    ldr x0, =sendfile_offset
    str xzr, [x0]
srg_send:
    cmp x22, #0
    ble srg_done
    mov x0, x20
    mov x1, x21
    ldr x2, =sendfile_offset
    mov x3, x22
    mov x8, SYS_SENDFILE
    svc #0
    cmp x0, #0
    ble srg_done
    sub x22, x22, x0
    b srg_send

srg_done:
    /* Close file */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    
    /* Log 200 */
    ldr x0, =current_status
    mov w1, #200
    str w1, [x0]
    bl log_request
    
    cmp x28, #1
    beq hc_loop
    b hc_close_final

send_304:
    mov x0, x20
    ldr x1, =http_304
    ldr x2, =len_304
    mov x8, SYS_WRITE
    svc #0
    
    /* 304 ETag */
    mov x0, x20
    ldr x1, =http_etag_start
    ldr x2, =len_etag_start
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x20
    ldr x1, =etag_buffer
    mov x2, x27
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x20
    ldr x1, =http_quote_newline
    ldr x2, =len_quote_newline
    mov x8, SYS_WRITE
    svc #0
    
    /* Log 304 */
    ldr x0, =current_status
    mov w1, #304
    str w1, [x0]
    bl log_request
    
    cmp x28, #1
    beq hc_loop
    b hc_close_final

/* ------------------------------------------------------------------------- */
/* Error Handlers */
/* ------------------------------------------------------------------------- */

/* send_redirect: send 301/302/307 redirect using return_code / return_url_buf */
send_redirect:
    ldr x9, =return_code
    ldr w9, [x9]
    /* Select status line based on code */
    cmp w9, #301
    bne srd_try302
    mov x0, x20
    ldr x1, =http_redirect_301
    mov x2, #42
    b srd_send_status
srd_try302:
    cmp w9, #302
    bne srd_try307
    mov x0, x20
    ldr x1, =http_redirect_302
    mov x2, #30
    b srd_send_status
srd_try307:
    mov x0, x20
    ldr x1, =http_redirect_307
    mov x2, #43
srd_send_status:
    mov x8, SYS_WRITE
    svc #0
    /* Write URL */
    ldr x1, =return_url_buf
    mov x0, x1              /* x0 = string ptr for strlen */
    bl strlen
    mov x2, x0
    mov x0, x20
    ldr x1, =return_url_buf
    mov x8, SYS_WRITE
    svc #0
    /* Write end of redirect response */
    mov x0, x20
    ldr x1, =http_redirect_end
    mov x2, #42             /* len_redirect_end */
    mov x8, SYS_WRITE
    svc #0
    ldr x0, =current_status
    ldr w1, [x9]
    str w1, [x0]            /* log the redirect code */
    ldr x1, =return_code
    ldr w1, [x1]
    ldr x0, =current_status
    str w1, [x0]
    bl log_request
    b hc_close_final

send_400:
    mov x0, x20
    ldr x1, =http_400
    ldr x2, =len_400
    mov x8, SYS_WRITE
    svc #0
    
    ldr x0, =current_status
    mov w1, #400
    str w1, [x0]
    bl log_request
    b hc_close_final

send_403:
    mov x0, x20
    ldr x1, =http_403
    ldr x2, =len_403
    mov x8, SYS_WRITE
    svc #0
    
    ldr x0, =current_status
    mov w1, #403
    str w1, [x0]
    bl log_request
    b hc_close_final

send_404:
    /* Check custom error page for 404 */
    ldr x0, =custom_error_code
    ldr w0, [x0]
    cmp w0, #404
    bne send_404_default

    /* Build full path: server_root + custom_error_path */
    ldr x0, =path_buffer
    ldr x1, =server_root
    bl strcpy
    ldr x0, =path_buffer
    ldr x1, =custom_error_path
    bl strcat

    /* Open the custom error file */
    mov x0, AT_FDCWD
    ldr x1, =path_buffer
    mov x2, #O_RDONLY
    mov x3, #0
    mov x8, SYS_OPENAT
    svc #0
    cmp x0, #0
    blt send_404_default

    mov x21, x0                 /* x21 = file_fd */

    /* Stat file to get size */
    mov x0, AT_FDCWD
    ldr x1, =path_buffer
    ldr x2, =stat_buffer
    mov x3, #0
    mov x8, SYS_NEWFSTATAT
    svc #0
    ldr x0, =stat_buffer
    ldr x22, [x0, #48]          /* x22 = st_size */

    /* Send 404 status line */
    mov x0, x20
    ldr x1, =http_status_404
    mov x2, #24                 /* len("HTTP/1.1 404 Not Found\r\n") */
    mov x8, SYS_WRITE
    svc #0

    /* Server header */
    mov x0, x20
    ldr x1, =http_server_hdr
    ldr x2, =len_server_hdr
    mov x8, SYS_WRITE
    svc #0

    /* Content-Type: text/html */
    mov x0, x20
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    mov x8, SYS_WRITE
    svc #0
    mov x0, x20
    ldr x1, =mime_html
    mov x2, #9
    mov x8, SYS_WRITE
    svc #0

    /* Content-Length: N */
    mov x0, x20
    ldr x1, =http_content_len
    mov x2, #18
    mov x8, SYS_WRITE
    svc #0
    mov x0, x22
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    mov x8, SYS_WRITE
    svc #0

    /* End of headers */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0

    /* Send file body via sendfile loop */
    ldr x0, =sendfile_offset
    str xzr, [x0]
send_custom_404_body:
    cmp x22, #0
    ble send_custom_404_done
    mov x0, x20
    mov x1, x21
    ldr x2, =sendfile_offset
    mov x3, x22
    mov x8, SYS_SENDFILE
    svc #0
    cmp x0, #0
    ble send_custom_404_done
    sub x22, x22, x0
    b send_custom_404_body
send_custom_404_done:
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0

    ldr x0, =current_status
    mov w1, #404
    str w1, [x0]
    bl log_request
    b hc_close_final

send_404_default:
    mov x0, x20
    ldr x1, =http_404
    ldr x2, =len_404
    mov x8, SYS_WRITE
    svc #0

    ldr x0, =current_status
    mov w1, #404
    str w1, [x0]
    bl log_request
    b hc_close_final

send_502:
    mov x0, x20
    ldr x1, =http_502
    ldr x2, =len_502
    mov x8, SYS_WRITE
    svc #0
    
    ldr x0, =current_status
    mov w1, #502
    str w1, [x0]
    bl log_request
    b hc_close_final

send_options:
    mov x0, x20
    ldr x1, =http_options_resp
    ldr x2, =len_options_resp
    mov x8, SYS_WRITE
    svc #0
    
    ldr x0, =current_status
    mov w1, #200
    str w1, [x0]
    bl log_request
    cmp x28, #1
    beq hc_loop
    b hc_close_final

send_405:
    mov x0, x20
    ldr x1, =http_405
    ldr x2, =len_405
    mov x8, SYS_WRITE
    svc #0
    
    ldr x0, =current_status
    mov w1, #405
    str w1, [x0]
    bl log_request
    b hc_close_final

send_429:
    mov x0, x20
    ldr x1, =http_429
    ldr x2, =len_429
    mov x8, SYS_WRITE
    svc #0
    
    ldr x0, =current_status
    mov w1, #429
    str w1, [x0]
    bl log_request
    b hc_close_final

send_server_status:
    mov x0, x20
    ldr x1, =http_status_200
    ldr x2, =len_status_200
    mov x8, SYS_WRITE
    svc #0

    mov x0, x20
    ldr x1, =server_status_hdr
    ldr x2, =len_server_status_hdr
    mov x8, SYS_WRITE
    svc #0

    /* Build dynamic JSON with request counter */
    ldr x9, =stats_mmap_ptr
    ldr x9, [x9]
    mov x10, #0             /* default counter = 0 */
    cbz x9, sss_no_stats
    ldr x10, [x9]           /* request_total */
sss_no_stats:
    /* Write JSON prefix */
    mov x0, x20
    ldr x1, =ss_json_prefix
    ldr x2, =len_ss_json_prefix
    mov x8, SYS_WRITE
    svc #0
    /* Write request count */
    mov x0, x10
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    mov x8, SYS_WRITE
    svc #0
    /* Write worker count */
    mov x0, x20
    ldr x1, =ss_json_mid
    ldr x2, =len_ss_json_mid
    mov x8, SYS_WRITE
    svc #0
    ldr x0, =worker_count
    ldr w0, [x0]
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    mov x8, SYS_WRITE
    svc #0
    /* Write JSON suffix */
    mov x0, x20
    ldr x1, =ss_json_suffix
    ldr x2, =len_ss_json_suffix
    mov x8, SYS_WRITE
    svc #0

    ldr x0, =current_status
    mov w1, #200
    str w1, [x0]
    bl log_request

    cmp x28, #1
    beq hc_loop
    b hc_close_final

hc_close_final:
    /* Unregister from epoll */
    ldr x0, =epoll_fd
    ldr w0, [x0]
    mov x1, #EPOLL_CTL_DEL
    mov x2, x20
    mov x3, #0
    mov x8, SYS_EPOLL_CTL
    svc #0

    mov x0, x20
    mov x8, SYS_CLOSE
    svc #0
    
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

/* ------------------------------------------------------------------------- */
/* Helpers */
/* ------------------------------------------------------------------------- */
parse_request:
    /* Find space */
    mov x1, x0
    mov x2, #0
pr_loop:
    ldrb w3, [x1, x2]
    cbz w3, pr_err
    cmp w3, #32     /* Space */
    beq pr_found_method
    add x2, x2, #1
    cmp x2, #10     /* Method too long? */
    bge pr_err
    b pr_loop
pr_found_method:
    add x1, x1, x2  /* Space after method */
    add x1, x1, #1  /* Start of path */
    
    /* Copy path to req_path */
    ldr x4, =req_path
    mov x5, #0
pr_path_loop:
    ldrb w3, [x1, x5]
    cbz w3, pr_done
    cmp w3, #32     /* Space */
    beq pr_path_done
    cmp w3, #63     /* '?' */
    beq pr_split_query
    strb w3, [x4, x5]
    add x5, x5, #1
    cmp x5, #255
    bge pr_path_done
    b pr_path_loop

pr_split_query:
    strb wzr, [x4, x5] /* Terminate req_path */
    add x1, x1, x5
    add x1, x1, #1  /* Start of query */
    ldr x4, =query_string
    mov x5, #0
pr_query_loop:
    ldrb w3, [x1, x5]
    cbz w3, pr_done
    cmp w3, #32
    beq pr_query_done
    strb w3, [x4, x5]
    add x5, x5, #1
    cmp x5, #255
    bge pr_query_done
    b pr_query_loop
pr_query_done:
    strb wzr, [x4, x5]
    mov x0, #0
    ret

pr_path_done:
    strb wzr, [x4, x5] /* Null terminate */
    
    /* Ensure query_string is empty if no '?' */
    ldr x4, =query_string
    strb wzr, [x4]
    
    /* Check if path is empty -> / */
    cmp x5, #0
    bne pr_ok
    ldr x4, =req_path
    mov w3, #47     /* / */
    strb w3, [x4]
    strb wzr, [x4, #1]
    
pr_ok:
    mov x0, #0
    ret
pr_done:
    strb wzr, [x4, x5]
    b pr_ok

pr_err:
    mov x0, #-1
    ret

check_traversal:
    mov x1, x0
    mov x2, #0
ct_loop:
    ldrb w3, [x1, x2]
    cbz w3, ct_ok
    cmp w3, #46     /* . */
    beq ct_dot
    cmp w3, #47     /* / */
    beq ct_slash
    add x2, x2, #1
    b ct_loop
ct_slash:
    add x2, x2, #1
    ldrb w3, [x1, x2]
    cmp w3, #46     /* . */
    bne ct_loop
    add x2, x2, #1
    ldrb w3, [x1, x2]
    cmp w3, #46     /* . */
    beq ct_fail
    b ct_loop
ct_dot:
    add x2, x2, #1
    ldrb w3, [x1, x2]
    cmp w3, #46     /* . */
    beq ct_fail
    b ct_loop
ct_ok:
    mov x0, #0
    ret
ct_fail:
    mov x0, #-1
    ret

/* detect_method(req_buffer) -> method type in x0 */
/* Method constants: GET=1, HEAD=2, POST=3, PUT=4, DELETE=5, OPTIONS=6, PATCH=7, UNKNOWN=0 */
.equ METHOD_GET, 1
.equ METHOD_HEAD, 2
.equ METHOD_POST, 3
.equ METHOD_PUT, 4
.equ METHOD_DELETE, 5
.equ METHOD_OPTIONS, 6
.equ METHOD_PATCH, 7
.equ METHOD_UNKNOWN, 0

detect_method:
    /* Check first byte to fast-path */
    ldrb w1, [x0]
    
    /* 'G' = 0x47 -> GET */
    cmp w1, #'G'
    beq dm_check_get
    /* 'H' = 0x48 -> HEAD */
    cmp w1, #'H'
    beq dm_check_head
    /* 'P' = 0x50 -> POST, PUT, PATCH */
    cmp w1, #'P'
    beq dm_check_p
    /* 'D' = 0x44 -> DELETE */
    cmp w1, #'D'
    beq dm_check_delete
    /* 'O' = 0x4F -> OPTIONS */
    cmp w1, #'O'
    beq dm_check_options
    
    mov x0, #METHOD_UNKNOWN
    ret

dm_check_get:
    ldrb w1, [x0, #1]
    cmp w1, #'E'
    bne dm_unknown
    ldrb w1, [x0, #2]
    cmp w1, #'T'
    bne dm_unknown
    ldrb w1, [x0, #3]
    cmp w1, #' '
    bne dm_unknown
    mov x0, #METHOD_GET
    ret

dm_check_head:
    ldrb w1, [x0, #1]
    cmp w1, #'E'
    bne dm_unknown
    ldrb w1, [x0, #2]
    cmp w1, #'A'
    bne dm_unknown
    ldrb w1, [x0, #3]
    cmp w1, #'D'
    bne dm_unknown
    ldrb w1, [x0, #4]
    cmp w1, #' '
    bne dm_unknown
    mov x0, #METHOD_HEAD
    ret

dm_check_p:
    ldrb w1, [x0, #1]
    cmp w1, #'O'
    beq dm_check_post
    cmp w1, #'U'
    beq dm_check_put
    cmp w1, #'A'
    beq dm_check_patch
    b dm_unknown

dm_check_post:
    ldrb w1, [x0, #2]
    cmp w1, #'S'
    bne dm_unknown
    ldrb w1, [x0, #3]
    cmp w1, #'T'
    bne dm_unknown
    ldrb w1, [x0, #4]
    cmp w1, #' '
    bne dm_unknown
    mov x0, #METHOD_POST
    ret

dm_check_put:
    ldrb w1, [x0, #2]
    cmp w1, #'T'
    bne dm_unknown
    ldrb w1, [x0, #3]
    cmp w1, #' '
    bne dm_unknown
    mov x0, #METHOD_PUT
    ret

dm_check_delete:
    ldrb w1, [x0, #1]
    cmp w1, #'E'
    bne dm_unknown
    ldrb w1, [x0, #2]
    cmp w1, #'L'
    bne dm_unknown
    ldrb w1, [x0, #3]
    cmp w1, #'E'
    bne dm_unknown
    ldrb w1, [x0, #4]
    cmp w1, #'T'
    bne dm_unknown
    ldrb w1, [x0, #5]
    cmp w1, #'E'
    bne dm_unknown
    ldrb w1, [x0, #6]
    cmp w1, #' '
    bne dm_unknown
    mov x0, #METHOD_DELETE
    ret

dm_check_options:
    ldrb w1, [x0, #1]
    cmp w1, #'P'
    bne dm_unknown
    ldrb w1, [x0, #2]
    cmp w1, #'T'
    bne dm_unknown
    ldrb w1, [x0, #3]
    cmp w1, #'I'
    bne dm_unknown
    ldrb w1, [x0, #4]
    cmp w1, #'O'
    bne dm_unknown
    ldrb w1, [x0, #5]
    cmp w1, #'N'
    bne dm_unknown
    ldrb w1, [x0, #6]
    cmp w1, #'S'
    bne dm_unknown
    ldrb w1, [x0, #7]
    cmp w1, #' '
    bne dm_unknown
    mov x0, #METHOD_OPTIONS
    ret

dm_check_patch:
    ldrb w1, [x0, #2]
    cmp w1, #'T'
    bne dm_unknown
    ldrb w1, [x0, #3]
    cmp w1, #'C'
    bne dm_unknown
    ldrb w1, [x0, #4]
    cmp w1, #'H'
    bne dm_unknown
    ldrb w1, [x0, #5]
    cmp w1, #' '
    bne dm_unknown
    mov x0, #METHOD_PATCH
    ret

dm_unknown:
    mov x0, #METHOD_UNKNOWN
    ret


/* serve_dynamic_gzip: on-the-fly gzip via /bin/gzip child process.
 * x20=client_fd, x21=file_fd, x25=mime_ptr, x26=mime_len, x28=keep_alive */
serve_dynamic_gzip:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]

    /* pipe2(gzip_pipe_fds, 0) */
    ldr x0, =gzip_pipe_fds
    mov x1, #0
    mov x8, SYS_PIPE2
    svc #0
    cmp x0, #0
    blt sdgz_fallback

    ldr x0, =gzip_pipe_fds
    ldr w23, [x0]               /* pipe_read */
    ldr w24, [x0, #4]           /* pipe_write */

    /* mmap 8KB stack for child */
    mov x0, #0
    mov x1, #8192
    mov x2, #(PROT_READ|PROT_WRITE)
    mov x3, #(MAP_PRIVATE|MAP_ANONYMOUS)
    orr x3, x3, #MAP_STACK
    mov x4, #-1
    mov x5, #0
    mov x8, SYS_MMAP
    svc #0
    cmp x0, #0
    blt sdgz_close_pipe
    add x27, x0, #8192

    /* clone(SIGCHLD, stack_top) */
    mov x0, #SIGCHLD_FLAG
    mov x1, x27
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov x8, SYS_CLONE
    svc #0
    cmp x0, #0
    blt sdgz_close_pipe
    bne sdgz_parent

    /* ---- CHILD ---- */
    mov x0, x23
    mov x8, SYS_CLOSE
    svc #0
    mov x0, x24
    mov x1, #1
    mov x2, #0
    mov x8, SYS_DUP3
    svc #0
    mov x0, x21
    mov x1, #0
    mov x2, #0
    mov x8, SYS_DUP3
    svc #0
    sub sp, sp, #32
    ldr x0, =gzip_arg0
    str x0, [sp]
    ldr x0, =gzip_argc
    str x0, [sp, #8]
    str xzr, [sp, #16]
    ldr x0, =gzip_bin
    mov x1, sp
    mov x2, #0
    mov x8, SYS_EXECVE
    svc #0
    mov x0, #1
    mov x8, SYS_EXIT
    svc #0

sdgz_parent:
    mov x19, x0                 /* child pid */
    /* Close pipe_write and file_fd in parent */
    mov x0, x24
    mov x8, SYS_CLOSE
    svc #0
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0

    /* HTTP/1.1 200 OK */
    mov x0, x20
    ldr x1, =http_status_200
    ldr x2, =len_status_200
    mov x8, SYS_WRITE
    svc #0
    /* Server header */
    mov x0, x20
    ldr x1, =http_server_hdr
    ldr x2, =len_server_hdr
    mov x8, SYS_WRITE
    svc #0
    /* Content-Type: <mime> */
    mov x0, x20
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    mov x8, SYS_WRITE
    svc #0
    mov x0, x20
    mov x1, x25
    mov x2, x26
    mov x8, SYS_WRITE
    svc #0
    /* "\r\n" after MIME value */
    sub sp, sp, #16
    mov w0, #0x0d
    strb w0, [sp]
    mov w0, #0x0a
    strb w0, [sp, #1]
    mov x0, x20
    mov x1, sp
    mov x2, #2
    mov x8, SYS_WRITE
    svc #0
    add sp, sp, #16
    /* Content-Encoding: gzip + Transfer-Encoding: chunked */
    mov x0, x20
    ldr x1, =dgzip_ce_hdr
    ldr x2, =dgzip_ce_len
    mov x8, SYS_WRITE
    svc #0
    /* Connection */
    cmp x28, #1
    bne sdgz_conn_close
    mov x0, x20
    ldr x1, =http_conn_ka
    ldr x2, =len_conn_ka
    mov x8, SYS_WRITE
    svc #0
    b sdgz_end_headers
sdgz_conn_close:
    mov x0, x20
    ldr x1, =http_conn_close_hdr
    ldr x2, =len_conn_close_hdr
    mov x8, SYS_WRITE
    svc #0
sdgz_end_headers:
    /* blank line */
    sub sp, sp, #16
    mov w0, #0x0d
    strb w0, [sp]
    mov w0, #0x0a
    strb w0, [sp, #1]
    mov x0, x20
    mov x1, sp
    mov x2, #2
    mov x8, SYS_WRITE
    svc #0
    add sp, sp, #16

sdgz_chunk_loop:
    mov x0, x23
    ldr x1, =gzip_chunk_buf
    mov x2, #8192
    mov x8, SYS_READ
    svc #0
    cmp x0, #0
    ble sdgz_chunk_done
    mov x22, x0
    /* hex size + \r\n */
    sub sp, sp, #32
    mov x0, x22
    mov x1, sp
    bl itoa_hex
    mov x2, x0
    mov x0, x20
    mov x1, sp
    mov x8, SYS_WRITE
    svc #0
    add sp, sp, #32
    sub sp, sp, #16
    mov w0, #0x0d
    strb w0, [sp]
    mov w0, #0x0a
    strb w0, [sp, #1]
    mov x0, x20
    mov x1, sp
    mov x2, #2
    mov x8, SYS_WRITE
    svc #0
    add sp, sp, #16
    /* chunk data */
    mov x0, x20
    ldr x1, =gzip_chunk_buf
    mov x2, x22
    mov x8, SYS_WRITE
    svc #0
    /* \r\n */
    sub sp, sp, #16
    mov w0, #0x0d
    strb w0, [sp]
    mov w0, #0x0a
    strb w0, [sp, #1]
    mov x0, x20
    mov x1, sp
    mov x2, #2
    mov x8, SYS_WRITE
    svc #0
    add sp, sp, #16
    b sdgz_chunk_loop

sdgz_chunk_done:
    /* "0\r\n\r\n" */
    mov x0, x20
    ldr x1, =dgzip_final_chunk
    ldr x2, =dgzip_final_len
    mov x8, SYS_WRITE
    svc #0
    /* close pipe_read */
    mov x0, x23
    mov x8, SYS_CLOSE
    svc #0
    /* wait for child */
    sub sp, sp, #16
    mov x0, x19
    mov x1, sp
    mov x2, #0
    mov x3, #0
    mov x8, SYS_WAIT4
    svc #0
    add sp, sp, #16
    /* log */
    ldr x0, =current_status
    mov w1, #200
    str w1, [x0]
    bl log_request

    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    cmp x28, #1
    beq hc_loop
    b hc_close_final

sdgz_close_pipe:
    mov x0, x23
    mov x8, SYS_CLOSE
    svc #0
    mov x0, x24
    mov x8, SYS_CLOSE
    svc #0
sdgz_fallback:
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    b send_response
