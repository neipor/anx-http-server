/* src/listing.s - Directory Listing Logic (event-driven, buffer generating) */

.include "src/defs.s"

.global serve_directory
.global html_parent_row, len_html_parent_row

/* list_buf capacity (data.s: list_buf .skip 524288).
 * SD_SOFT_CAP is the per-row watermark: once the cursor passes it we stop
 * emitting rows and close the document. The 2048 bytes of headroom always
 * fit the truncation note (28B) plus html_tail (30B). */
.equ SD_BUF_CAP,  524288
.equ SD_SOFT_CAP, 522240

.text

/* -------------------------------------------------------------------------
 * serve_directory(x0 = client_fd, x1 = dir_path, x2 = req_path) -> x0 = len
 *
 * Renders the full directory listing HTML *body* (html_head .. html_tail)
 * into the global list_buf and stores the byte count in list_len; the same
 * count is returned in x0. Nothing is written to the socket any more --
 * the caller (http.s handle_dir) owns the response header and must emit a
 * Content-Length equal to the returned length, then hand list_buf to the
 * connection as a PTR body (conn->wptr / conn->wlen / CONN_F_PTR_BODY).
 *
 * x0 (client_fd) is accepted for signature compatibility only; unused.
 * getdents64 scratch is config_buffer (8192B) -- req_buffer is no longer
 * touched, so the parsed request survives the listing (defect A5).
 * On open failure: list_len = 0 and x0 = 0.
 *
 * Cursor registers: x28 = list_buf base, x19 = write cursor,
 *                   x27 = soft-cap pointer (base + SD_SOFT_CAP).
 * ------------------------------------------------------------------------- */
