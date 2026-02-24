/* src/protocol/http2/hpack.s - HPACK Header Compression (RFC 7541) */

.include "src/defs.s"
.include "src/core/types.s"

.global hpack_init
.global hpack_decode
.global hpack_encode

/* ========================================================================
 * HPACK Static Table (61 entries)
 * ======================================================================== */

.data
.align 3

/* Static table entries - pairs of (name, value) pointers */
hpack_static_table:
    /* Index 1: :authority */
    .quad hpack_name_1, hpack_value_empty
    /* Index 2: :method GET */
    .quad hpack_name_2, hpack_value_2
    /* Index 3: :method POST */
    .quad hpack_name_2, hpack_value_3
    /* Index 4: :path / */
    .quad hpack_name_3, hpack_value_4
    /* Index 5: :path /index.html */
    .quad hpack_name_3, hpack_value_5
    /* Index 6: :scheme http */
    .quad hpack_name_4, hpack_value_6
    /* Index 7: :scheme https */
    .quad hpack_name_4, hpack_value_7
    /* Index 8: :status 200 */
    .quad hpack_name_5, hpack_value_8
    /* ... more entries (61 total) ... */
    .skip 53 * 16                     /* Placeholder for remaining entries */

hpack_name_1:   .asciz ":authority"
hpack_name_2:   .asciz ":method"
hpack_name_3:   .asciz ":path"
hpack_name_4:   .asciz ":scheme"
hpack_name_5:   .asciz ":status"
hpack_value_empty:  .asciz ""
hpack_value_2:  .asciz "GET"
hpack_value_3:  .asciz "POST"
hpack_value_4:  .asciz "/"
hpack_value_5:  .asciz "/index.html"
hpack_value_6:  .asciz "http"
hpack_value_7:  .asciz "https"
hpack_value_8:  .asciz "200"

/* Dynamic table structure */
.struct 0
hdt_capacity:   .quad 0         /* Maximum table size */
hdt_size:       .quad 0         /* Current table size */
hdt_entries:    .quad 0         /* Pointer to entries array */
hdt_count:      .word 0         /* Number of entries */
hdt_insert_idx: .word 0         /* Next insertion index */
.struct 32

/* Entry structure */
.struct 0
hde_name_len:   .word 0
hde_value_len:  .word 0
hde_name:       .quad 0
hde_value:      .quad 0
.struct 24

.text

/*
 * hpack_init(context, capacity) - Initialize HPACK context
 * x0 = context pointer
 * x1 = dynamic table capacity
 */
hpack_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Initialize dynamic table */
    str     x1, [x0]                /* capacity */
    str     xzr, [x0, #8]           /* size = 0 */
    str     xzr, [x0, #16]          /* entries = NULL (alloc on first use) */
    str     wzr, [x0, #24]          /* count = 0 */
    str     wzr, [x0, #28]          /* insert_idx = 0 */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/*
 * hpack_decode(context, input, input_len, output) - Decode HPACK headers
 * x0 = context pointer
 * x1 = input buffer
 * x2 = input length
 * x3 = output buffer (header list)
 * Returns: x0 = number of bytes consumed, or error code
 */
hpack_decode:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* context */
    mov     x20, x1                 /* input */
    mov     x21, x2                 /* input_len */
    mov     x22, x3                 /* output */
    
    mov     x0, #ERR_UNSUPPORTED    /* Not fully implemented yet */
    
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/*
 * hpack_encode(context, headers, header_count, output) - Encode headers
 * x0 = context pointer
 * x1 = headers array
 * x2 = header count
 * x3 = output buffer
 * Returns: x0 = output length, or error code
 */
hpack_encode:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    mov     x0, #ERR_UNSUPPORTED    /* Not fully implemented yet */
    
    ldp     x29, x30, [sp], #16
    ret

