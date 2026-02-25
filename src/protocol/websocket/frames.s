/* src/protocol/websocket/frames.s - WebSocket Frame Handling (RFC 6455) */

.include "src/defs.s"
.include "src/core/types.s"

.global ws_frame_parse
.global ws_frame_build
.global ws_mask_payload
.global ws_unmask_payload

/* WebSocket Frame Structure (max 14 bytes header) */
.struct 0
wsf_fin:        .byte 0         /* 1 bit: final fragment */
wsf_rsv:        .byte 0         /* 3 bits: reserved */
wsf_opcode:     .byte 0         /* 4 bits: opcode */
wsf_masked:     .byte 0         /* 1 bit: mask flag */
wsf_payload_len: .quad 0        /* 7/7+16/7+64 bits: payload length */
wsf_mask_key:   .word 0         /* 4 bytes: masking key (if masked) */
wsf_header_len: .byte 0         /* Total header length */
.struct 24

/* Opcodes */
.equ WS_OP_CONTINUATION,    0x0
.equ WS_OP_TEXT,            0x1
.equ WS_OP_BINARY,          0x2
.equ WS_OP_CLOSE,           0x8
.equ WS_OP_PING,            0x9
.equ WS_OP_PONG,            0xA

/* Close Status Codes */
.equ WS_CLOSE_NORMAL,       1000
.equ WS_CLOSE_GOING_AWAY,   1001
.equ WS_CLOSE_PROTOCOL,     1002
.equ WS_CLOSE_UNSUPPORTED,  1003
.equ WS_CLOSE_NO_STATUS,    1005
.equ WS_CLOSE_ABNORMAL,     1006
.equ WS_CLOSE_INVALID_DATA, 1007
.equ WS_CLOSE_POLICY,       1008
.equ WS_CLOSE_TOO_BIG,      1009
.equ WS_CLOSE_MANDATORY_EXT, 1010
.equ WS_CLOSE_SERVER_ERROR, 1011
.equ WS_CLOSE_TLS_HANDSHAKE, 1015

.text

/*
 * ws_frame_parse(buffer, len, frame) - Parse WebSocket frame
 * x0 = input buffer
 * x1 = buffer length
 * x2 = frame structure pointer
 * Returns: x0 = header length on success, error code on failure
 */
