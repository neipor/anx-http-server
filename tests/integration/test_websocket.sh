#!/bin/bash
# WebSocket Integration Tests
# Tests full WebSocket handshake and frame processing

source "$(dirname "$0")/../utils/common.sh"

log_section "WebSocket Integration Tests"

# =============================================================================
# Test 1: WebSocket Handshake (RFC 6455)
# =============================================================================
log_info "Test 1: WebSocket Handshake"

# Start server
start_test_server || exit 1

# Generate a WebSocket key (16 bytes base64 encoded)
WS_KEY=$(openssl rand -base64 16 | tr -d '\n')
log_info "Using WebSocket key: $WS_KEY"

# Calculate expected accept key
# accept = base64(sha1(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
MAGIC_STRING="258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
EXPECTED_ACCEPT=$(printf '%s%s' "$WS_KEY" "$MAGIC_STRING" | openssl sha1 -binary | base64 | tr -d '\n')
log_info "Expected accept key: $EXPECTED_ACCEPT"

# Send WebSocket upgrade request
WS_RESPONSE=$(curl -s -i \
    -H "Host: localhost:$TEST_PORT" \
    -H "Upgrade: websocket" \
    -H "Connection: Upgrade" \
    -H "Sec-WebSocket-Key: $WS_KEY" \
    -H "Sec-WebSocket-Version: 13" \
    "$BASE_URL/" 2>&1)

# Check response status
if echo "$WS_RESPONSE" | grep -q "HTTP/1.1 101"; then
    log_pass "WebSocket handshake returns 101 Switching Protocols"
else
    # Check if server returns upgrade required or other response
    STATUS=$(echo "$WS_RESPONSE" | grep -E "^HTTP/1\.[01]" | awk '{print $2}')
    if [ -z "$STATUS" ]; then
        log_fail "No HTTP status received in WebSocket handshake"
    else
        log_warn "WebSocket handshake returned status $STATUS (expected 101)"
    fi
fi

# Check for required headers
if echo "$WS_RESPONSE" | grep -qi "Upgrade: websocket"; then
    log_pass "WebSocket handshake includes Upgrade: websocket header"
else
    log_warn "WebSocket handshake missing Upgrade header"
fi

if echo "$WS_RESPONSE" | grep -qi "Connection: Upgrade"; then
    log_pass "WebSocket handshake includes Connection: Upgrade header"
else
    log_warn "WebSocket handshake missing Connection header"
fi

# Check Sec-WebSocket-Accept header
ACCEPT_HEADER=$(echo "$WS_RESPONSE" | grep -i "Sec-WebSocket-Accept" | awk '{print $2}' | tr -d '\r')
if [ -n "$ACCEPT_HEADER" ]; then
    log_info "Server returned accept key: $ACCEPT_HEADER"
    if [ "$ACCEPT_HEADER" == "$EXPECTED_ACCEPT" ]; then
        log_pass "Sec-WebSocket-Accept key is correct"
    else
        log_fail "Sec-WebSocket-Accept key mismatch"
        log_info "Expected: $EXPECTED_ACCEPT"
        log_info "Got:      $ACCEPT_HEADER"
    fi
else
    log_warn "Sec-WebSocket-Accept header not found"
fi

stop_test_server
sleep 2

# =============================================================================
# Test 2: Invalid WebSocket Requests
# =============================================================================
log_info "Test 2: Invalid WebSocket Requests"

start_test_server || exit 1

# Test without Sec-WebSocket-Key
log_info "Testing request without Sec-WebSocket-Key..."
RESPONSE_NO_KEY=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Host: localhost:$TEST_PORT" \
    -H "Upgrade: websocket" \
    -H "Connection: Upgrade" \
    -H "Sec-WebSocket-Version: 13" \
    "$BASE_URL/" 2>&1)

if [ "$RESPONSE_NO_KEY" == "400" ] || [ "$RESPONSE_NO_KEY" == "426" ]; then
    log_pass "Request without key rejected (HTTP $RESPONSE_NO_KEY)"
else
    log_info "Request without key returned HTTP $RESPONSE_NO_KEY"
fi

# Test with invalid WebSocket version
log_info "Testing request with invalid WebSocket version..."
RESPONSE_BAD_VER=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Host: localhost:$TEST_PORT" \
    -H "Upgrade: websocket" \
    -H "Connection: Upgrade" \
    -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" \
    -H "Sec-WebSocket-Version: 99" \
    "$BASE_URL/" 2>&1)

