/* src/protocol/http2/hpack_dynamic.s - HPACK Dynamic Table Management */

.include "src/defs.s"
.include "src/core/types.s"

.global hpack_dynamic_init
.global hpack_dynamic_insert
.global hpack_dynamic_lookup
.global hpack_dynamic_evict
.global hpack_dynamic_resize
.global hpack_dynamic_free

/* ========================================================================
 * Dynamic Table Constants
 * ======================================================================== */

.equ HPACK_DEFAULT_TABLE_SIZE, 4096       /* Default maximum size */
.equ HPACK_MAX_TABLE_SIZE, 16384          /* Maximum allowed size */
.equ HPACK_ENTRY_OVERHEAD, 32             /* Overhead per entry (name_len + value_len + 32) */

/* Dynamic Table Entry */
.struct 0
hde_name:       .quad 0                  /* Pointer to name string */
hde_value:      .quad 0                  /* Pointer to value string */
hde_name_len:   .word 0                  /* Name length */
hde_value_len:  .word 0                  /* Value length */
hde_size:       .word 0                  /* Entry size (name_len + value_len + 32) */
hde_flags:      .word 0                  /* Flags (valid, etc.) */
.struct 32

/* Dynamic Table Context */
.struct 0
hdt_capacity:   .quad 0                  /* Maximum table size */
hdt_size:       .quad 0                  /* Current table size */
hdt_entries:    .quad 0                  /* Pointer to entries array */
hdt_capacity_count: .word 0              /* Max number of entries */
hdt_count:      .word 0                  /* Current number of entries */
hdt_head:       .word 0                  /* Index of newest entry */
hdt_tail:       .word 0                  /* Index of oldest entry */
hdt_ref_count:  .word 0                  /* Reference count for memory management */
.struct 48

.text

/* ========================================================================
 * Dynamic Table Initialization
 * ======================================================================== */

/*
 * hpack_dynamic_init(context, max_size) - Initialize dynamic table
 * x0 = context pointer
 * x1 = maximum table size
 * Returns: x0 = 0 on success, error code on failure
 */
