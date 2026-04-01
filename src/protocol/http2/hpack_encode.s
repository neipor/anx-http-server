/* src/protocol/http2/hpack_encode.s - HPACK Header Field Encoding */

.include "src/defs.s"
.include "src/core/types.s"

.global hpack_encode_header
.global hpack_encode_indexed
.global hpack_encode_literal_indexed
.global hpack_encode_literal_not_indexed
.global hpack_encode_literal_never_indexed

/* Encoding Types (RFC 7541 Section 6) */
.equ HPACK_TYPE_INDEXED, 0x80                 /* 1xxxxxxx - Indexed Header Field */
.equ HPACK_TYPE_LITERAL_INDEXED, 0x40         /* 01xxxxxx - Literal with Incremental Indexing */
.equ HPACK_TYPE_LITERAL_NOT_INDEXED, 0x00     /* 0000xxxx - Literal without Indexing */
.equ HPACK_TYPE_LITERAL_NEVER_INDEXED, 0x10   /* 0001xxxx - Literal Never Indexed */
.equ HPACK_TYPE_DYNAMIC_SIZE_UPDATE, 0x20     /* 001xxxxx - Dynamic Table Size Update */

/* Static Table Size */
.equ HPACK_STATIC_TABLE_SIZE, 61

.text

/* ========================================================================
 * Header Encoding - Main Entry Point
 * ======================================================================== */

/*
 * hpack_encode_header(context, name, name_len, value, value_len, 
 *                     index_type, output, output_len)
 * x0 = HPACK context (includes dynamic table)
 * x1 = name pointer
 * x2 = name length
 * x3 = value pointer
 * x4 = value length
 * x5 = index type (0=indexed, 1=with indexing, 2=without, 3=never)
 * x6 = output buffer
 * x7 = output buffer length (pointer, updated)
 * Returns: x0 = bytes written, or error
 */
hpack_encode_header:
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
    mov     x24, x5                 /* index_type */
    
    /* First, try to find an existing match */
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    bl      hpack_find_match
    
    cmp     x0, #0
    blt     hpack_enc_no_match      /* No match found */
    
    /* Match found at index x0 */
    cmp     x24, #0
    beq     hpack_enc_use_indexed
    
    /* For literal encoding with existing name match */
    mov     x1, x0                  /* index */
    mov     x2, x22                 /* value */
    mov     x3, x23                 /* value_len */
    mov     x4, x24                 /* index_type */
    mov     x5, x6                  /* output */
    mov     x6, x7                  /* output_len */
    bl      hpack_encode_literal_with_name_index
    b       hpack_enc_done

hpack_enc_use_indexed:
    /* Use indexed header field representation */
    mov     x1, x0                  /* index */
    mov     x2, x6                  /* output */
    mov     x3, x7                  /* output_len */
    bl      hpack_encode_indexed
    b       hpack_enc_done

hpack_enc_no_match:
    /* No match - encode with literal name */
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    mov     x3, x22
    mov     x4, x23
    mov     x5, x24
    mov     x6, x6                  /* output */
    mov     x7, x7                  /* output_len */
    bl      hpack_encode_literal_with_name_literal

hpack_enc_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

/* ========================================================================
 * Indexed Header Field Encoding (Section 6.1)
 * ======================================================================== */

/*
 * hpack_encode_indexed(index, output, output_len)
 * x0 = index (1-based, 1-61 = static, 62+ = dynamic)
 * x1 = output buffer
 * x2 = output buffer length pointer
 * Returns: x0 = bytes written
 */
hpack_encode_indexed:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Indexed header field: 1xxxxxxx followed by index */
    /* First byte has prefix 0b1111111 (7 bits) */
    mov     x3, x1                  /* save output pointer */
    
    mov     x1, #HPACK_TYPE_INDEXED /* 0x80 */
    mov     x2, #7                  /* 7 prefix bits */
    bl      hpack_encode_integer
    
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Literal Header Field with Incremental Indexing (Section 6.2.1)
 * ======================================================================== */

/*
 * hpack_encode_literal_with_name_index(context, name_index, value, value_len,
 *                                       output, output_len)
 * x0 = context
 * x1 = name index (from static or dynamic table)
 * x2 = value pointer
 * x3 = value length
 * x4 = output buffer
 * x5 = output buffer length pointer
 * Returns: x0 = bytes written
 */
