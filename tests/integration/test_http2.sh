#!/bin/bash
# HTTP/2 Integration Tests
# Tests HTTP/2 protocol support, multiplexing, and HPACK

source "$(dirname "$0")/../utils/common.sh"

log_section "HTTP/2 Integration Tests"

# =============================================================================
# Check for HTTP/2 client tools
# =============================================================================
H2_CLIENT=""
if command -v h2load >/dev/null 2>&1; then
    H2_CLIENT="h2load"
    log_info "Using h2load for HTTP/2 testing"
elif command -v nghttp >/dev/null 2>&1; then
    H2_CLIENT="nghttp"
    log_info "Using nghttp for HTTP/2 testing"
elif command -v curl >/dev/null 2>&1 && curl --version | grep -q "HTTP2"; then
    H2_CLIENT="curl"
    log_info "Using curl with HTTP/2 support"
else
    log_warn "No HTTP/2 client found (h2load, nghttp, or curl with HTTP/2)"
    log_warn "HTTP/2 tests will be limited"
fi

# Create test data
mkdir -p "$TEST_DATA_DIR/http2"
echo "HTTP/2 test content" > "$TEST_DATA_DIR/http2/index.html"
dd if=/dev/urandom of="$TEST_DATA_DIR/http2/data.bin" bs=1K count=10 2>/dev/null

# =============================================================================
# Test 1: HTTP/2 Upgrade Negotiation
# =============================================================================
log_info "Test 1: HTTP/2 Upgrade Negotiation (HTTP Upgrade)"

start_test_server || exit 1

# Test HTTP/1.1 Upgrade request
UPGRADE_RESPONSE=$(curl -s -i \
    -H "Host: localhost:$TEST_PORT" \
    -H "Upgrade: h2c" \
    -H "HTTP2-Settings: AAMAAABkAARAAAAAAAIAAAAA" \
    -H "Connection: Upgrade, HTTP2-Settings" \
    "$BASE_URL/http2/index.html" 2>&1)

# Check if server supports HTTP/2 upgrade
if echo "$UPGRADE_RESPONSE" | grep -q "HTTP/1.1 101"; then
    log_pass "Server accepted HTTP/2 upgrade (101 Switching Protocols)"
    
    if echo "$UPGRADE_RESPONSE" | grep -qi "Upgrade: h2c"; then
        log_pass "Server confirmed h2c upgrade"
    fi
elif echo "$UPGRADE_RESPONSE" | grep -q "HTTP/1.1 200"; then
    log_info "Server responded with HTTP/1.1 (HTTP/2 upgrade not supported or ignored)"
else
    log_info "Upgrade response: $(echo "$UPGRADE_RESPONSE" | head -1)"
fi

stop_test_server
sleep 2

# =============================================================================
# Test 2: HTTP/2 Prior Knowledge (h2c direct)
# =============================================================================
log_info "Test 2: HTTP/2 Prior Knowledge (h2c)"

start_test_server || exit 1

if [ "$H2_CLIENT" == "h2load" ]; then
    log_info "Testing HTTP/2 with h2load..."
    
    # Basic HTTP/2 request
    h2load -n10 -c1 -m1 "$BASE_URL/http2/index.html" 2>&1 | tee "$TEST_RESULTS_DIR/h2load_basic.log" || true
    
    if [ -f "$TEST_RESULTS_DIR/h2load_basic.log" ]; then
        if grep -q "status: 200" "$TEST_RESULTS_DIR/h2load_basic.log"; then
            log_pass "HTTP/2 requests successful"
            
            # Extract statistics
            REQ_PER_SEC=$(grep "requests per second" "$TEST_RESULTS_DIR/h2load_basic.log" | awk '{print $4}' || echo "N/A")
            log_info "HTTP/2 performance: $REQ_PER_SEC req/s"
        else
            log_warn "HTTP/2 requests may have failed (check $TEST_RESULTS_DIR/h2load_basic.log)"
        fi
    fi
    
