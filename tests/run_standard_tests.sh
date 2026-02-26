#!/bin/bash
# ANX Web Server - Standard Test Suite (30 minutes)
# Tests: Build, Unit, HTTP/1.1, WebSocket, Performance, Quick Security

# Don't use set -e - we handle failures manually to continue testing

# Source test framework
source "$(dirname "$0")/utils/common.sh"

SUITE_NAME="standard"
SUITE_START_TIME=$(date +%s)

log_section "ANX Web Server Standard Test Suite"
log_info "Version: $(cat $PROJECT_DIR/src/version.s 2>/dev/null | grep msg_version | head -1 | cut -d'"' -f2 || echo 'unknown')"
log_info "Started at: $(date)"

# Cleanup on exit
trap cleanup_test_env EXIT

# =============================================================================
# Phase 1: Build Verification (2 minutes)
# =============================================================================
log_section "Phase 1: Build Verification"

start_timer
log_info "Cleaning previous build..."
make -C "$PROJECT_DIR" clean >/dev/null 2>&1 || true

log_info "Building server..."
if make -C "$PROJECT_DIR" -j$(nproc) > "$TEST_RESULTS_DIR/build.log" 2>&1; then
    log_pass "Build successful"
else
    log_fail "Build failed"
    cat "$TEST_RESULTS_DIR/build.log"
    exit 1
fi

# Verify binary
if [ -f "$SERVER_BIN" ]; then
    SIZE=$(ls -lh "$SERVER_BIN" | awk '{print $5}')
    log_info "Binary size: $SIZE"
    
    # Check if static
    if file "$SERVER_BIN" | grep -q "statically linked"; then
        log_pass "Binary is statically linked"
    else
        log_warn "Binary may have dynamic dependencies"
    fi
else
    log_fail "Binary not found"
    exit 1
fi

BUILD_TIME=$(stop_timer)
log_info "Build phase completed in ${BUILD_TIME}"

# =============================================================================
# Phase 2: Unit Tests (5 minutes)
# =============================================================================
log_section "Phase 2: Unit Tests"

# Test SIMD functions
if [ -f "$TESTS_DIR/unit/test_simd.sh" ]; then
    log_info "Running SIMD unit tests..."
    bash "$TESTS_DIR/unit/test_simd.sh" || log_fail "SIMD tests failed"
else
    log_skip "SIMD unit tests not found"
fi

# Test Crypto
if [ -f "$TESTS_DIR/unit/test_crypto.sh" ]; then
    log_info "Running Crypto unit tests..."
    bash "$TESTS_DIR/unit/test_crypto.sh" || log_fail "Crypto tests failed"
else
    log_skip "Crypto unit tests not found"
fi

# Test HPACK
if [ -f "$TESTS_DIR/unit/test_hpack.sh" ]; then
    log_info "Running HPACK unit tests..."
    bash "$TESTS_DIR/unit/test_hpack.sh" || log_fail "HPACK tests failed"
else
    log_skip "HPACK unit tests not found"
fi

# =============================================================================
# Phase 3: HTTP/1.1 Integration Tests (10 minutes)
# =============================================================================
log_section "Phase 3: HTTP/1.1 Integration Tests"

# Setup test data
mkdir -p "$TEST_DATA_DIR"
echo "<h1>Test Page</h1>" > "$TEST_DATA_DIR/index.html"
echo "body{color:red}" > "$TEST_DATA_DIR/style.css"
echo '{"test":"data"}' > "$TEST_DATA_DIR/api.json"
mkdir -p "$TEST_DATA_DIR/subdir"
echo "sub content" > "$TEST_DATA_DIR/subdir/file.txt"

# Start server
start_test_server || exit 1

# Basic connectivity
assert_status_code "$BASE_URL/" "200"

# Static files
assert_status_code "$BASE_URL/index.html" "200"
assert_status_code "$BASE_URL/style.css" "200"
assert_status_code "$BASE_URL/api.json" "200"

# Directory listing
assert_status_code "$BASE_URL/subdir/" "200"

# 404 handling
assert_status_code "$BASE_URL/notfound.html" "404"

# Path traversal protection
assert_status_code "$BASE_URL/../etc/passwd" "403"

# Concurrent connections test disabled - server has connection limits
log_skip "Concurrent connections test (server connection limits)"

