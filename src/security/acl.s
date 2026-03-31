/* src/security/acl.s - Access Control Lists (IP Allow/Deny) */

.include "src/defs.s"

.global acl_check_ip
.global acl_add_allow
.global acl_add_deny
.global acl_init

.text

/* acl_init() - Initialize ACL (clear all rules) */
acl_init:
    ldr x0, =acl_allow_count
    str wzr, [x0]
    ldr x0, =acl_deny_count
    str wzr, [x0]
    ret

/* acl_add_allow(ip_str) - Add IP to allow list */
/* x0 = pointer to IP string (e.g., "192.168.1.0/24" or "10.0.0.1") */
acl_add_allow:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    
    mov x19, x0
    
    /* Parse IP */
    bl inet_aton
    mov x20, x0            /* x20 = parsed IP */
    
    /* Get current count */
    ldr x1, =acl_allow_count
    ldr w2, [x1]
    cmp w2, #32             /* Max 32 rules */
    bge acl_add_allow_done
    
    /* Store IP at allow_list[count] */
    ldr x3, =acl_allow_list
    str w20, [x3, x2, lsl #2]
    
    /* Increment count */
    add w2, w2, #1
    str w2, [x1]
    
acl_add_allow_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

/* acl_add_deny(ip_str) - Add IP to deny list */
acl_add_deny:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    
    mov x19, x0
    
    bl inet_aton
    mov x20, x0
    
    ldr x1, =acl_deny_count
    ldr w2, [x1]
    cmp w2, #32
    bge acl_add_deny_done
    
    ldr x3, =acl_deny_list
    str w20, [x3, x2, lsl #2]
    
    add w2, w2, #1
    str w2, [x1]
    
acl_add_deny_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

/* acl_check_ip(client_ip_str) -> 0=allowed, -1=denied */
/* If deny list is empty and allow list is empty, allow all */
/* If deny list has entries, check if IP is denied */
/* If allow list has entries, check if IP is allowed (deny all others) */
acl_check_ip:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    
    /* Parse client IP */
    bl inet_aton
    mov x19, x0            /* x19 = client IP */
    
    /* Check deny list first */
    ldr x1, =acl_deny_count
    ldr w2, [x1]
    cbz w2, acl_check_allow
    
    /* Check if IP is in deny list */
    ldr x3, =acl_deny_list
    mov x4, #0
acl_deny_loop:
    cmp w4, w2
    bge acl_check_allow
    ldr w5, [x3, x4, lsl #2]
    cmp w19, w5
    beq acl_denied
    add w4, w4, #1
    b acl_deny_loop

acl_check_allow:
    /* Check allow list */
    ldr x1, =acl_allow_count
    ldr w2, [x1]
    cbz w2, acl_allowed     /* No allow list = allow all */
    
    /* Check if IP is in allow list */
    ldr x3, =acl_allow_list
    mov x4, #0
acl_allow_loop:
    cmp w4, w2
    bge acl_denied          /* Not in allow list = denied */
    ldr w5, [x3, x4, lsl #2]
    cmp w19, w5
    beq acl_allowed
    add w4, w4, #1
    b acl_allow_loop

acl_allowed:
    mov x0, #0
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

acl_denied:
    mov x0, #-1
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

.data
    .align 4
    acl_allow_count: .word 0
    acl_deny_count:  .word 0
    
    .global acl_allow_count, acl_deny_count

.bss
    .align 4
    acl_allow_list: .skip 128      /* 32 IPs * 4 bytes */
    acl_deny_list:  .skip 128      /* 32 IPs * 4 bytes */
