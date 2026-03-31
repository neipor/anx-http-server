/* src/access.s - IP Access Control & Rate Limiting */

.include "src/defs.s"

.global check_ip_access
.global add_ip_rule
.global init_access_rules
.global check_rate_limit
.global init_rate_limiter

/* IP access rule structure (12 bytes each):
 *   0-3:  IP address (network byte order)
 *   4-7:  netmask (network byte order, 0xFFFFFFFF = /32)
 *   8-11: action (0 = deny, 1 = allow)
 * Max 64 rules = 768 bytes
 */

.equ RULE_SIZE, 12
.equ RULE_IP_OFF, 0
.equ RULE_MASK_OFF, 4
.equ RULE_ACTION_OFF, 8
.equ MAX_RULES, 64

/* Rate limit bucket structure (16 bytes each):
 *   0-3:   IP address
 *   4-7:   tokens remaining (requests allowed)
 *   8-11:  last_refill_time (unix seconds, lower 32 bits)
 *   12-15: unused
 * Max 256 buckets = 4096 bytes (hash table)
 */

.equ BUCKET_SIZE, 16
.equ BUCKET_IP_OFF, 0
.equ BUCKET_TOKENS_OFF, 4
.equ BUCKET_TIME_OFF, 8
.equ MAX_BUCKETS, 256

.text

/* =========================================================================
 * init_access_rules() - Clear all access rules
 * ========================================================================= */
init_access_rules:
    ldr x0, =access_rule_count
    str wzr, [x0]
    /* Default policy: allow all */
    ldr x0, =default_policy
    mov w1, #1
    str w1, [x0]
    ret

/* =========================================================================
 * add_ip_rule(ip, mask, action) - Add an IP access rule
 * x0 = IP address (network order)
 * x1 = netmask (network order)
 * x2 = action (0=deny, 1=allow)
 * Returns: 0 on success, -1 if full
 * ========================================================================= */
