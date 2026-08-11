/* src/http.s - HTTP request handling: fast path + slow path
 *
 * Two entry points share one body of code and one 96-byte frame layout:
 *
 *   conn_serve(x0=conn)   FAST path, called synchronously by the event loop in
 *                         conn.s. The request head is already in req_buffer, so
 *                         this run is pure CPU: every write aimed at the client
 *                         goes through conn_sink_write into conn->out_buf, file
 *                         bodies are handed over as conn->file_fd/off/rem, and
 *                         the function returns a disposition code:
 *                           0 = done, keep-alive (CONN_F_KEEPALIVE set)
 *                           1 = done, close once the output has drained
 *                           3 = slow path forked, conn slot already released
 *
 *   handle_client(x0=fd)  SLOW path, running inside a forked child with
 *                         slow_child_mode=1 on a blocking socket. Original
 *                         synchronous behaviour, keep-alive read loop included;
 *                         conn_sink_write degrades to a blocking write there.
 *
 * Every divergence between the two is a slow_child_mode test branching to a
 * *_slow label that holds the untouched original code. Work the fast path must
 * not run synchronously (proxying, POST/PUT/DELETE/PATCH, CGI, on-the-fly gzip,
 * oversized directory listings) is classified up front and handed to
 * fork_slow_child; the forked child never returns to the event loop, it exits
 * from hc_close_final_slow.
 *
 * fd ownership on the fast path: once a body fd is stored into conn->file_fd it
 * belongs to conn.s and is NOT closed here.
 */

.include "src/defs.s"

.global handle_client
.global conn_serve
.extern get_http_date
.extern conn_sink_write
.extern fork_slow_child
.extern serve_directory
.extern cache_lookup
.extern cache_maybe_fill
.extern serving_cached
.extern cache_hit_ptr
.extern fdc_get
.extern fdc_put
.extern fdc_put_borrow
.extern fdc_put_slot

/* "Date: Day, DD Mon YYYY HH:MM:SS GMT\r\n" - fixed width, see get_http_date */
.equ LEN_HTTP_DATE, 37

.text