hpack_encode_literal_with_name_index:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x4                 /* output */
    mov     x20, x5                 /* output_len */
    mov     x21, x2                 /* value */
    mov     x22, x3                 /* value_len */
    
    /* Encode name index with type prefix */
    /* Type: 01xxxxxx (6-bit prefix for index) */
    sub     x0, x1, #1              /* index - 1 (0-based for encoding) */
    mov     x1, #HPACK_TYPE_LITERAL_INDEXED  /* 0x40 */
    mov     x2, #6                  /* 6 prefix bits */
    mov     x3, x19                 /* output */
    bl      hpack_encode_integer
    
    add     x19, x19, x0            /* advance output */
    
    /* Encode value as string literal */
    mov     x0, x21                 /* value */
    mov     x1, x22                 /* value_len */
    mov     x2, x19                 /* output */
    mov     x3, #0                  /* no huffman */
    bl      hpack_encode_string
    
    add     x0, x19, x0             /* total bytes */
    sub     x0, x0, x19
    add     x0, x0, x19
    sub     x0, x0, x4              /* bytes written from original output */
    
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/*
 * hpack_encode_literal_with_name_literal(context, name, name_len, value, value_len,
 *                                         index_type, output, output_len)
 * x0 = context
 * x1 = name pointer
 * x2 = name length  
 * x3 = value pointer
 * x4 = value length
 * x5 = index type
 * x6 = output buffer
 * x7 = output buffer length pointer
 * Returns: x0 = bytes written
 */
hpack_encode_literal_with_name_literal:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    
    mov     x19, x0                 /* context */
    mov     x20, x6                 /* output */
    mov     x21, x7                 /* output_len */
    
    /* Determine type prefix */
    cmp     x5, #1
    beq     hpack_enc_lit_name_idx
    cmp     x5, #2
    beq     hpack_enc_lit_name_no_idx
    cmp     x5, #3
    beq     hpack_enc_lit_name_never
    
hpack_enc_lit_name_idx:
    mov     x24, #HPACK_TYPE_LITERAL_INDEXED      /* 0x40, 6-bit prefix */
    mov     x23, #6
    b       hpack_enc_lit_name_start
    
hpack_enc_lit_name_no_idx:
    mov     x24, #HPACK_TYPE_LITERAL_NOT_INDEXED  /* 0x00, 4-bit prefix */
    mov     x23, #4
    b       hpack_enc_lit_name_start
    
hpack_enc_lit_name_never:
    mov     x24, #HPACK_TYPE_LITERAL_NEVER_INDEXED /* 0x10, 4-bit prefix */
    mov     x23, #4

hpack_enc_lit_name_start:
    /* Encode name index = 0 (literal name) with type prefix */
    mov     x0, #0                  /* index = 0 */
    mov     x1, x24                 /* type prefix */
    mov     x2, x23                 /* prefix bits */
    mov     x3, x20                 /* output */
    bl      hpack_encode_integer
    
    add     x20, x20, x0            /* advance output */
    
    /* Encode name as string literal */
    mov     x0, x1                  /* name */
    mov     x1, x2                  /* name_len */
    mov     x2, x20                 /* output */
    mov     x3, #0                  /* no huffman */
    bl      hpack_encode_string
    
    add     x20, x20, x0            /* advance output */
    
    /* Encode value as string literal */
    mov     x0, x3                  /* value */
    mov     x1, x4                  /* value_len */
    mov     x2, x20                 /* output */
    mov     x3, #0                  /* no huffman */
    bl      hpack_encode_string
    
    add     x20, x20, x0
    
    /* Insert into dynamic table if indexed type */
    cmp     x5, #1
    bne     hpack_enc_lit_name_no_insert
    
    mov     x0, x19
    add     x0, x0, #128            /* dynamic table offset (assumed) */
    mov     x1, x1                  /* name */
    mov     x2, x2                  /* name_len */
    mov     x3, x3                  /* value */
    mov     x4, x4                  /* value_len */
    bl      hpack_dynamic_insert

hpack_enc_lit_name_no_insert:
    /* Calculate total bytes written */
    sub     x0, x20, x6
    
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

/* ========================================================================
 * Header Lookup Functions
 * ======================================================================== */

/*
 * hpack_find_match(context, name, name_len, value, value_len)
 * x0 = context
 * x1 = name
 * x2 = name_len
 * x3 = value
 * x4 = value_len
 * Returns: x0 = index (1-based) if full match, index+ for name-only,
 *          or -1 if no match
 */
hpack_find_match:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Search static table first, then dynamic table */
    /* For now, return no match */
    mov     x0, #-1
    
    ldp     x29, x30, [sp], #16
    ret

/* External functions */
.global hpack_encode_integer
.global hpack_encode_string
.global hpack_dynamic_insert