add_ip_rule:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    
    ldr x3, =access_rule_count
    ldr w4, [x3]
    cmp w4, #MAX_RULES
    bge air_full
    
    /* Calculate entry address */
    ldr x5, =access_rules
    mov x6, #RULE_SIZE
    mul x6, x4, x6
    add x5, x5, x6
    
    /* Store rule */
    str w0, [x5, #RULE_IP_OFF]
    str w1, [x5, #RULE_MASK_OFF]
    str w2, [x5, #RULE_ACTION_OFF]
    
    /* Increment count */
    add w4, w4, #1
    str w4, [x3]
    
    mov x0, #0
    ldp x29, x30, [sp], #16
    ret
air_full:
    mov x0, #-1
    ldp x29, x30, [sp], #16
    ret

/* =========================================================================
 * check_ip_access(client_ip) - Check if IP is allowed
 * x0 = client IP (network order, from sockaddr_in)
 * Returns: 1 = allowed, 0 = denied
 * Rules are checked in order; first match wins (like nginx)
 * ========================================================================= */
check_ip_access:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    
    mov x19, x0            /* client IP */
    
    ldr x0, =access_rule_count
    ldr w20, [x0]          /* rule count */
    cbz w20, cia_default   /* No rules -> default policy */
    
    ldr x21, =access_rules
    mov x22, #0             /* index */

cia_loop:
    cmp w22, w20
    bge cia_default
    
    /* Load rule */
    ldr w0, [x21, #RULE_IP_OFF]
    ldr w1, [x21, #RULE_MASK_OFF]
    
    /* Apply mask to both */
    and w2, w19, w1         /* client_ip & mask */
    and w3, w0, w1          /* rule_ip & mask */
    
    cmp w2, w3
    bne cia_next
    
    /* Match! Return action */
    ldr w0, [x21, #RULE_ACTION_OFF]
    b cia_done

cia_next:
    add x21, x21, #RULE_SIZE
    add x22, x22, #1
    b cia_loop

cia_default:
    ldr x0, =default_policy
    ldr w0, [x0]

cia_done:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

/* =========================================================================
 * init_rate_limiter() - Initialize rate limiter
 * ========================================================================= */
init_rate_limiter:
    /* Zero out all buckets */
    ldr x0, =rate_buckets
    mov x1, #BUCKET_SIZE * MAX_BUCKETS
    mov x2, #0
irl_loop:
    cbz x1, irl_done
    strb wzr, [x0], #1
    sub x1, x1, #1
    b irl_loop
irl_done:
    /* Set default rate: 100 requests/second */
    ldr x0, =rate_limit_rps
    mov w1, #100
    str w1, [x0]
    ret

/* =========================================================================
 * check_rate_limit(client_ip) - Token bucket rate limiter
 * x0 = client IP (network order)
 * Returns: 1 = allowed, 0 = rate limited (429)
 * ========================================================================= */
check_rate_limit:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    
    mov x19, x0            /* client IP */
    
    /* Check if rate limiting is enabled */
    ldr x0, =rate_limit_rps
    ldr w0, [x0]
    cbz w0, crl_allow       /* 0 = disabled */
    mov x22, x0            /* x22 = max tokens */
    
    /* Hash IP to bucket index: IP % MAX_BUCKETS */
    and w0, w19, #(MAX_BUCKETS - 1)
    mov x1, #BUCKET_SIZE
    mul x0, x0, x1
    ldr x1, =rate_buckets
    add x20, x1, x0        /* x20 = bucket ptr */
    
    /* Get current time */
    sub sp, sp, #16
    mov x0, #0              /* CLOCK_REALTIME */
    mov x1, sp
    mov x8, #113            /* clock_gettime */
    svc #0
    ldr x21, [sp]          /* x21 = current seconds */
    add sp, sp, #16
    
    /* Check if this bucket belongs to our IP */
    ldr w0, [x20, #BUCKET_IP_OFF]
    cmp w0, w19
    bne crl_new_bucket
    
    /* Same IP - check time and refill */
    ldr w0, [x20, #BUCKET_TIME_OFF]
    cmp w21, w0
    beq crl_check_tokens    /* Same second - just check tokens */
    
    /* New second - refill tokens */
    sub w1, w21, w0         /* seconds elapsed */
    ldr w2, [x20, #BUCKET_TOKENS_OFF]
    
    /* Add tokens: elapsed * rate_limit_rps */
    mul x1, x1, x22
    add w2, w2, w1
    
    /* Cap at max */
    cmp w2, w22
    csel w2, w22, w2, gt
    
    str w2, [x20, #BUCKET_TOKENS_OFF]
    str w21, [x20, #BUCKET_TIME_OFF]
    b crl_check_tokens

crl_new_bucket:
    /* New IP in this bucket - initialize */
    str w19, [x20, #BUCKET_IP_OFF]
    str w22, [x20, #BUCKET_TOKENS_OFF]
    str w21, [x20, #BUCKET_TIME_OFF]

crl_check_tokens:
    ldr w0, [x20, #BUCKET_TOKENS_OFF]
    cbz w0, crl_deny
    
    /* Decrement token */
    sub w0, w0, #1
    str w0, [x20, #BUCKET_TOKENS_OFF]

crl_allow:
    mov x0, #1
    b crl_done

crl_deny:
    mov x0, #0

crl_done:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

/* =========================================================================
 * Data Section
 * ========================================================================= */
.data
    .global access_rule_count, default_policy, rate_limit_rps
    access_rule_count: .word 0
    default_policy:    .word 1     /* 1 = allow by default */
    rate_limit_rps:    .word 0     /* 0 = disabled, >0 = requests/sec */

.bss
    .align 4
    .global access_rules, rate_buckets
    access_rules:  .skip RULE_SIZE * MAX_RULES    /* 768 bytes */
    rate_buckets:  .skip BUCKET_SIZE * MAX_BUCKETS /* 4096 bytes */