elif [ "$H2_CLIENT" == "nghttp" ]; then
    log_info "Testing HTTP/2 with nghttp..."
    
    nghttp -v "$BASE_URL/http2/index.html" 2>&1 | tee "$TEST_RESULTS_DIR/nghttp.log" || true
    
    if grep -q ":status: 200" "$TEST_RESULTS_DIR/nghttp.log" 2>/dev/null; then
        log_pass "HTTP/2 request successful (nghttp)"
    else
        log_warn "HTTP/2 request with nghttp may have failed"
    fi
    
elif [ "$H2_CLIENT" == "curl" ]; then
    log_info "Testing HTTP/2 with curl..."
    
    if curl --http2 -s -o /dev/null "$BASE_URL/http2/index.html" 2>/dev/null; then
        log_pass "HTTP/2 request successful (curl)"
    else
        log_warn "HTTP/2 request with curl may have failed"
    fi
fi

stop_test_server
sleep 2

# =============================================================================
# Test 3: HTTP/2 Multiplexing
# =============================================================================
log_info "Test 3: HTTP/2 Multiplexing"

start_test_server || exit 1

if [ "$H2_CLIENT" == "h2load" ]; then
    log_info "Testing HTTP/2 multiplexing (multiple streams per connection)..."
    
    # 100 requests, 1 connection, 10 concurrent streams
    h2load -n100 -c1 -m10 "$BASE_URL/http2/index.html" 2>&1 | tee "$TEST_RESULTS_DIR/h2load_mux.log" || true
    
    if [ -f "$TEST_RESULTS_DIR/h2load_mux.log" ]; then
        SUCCESS=$(grep "status: 200" "$TEST_RESULTS_DIR/h2load_mux.log" | wc -l)
        log_info "Multiplexing: $SUCCESS/100 requests succeeded"
        
        if [ $SUCCESS -ge 80 ]; then
            log_pass "HTTP/2 multiplexing working"
        else
            log_warn "HTTP/2 multiplexing has issues ($SUCCESS/100 success)"
        fi
    fi
fi

stop_test_server
sleep 2

# =============================================================================
# Test 4: HTTP/2 Concurrent Connections
# =============================================================================
log_info "Test 4: HTTP/2 Concurrent Connections"

start_test_server || exit 1

if [ "$H2_CLIENT" == "h2load" ]; then
    log_info "Testing multiple HTTP/2 connections..."
    
    # 1000 requests, 10 connections, 5 streams each
    h2load -n1000 -c10 -m5 "$BASE_URL/http2/index.html" 2>&1 | tee "$TEST_RESULTS_DIR/h2load_concurrent.log" || true
    
    if [ -f "$TEST_RESULTS_DIR/h2load_concurrent.log" ]; then
        REQ_PER_SEC=$(grep "requests per second" "$TEST_RESULTS_DIR/h2load_concurrent.log" | awk '{print $4}' || echo "N/A")
        log_info "HTTP/2 with 10 connections: $REQ_PER_SEC req/s"
        
        if [ "$REQ_PER_SEC" != "N/A" ] && [ "${REQ_PER_SEC%.*}" -gt 100 ] 2>/dev/null; then
            log_pass "HTTP/2 performance good (>100 req/s)"
        else
            log_info "HTTP/2 performance: $REQ_PER_SEC req/s"
        fi
    fi
fi

stop_test_server
sleep 2

# =============================================================================
# Test 5: HTTP/2 Server Push (if supported)
# =============================================================================
log_info "Test 5: HTTP/2 Server Push"

start_test_server || exit 1

log_info "Testing HTTP/2 server push..."

if [ "$H2_CLIENT" == "nghttp" ]; then
    # nghttp can detect server push
    nghttp -v "$BASE_URL/http2/index.html" 2>&1 | grep -i "push" > "$TEST_RESULTS_DIR/http2_push.log" || true
    
    if [ -s "$TEST_RESULTS_DIR/http2_push.log" ]; then
        log_info "Server push detected"
    else
        log_info "No server push detected (may not be implemented)"
    fi
