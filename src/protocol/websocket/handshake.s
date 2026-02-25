/* src/protocol/websocket/handshake.s - WebSocket Handshake Handler (RFC 6455) */

.include "src/defs.s"
.include "src/core/types.s"

.global ws_validate_handshake
.global ws_generate_accept_key
.global ws_handle_upgrade
.global ws_extract_key

/* SHA-1 context size */
.equ SHA1_CTX_SIZE, 96

/* WebSocket Magic String */
.data
.align 3
ws_magic_string: .asciz "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
ws_magic_len = . - ws_magic_string - 1

/* Required headers for WebSocket upgrade */
ws_header_upgrade:     .asciz "Upgrade: websocket"
ws_header_connection:  .asciz "Connection: Upgrade"
ws_header_ws_key:      .asciz "Sec-WebSocket-Key:"
ws_header_ws_version:  .asciz "Sec-WebSocket-Version: 13"

/* Response template */
ws_response_template:  .ascii "HTTP/1.1 101 Switching Protocols\r\n"
                       .ascii "Upgrade: websocket\r\n"
                       .ascii "Connection: Upgrade\r\n"
                       .ascii "Sec-WebSocket-Accept: "
ws_response_template_len = . - ws_response_template

.text

/* ========================================================================
 * WebSocket Handshake Validation
 * ======================================================================== */

/*
 * ws_validate_handshake(request) - Validate WebSocket upgrade request
 * x0 = HTTP request buffer
 * Returns: x0 = 0 on success, error code on failure
 */
ws_validate_handshake:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* request buffer */
    
    /* Check Upgrade: websocket header */
    mov     x0, x19
    ldr     x1, =ws_header_upgrade
    bl      strstr
    cmp     x0, #0
    beq     ws_validate_fail
    
    /* Check Connection: Upgrade header */
    mov     x0, x19
    ldr     x1, =ws_header_connection
    bl      strstr
    cmp     x0, #0
    beq     ws_validate_fail
    
    /* Check Sec-WebSocket-Key header */
    mov     x0, x19
    ldr     x1, =ws_header_ws_key
    bl      strstr
    cmp     x0, #0
    beq     ws_validate_fail
    
    /* Check Sec-WebSocket-Version: 13 */
    mov     x0, x19
    ldr     x1, =ws_header_ws_version
    bl      strstr
    cmp     x0, #0
    beq     ws_validate_fail
    
    mov     x0, #0                  /* Success */
    b       ws_validate_done

ws_validate_fail:
    mov     x0, #ERR_INVALID

ws_validate_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * Extract WebSocket Key
 * ======================================================================== */

/*
 * ws_extract_key(request, key_buffer) - Extract Sec-WebSocket-Key value
 * x0 = HTTP request buffer
 * x1 = output buffer (at least 25 bytes for 24-char key + null)
 * Returns: x0 = key length on success, 0 on failure
 */
ws_extract_key:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* request */
    mov     x20, x1                 /* key buffer */
    
    /* Find "Sec-WebSocket-Key:" */
    ldr     x1, =ws_header_ws_key
    bl      strstr
    cmp     x0, #0
    beq     ws_extract_fail
    
    /* Skip past the header name */
    add     x0, x0, #18             /* strlen("Sec-WebSocket-Key:") */
    
    /* Skip whitespace */
1:
    ldrb    w1, [x0]
    cmp     w1, #' '
    beq     2f
    cmp     w1, #'\t'
    bne     3f
2:
    add     x0, x0, #1
    b       1b

3:
    /* Copy the key (24 base64 chars) */
    mov     x21, #0                 /* count */
    mov     x22, x20                /* output pointer */

ws_extract_copy:
    ldrb    w1, [x0, x21]
    
    /* Check for end of key (whitespace or CR/LF) */
    cmp     w1, #' '
    beq     ws_extract_done
    cmp     w1, #'\t'
    beq     ws_extract_done
    cmp     w1, #'\r'
    beq     ws_extract_done
    cmp     w1, #'\n'
    beq     ws_extract_done
    cmp     w1, #0
    beq     ws_extract_done
    
    /* Store character */
    strb    w1, [x22], #1
    add     x21, x21, #1
    
    /* Max key length is 24 */
    cmp     x21, #24
    ble     ws_extract_copy

ws_extract_done:
    /* Null terminate */
    strb    wzr, [x22]
    
    /* Validate key length (should be 24) */
    cmp     x21, #24
    bne     ws_extract_fail
    
    mov     x0, x21
    b       ws_extract_return

ws_extract_fail:
    mov     x0, #0

ws_extract_return:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* ========================================================================
 * Generate Accept Key
 * ======================================================================== */

