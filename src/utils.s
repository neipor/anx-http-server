/* src/utils.s - String & Math Utilities */

.include "src/defs.s"

.global memcpy
.global strcpy
.global strcat
.global strlen
.global strcmp
.global strstr
.global has_dotdot
.global get_extension
.global atoi
.global itoa
.global htons
.global ntohs
.global log_request
.global ip_to_str
.global get_time_str
.global set_nonblocking
.global copy_value_until_newline
.global inet_aton
.global itoa_hex
.global daemonize

.text

/* memcpy(dest, src, n) - Copy n bytes */
memcpy:
    cmp     x2, #0
    beq     memcpy_done
    mov     x3, #0
memcpy_loop:
    ldrb    w4, [x1, x3]
    strb    w4, [x0, x3]
    add     x3, x3, #1
    cmp     x3, x2
    blt     memcpy_loop
memcpy_done:
    ret

/* strcpy(dest, src) - 4-way unrolled */
strcpy:
    mov x2, x0
scp_loop:
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    beq scp_done
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    beq scp_done
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    beq scp_done
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    bne scp_loop
scp_done:
    ret

/* strcat(dest, src) */
strcat:
    mov x2, x0
sct_find_end:
    ldrb w3, [x2]
    cmp w3, #0
    beq sct_copy
    add x2, x2, #1
    b sct_find_end
sct_copy:
    mov x4, x1
sct_loop:
    ldrb w3, [x4], #1
    strb w3, [x2], #1
    cmp w3, #0
    bne sct_loop
    ret

/* strlen(str) -> len - 4-way unrolled */
strlen:
    mov x1, x0
sl_loop:
    ldrb w2, [x1], #1
    cmp w2, #0
    beq sl_end_1
    ldrb w2, [x1], #1
    cmp w2, #0
    beq sl_end_1
    ldrb w2, [x1], #1
    cmp w2, #0
    beq sl_end_1
    ldrb w2, [x1], #1
    cmp w2, #0
    bne sl_loop
sl_end_1:
    sub x0, x1, x0
    sub x0, x0, #1
    ret

/* strcmp(s1, s2) -> 0 if eq */
strcmp:
    mov x4, x0
    mov x5, x1
scmp_loop:
    ldrb w2, [x4], #1
    ldrb w3, [x5], #1
    cmp w2, #0
    beq scmp_check_end
    cmp w2, w3
    bne scmp_diff
    b scmp_loop
scmp_check_end:
    cmp w3, #0
    beq scmp_eq
scmp_diff:
    sub x0, x2, x3
    ret
scmp_eq:
    mov x0, #0
    ret

/* strstr(haystack, needle) -> ptr or NULL */
strstr:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    mov x20, x1
    mov x0, x20
    bl strlen
    mov x3, x0
    cmp x3, #0
    beq strstr_found_immediate
strstr_loop:
    ldrb w4, [x19]
    cmp w4, #0
    beq strstr_not_found
    mov x5, #0
cmp_loop:
    cmp x5, x3
    beq strstr_found
    ldrb w6, [x19, x5]
    ldrb w7, [x20, x5]
    cmp w6, w7
    bne next_char
    add x5, x5, #1
    b cmp_loop
next_char:
    add x19, x19, #1
    b strstr_loop
strstr_found:
    mov x0, x19
    b strstr_exit
strstr_found_immediate:
    mov x0, x19
    b strstr_exit
strstr_not_found:
    mov x0, #0
strstr_exit:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

/* has_dotdot(str) -> 1 if has ".." */
has_dotdot:
    mov x1, x0
