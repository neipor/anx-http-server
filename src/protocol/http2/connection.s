/* src/protocol/http2/connection.s - HTTP/2 Connection Management */

.include "src/defs.s"
.include "src/core/types.s"
.include "src/protocol/http2/frames.s"

.global h2_conn_init
.global h2_conn_handle_frame
.global h2_conn_send_settings
.global h2_conn_close
.global h2_conn_process_preface

/* ========================================================================
 * HTTP/2 Connection State
 * ======================================================================== */

/* Connection State */
.equ H2_CONN_IDLE,          0
.equ H2_CONN_OPEN,          1
.equ H2_CONN_CLOSING,       2
.equ H2_CONN_CLOSED,        3

/* Connection Structure (256 bytes) */
.struct 0
h2c_state:          .word 0         /* Connection state */
h2c_flags:          .word 0         /* Flags: bit0=server, bit1=preface_received */
h2c_next_stream_id: .word 0         /* Next stream ID to allocate */
h2c_last_stream_id: .word 0         /* Last processed stream ID */

/* SETTINGS */
h2c_settings_local: .skip 48         /* 6 settings * 8 bytes (id + value) */
h2c_settings_remote:.skip 48         /* Peer settings */
h2c_settings_ack:   .word 0         /* Settings ACK pending */

/* Flow Control */
h2c_window_local:   .word 0         /* Connection-level send window */
h2c_window_remote:  .word 0         /* Connection-level receive window */

/* Streams */
h2c_streams:        .quad 0         /* Pointer to stream table */
h2c_stream_count:   .word 0         /* Active stream count */
h2c_max_streams:    .word 0         /* Max concurrent streams */

/* HPACK */
h2c_hpack_enc:      .quad 0         /* HPACK encoder context */
h2c_hpack_dec:      .quad 0         /* HPACK decoder context */

/* I/O */
h2c_fd:             .word 0         /* Socket fd */
h2c_send_buf:       .quad 0         /* Send buffer */
h2c_recv_buf:       .quad 0         /* Receive buffer */

/* Padding for alignment */
h2c_pad:            .skip 64
.struct 256

/* Default Settings Values (RFC 7540 Section 6.5.2) */
.equ H2_DEFAULT_HEADER_TABLE_SIZE,      4096
.equ H2_DEFAULT_ENABLE_PUSH,            1
.equ H2_DEFAULT_MAX_CONCURRENT_STREAMS, 100
.equ H2_DEFAULT_INITIAL_WINDOW_SIZE,    65535
.equ H2_DEFAULT_MAX_FRAME_SIZE,         16384
.equ H2_DEFAULT_MAX_HEADER_LIST_SIZE,   0       /* Unlimited */

/* Our optimized settings */
.equ H2_OPTIMIZED_MAX_CONCURRENT_STREAMS, 1000
.equ H2_OPTIMIZED_INITIAL_WINDOW_SIZE,   131072  /* 128KB - larger for throughput */

/* Connection preface (client magic) */
.data
.align 3
h2_client_preface:  .ascii "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
h2_preface_len = . - h2_client_preface

/* Server SETTINGS frame (pre-built for performance) */
h2_server_settings:
    .byte 0x00, 0x00, 0x12       /* Length: 18 bytes (6 settings) */
    .byte 0x04                   /* Type: SETTINGS */
    .byte 0x00                   /* Flags: none */
    .byte 0x00, 0x00, 0x00, 0x00 /* Stream ID: 0 */
    /* Setting 1: HEADER_TABLE_SIZE = 4096 */
    .byte 0x00, 0x01
    .word 0x00001000             /* 4096 (big-endian) */
    /* Setting 2: ENABLE_PUSH = 0 (server doesn't push) */
    .byte 0x00, 0x02
    .word 0x00000000
    /* Setting 3: MAX_CONCURRENT_STREAMS = 1000 */
    .byte 0x00, 0x03
    .word 0x000003E8             /* 1000 */
    /* Setting 4: INITIAL_WINDOW_SIZE = 131072 */
    .byte 0x00, 0x04
    .word 0x00020000             /* 131072 */
    /* Setting 5: MAX_FRAME_SIZE = 16384 */
    .byte 0x00, 0x05
    .word 0x00004000             /* 16384 */
    /* Setting 6: MAX_HEADER_LIST_SIZE = unlimited */
    .byte 0x00, 0x06
    .word 0x00000000
