#!/bin/bash
# Stress Tests - High concurrency, memory leaks, resource exhaustion
# Tests server stability under heavy load

source "$(dirname "$0")/../utils/common.sh"

log_section "Stress Tests"

# =============================================================================
# Configuration
# =============================================================================
STRESS_DURATION=${STRESS_DURATION:-30}  # seconds
CONCURRENT_CONNECTIONS=${CONCURRENT_CONNECTIONS:-50}
REQUESTS_PER_CONNECTION=${REQUESTS_PER_CONNECTION:-100}

log_info "Stress test configuration:"
log_info "  Duration: ${STRESS_DURATION}s"
log_info "  Concurrent connections: $CONCURRENT_CONNECTIONS"
log_info "  Requests per connection: $REQUESTS_PER_CONNECTION"

# Create test data directory
mkdir -p "$TEST_DATA_DIR/stress"
echo "Stress test content" > "$TEST_DATA_DIR/stress/test.txt"
dd if=/dev/urandom of="$TEST_DATA_DIR/stress/random.bin" bs=1K count=100 2>/dev/null

# =============================================================================
# Test 1: Connection Storm
# =============================================================================
log_info "Test 1: Connection Storm ($CONCURRENT_CONNECTIONS rapid connections)"

start_test_server || exit 1

# Monitor server memory before
if [ -f /proc/$(pgrep anx)/status ] 2>/dev/null; then
    MEM_BEFORE=$(grep VmRSS /proc/$(pgrep anx)/status | awk '{print $2}')
    log_info "Server memory before test: ${MEM_BEFORE}KB"
fi

# Rapid connection test
CONNECT_SUCCESS=0
CONNECT_FAIL=0
START_TIME=$(date +%s)

log_info "Opening $CONCURRENT_CONNECTIONS connections..."
for i in $(seq 1 $CONCURRENT_CONNECTIONS); do
    if curl -s --connect-timeout 2 -o /dev/null "$BASE_URL/stress/test.txt" 2>/dev/null; then
        CONNECT_SUCCESS=$((CONNECT_SUCCESS + 1))
    else
        CONNECT_FAIL=$((CONNECT_FAIL + 1))
    fi
    
    # Progress indicator every 10 connections
    if [ $((i % 10)) -eq 0 ]; then
        echo -n "."
    fi
done
echo ""

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
SUCCESS_RATE=$((CONNECT_SUCCESS * 100 / CONCURRENT_CONNECTIONS))

log_info "Connection storm completed in ${DURATION}s"
log_info "  Successful: $CONNECT_SUCCESS"
log_info "  Failed: $CONNECT_FAIL"
log_info "  Success rate: ${SUCCESS_RATE}%"

if [ $SUCCESS_RATE -gt 80 ]; then
    log_pass "Connection storm: ${SUCCESS_RATE}% success rate"
else
    log_fail "Connection storm: only ${SUCCESS_RATE}% success rate"
fi

# Check memory after
if [ -f /proc/$(pgrep anx)/status ] 2>/dev/null; then
    MEM_AFTER=$(grep VmRSS /proc/$(pgrep anx)/status | awk '{print $2}')
    log_info "Server memory after test: ${MEM_AFTER}KB"
    MEM_DIFF=$((MEM_AFTER - MEM_BEFORE))
    if [ $MEM_DIFF -gt 10240 ]; then  # 10MB threshold
        log_warn "Memory increased by ${MEM_DIFF}KB"
    else
        log_pass "Memory usage stable"
    fi
fi

stop_test_server
sleep 2

# =============================================================================
# Test 2: Sustained Load Test
# =============================================================================
log_info "Test 2: Sustained Load (${STRESS_DURATION}s duration)"

start_test_server || exit 1

TOTAL_REQUESTS=0
FAILED_REQUESTS=0
START_TIME=$(date +%s)
END_TIME=$((START_TIME + STRESS_DURATION))

