/* src/protocol/http2/h2_response.s - HTTP/2 Response Implementation */

.include "src/defs.s"
.include "src/core/types.s"

.global h2_build_headers_block_impl
.global h2_encode_status_header
.global h2_encode_content_type
.global h2_encode_content_length
.global h2_complete_file_response

/* ================================================================================================
 * h2_build_headers_block_impl(conn, status, headers, output, output_size)
 * Build complete HPACK-encoded headers block for HTTP/2 response
 * x0 = connection (for HPACK encoder context)
 * x1 = status code
 * x2 = extra headers array (optional)
 * x3 = output buffer
 * x4 = output buffer size
 * Returns: x0 = encoded length, or error
 * ================================================================================================ */
h2_build_headers_block_impl:
    stp     x29, x30, [sp, #-112]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* status code */
    mov     x21, x2                 /* extra headers */
    mov     x22, x3                 /* output buffer */
    mov     x23, x4                 /* output size */
    mov     x24, x3                 /* current output position */
    mov     x25, #0                 /* total encoded length */
    
    /* Encode :status pseudo-header */
    mov     x0, x19                 /* connection */
    mov     x1, x20                 /* status */
    mov     x2, x24                 /* output */
    sub     x3, x23, x25            /* remaining space */
    bl      h2_encode_status_header
    cmp     x0, #0
    blt     h2_build_headers_error
    add     x24, x24, x0
    add     x25, x25, x0
    
    /* Encode content-type if provided in extra headers */
    cmp     x21, #0
    beq     h2_build_skip_content_type
    
    /* Look for content-type in extra headers */
    /* For now, skip - would need header array structure */

h2_build_skip_content_type:
    /* Encode content-length if we know it */
    /* This would come from file stat or body length */
    
    /* Return total encoded length */
    mov     x0, x25
    b       h2_build_headers_done

h2_build_headers_error:
    /* x0 already contains error */

h2_build_headers_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x25, x26, [sp, #64]
    ldp     x27, x28, [sp, #80]
    ldp     x29, x30, [sp], #112
    ret

/* ================================================================================================
 * h2_encode_status_header(conn, status, output, output_size)
 * Encode :status pseudo-header using HPACK
 * Uses indexed encoding for common statuses, literal for others
 * x0 = connection
 * x1 = status code
 * x2 = output buffer
 * x3 = output size
 * Returns: x0 = encoded length, or error
 * ================================================================================================ */
h2_encode_status_header:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* status code */
    mov     x21, x2                 /* output */
    mov     x22, x3                 /* output size */
    
    /* Check if status is in static table (indexed) */
    cmp     x20, #200
    beq     h2_status_200
    cmp     x20, #204
    beq     h2_status_204
    cmp     x20, #206
    beq     h2_status_206
    cmp     x20, #304
    beq     h2_status_304
    cmp     x20, #400
    beq     h2_status_400
    cmp     x20, #404
    beq     h2_status_404
    cmp     x20, #500
    beq     h2_status_500
    
    /* Not in static table - encode as literal */
    b       h2_status_literal

h2_status_200:
    /* Index 8: :status 200 */
    mov     x0, #0x88               /* 1 (indexed) + 7-bit index 8 */
    strb    w0, [x21]
    mov     x0, #1                  /* 1 byte encoded */
    b       h2_status_done

h2_status_204:
    /* Index 9: :status 204 */
    mov     x0, #0x89
    strb    w0, [x21]
    mov     x0, #1
    b       h2_status_done

h2_status_206:
    /* Index 10: :status 206 */
    mov     x0, #0x8A
    strb    w0, [x21]
    mov     x0, #1
    b       h2_status_done

h2_status_304:
    /* Index 11: :status 304 */
    mov     x0, #0x8B
    strb    w0, [x21]
    mov     x0, #1
    b       h2_status_done

h2_status_400:
    /* Index 12: :status 400 */
    mov     x0, #0x8C
    strb    w0, [x21]
    mov     x0, #1
    b       h2_status_done

h2_status_404:
    /* Index 13: :status 404 */
    mov     x0, #0x8D
    strb    w0, [x21]
    mov     x0, #1
    b       h2_status_done

h2_status_500:
    /* Index 14: :status 500 */
    mov     x0, #0x8E
    strb    w0, [x21]
    mov     x0, #1
    b       h2_status_done

h2_status_literal:
    /* Encode :status as literal header field with indexing */
    /* Format: 0x40 (literal with indexing, 6-bit name index) + name_index + value */
    
    /* Check buffer space */
    cmp     x22, #16                /* need at least 16 bytes */
    blt     h2_status_err_overflow
    
    /* Name is at index 8 (:status) in static table */
    /* 0x40 | 0x08 = 0x48 (literal with indexing, 6-bit name index 8) */
    mov     x0, #0x48
    strb    w0, [x21], #1
    
    /* Convert status code to string */
    mov     x0, x20
    add     x1, sp, #40             /* temp buffer */
    bl      itoa
    mov     x23, x0                 /* status string length */
    
    /* Encode value length with 7-bit prefix, H=0 (no Huffman) */
    /* If value < 127, encode directly, else multibyte */
    cmp     x23, #127
    bge     h2_status_literal_long
    
    /* Short value: encode length directly */
    strb    w23, [x21], #1
    b       h2_status_copy_value

h2_status_literal_long:
    /* Long value: multibyte encoding */
    mov     x0, x23
    mov     x1, #0                  /* prefix = 0 */
    mov     x2, #7                  /* 7 prefix bits */
    mov     x3, x21                 /* output */
    bl      hpack_encode_integer
    add     x21, x21, x0

h2_status_copy_value:
    /* Copy status string */
    mov     x0, x21
    add     x1, sp, #40             /* status string */
    mov     x2, x23
    bl      memcpy
    
    /* Calculate total encoded length */
    sub     x0, x21, x2
    add     x0, x0, x23
    b       h2_status_done

h2_status_err_overflow:
    mov     x0, #-1

h2_status_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

/* ================================================================================================
 * h2_encode_content_type(conn, content_type, output, output_size)
 * Encode content-type header
 * x0 = connection
 * x1 = content-type string
 * x2 = output buffer
 * x3 = output size
 * Returns: x0 = encoded length
 * ================================================================================================ */
h2_encode_content_type:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* content-type */
    mov     x21, x2                 /* output */
    mov     x22, x3                 /* output size */
    
    /* TODO: Use static table index for common types? */
    /* content-type is at index 31 in static table (name only) */
    
    /* For now, encode as literal without indexing */
    /* 0x40 | 0x1F = 0x5F (literal with indexing, 6-bit name index 31) */
    /* Actually, better to not index response headers - use 0x40 (literal without indexing) */
    
    mov     x0, #0x40               /* literal without indexing, new name */
    strb    w0, [x21], #1
    
    /* Encode name length and name "content-type" */
    adr     x0, h2_content_type_name
    bl      strlen
    mov     x23, x0                 /* name length = 12 */
    
    /* Encode name length (7-bit prefix, no Huffman) */
    strb    w23, [x21], #1
    
    /* Copy name */
    adr     x0, h2_content_type_name
    mov     x1, x21
    mov     x2, x23
    bl      memcpy
    add     x21, x21, x23
    
    /* Encode value length */
    mov     x0, x20
    bl      strlen
    mov     x23, x0                 /* value length */
    strb    w23, [x21], #1
    
    /* Copy value */
    mov     x0, x21
    mov     x1, x20
    mov     x2, x23
    bl      memcpy
    add     x21, x21, x23
    
    /* Calculate total length */
    sub     x0, x21, x2

h2_encode_ct_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* ================================================================================================
 * h2_encode_content_length(conn, length, output, output_size)
 * Encode content-length header
 * x0 = connection
 * x1 = content length (integer)
 * x2 = output buffer
 * x3 = output size
 * Returns: x0 = encoded length
 * ================================================================================================ */
h2_encode_content_length:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* content length */
    mov     x21, x2                 /* output */
    mov     x22, x3                 /* output size */
    
    /* content-length is at index 28 in static table (name only) */
    /* Encode as literal with indexing (0x40 | 0x1C = 0x5C) */
    mov     x0, #0x5C
    strb    w0, [x21], #1
    
    /* Convert length to string */
    mov     x0, x20
    add     x1, sp, #40
    bl      itoa
    mov     x23, x0                 /* string length */
    
    /* Encode value length */
    strb    w23, [x21], #1
    
    /* Copy value */
    mov     x0, x21
    add     x1, sp, #40
    mov     x2, x23
    bl      memcpy
    add     x21, x21, x23
    
    /* Calculate total length */
    sub     x0, x21, x2

h2_encode_cl_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

/* ================================================================================================
 * h2_complete_file_response(conn, stream, fd, path)
 * Complete HTTP/2 file response including headers and file data
 * x0 = connection
 * x1 = stream
 * x2 = file descriptor
 * x3 = path (for MIME type detection)
 * Returns: x0 = 0 on success
 * ================================================================================================ */
h2_complete_file_response:
    stp     x29, x30, [sp, #-128]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* stream */
    mov     x21, x2                 /* file fd */
    mov     x22, x3                 /* path */
    
    /* Get file size */
    mov     x0, x21
    bl      get_file_size
    mov     x23, x0                 /* file size */
    cmp     x0, #0
    blt     h2_file_resp_err
    
    /* Get stream ID */
    ldr     w24, [x20]              /* stream_id */
    
    /* Build headers block */
    sub     sp, sp, #4096
    mov     x25, sp                 /* headers buffer */
    
    /* Start with :status 200 */
    mov     x0, x19
    mov     x1, #200
    mov     x2, x25
    mov     x3, #4096
    bl      h2_encode_status_header
    cmp     x0, #0
    blt     h2_file_resp_cleanup
    add     x26, x25, x0            /* current position */
    mov     x27, x0                 /* headers length so far */
    
    /* TODO: Add content-type based on file extension */
    /* TODO: Add content-length */
    
    /* Send HEADERS frame */
    mov     x0, x19
    mov     x1, x24
    mov     x2, x25
    mov     x3, x27
    mov     x4, #0x04               /* END_HEADERS */
    bl      h2_send_headers_frame
    cmp     x0, #0
    blt     h2_file_resp_cleanup
    
    /* Send file data using sendfile */
    mov     x0, x19
    mov     x1, x24
    mov     x2, x21
    mov     x3, x23
    mov     x4, #0x01               /* END_STREAM */
    bl      h2_send_file_data
    
h2_file_resp_cleanup:
    add     sp, sp, #4096

h2_file_resp_err:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x25, x26, [sp, #64]
    ldp     x27, x28, [sp, #80]
    ldp     x29, x30, [sp], #128
    ret

/* ================================================================================================
 * h2_send_file_data(conn, stream_id, fd, length, flags)
 * Send file data as HTTP/2 DATA frames
 * Uses sendfile for efficient zero-copy
 * x0 = connection
 * x1 = stream_id
 * x2 = file descriptor
 * x3 = file length
 * x4 = flags (END_STREAM)
 * ================================================================================================ */
h2_send_file_data:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    
    mov     x19, x0                 /* connection */
    mov     x20, x1                 /* stream_id */
    mov     x21, x2                 /* file fd */
    mov     x22, x3                 /* length */
    mov     x23, x4                 /* flags */
    
    /* For now, read file and send as DATA frames */
    /* In production, use sendfile with proper offset tracking */
    
    sub     sp, sp, #16384          /* read buffer */
    mov     x24, sp
    
h2_send_file_loop:
    cmp     x22, #0
    beq     h2_send_file_done
    
    /* Read chunk from file */
    mov     x0, x21                 /* fd */
    mov     x1, x24                 /* buffer */
    mov     x2, #16384              /* max read */
    cmp     x2, x22
    csel    x2, x2, x22, lo         /* min(16384, remaining) */
    mov     x8, #SYS_READ
    svc     #0
    
    cmp     x0, #0
    ble     h2_send_file_err
    
    mov     x25, x0                 /* bytes read */
    sub     x22, x22, x25           /* remaining */
    
    /* Determine if this is the last chunk */
    mov     x4, #0                  /* flags = 0 */
    cmp     x22, #0
    csel    x4, x23, x4, eq         /* if remaining == 0, use original flags */
    
    /* Send DATA frame */
    mov     x0, x19                 /* connection */
    mov     x1, x20                 /* stream_id */
    mov     x2, x24                 /* data */
    mov     x3, x25                 /* length */
    /* x4 = flags already set */
    bl      h2_send_data_frame
    
    cmp     x0, #0
    blt     h2_send_file_err
    
    b       h2_send_file_loop

h2_send_file_done:
    mov     x0, #0

h2_send_file_err:
    add     sp, sp, #16384
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

/* ================================================================================================
 * External Functions
 * ================================================================================================ */
.section .rodata
.align 3

h2_content_type_name:   .asciz "content-type"
h2_content_length_name: .asciz "content-length"

.text
.align 2

.global hpack_encode_integer
.global strlen
.global itoa
.global memcpy
.global get_file_size
.global h2_send_headers_frame
.global h2_send_data_frame