hpack_dynamic_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* context */
    mov     x20, x1                 /* max_size */
    
    /* Validate size */
    cmp     x20, #HPACK_MAX_TABLE_SIZE
    bgt     hpack_init_size_error
    cmp     x20, #0
    blt     hpack_init_size_error
    
    /* Set capacity */
    str     x20, [x19]              /* hdt_capacity */
    str     xzr, [x19, #8]          /* hdt_size = 0 */
    
    /* Calculate max entries (each entry min size ~32 bytes) */
    mov     x0, x20
    mov     x1, #32
    udiv    x0, x0, x1
    add     x0, x0, #1              /* +1 for safety */
    str     w0, [x19, #16]          /* hdt_capacity_count */
    
    /* Allocate entries array */
    mov     x1, #32                 /* sizeof(hpack_dynamic_entry) */
    mul     x0, x0, x1
    bl      mem_pool_alloc
    cmp     x0, #0
    beq     hpack_init_mem_error
    
    str     x0, [x19, #24]          /* hdt_entries */
    
    /* Initialize counters */
    str     wzr, [x19, #20]         /* hdt_count = 0 */
    str     wzr, [x19, #28]         /* hdt_head = 0 */
    str     wzr, [x19, #32]         /* hdt_tail = 0 */
    str     wzr, [x19, #36]         /* hdt_ref_count = 0 */
    
    mov     x0, #0
    b       hpack_init_done

hpack_init_size_error:
    mov     x0, #ERR_INVALID
    b       hpack_init_done

hpack_init_mem_error:
    mov     x0, #ERR_NOMEM

hpack_init_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * Dynamic Table Insertion
 * ======================================================================== */

/*
 * hpack_dynamic_insert(context, name, name_len, value, value_len)
 * x0 = context
 * x1 = name pointer
 * x2 = name length
 * x3 = value pointer
 * x4 = value length
 * Returns: x0 = index (1-based) on success, error code on failure
 */
hpack_dynamic_insert:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    
    mov     x19, x0                 /* context */
    mov     x20, x1                 /* name */
    mov     x21, x2                 /* name_len */
    mov     x22, x3                 /* value */
    mov     x23, x4                 /* value_len */
    
    /* Calculate entry size */
    add     x24, x21, x23           /* name_len + value_len */
    add     x24, x24, #HPACK_ENTRY_OVERHEAD
    
    /* Check if entry is too large for table */
    ldr     x0, [x19]               /* capacity */
    cmp     x24, x0
    bgt     hpack_insert_too_large
    
    /* Evict entries if necessary to make room */
hpack_insert_evict_loop:
    ldr     x0, [x19, #8]           /* current size */
    add     x1, x0, x24             /* size + new_entry_size */
    ldr     x2, [x19]               /* capacity */
    cmp     x1, x2
    ble     hpack_insert_room_ok
    
    /* Need to evict oldest entry */
    mov     x0, x19
    bl      hpack_dynamic_evict_oldest
    cmp     x0, #0
    blt     hpack_insert_evict_error
    b       hpack_insert_evict_loop

hpack_insert_room_ok:
    /* Get head position */
    ldr     w0, [x19, #28]          /* hdt_head */
    ldr     w1, [x19, #16]          /* capacity_count */
    sub     w1, w1, #1
    and     w0, w0, w1              /* head % capacity */
    
    /* Calculate entry address */
    ldr     x2, [x19, #24]          /* entries pointer */
    mov     x3, #32                 /* sizeof(entry) */
    mul     x3, x0, x3
    add     x24, x2, x3             /* entry pointer */
    
    /* Store entry data */
    str     x20, [x24]              /* name */
    str     x22, [x24, #8]          /* value */
    str     w21, [x24, #16]         /* name_len */
    str     w23, [x24, #20]         /* value_len */
    
    ldr     x0, [x19, #8]           /* current size */
    add     x0, x0, x24
    sub     x0, x0, #32             /* subtract pointer size */
    str     w0, [x24, #24]          /* size */
    
    mov     w0, #1
    str     w0, [x24, #28]          /* flags = valid */
    
    /* Update table size */
    ldr     x0, [x19, #8]           /* current size */
    add     x0, x0, x24
    sub     x0, x0, #32
    str     x0, [x19, #8]           /* new size */
    
    /* Update head */
    ldr     w0, [x19, #28]
    add     w0, w0, #1
    str     w0, [x19, #28]
    
    /* Increment count */
    ldr     w0, [x19, #20]
    add     w0, w0, #1
    str     w0, [x19, #20]
    
    /* Return index (head position + 1, since dynamic table is 1-based after static) */
    ldr     w0, [x19, #28]
    sub     w0, w0, #1
    and     w0, w0, w1
    add     w0, w0, #62             /* +61 for static table size + 1 */
    b       hpack_insert_done

hpack_insert_too_large:
    mov     x0, #ERR_TOO_LARGE
    b       hpack_insert_done

hpack_insert_evict_error:
    mov     x0, #ERR_INVALID

hpack_insert_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

/* ========================================================================
 * Dynamic Table Eviction
 * ======================================================================== */

/*
 * hpack_dynamic_evict_oldest(context) - Remove oldest entry
 * x0 = context
 * Returns: x0 = 0 on success, error on failure
 */
hpack_dynamic_evict_oldest:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* context */
    
    /* Check if table is empty */
    ldr     w0, [x19, #20]          /* count */
    cbz     w0, hpack_evict_empty
    
    /* Get tail entry */
    ldr     w0, [x19, #32]          /* tail */
    ldr     w1, [x19, #16]          /* capacity */
    sub     w1, w1, #1
    and     w0, w0, w1
    
    /* Calculate entry address */
    ldr     x2, [x19, #24]          /* entries */
    mov     x3, #32
    mul     x3, x0, x3
    add     x20, x2, x3             /* entry pointer */
    
    /* Get entry size */
    ldr     w3, [x20, #24]          /* size */
    
    /* Free entry strings (if dynamically allocated) */
    /* For now, assume strings are managed externally */
    
    /* Mark entry as invalid */
    str     wzr, [x20, #28]         /* flags = 0 */
    
    /* Update table size */
    ldr     x0, [x19, #8]           /* current size */
    sub     x0, x0, x3
    str     x0, [x19, #8]           /* new size */
    
    /* Update tail */
    ldr     w0, [x19, #32]
    add     w0, w0, #1
    str     w0, [x19, #32]
    
    /* Decrement count */
    ldr     w0, [x19, #20]
    sub     w0, w0, #1
    str     w0, [x19, #20]
    
    mov     x0, #0
    b       hpack_evict_done

hpack_evict_empty:
    mov     x0, #-1

hpack_evict_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * Dynamic Table Lookup
 * ======================================================================== */

/*
 * hpack_dynamic_lookup(context, index, name_out, value_out)
 * x0 = context
 * x1 = index (1-based from start of dynamic table)
 * x2 = name output pointer
 * x3 = value output pointer
 * Returns: x0 = 0 on success, error on failure
 */
hpack_dynamic_lookup:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* context */
    mov     x20, x1                 /* index */
    mov     x21, x2                 /* name_out */
    mov     x22, x3                 /* value_out */
    
    /* Convert to 0-based and adjust for circular buffer */
    ldr     w0, [x19, #28]          /* head */
    sub     w0, w0, w20             /* head - index */
    ldr     w1, [x19, #16]          /* capacity */
    sub     w1, w1, #1
    and     w0, w0, w1              /* (head - index) % capacity */
    
    /* Calculate entry address */
    ldr     x1, [x19, #24]          /* entries */
    mov     x2, #32
    mul     x2, x0, x2
    add     x0, x1, x2
    
    /* Check if entry is valid */
    ldr     w1, [x0, #28]           /* flags */
    cbz     w1, hpack_lookup_invalid
    
    /* Copy pointers to output */
    ldr     x1, [x0]                /* name */
    str     x1, [x21]
    ldr     x1, [x0, #8]            /* value */
    str     x1, [x22]
    
    mov     x0, #0
    b       hpack_lookup_done

hpack_lookup_invalid:
    mov     x0, #ERR_NOT_FOUND

hpack_lookup_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* ========================================================================
 * Dynamic Table Resize
 * ======================================================================== */

/*
 * hpack_dynamic_resize(context, new_capacity)
 * x0 = context
 * x1 = new capacity
 * Returns: x0 = 0 on success
 */
hpack_dynamic_resize:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Validate new capacity */
    cmp     x1, #HPACK_MAX_TABLE_SIZE
    bgt     hpack_resize_error
    
    /* Update capacity */
    str     x1, [x0]                /* hdt_capacity */
    
    /* Evict entries if current size exceeds new capacity */
hpack_resize_evict_loop:
    ldr     x2, [x0, #8]            /* current size */
    cmp     x2, x1
    ble     hpack_resize_done
    
    bl      hpack_dynamic_evict_oldest
    cmp     x0, #0
    blt     hpack_resize_error
    b       hpack_resize_evict_loop

hpack_resize_done:
    mov     x0, #0
    b       hpack_resize_return

hpack_resize_error:
    mov     x0, #ERR_INVALID

hpack_resize_return:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Dynamic Table Free
 * ======================================================================== */

/*
 * hpack_dynamic_free(context)
 * x0 = context
 */
hpack_dynamic_free:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Free entries array */
    ldr     x1, [x0, #24]           /* entries */
    cbz     x1, hpack_free_done
    
    ldr     x2, [x0, #16]           /* capacity_count */
    mov     x3, #32
    mul     x2, x2, x3
    
    mov     x0, x1
    mov     x1, x2
    bl      mem_pool_free

hpack_free_done:
    ldp     x29, x30, [sp], #16
    ret

/* External functions */
.global mem_pool_alloc
.global mem_pool_free

