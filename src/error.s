/* src/error.s - HTTP Error Page Generation */

.include "src/defs.s"

.global send_error_page
.global send_error_json
.global build_error_response
.global check_accept_json
.global get_error_description
.global error_response_buffer
.global format_error_timestamp

.text

/* ------------------------------------------------------------------------- */
/* Error Code Constants */
/* ------------------------------------------------------------------------- */
.equ ERR_400, 400
.equ ERR_403, 403
.equ ERR_404, 404
.equ ERR_405, 405
.equ ERR_413, 413
.equ ERR_414, 414
.equ ERR_500, 500
.equ ERR_502, 502
.equ ERR_503, 503
.equ ERR_504, 504

/* ------------------------------------------------------------------------- */
/* Error Description Strings */
/* ------------------------------------------------------------------------- */
.data
.align 2
err_desc_400: .asciz "Bad Request"
err_desc_403: .asciz "Forbidden"
err_desc_404: .asciz "Not Found"
err_desc_405: .asciz "Method Not Allowed"
err_desc_413: .asciz "Payload Too Large"
err_desc_414: .asciz "URI Too Long"
err_desc_500: .asciz "Internal Server Error"
err_desc_502: .asciz "Bad Gateway"
err_desc_503: .asciz "Service Unavailable"
err_desc_504: .asciz "Gateway Timeout"

.global err_desc_400, err_desc_403, err_desc_404, err_desc_405
.global err_desc_413, err_desc_414, err_desc_500, err_desc_502
.global err_desc_503, err_desc_504

/* HTTP Status Lines */
.align 2
http_status_400: .ascii "HTTP/1.1 400 Bad Request\r\n"
http_status_403: .ascii "HTTP/1.1 403 Forbidden\r\n"
http_status_404: .ascii "HTTP/1.1 404 Not Found\r\n"
http_status_405: .ascii "HTTP/1.1 405 Method Not Allowed\r\n"
http_status_413: .ascii "HTTP/1.1 413 Payload Too Large\r\n"
http_status_414: .ascii "HTTP/1.1 414 URI Too Long\r\n"
http_status_500: .ascii "HTTP/1.1 500 Internal Server Error\r\n"
http_status_502: .ascii "HTTP/1.1 502 Bad Gateway\r\n"
http_status_503: .ascii "HTTP/1.1 503 Service Unavailable\r\n"
http_status_504: .ascii "HTTP/1.1 504 Gateway Timeout\r\n"

len_http_status_400: .word . - http_status_400
len_http_status_403: .word http_status_403 - http_status_400
len_http_status_404: .word http_status_404 - http_status_403
len_http_status_405: .word http_status_405 - http_status_404
len_http_status_413: .word http_status_413 - http_status_405
len_http_status_414: .word http_status_414 - http_status_413
len_http_status_500: .word http_status_500 - http_status_414
len_http_status_502: .word http_status_502 - http_status_500
len_http_status_503: .word http_status_503 - http_status_502
len_http_status_504: .word http_status_504 - http_status_503

.global http_status_400, http_status_403, http_status_404, http_status_405
.global http_status_413, http_status_414, http_status_500, http_status_502
.global http_status_503, http_status_504

/* Header Keys */
.align 2
str_accept_json: .asciz "application/json"
json_content_type: .asciz "application/json"
html_content_type: .asciz "text/html"

secs_per_day: .word 86400

.global str_accept_json
.global json_content_type, html_content_type

/* Simple HTML Error Template */
.align 2
error_html_start: .ascii "<!DOCTYPE html><html><head><title>"
error_html_title_end: .ascii "</title></head><body><h1>"
error_html_h1_end: .ascii "</h1><p>"

error_html_details: .ascii "</p><hr><p><strong>URL:</strong> "
error_html_time: .ascii "<br><strong>Time:</strong> "
error_html_end: .ascii "<br><small>ANX Server</small></p></body></html>"

