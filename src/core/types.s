/* src/core/types.s - Core Type Definitions and Constants */

#ifndef CORE_TYPES_S
#define CORE_TYPES_S

/* ========================================================================
 * Memory Management Types
 * ======================================================================== */

/* Memory Pool Block Size */
.equ MEM_BLOCK_SMALL,   256
.equ MEM_BLOCK_MEDIUM,  1024
.equ MEM_BLOCK_LARGE,   4096
.equ MEM_BLOCK_XLARGE,  16384

/* Memory Pool Structure (32 bytes) */
.struct 0
mp_next:        .quad 0         /* Next block pointer */
mp_size:        .quad 0         /* Block size */
mp_used:        .quad 0         /* Used bytes */
mp_flags:       .word 0         /* Flags: bit0=free, bit1=pinned */
mp_pool_id:     .word 0         /* Pool ID for debugging */
mp_reserved:    .quad 0         /* Reserved for alignment */
.struct 32

/* ========================================================================
 * Buffer Types
 * ======================================================================== */

/* Dynamic Buffer Structure (24 bytes) */
.struct 0
buf_data:       .quad 0         /* Pointer to data */
buf_size:       .quad 0         /* Total size */
buf_len:        .quad 0         /* Current length */
.struct 24

/* ========================================================================
 * Error Types
 * ======================================================================== */

/* Error Codes */
.equ ERR_OK,                0
.equ ERR_NOMEM,            -1
.equ ERR_INVALID,          -2
.equ ERR_NOT_FOUND,        -3
.equ ERR_PERMISSION,       -4
.equ ERR_IO,               -5
.equ ERR_NETWORK,          -6
.equ ERR_PROTOCOL,         -7
.equ ERR_TIMEOUT,          -8
.equ ERR_CLOSED,           -9
.equ ERR_TOO_LARGE,        -10
.equ ERR_UNSUPPORTED,      -11

/* ========================================================================
 * Connection Types
 * ======================================================================== */

/* Connection State */
.equ CONN_STATE_IDLE,       0
.equ CONN_STATE_READING,    1
.equ CONN_STATE_PROCESSING, 2
.equ CONN_STATE_WRITING,    3
.equ CONN_STATE_CLOSING,    4
.equ CONN_STATE_CLOSED,     5

/* Connection Structure (64 bytes) */
.struct 0
conn_fd:        .word 0         /* Socket fd */
conn_state:     .word 0         /* Connection state */
conn_flags:     .word 0         /* Flags */
conn_proto:     .word 0         /* Protocol: 1=HTTP/1, 2=HTTP/2 */
conn_req_buf:   .quad 0         /* Request buffer pointer */
conn_req_len:   .quad 0         /* Request length */
conn_res_buf:   .quad 0         /* Response buffer pointer */
conn_res_len:   .quad 0         /* Response length */
conn_ctx:       .quad 0         /* Protocol-specific context */
conn_next:      .quad 0         /* Next connection in list */
.struct 64

/* ========================================================================
 * Protocol Types
 * ======================================================================== */

/* Protocol Identifiers */
.equ PROTO_HTTP1,           1
.equ PROTO_HTTP2,           2
.equ PROTO_WEBSOCKET,       3

/* HTTP Method Types */
.equ METHOD_GET,            1
.equ METHOD_POST,           2
.equ METHOD_PUT,            3
.equ METHOD_DELETE,         4
.equ METHOD_HEAD,           5
.equ METHOD_OPTIONS,        6
.equ METHOD_PATCH,          7
.equ METHOD_CONNECT,        8
.equ METHOD_TRACE,          9

/* ========================================================================
 * HTTP/2 Types
 * ======================================================================== */

/* HTTP/2 Frame Types */
.equ H2_FRAME_DATA,         0x0
.equ H2_FRAME_HEADERS,      0x1
.equ H2_FRAME_PRIORITY,     0x2
.equ H2_FRAME_RST_STREAM,   0x3
.equ H2_FRAME_SETTINGS,     0x4
.equ H2_FRAME_PUSH_PROMISE, 0x5
.equ H2_FRAME_PING,         0x6
.equ H2_FRAME_GOAWAY,       0x7
.equ H2_FRAME_WINDOW_UPDATE, 0x8
.equ H2_FRAME_CONTINUATION, 0x9

/* HTTP/2 Settings */
.equ H2_SETTINGS_HEADER_TABLE_SIZE,      0x1
.equ H2_SETTINGS_ENABLE_PUSH,            0x2
.equ H2_SETTINGS_MAX_CONCURRENT_STREAMS, 0x3
.equ H2_SETTINGS_INITIAL_WINDOW_SIZE,    0x4
.equ H2_SETTINGS_MAX_FRAME_SIZE,         0x5
.equ H2_SETTINGS_MAX_HEADER_LIST_SIZE,   0x6

/* ========================================================================
 * WebSocket Types
 * ======================================================================== */

/* WebSocket OpCodes */
.equ WS_OP_CONTINUATION,    0x0
.equ WS_OP_TEXT,            0x1
.equ WS_OP_BINARY,          0x2
.equ WS_OP_CLOSE,           0x8
.equ WS_OP_PING,            0x9
.equ WS_OP_PONG,            0xA

#endif /* CORE_TYPES_S */