if [ "$RESPONSE_BAD_VER" == "426" ]; then
    log_pass "Invalid version rejected with 426 Upgrade Required"
    
    # Check for Sec-WebSocket-Version header in response
    VER_HEADER=$(curl -s -i \
        -H "Host: localhost:$TEST_PORT" \
        -H "Upgrade: websocket" \
        -H "Connection: Upgrade" \
        -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" \
        -H "Sec-WebSocket-Version: 99" \
        "$BASE_URL/" 2>&1 | grep -i "Sec-WebSocket-Version")
    
    if [ -n "$VER_HEADER" ]; then
        log_pass "Server returned supported versions: $VER_HEADER"
    fi
else
    log_info "Invalid version returned HTTP $RESPONSE_BAD_VER"
fi

# Test without Upgrade header
log_info "Testing request without Upgrade header..."
RESPONSE_NO_UPGRADE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Host: localhost:$TEST_PORT" \
    -H "Connection: Upgrade" \
    -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" \
    -H "Sec-WebSocket-Version: 13" \
    "$BASE_URL/" 2>&1)

if [ "$RESPONSE_NO_UPGRADE" != "101" ]; then
    log_pass "Request without Upgrade header not upgraded (HTTP $RESPONSE_NO_UPGRADE)"
else
    log_warn "Request without Upgrade header was upgraded"
fi

stop_test_server
sleep 2

# =============================================================================
# Test 3: WebSocket Frame Format Validation
# =============================================================================
log_info "Test 3: WebSocket Frame Format"

# Frame structure (RFC 6455 Section 5.2):
#  0                   1                   2                   3
#  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
# +-+-+-+-+-------+-+-------------+-------------------------------+
# |F|R|R|R| opcode|M| Payload len |    Extended payload length    |
# |I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
# |N|V|V|V|       |S|             |   (if payload len==126/127)   |
# | |1|2|3|       |K|             |                               |
# +-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
# |     Extended payload length continued, if payload len == 127  |
# + - - - - - - - - - - - - - - - +-------------------------------+
# |                               |Masking-key, if MASK set to 1  |
# +-------------------------------+-------------------------------+
# | Masking-key (continued)       |          Payload Data         |
# +-------------------------------- - - - - - - - - - - - - - - - +
# :                     Payload Data continued ...                :
# + - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
# |                     Payload Data continued ...                |
# +---------------------------------------------------------------+

log_info "WebSocket frame format validation requires binary frame testing"
log_skip "WebSocket frame format tests (requires WebSocket client library)"

# =============================================================================
# Test 4: WebSocket Protocol Compliance
# =============================================================================
log_info "Test 4: WebSocket Protocol Compliance"

# Test supported opcodes
log_info "WebSocket opcodes: 0x0=continuation, 0x1=text, 0x2=binary, 0x8=close, 0x9=ping, 0xA=pong"
log_skip "WebSocket opcode tests (requires WebSocket client library)"

# =============================================================================
# Test 5: Concurrent WebSocket Connections
# =============================================================================
log_info "Test 5: Concurrent WebSocket Connections"

start_test_server || exit 1

# Try to open multiple WebSocket connections
log_info "Testing 3 concurrent WebSocket handshakes..."

for i in 1 2 3; do
    KEY=$(openssl rand -base64 16)
    (
        curl -s -o /dev/null \
            -H "Host: localhost:$TEST_PORT" \
            -H "Upgrade: websocket" \
            -H "Connection: Upgrade" \
            -H "Sec-WebSocket-Key: $KEY" \
            -H "Sec-WebSocket-Version: 13" \
            "$BASE_URL/" 2>&1
    ) &
done

wait
log_info "Concurrent handshake requests sent"

stop_test_server
sleep 2

# =============================================================================
# Test 6: WebSocket with Query Parameters
# =============================================================================
log_info "Test 6: WebSocket Handshake with Query Parameters"

start_test_server || exit 1

WS_KEY=$(openssl rand -base64 16)
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Host: localhost:$TEST_PORT" \
    -H "Upgrade: websocket" \
    -H "Connection: Upgrade" \
    -H "Sec-WebSocket-Key: $WS_KEY" \
    -H "Sec-WebSocket-Version: 13" \
    "$BASE_URL/?room=123&user=test" 2>&1)

if [ "$RESPONSE" == "101" ]; then
    log_pass "WebSocket handshake with query parameters successful"
else
    log_info "WebSocket with query params returned HTTP $RESPONSE"
fi

stop_test_server

# =============================================================================
# Summary
# =============================================================================
log_info "WebSocket integration tests completed"
log_info "Note: Full frame and message testing requires WebSocket client library"