/*
 * ws_generate_accept_key(client_key, output) - Generate accept key per RFC 6455
 * x0 = client key (24 bytes, null-terminated)
 * x1 = output buffer (29 bytes for 28-char base64 + null)
 * Returns: x0 = output length (28) on success, error code on failure
 * 
 * accept-key = BASE64(SHA1(client_key + magic_string))
 */
ws_generate_accept_key:
    stp     x29, x30, [sp, #-256]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    
    mov     x19, x0                 /* client key */
    mov     x20, x1                 /* output buffer */
    
    /* Get client key length */
    mov     x0, x19
    bl      strlen
    cmp     x0, #24
    bne     ws_key_fail
    mov     x21, x0                 /* key_len */
    
    /* Allocate SHA1 context on stack */
    add     x22, sp, #64            /* SHA1 ctx */
    
    /* Initialize SHA1 */
    mov     x0, x22
    bl      sha1_init
    
    /* Update with client key */
    mov     x0, x22
    mov     x1, x19
    mov     x2, x21
    bl      sha1_update
    
    /* Update with magic string */
    mov     x0, x22
    ldr     x1, =ws_magic_string
    mov     x2, ws_magic_len
    bl      sha1_update
    
    /* Finalize - get 20-byte SHA1 hash */
    add     x23, sp, #160           /* hash buffer (20 bytes) */
    mov     x0, x22
    mov     x1, x23
    bl      sha1_final
    
    /* Base64 encode the hash */
    mov     x0, x23                 /* src = hash */
    mov     x1, #20                 /* srclen = 20 */
    mov     x2, x20                 /* dst = output buffer */
    add     x3, sp, #180            /* dstlen pointer */
    mov     x24, #29                /* max output: 28 + null */
    str     x24, [x3]
    bl      base64_encode
    cmp     x0, #0
    bne     ws_key_fail
    
    /* Get actual output length */
    ldr     x0, [sp, #180]
    /* Should be 28 (no padding for 20 bytes -> 28 base64 chars) */
    cmp     x0, #28
    bne     ws_key_fail
    
    /* Add null terminator */
    strb    wzr, [x20, #28]
    
    mov     x0, #28                 /* Return length */
    b       ws_key_done

ws_key_fail:
    mov     x0, #ERR_INVALID

ws_key_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #256
    ret

/* ========================================================================
 * Handle WebSocket Upgrade
 * ======================================================================== */

/*
 * ws_handle_upgrade(client_fd, request, response) - Handle WebSocket upgrade
 * x0 = client file descriptor
 * x1 = HTTP request buffer
 * x2 = response buffer (must be >= 512 bytes)
 * Returns: x0 = response length on success, error code on failure
 */
ws_handle_upgrade:
    stp     x29, x30, [sp, #-496]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    
    mov     x19, x0                 /* client_fd */
    mov     x20, x1                 /* request */
    mov     x21, x2                 /* response buffer */
    
    /* Validate handshake request */
    mov     x0, x20
    bl      ws_validate_handshake
    cmp     x0, #0
    bne     ws_upgrade_fail
    
    /* Extract client key */
    add     x22, sp, #64            /* key buffer (32 bytes) */
    mov     x0, x20
    mov     x1, x22
    bl      ws_extract_key
    cmp     x0, #24
    bne     ws_upgrade_fail
    
    /* Generate accept key */
    add     x23, sp, #96            /* accept key buffer (32 bytes) */
    mov     x0, x22
    mov     x1, x23
    bl      ws_generate_accept_key
    cmp     x0, #28
    bne     ws_upgrade_fail
    mov     x24, x0                 /* Save accept key length */
    
    /* Build response */
    /* Copy template */
    mov     x0, x21
    ldr     x1, =ws_response_template
    mov     x2, ws_response_template_len
    bl      memcpy
    
    /* Append accept key */
    add     x0, x21, ws_response_template_len
    mov     x1, x23
    mov     x2, x24
    bl      memcpy
    
    /* Calculate total length so far */
    mov     x0, ws_response_template_len
    add     x0, x0, x24             /* + accept key */
    
    /* Append final CRLF */
    add     x1, x21, x0
    mov     w2, #0x0D
    strb    w2, [x1], #1
    mov     w2, #0x0A
    strb    w2, [x1], #1
    add     x0, x0, #2
    
    /* Null terminate (for debugging) */
    strb    wzr, [x1]
    
    b       ws_upgrade_done

ws_upgrade_fail:
    mov     x0, #ERR_INVALID

ws_upgrade_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #496
    ret

/* External functions */
.global sha1_init
.global sha1_update
.global sha1_final
.global base64_encode
.global memcpy
.global strlen
.global strstr