h2_server_settings_len = . - h2_server_settings

/* SETTINGS ACK frame (pre-built) */
h2_settings_ack:
    .byte 0x00, 0x00, 0x00       /* Length: 0 */
    .byte 0x04                   /* Type: SETTINGS */
    .byte 0x01                   /* Flags: ACK */
    .byte 0x00, 0x00, 0x00, 0x00 /* Stream ID: 0 */
h2_settings_ack_len = . - h2_settings_ack

.text

/* ========================================================================
 * Connection Initialization
 * ======================================================================== */

/*
 * h2_conn_init(conn, fd) - Initialize HTTP/2 connection
 * x0 = connection structure pointer
 * x1 = socket file descriptor
 * Returns: x0 = 0 on success
 */
h2_conn_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* Connection pointer */
    mov     x20, x1                 /* Socket fd */
    
    /* Clear connection structure */
    mov     x0, x19
    mov     x1, #0
    mov     x2, #256
    bl      memset
    
    /* Initialize state */
    mov     w0, #H2_CONN_IDLE
    str     w0, [x19]               /* h2c_state */
    
    mov     w0, #1
    str     w0, [x19, #4]           /* h2c_flags: server mode */
    
    mov     w0, #2
    str     w0, [x19, #8]           /* h2c_next_stream_id: start at 2 (server) */
    
    mov     w0, #0
    str     w0, [x19, #12]          /* h2c_last_stream_id */
    
    /* Initialize default settings - local (what we accept) */
    mov     x0, x19
    add     x0, x0, #16             /* h2c_settings_local */
    
    /* HEADER_TABLE_SIZE = 4096 */
    mov     w1, #1
    strh    w1, [x0]
    mov     w1, #4096
    str     w1, [x0, #4]
    
    /* ENABLE_PUSH = 0 */
    mov     w1, #2
    strh    w1, [x0, #8]
    str     wzr, [x0, #12]
    
    /* MAX_CONCURRENT_STREAMS = 1000 */
    mov     w1, #3
    strh    w1, [x0, #16]
    mov     w1, #1000
    str     w1, [x0, #20]
    
    /* INITIAL_WINDOW_SIZE = 131072 */
    mov     w1, #4
    strh    w1, [x0, #24]
    mov     w1, #131072
    str     w1, [x0, #28]
    
    /* MAX_FRAME_SIZE = 16384 */
    mov     w1, #5
    strh    w1, [x0, #32]
    mov     w1, #16384
    str     w1, [x0, #36]
    
    /* MAX_HEADER_LIST_SIZE = 0 (unlimited) */
    mov     w1, #6
    strh    w1, [x0, #40]
    str     wzr, [x0, #44]
    
    /* Initialize remote settings to RFC defaults */
    mov     x0, x19
    add     x0, x0, #64             /* h2c_settings_remote */
    
    mov     w1, #1
    strh    w1, [x0]
    mov     w1, #4096
    str     w1, [x0, #4]
    
    mov     w1, #2
    strh    w1, [x0, #8]
    mov     w1, #1
    str     w1, [x0, #12]
    
    mov     w1, #3
    strh    w1, [x0, #16]
    mov     w1, #-1                 /* Unlimited */
    str     w1, [x0, #20]
    
    mov     w1, #4
    strh    w1, [x0, #24]
    mov     w1, #65535
    str     w1, [x0, #28]
    
    mov     w1, #5
    strh    w1, [x0, #32]
    mov     w1, #16384
    str     w1, [x0, #36]
    
    mov     w1, #6
    strh    w1, [x0, #40]
    str     wzr, [x0, #44]
    
    /* Initialize flow control windows */
    mov     w0, #H2_OPTIMIZED_INITIAL_WINDOW_SIZE
    str     w0, [x19, #112]         /* h2c_window_local */
    str     w0, [x19, #116]         /* h2c_window_remote */
    
    /* Store fd */
    str     w20, [x19, #152]        /* h2c_fd */
    
    /* Initialize stream table - allocate memory */
    mov     x0, #4096               /* Space for 64 streams */
    bl      mem_pool_alloc
    cmp     x0, #0
    beq     h2_init_fail
    
    str     x0, [x19, #120]         /* h2c_streams */
    str     wzr, [x19, #128]        /* h2c_stream_count = 0 */
    mov     w0, #1000
    str     w0, [x19, #132]         /* h2c_max_streams = 1000 */
    
    /* Success */
    mov     x0, #0
    b       h2_init_done

h2_init_fail:
    mov     x0, #ERR_NOMEM

h2_init_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * Preface Processing
 * ======================================================================== */

/*
 * h2_conn_process_preface(conn, buffer, len) - Process client preface
 * x0 = connection pointer
 * x1 = buffer with received data
 * x2 = buffer length
 * Returns: x0 = bytes consumed (24 on success), error code on failure
 */
h2_conn_process_preface:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Check if enough data */
    cmp     x2, #24
    blt     h2_preface_need_more
    
    /* Compare with expected preface */
    ldr     x3, =h2_client_preface
    mov     x4, #24
    
preface_cmp_loop:
    ldrb    w5, [x1], #1
    ldrb    w6, [x3], #1
    cmp     w5, w6
    bne     h2_preface_invalid
    subs    x4, x4, #1
    bne     preface_cmp_loop
    
    /* Preface matched! Send our SETTINGS */
    mov     x19, x0
    bl      h2_conn_send_settings
    cmp     x0, #0
    blt     h2_preface_fail
    
    /* Mark preface received */
    mov     x0, x19
    ldr     w1, [x0, #4]            /* h2c_flags */
    orr     w1, w1, #2              /* Set preface_received bit */
    str     w1, [x0, #4]
    
    /* Change state to OPEN */
    mov     w1, #H2_CONN_OPEN
    str     w1, [x0]                /* h2c_state */
    
    mov     x0, #24                 /* Return bytes consumed */
    b       h2_preface_done

h2_preface_need_more:
    mov     x0, #0                  /* Need more data */
    b       h2_preface_done

h2_preface_invalid:
    mov     x0, #H2_ERROR_PROTOCOL_ERROR
    b       h2_preface_done

h2_preface_fail:
    /* x0 already contains error */

h2_preface_done:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Send SETTINGS Frame
 * ======================================================================== */

/*
 * h2_conn_send_settings(conn) - Send server SETTINGS frame
 * x0 = connection pointer
 * Returns: x0 = 0 on success
 */
h2_conn_send_settings:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    mov     x19, x0
    
    /* Get socket fd */
    ldr     w0, [x19, #152]         /* h2c_fd */
    
    /* Send pre-built SETTINGS frame */
    ldr     x1, =h2_server_settings
    mov     x2, h2_server_settings_len
    mov     x8, #SYS_WRITE
    svc     #0
    
    cmp     x0, #0
    blt     h2_send_settings_fail
    
    mov     x0, #0                  /* Success */
    b       h2_send_settings_done

h2_send_settings_fail:
    mov     x0, #ERR_IO

h2_send_settings_done:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Send SETTINGS ACK
 * ======================================================================== */

/*
 * h2_conn_send_settings_ack(conn) - Send SETTINGS ACK
 * x0 = connection pointer
 */
h2_conn_send_settings_ack:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    mov     x19, x0
    
    ldr     w0, [x19, #152]         /* h2c_fd */
    ldr     x1, =h2_settings_ack
    mov     x2, h2_settings_ack_len
    mov     x8, #SYS_WRITE
    svc     #0
    
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Handle Received Frame
 * ======================================================================== */

/*
 * h2_conn_handle_frame(conn, frame, payload) - Process received frame
 * x0 = connection pointer
 * x1 = frame header pointer
 * x2 = payload pointer
 * Returns: x0 = 0 on success, error code on failure
 */
h2_conn_handle_frame:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* Connection */
    mov     x20, x1                 /* Frame header */
    
    /* Get frame type */
    ldrb    w3, [x20, #3]           /* frame.type */
    
    /* Dispatch by type */
    cmp     w3, #H2_FRAME_SETTINGS
    beq     h2_handle_settings
    cmp     w3, #H2_FRAME_HEADERS
    beq     h2_handle_headers
    cmp     w3, #H2_FRAME_DATA
    beq     h2_handle_data
    cmp     w3, #H2_FRAME_WINDOW_UPDATE
    beq     h2_handle_window_update
    cmp     w3, #H2_FRAME_PING
    beq     h2_handle_ping
    cmp     w3, #H2_FRAME_GOAWAY
    beq     h2_handle_goaway
    cmp     w3, #H2_FRAME_RST_STREAM
    beq     h2_handle_rst_stream
    cmp     w3, #H2_FRAME_PRIORITY
    beq     h2_handle_priority
    
    /* Unknown frame type - ignore per RFC */
    mov     x0, #0
    b       h2_handle_done

h2_handle_settings:
    mov     x0, x19
    mov     x1, x20
    mov     x2, x20                 /* payload starts after header */
    add     x2, x2, #9
    bl      h2_handle_settings_frame
    b       h2_handle_done

h2_handle_headers:
    mov     x0, x19
    mov     x1, x20
    bl      h2_handle_headers_frame
    b       h2_handle_done

h2_handle_data:
    mov     x0, x19
    mov     x1, x20
    bl      h2_handle_data_frame
    b       h2_handle_done

h2_handle_window_update:
    mov     x0, x19
    mov     x1, x20
    bl      h2_handle_window_update_frame
    b       h2_handle_done

h2_handle_ping:
    mov     x0, x19
    mov     x1, x20
    bl      h2_handle_ping_frame
    b       h2_handle_done

h2_handle_goaway:
    mov     x0, x19
    mov     x1, x20
    bl      h2_handle_goaway_frame
    b       h2_handle_done

h2_handle_rst_stream:
    mov     x0, x19
    mov     x1, x20
    bl      h2_handle_rst_stream_frame
    b       h2_handle_done

h2_handle_priority:
    /* PRIORITY - ignore for now */
    mov     x0, #0
    b       h2_handle_done

h2_handle_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* Stub handlers - will be implemented */
h2_handle_settings_frame:
    ret

h2_handle_headers_frame:
    mov     x0, #0
    ret

h2_handle_data_frame:
    mov     x0, #0
    ret

h2_handle_window_update_frame:
    mov     x0, #0
    ret

h2_handle_ping_frame:
    mov     x0, #0
    ret

h2_handle_goaway_frame:
    mov     x0, #0
    ret

h2_handle_rst_stream_frame:
    mov     x0, #0
    ret

/* ========================================================================
 * Connection Close
 * ======================================================================== */

/*
 * h2_conn_close(conn, error_code, msg) - Close connection with GOAWAY
 * x0 = connection pointer
 * x1 = error code
 * x2 = message pointer (optional, can be 0)
 */
h2_conn_close:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    mov     x19, x0
    
    /* Change state to CLOSING */
    mov     w3, #H2_CONN_CLOSING
    str     w3, [x19]               /* h2c_state */
    
    /* Send GOAWAY frame */
    /* TODO: Build and send GOAWAY */
    
    /* Change state to CLOSED */
    mov     w3, #H2_CONN_CLOSED
    str     w3, [x19]
    
    /* Free resources */
    ldr     x0, [x19, #120]         /* h2c_streams */
    cmp     x0, #0
    beq     h2_close_no_streams
    mov     x1, #4096
    bl      mem_pool_free

h2_close_no_streams:
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

