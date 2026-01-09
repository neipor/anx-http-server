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
    
hc_loop:
    /* Read Request */
    mov x0, x20
    ldr x1, =req_buffer
    mov x2, #2048
    mov x8, SYS_READ
    svc #0
    
    /* Keep-Alive Check: 0 = EOF, <0 = Error */
    cmp x0, #0
    ble hc_close_final
    
    mov x22, x0             /* x22 = req len */
    
    /* Detect Method (SWAR) */
    ldr x1, =req_buffer
    ldr w2, [x1]            /* Load 4 bytes */
    
    ldr w3, =0x20544547     /* "GET " */
    cmp w2, w3
    beq is_get
    
    ldr w3, =0x54534f50     /* "POST" */
    cmp w2, w3
    beq is_post
    
    ldr w3, =0x44414548     /* "HEAD" */
    cmp w2, w3
    beq is_head
    
    b is_unknown

is_get:
    ldr x24, =str_get       /* x24 = method string */
    add x1, x1, #4          /* Skip "GET " */
    b method_done
is_post:
    ldr x24, =str_post
    add x1, x1, #5          /* "POST " */
    b method_done
is_head:
    ldr x24, =str_head
    add x1, x1, #5          /* "HEAD " */
    b method_done
is_unknown:
    ldr x24, =str_unknown
    add x1, x1, #4          /* Assume 4 chars? Unsafe but keeping simple */

method_done:
    /* Check Proxy Configuration */
    ldr x0, =upstream_ip
    ldr w0, [x0]
    cmp w0, #0
    bne do_proxy
    
    /* Parse Request Path */
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
    /* Construct full path */
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
    
    /* Failed to open index.html, revert path */
    ldr x0, =file_path
    ldr x1, =server_root
    bl strcpy
    
    ldr x0, =file_path
    ldr x1, =req_buffer
    add x1, x1, #4
    bl strcat
    
    /* Now try open as directory */
    mov x1, O_RDONLY
    mov x2, #0x4000       /* O_DIRECTORY */
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
    
    b hc_next_req

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
    
    ldrh w23, [x22, #16]    /* d_reclen */
    add x25, x22, #19       /* name */
    
    /* Size via NEWFSTATAT */
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

    /* HTML Table Row */
    mov x0, x20
    ldr x1, =tr_start
    ldr x2, =len_tr_start
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x25
    bl strlen
    mov x2, x0
    mov x0, x20
    mov x1, x25
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x20
    ldr x1, =tr_mid
    ldr x2, =len_tr_mid
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x25
    bl strlen
    mov x2, x0
    mov x0, x20
    mov x1, x25
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x20
    ldr x1, =tr_mid_2
    ldr x2, =len_tr_mid_2
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x26
    ldr x1, =num_buffer
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =num_buffer
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x20
    ldr x1, =tr_end
    ldr x2, =len_tr_end
    mov x8, SYS_WRITE
    svc #0
    
    add x22, x22, x23       /* ptr += reclen */
    b parse_dirent

dir_done:
    mov x0, x20
    ldr x1, =dir_html_end
    ldr x2, =len_dir_end
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    
    b hc_next_req

serve_file:
    /* Get File Size from cached stat_buffer (filled in got_file_fd) */
    /* st_size is at offset 48 */
    ldr x1, =stat_buffer
    ldr x22, [x1, #48]      /* x22 = file size */
    
    /* MIME Type (SWAR) */
    ldr x0, =file_path
    bl get_extension
    cmp x0, #0
    beq set_mime_plain
    
    mov x19, x0
    ldr x0, [x19]           /* Load 8 bytes */
    
    /* .html\0 = 0x006c6d74682e */
    ldr x1, =0x6c6d74682e
    cmp x0, x1
    beq set_mime_html
    
    /* .css\0 = 0x007373632e (5 bytes) */
    mov x2, #0xFFFFFFFFFF
    and x3, x0, x2
    ldr x1, =0x7373632e
    cmp x3, x1
    beq set_mime_css
    
    /* .js\0 = 0x00736a2e (4 bytes) */
    mov w3, w0
    ldr w1, =0x736a2e
    cmp w3, w1
    beq set_mime_js
    
    /* .png\0 = 0x00676e702e (5 bytes) */
    and x3, x0, x2
    ldr x1, =0x676e702e
    cmp x3, x1
    beq set_mime_png
    
    /* .jpg\0 = 0x0067706a2e (5 bytes) */
    and x3, x0, x2
    ldr x1, =0x67706a2e
    cmp x3, x1
    beq set_mime_jpg
    
    b set_mime_plain

set_mime_html: ldr x23, =mime_html
    b send_response
set_mime_css: ldr x23, =mime_css
    b send_response
set_mime_js: ldr x23, =mime_js
    b send_response
set_mime_png: ldr x23, =mime_png
    b send_response
set_mime_jpg: ldr x23, =mime_jpg
    b send_response
set_mime_plain: ldr x23, =mime_plain

send_response:
    /* Log 200 */
    mov x0, x24
    ldr x1, =req_buffer
    add x1, x1, #4
    mov x2, #200
    bl log_request

    /* PREPARE WRITEV (4 iovecs) */
    ldr x25, =iovec_buffer
    
    /* iov[0]: "HTTP/1.1 200 OK..." */
    ldr x1, =http_200_start
    str x1, [x25]           /* iov_base */
    ldr x1, =len_200_start
    str x1, [x25, #8]       /* iov_len */
    
    /* iov[1]: MIME Type */
    /* Need length of mime string */
    mov x0, x23
    bl strlen
    str x23, [x25, #16]     /* iov_base */
    str x0, [x25, #24]      /* iov_len */
    
    /* iov[2]: "Content-Length: " */
    ldr x1, =http_content_len
    str x1, [x25, #32]
    ldr x1, =len_content_len
    str x1, [x25, #40]
    
    /* iov[3]: Size Value */
    mov x0, x22
    ldr x1, =num_buffer
    bl itoa                 /* x0 = len */
    ldr x1, =num_buffer
    str x1, [x25, #48]
    str x0, [x25, #56]
    
    /* iov[4]: CRLF CRLF */
    ldr x1, =http_end
    str x1, [x25, #64]
    mov x0, #4
    str x0, [x25, #72]
    
    /* Execute writev (5 iovecs) */
    mov x0, x20             /* fd */
    mov x1, x25             /* iovec ptr */
    mov x2, #5              /* count */
    mov x8, SYS_WRITEV
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
    
    b hc_next_req

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
    
    /* Forward Request */
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
    b hc_close_final

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
    b hc_next_req

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
    b hc_next_req

hc_next_req:
    /* Loop back for Keep-Alive */
    b hc_loop

hc_close_final:
    mov x0, x20
    mov x8, SYS_CLOSE
    svc #0
    
    ldr x23, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret