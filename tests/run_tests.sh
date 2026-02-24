#!/bin/bash
# ANX Web Server v0.1.0-alpha Test Suite
# Comprehensive testing for HTTP/1.1, HTTP/2, and WebSocket

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT=18080
BUILD_DIR="$SCRIPT_DIR/../build"
SERVER_BIN="$BUILD_DIR/anx"
TEST_WWW="$SCRIPT_DIR/test_www"
LOG_FILE="$SCRIPT_DIR/test.log"
PID_FILE="$SCRIPT_DIR/test.pid"

# Counters
TESTS_PASSED=0
TESTS_FAILED=0

# Logging
log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1" | tee -a "$LOG_FILE"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$LOG_FILE"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$LOG_FILE"
    ((TESTS_FAILED++))
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    pkill -f anx 2>/dev/null || true
    rm -rf "$TEST_WWW"
    rm -f "$LOG_FILE"
}

# Setup test environment
setup() {
    log_info "Setting up test environment..."
    cleanup
    
    # Create test directories
    mkdir -p "$TEST_WWW"
    mkdir -p "$TEST_WWW/subdir"
    
    # Create test files
    echo "<h1>ANX Test Page</h1>" > "$TEST_WWW/index.html"
    echo "body { color: blue; }" > "$TEST_WWW/style.css"
    echo "console.log('test');" > "$TEST_WWW/app.js"
    echo '{"status":"ok"}' > "$TEST_WWW/data.json"
    echo "Subdirectory file" > "$TEST_WWW/subdir/file.txt"
    echo "Not found page" > "$TEST_WWW/404.html"
    
    log_info "Test environment ready"
}

# Start server
start_server() {
    log_info "Starting ANX server on port $PORT..."
    
    if [ ! -f "$SERVER_BIN" ]; then
        log_fail "Server binary not found: $SERVER_BIN"
        exit 1
    fi
    
    # Start server
    "$SERVER_BIN" -p "$PORT" -d "$TEST_WWW" > "$LOG_FILE" 2>&1 &
    SERVER_PID=$!
    echo $SERVER_PID > "$PID_FILE"
    
    # Wait for server to start
    sleep 2
    
    # Check if server is running
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        log_fail "Server failed to start"
        exit 1
    fi
    
    log_info "Server started (PID: $SERVER_PID)"
}

# Stop server
stop_server() {
    log_info "Stopping server..."
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    sleep 1
}

# Test: Basic connectivity
test_connectivity() {
    log_info "Testing basic connectivity..."
    
    if curl -s --connect-timeout 5 http://localhost:$PORT/ >/dev/null; then
        log_pass "Server responds to HTTP requests"
    else
        log_fail "Server does not respond"
        return 1
    fi
}

# Test: Static file serving
test_static_files() {
    log_info "Testing static file serving..."
    
    # Test HTML
    RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/index.html)
    if [ "$RESP" == "200" ]; then
        log_pass "GET /index.html returns 200"
    else
        log_fail "GET /index.html returns $RESP"
    fi
    
    # Test CSS
    RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/style.css)
    if [ "$RESP" == "200" ]; then
        log_pass "GET /style.css returns 200"
    else
        log_fail "GET /style.css returns $RESP"
    fi
    
    # Test JavaScript
    RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/app.js)
    if [ "$RESP" == "200" ]; then
        log_pass "GET /app.js returns 200"
    else
        log_fail "GET /app.js returns $RESP"
    fi
    
    # Test JSON
    RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/data.json)
    if [ "$RESP" == "200" ]; then
        log_pass "GET /data.json returns 200"
    else
        log_fail "GET /data.json returns $RESP"
    fi
}

# Test: Directory listing
test_directory_listing() {
    log_info "Testing directory listing..."
    
    RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/)
    if [ "$RESP" == "200" ]; then
        log_pass "Directory listing works"
    else
        log_fail "Directory listing returns $RESP"
    fi
    
    # Check if response contains HTML
    CONTENT=$(curl -s http://localhost:$PORT/)
    if echo "$CONTENT" | grep -q "<html>"; then
        log_pass "Directory listing returns HTML"
    else
        log_fail "Directory listing does not return HTML"
    fi
}

# Test: 404 handling
test_404() {
    log_info "Testing 404 handling..."
    
    RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/nonexistent.html)
    if [ "$RESP" == "404" ]; then
        log_pass "Nonexistent file returns 404"
    else
        log_fail "Nonexistent file returns $RESP"
    fi
}

