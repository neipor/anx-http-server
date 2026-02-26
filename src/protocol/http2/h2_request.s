/* src/protocol/http2/h2_request.s - HTTP/2 Request Processing */

.include "src/defs.s"
.include "src/core/types.s"

.global hpack_decode_headers_impl
.global h2_build_http1_request_impl
.global h2_process_request_impl
.global h2_route_request
.global h2_serve_file

/* HTTP/2 Error Codes */
.set H2_ERROR_NO_ERROR,         0x0
.set H2_ERROR_PROTOCOL_ERROR,   0x1
.set H2_ERROR_INTERNAL_ERROR,   0x2
.set H2_ERROR_FLOW_CONTROL,     0x3
.set H2_ERROR_SETTINGS_TIMEOUT, 0x4
.set H2_ERROR_STREAM_CLOSED,    0x5
.set H2_ERROR_FRAME_SIZE,       0x6
.set H2_ERROR_REFUSED_STREAM,   0x7
.set H2_ERROR_CANCEL,           0x8
.set H2_ERROR_COMPRESSION,      0x9
.set H2_ERROR_CONNECT,          0xa
.set H2_ERROR_ENHANCE_YOUR_CALM, 0xb
.set H2_ERROR_INADEQUATE_SECURITY, 0xc
.set H2_ERROR_HTTP_1_1_REQUIRED, 0xd

/* Maximum sizes */
.set H2_MAX_REQUEST_BUFFER,     8192
.set H2_MAX_HEADER_SIZE,        4096

/* ================================================================================================
 * hpack_decode_headers_impl(context, input, input_len, request)
 * Full HPACK header decoding for HTTP/2 requests
 * x0 = HPACK decoder context
 * x1 = input buffer (HPACK encoded headers)
 * x2 = input length
 * x3 = request context (h2req_* structure)
 * Returns: x0 = 0 on success, error code on failure
 * ================================================================================================ */
hpack_decode_headers_impl:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    
    mov     x19, x0                 /* hpack context */
    mov     x20, x1                 /* input buffer */
    mov     x21, x2                 /* input length */
    mov     x22, x3                 /* request context */
    
    /* Allocate buffers for decoded headers on stack */
    sub     sp, sp, #H2_MAX_HEADER_SIZE * 2
    mov     x23, sp                 /* name buffer */
    add     x24, sp, #H2_MAX_HEADER_SIZE  /* value buffer */
    
    mov     x25, #0                 /* total bytes consumed */
    
hpack_decode_loop:
    /* Check if we've consumed all input */
    cmp     x25, x21
    bge     hpack_decode_success
    
    /* Decode one header field */
    mov     x0, x19                 /* hpack context */
    add     x1, x20, x25            /* current input position */
    sub     x2, x21, x25            /* remaining length */
    mov     x3, x23                 /* name buffer */
    mov     x4, x24                 /* value buffer */
    mov     x5, #H2_MAX_HEADER_SIZE /* name max */
    mov     x6, #H2_MAX_HEADER_SIZE /* value max */
    bl      hpack_decode_header_field
    
    cmp     x0, #0
    blt     hpack_decode_error      /* error code in x0 */
    
    /* x0 = bytes consumed, x1 = name_len, x2 = value_len */
    add     x25, x25, x0            /* update bytes consumed */
    mov     x26, x1                 /* name_len */
    mov     x27, x2                 /* value_len */
    
    /* Check if this is a dynamic table update (no header produced) */
    cmp     x26, #0
    beq     hpack_decode_loop       /* skip if no header */
    
    /* Process decoded header - check for pseudo-headers */
    mov     x0, x22                 /* request context */
    mov     x1, x23                 /* name */
    mov     x2, x26                 /* name_len */
    mov     x3, x24                 /* value */
    mov     x4, x27                 /* value_len */
    bl      h2_process_header
    
    cmp     x0, #0
    blt     hpack_decode_error
    
    b       hpack_decode_loop

hpack_decode_success:
    mov     x0, #0
    b       hpack_decode_done

hpack_decode_error:
    /* x0 already contains error code */

