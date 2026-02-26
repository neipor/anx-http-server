/* src/protocol/http2/hpack_impl.s - HPACK Implementation (RFC 7541) */

.include "src/defs.s"
.include "src/core/types.s"

.global hpack_encode_integer
.global hpack_decode_integer
.global hpack_encode_string
.global hpack_decode_string
.global hpack_find_static
.global hpack_find_dynamic

/* ========================================================================
 * HPACK Integer Encoding/Decoding (RFC 7541 Section 5.1)
 * ======================================================================== */

/*
 * hpack_encode_integer(value, prefix, prefix_bits, output) - Encode integer
 * x0 = value to encode
 * x1 = prefix (initial byte with prefix bits set)
 * x2 = number of prefix bits (N, 1-8)
 * x3 = output buffer
 * Returns: x0 = number of bytes written
 * 
 * Encoding:
 * If value < 2^N - 1: encode in N bits
 * Else: encode (2^N - 1) in N bits, then value - (2^N - 1) in 7-bit chunks
 */
hpack_encode_integer:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x3                 /* output pointer */
    
    /* Calculate 2^N - 1 (maximum value for prefix) */
    mov     x4, #1
    lsl     x4, x4, x2              /* 2^N */
    sub     x4, x4, #1              /* 2^N - 1 */
    
    /* Check if value fits in prefix */
    cmp     x0, x4
    blt     hpack_int_fits_prefix
    
    /* Value doesn't fit: encode max in prefix */
    orr     x1, x1, x4              /* Set all prefix bits */
    strb    w1, [x19], #1
    
    /* Encode remaining value - (2^N - 1) in 7-bit chunks */
    sub     x0, x0, x4              /* remaining = value - (2^N - 1) */
    
hpack_int_multibyte:
    cmp     x0, #128
    blt     hpack_int_last_byte
    
    /* More bytes to come: set MSB */
    mov     x5, x0
    and     x5, x5, #0x7F           /* 7 bits */
    orr     x5, x5, #0x80           /* Set continuation bit */
    strb    w5, [x19], #1
    
    lsr     x0, x0, #7              /* value >>= 7 */
    b       hpack_int_multibyte

hpack_int_last_byte:
    /* Last byte: no continuation bit */
    strb    w0, [x19], #1
    b       hpack_int_done

hpack_int_fits_prefix:
    /* Value fits: encode directly */
    orr     x1, x1, x0
    strb    w1, [x19], #1

hpack_int_done:
    /* Calculate bytes written */
    sub     x0, x19, x3
    
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/*
 * hpack_decode_integer(input, prefix_bits, output_value) - Decode integer
 * x0 = input buffer pointer (updated to point after integer)
 * x1 = number of prefix bits (N)
 * x2 = output value pointer
 * Returns: x0 = 0 on success
 */
hpack_decode_integer:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* input pointer (we'll update this) */
    
    /* Calculate max prefix value: 2^N - 1 */
    mov     x3, #1
    lsl     x3, x3, x1              /* 2^N */
    sub     x3, x3, #1              /* 2^N - 1 */
    
    /* Read first byte */
    ldrb    w4, [x19], #1
    and     x5, x4, x3              /* value = first_byte & (2^N - 1) */
    
    /* Check if more bytes follow */
    cmp     x5, x3
    blt     hpack_dec_int_done
    
    /* Multibyte: decode 7-bit chunks */
    mov     x6, x3                  /* M = 2^N - 1 */
    
hpack_dec_int_multibyte:
    ldrb    w4, [x19], #1
    and     x7, x4, #0x7F           /* 7 bits */
    
    /* value += 7-bit * M (but careful of overflow) */
    mul     x7, x7, x6
    add     x5, x5, x7
    
    /* Check continuation bit */
    tst     x4, #0x80
    bne     hpack_dec_int_multibyte
    
    /* If continuation bit was set, M = M * 128 for next iteration */
    mov     x8, #128
    mul     x6, x6, x8

hpack_dec_int_done:
    /* Store result */
    str     x5, [x2]
    
    /* Update input pointer */
    str     x19, [x0]
    
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * HPACK String Literal Encoding/Decoding (RFC 7541 Section 5.2)
 * ======================================================================== */

/*
 * hpack_encode_string(src, len, output, huffman) - Encode string literal
 * x0 = source string
 * x1 = length
 * x2 = output buffer
 * x3 = 1 to use Huffman encoding, 0 for literal
 * Returns: x0 = number of bytes written
 */
hpack_encode_string:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* src */
    mov     x20, x1                 /* len */
    mov     x21, x2                 /* output */
    mov     x22, x3                 /* huffman flag */
    
    cmp     x22, #0
    bne     hpack_enc_str_huffman
    
    /* Literal encoding (no Huffman) */
    /* Encode length with 7-bit prefix (H bit = 0) */
    mov     x0, x20                 /* value = len */
    mov     x1, #0                  /* prefix = 0 (H=0) */
    mov     x2, #7                  /* 7 prefix bits */
    mov     x3, x21                 /* output */
    bl      hpack_encode_integer
    
    add     x21, x21, x0            /* advance output */
    
    /* Copy string data */
    mov     x0, x21
    mov     x1, x19
    mov     x2, x20
    bl      memcpy
    add     x21, x21, x20
    
    b       hpack_enc_str_done

hpack_enc_str_huffman:
    /* TODO: Huffman encoding */
    mov     x0, #ERR_UNSUPPORTED
    b       hpack_enc_str_return

hpack_enc_str_done:
    sub     x0, x21, x2             /* bytes written */

hpack_enc_str_return:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/*
 * hpack_decode_string(input, output, output_len) - Decode string literal
 * x0 = input buffer pointer (updated)
 * x1 = output buffer
 * x2 = output buffer length (max)
 * Returns: x0 = decoded string length, or error code
 */
hpack_decode_string:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* input pointer addr */
    mov     x20, x1                 /* output buffer */
    mov     x21, x2                 /* output max len */
    
    /* Read first byte */
    ldr     x22, [x19]              /* input pointer */
    ldrb    w4, [x22]
    
    /* Check H bit (bit 7) */
    tst     x4, #0x80
    bne     hpack_dec_str_huffman
    
    /* Literal string: decode length with 7-bit prefix */
    add     x0, sp, #40             /* temp for decoded length */
    mov     x1, #7                  /* 7 prefix bits */
    bl      hpack_decode_integer
    
    ldr     x4, [sp, #40]           /* decoded length */
    
    /* Check if output buffer is large enough */
    cmp     x4, x21
    bgt     hpack_dec_str_overflow
    
    /* Copy string data */
    ldr     x0, [x19]               /* current input pointer */
    mov     x1, x20                 /* output */
    mov     x2, x4                  /* length */
    bl      memcpy
    
    /* Update input pointer */
    ldr     x0, [x19]
    add     x0, x0, x4
    str     x0, [x19]
    
    mov     x0, x4                  /* return decoded length */
    b       hpack_dec_str_return

hpack_dec_str_huffman:
    /* TODO: Huffman decoding */
    mov     x0, #ERR_UNSUPPORTED
    b       hpack_dec_str_return

hpack_dec_str_overflow:
    mov     x0, #ERR_TOO_LARGE

hpack_dec_str_return:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* External functions */
.global memcpy

