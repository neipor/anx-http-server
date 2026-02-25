#!/bin/bash
# ANX HTTP/2 Benchmark using h2load

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/../build"
SERVER="$BUILD_DIR/anx"
PORT=18081
TEST_DIR="$SCRIPT_DIR/test_www_h2"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Default parameters
THREADS=4
CONNECTIONS=100
REQUESTS=10000

setup() {
    log_info "Setting up HTTP/2 test environment..."
    mkdir -p "$TEST_DIR"
    echo "<h1>HTTP/2 Benchmark</h1>" > "$TEST_DIR/index.html"
    dd if=/dev/urandom of="$TEST_DIR/1mb.bin" bs=1M count=1 2>/dev/null
}

start_server() {
    log_info "Starting server with HTTP/2 support on port $PORT..."
    $SERVER -p $PORT -d "$TEST_DIR" > /tmp/anx_h2.log 2>&1 &
    SERVER_PID=$!
    sleep 2
    
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        log_fail "Server failed to start"
        cat /tmp/anx_h2.log
        exit 1
    fi
    log_pass "Server started (PID: $SERVER_PID)"
}

stop_server() {
    log_info "Stopping server..."
    pkill -f "anx.*$PORT" 2>/dev/null || true
    sleep 1
}

run_h2load() {
    local test_name=$1
    local url=$2
    
    if ! command -v h2load &> /dev/null; then
        log_warn "h2load not installed. Install with: apt install nghttp2-client"
        return 1
    fi
    
    log_info "Running h2load test: $test_name"
    
    h2load -n$REQUESTS -c$CONNECTIONS -t$THREADS "$url" 2>&1 | tee /tmp/h2load_$test_name.log
    
    local rps=$(grep "requests per second" /tmp/h2load_$test_name.log | awk '{print $1}')
    echo ""
    echo "  HTTP/2 RPS: $rps"
    echo ""
}

main() {
    echo "========================================"
    echo "ANX HTTP/2 Performance Benchmark"
    echo "========================================"
    
    setup
    start_server
    
    echo ""
    echo "Parameters:"
    echo "  Requests: $REQUESTS"
    echo "  Connections: $CONNECTIONS"
    echo "  Threads: $THREADS"
    echo ""
    
    run_h2load "http2" "http://localhost:$PORT/index.html"
    
    stop_server
    
    echo "========================================"
    echo "HTTP/2 Benchmark Complete"
    echo "========================================"
}

trap stop_server EXIT
main
