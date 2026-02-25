/* src/crypto/base64.s - Base64 Encoding/Decoding (RFC 4648) */

.include "src/defs.s"

.global base64_encode
.global base64_decode
.global base64_encode_neon
.global base64_decode_neon

/* ========================================================================
 * Base64 Encoding Tables
 * ======================================================================== */

.data
.align 4

/* Standard Base64 alphabet */
base64_encode_table:
    .ascii "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

/* URL-safe Base64 alphabet (for JWT, etc) */
base64url_encode_table:
    .ascii "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

/* Decode table: value for each ASCII char, 0xFF = invalid */
base64_decode_table:
    .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF  /* 0x00-0x07 */
    .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF  /* 0x08-0x0F */
    .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF  /* 0x10-0x17 */
    .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF  /* 0x18-0x1F */
    .byte 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF  /* 0x20-0x27 */
    .byte 0xFF, 0xFF, 0xFF, 0x3E, 0xFF, 0xFF, 0xFF, 0x3F  /* 0x28-0x2F: (+, /) */
    .byte 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B  /* 0x30-0x37: 0-7 */
    .byte 0x3C, 0x3D, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF  /* 0x38-0x3F: 8-9 */
    .byte 0xFF, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06  /* 0x40-0x47: A-G */
    .byte 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E  /* 0x48-0x4F: H-O */
    .byte 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16  /* 0x50-0x57: P-W */
    .byte 0x17, 0x18, 0x19, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF  /* 0x58-0x5F: X-Z */
    .byte 0xFF, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20  /* 0x60-0x67: a-g */
    .byte 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28  /* 0x68-0x6F: h-o */
    .byte 0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30  /* 0x70-0x77: p-w */
    .byte 0x31, 0x32, 0x33, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF  /* 0x78-0x7F: x-z */
    /* Remainder filled with 0xFF */
    .rept 128
    .byte 0xFF
    .endr

.text

/* ========================================================================
 * Base64 Encode (Scalar)
 * ======================================================================== */

/*
 * base64_encode(src, srclen, dst, dstlen) - Encode data to Base64
 * x0 = source pointer
 * x1 = source length
 * x2 = destination pointer
 * x3 = destination buffer length (output: actual length written)
 * Returns: x0 = 0 on success, -1 on buffer too small
 */
base64_encode:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0             /* src */
    mov     x20, x1             /* srclen */
    mov     x21, x2             /* dst */
    mov     x22, x3             /* dstlen ptr */
    
    /* Calculate required output length: 4 * ceil(srclen / 3) */
    add     x4, x20, #2
    mov     x5, #3
    udiv    x4, x4, x5
    mov     x5, #4
    mul     x4, x4, x5          /* Required length */
    
    /* Check if buffer is large enough */
    ldr     x5, [x22]           /* Current dstlen */
    cmp     x5, x4
    blt     base64_encode_fail
    
    /* Store actual output length */
    str     x4, [x22]
    
    ldr     x22, =base64_encode_table
    
    /* Process 3 bytes at a time */
    mov     x5, x20
    udiv    x6, x5, x3          /* Number of complete triplets */
    msub    x7, x6, x3, x5      /* Remainder */

base64_encode_loop:
    cbz     x6, base64_encode_tail
    
    /* Load 3 bytes */
    ldrb    w8, [x19], #1       /* Byte 0 */
    ldrb    w9, [x19], #1       /* Byte 1 */
    ldrb    w10, [x19], #1      /* Byte 2 */
    
    /* Encode to 4 Base64 chars */
    /* c0 = (byte0 >> 2) & 0x3F */
    lsr     w11, w8, #2
    ldrb    w11, [x22, x11]
    strb    w11, [x21], #1
    
    /* c1 = ((byte0 & 0x03) << 4) | ((byte1 >> 4) & 0x0F) */
    and     w11, w8, #0x03
    lsl     w11, w11, #4
    lsr     w12, w9, #4
    orr     w11, w11, w12
    ldrb    w11, [x22, x11]
    strb    w11, [x21], #1
    
    /* c2 = ((byte1 & 0x0F) << 2) | ((byte2 >> 6) & 0x03) */
    and     w11, w9, #0x0F
    lsl     w11, w11, #2
    lsr     w12, w10, #6
    orr     w11, w11, w12
    ldrb    w11, [x22, x11]
    strb    w11, [x21], #1
    
    /* c3 = byte2 & 0x3F */
    and     w11, w10, #0x3F
    ldrb    w11, [x22, x11]
    strb    w11, [x21], #1
    
    sub     x6, x6, #1
    b       base64_encode_loop

base64_encode_tail:
    /* Handle remaining 1 or 2 bytes */
    cmp     x7, #0
    beq     base64_encode_done
    
    cmp     x7, #1
    beq     base64_encode_one
    
    /* Two bytes remaining */
    ldrb    w8, [x19], #1
    ldrb    w9, [x19]
    
    lsr     w11, w8, #2
    ldrb    w11, [x22, x11]
    strb    w11, [x21], #1
    
    and     w11, w8, #0x03
    lsl     w11, w11, #4
    lsr     w12, w9, #4
    orr     w11, w11, w12
    ldrb    w11, [x22, x11]
    strb    w11, [x21], #1
    
    and     w11, w9, #0x0F
    lsl     w11, w11, #2
    ldrb    w11, [x22, x11]
    strb    w11, [x21], #1
    
    mov     w11, #'='
    strb    w11, [x21]
    
    b       base64_encode_done

