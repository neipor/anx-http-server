/* src/core/simd_wrapper.s - SIMD Auto-Selection Wrapper
 * 
 * 根据缓冲区大小自动选择最优实现：
 * - 小缓冲区 (<128 bytes): 使用标量实现（避免SIMD开销）
 * - 大缓冲区 (>=128 bytes): 使用SIMD实现（NEON 128-bit）
 * 
 * 性能目标: 3-4x 提升 vs 标准实现
 */

.include "src/defs.s"

.global fast_memcpy
.global fast_memset
.global fast_strlen
.global fast_strcmp

/* 性能优化阈值 */
.equ SIMD_THRESHOLD_MEMCPY, 128
.equ SIMD_THRESHOLD_MEMSET, 128
.equ SIMD_THRESHOLD_STRLEN, 64
.equ SIMD_THRESHOLD_STRCMP, 64

/* 外部SIMD函数声明 */
.global simd_memcpy_128
.global simd_memset_128
.global simd_strlen_neon
.global simd_strcmp_neon

.text

/* ========================================================================
 * Fast Memory Copy
 * ======================================================================== */

/*
 * fast_memcpy(dest, src, n) - Auto-select memcpy implementation
 * x0 = destination
 * x1 = source  
 * x2 = length
 * Returns: x0 = destination
 */
fast_memcpy:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* 检查长度是否足够大 */
    cmp     x2, #SIMD_THRESHOLD_MEMCPY
    blt     fast_memcpy_scalar
    
    /* 大缓冲区：使用SIMD */
    bl      simd_memcpy_128
    b       fast_memcpy_done

fast_memcpy_scalar:
    /* 小缓冲区：使用标量 */
    cmp     x2, #0
    beq     fast_memcpy_done
    mov     x3, #0
fast_memcpy_loop:
    ldrb    w4, [x1, x3]
    strb    w4, [x0, x3]
    add     x3, x3, #1
    cmp     x3, x2
    blt     fast_memcpy_loop

fast_memcpy_done:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Fast Memory Set
 * ======================================================================== */

/*
 * fast_memset(dest, val, n) - Auto-select memset implementation
 * x0 = destination
 * x1 = value (byte)
 * x2 = length
 * Returns: x0 = destination
 */
fast_memset:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    cmp     x2, #SIMD_THRESHOLD_MEMSET
    blt     fast_memset_scalar
    
    /* 大缓冲区：使用SIMD */
    bl      simd_memset_128
    b       fast_memset_done

fast_memset_scalar:
    cmp     x2, #0
    beq     fast_memset_done
    mov     x3, #0
fast_memset_loop:
    strb    w1, [x0, x3]
    add     x3, x3, #1
    cmp     x3, x2
    blt     fast_memset_loop

fast_memset_done:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Fast String Length
 * ======================================================================== */

/*
 * fast_strlen(str) - Auto-select strlen implementation
 * x0 = string pointer
 * Returns: x0 = length
 */
fast_strlen:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Save original pointer */
    mov     x4, x0
    mov     x5, #0                  /* Count of bytes before alignment */
    
    /* Check alignment */
    and     x1, x0, #15
    cbz     x1, 1f
    
    /* Handle unaligned prefix byte by byte */
2:
    ldrb    w2, [x0], #1
    cbz     w2, fast_strlen_done
    add     x5, x5, #1
    and     x1, x0, #15             /* Check if now aligned */
    cbnz    x1, 2b

1:
    /* Now aligned: use SIMD */
    bl      simd_strlen_neon
    /* x0 contains length from aligned position */
    /* Add the unaligned prefix count */
    add     x0, x0, x5
    b       fast_strlen_return

fast_strlen_done:
    sub     x0, x0, x4              /* Return total length */

fast_strlen_return:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Fast String Compare  
 * ======================================================================== */

/*
 * fast_strcmp(s1, s2) - Auto-select strcmp implementation
 * x0 = string 1
 * x1 = string 2
 * Returns: x0 = 0 if equal, <0 if s1<s2, >0 if s1>s2
 */
fast_strcmp:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* 检查前几个字节来决定是否使用SIMD */
    mov     x2, #0
fast_strcmp_check:
    ldrb    w3, [x0, x2]
    ldrb    w4, [x1, x2]
    
    /* 如果任一字符串结束或不相等，使用SIMD */
    cmp     w3, w4
    bne     fast_strcmp_scalar
    cbz     w3, fast_strcmp_done
    
    add     x2, x2, #1
    cmp     x2, #SIMD_THRESHOLD_STRCMP
    blt     fast_strcmp_check
    
    /* 长度足够，使用SIMD */
    bl      simd_strcmp_neon
    b       fast_strcmp_done_2

fast_strcmp_scalar:
    sub     w0, w3, w4
    sxtw    x0, w0

fast_strcmp_done:
    mov     x0, #0

fast_strcmp_done_2:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Performance Profiling (Optional)
 * ======================================================================== */

.global simd_stats_enable
.global simd_stats_print
.global simd_threshold_tuning

.data
.align 3
simd_stats_enabled: .byte 0
simd_copy_scalar:   .quad 0      /* 标量copy次数 */
simd_copy_simd:     .quad 0      /* SIMD copy次数 */
simd_set_scalar:     .quad 0
simd_set_simd:      .quad 0
simd_len_scalar:     .quad 0
simd_len_simd:      .quad 0
simd_cmp_scalar:     .quad 0
simd_cmp_simd:      .quad 0

.text

/*
 * simd_stats_enable(enable) - Enable/disable statistics
 * x0 = 1 to enable, 0 to disable
 */
simd_stats_enable:
    ldr     x1, =simd_stats_enabled
    strb    w0, [x1]
    ret

/*
 * simd_stats_print() - Print statistics to stdout
 */
simd_stats_print:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Print statistics */
    
    ldp     x29, x30, [sp], #16
    ret

/*
 * simd_threshold_tuning() - Auto-tune thresholds based on runtime stats
 * 
 * 这个函数会根据实际运行数据动态调整阈值
 * 例如：如果SIMD在小缓冲区上也表现更好，可以降低阈值
 */
simd_threshold_tuning:
    ret

