/* src/utils.s - String & Math Utilities */

.global strcpy
.global strcat
.global strlen
.global strcmp
.global strstr
.global atoi
.global itoa
.global htons
.global ntohs

.text

/* strcpy(dest, src) */
strcpy:
    mov x2, x0
scp_loop:
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    bne scp_loop
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
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    bne sct_copy
    ret

/* strlen(str) -> len */
strlen:
    mov x1, x0
sl_loop:
    ldrb w2, [x1], #1
    cmp w2, #0
    bne sl_loop
    sub x0, x1, x0
    sub x0, x0, #1
    ret

/* strcmp(s1, s2) -> 0 if eq */
strcmp:
    ldrb w2, [x0], #1
    ldrb w3, [x1], #1
    cmp w2, #0
    beq scmp_done
    cmp w2, w3
    beq strcmp
    sub x0, x2, x3
    ret
scmp_done:
    sub x0, x2, x3
    ret

/* strstr(haystack, needle) -> ptr or NULL */
strstr:
    stp x19, x20, [sp, #-16]!
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
    ldp x19, x20, [sp], #16
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

/* htons(short) -> short (swap bytes) */
htons:
    rev16 w0, w0
    ret

/* ntohs(short) -> short */
ntohs:
    rev16 w0, w0
    ret