log_info "Sending requests for ${STRESS_DURATION} seconds..."

while [ $(date +%s) -lt $END_TIME ]; do
    if curl -s --max-time 3 -o /dev/null "$BASE_URL/stress/test.txt" 2>/dev/null; then
        TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
    else
        FAILED_REQUESTS=$((FAILED_REQUESTS + 1))
    fi
    
    # Progress every 100 requests
    if [ $((TOTAL_REQUESTS % 100)) -eq 0 ]; then
        echo -n "."
    fi
done
echo ""

ACTUAL_DURATION=$(($(date +%s) - START_TIME))
RPS=$((TOTAL_REQUESTS / ACTUAL_DURATION))
FAIL_RATE=$((FAILED_REQUESTS * 100 / (TOTAL_REQUESTS + FAILED_REQUESTS)))

log_info "Sustained load test completed"
log_info "  Duration: ${ACTUAL_DURATION}s"
log_info "  Total requests: $TOTAL_REQUESTS"
log_info "  Failed requests: $FAILED_REQUESTS"
log_info "  Requests/sec: $RPS"
log_info "  Failure rate: ${FAIL_RATE}%"

if [ $FAIL_RATE -lt 5 ]; then
    log_pass "Sustained load: ${FAIL_RATE}% failure rate"
else
    log_fail "Sustained load: ${FAIL_RATE}% failure rate"
fi

stop_test_server
sleep 2

# =============================================================================
# Test 3: Large File Transfer Stress
# =============================================================================
log_info "Test 3: Large File Transfer Stress"

start_test_server || exit 1

# Create various sized files
for size in 1 10 50; do
    dd if=/dev/urandom of="$TEST_DATA_DIR/stress/large_${size}mb.bin" bs=1M count=$size 2>/dev/null
    log_info "Created ${size}MB test file"
done

# Test large file downloads
for size in 1 10 50; do
    FILE="$TEST_DATA_DIR/stress/large_${size}mb.bin"
    FILE_SIZE=$(stat -c%s "$FILE" 2>/dev/null || stat -f%z "$FILE" 2>/dev/null)
    
    log_info "Downloading ${size}MB file..."
    START=$(date +%s)
    
    if curl -s --max-time 60 -o "$TEST_RESULTS_DIR/downloaded_${size}mb.bin" \
            "$BASE_URL/stress/large_${size}mb.bin" 2>/dev/null; then
        END=$(date +%s)
        DURATION=$((END - START))
        THROUGHPUT=$((size * 1024 / (DURATION + 1)))
        
        log_info "  Downloaded in ${DURATION}s (${THROUGHPUT} KB/s)"
        
        # Verify file integrity
        if [ -f "$TEST_RESULTS_DIR/downloaded_${size}mb.bin" ]; then
            DOWNLOADED_SIZE=$(stat -c%s "$TEST_RESULTS_DIR/downloaded_${size}mb.bin" 2>/dev/null || stat -f%z "$TEST_RESULTS_DIR/downloaded_${size}mb.bin" 2>/dev/null)
            if [ "$DOWNLOADED_SIZE" == "$FILE_SIZE" ]; then
                log_pass "${size}MB file transfer complete and verified"
            else
                log_fail "${size}MB file size mismatch (expected $FILE_SIZE, got $DOWNLOADED_SIZE)"
            fi
            rm -f "$TEST_RESULTS_DIR/downloaded_${size}mb.bin"
        fi
    else
        log_fail "Failed to download ${size}MB file"
    fi
done

stop_test_server
sleep 2

# =============================================================================
# Test 4: Connection Leak Detection
# =============================================================================
log_info "Test 4: Connection Leak Detection"

start_test_server || exit 1

# Get initial connection count (if possible)
INITIAL_CONN_COUNT=$(ss -tan 2>/dev/null | grep :$TEST_PORT | wc -l)
log_info "Initial connection count: $INITIAL_CONN_COUNT"

