/* src/protocol/http2/streams.s - HTTP/2 Stream Management */

.include "src/defs.s"
.include "src/core/types.s"

/* HTTP/2 Error Codes */
.equ H2_ERROR_NO_ERROR,         0x0
.equ H2_ERROR_PROTOCOL_ERROR,   0x1
.equ H2_ERROR_INTERNAL_ERROR,   0x2
.equ H2_ERROR_FLOW_CONTROL,     0x3
.equ H2_ERROR_SETTINGS_TIMEOUT, 0x4
.equ H2_ERROR_STREAM_CLOSED,    0x5
.equ H2_ERROR_FRAME_SIZE,       0x6
.equ H2_ERROR_REFUSED_STREAM,   0x7
.equ H2_ERROR_CANCEL,           0x8
.equ H2_ERROR_COMPRESSION,      0x9
.equ H2_ERROR_CONNECT_ERROR,    0xA
.equ H2_ERROR_ENHANCE_YOUR_CALM, 0xB
.equ H2_ERROR_INADEQUATE_SECURITY, 0xC
.equ H2_ERROR_HTTP_1_1_REQUIRED, 0xD

.global h2_stream_create
.global h2_stream_find
.global h2_stream_close
.global h2_stream_send_headers
.global h2_stream_send_data
.global h2_stream_recv_headers
.global h2_stream_recv_data
.global h2_stream_update_window

/* ========================================================================
 * Stream State Machine
 * ======================================================================== */

/* Stream States (RFC 7540 Section 5.1) */
.equ H2_STREAM_IDLE,            0
.equ H2_STREAM_RESERVED_LOCAL,  1
.equ H2_STREAM_RESERVED_REMOTE, 2
.equ H2_STREAM_OPEN,            3
.equ H2_STREAM_HALF_CLOSED_LOCAL,   4
.equ H2_STREAM_HALF_CLOSED_REMOTE,  5
.equ H2_STREAM_CLOSED,          6

/* Stream Flags */
.equ H2_STREAM_FLAG_SEND_END_HEADERS,   0x01
.equ H2_STREAM_FLAG_RECV_END_HEADERS,   0x02
.equ H2_STREAM_FLAG_SEND_END_STREAM,    0x04
.equ H2_STREAM_FLAG_RECV_END_STREAM,    0x08

/* Stream Structure (128 bytes) - cache line optimized */
.struct 0
h2s_id:             .word 0         /* Stream ID */
h2s_state:          .word 0         /* Stream state */
h2s_flags:          .word 0         /* Stream flags */
h2s_weight:         .word 0         /* Priority weight */
h2s_dependency:     .word 0         /* Stream dependency */
h2s_pad1:           .skip 12        /* Padding to 32 bytes */

/* Flow Control (offset 32) */
h2s_window_local:   .word 0         /* Send window */
h2s_window_remote:  .word 0         /* Receive window */
h2s_pad2:           .skip 24        /* Padding to 64 bytes */

/* Request/Response (offset 64) */
h2s_req_headers:    .quad 0         /* Request headers (HPACK decoded) */
h2s_req_body:       .quad 0         /* Request body buffer */
h2s_res_headers:    .quad 0         /* Response headers */
h2s_res_body:       .quad 0         /* Response body */
h2s_pad3:           .skip 32        /* Padding to 128 bytes */
.struct 128

/* Stream Table - simple hash table */
.equ H2_STREAM_TABLE_SIZE,  64      /* Must be power of 2 */
.equ H2_STREAM_HASH_MASK,   0x3F

.data
.align 3
h2_stream_table:    .skip H2_STREAM_TABLE_SIZE * 8  /* Array of stream pointers */

.text

/* ========================================================================
 * Stream Creation
 * ======================================================================== */

/*
 * h2_stream_create(conn, stream_id) - Create new stream
 * x0 = connection pointer
 * x1 = stream ID
 * Returns: x0 = stream pointer, or 0 on failure
 */
