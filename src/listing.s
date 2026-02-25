/* src/listing.s - Directory Listing Logic (Stable) */

.include "src/defs.s"

.global serve_directory
.global html_parent_row, len_html_parent_row

.text

/* serve_directory(client_fd, dir_path, req_path) */
serve_directory:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]

    mov x19, x0             /* client_fd */
    mov x23, x1             /* dir_path (saved for later if needed, mostly for open) */
    mov x22, x2             /* req_path */
    
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
    
    ldr x21, =iovec_buffer
    
    ldr x1, =http_200_close
    str x1, [x21]
    ldr x1, =len_200_close
    str x1, [x21, #8]
    
    ldr x1, =html_head
    str x1, [x21, #16]
    ldr x1, =len_html_head
    str x1, [x21, #24]
    
    mov x0, x19
    mov x1, x21
    mov x2, #2
    mov x8, SYS_WRITEV
    svc #0

    /* Check if we need Parent Link (if path != "/") */
    /* req_path in x22 */
    ldrb w4, [x22]
    cmp w4, #'/'
    bne render_parent
    ldrb w4, [x22, #1]
    cmp w4, #0
    beq start_dir_loop            /* Is root "/", skip parent link */

render_parent:
    mov x0, x19
    ldr x1, =html_parent_row
    ldr x2, =len_html_parent_row
    mov x8, SYS_WRITE
    svc #0

start_dir_loop:
dir_loop:
    mov x0, x20
    ldr x1, =req_buffer
    mov x2, #8192
    mov x8, SYS_GETDENTS64
    svc #0
    
    cmp x0, #0
    ble dir_done
    
    mov x22, x0             /* x22 = nread */
    ldr x21, =req_buffer    /* x21 = current ptr */
    add x22, x21, x22       /* x22 = end ptr */
    
parse_entry:
    cmp x21, x22
    bge dir_loop
    
    ldrh w23, [x21, #16]    /* d_reclen */
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
    ldr x28, =iovec_buffer
    
    /* 0 */
    ldr x1, =html_row_start
    str x1, [x28]
    ldr x1, =len_html_row_start
    str x1, [x28, #8]
    
    /* 1 */
    str x24, [x28, #16]
    mov x0, x24
    bl strlen
    str x0, [x28, #24]
    
    /* 2 */
    ldr x1, =html_row_mid1
    str x1, [x28, #32]
    ldr x1, =len_html_row_mid1
    str x1, [x28, #40]
    
    /* 3 */
    str x24, [x28, #48]
    mov x0, x24
    bl strlen
    str x0, [x28, #56]
    
    /* 4 */
    ldr x1, =html_row_mid2
    str x1, [x28, #64]
    ldr x1, =len_html_row_mid2
    str x1, [x28, #72]
    
    /* 5 */
    mov x0, x26
    ldr x1, =time_buffer
    bl itoa
    ldr x1, =time_buffer
    str x1, [x28, #80]
    str x0, [x28, #88]
    
    /* 6 */
    ldr x1, =html_row_mid3
    str x1, [x28, #96]
    ldr x1, =len_html_row_mid3
    str x1, [x28, #104]
    
    /* 7 */
    mov x0, x25
    ldr x1, =num_buffer
    bl itoa
    ldr x1, =num_buffer
    str x1, [x28, #112]
    str x0, [x28, #120]
    
    /* 8 */
    ldr x1, =html_row_end
    str x1, [x28, #128]
    ldr x1, =len_html_row_end
    str x1, [x28, #136]
    
    mov x0, x19
    mov x1, x28
    mov x2, #9
    mov x8, SYS_WRITEV
    svc #0
    
skip_entry:
    add x21, x21, x23
    b parse_entry

dir_done:
    mov x0, x19
    ldr x1, =html_tail
    ldr x2, =len_html_tail
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x20
    mov x8, SYS_CLOSE
    svc #0
    
    b sd_exit

sd_fail:
    /* Just return, caller handles error/close */
    
sd_exit:
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret
