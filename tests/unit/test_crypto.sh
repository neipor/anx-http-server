#!/bin/bash
# Crypto Unit Tests - SHA1 and Base64 validation
# Tests cryptographic functions using known test vectors

source "$(dirname "$0")/../utils/common.sh"

log_section "Crypto Unit Tests"

# =============================================================================
# SHA1 Test Vectors (from RFC 3174, NIST examples)
# =============================================================================
declare -A SHA1_TESTS=(
    ["abc"]="a9993e364706816aba3e25717850c26c9cd0d89d"
    [""]="da39a3ee5e6b4b0d3255bfef95601890afd80709"
    ["abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"]="84983e441c3bd26ebaae4aa1f95129e5e54670f1"
    ["The quick brown fox jumps over the lazy dog"]="2fd4e1c67a2d28fced849ee1bb76e7391b93eb12"
    ["The quick brown fox jumps over the lazy cog"]="de9f2c7fd25e1b3afad3e85a0bd17d9b100db4b3"
)

# =============================================================================
# Base64 Test Vectors (from RFC 4648)
# =============================================================================
declare -A BASE64_TESTS=(
    [""]=""
    ["f"]="Zg=="
    ["fo"]="Zm8="
    ["foo"]="Zm9v"
    ["foob"]="Zm9vYg=="
    ["fooba"]="Zm9vYmE="
    ["foobar"]="Zm9vYmFy"
    ["Hello World"]="SGVsbG8gV29ybGQ="
    ["The quick brown fox jumps over the lazy dog."]="VGhlIHF1aWNrIGJyb3duIGZveCBqdW1wcyBvdmVyIHRoZSBsYXp5IGRvZy4="
)

# =============================================================================
# SHA1 Tests
# =============================================================================
log_info "Testing SHA1 hash function..."

# Check if we have sha1sum or shasum
if command -v sha1sum >/dev/null 2>&1; then
    SHA1_CMD="sha1sum"
elif command -v shasum >/dev/null 2>&1; then
    SHA1_CMD="shasum -a 1"
else
    log_skip "SHA1 test - no sha1sum or shasum available"
    SHA1_CMD=""
fi

if [ -n "$SHA1_CMD" ]; then
    PASS_COUNT=0
    FAIL_COUNT=0
    
    for input in "${!SHA1_TESTS[@]}"; do
        expected="${SHA1_TESTS[$input]}"
        # Use printf to handle special characters properly
        result=$(printf '%s' "$input" | $SHA1_CMD | awk '{print $1}')
        
        if [ "$result" == "$expected" ]; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            log_fail "SHA1('$input'): expected $expected, got $result"
        fi
    done
    
    if [ $FAIL_COUNT -eq 0 ]; then
        log_pass "All $PASS_COUNT SHA1 test vectors passed"
    else
        log_fail "$FAIL_COUNT SHA1 tests failed"
    fi
fi

# =============================================================================
# Base64 Tests
# =============================================================================
log_info "Testing Base64 encoding..."

# Check if we have base64
if command -v base64 >/dev/null 2>&1; then
    PASS_COUNT=0
    FAIL_COUNT=0
    
    for input in "${!BASE64_TESTS[@]}"; do
        expected="${BASE64_TESTS[$input]}"
        result=$(printf '%s' "$input" | base64 | tr -d '\n')
        
        if [ "$result" == "$expected" ]; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            log_fail "Base64('$input'): expected '$expected', got '$result'"
        fi
    done
    
    if [ $FAIL_COUNT -eq 0 ]; then
        log_pass "All $PASS_COUNT Base64 encoding tests passed"
    else
        log_fail "$FAIL_COUNT Base64 encoding tests failed"
    fi
    
    # Test Base64 decoding
    log_info "Testing Base64 decoding..."
    PASS_COUNT=0
    FAIL_COUNT=0
    
    for input in "${!BASE64_TESTS[@]}"; do
        expected="$input"
        encoded="${BASE64_TESTS[$input]}"
        result=$(printf '%s' "$encoded" | base64 -d)
        
        if [ "$result" == "$expected" ]; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
            log_fail "Base64 decode('$encoded'): mismatch"
        fi
    done
    
    if [ $FAIL_COUNT -eq 0 ]; then
        log_pass "All $PASS_COUNT Base64 decoding tests passed"
    else
        log_fail "$FAIL_COUNT Base64 decoding tests failed"
    fi
    
    # Test with binary data
    log_info "Testing Base64 with binary data..."
    # Create a 256-byte binary file with all byte values
    for i in $(seq 0 255); do
        printf "\\x$(printf '%02x' $i)"
    done > "$TEST_RESULTS_DIR/crypto_binary.bin"
    
    # Encode and decode
    base64 "$TEST_RESULTS_DIR/crypto_binary.bin" > "$TEST_RESULTS_DIR/crypto_encoded.b64"
    base64 -d "$TEST_RESULTS_DIR/crypto_encoded.b64" > "$TEST_RESULTS_DIR/crypto_decoded.bin"
    
    # Compare
    if diff -q "$TEST_RESULTS_DIR/crypto_binary.bin" "$TEST_RESULTS_DIR/crypto_decoded.bin" >/dev/null 2>&1; then
        log_pass "Base64 round-trip with 256 bytes of binary data"
    else
        log_fail "Base64 round-trip failed for binary data"
    fi
    
    # Cleanup
    rm -f "$TEST_RESULTS_DIR/crypto_binary.bin" "$TEST_RESULTS_DIR/crypto_encoded.b64" "$TEST_RESULTS_DIR/crypto_decoded.bin"
    
else
    log_skip "Base64 test - base64 command not available"
fi

# =============================================================================
# WebSocket Key Generation Test
# =============================================================================
log_info "Testing WebSocket key generation logic..."

# WebSocket handshake: key = base64(sha1(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
# Test with known example from RFC 6455
TEST_KEY="dGhlIHNhbXBsZSBub25jZQ=="
EXPECTED_ACCEPT="s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

# Calculate using system tools
MAGIC_STRING="258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
if command -v openssl >/dev/null 2>&1; then
    CALCULATED=$(printf '%s%s' "$TEST_KEY" "$MAGIC_STRING" | openssl sha1 -binary | base64 | tr -d '\n')
    
    if [ "$CALCULATED" == "$EXPECTED_ACCEPT" ]; then
        log_pass "WebSocket accept key calculation (RFC 6455 example)"
    else
        log_fail "WebSocket accept key: expected $EXPECTED_ACCEPT, got $CALCULATED"
    fi
else
    log_skip "WebSocket key test - openssl not available"
fi

# =============================================================================
# Performance Benchmarks
# =============================================================================
log_info "Running crypto performance benchmarks..."

# SHA1 performance test
if [ -n "$SHA1_CMD" ]; then
    log_info "SHA1 performance test (10MB of data)..."
    
    # Generate 10MB of test data
    dd if=/dev/urandom of="$TEST_RESULTS_DIR/crypto_perf.bin" bs=1M count=10 2>/dev/null
    
    START=$(date +%s%N)
    $SHA1_CMD "$TEST_RESULTS_DIR/crypto_perf.bin" >/dev/null
    END=$(date +%s%N)
    
    DURATION_NS=$((END - START))
    DURATION_MS=$((DURATION_NS / 1000000))
    THROUGHPUT=$((10000 / DURATION_MS))  # MB/s
    
    log_info "SHA1: ${DURATION_MS}ms for 10MB (${THROUGHPUT} MB/s)"
    
    if [ $THROUGHPUT -gt 50 ]; then
        log_pass "SHA1 throughput acceptable (>50 MB/s)"
    else
        log_warn "SHA1 throughput low: ${THROUGHPUT} MB/s"
    fi
    
    rm -f "$TEST_RESULTS_DIR/crypto_perf.bin"
fi

# Base64 performance test
if command -v base64 >/dev/null 2>&1; then
    log_info "Base64 performance test (10MB of data)..."
    
    # Generate 10MB of test data
    dd if=/dev/urandom of="$TEST_RESULTS_DIR/crypto_perf.bin" bs=1M count=10 2>/dev/null
    
    START=$(date +%s%N)
    base64 "$TEST_RESULTS_DIR/crypto_perf.bin" > "$TEST_RESULTS_DIR/crypto_perf.b64"
    END=$(date +%s%N)
    
    DURATION_NS=$((END - START))
    DURATION_MS=$((DURATION_NS / 1000000))
    THROUGHPUT=$((10000 / DURATION_MS))  # MB/s
    
    log_info "Base64 encode: ${DURATION_MS}ms for 10MB (${THROUGHPUT} MB/s)"
    
    # Cleanup
    rm -f "$TEST_RESULTS_DIR/crypto_perf.bin" "$TEST_RESULTS_DIR/crypto_perf.b64"
fi

log_info "Crypto unit tests completed"
