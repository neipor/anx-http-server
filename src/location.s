/* src/location.s - Location-based Request Routing */
/* Matches request paths to location blocks from config */

.include "src/defs.s"

.global match_location
.global add_location
.global init_locations

/* Location table entry structure (352 bytes each):
 *   0-63:    path prefix (null-terminated string, max 63 chars)
 *   64-319:  root override (null-terminated, max 255 chars)  
 *   320-323: proxy_ip (0 = no proxy)
 *   324-325: proxy_port (network byte order)
 *   326:     match_type (0=prefix, 1=exact)
 *   327:     flags (bit 0: deny all, bit 1: allow gzip)
 *   328-351: reserved
 * Max 16 locations = 5632 bytes
 */

.equ LOC_ENTRY_SIZE, 352
.equ LOC_PATH_OFF, 0
.equ LOC_ROOT_OFF, 64
.equ LOC_PROXY_IP_OFF, 320
.equ LOC_PROXY_PORT_OFF, 324
.equ LOC_MATCH_TYPE_OFF, 326
.equ LOC_FLAGS_OFF, 327
.equ LOC_MAX_ENTRIES, 16

.text

/* =========================================================================
 * init_locations() - Initialize location table
 * ========================================================================= */
init_locations:
    ldr x0, =location_count
    str wzr, [x0]
    ret

/* =========================================================================
 * add_location(path, root, proxy_ip, proxy_port, match_type)
 * x0 = path string, x1 = root string (or NULL)
 * x2 = proxy_ip (0 = none), x3 = proxy_port, x4 = match_type
 * Returns: 0 on success, -1 if table full
 * ========================================================================= */
add_location:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    
    mov x19, x0            /* path */
    mov x20, x1            /* root */
    mov x21, x2            /* proxy_ip */
    mov x22, x3            /* proxy_port */
    mov x23, x4            /* match_type */
    
    /* Check if table is full */
    ldr x0, =location_count
    ldr w24, [x0]
    cmp w24, #LOC_MAX_ENTRIES
    bge al_full
    
    /* Calculate entry address: loc_table + index * LOC_ENTRY_SIZE */
    ldr x0, =location_table
    mov x1, #LOC_ENTRY_SIZE
    mul x1, x24, x1
    add x0, x0, x1         /* x0 = entry base */
    mov x24, x0            /* x24 = entry base */
    
    /* Copy path */
    mov x1, x19
    bl strcpy
    
    /* Copy root if provided */
    cbz x20, al_no_root
    add x0, x24, #LOC_ROOT_OFF
    mov x1, x20
    bl strcpy
    b al_set_proxy
al_no_root:
    add x0, x24, #LOC_ROOT_OFF
    strb wzr, [x0]
    
al_set_proxy:
    /* Set proxy */
    str w21, [x24, #LOC_PROXY_IP_OFF]
    strh w22, [x24, #LOC_PROXY_PORT_OFF]
    
    /* Set match type */
    strb w23, [x24, #LOC_MATCH_TYPE_OFF]
    
    /* Clear flags */
    strb wzr, [x24, #LOC_FLAGS_OFF]
    
    /* Increment count */
    ldr x0, =location_count
    ldr w1, [x0]
    add w1, w1, #1
    str w1, [x0]
    
    mov x0, #0
    b al_done

al_full:
    mov x0, #-1

al_done:
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

/* =========================================================================
 * match_location(req_path) - Find best matching location
 * x0 = request path (null-terminated)
 * Returns: pointer to location entry, or 0 if no match
 * Uses longest prefix match (like nginx)
 * ========================================================================= */
match_location:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    
    mov x19, x0            /* x19 = req_path */
    mov x20, #0             /* x20 = best match ptr (0 = none) */
    mov x21, #0             /* x21 = best match length */
    
    ldr x0, =location_count
    ldr w22, [x0]          /* x22 = count */
    cbz w22, ml_done
    
    ldr x23, =location_table /* x23 = current entry */
    mov x24, #0             /* x24 = index */

ml_loop:
    cmp w24, w22
    bge ml_done
    
    /* Get match type */
    ldrb w0, [x23, #LOC_MATCH_TYPE_OFF]
    
    /* Get location path */
    mov x25, x23           /* entry ptr */
    
    /* Check if request path starts with location path */
    mov x0, x19            /* req_path */
    mov x1, x23            /* location path (at offset 0) */
    bl ml_prefix_match     /* returns match length or 0 */
    
    cbz x0, ml_next
    
    /* Check if exact match required */
    ldrb w1, [x25, #LOC_MATCH_TYPE_OFF]
    cbnz w1, ml_check_exact
    
    /* Prefix match - check if longer than current best */
    cmp x0, x21
    ble ml_next
    mov x20, x25           /* new best match */
    mov x21, x0            /* new best length */
    b ml_next

ml_check_exact:
    /* Exact match - req_path must end here or have nothing after */
    ldrb w1, [x19, x0]
    cbz w1, ml_exact_hit   /* Exact match */
    cmp w1, #'?'            /* Query string is ok */
    beq ml_exact_hit
    b ml_next

ml_exact_hit:
    mov x20, x25
    mov x21, x0
    b ml_done              /* Exact match wins immediately */

ml_next:
    add x23, x23, #LOC_ENTRY_SIZE
    add x24, x24, #1
    b ml_loop

ml_done:
    mov x0, x20            /* Return best match or 0 */
    
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #80
    ret

/* ml_prefix_match(str, prefix) - Check if str starts with prefix
 * x0 = string, x1 = prefix
 * Returns: length of matched prefix, or 0 if no match */
ml_prefix_match:
    mov x2, #0
ml_pm_loop:
    ldrb w3, [x1, x2]     /* prefix char */
    cbz w3, ml_pm_done    /* End of prefix = match */
    ldrb w4, [x0, x2]     /* string char */
    cbz w4, ml_pm_fail    /* String ended before prefix */
    cmp w3, w4
    bne ml_pm_fail
    add x2, x2, #1
    b ml_pm_loop
ml_pm_done:
    mov x0, x2
    ret
ml_pm_fail:
    mov x0, #0
    ret

/* =========================================================================
 * Data Section
 * ========================================================================= */
.data
    .global location_count
    location_count: .word 0

.bss
    .align 4
    .global location_table
    location_table: .skip LOC_ENTRY_SIZE * LOC_MAX_ENTRIES  /* 5632 bytes */
