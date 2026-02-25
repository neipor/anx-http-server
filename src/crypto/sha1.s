/* src/crypto/sha1.s - SHA-1 Hash Algorithm (RFC 3174) */

.include "src/defs.s"

.global sha1_init
.global sha1_update
.global sha1_final
.global sha1_transform

/* ========================================================================
 * SHA-1 Context Structure (96 bytes)
 * ======================================================================== */
.struct 0
sha1_state:     .skip 20          /* 5 state words (H0-H4) */
sha1_count:     .quad 0           /* 64-bit bit count */
sha1_buffer:    .skip 64          /* 64-byte buffer */
sha1_buf_used:  .word 0           /* Bytes used in buffer */
.struct 96

/* ========================================================================
 * SHA-1 Constants (K values)
 * ======================================================================== */
.data
.align 2
sha1_K:
    .word   0x5A827999       /* Rounds 0-19 */
    .word   0x6ED9EBA1       /* Rounds 20-39 */
    .word   0x8F1BBCDC       /* Rounds 40-59 */
    .word   0xCA62C1D6       /* Rounds 60-79 */

/* Initial hash values */
sha1_initial:
    .word   0x67452301       /* H0 */
    .word   0xEFCDAB89       /* H1 */
    .word   0x98BADCFE       /* H2 */
    .word   0x10325476       /* H3 */
    .word   0xC3D2E1F0       /* H4 */

.text

/* ========================================================================
 * SHA-1 Initialize
 * ======================================================================== */

/*
 * sha1_init(ctx) - Initialize SHA-1 context
 * x0 = context pointer
 */