hd_loop:
    ldrb w2, [x1]
    cmp w2, #0
    beq hd_not_found
    cmp w2, #'.'
    bne hd_next
    ldrb w3, [x1, #1]
    cmp w3, #'.'
    beq hd_found
hd_next:
    add x1, x1, #1
    b hd_loop
hd_found:
    mov x0, #1
    ret
hd_not_found:
    mov x0, #0
    ret

/* get_extension(filename) -> ptr to dot or NULL */
get_extension:
    mov x1, x0
    mov x2, #0
ge_loop:
    ldrb w3, [x1]
    cmp w3, #0
    beq ge_done
    cmp w3, #'.'
    beq ge_found_dot
    add x1, x1, #1
    b ge_loop
ge_found_dot:
    mov x2, x1
    add x1, x1, #1
    b ge_loop
ge_done:
    mov x0, x2
    ret

/* atoi(str) -> int */
atoi:
    mov x1, #0
    mov x2, #10
at_loop:
    ldrb w3, [x0], #1
    sub w3, w3, #'0'
    cmp w3, #0
    blt at_done
    cmp w3, #9
    bgt at_done
    mul x1, x1, x2
    add x1, x1, x3
    b at_loop
at_done:
    mov x0, x1
    ret

/* itoa(int, buf) -> len */
itoa:
    mov x2, x1
    mov x3, x0
    mov x4, #0
    mov x5, #10
    cmp x3, #0
    bne itoa_loop_l
    mov w6, #'0'
    strb w6, [x2]
    mov x0, #1
    ret
itoa_loop_l:
    cmp x3, #0
    beq itoa_rev_l
    udiv x6, x3, x5
    msub x7, x6, x5, x3
    add w7, w7, #'0'
    strb w7, [x2, x4]
    add x4, x4, #1
    mov x3, x6
    b itoa_loop_l
itoa_rev_l:
    mov x0, x4
    mov x8, #0
    sub x9, x4, #1
rv_loop_l:
    cmp x8, x9
    bge rv_dn_l
    ldrb w10, [x2, x8]
    ldrb w11, [x2, x9]
    strb w11, [x2, x8]
    strb w10, [x2, x9]
    add x8, x8, #1
    sub x9, x9, #1
    b rv_loop_l
rv_dn_l: ret

/* itoa_hex(uint64 val, char* buf) -> len */
itoa_hex:
    mov x2, x1
    mov x3, x0
    mov x4, #0
    cmp x3, #0
    bne ih_loop
    mov w5, #'0'
    strb w5, [x2]
    mov x0, #1
    ret
ih_loop:
    cmp x3, #0
    beq ih_rev
    and x5, x3, #0xF
    cmp x5, #10
    blt ih_digit
    add x5, x5, #7 /* 10+7+48=65('A') */
ih_digit:
    add x5, x5, #'0'
    strb w5, [x2, x4]
    add x4, x4, #1
    lsr x3, x3, #4
    b ih_loop
ih_rev:
    mov x0, x4
    mov x8, #0
    sub x9, x4, #1
ih_rv_loop:
    cmp x8, x9
    bge ih_done
    ldrb w10, [x2, x8]
    ldrb w11, [x2, x9]
    strb w11, [x2, x8]
    strb w10, [x2, x9]
    add x8, x8, #1
    sub x9, x9, #1
    b ih_rv_loop
ih_done:
    ret

/* inet_ntoa(uint32_t ip_addr_ptr, char* buf) */
.global inet_ntoa
inet_ntoa:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, x1
    mov x21, #0
in_loop:
    cmp x21, #4
    beq in_done
    ldrb w0, [x19, x21]
    mov x1, x20
    bl itoa
    add x20, x20, x0
    cmp x21, #3
    beq in_skip_dot
    mov w2, #'.'
    strb w2, [x20], #1
in_skip_dot:
    add x21, x21, #1
    b in_loop
in_done:
    strb wzr, [x20]
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

/* daemonize() */
daemonize:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x0, SIGCHLD_FLAG
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov x8, SYS_CLONE
    svc #0
    cmp x0, #0
    blt dae_fail
    bgt dae_parent
    mov x8, SYS_SETSID
    svc #0
    mov x0, AT_FDCWD
    adr x1, dev_null
    mov x2, #2
    mov x3, #0
    mov x8, SYS_OPENAT
    svc #0
    cmp x0, #0
    blt dae_done
    mov x19, x0
    mov x0, x19
    mov x1, #0
    mov x2, #0
    mov x8, SYS_DUP3
    svc #0
    mov x0, x19
    mov x1, #1
    mov x2, #0
    mov x8, SYS_DUP3
    svc #0
    mov x0, x19
    mov x1, #2
    mov x2, #0
    mov x8, SYS_DUP3
    svc #0
    cmp x19, #2
    ble dae_done
    mov x0, x19
    mov x8, SYS_CLOSE
    svc #0
dae_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret
dae_parent:
    mov x0, #0
    mov x8, SYS_EXIT
    svc #0
dae_fail:
    mov x0, #-1
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

    .align 4
dev_null: .asciz "/dev/null"
    .align 4

/* inet_aton(char* str) -> uint32_t ip */
inet_aton:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    mov x19, x0
    mov x20, #0
    mov x21, #0
ia_loop:
    cmp x21, #4
    beq ia_done
    mov x0, x19
    bl atoi
    and w0, w0, #0xFF
    lsl w2, w21, #3
    lsl w0, w0, w2
    orr w20, w20, w0
ia_find_dot:
    ldrb w2, [x19]
    cmp w2, #0
    beq ia_check_end
    cmp w2, #'.'
    beq ia_dot_found
    add x19, x19, #1
    b ia_find_dot
ia_dot_found:
    add x19, x19, #1
    add x21, x21, #1
    b ia_loop
ia_check_end:
    add x21, x21, #1
    b ia_loop
ia_done:
    mov w0, w20
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

htons:
    rev16 w0, w0
    ret
ntohs:
    rev16 w0, w0
    ret

set_nonblocking:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    mov x1, F_GETFL
    mov x2, #0
    mov x8, SYS_FCNTL
    svc #0
    cmp x0, #0
    blt snb_fail
    mov x20, x0
    mov x2, O_NONBLOCK
    orr x2, x20, x2
    mov x0, x19
    mov x1, F_SETFL
    mov x8, SYS_FCNTL
    svc #0
    mov x0, #0
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret
snb_fail:
    mov x0, #-1
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

copy_value_until_newline:
    mov x2, x0
    mov x3, x1
cv_loop:
    ldrb w4, [x3], #1
    cmp w4, #0
    beq cv_done
    cmp w4, #10
    beq cv_done
    cmp w4, #13
    beq cv_skip
    strb w4, [x2], #1
    b cv_loop
cv_skip:
    b cv_loop
cv_done:
    strb wzr, [x2]
    ret

/* find_header_value(req_ptr, header_name) -> ptr to value or NULL */
.global find_header_value
find_header_value:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    
    mov x19, x0     /* req */
    mov x20, x1     /* name */
    
    bl strstr
    cmp x0, #0
    beq fhv_not_found
    
    /* Found header name. Now skip it. */
    mov x19, x0
    mov x0, x20
    bl strlen
    add x19, x19, x0
    
    /* Now skip optional space */
fhv_skip_space:
    ldrb w2, [x19]
    cmp w2, #32
    bne fhv_found
    add x19, x19, #1
    b fhv_skip_space

fhv_found:
    mov x0, x19
    b fhv_exit

fhv_not_found:
    mov x0, #0
fhv_exit:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

/* ip_to_str(uint32 ip, char* buf) */
.global ip_to_str
ip_to_str:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0
    mov x20, x1
    and w0, w19, #0xFF
    mov x1, x20
    bl itoa
    add x20, x20, x0
    mov w2, #'.'
    strb w2, [x20], #1
    lsr w0, w19, #8
    and w0, w0, #0xFF
    mov x1, x20
    bl itoa
    add x20, x20, x0
    mov w2, #'.'
    strb w2, [x20], #1
    lsr w0, w19, #16
    and w0, w0, #0xFF
    mov x1, x20
    bl itoa
    add x20, x20, x0
    mov w2, #'.'
    strb w2, [x20], #1
    lsr w0, w19, #24
    and w0, w0, #0xFF
    mov x1, x20
    bl itoa
    add x20, x20, x0
    mov w2, #0
    strb w2, [x20]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

get_time_str:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x1
    mov x0, #0
    ldr x1, =timespec
    mov x8, #113
    svc #0
    ldr x1, =timespec
    ldr x0, [x1]
    ldr x2, =last_log_sec
    ldr x3, [x2]
    cmp x0, x3
    beq gt_done
    str x0, [x2]
    ldr x2, =86400
    udiv x3, x0, x2
    msub x0, x3, x2, x0
    mov x2, #3600
    udiv x4, x0, x2
    msub x0, x4, x2, x0
    mov x2, #60
    udiv x5, x0, x2
    msub x6, x5, x2, x0
    mov x20, x19
    mov w2, #'['
    strb w2, [x20], #1
    mov x0, x4
    bl append_2digits
    mov w2, #':'
    strb w2, [x20], #1
    mov x0, x5
    bl append_2digits
    mov w2, #':'
    strb w2, [x20], #1
    mov x0, x6
    bl append_2digits
    mov w2, #']'
    strb w2, [x20], #1
    mov w2, #' '
    strb w2, [x20], #1
    mov w2, #0
    strb w2, [x20]
gt_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

append_2digits:
    cmp x0, #10
    bge a2d_ok
    mov w2, #'0'
    strb w2, [x20], #1
a2d_ok:
    stp x29, x30, [sp, #-16]!
    mov x1, x20
    bl itoa
    add x20, x20, x0
    ldp x29, x30, [sp], #16
    ret

log_request:
    /* Check Silent Mode */
    ldr x3, =is_silent
    ldr w3, [x3]
    cmp w3, #1
    beq log_exit

    stp x29, x30, [sp, #-64]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    str x23, [sp, #48]
    
    mov x19, x0
    mov x20, x1
    mov x21, x2
    ldr x22, =log_buffer
    
    /* 1. Time */
    ldr x1, =time_buffer
    bl get_time_str
    mov x0, x22
    ldr x1, =time_buffer
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    
    /* 2. Prefix */
    mov x0, x22
    ldr x1, =log_info_prefix
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    mov w0, #' '
    strb w0, [x22], #1
    
    /* 3. IP */
    mov x0, x22
    ldr x1, =client_ip_str
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    mov w0, #' '
    strb w0, [x22], #1
    
    /* 4. Method */
    mov x0, x22
    mov x1, x19
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    mov w0, #' '
    strb w0, [x22], #1
    
    /* 5. Path */
    mov x0, x22
    mov x1, x20
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    
    /* 6. Arrow */
    mov x0, x22
    ldr x1, =txt_arrow
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    
    /* 7. Status */
    mov x0, x21
    cmp x0, #300
    blt l_green
    cmp x0, #400
    blt l_yellow
    b l_red
l_green: ldr x1, =col_green
    b l_col
l_yellow: ldr x1, =col_yellow
    b l_col
l_red: ldr x1, =col_red
l_col:
    mov x0, x22
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    
    /* Status Code */
    mov x0, x21
    mov x1, x22
    bl itoa
    add x22, x22, x0
    
    /* Reset */
    mov x0, x22
    ldr x1, =col_reset
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    
    /* Newline */
    mov w0, #10
    strb w0, [x22], #1
    mov w0, #0
    strb w0, [x22]
    
    /* Write */
    ldr x0, =log_fd
    ldr w0, [x0]
    ldr x1, =log_buffer
    mov x2, x22
    sub x2, x2, x1
    mov x8, SYS_WRITE
    svc #0
    
    ldr x23, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

log_exit:
    ret
