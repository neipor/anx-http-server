/* src/security/redirect.s - URL Redirect Support */

.include "src/defs.s"

.global redirect_init
.global redirect_add_rule
.global redirect_check

.text

/* redirect_init() - Clear redirect rules */
redirect_init:
    ldr x0, =redirect_count
    str wzr, [x0]
    ret

/* redirect_add_rule(from_str, to_str, code) */
/* x0 = from path, x1 = to path, x2 = status code (301/302) */
redirect_add_rule:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    
    mov x19, x0            /* from */
    mov x20, x1            /* to */
    mov x21, x2            /* code */
    
    /* Get current count */
    ldr x1, =redirect_count
    ldr w22, [x1]
    cmp w22, #16            /* Max 16 rules */
    bge rdr_add_done
    
    /* Calculate entry offset: each entry = 256 + 256 + 4 = 516 bytes */
    /* from[256] | to[256] | code[4] */
    mov x0, #516
    mul x0, x0, x22
    ldr x1, =redirect_rules
    add x1, x1, x0
    
    /* Copy from path */
    mov x0, x1
    mov x1, x19
    bl strcpy
    
    /* Copy to path */
    ldr x0, =redirect_count
    ldr w22, [x0]
    mov x0, #516
    mul x0, x0, x22
    ldr x1, =redirect_rules
    add x1, x1, x0
    add x0, x1, #256        /* to offset */
    mov x1, x20
    bl strcpy
    
    /* Store code */
    ldr x0, =redirect_count
    ldr w22, [x0]
    mov x0, #516
    mul x0, x0, x22
    ldr x1, =redirect_rules
    add x1, x1, x0
    add x1, x1, #512
    str w21, [x1]
    
    /* Increment count */
    ldr x0, =redirect_count
    ldr w1, [x0]
    add w1, w1, #1
    str w1, [x0]
    
rdr_add_done:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

/* redirect_check(req_path) -> 0=no match, 1=matched (result in redirect_result) */
redirect_check:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    
    mov x19, x0            /* req_path */
    
    ldr x0, =redirect_count
    ldr w20, [x0]
    cbz w20, rdr_no_match
    
    mov w21, #0             /* index */
    
rdr_check_loop:
    cmp w21, w20
    bge rdr_no_match
    
    /* Calculate entry offset */
    mov x0, #516
    mul x0, x0, x21
    ldr x1, =redirect_rules
    add x22, x1, x0         /* entry start */
    
    /* Compare from path */
    mov x0, x19
    mov x1, x22
    bl strcmp
    cmp x0, #0
    beq rdr_matched
    
    add w21, w21, #1
    b rdr_check_loop

rdr_matched:
    /* Copy target URL to redirect_result_url */
    ldr x0, =redirect_result_url
    add x1, x22, #256
    bl strcpy
    
    /* Load status code */
    add x0, x22, #512
    ldr w0, [x0]
    ldr x1, =redirect_result_code
    str w0, [x1]
    
    mov x0, #1
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

rdr_no_match:
    mov x0, #0
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

.data
    .align 4
    redirect_count: .word 0
    redirect_result_code: .word 0
    
    .global redirect_count, redirect_result_code, redirect_result_url

.bss
    .align 4
    redirect_rules: .skip 8256      /* 16 rules * 516 bytes */
    redirect_result_url: .skip 256
