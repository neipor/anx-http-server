/* src/utils.s - String & Math Utilities */

.include "src/defs.s"

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

.text

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
    /* Reuse unrolled copy logic manually for speed */
sct_loop:
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    beq sct_done
    
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    beq sct_done
    
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    beq sct_done
    
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    bne sct_loop
sct_done:
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
    
    /* Found at 4th byte (offset 3 from start of loop iteration) */
sl_end_1:
    sub x0, x1, x0
    sub x0, x0, #1
    ret

/* strcmp(s1, s2) -> 0 if eq */
strcmp:
    mov x4, x0  /* save s1 */
    mov x5, x1  /* save s2 */
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
    
    mov x19, x0     /* haystack */
    mov x20, x1     /* needle */
    
    /* needle len */
    mov x0, x20
    bl strlen
    mov x3, x0      /* x3 = needle len */
    cmp x3, #0
    beq strstr_found_immediate
    
strstr_loop:
    ldrb w4, [x19]
    cmp w4, #0
    beq strstr_not_found
    
    /* Compare x3 bytes */
    mov x5, #0      /* index */
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

/* has_dotdot(str) -> 1 if has "..", 0 if not */
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
    mov x1, x0      /* current ptr */
    mov x2, #0      /* last dot ptr */
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
    mov x1, #0      /* result */
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
.global itoa_hex
itoa_hex:
    mov x2, x1      /* buf */
    mov x3, x0      /* val */
    mov x4, #0      /* len */
    
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
    add x5, x5, #39 /* 'A' - 10 - '0' = 65 - 10 - 48 = 7. Wait. 'a' is 97. */
    /* 'A'(65) for 10. 10+55=65. */
    add x5, x5, #7
ih_digit:
    add x5, x5, #'0'
    strb w5, [x2, x4]
    add x4, x4, #1
    lsr x3, x3, #4
    b ih_loop

ih_rev:
    /* Reuse reverse logic from itoa if possible, but registers differ. Inline it. */
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

/* htons(short) -> short (swap bytes) */
htons:
    rev16 w0, w0
    ret

/* ntohs(short) -> short */
ntohs:
    rev16 w0, w0
    ret

/* set_nonblocking(fd) -> 0 or -1 */
set_nonblocking:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    mov x19, x0     /* fd */
    
    /* Get Flags */
    mov x1, F_GETFL
    mov x2, #0
    mov x8, SYS_FCNTL
    svc #0
    cmp x0, #0
    blt snb_fail
    
    mov x20, x0     /* flags */
    
    /* Add O_NONBLOCK */
    mov x2, O_NONBLOCK
    orr x2, x20, x2
    
    /* Set Flags */
    mov x0, x19
    mov x1, F_SETFL
    /* x2 already set */
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

/* ip_to_str(uint32 ip, char* buf) */
ip_to_str:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    
    mov x19, x0     /* IP */
    mov x20, x1     /* Buf */
    
    /* Byte 0 */
    and w0, w19, #0xFF
    mov x1, x20
    bl itoa
    add x20, x20, x0
    
    mov w2, #'.'
    strb w2, [x20], #1
    
    /* Byte 1 */
    lsr w0, w19, #8
    and w0, w0, #0xFF
    mov x1, x20
    bl itoa
    add x20, x20, x0
    
    mov w2, #'.'
    strb w2, [x20], #1
    
    /* Byte 2 */
    lsr w0, w19, #16
    and w0, w0, #0xFF
    mov x1, x20
    bl itoa
    add x20, x20, x0
    
    mov w2, #'.'
    strb w2, [x20], #1
    
    /* Byte 3 */
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

/* get_time_str(char* buf) */
get_time_str:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    
    mov x19, x1     /* buf */
    
    /* clock_gettime(0, &timespec) */
    mov x0, #0      /* CLOCK_REALTIME */
    ldr x1, =timespec
    mov x8, #113    /* SYS_CLOCK_GETTIME */
    svc #0
    
    ldr x1, =timespec
    ldr x0, [x1]    /* tv_sec */
    
    /* Check Cache */
    ldr x2, =last_log_sec
    ldr x3, [x2]
    cmp x0, x3
    beq gt_done     /* Cache hit, buffer already valid */
    
    str x0, [x2]    /* Update cache key */
    
    /* Calculate HH:MM:SS */
    /* Day seconds = 86400 */
    ldr x2, =86400
    udiv x3, x0, x2
    msub x0, x3, x2, x0 /* x0 = sec % 86400 */
    
    /* Hour = x0 / 3600 */
    mov x2, #3600
    udiv x4, x0, x2     /* x4 = HH */
    msub x0, x4, x2, x0 /* x0 = rem */
    
    /* Min = x0 / 60 */
    mov x2, #60
    udiv x5, x0, x2     /* x5 = MM */
    msub x6, x5, x2, x0 /* x6 = SS */
    
    /* Format into buf "[HH:MM:SS] " */
    mov x20, x19
    
    mov w2, #'['
    strb w2, [x20], #1
    
    /* HH */
    mov x0, x4
    bl append_2digits
    
    mov w2, #':'
    strb w2, [x20], #1
    
    /* MM */
    mov x0, x5
    bl append_2digits
    
    mov w2, #':'
    strb w2, [x20], #1
    
    /* SS */
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
    /* x0 = val, x20 = buf ptr. updates x20 */
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

/* log_request(method_ptr, path_ptr, status_code_int) */
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
    
    mov x19, x0     /* method */
    mov x20, x1     /* path */
    mov x21, x2     /* status code */
    
    ldr x22, =log_buffer /* Current ptr */
    
    /* 1. Time "[HH:MM:SS] " */
    ldr x1, =time_buffer
    bl get_time_str
    
    mov x0, x22
    ldr x1, =time_buffer
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    
    /* 2. Log Prefix (Color) "[ACCESS]" */
    mov x0, x22
    ldr x1, =log_info_prefix
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    
    mov w0, #' '
    strb w0, [x22], #1
    
    /* 3. IP Address */
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
    
    /* 6. Arrow " -> " */
    mov x0, x22
    ldr x1, =txt_arrow
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    
    /* 7. Status Color */
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
    
    /* 8. Status Code */
    mov x0, x21
    mov x1, x22
    bl itoa
    add x22, x22, x0
    
    /* 9. Reset Color */
    mov x0, x22
    ldr x1, =col_reset
    bl strcpy
    mov x0, x22
    bl strlen
    add x22, x22, x0
    
    /* 10. Newline */
    mov w0, #10
    strb w0, [x22], #1
    mov w0, #0
    strb w0, [x22]
    
    /* ATOMIC WRITE */
    mov x0, STDOUT
    ldr x1, =log_buffer
    mov x2, x22
    sub x2, x2, x1  /* len = ptr - start */
    mov x8, SYS_WRITE
    svc #0
    
    ldr x23, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

log_exit:
    ret