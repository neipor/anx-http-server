/* src/protocol/http2/response.s - HTTP/2 Response Builder */

.include "src/defs.s"
.include "src/core/types.s"

.global h2_send_response
.global h2_send_headers_frame
.global h2_send_data_frame
.global h2_build_headers_block

/* ========================================================================
 * Send HTTP/2 Response
 * ======================================================================== */

/*
 * h2_send_response(conn, stream, status, headers, body, body_len)
 * x0 = connection
 * x1 = stream
 * x2 = HTTP status code
 * x3 = response headers (optional, can be 0)
 * x4 = body pointer
 * x5 = body length
 * Returns: x0 = 0 on success
 */
h2_send_response:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* stream */
    mov     x21, x2                 /* status code */
    mov     x22, x3                 /* headers */
    mov     x23, x4                 /* body */
    mov     x24, x5                 /* body_len */
    
    /* Get stream ID */
    ldr     w26, [x20]              /* stream_id */
    
    /* Build headers block */
    sub     sp, sp, #8192           /* headers buffer */
    mov     x25, sp
    
    mov     x0, x19                 /* connection */
    mov     x1, x21                 /* status */
    mov     x2, x22                 /* headers */
    mov     x3, x25                 /* output buffer */
    bl      h2_build_headers_block
    mov     x27, x0                 /* headers length */
    
    /* Send HEADERS frame */
    mov     x0, x19                 /* connection */
    mov     x1, x26                 /* stream_id */
    mov     x2, x25                 /* headers block */
    mov     x3, x27                 /* length */
    mov     x4, #1                  /* END_HEADERS */
    cmp     x24, #0                 /* if no body, add END_STREAM */
    csel    x4, x4, x5, eq
    bl      h2_send_headers_frame
    cmp     x0, #0
    blt     h2_resp_error
    
    /* Send body if present */
    cmp     x24, #0
    beq     h2_resp_success
    
    mov     x0, x19                 /* connection */
    mov     x1, x26                 /* stream_id */
    mov     x2, x23                 /* body */
    mov     x3, x24                 /* body_len */
    mov     x4, #1                  /* END_STREAM */
    bl      h2_send_data_frame
    cmp     x0, #0
    blt     h2_resp_error

h2_resp_success:
    add     sp, sp, #8192           /* free headers buffer */
    mov     x0, #0
    b       h2_resp_done

h2_resp_error:
    add     sp, sp, #8192
    mov     x0, #-1

h2_resp_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x25, x26, [sp, #64]
    ldp     x27, x28, [sp, #80]
    ldp     x29, x30, [sp], #96
    ret

/* ========================================================================
 * Build Headers Block (HPACK encoded)
 * ======================================================================== */

/*
 * h2_build_headers_block(conn, status, headers, output)
 * x0 = connection
 * x1 = status code
 * x2 = extra headers
 * x3 = output buffer
 * Returns: x0 = encoded length
 */
h2_build_headers_block:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* status */
    mov     x21, x2                 /* headers */
    mov     x22, x3                 /* output */
    mov     x23, x3                 /* current output position */
    
    /* Encode :status pseudo-header */
    /* Convert status to string */
    mov     x0, x20
    add     x1, sp, #40             /* temp buffer */
    bl      itoa
    mov     x24, x0                 /* status string length */
    
    /* TODO: Use indexed status if common (200, 204, 404, etc.) */
    /* For now, encode as literal with indexing */
    
    add     sp, sp, #64             /* cleanup */
    
    /* Return encoded length */
    sub     x0, x23, x22
    
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

/* ========================================================================
 * Send HEADERS Frame
 * ======================================================================== */

/*
 * h2_send_headers_frame(conn, stream_id, headers, len, flags)
 * x0 = connection
 * x1 = stream_id
 * x2 = headers block
 * x3 = length
 * x4 = flags (END_HEADERS, END_STREAM)
 */
h2_send_headers_frame:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* connection */
    mov     x20, x2                 /* headers */
    mov     x21, x3                 /* length */
    
    /* Build frame header on stack */
    sub     sp, sp, #9
    
    /* Length (3 bytes, big-endian) */
    mov     x5, x21
    lsr     x6, x5, #16
    strb    w6, [sp]
    lsr     x6, x5, #8
    strb    w6, [sp, #1]
    strb    w5, [sp, #2]
    
    /* Type: HEADERS (0x01) */
    mov     w6, #0x01
    strb    w6, [sp, #3]
    
    /* Flags */
    strb    w4, [sp, #4]
    
    /* Stream ID (4 bytes, big-endian) */
    rev     w6, w1
    str     w6, [sp, #5]
    
    /* Send frame header */
    ldr     w0, [x19, #152]         /* connection fd */
    mov     x1, sp
    mov     x2, #9
    mov     x8, #SYS_WRITE
    svc     #0
    
    cmp     x0, #0
    blt     h2_headers_send_error
    
    /* Send headers block */
    ldr     w0, [x19, #152]
    mov     x1, x20
    mov     x2, x21
    mov     x8, #SYS_WRITE
    svc     #0
    
    cmp     x0, #0
    blt     h2_headers_send_error
    
    add     sp, sp, #9
    mov     x0, #0
    b       h2_headers_send_done

h2_headers_send_error:
    add     sp, sp, #9
    mov     x0, #-1

h2_headers_send_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* ========================================================================
 * Send DATA Frame
 * ======================================================================== */

/*
 * h2_send_data_frame(conn, stream_id, data, len, flags)
 * x0 = connection
 * x1 = stream_id  
 * x2 = data
 * x3 = length
 * x4 = flags (END_STREAM)
 */
h2_send_data_frame:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* connection */
    mov     x20, x2                 /* data */
    mov     x21, x3                 /* length */
    
    /* Build frame header */
    sub     sp, sp, #9
    
    /* Length (3 bytes) */
    mov     x5, x21
    lsr     x6, x5, #16
    strb    w6, [sp]
    lsr     x6, x5, #8
    strb    w6, [sp, #1]
    strb    w5, [sp, #2]
    
    /* Type: DATA (0x00) */
    strb    wzr, [sp, #3]
    
    /* Flags */
    strb    w4, [sp, #4]
    
    /* Stream ID */
    rev     w6, w1
    str     w6, [sp, #5]
    
    /* Send header */
    ldr     w0, [x19, #152]
    mov     x1, sp
    mov     x2, #9
    mov     x8, #SYS_WRITE
    svc     #0
    
    cmp     x0, #0
    blt     h2_data_send_error
    
    /* Send data */
    ldr     w0, [x19, #152]
    mov     x1, x20
    mov     x2, x21
    mov     x8, #SYS_WRITE
    svc     #0
    
    cmp     x0, #0
    blt     h2_data_send_error
    
    add     sp, sp, #9
    mov     x0, #0
    b       h2_data_send_done

h2_data_send_error:
    add     sp, sp, #9
    mov     x0, #-1

h2_data_send_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* External functions */
.global itoa
.global memcpy

