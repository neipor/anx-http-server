/* src/protocol/http2/frames.s - HTTP/2 Frame Handling */

.include "src/defs.s"
.include "src/core/types.s"

.global h2_frame_parse
.global h2_frame_build
.global h2_frame_validate

/* HTTP/2 Frame Header (9 bytes) */
.struct 0
h2f_length:     .word 0         /* 3 bytes: payload length */
h2f_type:       .byte 0         /* 1 byte: frame type */
h2f_flags:      .byte 0         /* 1 byte: flags */
h2f_reserved:   .byte 0         /* 1 bit reserved */
h2f_stream_id:  .word 0         /* 31 bits: stream ID */
.struct 9

/* Frame Types */
.equ H2_DATA,           0x0
.equ H2_HEADERS,        0x1
.equ H2_PRIORITY,       0x2
.equ H2_RST_STREAM,     0x3
.equ H2_SETTINGS,       0x4
.equ H2_PUSH_PROMISE,   0x5
.equ H2_PING,           0x6
.equ H2_GOAWAY,         0x7
.equ H2_WINDOW_UPDATE,  0x8
.equ H2_CONTINUATION,   0x9

/* Frame Flags */
.equ H2_FLAG_END_STREAM,    0x01
.equ H2_FLAG_ACK,           0x01
.equ H2_FLAG_END_HEADERS,   0x04
.equ H2_FLAG_PADDED,        0x08
.equ H2_FLAG_PRIORITY,      0x20

/* Error Codes */
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

.text

/*
 * h2_frame_parse(buffer, len, frame) - Parse HTTP/2 frame header
 * x0 = input buffer
 * x1 = buffer length
 * x2 = frame structure pointer
 * Returns: x0 = header length (9) on success, error code on failure
 */
h2_frame_parse:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Check minimum length */
    cmp     x1, #9
    blt     parse_fail_short
    
    /* Parse length (3 bytes, big-endian) */
    ldrb    w3, [x0]
    ldrb    w4, [x0, #1]
    ldrb    w5, [x0, #2]
    ubfx    x3, x3, #0, #8
    lsl     x3, x3, #16
    ubfx    x4, x4, #0, #8
    lsl     x4, x4, #8
    orr     x3, x3, x4
    ubfx    x5, x5, #0, #8
    orr     x3, x3, x5
    
    /* Check maximum payload size (16384 = 2^14) */
    cmp     x3, #16384
    bgt     parse_fail_size
    
    str     w3, [x2]                /* frame.length */
    
    /* Parse type */
    ldrb    w3, [x0, #3]
    strb    w3, [x2, #3]            /* frame.type */
    
    /* Parse flags */
    ldrb    w3, [x0, #4]
    strb    w3, [x2, #4]            /* frame.flags */
    
    /* Parse stream ID (4 bytes, big-endian, top bit reserved) */
    ldr     w3, [x0, #5]
    rev     w3, w3                  /* Convert to host endian */
    and     w3, w3, #0x7FFFFFFF     /* Clear reserved bit */
    str     w3, [x2, #5]            /* frame.stream_id */
    
    mov     x0, #9                  /* Return header length */
    b       parse_done

parse_fail_short:
    mov     x0, #ERR_INVALID
    b       parse_done

parse_fail_size:
    mov     x0, #ERR_TOO_LARGE

parse_done:
    ldp     x29, x30, [sp], #16
    ret

/*
 * h2_frame_build(frame, payload, payload_len, buffer) - Build HTTP/2 frame
 * x0 = frame structure pointer
 * x1 = payload buffer
 * x2 = payload length
 * x3 = output buffer
 * Returns: x0 = total frame length
 */
h2_frame_build:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    
    mov     x19, x3                 /* Save output buffer */
    
    /* Write length (3 bytes, big-endian) */
    mov     x4, x2
    ubfx    x5, x4, #16, #8
    strb    w5, [x19]
    ubfx    x5, x4, #8, #8
    strb    w5, [x19, #1]
    strb    w4, [x19, #2]
    
    /* Write type */
    ldrb    w4, [x0, #3]
    strb    w4, [x19, #3]
    
    /* Write flags */
    ldrb    w4, [x0, #4]
    strb    w4, [x19, #4]
    
    /* Write stream ID */
    ldr     w4, [x0, #5]
    rev     w4, w4
    str     w4, [x19, #5]
    
    /* Copy payload */
    cmp     x2, #0
    beq     build_no_payload
    
    add     x0, x19, #9             /* dest = buffer + 9 */
    mov     x2, x2                  /* len = payload_len */
    bl      memcpy

build_no_payload:
    /* Return total length */
    ldr     w0, [x19]               /* length field */
    and     x0, x0, #0xFFFFFF       /* Mask to 24 bits */
    add     x0, x0, #9              /* + header size */
    
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/*
 * h2_frame_validate(frame) - Validate frame structure
 * x0 = frame structure pointer
 * Returns: x0 = 0 on success, error code on failure
 */
h2_frame_validate:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Get frame type */
    ldrb    w1, [x0, #3]
    
    /* Validate frame type */
    cmp     w1, #0x9
    bgt     validate_fail_type
    
    /* Check length constraints by type */
    ldr     w2, [x0]                /* payload length */
    and     x2, x2, #0xFFFFFF
    
    cmp     w1, #H2_SETTINGS
    beq     validate_settings
    cmp     w1, #H2_WINDOW_UPDATE
    beq     validate_window_update
    cmp     w1, #H2_PING
    beq     validate_ping
    
    /* Default: max 16384 */
    cmp     x2, #16384
    bgt     validate_fail_size
    b       validate_ok

validate_settings:
    /* SETTINGS: must be multiple of 6 */
    mov     x3, #6
    udiv    x4, x2, x3
    msub    x5, x4, x3, x2
    cbnz    x5, validate_fail_size
    b       validate_ok

validate_window_update:
    /* WINDOW_UPDATE: must be 4 bytes */
    cmp     x2, #4
    bne     validate_fail_size
    b       validate_ok

validate_ping:
    /* PING: must be 8 bytes */
    cmp     x2, #8
    bne     validate_fail_size
    b       validate_ok

validate_fail_type:
    mov     x0, #H2_ERROR_PROTOCOL_ERROR
    b       validate_done

validate_fail_size:
    mov     x0, #H2_ERROR_FRAME_SIZE
    b       validate_done

validate_ok:
    mov     x0, #0

validate_done:
    ldp     x29, x30, [sp], #16
    ret

