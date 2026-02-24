/* src/protocol/websocket/handshake.s - WebSocket Handshake Handler */

.include "src/defs.s"
.include "src/core/types.s"

.global ws_validate_handshake
.global ws_generate_accept_key
.global ws_handle_upgrade

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
ws_response_accept:    .ascii "HTTP/1.1 101 Switching Protocols\r\n"
                       .ascii "Upgrade: websocket\r\n"
                       .ascii "Connection: Upgrade\r\n"
                       .ascii "Sec-WebSocket-Accept: "
ws_response_accept_len = . - ws_response_accept

.text

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

/*
 * ws_generate_accept_key(client_key, key_len, output) - Generate accept key
 * x0 = client key (base64 encoded, 24 bytes)
 * x1 = key length (should be 24)
 * x2 = output buffer (min 29 bytes for base64 SHA1)
 * Returns: x0 = output length on success, error code on failure
 */
ws_generate_accept_key:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    str     x23, [sp, #48]
    
    mov     x19, x0                 /* client key */
    mov     x20, x1                 /* key length */
    mov     x21, x2                 /* output buffer */
    
    /* Validate key length (should be 24 for base64 of 16 bytes) */
    cmp     x20, #24
    bne     ws_key_fail
    
    /* Concatenate: client_key + magic_string */
    /* For now, this is a simplified version */
    /* Real implementation needs SHA1 and base64 */
    
    /* Copy client key to buffer */
    mov     x0, x21
    mov     x1, x19
    mov     x2, x20
    bl      memcpy
    
    /* This is a placeholder - real implementation needs SHA1 */
    /* For testing, just return the client key */
    mov     x0, x20
    b       ws_key_done

ws_key_fail:
    mov     x0, #ERR_INVALID

ws_key_done:
    ldr     x23, [sp, #48]
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #64
    ret

/*
 * ws_handle_upgrade(client_fd, request, response) - Handle WebSocket upgrade
 * x0 = client file descriptor
 * x1 = HTTP request buffer
 * x2 = response buffer
 * Returns: x0 = 0 on success, error code on failure
 */
ws_handle_upgrade:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* client_fd */
    mov     x20, x1                 /* request */
    mov     x21, x2                 /* response buffer */
    
    /* Validate handshake request */
    mov     x0, x20
    bl      ws_validate_handshake
    cmp     x0, #0
    bne     ws_upgrade_fail
    
    /* Extract client key */
    /* TODO: Parse Sec-WebSocket-Key value */
    
    /* Generate accept key */
    /* TODO: Implement proper SHA1 + base64 */
    
    /* Build response */
    mov     x0, x21
    ldr     x1, =ws_response_accept
    mov     x2, ws_response_accept_len
    bl      memcpy
    
    /* Add accept key to response */
    /* TODO: Add generated key */
    
    /* Add final CRLF */
    mov     w3, #0x0D
    strb    w3, [x21, ws_response_accept_len]
    mov     w3, #0x0A
    strb    w3, [x21, ws_response_accept_len + 1]
    
    mov     x0, #0
    b       ws_upgrade_done

ws_upgrade_fail:
    mov     x0, #ERR_INVALID

ws_upgrade_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* Helper: Simple SHA1 implementation (stub) */
/* TODO: Implement full SHA1 in assembly */
sha1_hash:
    mov     x0, #ERR_UNSUPPORTED
    ret

/* Helper: Base64 encode */
/* TODO: Implement base64 in assembly */
base64_encode:
    mov     x0, #ERR_UNSUPPORTED
    ret

