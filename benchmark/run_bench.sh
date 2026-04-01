#!/bin/bash
# ANX Web Server Performance Benchmark Suite
# Tests HTTP/1.1 and HTTP/2 performance

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/../build"
SERVER="$BUILD_DIR/anx"
PORT=18080
TEST_FILE="index.html"
TEST_DIR="$SCRIPT_DIR/test_www"

# Default test parameters
THREADS=4
CONNECTIONS=100
DURATION=10

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Setup test environment
setup() {
    log_info "Setting up benchmark environment..."
    mkdir -p "$TEST_DIR"
    echo "<h1>Benchmark Test</h1>" > "$TEST_DIR/$TEST_FILE"
    
    # Create various size test files
    dd if=/dev/urandom of="$TEST_DIR/small.bin" bs=1K count=1 2>/dev/null
    dd if=/dev/urandom of="$TEST_DIR/medium.bin" bs=1K count=100 2>/dev/null
    dd if=/dev/urandom of="$TEST_DIR/large.bin" bs=1M count=1 2>/dev/null
    
    log_info "Test files created"
}

# Start server
start_server() {
    log_info "Starting ANX server on port $PORT..."
    $SERVER -p $PORT -d "$TEST_DIR" > /tmp/anx_bench.log 2>&1 &
    SERVER_PID=$!
    sleep 2
    
    if ! kill -0 $SERVER_PID 2>/dev/null; then
        log_fail "Server failed to start"
        cat /tmp/anx_bench.log
        exit 1
    fi
    log_pass "Server started (PID: $SERVER_PID)"
}

# Stop server
stop_server() {
    log_info "Stopping server..."
    if [ -n "$SERVER_PID" ]; then
        kill $SERVER_PID 2>/dev/null || true
    fi
    pkill -f "anx.*$PORT" 2>/dev/null || true
    sleep 1
}

# Test connectivity
test_connectivity() {
    log_info "Testing connectivity..."
    if curl -s --connect-timeout 5 http://localhost:$PORT/$TEST_FILE >/dev/null; then
        log_pass "Server responds"
        return 0
    else
        log_fail "Server not responding"
        return 1
    fi
}

# Run wrk benchmark (if available)
run_wrk_benchmark() {
    local test_name=$1
    local url=$2
    
    log_info "Running wrk benchmark: $test_name"
    
    if ! command -v wrk &> /dev/null; then
        log_warn "wrk not installed, skipping benchmark"
        return 1
    fi
    
    # Run wrk
    local result
    result=$(wrk -t$THREADS -c$CONNECTIONS -d${DURATION}s --latency "$url" 2>/dev/null)
    
    # Extract metrics
    local rps=$(echo "$result" | grep "Requests/sec:" | awk '{print $2}')
    local lat_p50=$(echo "$result" | grep "Latency" | awk '{print $2}')
    local lat_p99=$(echo "$result" | grep "Latency" | awk '{print $5}')
    
    echo ""
    echo "  RPS: $rps"
    echo "  Latency P50: $lat_p50"
    echo "  Latency P99: $lat_p99"
    echo ""
}

# Run basic curl benchmark
run_curl_benchmark() {
    local test_name=$1
    local url=$2
    
    log_info "Running curl benchmark: $test_name"
    
    local start=$(date +%s%N)
    local count=0
    local errors=0
    
    for i in $(seq 1 100); do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$PORT$url" | grep -q "200"; then
            ((count++))
        else
            ((errors++))
        fi
    done
    
    local end=$(date +%s%N)
    local duration=$(( (end - start) / 1000000 ))
    local rps=$(( count * 1000 / duration ))
    
    echo ""
    echo "  Requests: $count success, $errors errors"
    echo "  Duration: ${duration}ms"
    echo "  RPS: ~$rps"
    echo ""
}

# Main benchmark
run_benchmarks() {
    echo "========================================"
    echo "ANX Web Server Performance Benchmark"
    echo "========================================"
    echo ""
    
    setup
    start_server
    
    if ! test_connectivity; then
        stop_server
        exit 1
    fi
    
    echo ""
    echo "Test Parameters:"
    echo "  Threads: $THREADS"
    echo "  Connections: $CONNECTIONS"
    echo "  Duration: ${DURATION}s"
    echo ""
    
    # Small file benchmark
    echo "----------------------------------------"
    echo "Small File Test (1KB)"
    echo "----------------------------------------"
    run_curl_benchmark "small" "/$TEST_FILE"
    run_wrk_benchmark "small" "http://localhost:$PORT/$TEST_FILE"
    
    # Medium file benchmark  
    echo "----------------------------------------"
    echo "Medium File Test (100KB)"
    echo "----------------------------------------"
    run_curl_benchmark "medium" "/medium.bin"
    run_wrk_benchmark "medium" "http://localhost:$PORT/medium.bin"
    
    # Concurrent connections test
    echo "----------------------------------------"
    echo "Concurrent Connections Test"
    echo "----------------------------------------"
    CONNECTIONS=500
    run_wrk_benchmark "concurrent" "http://localhost:$PORT/$TEST_FILE"
    CONNECTIONS=100
    
    # High latency test
    echo "----------------------------------------"
    echo "High Load Test"
    echo "----------------------------------------"
    CONNECTIONS=1000
    THREADS=8
    run_wrk_benchmark "highload" "http://localhost:$PORT/$TEST_FILE"
    
    stop_server
    
    echo "========================================"
    echo "Benchmark Complete"
    echo "========================================"
}

# Show usage
usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -t N    Number of threads (default: 4)"
    echo "  -c N    Number of connections (default: 100)"
    echo "  -d N    Duration in seconds (default: 10)"
    echo "  -p N    Server port (default: 18080)"
    echo "  -h      Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                 # Run with defaults"
    echo "  $0 -t 8 -c 500    # 8 threads, 500 connections"
    echo "  $0 -d 30          # 30 second test"
}

# Parse arguments
while getopts "t:c:d:p:h" opt; do
    case $opt in
        t) THREADS=$OPTARG ;;
        c) CONNECTIONS=$OPTARG ;;
        d) DURATION=$OPTARG ;;
        p) PORT=$OPTARG ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

# Check server exists
if [ ! -f "$SERVER" ]; then
    log_info "Building server..."
    cd "$SCRIPT_DIR/.."
    make
fi

# Run benchmarks
trap stop_server EXIT
run_benchmarks
