/* src/http.s - HTTP Request Handling */

.include "src/defs.s"

.global handle_client

.text

/* handle_client(client_fd) */
handle_client:
    stp x29, x30, [sp, #-48]! /* Allocate 48 bytes */
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    str x23, [sp, #48]        /* Wait, offset 48 is out of bounds if size is 48 (0-47) */
    
    /* Correct alignment: 
       sp -> [x29, x30] (0-15)
             [x19, x20] (16-31)
             [x21, x22] (32-47)
             [x23, padding] (48-63)
       Total alloc: 64 bytes
    */
    
    add sp, sp, #48           /* Restore SP first? No. Re-do logic */
    
    /* New Prologue */
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    str x23, [sp, #48]

    mov x20, x0             /* x20 = client_fd */
    
    /* Read Request */
    mov x0, x20
    ldr x1, =req_buffer
    mov x2, #2048
    mov x8, SYS_READ
    svc #0
    cmp x0, #0
    ble hc_close
    
    /* Parse Request Path (Simple: assume "GET <path> HTTP...") */
    ldr x1, =req_buffer
    
    /* Skip "GET " */
    add x1, x1, #4
    
    /* Find end of path (space) */
    mov x2, x1
find_path_end:
    ldrb w3, [x2]
    cmp w3, #' '
    beq path_found
    add x2, x2, #1
    b find_path_end

path_found:
    mov w3, #0
    strb w3, [x2]           /* Null terminate path */
    
    /* Construct full path: root + path */
    ldr x0, =file_path
    ldr x1, =server_root
    bl strcpy
    
    /* If path is "/", append "/index.html" */
    ldr x1, =req_buffer
    add x1, x1, #4          /* x1 points to path */
    
    ldrb w3, [x1]
    cmp w3, #0              /* Empty path? */
    beq append_index
    
    ldr x2, =req_buffer
    add x2, x2, #4
    ldrb w3, [x2]
    ldrb w4, [x2, #1]
    cmp w3, #'/'
    bne append_path
    cmp w4, #0
    beq append_index

append_path:
    ldr x0, =file_path
    /* x1 is already path */
    bl strcat
    b open_file

append_index:
    ldr x0, =file_path
    ldr x1, =index_file
    bl strcat

open_file:
    /* x0 (file_path) is ready */
    mov x1, O_RDONLY
    mov x2, #0
    mov x8, SYS_OPENAT
    mov x0, AT_FDCWD
    ldr x1, =file_path
    svc #0
    
    cmp x0, #0
    blt send_404
    mov x21, x0             /* x21 = file_fd */
    
    /* Get File Size using LSEEK */
    mov x0, x21
    mov x1, #0
    mov x2, SEEK_END
    mov x8, SYS_LSEEK
    svc #0
    mov x22, x0             /* x22 = file size */
    
    /* Reset File Ptr */
    mov x0, x21
    mov x1, #0
    mov x2, SEEK_SET
    mov x8, SYS_LSEEK
    svc #0
    
    /* Determine MIME Type */
    ldr x0, =file_path
    bl get_extension
    cmp x0, #0
    beq set_mime_plain      /* No extension -> plain */
    
    /* Compare Extensions */
    mov x19, x0             /* Save ext ptr */
    
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
    ldr x1, =ext_png
    bl strcmp
    cmp x0, #0
    beq set_mime_png
    
    mov x0, x19
    ldr x1, =ext_jpg
    bl strcmp
    cmp x0, #0
    beq set_mime_jpg
    
    b set_mime_plain

set_mime_html:
    ldr x23, =mime_html
    b send_response
set_mime_css:
    ldr x23, =mime_css
    b send_response
set_mime_js:
    ldr x23, =mime_js
    b send_response
set_mime_png:
    ldr x23, =mime_png
    b send_response
set_mime_jpg:
    ldr x23, =mime_jpg
    b send_response
set_mime_plain:
    ldr x23, =mime_plain

send_response:
    /* Send 200 Start */
    mov x0, x20
    ldr x1, =http_200_start
    ldr x2, =len_200_start
    mov x8, SYS_WRITE
    svc #0
    
    /* Send MIME String */
    mov x0, x23             /* MIME string */
    bl strlen               /* Calc MIME len */
    mov x2, x0              /* Length */
    mov x1, x23             /* RELOAD Buffer (MIME string) - Critical Fix */
    mov x0, x20             /* fd */
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Content-Length Header Part */
    mov x0, x20
    ldr x1, =http_content_len
    ldr x2, =len_content_len
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Size Value */
    mov x0, x22
    ldr x1, =num_buffer
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =num_buffer
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Header End (CRLF CRLF) */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0
    
    /* Send File (sendfile) */
    mov x0, x20
    mov x1, x21
    mov x2, #0              /* offset = NULL */
    mov x3, x22             /* count = size */
    mov x8, SYS_SENDFILE
    svc #0
    
    /* Close file */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    
    b hc_close

send_404:
    mov x0, x20
    ldr x1, =http_404
    ldr x2, =len_404
    mov x8, SYS_WRITE
    svc #0

hc_close:
    mov x0, x20
    mov x8, SYS_CLOSE
    svc #0
    
    ldr x23, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret