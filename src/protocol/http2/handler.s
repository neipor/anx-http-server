/* src/protocol/http2/handler.s - HTTP/2 Request Handler */

.include "src/defs.s"
.include "src/core/types.s"

.global h2_handle_headers
.global h2_handle_data
.global h2_build_response_headers

/* ========================================================================
 * HTTP/2 Stream Request Context
 * ======================================================================== */

.struct 0
h2req_stream_id:    .word 0         /* Stream ID */
h2req_state:        .word 0         /* Stream state */
h2req_method:       .quad 0         /* HTTP method string */
h2req_path:         .quad 0         /* Request path */
h2req_authority:    .quad 0         /* :authority */
h2req_scheme:       .quad 0         /* :scheme */
h2req_headers:      .quad 0         /* Pointer to headers buffer */
h2req_body:         .quad 0         /* Pointer to body buffer */
h2req_body_len:     .quad 0         /* Body length */
h2req_content_length: .quad 0       /* Content-Length header */
.struct 96

/* ========================================================================
 * Handle HEADERS Frame
 * ======================================================================== */

/*
 * h2_handle_headers(conn, stream, frame, payload)
 * x0 = connection pointer
 * x1 = stream pointer
 * x2 = frame header pointer
 * x3 = payload pointer
 * Returns: x0 = 0 on success, error code on failure
 */