ws_frame_parse:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* buffer */
    mov     x20, x1                 /* len */
    
    /* Check minimum length (2 bytes) */
    cmp     x20, #2
    blt     ws_parse_fail_short
    
    /* Parse first byte: FIN + RSV + OPCODE */
    ldrb    w3, [x19]
    
    /* FIN bit */
    tst     w3, #0x80
    cset    w4, ne
    strb    w4, [x2]                /* wsf_fin */
    
    /* RSV bits */
    ubfx    w4, w3, #4, #3
    strb    w4, [x2, #1]            /* wsf_rsv */
    
    /* Opcode */
    and     w4, w3, #0x0F
    strb    w4, [x2, #2]            /* wsf_opcode */
    
    /* Parse second byte: MASK + Payload length */
    ldrb    w3, [x19, #1]
    
    /* MASK bit */
    tst     w3, #0x80
    cset    w4, ne
    strb    w4, [x2, #3]            /* wsf_masked */
    
    /* Payload length (7 bits initially) */
    and     w4, w3, #0x7F
    mov     x5, #2                  /* header_len = 2 */
    
    cmp     w4, #126
    beq     ws_parse_len_16
    cmp     w4, #127
    beq     ws_parse_len_64
    
    /* Length < 126, fits in 7 bits */
    str     w4, [x2, #4]            /* wsf_payload_len (low 32 bits) */
    b       ws_parse_mask_key

ws_parse_len_16:
    /* 16-bit extended length */
    cmp     x20, #4
    blt     ws_parse_fail_short
    
    ldrb    w3, [x19, #2]
    ldrb    w4, [x19, #3]
    lsl     w3, w3, #8
    orr     w4, w4, w3
    str     w4, [x2, #4]
    mov     x5, #4                  /* header_len = 4 */
    b       ws_parse_mask_key

ws_parse_len_64:
    /* 64-bit extended length */
    cmp     x20, #10
    blt     ws_parse_fail_short
    
    /* Read 8 bytes (big-endian) */
    ldr     x3, [x19, #2]
    ldr     x4, [x19, #10]
    rev     x3, x3                  /* Swap endianness */
    rev     x4, x4
    /* Combine: high 32 bits from x3, low 32 from x4 (simplified) */
    str     x4, [x2, #4]            /* Store low 64 bits */
    mov     x5, #10                 /* header_len = 10 */

ws_parse_mask_key:
    /* Check if masked */
    ldrb    w3, [x2, #3]            /* wsf_masked */
    cbz     w3, ws_parse_done
    
    /* Read mask key (4 bytes) */
    add     x6, x5, #4              /* header_len += 4 */
    cmp     x20, x6
    blt     ws_parse_fail_short
    
    ldr     w3, [x19, x5]           /* Read mask key at offset */
    str     w3, [x2, #12]           /* wsf_mask_key */
    mov     x5, x6                  /* Update header_len */

ws_parse_done:
    strb    w5, [x2, #16]           /* wsf_header_len */
    mov     x0, x5                  /* Return header length */
    b       ws_parse_ret

ws_parse_fail_short:
    mov     x0, #ERR_INVALID

ws_parse_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/*
 * ws_frame_build(frame, payload, buffer) - Build WebSocket frame
 * x0 = frame structure pointer
 * x1 = payload buffer
 * x2 = output buffer
 * Returns: x0 = total frame length
 */
ws_frame_build:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    
    mov     x19, x0                 /* frame */
    mov     x20, x1                 /* payload */
    mov     x21, x2                 /* output buffer */
    
    /* Build first byte: FIN + RSV + OPCODE */
    mov     w3, #0
    
    ldrb    w4, [x19]               /* FIN */
    cbz     w4, 1f
    orr     w3, w3, #0x80
1:
    ldrb    w4, [x19, #1]           /* RSV */
    lsl     w4, w4, #4
    orr     w3, w3, w4
    
    ldrb    w4, [x19, #2]           /* OPCODE */
    and     w4, w4, #0x0F
    orr     w3, w3, w4
    
    strb    w3, [x21]
    
    /* Build second byte: MASK + Payload length */
    ldr     x4, [x19, #4]           /* payload_len */
    mov     w3, #0
    
    ldrb    w5, [x19, #3]           /* MASKED */
    cbz     w5, 2f
    orr     w3, w3, #0x80
2:
    
    mov     x5, #2                  /* header offset */
    
    cmp     x4, #126
    blt     ws_build_len_7
    mov     x6, #65535
    cmp     x4, x6
    ble     ws_build_len_16
    
    /* 64-bit length */
    orr     w3, w3, #127
    strb    w3, [x21, #1]
    
    /* Write 8 bytes (big-endian) */
    mov     x3, x4
    rev     x3, x3
    str     x3, [x21, #10]          /* High 64 bits (simplified) */
    mov     x5, #10
    b       ws_build_mask

ws_build_len_16:
    /* 16-bit length */
    orr     w3, w3, #126
    strb    w3, [x21, #1]
    
    /* Write 2 bytes (big-endian) */
    lsr     w3, w4, #8
    strb    w3, [x21, #2]
    strb    w4, [x21, #3]
    mov     x5, #4
    b       ws_build_mask

ws_build_len_7:
    /* 7-bit length */
    and     w4, w4, #0x7F
    orr     w3, w3, w4
    strb    w3, [x21, #1]

ws_build_mask:
    /* Add mask key if needed */
    ldrb    w3, [x19, #3]
    cbz     w3, ws_build_payload
    
    ldr     w3, [x19, #12]          /* mask_key */
    str     w3, [x21, x5]
    add     x5, x5, #4

ws_build_payload:
    /* Copy payload */
    ldr     x6, [x19, #4]           /* payload_len */
    cmp     x6, #0
    beq     ws_build_done
    
    add     x0, x21, x5             /* dest */
    mov     x1, x20                 /* src */
    mov     x2, x6                  /* len */
    bl      memcpy

ws_build_done:
    /* Return total length */
    ldr     x6, [x19, #4]
    add     x0, x5, x6
    
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

/*
 * ws_mask_payload(payload, len, mask_key) - XOR payload with mask
 * x0 = payload buffer
 * x1 = payload length
 * x2 = mask key (4 bytes)
 * Returns: x0 = 0
 */
ws_mask_payload:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* payload */
    mov     x20, x1                 /* length */
    mov     w3, w2                  /* mask key */
    
    /* Broadcast mask to all bytes */
    mov     w4, w3
    lsl     w4, w4, #8
    orr     w3, w3, w4
    lsl     w4, w3, #16
    orr     w3, w3, w4
    mov     x2, x3                  /* x2 = 0xKKKKKKKK (broadcast) */
    
    mov     x3, #0                  /* offset */

mask_loop:
    cmp     x3, x20
    bge     mask_done
    
    /* XOR 4 bytes at a time when possible */
    sub     x4, x20, x3
    cmp     x4, #4
    blt     mask_byte
    
    /* XOR 4 bytes */
    ldr     w4, [x19, x3]
    eor     w4, w4, w2
    str     w4, [x19, x3]
    add     x3, x3, #4
    b       mask_loop

mask_byte:
    /* XOR single byte */
    and     x5, x3, #3              /* offset % 4 */
    lsl     x6, x5, #3              /* shift amount = offset * 8 */
    lsr     w4, w2, w6              /* Shift mask to correct byte */
    and     w4, w4, #0xFF
    
    ldrb    w5, [x19, x3]
    eor     w5, w5, w4
    strb    w5, [x19, x3]
    
    add     x3, x3, #1
    b       mask_loop

mask_done:
    mov     x0, #0
    
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/*
 * ws_unmask_payload(payload, len, mask_key) - Unmask is same as mask
 */
ws_unmask_payload:
    b       ws_mask_payload         /* XOR is symmetric */