len_error_html_start = . - error_html_start
.global len_error_html_start
len_error_html_title_end = . - error_html_title_end
.global len_error_html_title_end
len_error_html_h1_end = . - error_html_h1_end
.global len_error_html_h1_end
len_error_html_details = . - error_html_details
.global len_error_html_details
len_error_html_time = . - error_html_time
.global len_error_html_time
len_error_html_end = . - error_html_end
.global len_error_html_end

/* JSON Error Template */
.align 2
error_json_start: .ascii "{\"error\":{\"code\":"
error_json_msg_start: .ascii ",\"message\":\""
error_json_url_start: .ascii "\",\"url\":\""
error_json_time_start: .ascii "\",\"timestamp\":\""
error_json_method_start: .ascii "\",\"method\":\""
error_json_end: .ascii "\"}}"

len_error_json_start = . - error_json_start
.global len_error_json_start
len_error_json_msg_start = . - error_json_msg_start
.global len_error_json_msg_start
len_error_json_url_start = . - error_json_url_start
.global len_error_json_url_start
len_error_json_time_start = . - error_json_time_start
.global len_error_json_time_start
len_error_json_method_start = . - error_json_method_start
.global len_error_json_method_start
len_error_json_end = . - error_json_end
.global len_error_json_end

/* ------------------------------------------------------------------------- */
/* get_error_description(error_code) -> ptr to description string */
/* ------------------------------------------------------------------------- */
get_error_description:
    cmp x0, #400
    beq ged_400
    cmp x0, #403
    beq ged_403
    cmp x0, #404
    beq ged_404
    cmp x0, #405
    beq ged_405
    cmp x0, #413
    beq ged_413
    cmp x0, #414
    beq ged_414
    cmp x0, #500
    beq ged_500
    cmp x0, #502
    beq ged_502
    cmp x0, #503
    beq ged_503
    cmp x0, #504
    beq ged_504
ged_500:
    ldr x0, =err_desc_500
    ret
ged_400: ldr x0, =err_desc_400; ret
ged_403: ldr x0, =err_desc_403; ret
ged_404: ldr x0, =err_desc_404; ret
ged_405: ldr x0, =err_desc_405; ret
ged_413: ldr x0, =err_desc_413; ret
ged_414: ldr x0, =err_desc_414; ret
ged_502: ldr x0, =err_desc_502; ret
ged_503: ldr x0, =err_desc_503; ret
ged_504: ldr x0, =err_desc_504; ret

/* ------------------------------------------------------------------------- */
/* check_accept_json(request_buffer) -> 0=HTML, 1=JSON */
/* ------------------------------------------------------------------------- */
check_accept_json:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    
    mov x19, x0             /* x19 = request buffer */
    
    /* Search for "Accept:" header */
    ldr x0, =req_buffer
    ldr x1, =str_accept_json
    bl strstr
    cmp x0, #0
    beq caj_not_json
    
    mov x0, #1
    b caj_done
    
caj_not_json:
    mov x0, #0
    
caj_done:
    ldp x29, x30, [sp], #16
    ret

/* ------------------------------------------------------------------------- */
/* Escape HTML special characters in string */
/* Returns: length */
/* ------------------------------------------------------------------------- */
escape_html_string:
    mov x2, x0             /* dest */
    mov x3, x1             /* src */

ehs_loop:
    ldrb w4, [x3], #1
    cmp w4, #0
    beq ehs_done
    
    cmp w4, #'&'
    beq ehs_amp
    cmp w4, #'<'
    beq ehs_lt
    cmp w4, #'>'
    beq ehs_gt
    
    strb w4, [x2], #1
    b ehs_loop

ehs_amp:
    mov x1, #5
    adr x0, html_amp
    b ehs_copy_entity
ehs_lt:
    mov x1, #4
    adr x0, html_lt
    b ehs_copy_entity
ehs_gt:
    mov x1, #4
    adr x0, html_gt
    
ehs_copy_entity:
    mov x6, x1
