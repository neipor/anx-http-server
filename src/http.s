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
    stp x23, x24, [sp, #48]

    mov x20, x0             /* x20 = client_fd */
    
    /* Read Request */
    mov x0, x20
    ldr x1, =req_buffer
    mov x2, #2048
    mov x8, SYS_READ
    svc #0
    cmp x0, #0
    ble hc_close
    
    mov x22, x0             /* x22 = req len */
    
    /* Detect Method */
    ldr x1, =req_buffer
    ldrb w2, [x1]
    cmp w2, #'G'
    beq is_get
    cmp w2, #'P'
    beq is_post
    cmp w2, #'H'
    beq is_head
    b is_unknown

is_get:
    ldr x24, =str_get       /* x24 = method string */
    add x1, x1, #4          /* Skip "GET " */
    b method_done
is_post:
    ldr x24, =str_post
    add x1, x1, #5
    b method_done
is_head:
    ldr x24, =str_head
    add x1, x1, #5
    b method_done
is_unknown:
    ldr x24, =str_unknown
    add x1, x1, #4          /* Assume 4 chars? Unsafe but keeping simple */

method_done:
    /* x1 now points to Path start */
    
    /* Check Proxy Configuration */
    ldr x0, =upstream_ip
    ldr w0, [x0]
    cmp w0, #0
    bne do_proxy
    
    /* Parse Request Path (x1 is already set) */
    
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

    /* Check if it is a directory using FSTAT */
    mov x0, x21
    ldr x1, =stat_buffer
    mov x8, SYS_FSTAT
    svc #0
    
    ldr x1, =stat_buffer
    ldr w2, [x1, #16]       /* st_mode */
    and w2, w2, #0xF000     /* S_IFMT */
    cmp w2, #0x4000         /* S_IFDIR */
    beq send_redirect
    
    b serve_file

send_redirect:
    /* Close file fd */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    
    /* Send 301 Header */
    mov x0, x20
    ldr x1, =http_301_start
    ldr x2, =len_301_start
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Current Path */
    ldr x1, =req_buffer
    add x1, x1, #4
    mov x25, x1             /* Save path ptr */
    
        /* Log 301 */
        mov x0, x24
        mov x1, x25
        mov x2, #301
        bl log_request
    
        mov x0, x25
        bl strlen
        mov x2, x0
    mov x0, x20
    mov x1, x25
    mov x8, SYS_WRITE
    svc #0
    
    /* Send / and End */
    mov x0, x20
    ldr x1, =slash_newline
    ldr x2, =len_slash_nl
    mov x8, SYS_WRITE
    svc #0
    
    b hc_close

handle_directory_listing:
    mov x21, x0             /* x21 = dir_fd */
    
    /* Log 200 */
    mov x0, x24
    ldr x1, =req_buffer
    add x1, x1, #4
    mov x2, #200
    bl log_request
    
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
    
    /* Send double CRLF */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Dir Start (Table Header) */
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
    
    ldrh w23, [x22, #16]    /* d_reclen */
    
    /* Name at x22 + 19 */
    add x25, x22, #19       /* x25 = name ptr */
    
    /* Get File Size using NEWFSTATAT(dirfd, name, buf, flags) */
    mov x0, x21
    mov x1, x25
    ldr x2, =stat_buffer
    mov x3, #0
    mov x8, SYS_NEWFSTATAT
    svc #0
    
    cmp x0, #0
    bne size_fail
    ldr x1, =stat_buffer
    ldr x26, [x1, #48]      /* st_size */
    b size_done
size_fail:
    mov x26, #0             /* 0 on error */
size_done:

    /* Send Row Start */
    mov x0, x20
    ldr x1, =tr_start
    ldr x2, =len_tr_start
    mov x8, SYS_WRITE
    svc #0
    
    /* Send NAME */
    mov x0, x25
    bl strlen
    mov x2, x0
    mov x0, x20
    mov x1, x25
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Link Mid */
    mov x0, x20
    ldr x1, =tr_mid
    ldr x2, =len_tr_mid
    mov x8, SYS_WRITE
    svc #0
    
    /* Send NAME again */
    mov x0, x25
    bl strlen
    mov x2, x0
    mov x0, x20
    mov x1, x25
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Link End & Cell Mid */
    mov x0, x20
    ldr x1, =tr_mid_2
    ldr x2, =len_tr_mid_2
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Size */
    mov x0, x26
    ldr x1, =num_buffer
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =num_buffer
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Row End */
    mov x0, x20
    ldr x1, =tr_end
    ldr x2, =len_tr_end
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
    /* Get File Size from cached stat_buffer (filled in got_file_fd) */
    /* st_size is at offset 48 */
    ldr x1, =stat_buffer
    ldr x22, [x1, #48]      /* x22 = file size */
    
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
    /* Log 200 */
    mov x0, x24
    ldr x1, =req_buffer
    add x1, x1, #4
    mov x2, #200
    bl log_request

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

do_proxy:
    bl connect_to_upstream
    cmp x0, #0
    blt send_502
        mov x21, x0     /* x21 = upstream_fd */
        
        /* Log 200 (Proxy) */
        mov x0, x24
        ldr x1, =req_buffer
        add x1, x1, #4
        mov x2, #200
        bl log_request
    
        /* Forward Request (Original, x22 = len) */
        mov x0, x21
    ldr x1, =req_buffer
    mov x2, x22
    mov x8, SYS_WRITE
    svc #0
    
proxy_loop:
    mov x0, x21     /* upstream */
    ldr x1, =req_buffer
    mov x2, #2048
    mov x8, SYS_READ
    svc #0
    
    cmp x0, #0
    ble proxy_done
    
    mov x2, x0      /* len */
    mov x0, x20     /* client */
    ldr x1, =req_buffer
    mov x8, SYS_WRITE
    svc #0
    
    b proxy_loop

proxy_done:
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    b hc_close

send_502:
    /* Log 502 */
    mov x0, x24
    ldr x1, =req_buffer
    add x1, x1, #4
    mov x2, #502
    bl log_request

    mov x0, x20
    ldr x1, =http_502
    ldr x2, =len_502
    mov x8, SYS_WRITE
    svc #0
    b hc_close

send_404:
    /* Log 404 */
    mov x0, x24
    ldr x1, =req_buffer
    add x1, x1, #4
    mov x2, #404
    bl log_request

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
