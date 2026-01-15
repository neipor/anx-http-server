/* src/http.s - Full Implementation */

.include "src/defs.s"

.global handle_client

.text

/* ------------------------------------------------------------------------- */
/* handle_client(client_fd) */
/* ------------------------------------------------------------------------- */
handle_client:
    /* Stack Frame: 96 bytes */
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]

    mov x20, x0             /* x20 = client_fd */

hc_loop:
    /* 1. Read Request */
    mov x0, x20
    ldr x1, =req_buffer
    mov x2, #8192
    mov x8, SYS_READ
    svc #0

    cmp x0, #0
    ble hc_close_final

    /* 2. Parse Request */
    ldr x0, =req_buffer
    bl parse_request
    cmp x0, #0
    bne send_400

    /* 3. Security: Check Directory Traversal */
    ldr x0, =req_path
    bl check_traversal
    cmp x0, #0
    bne send_403

    /* 4. Resolve Path */
    /* Construct full path: server_root + req_path */
    ldr x27, =path_buffer
    
    ldr x0, =path_buffer    /* dst */
    ldr x1, =server_root    /* src */
    bl strcpy
    
    ldr x0, =path_buffer    /* dst */
    ldr x1, =req_path       /* src */
    bl strcat

    /* 5. Stat File */
    mov x0, AT_FDCWD
    mov x1, x27             /* path_buffer */
    ldr x2, =stat_buffer
    mov x3, #0              /* flags */
    mov x8, SYS_NEWFSTATAT
    svc #0

    cmp x0, #0
    blt send_404

    /* 6. Check File Type */
    ldr x1, =stat_buffer
    ldr w2, [x1, #16]       /* st_mode */
    
    ldr w3, =S_IFMT
    and w3, w2, w3
    
    ldr w4, =S_IFDIR
    cmp w3, w4
    beq handle_dir
    
    ldr w4, =S_IFREG
    cmp w3, w4
    beq handle_file_load_size
    
    b send_403

/* ------------------------------------------------------------------------- */
/* File Handling */
/* ------------------------------------------------------------------------- */
handle_file_load_size:
    ldr x1, =stat_buffer
    ldr x22, [x1, #48]      /* st_size */
    b serve_file

handle_file:
    b serve_file

/* ------------------------------------------------------------------------- */
/* Directory Handling */
/* ------------------------------------------------------------------------- */
handle_dir:
    /* Check if index.html exists */
    ldr x0, =path_buffer
    ldr x1, =index_file
    bl strcat
    
    mov x0, AT_FDCWD
    ldr x1, =path_buffer
    ldr x2, =stat_buffer
    mov x3, #0
    mov x8, SYS_NEWFSTATAT
    svc #0
    
    cmp x0, #0
    beq handle_file_load_size         /* index.html exists -> serve it */
    
    /* Else -> Listing */
    ldr x0, =path_buffer    /* dst */
    ldr x1, =server_root    /* src */
    bl strcpy
    ldr x0, =path_buffer
    ldr x1, =req_path
    bl strcat
    
    mov x0, x20             /* client_fd */
    ldr x1, =path_buffer
    ldr x2, =req_path       /* relative path for links */
    bl serve_directory
    b hc_close_final

/* ------------------------------------------------------------------------- */
/* Serve File Logic */
/* ------------------------------------------------------------------------- */
serve_file:
    /* Open File */
    mov x0, AT_FDCWD
    ldr x1, =path_buffer
    mov x2, O_RDONLY
    mov x3, #0
    mov x8, SYS_OPENAT
    svc #0
    
    cmp x0, #0
    blt send_403
    mov x21, x0             /* x21 = file_fd */

    /* MIME Detection */
    ldr x0, =path_buffer
    bl get_extension
    mov x19, x0             /* x19 = ext ptr */
    
    cmp x19, #0
    beq set_mime_bin

    /* Compare Extensions */
    mov x0, x19
    ldr x1, =ext_html
    bl strcmp
    cmp x0, #0
    beq set_mime_html
    
    mov x0, x19
    ldr x1, =ext_css
    bl strcmp
    cmp x0, #0
    beq set_mime_css
    
    mov x0, x19
    ldr x1, =ext_js
    bl strcmp
    cmp x0, #0
    beq set_mime_js
    
    mov x0, x19
    ldr x1, =ext_txt
    bl strcmp
    cmp x0, #0
    beq set_mime_txt
    
    /* Default */
    b set_mime_bin

set_mime_html:
    ldr x25, =mime_html
    mov x26, #9
    b send_response
set_mime_css:
    ldr x25, =mime_css
    mov x26, #8
    b send_response
set_mime_js:
    ldr x25, =mime_js
    mov x26, #22
    b send_response
set_mime_txt:
    ldr x25, =mime_txt
    mov x26, #10
    b send_response
set_mime_bin:
    ldr x25, =mime_bin
    mov x26, #24
    b send_response

send_response:
    /* 1. Write HTTP header start */
    mov x0, x20
    ldr x1, =http_200_start
    mov x2, #55
    mov x8, SYS_WRITE
    svc #0
    
    /* 2. Write MIME type */
    mov x0, x20
    mov x1, x25
    mov x2, x26
    mov x8, SYS_WRITE
    svc #0
    
    /* 3. Write Content-Length header */
    mov x0, x20
    ldr x1, =http_content_len
    mov x2, #18
    mov x8, SYS_WRITE
    svc #0
    
    /* 4. Write content length value */
    mov x0, x22
    ldr x1, =content_len_str
    bl itoa
    mov x2, x0
    mov x0, x20
    mov x8, SYS_WRITE
    svc #0
    
    /* 5. Write header end */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0
    
    /* 6. Send file content using sendfile */
    ldr x0, =sendfile_offset
    str xzr, [x0]            /* offset = 0 */
    mov x0, x20              /* out fd */
    mov x1, x21              /* in fd */
    ldr x2, =sendfile_offset /* offset ptr */
    mov x3, x22              /* count */
    mov x8, SYS_SENDFILE
    svc #0
    
    /* Close file */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    b hc_close_final

/* ------------------------------------------------------------------------- */
/* Error Handlers */
/* ------------------------------------------------------------------------- */
send_400:
    mov x0, x20
    ldr x1, =http_400
    ldr x2, =len_400
    mov x8, SYS_WRITE
    svc #0
    b hc_close_final

send_403:
    mov x0, x20
    ldr x1, =http_403
    ldr x2, =len_403
    mov x8, SYS_WRITE
    svc #0
    b hc_close_final

send_404:
    mov x0, x20
    ldr x1, =http_404
    ldr x2, =len_404
    mov x8, SYS_WRITE
    svc #0
    b hc_close_final

hc_close_final:
    mov x0, x20
    mov x8, SYS_CLOSE
    svc #0
    
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

/* ------------------------------------------------------------------------- */
/* Helpers */
/* ------------------------------------------------------------------------- */
parse_request:
    /* Find space */
    mov x1, x0
    mov x2, #0
pr_loop:
    ldrb w3, [x1, x2]
    cbz w3, pr_err
    cmp w3, #32     /* Space */
    beq pr_found_method
    add x2, x2, #1
    cmp x2, #10     /* Method too long? */
    bge pr_err
    b pr_loop
pr_found_method:
    add x1, x1, x2  /* Space after method */
    add x1, x1, #1  /* Start of path */
    
    /* Copy path to req_path */
    ldr x4, =req_path
    mov x5, #0
pr_path_loop:
    ldrb w3, [x1, x5]
    cbz w3, pr_done
    cmp w3, #32     /* Space */
    beq pr_path_done
    strb w3, [x4, x5]
    add x5, x5, #1
    cmp x5, #255
    bge pr_path_done
    b pr_path_loop
pr_path_done:
    strb wzr, [x4, x5] /* Null terminate */
    
    /* Check if path is empty -> / */
    cmp x5, #0
    bne pr_ok
    mov w3, #47     /* / */
    strb w3, [x4]
    strb wzr, [x4, #1]
    
pr_ok:
    mov x0, #0
    ret
pr_done:
    strb wzr, [x4, x5]
    b pr_ok

pr_err:
    mov x0, #-1
    ret

check_traversal:
    mov x1, x0
    mov x2, #0
ct_loop:
    ldrb w3, [x1, x2]
    cbz w3, ct_ok
    cmp w3, #46     /* . */
    beq ct_dot
    add x2, x2, #1
    b ct_loop
ct_dot:
    add x2, x2, #1
    ldrb w3, [x1, x2]
    cmp w3, #46     /* . */
    beq ct_fail
    b ct_loop
ct_ok:
    mov x0, #0
    ret
ct_fail:
    mov x0, #-1
    ret