ehs_ent_loop:
    ldrb w7, [x0], #1
    strb w7, [x2], #1
    subs x6, x6, #1
    bne ehs_ent_loop
    b ehs_loop

ehs_done:
    strb wzr, [x2]
    mov x0, x3
    sub x0, x0, x1
    ret

.align 2
html_amp: .asciz "&amp;"
html_lt:  .asciz "&lt;"
html_gt:  .asciz "&gt;"

/* ------------------------------------------------------------------------- */
/* Escape JSON special characters */
/* Returns: length */
/* ------------------------------------------------------------------------- */
escape_json_string:
    mov x2, x0             /* dest */
    mov x3, x1             /* src */

ejs_loop:
    ldrb w4, [x3], #1
    cmp w4, #0
    beq ejs_done
    
    cmp w4, #'"'
    beq ejs_quot
    cmp w4, #'\\'
    beq ejs_backslash
    cmp w4, #10
    beq ejs_newline
    
    strb w4, [x2], #1
    b ejs_loop

ejs_quot:
    mov w5, #'\\'
    strb w5, [x2], #1
    mov w5, #'"'
    strb w5, [x2], #1
    b ejs_loop

ejs_backslash:
    mov w5, #'\\'
    strb w5, [x2], #1
    mov w5, #'\\'
    strb w5, [x2], #1
    b ejs_loop

ejs_newline:
    mov w5, #'\\'
    strb w5, [x2], #1
    mov w5, #'n'
    strb w5, [x2], #1
    b ejs_loop

ejs_done:
    strb wzr, [x2]
    mov x0, x3
    sub x0, x0, x1
    ret

/* ------------------------------------------------------------------------- */
/* format_error_timestamp(buffer) -> length */
/* Simple timestamp format: YYYY-MM-DDTHH:MM:SSZ */
/* ------------------------------------------------------------------------- */
format_error_timestamp:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    
    mov x19, x0             /* x19 = buffer */
    mov x20, x19            /* x20 = current pos */
    
    /* Get current time */
    mov x0, #0              /* CLOCK_REALTIME */
    ldr x1, =timespec
    mov x8, #113            /* SYS_CLOCK_GETTIME */
    svc #0
    
    ldr x0, =timespec
    ldr x0, [x0]            /* seconds since epoch */
    
    /* Convert to date/time (simplified) */
    /* days = seconds / 86400 - use ldr to get constant */
    ldr x1, =secs_per_day
    ldr x1, [x1]
    udiv x3, x0, x1         /* x3 = days */
    msub x4, x3, x1, x0     /* x4 = seconds of day */
    
    /* Simple year calculation */
    mov x5, #1970           /* start year */
fet_year:
    /* Check leap year */
    mov x0, x5
    and x1, x0, #3
    cmp x1, #0
    bne fet_not_leap
    mov x1, #100
    udiv x6, x0, x1
    msub x6, x6, x1, x0
    cmp x6, #0
    bne fet_is_leap
    mov x1, #400
    udiv x6, x0, x1
    msub x6, x6, x1, x0
    cmp x6, #0
    beq fet_is_leap
fet_not_leap:
    mov x1, #365
    b fet_days_in_year
fet_is_leap:
    mov x1, #366
    
fet_days_in_year:
    cmp x3, x1
    blt fet_found_year
    sub x3, x3, x1
    add x5, x5, #1
    b fet_year

