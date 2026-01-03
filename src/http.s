/* src/http.s - HTTP Request Handling */

.include "src/defs.s"

.global handle_client

.text

/* handle_client(client_fd) */
handle_client:
    stp x29, x30, [sp, #-16]!
    stp x20, x21, [sp, #-16]!
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
    
    /* Send 200 Header */
    mov x0, x20
    ldr x1, =http_200
    ldr x2, =len_200
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Size */
    mov x0, x22
    ldr x1, =num_buffer
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =num_buffer
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Header End */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0
    
    /* Send File (sendfile) */
    /* sendfile(out_fd, in_fd, offset, count) */
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
    
    ldp x20, x21, [sp], #16
    ldp x29, x30, [sp], #16
    ret