h2_handle_headers:
    stp     x29, x30, [sp, #-128]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* stream */
    mov     x21, x2                 /* frame header */
    mov     x22, x3                 /* payload */
    
    /* Check END_HEADERS flag */
    ldrb    w0, [x21, #4]           /* frame flags */
    tst     w0, #0x04               /* END_HEADERS */
    beq     h2_headers_need_continuation
    
    /* Get payload length */
    ldr     w23, [x21]              /* length field (24 bits) */
    and     x23, x23, #0xFFFFFF     /* mask to 24 bits */
    
    /* Check for padding */
    tst     w0, #0x08               /* PADDED */
    beq     h2_headers_no_pad
    
    /* Read pad length */
    ldrb    w24, [x22]              /* Pad Length */
    add     x22, x22, #1            /* Skip pad length field */
    sub     x23, x23, x24           /* Subtract padding from payload */
    sub     x23, x23, #1            /* Subtract pad length field */

h2_headers_no_pad:
    /* Check for priority */
    tst     w0, #0x20               /* PRIORITY */
    beq     h2_headers_no_priority
    
    /* Skip priority fields (5 bytes) */
    add     x22, x22, #5
    sub     x23, x23, #5

h2_headers_no_priority:
    
    /* Decode HPACK headers */
    /* Allocate request context on stack */
    sub     sp, sp, #96
    mov     x25, sp                 /* request context */
    
    /* Clear request context */
    mov     x0, x25
    mov     x1, #0
    mov     x2, #96
    bl      memset
    
    /* Store stream ID */
    ldr     w0, [x21, #5]           /* stream ID */
    str     w0, [x25]               /* h2req_stream_id */
    
    /* Decode headers using HPACK */
    add     x0, x19, #136           /* hpack decoder context (assumed offset) */
    mov     x1, x22                 /* payload */
    mov     x2, x23                 /* payload length */
    mov     x3, x25                 /* request context */
    bl      hpack_decode_headers
    cmp     x0, #0
    blt     h2_headers_decode_error
    
    /* Check if we have all required pseudo-headers */
    ldr     x0, [x25, #16]          /* :method */
    cbz     x0, h2_headers_missing_method
    ldr     x0, [x25, #24]          /* :path */
    cbz     x0, h2_headers_missing_path
    ldr     x0, [x25, #32]          /* :authority */
    cbz     x0, h2_headers_missing_authority
    ldr     x0, [x25, #40]          /* :scheme */
    cbz     x0, h2_headers_missing_scheme
    
    /* Build HTTP/1.1 style request buffer for reuse with existing code */
    mov     x0, x25
    bl      h2_build_http1_request
    cmp     x0, #0
    blt     h2_headers_build_error
    
    /* Process request (reuse existing HTTP/1.1 logic) */
    mov     x0, x19                 /* connection */
    mov     x1, x20                 /* stream */
    mov     x2, x25                 /* request context */
    bl      h2_process_request
    
    /* Check for END_STREAM flag */
    ldrb    w0, [x21, #4]           /* flags */
    tst     w0, #0x01               /* END_STREAM */
    beq     h2_headers_keep_alive
    
    /* END_STREAM: half-close the stream */
    ldr     w0, [x20, #4]           /* stream state */
    cmp     w0, #H2_STREAM_OPEN
    bne     h2_headers_state_error
    mov     w0, #H2_STREAM_HALF_CLOSED_REMOTE
    str     w0, [x20, #4]

h2_headers_keep_alive:
    add     sp, sp, #96             /* Free request context */
    mov     x0, #0
    b       h2_headers_done

h2_headers_need_continuation:
    /* Need CONTINUATION frame - for now, error */
    mov     x0, #H2_ERROR_PROTOCOL_ERROR
    b       h2_headers_done

h2_headers_decode_error:
    add     sp, sp, #96
    mov     x0, #H2_ERROR_COMPRESSION
    b       h2_headers_done

h2_headers_missing_method:
    add     sp, sp, #96
    mov     x0, #H2_ERROR_PROTOCOL_ERROR
    b       h2_headers_done

h2_headers_missing_path:
    add     sp, sp, #96
    mov     x0, #H2_ERROR_PROTOCOL_ERROR
    b       h2_headers_done

h2_headers_missing_authority:
    add     sp, sp, #96
    mov     x0, #H2_ERROR_PROTOCOL_ERROR
    b       h2_headers_done

h2_headers_missing_scheme:
    add     sp, sp, #96
    mov     x0, #H2_ERROR_PROTOCOL_ERROR
    b       h2_headers_done

h2_headers_build_error:
    add     sp, sp, #96
    mov     x0, #H2_ERROR_INTERNAL_ERROR
    b       h2_headers_done

h2_headers_state_error:
    add     sp, sp, #96
    mov     x0, #H2_ERROR_PROTOCOL_ERROR

h2_headers_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x25, x26, [sp, #64]
    ldp     x27, x28, [sp, #80]
    ldp     x29, x30, [sp], #128
    ret

/* ========================================================================
 * Handle DATA Frame
 * ======================================================================== */

/*
 * h2_handle_data(conn, stream, frame, payload)
 * x0 = connection
 * x1 = stream
 * x2 = frame header
 * x3 = payload
 * Returns: x0 = 0 on success
 */
h2_handle_data:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2
    mov     x22, x3
    
    /* Get payload length */
    ldr     w2, [x21]
    and     x2, x2, #0xFFFFFF
    
    /* Check for padding */
    ldrb    w0, [x21, #4]
    tst     w0, #0x08
    beq     h2_data_no_pad
    
    /* Read and subtract padding */
    ldrb    w3, [x22]
    add     x22, x22, #1
    sub     x2, x2, x3
    sub     x2, x2, #1

h2_data_no_pad:
    /* Append data to stream's request body buffer */
    /* For now, just process immediately */
    
    /* Check flow control windows */
    /* TODO: Update connection and stream flow control */
    
    /* Check END_STREAM flag */
    ldrb    w0, [x21, #4]
    tst     w0, #0x01
    beq     h2_data_done
    
    /* END_STREAM: half-close stream */
    ldr     w0, [x20, #4]
    cmp     w0, #H2_STREAM_OPEN
    bne     h2_data_state_ok
    mov     w0, #H2_STREAM_HALF_CLOSED_REMOTE
    str     w0, [x20, #4]

h2_data_state_ok:
h2_data_done:
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* ========================================================================
 * Build HTTP/1.1 Request from HTTP/2
 * ======================================================================== */

/*
 * h2_build_http1_request(request_context) - Build HTTP/1.1 style request
 * x0 = request context
 * Returns: x0 = 0 on success
 */
h2_build_http1_request:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Build request buffer in format expected by existing code */
    /* Format: "METHOD PATH HTTP/1.1\r\nHost: authority\r\n...headers...\r\n" */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Process HTTP/2 Request
 * ======================================================================== */

/*
 * h2_process_request(conn, stream, request)
 * x0 = connection
 * x1 = stream
 * x2 = request context
 */
h2_process_request:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Route to appropriate handler */
    /* 1. Check path and route */
    /* 2. Read file or process request */
    /* 3. Build HTTP/2 response */
    /* 4. Send HEADERS frame */
    /* 5. Send DATA frames */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * HPACK Decode Headers (simplified)
 * ======================================================================== */

/*
 * hpack_decode_headers(context, input, input_len, request)
 * x0 = HPACK context
 * x1 = input buffer
 * x2 = input length
 * x3 = request context to fill
 */
hpack_decode_headers:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Implement full HPACK decoding */
    /* For now, stub */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Build HTTP/2 Response Headers
 * ======================================================================== */

/*
 * h2_build_response_headers(status_code, headers, output)
 * x0 = HTTP status code
 * x1 = additional headers (nullable)
 * x2 = output buffer for HPACK encoded headers
 * Returns: x0 = encoded length
 */
h2_build_response_headers:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* status code */
    mov     x20, x2                 /* output buffer */
    
    /* Encode :status pseudo-header */
    /* Convert status code to string */
    mov     x0, x19
    add     x1, sp, #40             /* temp buffer for status string */
    bl      itoa
    
    /* TODO: Encode :status using HPACK */
    /* For indexed status, use static table index 8 (200), 9 (204), etc. */
    
    /* Encode content-type if provided */
    /* Encode content-length */
    
    mov     x0, #0                  /* return length */
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* External functions */
.global memset
.global itoa