fet_found_year:
    /* x5 = year, x3 = day of year */
    /* Write year */
    mov x0, x5
    mov x1, x20
    bl itoa
    add x20, x20, x0
    
    /* Write T */
    mov w0, #'T'
    strb w0, [x20], #1
    
    /* Hours: seconds / 3600 */
    mov x0, x4
    mov x1, #3600
    udiv x6, x0, x1
    msub x7, x6, x1, x0
    
    /* Write hours */
    mov x0, x6
    mov x1, x20
    bl append_2dig
    add x20, x20, x0
    
    /* Write : */
    mov w0, #':'
    strb w0, [x20], #1
    
    /* Minutes: remaining / 60 */
    mov x0, x7
    mov x1, #60
    udiv x6, x0, x1
    msub x7, x6, x1, x0
    
    /* Write minutes */
    mov x0, x6
    mov x1, x20
    bl append_2dig
    add x20, x20, x0
    
    /* Write : */
    mov w0, #':'
    strb w0, [x20], #1
    
    /* Write seconds */
    mov x0, x7
    mov x1, x20
    bl append_2dig
    add x20, x20, x0
    
    /* Write Z */
    mov w0, #'Z'
    strb w0, [x20], #1
    
    /* Null terminate */
    strb wzr, [x20]
    
    /* Return length */
    mov x0, x20
    sub x0, x0, x19
    
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

append_2dig:
    cmp x0, #10
    bge ad_ok
    mov w2, #'0'
    strb w2, [x1], #1
