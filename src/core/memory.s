/* src/core/memory.s - Memory Pool Management */

.include "src/defs.s"
.include "src/core/types.s"

.global mem_pool_init
.global mem_pool_alloc
.global mem_pool_free
.global mem_pool_destroy
.global mem_buffer_create
.global mem_buffer_destroy
.global mem_buffer_resize

/* ========================================================================
 * Memory Pool Management
 * ======================================================================== */

/* Memory Pool Configuration */
.equ MEM_POOL_INITIAL_BLOCKS, 16
.equ MEM_POOL_MAX_BLOCKS, 256

.text

/*
 * mem_pool_init() - Initialize memory pool
 * Returns: x0 = 0 on success, error code on failure
 */
mem_pool_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Initialize memory pool structure */
    /* For now, just return success */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/*
 * mem_pool_alloc(size) - Allocate memory from pool
 * x0 = size in bytes
 * Returns: x0 = pointer to allocated memory, or NULL on failure
 */
mem_pool_alloc:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x0, [sp, #16]           /* Save requested size */
    
    /* Round up size to next power of 2 or block boundary */
    /* For now, use mmap directly for large allocations */
    cmp     x0, #16384
    bgt     use_mmap
    
use_mmap:
    /* Use mmap for allocation */
    mov     x1, x0                  /* length = size */
    mov     x0, #0                  /* addr = NULL (kernel chooses) */
    mov     x2, #3                  /* prot = PROT_READ | PROT_WRITE */
    mov     x3, #0x22               /* flags = MAP_PRIVATE | MAP_ANONYMOUS */
    mov     x4, #-1                 /* fd = -1 */
    mov     x5, #0                  /* offset = 0 */
    mov     x8, #222                /* SYS_MMAP2 */
    svc     #0
    
    /* Check for error (returns -errno on failure) */
    cmp     x0, #0
    blt     alloc_fail
    
    ldp     x29, x30, [sp], #32
    ret

alloc_fail:
    mov     x0, #0                  /* Return NULL */
    ldp     x29, x30, [sp], #32
    ret

/*
 * mem_pool_free(ptr, size) - Free memory back to pool
 * x0 = pointer to memory
 * x1 = size in bytes
 */
mem_pool_free:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Use munmap to free */
    mov     x2, x1                  /* length */
    mov     x1, x0                  /* addr */
    mov     x0, x1
    mov     x1, x2
    mov     x8, #215                /* SYS_MUNMAP */
    svc     #0
    
    ldp     x29, x30, [sp], #16
    ret

/*
 * mem_pool_destroy() - Destroy memory pool and free all blocks
 */
mem_pool_destroy:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Free all pool blocks */
    
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Dynamic Buffer Management
 * ======================================================================== */

/*
 * mem_buffer_create(initial_size) - Create a dynamic buffer
 * x0 = initial size
 * Returns: x0 = pointer to buffer structure
 */
mem_buffer_create:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x0, [sp, #16]           /* Save initial size */
    
    /* Allocate buffer structure (24 bytes) */
    mov     x0, #24
    bl      mem_pool_alloc
    cmp     x0, #0
    beq     buf_create_fail
    
    mov     x19, x0                 /* Save buffer struct pointer */
    
    /* Allocate data buffer */
    ldr     x0, [sp, #16]           /* Get initial size */
    cmp     x0, #1024
    bge     buf_size_ok
    mov     x0, #1024               /* Minimum 1KB */
buf_size_ok:
    bl      mem_pool_alloc
    cmp     x0, #0
    beq     buf_create_fail_struct
    
    /* Initialize buffer structure */
    str     x0, [x19]               /* buf_data */
    ldr     x1, [sp, #16]
    cmp     x1, #1024
    bge     buf_store_size
    mov     x1, #1024
buf_store_size:
    str     x1, [x19, #8]           /* buf_size */
    str     xzr, [x19, #16]         /* buf_len = 0 */
    
    mov     x0, x19                 /* Return buffer struct */
    ldp     x29, x30, [sp], #32
    ret

buf_create_fail_struct:
    mov     x0, x19
    mov     x1, #24
    bl      mem_pool_free
buf_create_fail:
    mov     x0, #0
    ldp     x29, x30, [sp], #32
    ret

/*
 * mem_buffer_destroy(buf) - Destroy a dynamic buffer
 * x0 = buffer structure pointer
 */
mem_buffer_destroy:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    cmp     x0, #0
    beq     buf_destroy_done
    
    mov     x19, x0
    
    /* Free data buffer */
    ldr     x0, [x19]               /* buf_data */
    ldr     x1, [x19, #8]           /* buf_size */
    bl      mem_pool_free
    
    /* Free structure */
    mov     x0, x19
    mov     x1, #24
    bl      mem_pool_free

buf_destroy_done:
    ldp     x29, x30, [sp], #16
    ret

/*
 * mem_buffer_resize(buf, new_size) - Resize buffer
 * x0 = buffer structure pointer
 * x1 = new size
 * Returns: x0 = 0 on success, error code on failure
 */
mem_buffer_resize:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* Buffer pointer */
    mov     x20, x1                 /* New size */
    
    /* Check if resize is needed */
    ldr     x2, [x19, #8]           /* Current size */
    cmp     x20, x2
    ble     resize_ok               /* New size <= current size */
    
    /* Allocate new buffer */
    mov     x0, x20
    bl      mem_pool_alloc
    cmp     x0, #0
    beq     resize_fail
    
    mov     x21, x0                 /* New buffer */
    
    /* Copy old data */
    ldr     x1, [x19]               /* Old data pointer */
    ldr     x2, [x19, #16]          /* Current length */
    cmp     x2, x20
    csel    x2, x2, x20, le         /* Copy min(len, new_size) */
    
    /* memcpy(new_buf, old_buf, copy_len) */
    mov     x22, x0                 /* Save new buffer */
    mov     x0, x21
    bl      memcpy
    
    /* Free old buffer */
    ldr     x0, [x19]               /* Old data */
    ldr     x1, [x19, #8]           /* Old size */
    bl      mem_pool_free
    
    /* Update structure */
    str     x21, [x19]              /* New data pointer */
    str     x20, [x19, #8]          /* New size */

resize_ok:
    mov     x0, #0
    b       resize_done

resize_fail:
    mov     x0, #ERR_NOMEM

resize_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * Helper: memcpy (local version)
 * ======================================================================== */
memcpy_local:
    cmp     x2, #0
    beq     memcpy_done
    mov     x3, #0
memcpy_loop:
    ldrb    w4, [x1, x3]
    strb    w4, [x0, x3]
    add     x3, x3, #1
    cmp     x3, x2
    blt     memcpy_loop
memcpy_done:
    ret