/* -------------------------------------------------------------------------- */
/* conn_serve(conn) -> 0 keep-alive | 1 close | 3 forked                        */
/*                                                                              */
/* Fast-path entry. Builds the very same frame as handle_client so all the       */
/* shared code below (living on x20/x21/x22/x25/x26/x27/x28) works unchanged,     */
/* then jumps straight at the parser: the head is already in req_buffer.          */
/* -------------------------------------------------------------------------- */
conn_serve:
    /* Stack Frame: 96 bytes (identical layout to handle_client) */
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]

    mov x19, x0                     /* x19 = conn */
    ldr x9, =cur_conn
    str x19, [x9]                   /* anchor for this processing section */

    ldr w20, [x19, #CONN_FD_OFF]    /* x20 = client_fd */
    mov x28, #1                     /* x28 = keep_alive (1=true) */

    /* x25 = bytes of this request sitting in req_buffer (head plus any body).
     * handle_proxy forwards req_buffer[0..x25) and handle_cgi looks past the
     * header terminator for a body; those bytes have already been drained off
     * the socket by conn_on_read, so this must be the full buffered amount,
     * not just the header length. */
    ldr w9, [x19, #CONN_RLEN_OFF]
    ldr w10, [x19, #CONN_RPOS_OFF]
    sub w9, w9, w10
    mov w10, #8191
    cmp w9, w10
    csel w9, w9, w10, ls
    mov x25, x9

    /* Resolve IP using getpeername */
    sub sp, sp, #32
    mov w0, #16
    str w0, [sp, #16]               /* addrlen */

    mov x0, x20                     /* fd */
    mov x1, sp                      /* sockaddr ptr */
    add x2, sp, #16                 /* addrlen ptr */
    mov x8, SYS_GETPEERNAME
    svc #0

    cmp x0, #0
    bne cs_ip_skip

    /* Convert IP (at sp + 4) */
    add x0, sp, #4
    ldr x1, =client_ip_str
    bl inet_ntoa

cs_ip_skip:
    add sp, sp, #32

    /* Atomic request counter increment (shared stats page) */
    ldr x9, =stats_mmap_ptr
    ldr x9, [x9]
    cbz x9, cs_no_stats
cs_stats_inc:
    ldxr x10, [x9]
    add x10, x10, #1
    stxr w11, x10, [x9]
    cbnz w11, cs_stats_inc
cs_no_stats:

    /* Reset range flag for each new request */
    ldr x0, =has_range_request
    str wzr, [x0]

    b hc_parse


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

    b hc_loop_slow          /* slow entry always starts by reading the socket */

hc_loop:
    /* Response finished with keep-alive still on.
     * slow: loop back and block on the next request.
     * fast: flag the connection reusable and hand control back to conn.s. */
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, hc_loop_slow

    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, hc_loop_fast_ret
    ldr w10, [x9, #CONN_FLAGS_OFF]
    orr w10, w10, #CONN_F_KEEPALIVE
    str w10, [x9, #CONN_FLAGS_OFF]
hc_loop_fast_ret:
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    mov x0, #0
    ret

hc_loop_slow:
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

hc_parse:
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

    /* 2.1 Slow-path classifier.
     * The fast path runs inside the worker's event loop and must never block,
     * so anything that talks to another process or another host is forked off
     * to a slow child here, right after the method is known. */
hc_classify:
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, hc_classify_slow_ok

    /* Global proxy mode (-x) or a previous proxy_pass: always slow */
    ldr x9, =upstream_ip
    ldr w9, [x9]
    cbnz w9, hc_slow_proxy

    /* Bodies and mutations: POST/PUT/DELETE/PATCH are slow.
     * GET/HEAD/OPTIONS stay fast, UNKNOWN already answered 405 above. */
    ldr x9, =current_method
    ldr w9, [x9]
    cmp w9, #METHOD_POST
    beq hc_slow_other
    cmp w9, #METHOD_PUT
    beq hc_slow_other
    cmp w9, #METHOD_DELETE
    beq hc_slow_other
    cmp w9, #METHOD_PATCH
    beq hc_slow_other

    /* CGI: mirrors the .py/.sh/.cgi tests guarding invoke_cgi. req_path
     * carries the extension path_buffer will end up with - the only suffixes
     * ever appended below are "/index.html" and ".html". */
    ldr x0, =req_path
    bl get_extension
    cbz x0, hc_classify_fast_ok     /* no dot in the path: never CGI */
    mov x19, x0                     /* x19 = extension (survives strcmp) */
    ldr x1, =ext_py
    bl strcmp
    cbz x0, hc_slow_cgi
    mov x0, x19
    ldr x1, =ext_sh
    bl strcmp
    cbz x0, hc_slow_cgi
    mov x0, x19
    ldr x1, =ext_cgi
    bl strcmp
    cbz x0, hc_slow_cgi

hc_classify_fast_ok:
    b check_conn_close

hc_classify_slow_ok:
    /* Original proxy check, child only */
    ldr x0, =upstream_ip
    ldr w0, [x0]
    cbnz w0, handle_proxy   /* If upstream_ip != 0, proxy it */
    b check_conn_close

hc_slow_proxy:
    ldr x0, =cur_conn
    ldr x0, [x0]
    ldr x1, =hc_slow_proxy_child
    bl fork_slow_child
    cmp x0, #3
    beq hc_fork_ret
    b send_429              /* out of child budget or fork failed */
hc_slow_proxy_child:
    b handle_proxy

hc_slow_other:
hc_slow_cgi:
    ldr x0, =cur_conn
    ldr x0, [x0]
    ldr x1, =hc_slow_resume_child
    bl fork_slow_child
    cmp x0, #3
    beq hc_fork_ret
    b send_429
hc_slow_resume_child:
    /* The child re-enters the ordinary flow with slow_child_mode set and so
     * reaches handle_cgi / the method handling along the original route. */
    b hc_classify_slow_ok

hc_fork_ret:
    /* Parent after a successful fork: the conn slot and the socket are gone. */
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    mov x0, #3
    ret
    
/* ------------------------------------------------------------------ */
/* bounded_strstr: scan only the current request's head for needle x1. */
/* req_buffer may hold pipelined follow-up requests or a body past the */
/* head (CONN_HLEN_OFF includes the trailing CRLFCRLF, so req_buffer   */
/* [hlen] is the first body / next-request byte): their Connection /   */
/* Accept-Encoding / If-None-Match / Range headers must not decide     */
/* this response, and the body byte must survive untouched.            */
/* Temporarily NULs the byte after the head, calls strstr, restores    */
/* it. Slow children re-read fresh requests straight into req_buffer   */
/* (cr_copy never reruns for them), so CONN_HLEN_OFF is stale there -  */
/* they re-locate "\r\n\r\n" instead. Returns strstr result in x0.     */
/* Clobbers x9-x14 (caller-saved).                                     */
/* ------------------------------------------------------------------ */
bounded_strstr:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #24]
    mov x19, x0
    mov x20, x1
    ldr x11, =req_buffer
    cmp x19, x11
    bne bs_plain
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, bs_bound_scan
    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, bs_plain
    ldr w10, [x9, #CONN_HLEN_OFF]
    add x12, x11, w10, uxtw
    b bs_bound_ready
bs_bound_scan:
    mov x0, x11
    ldr x1, =str_http_end
    bl strstr
    cbz x0, bs_plain
    add x12, x0, #4
bs_bound_ready:
    ldrb w13, [x12]
    strb w13, [sp, #40]
    strb wzr, [x12]
    mov x0, x19
    mov x1, x20
    bl strstr
    str x0, [sp, #16]
    ldr x11, =req_buffer
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, bs_restore_scan
    ldr x9, =cur_conn
    ldr x9, [x9]
    ldr w10, [x9, #CONN_HLEN_OFF]
    add x12, x11, w10, uxtw
    b bs_restore_ready
bs_restore_scan:
    mov x0, x11
    ldr x1, =str_http_end
    bl strstr
    add x12, x0, #4
bs_restore_ready:
    ldrb w13, [sp, #40]
    strb w13, [x12]
    ldr x0, [sp, #16]
    ldp x19, x20, [sp, #24]
    ldp x29, x30, [sp], #48
    ret
bs_plain:
    mov x0, x19
    mov x1, x20
    bl strstr
    ldp x19, x20, [sp, #24]
    ldp x29, x30, [sp], #48
    ret

check_conn_close:
    /* 2.5 Check Connection: close */
    ldr x0, =req_buffer
    ldr x1, =str_conn_close
    bl bounded_strstr
    cmp x0, #0
    beq check_trav
    mov x28, #0             /* Found Connection: close -> disable KA */

check_trav:
    /* 2.6 Detect Accept-Encoding: gzip */
    ldr x0, =req_buffer
    ldr x1, =str_accept_gzip
    bl bounded_strstr
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

    /* A3: on the fast path the fork has to happen BEFORE upstream_ip is set.
     * upstream_ip is a process-wide global that nothing ever clears, so a
     * parent worker writing it here would classify every later connection on
     * this worker as a proxy request and burn its whole child budget. The
     * child performs the stores itself - matched_location comes along by COW. */
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, loc_proxy_set

    ldr x0, =cur_conn
    ldr x0, [x0]
    ldr x1, =hc_slow_locproxy_child
    bl fork_slow_child
    cmp x0, #3
    beq hc_fork_ret
    b send_429

hc_slow_locproxy_child:
    ldr x1, =matched_location
    ldr x1, [x1]
    ldr w0, [x1, #320]      /* LOC_PROXY_IP_OFF (x0 held the fd on entry) */

loc_proxy_set:
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
    /* Fail closed: the classifier forks every proxy request, so reaching this
     * inside the worker would be a routing bug. Never block the event loop. */
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbz w9, hc_close_final
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
    /* A1: strlen takes the string, not the upstream fd (x21) */
    ldr x0, =client_ip_str
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
    bl conn_sink_write
    
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

    /* Opportunistic file-cache fill (slot re-checked in memory; only stale
     * or empty slots open/read the file). stat_buffer here is still the
     * route-time stat, so tv_nsec at +96 is valid. */
    ldr x0, =path_buffer
    mov x1, x22
    mov x2, x23
    ldr x9, =stat_buffer
    ldr x3, [x9, #96]        /* st_mtim.tv_nsec */
    bl cache_maybe_fill

    /* Check If-None-Match */
    ldr x0, =req_buffer
    ldr x1, =etag_buffer
    bl bounded_strstr
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
    
    mov x0, x20             /* client_fd (kept for signature compatibility) */
    ldr x1, =path_buffer
    ldr x2, =req_path       /* relative path for links */
    bl serve_directory      /* renders into list_buf, returns total length */

    mov x22, x0             /* x22 = body length (also in list_len) */
    cbz x22, send_403       /* could not open the directory */

    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, hd_emit

    /* list_buf is one process-wide buffer, so it cannot be left as a
     * CONN_F_PTR_BODY source across event-loop turns: the next directory
     * request would overwrite a listing that is still draining. Anything that
     * fits goes into the connection's own out_buf; the rare oversized listing
     * is handed to a slow child, which owns a private copy through COW. The
     * capacity test runs before the first sink so a forking parent never
     * leaves a half-written head in a buffer it is about to release. */
    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, hd_fork
    ldr w10, [x9, #CONN_OUT_LEN_OFF]
    mov w11, #CONN_OUT_CAP
    sub w10, w11, w10
    subs w10, w10, #192     /* reserve room for the response head */
    ble hd_fork
    sxtw x10, w10
    cmp x22, x10
    bgt hd_fork
    b hd_emit

hd_fork:
    ldr x0, =cur_conn
    ldr x0, [x0]
    ldr x1, =hd_slow_child
    bl fork_slow_child
    cmp x0, #3
    beq hc_fork_ret
    b send_429

hd_slow_child:
    /* Blocking socket, private copy of list_buf: emit head and body directly
     * and leave through hc_close_final, which exits the child. */
    ldr x9, =list_len
    ldr x22, [x9]

hd_emit:
    mov x0, x20
    ldr x1, =http_status_200
    ldr x2, =len_status_200
    bl conn_sink_write

    mov x0, x20
    ldr x1, =http_conn_close_hdr
    ldr x2, =len_conn_close_hdr
    bl conn_sink_write

    mov x0, x20
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    bl conn_sink_write
    mov x0, x20
    ldr x1, =mime_html
    mov x2, #9              /* len_mime_html - 1: mime_html is .asciz */
    bl conn_sink_write

    /* http_content_len opens with "\r\n", terminating the Content-Type line */
    mov x0, x20
    ldr x1, =http_content_len
    mov x2, #18
    bl conn_sink_write
    mov x0, x22
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    bl conn_sink_write

    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    bl conn_sink_write

    /* Body */
    mov x0, x20
    ldr x1, =list_buf
    mov x2, x22
    bl conn_sink_write

    ldr x0, =current_status
    mov w1, #200
    str w1, [x0]
    bl log_request

    b hc_close_final

/* ------------------------------------------------------------------------- */
/* Serve File Logic */
/* ------------------------------------------------------------------------- */
serve_file:
    /* Reset per-request file-cache arm: every request starts uncached */
    ldr x0, =serving_cached
    str wzr, [x0]
    /* fd-cache intent never survives a request boundary */
    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, 99f
    ldr w10, [x9, #CONN_FLAGS_OFF]
    bic w10, w10, #(CONN_F_FD_CACHED|CONN_F_FD_BORROWED)
    str w10, [x9, #CONN_FLAGS_OFF]
    mov w10, #-1
    str w10, [x9, #CONN_FDC_SLOT_OFF]
99:

    /* Parse Range header if present */
    ldr x0, =req_buffer
    ldr x1, =str_range_header
    bl bounded_strstr
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

    /* ---- memory file-cache fast path ----
     * stat_buffer at this point still holds the route-time NEWFSTATAT of the
     * original file: the .gz probe only overwrites it on SUCCESS, and success
     * branches to gzip serving before reaching here. So the key (size @48 /
     * st_mtim.tv_sec @88 / tv_nsec @96) plus the live registers x22/x23 set
     * by handle_file_load_size are the fresh stat of THIS request and the
     * lookup below costs zero syscalls. */
    ldr x0, =has_range_request
    ldr w0, [x0]
    cbnz w0, sfd_open              /* Range: never served from cache */
    ldr x0, =path_buffer
    bl get_extension
    mov x19, x0
    cbz x19, sfd_cache_ext_ok
    mov x0, x19
    ldr x1, =ext_py
    bl strcmp
    cbz x0, sfd_open               /* CGI: never cached */
    mov x0, x19
    ldr x1, =ext_sh
    bl strcmp
    cbz x0, sfd_open
    mov x0, x19
    ldr x1, =ext_cgi
    bl strcmp
    cbz x0, sfd_open
sfd_cache_ext_ok:
    ldr x0, =path_buffer
    mov x1, x22
    mov x2, x23
    ldr x9, =stat_buffer
    ldr x3, [x9, #96]
    bl cache_lookup
    cbz x0, sfd_open
    mov x21, x0                    /* entry ptr */
    /* The body must fit in conn->out_buf beside the response head; otherwise
     * serve via sendfile exactly as before. */
    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, sfd_open
    ldr w10, [x9, #CONN_OUT_LEN_OFF]
    mov w11, #CONN_OUT_CAP
    sub w11, w11, w10
    /* head budget: base + add_headers (each slot can emit up to ~256B) */
    ldr x13, =add_headers_count
    ldr w13, [x13]
    lsl w13, w13, #8
    add w13, w13, #512
    subs w11, w11, w13
    ble sfd_open                   /* head too big for one coalesced write */
    ldr w12, [x21, #CACHE_SIZE_OFF]
    cmp w12, w11
    bgt sfd_open                   /* body too big: serve via sendfile */
    /* Arm: send_response ships the body from the cache (zero file syscalls) */
    ldr x0, =serving_cached
    mov w1, #1
    str w1, [x0]
    ldr x0, =cache_hit_ptr
    str x21, [x0]
    mov x21, #-1                   /* no file fd; sendfile_done's close is EBADF-clean */
    cbz x19, sfd_cached_bin
    b serve_file_mime
sfd_cached_bin:
    ldr x25, =mime_bin
    mov x26, #24
    b send_response
sfd_open:
    /* ---- open-file-descriptor cache borrow (nginx open_file_cache equiv) ----
     * Skip the openat+close syscalls when the fd is already cached for this
     * exact file (key = size+mtime+path). Only the fast, non-range, non-CGI
     * GET/HEAD path reaches here; slow children do their own openat. */
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, sfd_do_openat          /* child: never borrow, keep parent table clean */
    ldr x0, =has_range_request
    ldr w0, [x0]
    cbnz w0, sfd_do_openat          /* Range: per-offset sendfile, serve fresh */
    /* mark intent: this fd is returned/inserted to fdcache on completion */
    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, sfd_do_openat
    ldr w10, [x9, #CONN_FLAGS_OFF]
    orr w10, w10, #CONN_F_FD_CACHED
    str w10, [x9, #CONN_FLAGS_OFF]
    /* fdc_get(path, size, mt_sec, mt_nsec) */
    ldr x0, =path_buffer
    mov x1, x22                     /* size */
    mov x2, x23                     /* st_mtim.tv_sec */
    ldr x9, =stat_buffer
    ldr x3, [x9, #96]               /* st_mtim.tv_nsec */
    bl fdc_get
    cmn x0, #1
    beq sfd_do_openat              /* miss: fall through to openat (flag kept) */
    /* hit: borrow cached fd */
    mov x21, x0
    ldr x9, =cur_conn
    ldr x9, [x9]
    str w21, [x9, #CONN_FILE_FD_OFF]
    str w1, [x9, #CONN_FDC_SLOT_OFF]   /* x1 = slot index from fdc_get */
    ldr w10, [x9, #CONN_FLAGS_OFF]
    orr w10, w10, #CONN_F_FD_BORROWED
    str w10, [x9, #CONN_FLAGS_OFF]
    /* MIME detection needs x19 = extension */
    ldr x0, =path_buffer
    bl get_extension
    mov x19, x0
    b serve_file_mime
sfd_do_openat:
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
    /* A4: serve_file_direct already opened the script for static serving and
     * handle_cgi does not use that descriptor - without this close every CGI
     * request leaks one. */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0

    /* Fail closed: CGI is classified slow up front, so the worker should never
     * arrive here; if it does, drop the connection rather than block. */
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbz w9, hc_close_final

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
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, serve_dynamic_gzip

    /* Compressing on the fly means spawning /bin/gzip and streaming chunks,
     * both blocking, so the whole response goes to a slow child. This is the
     * one slow class the classifier cannot predict up front: it depends on the
     * file that routing finally resolved. */
    ldr x0, =cur_conn
    ldr x0, [x0]
    ldr x1, =hc_slow_gzip_child
    bl fork_slow_child
    cmp x0, #3
    bne mdgz_no_child
    /* Parent still holds the open file: the child has its own descriptor. */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    b hc_fork_ret

mdgz_no_child:
    b send_response         /* no child available: serve it uncompressed */

hc_slow_gzip_child:
    /* A cache-hit fast path armed no file fd (x21 = -1). The dynamic gzip
     * child dup3's x21 onto its stdin, so reopen here on the rare
     * Accept-Encoding: gzip + cache-hit combination. */
    cmn x21, #1
    bne hcsgc_go
    mov x0, AT_FDCWD
    ldr x1, =path_buffer
    mov x2, O_RDONLY
    mov x3, #0
    mov x8, SYS_OPENAT
    svc #0
    mov x21, x0
hcsgc_go:
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
    bl conn_sink_write
    
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
    bl conn_sink_write
    
    /* 1.5 Write Server Header (skip if server_tokens off) */
    ldr x0, =server_tokens
    ldr w0, [x0]
    cbz w0, sr_skip_server_hdr
    mov x0, x20
    ldr x1, =http_server_hdr
    ldr x2, =len_server_hdr
    bl conn_sink_write
sr_skip_server_hdr:

    /* 1.51 Write Date Header */
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbz w9, sr_date_fast
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl get_http_date
    ldp x29, x30, [sp], #16
    /* x0 = length of date string in http_date_buffer */
    mov x2, x0
    b sr_date_done
sr_date_fast:
    /* http_date_buffer is refreshed once per event-loop turn by refresh_date */
    mov x2, #LEN_HTTP_DATE
sr_date_done:
    mov x0, x20
    ldr x1, =http_date_buffer
    bl conn_sink_write

    /* 1.55 Write ETag */
    mov x0, x20
    ldr x1, =http_etag_start
    ldr x2, =len_etag_start
    bl conn_sink_write
    
    mov x0, x20
    ldr x1, =etag_buffer
    mov x2, x27
    bl conn_sink_write
    
    mov x0, x20
    ldr x1, =http_quote_newline
    ldr x2, =len_quote_newline
    bl conn_sink_write

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
    bl conn_sink_write
    /* write ": " */
    mov x0, x20
    ldr x1, =str_header_sep
    mov x2, #2
    bl conn_sink_write
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
    bl conn_sink_write
    /* write \r\n to terminate this header */
    mov x0, x20
    ldr x1, =str_crlf
    mov x2, #2
    bl conn_sink_write
    add x19, x19, #1
    b sr_add_hdr_loop
sr_add_hdrs_done:

    /* 1.6 Write Content-Type Label */
    mov x0, x20
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    bl conn_sink_write
    
    /* 2. Write MIME type */
    mov x0, x20
    mov x1, x25
    mov x2, x26
    bl conn_sink_write
    
    /* 3. Write Content-Length header */
    mov x0, x20
    ldr x1, =http_content_len
    mov x2, #18
    bl conn_sink_write
    
    /* 4. Write content length value */
    mov x0, x22
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    bl conn_sink_write
    
    /* 5. Write Accept-Ranges header */
    mov x0, x20
    ldr x1, =http_accept_ranges
    ldr x2, =len_accept_ranges
    bl conn_sink_write

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
    bl conn_sink_write
    b sr_no_cache_ctrl
sr_cc_maxage:
    /* N = max-age=N */
    mov x9, x0              /* save seconds */
    mov x0, x20
    ldr x1, =hdr_cache_control
    mov x2, #25             /* len_hdr_cache_control */
    bl conn_sink_write
    mov x0, x9
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    bl conn_sink_write
sr_no_cache_ctrl:

    /* 5.5 Write header end */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    bl conn_sink_write
    
    /* Check if HEAD request - skip body */
    ldr x0, =current_method
    ldr w0, [x0]
    cmp w0, #METHOD_HEAD
    beq head_skip_body

    /* 6. Send body. Cached files were memcpy'd into out_buf by the sink -
     * one write syscall for the whole response. Everything else keeps the
     * sendfile hand-off to the event loop. */
    ldr x0, =serving_cached
    ldr w0, [x0]
    cbnz w0, sr_body_cached
    /* 6. Send file content using sendfile (Loop) */
    ldr x0, =sendfile_offset
    str xzr, [x0]
    b sendfile_loop
sr_body_cached:
    ldr x9, =cache_hit_ptr
    ldr x9, [x9]
    cbz x9, sr_body_cached_noop
    ldr x1, [x9, #CACHE_CONTENT_OFF]
    mov x0, x20
    mov x2, x22
    bl conn_sink_write
    b sendfile_logged
sr_body_cached_noop:
    /* defensive: armed without an entry - drop the body, keep the head */
    b sendfile_done            /* offset = 0 */

sendfile_loop:
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, sendfile_loop_slow

    /* fast: try to ship head+body synchronously, in order. conn_flush does
     * exactly this on its own wakeup, but the event-loop round trip costs an
     * EPOLLOUT arm + a second epoll_pwait return per request. For bodies that
     * fit the socket buffer one write + one sendfile completes right here. */
    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, sendfile_loop_slow
    cmp x22, #0
    ble sendfile_done               /* empty file: nothing to hand over */
    mov x13, x22                    /* total body size: the log wants it */

    /* an abort-flagged conn has a truncated head in out_buf: conn_flush owns
     * the close-without-write, never put a malformed response on the wire */
    ldr w10, [x9, #CONN_FLAGS_OFF]
    tst w10, #CONN_F_ABORT
    bne sfl_arm_ev

    /* 1. flush the head first - a body byte must never precede it. Head
     *    progress lives in CONN_OUT_POS_OFF (conn_flush's own contract):
     *    write what remains, advance pos; a short write just leaves the
     *    rest for the event loop, which continues from the new pos. */
    ldr w10, [x9, #CONN_OUT_LEN_OFF]
    ldr w11, [x9, #CONN_OUT_POS_OFF]
    cmp w11, w10
    bge sfl_head_done
    add x12, x9, #CONN_OUT_BUF_OFF
    add x1, x12, w11, uxtw
    mov x0, x20
    sub w2, w10, w11
    uxtw x2, w2
    mov x8, SYS_WRITE
    svc #0
    cmp x0, #0
    ble sfl_arm_ev                  /* EAGAIN/error: conn_flush retries from pos */
    add w11, w11, w0
    str w11, [x9, #CONN_OUT_POS_OFF]  /* head progress is conn_flush's contract */
sfl_head_done:
    /* 2. one immediate sendfile; the socket usually drains it in one shot */
    mov x0, x20
    mov w1, w21
    ldr x2, =sendfile_offset
    mov x3, x22
    mov x8, SYS_SENDFILE
    svc #0
    cmp x0, #0
    ble sfl_arm_ev                  /* EAGAIN/error: event loop owns the body */
    ldr x2, =sendfile_offset
    ldr x2, [x2]                    /* kernel-updated continuation offset */
    sub x22, x22, x0
    cbz x22, sfl_sent_all
    /* handoff stores FIRST: x2 (continuation offset), x9 (cur_conn) and x13
     * (total) all die at the insert call below, so they must be consumed
     * before it. x22 = REMAINING for CONN_FILE_REM_OFF, then restored to the
     * total for the log (x22 is callee-saved, survives the call). */
    str x2, [x9, #CONN_FILE_OFF_OFF]
    str x22, [x9, #CONN_FILE_REM_OFF]
    str w21, [x9, #CONN_FILE_FD_OFF]
    ldr w10, [x9, #CONN_FLAGS_OFF]
    orr w10, w10, #CONN_F_FILE_BODY
    str w10, [x9, #CONN_FLAGS_OFF]
    mov x22, x13                    /* log the total, not the remainder */
    /* openat-intent fd: insert + borrow back NOW (globals still this
     * request's; x23 is add_headers_count here, key comes from stat_buffer)
     * so cf_finish returns it via slot instead of native-closing it. */
    ldr x9, =cur_conn
    ldr x9, [x9]
    ldr w10, [x9, #CONN_FLAGS_OFF]
    tst w10, #CONN_F_FD_CACHED
    beq sfl_partial_done
    tst w10, #CONN_F_FD_BORROWED
    bne sfl_partial_done
    mov w0, w21
    ldr x1, =path_buffer
    ldr x5, =stat_buffer
    ldr x2, [x5, #48]              /* st_size */
    ldr x3, [x5, #88]              /* st_mtim.tv_sec */
    ldr x4, [x5, #96]              /* st_mtim.tv_nsec */
    bl fdc_put_borrow
    cmn w1, #1
    beq sfl_partial_done            /* could not cache: cf_finish closes fd */
    ldr x9, =cur_conn
    ldr x9, [x9]
    str w1, [x9, #CONN_FDC_SLOT_OFF]
    ldr w10, [x9, #CONN_FLAGS_OFF]
    orr w10, w10, #CONN_F_FD_BORROWED
    str w10, [x9, #CONN_FLAGS_OFF]
sfl_partial_done:
    b sendfile_logged

sfl_sent_all:
    /* one sendfile shipped the whole body (inline): the path/stat globals
     * are still THIS request's. Borrow -> return via slot (key-free).
     * Openat -> INSERT the fd (fresh key). Then log, keepalive. */
    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, sfl_close_raw
    ldr w10, [x9, #CONN_FLAGS_OFF]
    tst w10, #CONN_F_FD_CACHED
    beq sfl_close_raw
    tst w10, #CONN_F_FD_BORROWED
    bne sfl_put_slot
    /* openat-intent inline: insert. x23 was clobbered by send_response
     * (add_headers_count), so the key comes from stat_buffer. fdc_put no
     * longer closes on skip: this conn is DONE with the fd, so a skip (-1)
     * means close it here. */
    mov w0, w21
    ldr x1, =path_buffer
    ldr x5, =stat_buffer
    ldr x2, [x5, #48]              /* st_size */
    ldr x3, [x5, #88]              /* st_mtim.tv_sec */
    ldr x4, [x5, #96]              /* st_mtim.tv_nsec */
    bl fdc_put
    cmn w1, #1
    bne sfl_fdc_done
    /* skip: conn is done with the fd, close it here, never fall into
     * sfl_put_slot (x9 holds cur_conn at sfl_put_slot only on the borrow
     * path; after this call x9 is clobbered). */
    mov w0, w21
    mov x8, SYS_CLOSE
    svc #0
    b sfl_fdc_done
sfl_put_slot:
    ldr w0, [x9, #CONN_FDC_SLOT_OFF]
    bl fdc_put_slot
sfl_fdc_done:
    ldr x9, =cur_conn
    ldr x9, [x9]
    ldr w10, [x9, #CONN_FLAGS_OFF]
    bic w10, w10, #(CONN_F_FD_CACHED|CONN_F_FD_BORROWED)
    str w10, [x9, #CONN_FLAGS_OFF]
    mov w10, #-1
    str w10, [x9, #CONN_FILE_FD_OFF]
    mov w10, #-1
    str w10, [x9, #CONN_FDC_SLOT_OFF]
    mov x21, #-1
    /* x13/x5 were clobbered by fdc_put / fdc_put_slot: total from stat_buffer */
    ldr x5, =stat_buffer
    ldr x22, [x5, #48]              /* st_size = total, the log wants it */
    b sendfile_logged
sfl_close_raw:
    /* one sendfile shipped the whole body: close the fd, log, keepalive */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    mov x21, #-1
    mov x22, x13
    b sendfile_logged

head_skip_body:
sendfile_done:
    /* Inline completion (HEAD / empty file / slow child): a borrow returns
     * via slot; an openat fd is native-closed (globals may be stale if this
     * ran after the worker parsed another request; the size-0 guard makes
     * inserting pointless anyway). */
    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, sfd_close_raw
    ldr w10, [x9, #CONN_FLAGS_OFF]
    tst w10, #CONN_F_FD_CACHED
    beq sfd_close_raw
    tst w10, #CONN_F_FD_BORROWED
    beq sfd_close_raw
    ldr w0, [x9, #CONN_FDC_SLOT_OFF]
    bl fdc_put_slot
    ldr x9, =cur_conn
    ldr x9, [x9]
    ldr w10, [x9, #CONN_FLAGS_OFF]
    bic w10, w10, #(CONN_F_FD_CACHED|CONN_F_FD_BORROWED)
    str w10, [x9, #CONN_FLAGS_OFF]
    mov w10, #-1
    str w10, [x9, #CONN_FILE_FD_OFF]
    mov w10, #-1
    str w10, [x9, #CONN_FDC_SLOT_OFF]
    mov x21, #-1
    b sendfile_logged
sfd_close_raw:
    /* Close file */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    b sendfile_logged
sfl_arm_ev:
    /* Event-loop handoff: head or body EAGAINed inline, we hand the in-flight
     * response to conn_flush.  Reached with path/stat globals STILL THIS
     * request's (no other request parsed yet), so an openat-intent fd is
     * inserted + borrowed back here - otherwise cf_finish would native-close
     * it and the cache would never gain an entry (0% HIT). The key is read
     * from stat_buffer: x23 was clobbered by send_response (add_headers_count)
     * and x22 is the remaining body, not st_size. */
    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, sfl_arm_handoff
    ldr w10, [x9, #CONN_FLAGS_OFF]
    tst w10, #CONN_F_FD_CACHED
    beq sfl_arm_handoff            /* not an fd-cache flow */
    tst w10, #CONN_F_FD_BORROWED
    bne sfl_arm_handoff            /* borrow: cf_finish returns it via slot */
    mov w0, w21
    ldr x1, =path_buffer
    ldr x5, =stat_buffer
    ldr x2, [x5, #48]              /* st_size */
    ldr x3, [x5, #88]              /* st_mtim.tv_sec */
    ldr x4, [x5, #96]              /* st_mtim.tv_nsec */
    bl fdc_put_borrow
    cmn w1, #1
    beq sfl_arm_handoff            /* could not cache: cf_finish closes fd */
    ldr x9, =cur_conn
    ldr x9, [x9]
    str w1, [x9, #CONN_FDC_SLOT_OFF]
    ldr w10, [x9, #CONN_FLAGS_OFF]
    orr w10, w10, #CONN_F_FD_BORROWED
    str w10, [x9, #CONN_FLAGS_OFF]
sfl_arm_handoff:
    /* reload cur_conn: the insert-skip path above arrives with x9 clobbered
     * by fdc_put_borrow */
    ldr x9, =cur_conn
    ldr x9, [x9]
    str w21, [x9, #CONN_FILE_FD_OFF]
    str xzr, [x9, #CONN_FILE_OFF_OFF]
    str x22, [x9, #CONN_FILE_REM_OFF]
    ldr w10, [x9, #CONN_FLAGS_OFF]
    orr w10, w10, #CONN_F_FILE_BODY
    str w10, [x9, #CONN_FLAGS_OFF]
    b sendfile_logged

sendfile_loop_slow:
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
    b sendfile_loop_slow


sendfile_logged:
    
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
    /* Load and validate range bounds.
     * x19/x24 hold them, not x9/x10: itoa clobbers x9-x11 and this function
     * still needs range_start/range_end after emitting the Content-Range
     * values (and, on the fast path, as the sendfile offset). */
    ldr x19, =range_start
    ldr x19, [x19]
    ldr x24, =range_end
    ldr x24, [x24]
    mov x23, x22            /* x23 = total file size (callee-saved, preserved across bl calls) */

    /* Clamp range_end: if sentinel (-1) or >= file_size, use file_size - 1 */
    sub x11, x22, #1
    cmp x24, x22
    blt spc_range_end_ok
    mov x24, x11
spc_range_end_ok:
    /* 416 if range_start >= file_size */
    cmp x19, x22
    bge send_416
    /* 416 if range_end < range_start */
    cmp x24, x19
    blt send_416

    /* content_length = range_end - range_start + 1 */
    sub x22, x24, x19
    add x22, x22, #1

    /* --- Status line --- */
    mov x0, x20
    ldr x1, =http_206
    mov x2, #30             /* len("HTTP/1.1 206 Partial Content\r\n") */
    bl conn_sink_write

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
    bl conn_sink_write

    /* --- Server header --- */
    mov x0, x20
    ldr x1, =http_server_hdr
    ldr x2, =len_server_hdr
    bl conn_sink_write

    /* --- Date header --- */
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbz w9, spc_date_fast
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl get_http_date
    ldp x29, x30, [sp], #16
    mov x2, x0
    b spc_date_done
spc_date_fast:
    mov x2, #LEN_HTTP_DATE
spc_date_done:
    mov x0, x20
    ldr x1, =http_date_buffer
    bl conn_sink_write

    /* --- Content-Type: label + MIME --- */
    mov x0, x20
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    bl conn_sink_write
    mov x0, x20
    mov x1, x25
    mov x2, x26
    bl conn_sink_write

    /* --- Content-Range: bytes START-END/TOTAL\r\n ---
     * http_content_range starts with "\r\n" which terminates Content-Type */
    mov x0, x20
    ldr x1, =http_content_range
    ldr x2, =len_content_range
    bl conn_sink_write

    /* Write range_start */
    mov x0, x19
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    bl conn_sink_write

    /* Write "-" */
    mov x0, x20
    ldr x1, =str_dash
    mov x2, #1
    bl conn_sink_write

    /* Write range_end */
    mov x0, x24
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    bl conn_sink_write

    /* Write "/" */
    mov x0, x20
    ldr x1, =str_slash
    mov x2, #1
    bl conn_sink_write

    /* Write total file size */
    mov x0, x23
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    bl conn_sink_write

    /* --- Content-Length: content_length ---
     * http_content_len starts with \r\n which terminates Content-Range line */
    mov x0, x20
    ldr x1, =http_content_len  /* "\r\nContent-Length: " */
    mov x2, #18
    bl conn_sink_write
    mov x0, x22
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    bl conn_sink_write

    /* --- Accept-Ranges: bytes + end of headers --- */
    mov x0, x20
    ldr x1, =http_accept_ranges  /* "\r\nAccept-Ranges: bytes" */
    ldr x2, =len_accept_ranges
    bl conn_sink_write
    mov x0, x20
    ldr x1, =http_end            /* "\r\n\r\n" */
    mov x2, #4
    bl conn_sink_write

    /* Skip body for HEAD requests */
    ldr x0, =current_method
    ldr w0, [x0]
    cmp w0, #METHOD_HEAD
    beq spc_done

    /* --- Send partial body via sendfile with offset --- */
    ldr x0, =sendfile_offset
    str x19, [x0]           /* offset = range_start */
spc_sendfile_loop:
    /* x19 = range_start, x24 = range_end here; the guard borrows x11/x12 */
    ldr x11, =slow_child_mode
    ldr w11, [x11]
    cbnz w11, spc_sendfile_loop_slow

    ldr x11, =cur_conn
    ldr x11, [x11]
    cbz x11, spc_sendfile_loop_slow
    cmp x22, #0
    ble spc_done
    str w21, [x11, #CONN_FILE_FD_OFF]
    str x19, [x11, #CONN_FILE_OFF_OFF]      /* body starts at range_start */
    str x22, [x11, #CONN_FILE_REM_OFF]
    ldr w12, [x11, #CONN_FLAGS_OFF]
    orr w12, w12, #CONN_F_FILE_BODY
    str w12, [x11, #CONN_FLAGS_OFF]
    b spc_logged

spc_sendfile_loop_slow:
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
    b spc_sendfile_loop_slow

spc_done:
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0

spc_logged:

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
    bl conn_sink_write

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
    bl conn_sink_write
    
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
    bl conn_sink_write
    
    /* Server header */
    mov x0, x20
    ldr x1, =http_server_hdr
    ldr x2, =len_server_hdr
    bl conn_sink_write
    
    /* Date header */
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbz w9, srg_date_fast
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    bl get_http_date
    ldp x29, x30, [sp], #16
    mov x2, x0
    b srg_date_done
srg_date_fast:
    mov x2, #LEN_HTTP_DATE
srg_date_done:
    mov x0, x20
    ldr x1, =http_date_buffer
    bl conn_sink_write
    
    /* Content-Type */
    mov x0, x20
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    bl conn_sink_write
    mov x0, x20
    mov x1, x25
    mov x2, x26
    bl conn_sink_write
    
    /* Content-Encoding: gzip */
    mov x0, x20
    ldr x1, =http_content_encoding_gzip
    ldr x2, =len_content_encoding_gzip
    bl conn_sink_write
    
    /* Content-Length */
    mov x0, x20
    ldr x1, =http_content_len
    mov x2, #18
    bl conn_sink_write
    mov x0, x22
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    bl conn_sink_write
    
    /* Vary: Accept-Encoding (important for caching) */
    mov x0, x20
    ldr x1, =http_vary_encoding
    ldr x2, =len_vary_encoding
    bl conn_sink_write
    
    /* End headers */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    bl conn_sink_write
    
    /* Check HEAD */
    ldr x0, =current_method
    ldr w0, [x0]
    cmp w0, #METHOD_HEAD
    beq srg_done
    
    /* Sendfile loop */
    ldr x0, =sendfile_offset
    str xzr, [x0]
srg_send:
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, srg_send_slow

    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, srg_send_slow
    cmp x22, #0
    ble srg_done
    str w21, [x9, #CONN_FILE_FD_OFF]
    str xzr, [x9, #CONN_FILE_OFF_OFF]
    str x22, [x9, #CONN_FILE_REM_OFF]
    ldr w10, [x9, #CONN_FLAGS_OFF]
    orr w10, w10, #CONN_F_FILE_BODY
    str w10, [x9, #CONN_FLAGS_OFF]
    b srg_logged

srg_send_slow:
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
    b srg_send_slow

srg_done:
    /* Close file */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0

srg_logged:
    
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
    bl conn_sink_write
    
    /* 304 ETag */
    mov x0, x20
    ldr x1, =http_etag_start
    ldr x2, =len_etag_start
    bl conn_sink_write
    
    mov x0, x20
    ldr x1, =etag_buffer
    mov x2, x27
    bl conn_sink_write
    
    mov x0, x20
    ldr x1, =http_quote_newline
    ldr x2, =len_quote_newline
    bl conn_sink_write
    
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
    bl conn_sink_write
    /* Write URL */
    ldr x1, =return_url_buf
    mov x0, x1              /* x0 = string ptr for strlen */
    bl strlen
    mov x2, x0
    mov x0, x20
    ldr x1, =return_url_buf
    bl conn_sink_write
    /* Write end of redirect response */
    mov x0, x20
    ldr x1, =http_redirect_end
    mov x2, #42             /* len_redirect_end */
    bl conn_sink_write
    /* A2: dropped a store of *x9 (a status-line pointer, not the code) into
     * current_status - the reload from return_code just below is the correct one */
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
    bl conn_sink_write
    
    ldr x0, =current_status
    mov w1, #400
    str w1, [x0]
    bl log_request
    b hc_close_final

send_403:
    mov x0, x20
    ldr x1, =http_403
    ldr x2, =len_403
    bl conn_sink_write
    
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
    bl conn_sink_write

    /* Server header */
    mov x0, x20
    ldr x1, =http_server_hdr
    ldr x2, =len_server_hdr
    bl conn_sink_write

    /* Content-Type: text/html */
    mov x0, x20
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    bl conn_sink_write
    mov x0, x20
    ldr x1, =mime_html
    mov x2, #9
    bl conn_sink_write

    /* Content-Length: N */
    mov x0, x20
    ldr x1, =http_content_len
    mov x2, #18
    bl conn_sink_write
    mov x0, x22
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    bl conn_sink_write

    /* End of headers */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    bl conn_sink_write

    /* Send file body via sendfile loop */
    ldr x0, =sendfile_offset
    str xzr, [x0]
send_custom_404_body:
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, send_custom_404_body_slow

    ldr x9, =cur_conn
    ldr x9, [x9]
    cbz x9, send_custom_404_body_slow
    cmp x22, #0
    ble send_custom_404_done
    str w21, [x9, #CONN_FILE_FD_OFF]
    str xzr, [x9, #CONN_FILE_OFF_OFF]
    str x22, [x9, #CONN_FILE_REM_OFF]
    ldr w10, [x9, #CONN_FLAGS_OFF]
    orr w10, w10, #CONN_F_FILE_BODY
    str w10, [x9, #CONN_FLAGS_OFF]
    b send_custom_404_logged

send_custom_404_body_slow:
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
    b send_custom_404_body_slow

send_custom_404_done:
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0

send_custom_404_logged:

    ldr x0, =current_status
    mov w1, #404
    str w1, [x0]
    bl log_request
    b hc_close_final

send_404_default:
    mov x0, x20
    ldr x1, =http_404
    ldr x2, =len_404
    bl conn_sink_write

    ldr x0, =current_status
    mov w1, #404
    str w1, [x0]
    bl log_request
    b hc_close_final

send_502:
    mov x0, x20
    ldr x1, =http_502
    ldr x2, =len_502
    bl conn_sink_write
    
    ldr x0, =current_status
    mov w1, #502
    str w1, [x0]
    bl log_request
    b hc_close_final

send_options:
    mov x0, x20
    ldr x1, =http_options_resp
    ldr x2, =len_options_resp
    bl conn_sink_write
    
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
    bl conn_sink_write
    
    ldr x0, =current_status
    mov w1, #405
    str w1, [x0]
    bl log_request
    b hc_close_final

send_429:
    mov x0, x20
    ldr x1, =http_429
    ldr x2, =len_429
    bl conn_sink_write
    
    ldr x0, =current_status
    mov w1, #429
    str w1, [x0]
    bl log_request
    b hc_close_final

send_server_status:
    mov x0, x20
    ldr x1, =http_status_200
    ldr x2, =len_status_200
    bl conn_sink_write

    mov x0, x20
    ldr x1, =server_status_hdr
    ldr x2, =len_server_status_hdr
    bl conn_sink_write

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
    bl conn_sink_write
    /* Write request count */
    mov x0, x10
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    bl conn_sink_write
    /* Write worker count */
    mov x0, x20
    ldr x1, =ss_json_mid
    ldr x2, =len_ss_json_mid
    bl conn_sink_write
    ldr x0, =worker_count
    ldr w0, [x0]
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =content_len_str
    bl conn_sink_write
    /* Write JSON suffix */
    mov x0, x20
    ldr x1, =ss_json_suffix
    ldr x2, =len_ss_json_suffix
    bl conn_sink_write

    ldr x0, =current_status
    mov w1, #200
    str w1, [x0]
    bl log_request

    cmp x28, #1
    beq hc_loop
    b hc_close_final

hc_close_final:
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbnz w9, hc_close_final_slow

    /* fast: the whole response is queued on the connection (out_buf, plus a
     * file or pointer body). conn.s drains it and then closes the socket and
     * releases the slot; CONN_F_KEEPALIVE was never set, so it will close. */
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    mov x0, #1
    ret

hc_close_final_slow:
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

    /* A slow child exists to serve this one connection. Returning would take
     * it back through conn_on_read into the worker's event loop as a rogue
     * second worker sharing conn_pool and the listening socket, so it exits
     * here instead. handle_client has no other caller. */
    mov x0, #0
    mov x8, SYS_EXIT
    svc #0

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
    /* Fail closed: this spawns /bin/gzip and streams chunks, both blocking.
     * mdgz_do forks before branching here, so the worker must never arrive.
     * The guard sits ahead of the prologue - there is no frame to unwind. */
    ldr x9, =slow_child_mode
    ldr w9, [x9]
    cbz w9, hc_close_final

sdgz_slow:
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
    bl conn_sink_write
    /* Server header */
    mov x0, x20
    ldr x1, =http_server_hdr
    ldr x2, =len_server_hdr
    bl conn_sink_write
    /* Content-Type: <mime> */
    mov x0, x20
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    bl conn_sink_write
    mov x0, x20
    mov x1, x25
    mov x2, x26
    bl conn_sink_write
    /* "\r\n" after MIME value */
    sub sp, sp, #16
    mov w0, #0x0d
    strb w0, [sp]
    mov w0, #0x0a
    strb w0, [sp, #1]
    mov x0, x20
    mov x1, sp
    mov x2, #2
    bl conn_sink_write
    add sp, sp, #16
    /* Content-Encoding: gzip + Transfer-Encoding: chunked */
    mov x0, x20
    ldr x1, =dgzip_ce_hdr
    ldr x2, =dgzip_ce_len
    bl conn_sink_write
    /* Connection */
    cmp x28, #1
    bne sdgz_conn_close
    mov x0, x20
    ldr x1, =http_conn_ka
    ldr x2, =len_conn_ka
    bl conn_sink_write
    b sdgz_end_headers
sdgz_conn_close:
    mov x0, x20
    ldr x1, =http_conn_close_hdr
    ldr x2, =len_conn_close_hdr
    bl conn_sink_write
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
    bl conn_sink_write
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
    bl conn_sink_write
    add sp, sp, #32
    sub sp, sp, #16
    mov w0, #0x0d
    strb w0, [sp]
    mov w0, #0x0a
    strb w0, [sp, #1]
    mov x0, x20
    mov x1, sp
    mov x2, #2
    bl conn_sink_write
    add sp, sp, #16
    /* chunk data */
    mov x0, x20
    ldr x1, =gzip_chunk_buf
    mov x2, x22
    bl conn_sink_write
    /* \r\n */
    sub sp, sp, #16
    mov w0, #0x0d
    strb w0, [sp]
    mov w0, #0x0a
    strb w0, [sp, #1]
    mov x0, x20
    mov x1, sp
    mov x2, #2
    bl conn_sink_write
    add sp, sp, #16
    b sdgz_chunk_loop

sdgz_chunk_done:
    /* "0\r\n\r\n" */
    mov x0, x20
    ldr x1, =dgzip_final_chunk
    ldr x2, =dgzip_final_len
    bl conn_sink_write
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