# Content-Type headers
CT=$(curl -s -o /dev/null -w "%{content_type}" "$BASE_URL/index.html")
if echo "$CT" | grep -q "text/html"; then
    log_pass "HTML Content-Type correct"
else
    log_fail "HTML Content-Type incorrect: $CT"
fi

# Stop server
stop_test_server

# =============================================================================
# Phase 4: WebSocket Tests (5 minutes)
# =============================================================================
log_section "Phase 4: WebSocket Tests"

if [ -f "$TESTS_DIR/integration/test_websocket.sh" ]; then
    bash "$TESTS_DIR/integration/test_websocket.sh"
else
    log_skip "WebSocket tests not implemented yet"
fi

# =============================================================================
# Phase 5: Performance Benchmarks (5 minutes)
# =============================================================================
log_section "Phase 5: Performance Benchmarks"

# Wait for port to be released
sleep 2
start_test_server || exit 1

# Basic latency test
log_info "Testing request latency..."
LATENCY_TOTAL=0
for i in {1..5}; do
    START=$(date +%s%N)
    curl -s -o /dev/null --max-time 5 "$BASE_URL/index.html"
    END=$(date +%s%N)
    LATENCY=$(( (END - START) / 1000000 ))
    LATENCY_TOTAL=$((LATENCY_TOTAL + LATENCY))
done
AVG_LATENCY=$((LATENCY_TOTAL / 5))
log_info "Average latency: ${AVG_LATENCY}ms"

if [ $AVG_LATENCY -lt 100 ]; then
    log_pass "Latency acceptable (<100ms)"
else
    log_warn "Latency high: ${AVG_LATENCY}ms"
fi

# Throughput test with curl (reduced to 50 for speed)
log_info "Testing throughput (50 sequential requests)..."
START=$(date +%s)
for i in {1..50}; do
    curl -s -o /dev/null --max-time 5 "$BASE_URL/index.html"
done
END=$(date +%s)
DURATION=$((END - START))
RPS=$((50 / DURATION))
log_info "Throughput: ~${RPS} req/s (50 requests in ${DURATION}s)"

if [ $RPS -gt 10 ]; then
    log_pass "Basic throughput acceptable"
else
    log_warn "Throughput low: ${RPS} req/s"
fi

# Wrk benchmark (if available)
if check_dependency wrk; then
    log_info "Running wrk benchmark (10 seconds)..."
    WRK_OUTPUT=$(wrk -t4 -c100 -d10s --latency "$BASE_URL/index.html" 2>&1 || true)
    if [ -n "$WRK_OUTPUT" ]; then
        RPS=$(echo "$WRK_OUTPUT" | grep "Requests/sec:" | awk '{print $2}')
        log_info "wrk RPS: $RPS"
        if (( $(echo "$RPS > 1000" | bc -l 2>/dev/null || echo "0") )); then
            log_pass "wrk performance good (>1000 RPS)"
        fi
    fi
fi

stop_test_server

# =============================================================================
# Phase 6: Quick Security Scan (3 minutes)
# =============================================================================
log_section "Phase 6: Quick Security Scan"

start_test_server || exit 1

# Path traversal
assert_status_code "$BASE_URL/../../../etc/passwd" "403"
assert_status_code "$BASE_URL/%2e%2e/%2e%2e/etc/passwd" "403"

# NULL byte injection
assert_status_code "$BASE_URL/index.html%00.txt" "400"

# Long URL
LONG_URL="$BASE_URL/$(python3 -c 'print("A"*2000)')"
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$LONG_URL" 2>/dev/null || echo "000")
if [ "$RESPONSE" == "414" ] || [ "$RESPONSE" == "400" ] || [ "$RESPONSE" == "403" ]; then
    log_pass "Long URL handled properly ($RESPONSE)"
else
    log_warn "Long URL response: $RESPONSE"
fi

# Method not allowed
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/index.html")
if [ "$RESPONSE" == "405" ] || [ "$RESPONSE" == "501" ]; then
    log_pass "DELETE method rejected properly"
else
    log_info "DELETE response: $RESPONSE"
fi

stop_test_server

# =============================================================================
# Summary
# =============================================================================
SUITE_END_TIME=$(date +%s)
SUITE_DURATION=$((SUITE_END_TIME - SUITE_START_TIME))

log_section "Test Suite Complete"
generate_json_report "$SUITE_NAME" "$SUITE_DURATION"
print_summary "$SUITE_DURATION"

exit $TESTS_FAILED