h2_stream_create:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* Connection */
    mov     w20, w1                 /* Stream ID */
    
    /* Check if stream ID is valid */
    cmp     w20, #0
    beq     h2_stream_create_fail
    
    /* Allocate stream structure (128 bytes) */
    mov     x0, #128
    bl      mem_pool_alloc
    cmp     x0, #0
    beq     h2_stream_create_fail
    
    mov     x21, x0                 /* Stream pointer */
    
    /* Clear stream structure */
    mov     x22, x0
    mov     x0, x21
    mov     x1, #0
    mov     x2, #128
    bl      memset
    mov     x0, x22
    
    /* Initialize stream */
    str     w20, [x21]              /* h2s_id */
    
    /* Determine initial state based on ID parity */
    ands    w22, w20, #1            /* Check if odd (client) or even (server) */
    beq     h2_stream_server_init
    
    /* Client-initiated stream (odd ID) */
    mov     w0, #H2_STREAM_OPEN
    str     w0, [x21, #4]           /* h2s_state = OPEN */
    b       h2_stream_init_window

h2_stream_server_init:
    /* Server-initiated stream (even ID) */
    /* Server can only create streams with PUSH_PROMISE */
    /* For now, reject server-initiated streams */
    mov     x0, x21
    mov     x1, #128
    bl      mem_pool_free
    mov     x0, #0
    b       h2_stream_create_done

h2_stream_init_window:
    /* Get connection's INITIAL_WINDOW_SIZE settings */
    mov     x0, x19
    add     x0, x0, #16             /* h2c_settings_local */
    ldr     w1, [x0, #28]           /* INITIAL_WINDOW_SIZE */
    
    str     w1, [x21, #32]          /* h2s_window_local */
    
    mov     x0, x19
    add     x0, x0, #64             /* h2c_settings_remote */
    ldr     w1, [x0, #28]           /* INITIAL_WINDOW_SIZE */
    
    str     w1, [x21, #36]          /* h2s_window_remote */
    
    /* Add to connection's stream count */
    ldr     w0, [x19, #128]         /* h2c_stream_count */
    add     w0, w0, #1
    str     w0, [x19, #128]
    
    /* Insert into stream table */
    mov     x0, x21
    bl      h2_stream_insert
    
    mov     x0, x21                 /* Return stream pointer */
    b       h2_stream_create_done

h2_stream_create_fail:
    mov     x0, #0

h2_stream_create_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* ========================================================================
 * Stream Lookup
 * ======================================================================== */

/*
 * h2_stream_find(conn, stream_id) - Find stream by ID
 * x0 = connection pointer
 * x1 = stream ID
 * Returns: x0 = stream pointer, or 0 if not found
 */
h2_stream_find:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* Connection */
    mov     w20, w1                 /* Stream ID */
    
    /* Compute hash: stream_id & (table_size - 1) */
    and     w21, w20, #H2_STREAM_HASH_MASK
    
    /* Get stream table base */
    ldr     x22, [x19, #120]        /* h2c_streams */
    
    /* Compute bucket address: base + hash * 8 */
    add     x22, x22, x21, lsl #3
    
    /* Walk chain */
    ldr     x0, [x22]               /* First stream in bucket */
    
h2_find_loop:
    cmp     x0, #0
    beq     h2_find_not_found
    
    ldr     w1, [x0]                /* stream->id */
    cmp     w1, w20
    beq     h2_find_done
    
    ldr     x0, [x0, #120]          /* stream->next (using padding space) */
    b       h2_find_loop

h2_find_not_found:
    mov     x0, #0

h2_find_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * Stream Insert
 * ======================================================================== */

/*
 * h2_stream_insert(stream) - Insert stream into hash table
 * x0 = stream pointer
 */
h2_stream_insert:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Implement hash table insertion */
    /* For now, this is a stub */
    
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Stream Close
 * ======================================================================== */

/*
 * h2_stream_close(stream, error_code) - Close stream
 * x0 = stream pointer
 * x1 = error code (0 for normal close)
 */
h2_stream_close:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* Stream */
    mov     w20, w1                 /* Error code */
    
    /* Update state */
    mov     w0, #H2_STREAM_CLOSED
    str     w0, [x19, #4]           /* h2s_state */
    
    /* Free request/response buffers */
    ldr     x0, [x19, #64]          /* h2s_req_headers */
    cmp     x0, #0
    beq     h2_close_no_req_headers
    mov     x1, #4096               /* Assuming 4KB buffer */
    bl      mem_pool_free

h2_close_no_req_headers:
    ldr     x0, [x19, #72]          /* h2s_req_body */
    cmp     x0, #0
    beq     h2_close_no_req_body
    bl      mem_pool_free           /* Size stored elsewhere */

h2_close_no_req_body:
    /* TODO: Remove from hash table */
    
    /* Free stream structure */
    mov     x0, x19
    mov     x1, #128
    bl      mem_pool_free
    
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * Flow Control
 * ======================================================================== */

/*
 * h2_stream_update_window(stream, delta, local) - Update flow control window
 * x0 = stream pointer
 * x1 = delta (can be negative)
 * x2 = 1 for local window, 0 for remote
 * Returns: x0 = 0 on success, error code on failure
 */
h2_stream_update_window:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    cmp     x2, #0
    beq     h2_update_remote
    
    /* Update local (send) window */
    ldr     w3, [x0, #32]           /* h2s_window_local */
    add     w3, w3, w1              /* Add delta */
    
    /* Check for overflow/underflow */
    cmp     w3, #0
    blt     h2_window_error
    mov     w4, #0x7FFFFFFF         /* 2^31 - 1 */
    cmp     w3, w4
    bgt     h2_window_error
    
    str     w3, [x0, #32]
    b       h2_window_ok

h2_update_remote:
    /* Update remote (receive) window */
    ldr     w3, [x0, #36]           /* h2s_window_remote */
    add     w3, w3, w1
    
    cmp     w3, #0
    blt     h2_window_error
    mov     w4, #0x7FFFFFFF
    cmp     w3, w4
    bgt     h2_window_error
    
    str     w3, [x0, #36]

h2_window_ok:
    mov     x0, #0
    b       h2_window_done

h2_window_error:
    mov     x0, #H2_ERROR_FLOW_CONTROL

h2_window_done:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Send Headers
 * ======================================================================== */

/*
 * h2_stream_send_headers(stream, headers, flags) - Send HEADERS frame
 * x0 = stream pointer
 * x1 = HPACK-encoded headers
 * x2 = flags (END_HEADERS, END_STREAM, etc.)
 * Returns: x0 = bytes sent, or error code
 */
h2_stream_send_headers:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Build HEADERS frame and send */
    /* For now, stub implementation */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Send Data
 * ======================================================================== */

/*
 * h2_stream_send_data(stream, data, len, flags) - Send DATA frame
 * x0 = stream pointer
 * x1 = data pointer
 * x2 = data length
 * x3 = flags (END_STREAM)
 * Returns: x0 = bytes sent, or error code
 */
h2_stream_send_data:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* Stream */
    mov     x20, x2                 /* Length */
    
    /* Check flow control window */
    ldr     w4, [x19, #32]          /* h2s_window_local */
    cmp     w4, w20
    blt     h2_send_data_blocked
    
    /* TODO: Build DATA frame respecting MAX_FRAME_SIZE */
    /* For now, stub */
    
    /* Update window */
    sub     w4, w4, w20
    str     w4, [x19, #32]
    
    mov     x0, x20                 /* Return bytes sent */
    b       h2_send_data_done

h2_send_data_blocked:
    mov     x0, #0                  /* Would block */

h2_send_data_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * Receive Headers
 * ======================================================================== */

/*
 * h2_stream_recv_headers(stream, headers, len) - Process received headers
 * x0 = stream pointer
 * x1 = HPACK-encoded headers
 * x2 = length
 */
h2_stream_recv_headers:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: HPACK decode and process */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Receive Data
 * ======================================================================== */

/*
 * h2_stream_recv_data(stream, data, len) - Process received data
 * x0 = stream pointer
 * x1 = data pointer
 * x2 = data length
 */
h2_stream_recv_data:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Check window */
    ldr     w3, [x0, #36]           /* h2s_window_remote */
    cmp     w3, w2
    blt     h2_recv_data_error
    
    /* Update window */
    sub     w3, w3, w2
    str     w3, [x0, #36]
    
    /* TODO: Process data (pass to HTTP handler) */
    
    mov     x0, #0
    b       h2_recv_data_done

h2_recv_data_error:
    mov     x0, #H2_ERROR_FLOW_CONTROL

h2_recv_data_done:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Helper: memset
 * ======================================================================== */
memset:
    cmp     x2, #0
    beq     memset_done
    mov     x3, #0
memset_loop:
    strb    w1, [x0, x3]
    add     x3, x3, #1
    cmp     x3, x2
    blt     memset_loop
memset_done:
    ret

