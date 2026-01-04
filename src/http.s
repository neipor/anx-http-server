/* src/http.s - HTTP Request Handling */

.include "src/defs.s"

.global handle_client

.text

/* handle_client(client_fd) */
handle_client:
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
    
    /* Parse Request Path */
    ldr x1, =req_buffer
    add x1, x1, #4          /* Skip "GET " */
    
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
    
    /* Check if path ends with '/' */
    sub x2, x2, #1
    ldrb w3, [x2]
    cmp w3, #'/'
    beq is_dir_req
    
    /* Construct full path: root + path */
    ldr x0, =file_path
    ldr x1, =server_root
    bl strcpy
    
    ldr x0, =file_path
    ldr x1, =req_buffer
    add x1, x1, #4
    bl strcat
    
    b open_file_direct

is_dir_req:
    /* Construct full path: root + path */
    ldr x0, =file_path
    ldr x1, =server_root
    bl strcpy
    
    ldr x0, =file_path
    ldr x1, =req_buffer
    add x1, x1, #4
    bl strcat
    
    /* Try adding index.html */
    ldr x0, =file_path
    ldr x1, =index_file
    bl strcat
    
    /* Try open index.html */
    mov x1, O_RDONLY
    mov x2, #0
    mov x8, SYS_OPENAT
    mov x0, AT_FDCWD
    ldr x1, =file_path
    svc #0
    
    cmp x0, #0
    bge got_file_fd         /* Found index.html */
    
    /* Failed to open index.html, revert path (remove /index.html) */
    /* Or just re-construct path without index.html */
    ldr x0, =file_path
    ldr x1, =server_root
    bl strcpy
    
    ldr x0, =file_path
    ldr x1, =req_buffer
    add x1, x1, #4
    bl strcat
    
    /* Now try open as directory */
    mov x1, O_RDONLY
    mov x2, #1
    lsl x2, x2, #14       /* 0x4000 = O_DIRECTORY */
    
    mov x8, SYS_OPENAT
    mov x0, AT_FDCWD
    ldr x1, =file_path
    svc #0
    
    cmp x0, #0
    bge handle_directory_listing
    
    b send_404

open_file_direct:
    mov x1, O_RDONLY
    mov x2, #0
    mov x8, SYS_OPENAT
    mov x0, AT_FDCWD
    ldr x1, =file_path
    svc #0
    
    cmp x0, #0
    blt send_404
    
got_file_fd:
    mov x21, x0             /* x21 = file_fd */
    b serve_file

handle_directory_listing:
    mov x21, x0             /* x21 = dir_fd */
    
    /* Send 200 Header (HTML) */
    mov x0, x20
    ldr x1, =http_200_start
    ldr x2, =len_200_start
    mov x8, SYS_WRITE
    svc #0
    
    ldr x23, =mime_html
    mov x0, x20
    mov x1, x23
    mov x0, x23
    bl strlen
    mov x2, x0
    mov x1, x23             /* Reload */
    mov x0, x20
    mov x8, SYS_WRITE
    svc #0
    
    /* End header (Chunked or just close? We don't know size. Use connection: close) */
    /* We sent Content-Length part in http_200_start... Wait. */
    /* My http_200_start includes "Content-Type: ". */
    /* Then I need "Content-Length: ...". But I don't know length! */
    /* I should NOT send Content-Length for directory listing if I stream it. */
    /* But HTTP/1.1 needs length or chunked. */
    /* Simple: connection close and no content-length? */
    /* Or buffer the whole HTML? 2KB req_buffer is small. */
    /* Let's use Connection: close and NO Content-Length header. */
    
    /* But `http_content_len` is in `data.s`. I can skip it. */
    /* Just send double CRLF */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Dir Start */
    mov x0, x20
    ldr x1, =dir_html_start
    ldr x2, =len_dir_start
    mov x8, SYS_WRITE
    svc #0
    
    /* Read Directory Entries */
dir_loop:
    mov x0, x21             /* dir_fd */
    ldr x1, =req_buffer     /* reuse req_buffer for dirents */
    mov x2, #2048
    mov x8, SYS_GETDENTS64
    svc #0
    
    cmp x0, #0
    ble dir_done            /* 0 = EOF, <0 = Error */
    
    mov x19, x0             /* x19 = bytes read */
    ldr x22, =req_buffer    /* x22 = current ptr */
    add x19, x22, x19       /* x19 = end ptr */
    
parse_dirent:
    cmp x22, x19
    bge dir_loop            /* Buffer consumed, read more */
    
    /* linux_dirent64 layout:
       0: d_ino (8)
       8: d_off (8)
       16: d_reclen (2)
       18: d_type (1)
       19: d_name (string)
    */
    
    ldrh w23, [x22, #16]    /* d_reclen */
    
    /* Print <li><a href="NAME">NAME</a></li> */
    /* Name at x22 + 19 */
    add x24, x22, #19       /* x24 = name ptr */
    
    /* Skip "." and ".." if desired? Let's keep them. */
    
    /* Send <li><a href=" */
    mov x0, x20
    ldr x1, =li_start
    ldr x2, =len_li_start
    mov x8, SYS_WRITE
    svc #0
    
    /* Send NAME */
    mov x0, x24
    bl strlen
    mov x2, x0
    mov x0, x20
    mov x1, x24
    mov x8, SYS_WRITE
    svc #0
    
    /* Send "> */
    mov x0, x20
    ldr x1, =li_mid
    ldr x2, =len_li_mid
    mov x8, SYS_WRITE
    svc #0
    
    /* Send NAME again */
    mov x0, x24
    bl strlen
    mov x2, x0
    mov x0, x20
    mov x1, x24
    mov x8, SYS_WRITE
    svc #0
    
    /* Send </a></li> */
    mov x0, x20
    ldr x1, =li_end
    ldr x2, =len_li_end
    mov x8, SYS_WRITE
    svc #0
    
    /* Next entry */
    add x22, x22, x23       /* ptr += reclen */
    b parse_dirent

dir_done:
    /* Send Dir End */
    mov x0, x20
    ldr x1, =dir_html_end
    ldr x2, =len_dir_end
    mov x8, SYS_WRITE
    svc #0
    
    /* Close dir_fd */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    
    b hc_close

serve_file:
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
    mov x1, x23             /* RELOAD Buffer (MIME string) */
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