else
    log_skip "Server push test requires nghttp client"
fi

stop_test_server
sleep 2

# =============================================================================
# Test 6: HTTP/2 Flow Control
# =============================================================================
log_info "Test 6: HTTP/2 Flow Control"

start_test_server || exit 1

# Test with large file to trigger flow control
log_info "Testing flow control with large file..."

dd if=/dev/urandom of="$TEST_DATA_DIR/http2/large.bin" bs=1M count=5 2>/dev/null

if [ "$H2_CLIENT" == "h2load" ]; then
    h2load -n10 -c1 -m1 "$BASE_URL/http2/large.bin" 2>&1 | tee "$TEST_RESULTS_DIR/h2load_flow.log" || true
    
    if [ -f "$TEST_RESULTS_DIR/h2load_flow.log" ] && grep -q "status: 200" "$TEST_RESULTS_DIR/h2load_flow.log"; then
        log_pass "Large file transfer via HTTP/2 successful"
    else
        log_warn "Large file transfer may have issues"
    fi
fi

rm -f "$TEST_DATA_DIR/http2/large.bin"

stop_test_server
sleep 2

# =============================================================================
# Test 7: HPACK Header Compression
# =============================================================================
log_info "Test 7: HPACK Header Compression"

start_test_server || exit 1

if [ "$H2_CLIENT" == "nghttp" ]; then
    log_info "Testing HPACK with nghttp..."
    
    # nghttp shows headers
    nghttp -v "$BASE_URL/http2/index.html" 2>&1 | tee "$TEST_RESULTS_DIR/hpack.log" || true
    
    if [ -f "$TEST_RESULTS_DIR/hpack.log" ]; then
        # Check for common headers
        HEADERS=(":method" ":authority" ":scheme" ":path" "content-type")
        FOUND=0
        for header in "${HEADERS[@]}"; do
            if grep -q "$header" "$TEST_RESULTS_DIR/hpack.log"; then
                FOUND=$((FOUND + 1))
            fi
        done
        log_info "HTTP/2 headers found: $FOUND/${#HEADERS[@]}"
    fi
fi

stop_test_server
sleep 2

# =============================================================================
# Test 8: HTTP/2 Error Handling
# =============================================================================
log_info "Test 8: HTTP/2 Error Handling"

start_test_server || exit 1

# Test invalid stream ID, etc.
log_info "HTTP/2 error handling tests would require custom frame injection"
log_skip "HTTP/2 error handling (requires custom frame injection tool)"

stop_test_server

# =============================================================================
# Test 9: HTTP/2 vs HTTP/1.1 Performance Comparison
# =============================================================================
log_info "Test 9: HTTP/2 vs HTTP/1.1 Performance"

start_test_server || exit 1

if [ "$H2_CLIENT" == "h2load" ]; then
    log_info "Comparing HTTP/1.1 vs HTTP/2 performance..."
    
    # HTTP/1.1 test (if h2load supports it)
    curl -s -w "HTTP/1.1: %{time_total}s\n" -o /dev/null "$BASE_URL/http2/index.html" 2>/dev/null
    
    # HTTP/2 test
    h2load -n100 -c1 -m1 "$BASE_URL/http2/index.html" 2>&1 | tee "$TEST_RESULTS_DIR/h2_compare.log" || true
    
    if [ -f "$TEST_RESULTS_DIR/h2_compare.log" ]; then
        H2_RPS=$(grep "requests per second" "$TEST_RESULTS_DIR/h2_compare.log" | awk '{print $4}' || echo "N/A")
        log_info "HTTP/2 RPS: $H2_RPS"
    fi
fi

stop_test_server

# =============================================================================
# Cleanup
# =============================================================================
rm -rf "$TEST_DATA_DIR/http2"

# =============================================================================
# Summary
# =============================================================================
log_info "HTTP/2 integration tests completed"
log_info "Note: Full HTTP/2 testing requires h2load or nghttp client"