sha1_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    mov     x19, x0
    
    /* Copy initial state */
    ldr     x1, =sha1_initial
    ldp     w2, w3, [x1]
    stp     w2, w3, [x19]
    ldp     w2, w3, [x1, #8]
    stp     w2, w3, [x19, #8]
    ldr     w2, [x1, #16]
    str     w2, [x19, #16]
    
    /* Clear count */
    str     xzr, [x19, #20]
    
    /* Clear buffer */
    mov     x0, x19
    add     x0, x0, #28         /* sha1_buffer */
    mov     x1, #0
    mov     x2, #68             /* buffer + buf_used */
    bl      sha1_memset
    
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * SHA-1 Update
 * ======================================================================== */

/*
 * sha1_update(ctx, data, len) - Update SHA-1 with new data
 * x0 = context pointer
 * x1 = data pointer
 * x2 = length in bytes
 */
sha1_update:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0             /* ctx */
    mov     x20, x1             /* data */
    mov     x21, x2             /* len */
    
    /* Update bit count: count += len * 8 */
    ldr     x3, [x19, #20]      /* current count */
    mov     x4, x21
    lsl     x4, x4, #3          /* len * 8 */
    add     x3, x3, x4
    str     x3, [x19, #20]
    
    ldr     w22, [x19, #24]     /* sha1_buf_used */
    
    /* Check if we have buffered data */
    cbz     w22, sha1_update_direct
    
    /* Fill buffer first */
    mov     w3, #64
    sub     w3, w3, w22         /* Space left in buffer */
    
    cmp     x21, x3
    csel    x4, x21, x3, lt     /* Copy min(len, space_left) */
    
    /* Copy to buffer */
    add     x0, x19, #28        /* ctx->buffer + buf_used */
    add     x0, x0, x22
    mov     x1, x20
    mov     x2, x4
    bl      sha1_memcpy
    
    add     w22, w22, w4
    str     w22, [x19, #24]
    add     x20, x20, x4
    sub     x21, x21, x4
    
    /* If buffer is full, transform it */
    cmp     w22, #64
    blt     sha1_update_check_remainder
    
    add     x0, x19, #28
    bl      sha1_transform
    str     wzr, [x19, #24]     /* buf_used = 0 */

sha1_update_check_remainder:
    cbz     x21, sha1_update_done

sha1_update_direct:
    /* Process full 64-byte blocks directly */
    cmp     x21, #64
    blt     sha1_update_buffer_remainder
    
    mov     x0, x20
    bl      sha1_transform
    
    add     x20, x20, #64
    sub     x21, x21, #64
    b       sha1_update_direct

sha1_update_buffer_remainder:
    /* Copy remaining bytes to buffer */
    cbz     x21, sha1_update_done
    
    add     x0, x19, #28        /* ctx->buffer */
    mov     x1, x20
    mov     x2, x21
    bl      sha1_memcpy
    
    str     w21, [x19, #24]     /* buf_used = len */

sha1_update_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * SHA-1 Final
 * ======================================================================== */

/*
 * sha1_final(ctx, digest) - Finalize SHA-1 and output digest
 * x0 = context pointer
 * x1 = output digest (20 bytes)
 */
sha1_final:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0             /* ctx */
    mov     x20, x1             /* digest */
    
    ldr     w21, [x19, #24]     /* buf_used */
    
    /* Add padding: 0x80 followed by zeros */
    add     x0, x19, #28
    add     x0, x0, x21
    mov     w1, #0x80
    strb    w1, [x0]
    add     w21, w21, #1
    
    /* If we have >= 56 bytes used, need two blocks */
    cmp     w21, #56
    ble     sha1_final_pad_zeros
    
    /* Fill rest of this block with zeros */
    add     x0, x19, #28
    add     x0, x0, x21
    mov     w1, #0
    mov     w2, #64
    sub     w2, w2, w21
    bl      sha1_memset
    
    /* Transform this block */
    add     x0, x19, #28
    bl      sha1_transform
    
    mov     w21, #0

sha1_final_pad_zeros:
    /* Fill with zeros up to position 56 */
    add     x0, x19, #28
    add     x0, x0, x21
    mov     w1, #0
    mov     w2, #56
    sub     w2, w2, w21
    bl      sha1_memset
    
    /* Append bit count (64 bits, big-endian) */
    ldr     x2, [x19, #20]      /* 64-bit count */
    rev     x2, x2              /* Convert to big-endian */
    str     x2, [x19, #84]      /* Store at position 56 */
    
    /* Final transform */
    add     x0, x19, #28
    bl      sha1_transform
    
    /* Copy state to digest (big-endian) */
    ldr     w0, [x19]           /* H0 */
    rev     w0, w0
    str     w0, [x20]
    
    ldr     w0, [x19, #4]       /* H1 */
    rev     w0, w0
    str     w0, [x20, #4]
    
    ldr     w0, [x19, #8]       /* H2 */
    rev     w0, w0
    str     w0, [x20, #8]
    
    ldr     w0, [x19, #12]      /* H3 */
    rev     w0, w0
    str     w0, [x20, #12]
    
    ldr     w0, [x19, #16]      /* H4 */
    rev     w0, w0
    str     w0, [x20, #16]
    
    /* Clear context for security */
    mov     x0, x19
    mov     x1, #0
    mov     x2, #96
    bl      sha1_memset
    
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * SHA-1 Transform (Single 64-byte Block)
 * ======================================================================== */

/*
 * sha1_transform(data) - Process one 64-byte block
 * x0 = 64-byte data block pointer
 * Uses global ctx in x19
 */
sha1_transform:
    stp     x29, x30, [sp, #-128]!
    mov     x29, sp
    
    /* Save registers */
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    
    mov     x20, x0             /* Data block */
    
    /* Load state into working variables */
    ldr     w21, [x19]          /* a = H0 */
    ldr     w22, [x19, #4]      /* b = H1 */
    ldr     w23, [x19, #8]      /* c = H2 */
    ldr     w24, [x19, #12]     /* d = H3 */
    ldr     w25, [x19, #16]     /* e = H4 */
    
    /* Allocate W[80] on stack */
    sub     sp, sp, #320        /* 80 * 4 bytes */
    mov     x26, sp             /* W array */
    
    /* Copy M[0..15] to W[0..15] (big-endian to host) */
    mov     x0, x26
    mov     x1, x20
    mov     x2, #16
sha1_copy_W:
    ldr     w3, [x1], #4
    rev     w3, w3              /* Convert from big-endian */
    str     w3, [x0], #4
    subs    x2, x2, #1
    bne     sha1_copy_W
    
    /* Extend to W[16..79] */
    mov     x0, x26
    add     x0, x0, #64         /* W[16] */
    mov     x2, #64             /* 64 words to compute */
sha1_extend:
    sub     x3, x0, #12         /* W[t-3] */
    sub     x4, x0, #32         /* W[t-8] */
    sub     x5, x0, #56         /* W[t-14] */
    sub     x6, x0, #64         /* W[t-16] */
    
    ldr     w3, [x3]
    ldr     w4, [x4]
    ldr     w5, [x5]
    ldr     w6, [x6]
    
    eor     w3, w3, w4
    eor     w3, w3, w5
    eor     w3, w3, w6
    ror     w3, w3, #31         /* Rotate left by 1 */
    
    str     w3, [x0], #4
    subs    x2, x2, #1
    bne     sha1_extend
    
    /* Main loop: 80 rounds */
    mov     x27, #80
    mov     x28, x26            /* W pointer */

sha1_round_loop:
    /* Determine K and f based on round */
    cmp     x27, #60
    bgt     sha1_round_60_79
    cmp     x27, #40
    bgt     sha1_round_40_59
    cmp     x27, #20
    bgt     sha1_round_20_39
    
    /* Rounds 0-19: f = (b & c) | ((~b) & d), K = 0x5A827999 */
    and     w0, w22, w23        /* b & c */
    bic     w1, w24, w22        /* (~b) & d */
    orr     w0, w0, w1          /* f */
    ldr     w1, =0x5A827999
    b       sha1_compute_temp

sha1_round_20_39:
    /* Rounds 20-39: f = b ^ c ^ d, K = 0x6ED9EBA1 */
    eor     w0, w22, w23
    eor     w0, w0, w24
    ldr     w1, =0x6ED9EBA1
    b       sha1_compute_temp

sha1_round_40_59:
    /* Rounds 40-59: f = (b & c) | (b & d) | (c & d), K = 0x8F1BBCDC */
    and     w0, w22, w23        /* b & c */
    and     w2, w22, w24        /* b & d */
    orr     w0, w0, w2
    and     w2, w23, w24        /* c & d */
    orr     w0, w0, w2
    ldr     w1, =0x8F1BBCDC
    b       sha1_compute_temp

sha1_round_60_79:
    /* Rounds 60-79: f = b ^ c ^ d, K = 0xCA62C1D6 */
    eor     w0, w22, w23
    eor     w0, w0, w24
    ldr     w1, =0xCA62C1D6

sha1_compute_temp:
    /* temp = ROTL(a, 5) + f + e + K + W[t] */
    ror     w2, w21, #27        /* ROTL(a, 5) = ROR(a, 27) */
    add     w2, w2, w0          /* + f */
    add     w2, w2, w25         /* + e */
    add     w2, w2, w1          /* + K */
    ldr     w0, [x28], #4       /* W[t] */
    add     w2, w2, w0          /* + W[t] */
    
    /* Update variables */
    mov     w25, w24            /* e = d */
    mov     w24, w23            /* d = c */
    ror     w23, w22, #2        /* c = ROTL(b, 30) = ROR(b, 2) */
    mov     w22, w21            /* b = a */
    mov     w21, w2             /* a = temp */
    
    subs    x27, x27, #1
    bne     sha1_round_loop
    
    /* Add to previous state */
    ldr     w0, [x19]
    add     w21, w21, w0
    str     w21, [x19]
    
    ldr     w0, [x19, #4]
    add     w22, w22, w0
    str     w22, [x19, #4]
    
    ldr     w0, [x19, #8]
    add     w23, w23, w0
    str     w23, [x19, #8]
    
    ldr     w0, [x19, #12]
    add     w24, w24, w0
    str     w24, [x19, #12]
    
    ldr     w0, [x19, #16]
    add     w25, w25, w0
    str     w25, [x19, #16]
    
    /* Restore stack */
    add     sp, sp, #320
    
    /* Restore registers */
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x25, x26, [sp, #64]
    ldp     x27, x28, [sp, #80]
    ldp     x29, x30, [sp], #128
    ret

/* ========================================================================
 * Helper Functions
 * ======================================================================== */

sha1_memcpy:
    cmp     x2, #0
    beq     sha1_memcpy_done
    mov     x3, #0
sha1_memcpy_loop:
    ldrb    w4, [x1, x3]
    strb    w4, [x0, x3]
    add     x3, x3, #1
    cmp     x3, x2
    blt     sha1_memcpy_loop
sha1_memcpy_done:
    ret

sha1_memset:
    cmp     x2, #0
    beq     sha1_memset_done
    mov     x3, #0
sha1_memset_loop:
    strb    w1, [x0, x3]
    add     x3, x3, #1
    cmp     x3, x2
    blt     sha1_memset_loop
sha1_memset_done:
    ret