base64_encode_one:
    /* One byte remaining */
    ldrb    w8, [x19]
    
    lsr     w11, w8, #2
    ldrb    w11, [x22, x11]
    strb    w11, [x21], #1
    
    and     w11, w8, #0x03
    lsl     w11, w11, #4
    ldrb    w11, [x22, x11]
    strb    w11, [x21], #1
    
    mov     w11, #'='
    strb    w11, [x21], #1
    strb    w11, [x21]

base64_encode_done:
    mov     x0, #0
    b       base64_encode_return

base64_encode_fail:
    mov     x0, #-1

base64_encode_return:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* ========================================================================
 * Base64 Decode (Scalar)
 * ======================================================================== */

/*
 * base64_decode(src, srclen, dst, dstlen) - Decode Base64 data
 * x0 = source pointer
 * x1 = source length (must be multiple of 4)
 * x2 = destination pointer
 * x3 = destination buffer length (output: actual length written)
 * Returns: x0 = 0 on success, -1 on error
 */
base64_decode:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0             /* src */
    mov     x20, x1             /* srclen */
    mov     x21, x2             /* dst */
    mov     x22, x3             /* dstlen ptr */
    
    /* Validate input length (must be multiple of 4) */
    and     x4, x20, #3
    cbnz    x4, base64_decode_fail
    
    /* Calculate output length */
    mov     x4, x20
    mov     x5, #4
    udiv    x4, x4, x5
    mov     x5, #3
    mul     x4, x4, x5          /* Max output: 3 * (srclen / 4) */
    
    /* Check for padding */
    sub     x5, x20, #1
    ldrb    w6, [x19, x5]
    cmp     w6, #'='
    bne     1f
    sub     x4, x4, #1
    sub     x5, x5, #1
    ldrb    w6, [x19, x5]
    cmp     w6, #'='
    bne     1f
    sub     x4, x4, #1

1:
    /* Check buffer size */
    ldr     x5, [x22]
    cmp     x5, x4
    blt     base64_decode_fail
    
    str     x4, [x22]           /* Store actual output length */
    
    ldr     x22, =base64_decode_table
    
    /* Process 4 chars at a time */
    mov     x5, x20
    lsr     x5, x5, #2          /* Number of quads */

base64_decode_loop:
    cbz     x5, base64_decode_done
    
    /* Load 4 chars */
    ldrb    w8, [x19], #1
    ldrb    w9, [x19], #1
    ldrb    w10, [x19], #1
    ldrb    w11, [x19], #1
    
    /* Check for padding */
    cmp     w11, #'='
    beq     base64_decode_pad2
    cmp     w10, #'='
    beq     base64_decode_pad1
    
    /* Decode 4 chars to 3 bytes */
    ldrb    w8, [x22, x8]
    ldrb    w9, [x22, x9]
    ldrb    w10, [x22, x10]
    ldrb    w11, [x22, x11]
    
    /* Check for invalid chars */
    cmp     w8, #0xFF
    beq     base64_decode_fail
    cmp     w9, #0xFF
    beq     base64_decode_fail
    cmp     w10, #0xFF
    beq     base64_decode_fail
    cmp     w11, #0xFF
    beq     base64_decode_fail
    
    /* byte0 = (c0 << 2) | (c1 >> 4) */
    lsl     w12, w8, #2
    lsr     w13, w9, #4
    orr     w12, w12, w13
    strb    w12, [x21], #1
    
    /* byte1 = (c1 << 4) | (c2 >> 2) */
    lsl     w12, w9, #4
    lsr     w13, w10, #2
    orr     w12, w12, w13
    strb    w12, [x21], #1
    
    /* byte2 = (c2 << 6) | c3 */
    lsl     w12, w10, #6
    orr     w12, w12, w11
    strb    w12, [x21], #1
    
    sub     x5, x5, #1
    b       base64_decode_loop

base64_decode_pad2:
    /* Two padding chars: output 1 byte */
    ldrb    w8, [x22, x8]
    ldrb    w9, [x22, x9]
    
    cmp     w8, #0xFF
    beq     base64_decode_fail
    cmp     w9, #0xFF
    beq     base64_decode_fail
    
    lsl     w12, w8, #2
    lsr     w13, w9, #4
    orr     w12, w12, w13
    strb    w12, [x21]
    b       base64_decode_done

base64_decode_pad1:
    /* One padding char: output 2 bytes */
    uxtb    x8, w8
    uxtb    x9, w9
    uxtb    x10, w10
    ldrb    w8, [x22, x8]
    ldrb    w9, [x22, x9]
    ldrb    w10, [x22, x10]
    
    cmp     w8, #0xFF
    beq     base64_decode_fail
    cmp     w9, #0xFF
    beq     base64_decode_fail
    cmp     w10, #0xFF
    beq     base64_decode_fail
    
    lsl     w12, w8, #2
    lsr     w13, w9, #4
    orr     w12, w12, w13
    strb    w12, [x21], #1
    
    lsl     w12, w9, #4
    lsr     w13, w10, #2
    orr     w12, w12, w13
    strb    w12, [x21]

base64_decode_done:
    mov     x0, #0
    b       base64_decode_return

base64_decode_fail:
    mov     x0, #-1

base64_decode_return:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* ========================================================================
 * NEON-optimized Base64 (Stubs for future implementation)
 * ======================================================================== */

base64_encode_neon:
    /* TODO: Implement NEON-optimized version */
    /* Process 48 bytes (16 output chunks) at a time using TBL */
    b       base64_encode

base64_decode_neon:
    /* TODO: Implement NEON-optimized version */
    b       base64_decode