hpack_decode_done:
    add     sp, sp, #H2_MAX_HEADER_SIZE * 2
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x25, x26, [sp, #64]
    ldp     x27, x28, [sp, #80]
    ldp     x29, x30, [sp], #96
    ret

/* ================================================================================================
 * h2_process_header(request, name, name_len, value, value_len)
 * Process a single decoded header field
 * x0 = request context
 * x1 = name
 * x2 = name_len
 * x3 = value
 * x4 = value_len
 * Returns: x0 = 0 on success, error on failure
 * ================================================================================================ */
h2_process_header:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* request context */
    mov     x20, x1                 /* name */
    mov     x21, x2                 /* name_len */
    mov     x22, x3                 /* value */
    /* x4 = value_len */
    
    /* Check if pseudo-header (starts with ':') */
    ldrb    w0, [x20]
    cmp     w0, #':'
    beq     h2_process_pseudo_header
    
    /* Regular header - store in headers buffer */
    /* For now, just skip - we'll add header storage later */
    mov     x0, #0
    b       h2_process_header_done

h2_process_pseudo_header:
    /* Check which pseudo-header */
    cmp     x21, #7                 /* length of ":method" */
    bne     h2_check_path
    
    /* Check if ":method" */
    ldr     x5, [x20]               /* load first 8 bytes */
    mov     x6, #0x0000646F6864656D  /* ":method" little endian (partial) */
    /* Actually let's compare character by character */
    adr     x5, h2_method_str
    mov     x0, x20
    mov     x1, x5
    mov     x2, x21
    bl      strncmp
    cbnz    x0, h2_check_path
    
    /* Store method */
    str     x22, [x19, #16]         /* h2req_method */
    mov     x0, #0
    b       h2_process_header_done

h2_check_path:
    cmp     x21, #5                 /* ":path" */
    bne     h2_check_scheme
    
    adr     x5, h2_path_str
    mov     x0, x20
    mov     x1, x5
    mov     x2, x21
    bl      strncmp
    cbnz    x0, h2_check_scheme
    
    /* Store path */
    str     x22, [x19, #24]         /* h2req_path */
    mov     x0, #0
    b       h2_process_header_done

h2_check_scheme:
    cmp     x21, #7                 /* ":scheme" */
    bne     h2_check_authority
    
    adr     x5, h2_scheme_str
    mov     x0, x20
    mov     x1, x5
    mov     x2, x21
    bl      strncmp
    cbnz    x0, h2_check_authority
    
    /* Store scheme */
    str     x22, [x19, #40]         /* h2req_scheme */
    mov     x0, #0
    b       h2_process_header_done

h2_check_authority:
    cmp     x21, #10                /* ":authority" */
    bne     h2_check_status
    
    adr     x5, h2_authority_str
    mov     x0, x20
    mov     x1, x5
    mov     x2, x21
    bl      strncmp
    cbnz    x0, h2_check_status
    
    /* Store authority */
    str     x22, [x19, #32]         /* h2req_authority */
    mov     x0, #0
    b       h2_process_header_done

h2_check_status:
    /* :status is for responses, not requests - ignore or error */
    mov     x0, #H2_ERROR_PROTOCOL_ERROR

h2_process_header_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* ================================================================================================
 * h2_build_http1_request_impl(request, buffer, buffer_size)
 * Build HTTP/1.1 style request buffer from HTTP/2 request
 * x0 = request context
 * x1 = output buffer
 * x2 = buffer size
 * Returns: x0 = request length, or error
 * ================================================================================================ */
h2_build_http1_request_impl:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    
    mov     x19, x0                 /* request context */
    mov     x20, x1                 /* output buffer */
    mov     x21, x2                 /* buffer size */
    mov     x22, x1                 /* current output position */
    
    /* Build: "METHOD PATH HTTP/1.1\r\n" */
    
    /* Copy method */
    ldr     x0, [x19, #16]          /* method */
    cbz     x0, h2_build_err_missing
    
    bl      strlen
    mov     x23, x0                 /* method length */
    
    /* Check buffer space */
    add     x24, x23, #1            /* method + space */
    cmp     x24, x21
    bgt     h2_build_err_too_large
    
    /* Copy method */
    mov     x0, x22
    ldr     x1, [x19, #16]
    mov     x2, x23
    bl      memcpy
    add     x22, x22, x23
    
    /* Add space */
    mov     w0, #' '
    strb    w0, [x22], #1
    
    /* Copy path */
    ldr     x0, [x19, #24]          /* path */
    cbz     x0, h2_build_err_missing
    
    bl      strlen
    mov     x23, x0
    
    /* Check buffer space */
    add     x24, x22, x23
    add     x24, x24, #11           /* path + " HTTP/1.1\r\n" */
    cmp     x24, x20
    bgt     h2_build_err_too_large
    
    /* Copy path */
    mov     x0, x22
    ldr     x1, [x19, #24]
    mov     x2, x23
    bl      memcpy
    add     x22, x22, x23
    
    /* Add " HTTP/1.1\r\n" */
    adr     x0, h2_http11_line
    mov     x1, x22
    mov     x2, #11
    bl      memcpy
    add     x22, x22, #11
    
    /* Add Host header from :authority */
    ldr     x0, [x19, #32]          /* authority */
    cbnz    x0, h2_build_add_host
    
    /* No authority - use "localhost" */
    adr     x0, h2_localhost
    
h2_build_add_host:
    bl      strlen
    mov     x23, x0
    
    /* Check buffer space: "Host: " + authority + "\r\n" */
    add     x24, x22, #8            /* "Host: \r\n" */
    add     x24, x24, x23
    cmp     x24, x20
    bgt     h2_build_err_too_large
    
    /* Add "Host: " */
    adr     x0, h2_host_header
    mov     x1, x22
    mov     x2, #6
    bl      memcpy
    add     x22, x22, #6
    
    /* Add authority */
    mov     x0, x22
    ldr     x1, [x19, #32]
    mov     x2, x23
    bl      memcpy
    add     x22, x22, x23
    
    /* Add \r\n */
    mov     w0, #0x0D0A             /* \r\n */
    strh    w0, [x22], #2
    
    /* TODO: Add other headers */
    
    /* Final \r\n */
    mov     w0, #0x0D0A
    strh    w0, [x22], #2
    
    /* Calculate total length */
    sub     x0, x22, x20
    b       h2_build_done

h2_build_err_missing:
    mov     x0, #H2_ERROR_PROTOCOL_ERROR
    b       h2_build_done

h2_build_err_too_large:
    mov     x0, #H2_ERROR_INTERNAL_ERROR

h2_build_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x25, x26, [sp, #64]
    ldp     x29, x30, [sp], #80
    ret

/* ================================================================================================
 * h2_process_request_impl(conn, stream, request)
 * Process HTTP/2 request and generate response
 * x0 = connection
 * x1 = stream
 * x2 = request context
 * Returns: x0 = 0 on success
 * ================================================================================================ */
h2_process_request_impl:
    stp     x29, x30, [sp, #-112]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* stream */
    mov     x21, x2                 /* request context */
    
    /* Build HTTP/1.1 request buffer */
    sub     sp, sp, #H2_MAX_REQUEST_BUFFER
    mov     x22, sp
    
    mov     x0, x21                 /* request */
    mov     x1, x22                 /* buffer */
    mov     x2, #H2_MAX_REQUEST_BUFFER
    bl      h2_build_http1_request_impl
    
    cmp     x0, #0
    blt     h2_process_err
    
    mov     x23, x0                 /* request length */
    
    /* Route the request */
    mov     x0, x19                 /* connection */
    mov     x1, x20                 /* stream */
    mov     x2, x21                 /* request */
    mov     x3, x22                 /* request buffer */
    mov     x4, x23                 /* request length */
    bl      h2_route_request
    
h2_process_done:
    add     sp, sp, #H2_MAX_REQUEST_BUFFER
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x25, x26, [sp, #64]
    ldp     x27, x28, [sp, #80]
    ldp     x29, x30, [sp], #112
    ret

h2_process_err:
    mov     x0, x0                  /* error code */
    b       h2_process_done

/* ================================================================================================
 * h2_route_request(conn, stream, request, buffer, length)
 * Route HTTP/2 request to appropriate handler
 * x0 = connection
 * x1 = stream
 * x2 = request context
 * x3 = request buffer
 * x4 = request length
 * Returns: x0 = 0 on success
 * ================================================================================================ */
h2_route_request:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* stream */
    mov     x21, x2                 /* request */
    mov     x22, x3                 /* buffer */
    
    /* Get path from request */
    ldr     x0, [x21, #24]          /* path */
    cbz     x0, h2_route_err
    
    /* Check if path starts with /cgi/ for CGI */
    ldrb    w1, [x0]
    cmp     w1, #'/'
    bne     h2_route_file           /* invalid path, try file anyway */
    
    /* Check for CGI */
    adr     x2, h2_cgi_prefix
    mov     x3, #5
    bl      strncmp
    cbz     x0, h2_route_cgi
    
    /* Default: serve file */
h2_route_file:
    mov     x0, x19                 /* connection */
    mov     x1, x20                 /* stream */
    mov     x2, x21                 /* request */
    mov     x3, x22                 /* buffer */
    bl      h2_serve_file
    b       h2_route_done

h2_route_cgi:
    /* TODO: Implement CGI for HTTP/2 */
    mov     x0, #H2_ERROR_INTERNAL_ERROR
    b       h2_route_done

h2_route_err:
    mov     x0, #H2_ERROR_PROTOCOL_ERROR

h2_route_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* ================================================================================================
 * h2_serve_file(conn, stream, request, buffer)
 * Serve static file via HTTP/2
 * x0 = connection
 * x1 = stream
 * x2 = request context
 * x3 = request buffer (for fallback)
 * Returns: x0 = 0 on success
 * ================================================================================================ */
h2_serve_file:
    stp     x29, x30, [sp, #-128]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* stream */
    mov     x21, x2                 /* request */
    
    /* Get document root from connection */
    ldr     x22, [x19, #32]         /* doc_root (assumed offset) */
    cbz     x22, h2_file_err_config
    
    /* Get path */
    ldr     x23, [x21, #24]         /* path */
    cbz     x23, h2_file_err_path
    
    /* Build full path: doc_root + path */
    sub     sp, sp, #512
    mov     x24, sp                 /* full path buffer */
    
    /* Copy doc_root */
    mov     x0, x22
    bl      strlen
    mov     x25, x0
    mov     x0, x24
    mov     x1, x22
    mov     x2, x25
    bl      memcpy
    
    /* Copy path */
    mov     x0, x23
    bl      strlen
    mov     x26, x0
    add     x0, x24, x25
    mov     x1, x23
    mov     x2, x26
    bl      memcpy
    
    /* Null terminate */
    add     x0, x24, x25
    add     x0, x0, x26
    strb    wzr, [x0]
    
    /* TODO: Open file, determine MIME type, and send via HTTP/2 */
    /* For now, just return success */
    
    add     sp, sp, #512
    mov     x0, #0
    b       h2_file_done

h2_file_err_config:
    mov     x0, #H2_ERROR_INTERNAL_ERROR
    b       h2_file_done

h2_file_err_path:
    mov     x0, #H2_ERROR_PROTOCOL_ERROR

h2_file_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x25, x26, [sp, #64]
    ldp     x27, x28, [sp, #80]
    ldp     x29, x30, [sp], #128
    ret

/* ================================================================================================
 * String Constants
 * ================================================================================================ */

.section .rodata
.align 3

h2_method_str:      .asciz ":method"
h2_path_str:        .asciz ":path"
h2_scheme_str:      .asciz ":scheme"
h2_authority_str:   .asciz ":authority"
h2_http11_line:     .asciz " HTTP/1.1\r\n"
h2_host_header:     .asciz "Host: "
h2_localhost:       .asciz "localhost"
h2_cgi_prefix:      .asciz "/cgi/"

.text
.align 2

/* External functions */
.global strlen
.global strncmp
.global memcpy
.global memset
.global itoa
