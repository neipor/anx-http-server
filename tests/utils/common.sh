#!/bin/bash
# ANX Test Framework - Common Utilities
# Source this file in all test scripts

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Timing
TEST_START_TIME=0
SUITE_START_TIME=0

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"  # Go up 2 levels from utils/
TESTS_DIR="$PROJECT_DIR/tests"  # Tests directory
BUILD_DIR="$PROJECT_DIR/build"
SERVER_BIN="$BUILD_DIR/anx"
TEST_DATA_DIR="$TESTS_DIR/data"
TEST_RESULTS_DIR="$TESTS_DIR/results"

# Server settings
TEST_PORT=18080
TEST_HOST="localhost"
BASE_URL="http://$TEST_HOST:$TEST_PORT"

# Create results directory
mkdir -p "$TEST_RESULTS_DIR"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_section() {
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}"
}

# Timer functions
start_timer() {
    TEST_START_TIME=$(date +%s)
}

stop_timer() {
    local end_time=$(date +%s)
    local duration=$((end_time - TEST_START_TIME))
    echo "${duration}s"
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [ "$expected" == "$actual" ]; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (expected: $expected, got: $actual)"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-Assertion failed}"
    
    if echo "$haystack" | grep -q "$needle"; then
        log_pass "$message"
        return 0
    else
        log_fail "$message (expected to contain: $needle)"
        return 1
    fi
}

assert_status_code() {
    local url="$1"
    local expected="$2"
    local actual
    
    actual=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    assert_equals "$expected" "$actual" "HTTP status for $url"
}

assert_server_running() {
    if curl -s --connect-timeout 2 "$BASE_URL" >/dev/null 2>&1; then
        return 0
    else
        log_fail "Server not responding at $BASE_URL"
        return 1
    fi
}

# Server management
start_test_server() {
    local port="${1:-$TEST_PORT}"
    local docroot="${2:-$TEST_DATA_DIR}"
    local log_file="$TEST_RESULTS_DIR/server.log"
    
    # Check if server binary exists
    if [ ! -f "$SERVER_BIN" ]; then
        log_fail "Server binary not found: $SERVER_BIN"
        return 1
    fi
    
    # Create test data directory if not exists
    mkdir -p "$docroot"
    
    # Start server
    "$SERVER_BIN" -p "$port" -d "$docroot" > "$log_file" 2>&1 &
    local pid=$!
    echo $pid > "$TEST_RESULTS_DIR/server.pid"
    
    # Wait for server to start
    local attempts=0
    while [ $attempts -lt 10 ]; do
        if curl -s --connect-timeout 1 "http://$TEST_HOST:$port" >/dev/null 2>&1; then
            log_info "Server started on port $port (PID: $pid)"
            return 0
        fi
        sleep 0.5
        ((attempts++))
    done
    
    log_fail "Server failed to start within 5 seconds"
    return 1
}

stop_test_server() {
    if [ -f "$TEST_RESULTS_DIR/server.pid" ]; then
        local pid=$(cat "$TEST_RESULTS_DIR/server.pid")
        kill $pid 2>/dev/null || true
        rm -f "$TEST_RESULTS_DIR/server.pid"
        sleep 1
        log_info "Server stopped"
    fi
    pkill -f "anx.*$TEST_PORT" 2>/dev/null || true
}

# Cleanup
cleanup_test_env() {
    stop_test_server
    rm -rf "$TEST_DATA_DIR"
}

# Test summary
print_summary() {
    local duration="$1"
    
    echo ""
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN}Test Summary${NC}"
    echo -e "${CYAN}========================================${NC}"
    echo -e "Total Tests:  $TESTS_TOTAL"
    echo -e "${GREEN}Passed:       $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:       $TESTS_FAILED${NC}"
    echo -e "${YELLOW}Skipped:      $TESTS_SKIPPED${NC}"
    echo -e "Duration:     ${duration}s"
    echo -e "${CYAN}========================================${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed!${NC}"
        return 1
    fi
}

# Generate JSON report
generate_json_report() {
    local suite_name="$1"
    local duration="$2"
    local report_file="$TEST_RESULTS_DIR/${suite_name}_$(date +%Y%m%d_%H%M%S).json"
    
    cat > "$report_file" <<EOF
{
  "suite": "$suite_name",
  "timestamp": "$(date -Iseconds)",
  "version": "$(cat $PROJECT_DIR/src/version.s | grep msg_version | head -1 | cut -d'"' -f2)",
  "results": {
    "total": $TESTS_TOTAL,
    "passed": $TESTS_PASSED,
    "failed": $TESTS_FAILED,
    "skipped": $TESTS_SKIPPED
  },
  "duration_seconds": $duration,
  "success_rate": $(echo "scale=2; $TESTS_PASSED * 100 / $TESTS_TOTAL" | bc -l 2>/dev/null || echo "0")
}
EOF
    log_info "JSON report saved to: $report_file"
}

# Check dependencies
check_dependency() {
    local cmd="$1"
    local name="${2:-$1}"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        return 0
    else
        log_warn "$name not found, some tests will be skipped"
        return 1
    fi
}

# Export all functions
export -f log_info log_pass log_fail log_skip log_warn log_section
export -f start_timer stop_timer
export -f assert_equals assert_contains assert_status_code assert_server_running
export -f start_test_server stop_test_server cleanup_test_env
export -f print_summary generate_json_report check_dependency

# Export variables
export TEST_PORT TEST_HOST BASE_URL
export SCRIPT_DIR PROJECT_DIR TESTS_DIR BUILD_DIR SERVER_BIN
export TEST_DATA_DIR TEST_RESULTS_DIR