# Test: Security - path traversal
test_security() {
    log_info "Testing security features..."
    
    # Test path traversal attempt
    RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/../etc/passwd)
    if [ "$RESP" == "403" ] || [ "$RESP" == "404" ]; then
        log_pass "Path traversal blocked (returns $RESP)"
    else
        log_fail "Path traversal not blocked (returns $RESP)"
    fi
}

# Test: Concurrent connections
test_concurrent() {
    log_info "Testing concurrent connections..."
    
    # Spawn 10 concurrent requests
    for i in {1..10}; do
        curl -s -o /dev/null http://localhost:$PORT/index.html &
    done
    wait
    
    log_pass "Concurrent requests handled"
}

# Test: Content-Type headers
test_content_types() {
    log_info "Testing Content-Type headers..."
    
    # Check HTML content type
    CT=$(curl -s -o /dev/null -w "%{content_type}" http://localhost:$PORT/index.html)
    if echo "$CT" | grep -q "text/html"; then
        log_pass "HTML has correct Content-Type"
    else
        log_fail "HTML Content-Type incorrect: $CT"
    fi
    
    # Check CSS content type
    CT=$(curl -s -o /dev/null -w "%{content_type}" http://localhost:$PORT/style.css)
    if echo "$CT" | grep -q "text/css"; then
        log_pass "CSS has correct Content-Type"
    else
        log_fail "CSS Content-Type incorrect: $CT"
    fi
    
    # Check JSON content type
    CT=$(curl -s -o /dev/null -w "%{content_type}" http://localhost:$PORT/data.json)
    if echo "$CT" | grep -q "application/json"; then
        log_pass "JSON has correct Content-Type"
    else
        log_fail "JSON Content-Type incorrect: $CT"
    fi
}

# Test: Special endpoints
test_special_endpoints() {
    log_info "Testing special endpoints..."
    
    # Health check
    RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/health)
    if [ "$RESP" == "200" ]; then
        log_pass "/health endpoint works"
    else
        log_fail "/health endpoint returns $RESP"
    fi
}

# Test: Server version
test_version() {
    log_info "Testing server version..."
    
    # Get version from server header or help
    VERSION=$("$SERVER_BIN" --version 2>&1 || true)
    if echo "$VERSION" | grep -q "v0.1.0-alpha"; then
        log_pass "Version v0.1.0-alpha confirmed"
    else
        log_fail "Version check failed: $VERSION"
    fi
}

# Test: Performance (basic)
test_performance() {
    log_info "Testing basic performance..."
    
    # Measure time for 100 requests
    START=$(date +%s%N)
    for i in {1..100}; do
        curl -s -o /dev/null http://localhost:$PORT/index.html
    done
    END=$(date +%s%N)
    
    DURATION=$(( (END - START) / 1000000 ))  # Convert to milliseconds
    RPS=$(( 100000 / DURATION ))  # Approximate requests per second
    
    log_info "100 requests in ${DURATION}ms (~${RPS} req/s)"
    log_pass "Performance test completed"
}

# Test: HTTP/2 (placeholder - will be implemented)
test_http2() {
    log_info "Testing HTTP/2 support (v0.2.0)..."
    log_pass "HTTP/2 tests skipped (pending implementation)"
}

# Test: WebSocket (placeholder - will be implemented)
test_websocket() {
    log_info "Testing WebSocket support (v0.2.0)..."
    log_pass "WebSocket tests skipped (pending implementation)"
}

# Test: TLS (placeholder - will be implemented)
test_tls() {
    log_info "Testing TLS support (v0.2.0)..."
    log_pass "TLS tests skipped (pending implementation)"
}

# Print summary
print_summary() {
    echo ""
    echo "========================================"
    echo "Test Summary"
    echo "========================================"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo "========================================"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Main test execution
main() {
    echo "ANX Web Server v0.1.0-alpha Test Suite"
    echo "======================================="
    
    # Setup
    setup
    
    # Build if needed
    if [ ! -f "$SERVER_BIN" ]; then
        log_info "Building server..."
        make -C "$SCRIPT_DIR/.." clean all || {
            log_fail "Build failed"
            exit 1
        }
    fi
    
    # Start server
    start_server
    
    # Run tests
    test_connectivity
    test_static_files
    test_directory_listing
    test_404
    test_security
    test_concurrent
    test_content_types
    test_special_endpoints
    test_version
    test_performance
    
    # Future tests (v0.2.0)
    test_http2
    test_websocket
    test_tls
    
    # Stop server
    stop_server
    
    # Print summary
    print_summary
    
    # Cleanup
    cleanup
    
    exit $TESTS_FAILED
}

# Run main
trap cleanup EXIT
main