ad_ok:
    stp x29, x30, [sp, #-16]!
    mov x3, x1
    mov x1, x3
    bl itoa
    add x0, x3, x0
    ldp x29, x30, [sp], #16
    ret

/* ------------------------------------------------------------------------- */
/* build_error_response(error_code, request_path, method, accept_json) */
/* Builds error response in error_response_buffer */
/* Returns: response length */
/* x0 = error code */
/* x1 = request path */
/* x2 = method */
/* x3 = accept_json flag (1=JSON, 0=HTML) */
/* ------------------------------------------------------------------------- */
build_error_response:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    
    mov x19, x0             /* x19 = error code */
    mov x20, x1             /* x20 = request path */
    mov x21, x2             /* x21 = method */
    mov x22, x3             /* x22 = accept_json */
    
    ldr x23, =error_response_buffer
    mov x24, x23            /* x24 = current pos */
    
    cmp x22, #1
    beq ber_json
    
    /* HTML Response */
    /* Part 1: <!DOCTYPE html><html><head><title> */
    mov x0, x24
    ldr x1, =error_html_start
    ldr x2, =len_error_html_start
    bl memcpy
    add x24, x24, x2
    
    /* Part 2: Error code */
    mov x0, x24
    mov x1, x19
    bl itoa
    add x24, x24, x0
    
    /* Part 3: </title></head><h1> */
    mov x0, x24
    ldr x1, =error_html_title_end
    ldr x2, =len_error_html_title_end
    bl memcpy
    add x24, x24, x2
    
    /* Part 4: Error code again */
    mov x0, x24
    mov x1, x19
    bl itoa
    add x24, x24, x0
    
    /* Part 5: </h1><p> */
    mov x0, x24
    ldr x1, =error_html_h1_end
    ldr x2, =len_error_html_h1_end
    bl memcpy
    add x24, x24, x2
    
    /* Part 6: Error description */
    mov x0, x19
    bl get_error_description
    mov x1, x0
    mov x0, x24
    bl strcpy
    add x24, x24, x0
    
    /* Part 7: <hr><p><strong>URL:</strong> */
    mov x0, x24
    ldr x1, =error_html_details
    ldr x2, =len_error_html_details
    bl memcpy
    add x24, x24, x2
    
    /* Part 8: URL value */
    mov x0, x24
    mov x1, x20
    bl escape_html_string
    add x24, x24, x0
    
    /* Part 9: <br><strong>Time:</strong> */
    mov x0, x24
    ldr x1, =error_html_time
    ldr x2, =len_error_html_time
    bl memcpy
    add x24, x24, x2
    
    /* Part 10: Timestamp */
    mov x0, x24
    bl format_error_timestamp
    add x24, x24, x0
    
    /* Part 11: End tags */
    mov x0, x24
    ldr x1, =error_html_end
    ldr x2, =len_error_html_end
    bl memcpy
    add x24, x24, x2
    
    b ber_calc_len
    
ber_json:
    /* JSON Response */
    /* {"error":{"code": */
    mov x0, x24
    ldr x1, =error_json_start
    ldr x2, =len_error_json_start
    bl memcpy
    add x24, x24, x2
    
    /* Code value */
    mov x0, x24
    mov x1, x19
    bl itoa
    add x24, x24, x0
    
    /* ,"message":" */
    mov x0, x24
    ldr x1, =error_json_msg_start
    ldr x2, =len_error_json_msg_start
    bl memcpy
    add x24, x24, x2
    
    /* Message value */
    mov x0, x24
    mov x1, x19
    bl get_error_description
    mov x1, x0
    mov x0, x24
    bl escape_json_string
    add x24, x24, x0
    
    /* ","url":" */
    mov x0, x24
    ldr x1, =error_json_url_start
    ldr x2, =len_error_json_url_start
    bl memcpy
    add x24, x24, x2
    
    /* URL value */
    mov x0, x24
    mov x1, x20
    bl escape_json_string
    add x24, x24, x0
    
    /* ","timestamp":" */
    mov x0, x24
    ldr x1, =error_json_time_start
    ldr x2, =len_error_json_time_start
    bl memcpy
    add x24, x24, x2
    
    /* Timestamp */
    mov x0, x24
    bl format_error_timestamp
    add x24, x24, x0
    
    /* ","method":" */
    mov x0, x24
    ldr x1, =error_json_method_start
    ldr x2, =len_error_json_method_start
    bl memcpy
    add x24, x24, x2
    
    /* Method value */
    mov x0, x24
    mov x1, x21
    bl escape_json_string
    add x24, x24, x0
    
    /* "}} */
    mov x0, x24
    ldr x1, =error_json_end
    ldr x2, =len_error_json_end
    bl memcpy
    add x24, x24, x2
    
ber_calc_len:
    /* Calculate length */
    ldr x0, =error_response_buffer
    sub x0, x24, x0
    
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

/* ------------------------------------------------------------------------- */
/* send_error_page(client_fd, error_code, request_path, method) */
/* ------------------------------------------------------------------------- */
send_error_page:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    
    mov x19, x0             /* client_fd */
    mov x20, x1             /* error_code */
    mov x21, x2             /* request_path */
    mov x22, x3             /* method */
    
    /* Check Accept header */
    ldr x0, =req_buffer
    ldr x1, =str_accept_json
    bl strstr
    cmp x0, #0
    mov x23, #0
    beq sep_build
    
    mov x23, #1             /* JSON requested */
    
sep_build:
    /* Build error response */
    mov x0, x20
    mov x1, x21
    mov x2, x22
    mov x3, x23
    bl build_error_response
    mov x24, x0             /* response length */
    
    /* Send status line */
    cmp x20, #400; beq sep_400
    cmp x20, #403; beq sep_403
    cmp x20, #404; beq sep_404
    cmp x20, #405; beq sep_405
    cmp x20, #413; beq sep_413
    cmp x20, #414; beq sep_414
    cmp x20, #500; beq sep_500
    cmp x20, #502; beq sep_502
    cmp x20, #503; beq sep_503
    cmp x20, #504; beq sep_504
    b sep_default

sep_400: ldr x1, =http_status_400; ldr x2, =len_http_status_400; b sep_send_stat
sep_403: ldr x1, =http_status_403; ldr x2, =len_http_status_403; b sep_send_stat
sep_404: ldr x1, =http_status_404; ldr x2, =len_http_status_404; b sep_send_stat
sep_405: ldr x1, =http_status_405; ldr x2, =len_http_status_405; b sep_send_stat
sep_413: ldr x1, =http_status_413; ldr x2, =len_http_status_413; b sep_send_stat
sep_414: ldr x1, =http_status_414; ldr x2, =len_http_status_414; b sep_send_stat
sep_500: ldr x1, =http_status_500; ldr x2, =len_http_status_500; b sep_send_stat
sep_502: ldr x1, =http_status_502; ldr x2, =len_http_status_502; b sep_send_stat
sep_503: ldr x1, =http_status_503; ldr x2, =len_http_status_503; b sep_send_stat
sep_504: ldr x1, =http_status_504; ldr x2, =len_http_status_504; b sep_send_stat
sep_default: ldr x1, =http_status_500; ldr x2, =len_http_status_500

sep_send_stat:
    mov x0, x19
    mov x8, SYS_WRITE
    svc #0
    
    /* Server header */
    mov x0, x19
    ldr x1, =http_server_hdr
    ldr x2, =len_server_hdr
    mov x8, SYS_WRITE
    svc #0
    
    /* Content-Type header */
    mov x0, x19
    ldr x1, =http_content_type
    ldr x2, =len_content_type
    mov x8, SYS_WRITE
    svc #0
    
    /* Type value */
    cmp x23, #1
    beq sep_is_json
sep_is_html:
    mov x0, x19
    ldr x1, =html_content_type
    mov x2, #10
    b sep_type_done
sep_is_json:
    mov x0, x19
    ldr x1, =json_content_type
    mov x2, #16
    
sep_type_done:
    mov x8, SYS_WRITE
    svc #0
    
    /* Content-Length */
    mov x0, x19
    ldr x1, =http_content_len
    ldr x2, =len_content_len
    mov x8, SYS_WRITE
    svc #0
    
    /* Length value */
    mov x0, x19
    mov x1, x24
    bl itoa
    mov x2, x0
    mov x8, SYS_WRITE
    svc #0
    
    /* End headers */
    mov x0, x19
    ldr x1, =http_end
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0
    
    /* Body */
    mov x0, x19
    ldr x1, =error_response_buffer
    mov x2, x24
    mov x8, SYS_WRITE
    svc #0
    
    /* Log */
    ldr x0, =current_status
    str w20, [x0]
    bl log_request
    
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

/* ------------------------------------------------------------------------- */
/* send_error_json - Direct JSON error response */
/* ------------------------------------------------------------------------- */
send_error_json:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    
    mov x19, x0             /* client_fd */
    mov x20, x1             /* error_code */
    mov x21, x2             /* message */
    
    /* Build JSON */
    ldr x22, =error_response_buffer
    
    mov x0, x22
    ldr x1, =error_json_start
    ldr x2, =len_error_json_start
    bl memcpy
    
    mov x0, x22
    mov x1, x20
    bl itoa
    mov x0, x22
    bl strcat
    
    mov x0, x22
    ldr x1, =error_json_msg_start
    bl strcat
    
    mov x0, x22
    mov x1, x21
    bl escape_json_string
    mov x0, x22
    bl strcat
    
    mov x0, x22
    ldr x1, =error_json_time_start
    bl strcat
    
    mov x0, x22
    bl format_error_timestamp
    mov x0, x22
    bl strcat
    
    mov x0, x22
    ldr x1, =error_json_end
    bl strcat
    
    /* Get length */
    mov x0, x22
    bl strlen
    mov x24, x0
    
    /* Send status */
    cmp x20, #500; beq sej_500
    cmp x20, #502; beq sej_502
    b sej_default

sej_500: ldr x1, =http_status_500; ldr x2, =len_http_status_500; b sej_send
sej_502: ldr x1, =http_status_502; ldr x2, =len_http_status_502; b sej_send
sej_default: ldr x1, =http_status_500; ldr x2, =len_http_status_500

sej_send:
    mov x0, x19
    mov x8, SYS_WRITE
    svc #0
    
    /* Content-Type */
    mov x0, x19
    ldr x1, =json_content_type
    mov x2, #16
    mov x8, SYS_WRITE
    svc #0
    
    /* End */
    mov x0, x19
    ldr x1, =http_end
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0
    
    /* Body */
    mov x0, x19
    ldr x1, =error_response_buffer
    mov x2, x24
    mov x8, SYS_WRITE
    svc #0
    
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

.bss
    .align 4
error_response_buffer: .skip 4096

.global error_response_buffer