serve_directory:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]

    mov x23, x1             /* dir_path (used for the open only) */
    mov x22, x2             /* req_path (used for the parent link test) */

    ldr x28, =list_buf      /* output base */
    mov x19, x28            /* write cursor */
    ldr x27, =SD_SOFT_CAP
    add x27, x28, x27       /* row watermark pointer */

    /* Open Directory */
    mov x0, AT_FDCWD
    mov x1, x23
    ldr x2, =O_DIRECTORY
    ldr x3, =O_RDONLY
    orr x2, x2, x3
    mov x3, #0
    mov x8, SYS_OPENAT
    svc #0

    cmp x0, #0
    blt sd_fail
    mov x20, x0             /* dir_fd */

    /* Document head (no status line: the caller owns the HTTP header) */
    ldr x0, =html_head
    ldr x1, =len_html_head
    bl sd_put

    /* Check if we need Parent Link (if path != "/") */
    /* req_path in x22 */
    ldrb w4, [x22]
    cmp w4, #'/'
    bne render_parent
    ldrb w4, [x22, #1]
    cmp w4, #0
    beq start_dir_loop            /* Is root "/", skip parent link */

render_parent:
    ldr x0, =html_parent_row
    ldr x1, =len_html_parent_row
    bl sd_put

start_dir_loop:
dir_loop:
    mov x0, x20
    ldr x1, =config_buffer  /* getdents64 scratch (was req_buffer: defect A5) */
    mov x2, #8192
    mov x8, SYS_GETDENTS64
    svc #0

    cmp x0, #0
    ble dir_done

    mov x22, x0             /* x22 = nread */
    ldr x21, =config_buffer /* x21 = current ptr */
    add x22, x21, x22       /* x22 = end ptr */

parse_entry:
    cmp x21, x22
    bge dir_loop

    /* Stop emitting rows once the watermark is crossed */
    cmp x19, x27
    bge sd_truncated

    ldrh w23, [x21, #16]    /* d_reclen */
    cbz w23, dir_loop       /* defensive: a zero reclen would spin forever */
    add x24, x21, #19       /* name */

    ldrb w0, [x24]
    cmp w0, #'.'
    bne process_entry
    ldrb w0, [x24, #1]
    cmp w0, #0
    beq skip_entry
    /* Ignore .. as well for now to keep listing clean */
    cmp w0, #'.'
    bne process_entry
    ldrb w0, [x24, #2]
    cmp w0, #0
    beq skip_entry

process_entry:
    /* We need to stat relative to dir_fd! */
    mov x0, x20             /* dir_fd */
    mov x1, x24             /* name */
    ldr x2, =stat_buffer
    mov x3, #0
    mov x8, SYS_NEWFSTATAT
    svc #0

    ldr x1, =stat_buffer
    cmp x0, #0
    beq stat_ok
    mov x25, #0
    mov x26, #0
    b render_row

stat_ok:
    ldr x25, [x1, #48]      /* st_size */
    ldr x26, [x1, #88]      /* st_mtime */

render_row:
    /* 0: "<tr><td><a href=\"" */
    ldr x0, =html_row_start
    ldr x1, =len_html_row_start
    bl sd_put

    /* 1: name (href) -- HTML-escaped (defect: names were raw => XSS) */
    mov x0, x24
    bl sd_escape

    /* 2: "\">" */
    ldr x0, =html_row_mid1
    ldr x1, =len_html_row_mid1
    bl sd_put

    /* 3: name (text) -- HTML-escaped */
    mov x0, x24
    bl sd_escape

    /* 4: "</a></td><td class='d' data-v='" */
    ldr x0, =html_row_mid2
    ldr x1, =len_html_row_mid2
    bl sd_put

    /* 5: mtime */
    mov x0, x26
    ldr x1, =time_buffer
    bl itoa
    mov x1, x0
    ldr x0, =time_buffer
    bl sd_put

    /* 6: "'></td><td class='r' data-v='" */
    ldr x0, =html_row_mid3
    ldr x1, =len_html_row_mid3
    bl sd_put

    /* 7: size */
    mov x0, x25
    ldr x1, =num_buffer
    bl itoa
    mov x1, x0
    ldr x0, =num_buffer
    bl sd_put

    /* 8: "'></td></tr>" */
    ldr x0, =html_row_end
    ldr x1, =len_html_row_end
    bl sd_put

skip_entry:
    add x21, x21, x23
    b parse_entry

sd_truncated:
    /* Watermark hit: note it in the document and finish early */
    ldr x0, =html_trunc_note
    ldr x1, =len_html_trunc_note
    bl sd_put

dir_done:
    ldr x0, =html_tail
    ldr x1, =len_html_tail
    bl sd_put

    mov x0, x20
    mov x8, SYS_CLOSE
    svc #0

    /* total length = cursor - base */
    sub x0, x19, x28
    ldr x1, =list_len
    str x0, [x1]
    b sd_exit

sd_fail:
    /* Open failed: empty body, caller decides the error response */
    mov x0, #0
    ldr x1, =list_len
    str x0, [x1]

sd_exit:
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

/* -------------------------------------------------------------------------
 * sd_put(x0 = src, x1 = len) - append to list_buf at the cursor.
 *
 * Leaf helper, local to serve_directory. Clamps the copy to the hard cap
 * (SD_BUF_CAP) so list_buf can never overrun, then advances the cursor.
 *   in/out: x19 = cursor, x28 = list_buf base (both preserved-by-contract)
 *   clobbers: x0-x6 only (x20-x27 survive, callers keep state there)
 * Inline ldp/stp copy: no call to memcpy/fast_memcpy, which would trash the
 * callee-saved cursor registers.
 * ------------------------------------------------------------------------- */
sd_put:
    cbz x1, sd_put_ret
    sub x4, x19, x28            /* current offset into list_buf */
    ldr x5, =SD_BUF_CAP
    subs x4, x5, x4             /* remaining = cap - offset */
    ble sd_put_ret
    cmp x1, x4
    csel x1, x1, x4, le         /* len = min(len, remaining) */

    mov x2, x0                  /* src */
    mov x3, x19                 /* dst */

sd_put_16:
    cmp x1, #16
    blt sd_put_8
    ldp x5, x6, [x2], #16
    stp x5, x6, [x3], #16
    sub x1, x1, #16
    b sd_put_16

sd_put_8:
    cmp x1, #8
    blt sd_put_tail
    ldr x5, [x2], #8
    str x5, [x3], #8
    sub x1, x1, #8

sd_put_tail:
    cbz x1, sd_put_done
sd_put_byte:
    ldrb w5, [x2], #1
    strb w5, [x3], #1
    subs x1, x1, #1
    bne sd_put_byte

sd_put_done:
    mov x19, x3                 /* publish advanced cursor */
sd_put_ret:
    ret

/* -------------------------------------------------------------------------
 * sd_escape(x0 = src) - append HTML-escaped copy of a NUL-terminated name
 * to list_buf at the cursor. Escapes & < > " ' (quotes matter in the
 * href="..." attribute context: a raw quote would close the attribute).
 *   in/out: x19 = cursor, x28 = list_buf base (both preserved-by-contract)
 *   clobbers: x0-x6 only.  Writing stops at SD_BUF_CAP; the cursor never
 *   moves past the cap so the caller's length math stays correct.
 * ------------------------------------------------------------------------- */
sd_escape:
    mov x2, x0                  /* src cursor */
    ldr x6, =SD_BUF_CAP
    add x6, x28, x6             /* hard cap pointer */

sd_esc_loop:
    cmp x19, x6
    bge sd_esc_done
    ldrb w4, [x2], #1
    cbz w4, sd_esc_done
    cmp w4, #'&'
    beq sd_esc_amp
    cmp w4, #'<'
    beq sd_esc_lt
    cmp w4, #'>'
    beq sd_esc_gt
    cmp w4, #'"'
    beq sd_esc_quot
    cmp w4, #39                 /* ' */
    beq sd_esc_apos
    strb w4, [x19], #1
    b sd_esc_loop

/* Emit a fixed-length entity: x0 = addr, x1 = len (clamped per byte) */
sd_esc_emit:
    mov x4, x0
    mov x5, x1
sd_esc_emit_loop:
    cbz x5, sd_esc_loop
    cmp x19, x6
    bge sd_esc_done
    ldrb w4, [x4], #1
    strb w4, [x19], #1
    sub x5, x5, #1
    b sd_esc_emit_loop

sd_esc_amp:
    ldr x0, =l_html_amp
    mov x1, #5
    b sd_esc_emit
sd_esc_lt:
    ldr x0, =l_html_lt
    mov x1, #4
    b sd_esc_emit
sd_esc_gt:
    ldr x0, =l_html_gt
    mov x1, #4
    b sd_esc_emit
sd_esc_quot:
    ldr x0, =l_html_quot
    mov x1, #6
    b sd_esc_emit
sd_esc_apos:
    ldr x0, =l_html_apos
    mov x1, #5
    b sd_esc_emit

sd_esc_done:
    ret

    .align 4
l_html_amp:
    .ascii "&amp;"
l_html_lt:
    .ascii "&lt;"
l_html_gt:
    .ascii "&gt;"
l_html_quot:
    .ascii "&quot;"
l_html_apos:
    .ascii "&#39;"

    .align 4
html_trunc_note:
    .ascii "\n<!-- listing truncated -->\n"
len_html_trunc_note = . - html_trunc_note
    .align 4