# Open and close many connections
log_info "Opening and closing 100 connections..."
for i in $(seq 1 100); do
    curl -s --connect-timeout 2 -o /dev/null "$BASE_URL/stress/test.txt" 2>/dev/null
    # Small delay to prevent overwhelming
    if [ $((i % 10)) -eq 0 ]; then
        sleep 0.1
    fi
done

# Wait a bit for connections to close
sleep 2

# Check connection count again
FINAL_CONN_COUNT=$(ss -tan 2>/dev/null | grep :$TEST_PORT | wc -l)
log_info "Final connection count: $FINAL_CONN_COUNT"

if [ $FINAL_CONN_COUNT -le $((INITIAL_CONN_COUNT + 5)) ]; then
    log_pass "No connection leak detected"
else
    log_warn "Possible connection leak (initial: $INITIAL_CONN_COUNT, final: $FINAL_CONN_COUNT)"
fi

stop_test_server
sleep 2

# =============================================================================
# Test 5: Slowloris Attack Simulation
# =============================================================================
log_info "Test 5: Slowloris Attack Simulation (partial requests)"

start_test_server || exit 1

log_info "Sending 20 partial/slow HTTP requests..."
SLOWLORIS_SUCCESS=0

for i in $(seq 1 20); do
    # Send partial HTTP request
    (
        exec 3<>/dev/tcp/localhost/$TEST_PORT
        echo -e "GET /stress/test.txt HTTP/1.1\r" >&3
        echo -e "Host: localhost\r" >&3
        # Don't complete the request
        sleep 1
        exec 3>&-
    ) 2>/dev/null &
    
    SLOWLORIS_SUCCESS=$((SLOWLORIS_SUCCESS + 1))
done

wait
sleep 2

# Verify server is still responsive
if curl -s --max-time 5 -o /dev/null "$BASE_URL/stress/test.txt" 2>/dev/null; then
    log_pass "Server survived slowloris attack and remains responsive"
else
    log_warn "Server may be affected by slowloris attack"
fi

stop_test_server
sleep 2

# =============================================================================
# Test 6: Memory Usage Monitoring
# =============================================================================
log_info "Test 6: Memory Usage Under Load"

start_test_server || exit 1

# Get server PID
SERVER_PID=$(pgrep anx)
if [ -n "$SERVER_PID" ] && [ -f /proc/$SERVER_PID/status ]; then
    INITIAL_MEM=$(grep VmRSS /proc/$SERVER_PID/status | awk '{print $2}')
    log_info "Initial memory: ${INITIAL_MEM}KB"
    
    # Generate load
    log_info "Generating memory pressure..."
    for i in $(seq 1 50); do
        curl -s -o /dev/null "$BASE_URL/stress/large_1mb.bin" 2>/dev/null &
    done
    wait
    
    # Force garbage collection if possible
    sleep 2
    
    # Check memory again
    FINAL_MEM=$(grep VmRSS /proc/$SERVER_PID/status | awk '{print $2}')
    log_info "Final memory: ${FINAL_MEM}KB"
    
    MEM_INCREASE=$((FINAL_MEM - INITIAL_MEM))
    INCREASE_PERCENT=$((MEM_INCREASE * 100 / INITIAL_MEM))
    
    log_info "Memory increase: ${MEM_INCREASE}KB (${INCREASE_PERCENT}%)"
    
    if [ $INCREASE_PERCENT -lt 50 ]; then
        log_pass "Memory usage under control (${INCREASE_PERCENT}% increase)"
    else
        log_warn "Significant memory increase (${INCREASE_PERCENT}%)"
    fi
else
    log_skip "Memory monitoring (cannot access /proc)"
fi

stop_test_server

# =============================================================================
# Cleanup
# =============================================================================
rm -rf "$TEST_DATA_DIR/stress"

# =============================================================================
# Summary
# =============================================================================
log_info "Stress tests completed"
