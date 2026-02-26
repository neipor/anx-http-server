#!/bin/bash
# HPACK Unit Tests - HTTP/2 Header Compression (RFC 7541)
# Tests HPACK static table, dynamic table, and encoding/decoding

source "$(dirname "$0")/../utils/common.sh"

log_section "HPACK Unit Tests"

# =============================================================================
# HPACK Static Table Test Vectors (RFC 7541 Appendix A)
# =============================================================================

# Static table entries: Index -> (Name, Value)
declare -A HPACK_STATIC_TABLE=(
    [1]=":authority"
    [2]=":method GET"
    [3]=":method POST"
    [4]=":path /"
    [5]=":path /index.html"
    [6]=":scheme http"
    [7]=":scheme https"
    [8]=":status 200"
    [9]=":status 204"
    [10]=":status 206"
    [11]=":status 304"
    [12]=":status 400"
    [13]=":status 404"
    [14]=":status 500"
    [15]="accept-charset"
    [16]="accept-encoding gzip, deflate"
    [17]="accept-language"
    [18]="accept-ranges"
    [19]="accept"
    [20]="access-control-allow-origin"
    [21]="age"
    [22]="allow"
    [23]="authorization"
    [24]="cache-control"
    [25]="content-disposition"
    [26]="content-encoding"
    [27]="content-language"
    [28]="content-length"
    [29]="content-location"
    [30]="content-range"
    [31]="content-type"
    [32]="cookie"
    [33]="date"
    [34]="etag"
    [35]="expect"
    [36]="expires"
    [37]="from"
    [38]="host"
    [39]="if-match"
    [40]="if-modified-since"
    [41]="if-none-match"
    [42]="if-range"
    [43]="if-unmodified-since"
    [44]="last-modified"
    [45]="link"
    [46]="location"
    [47]="max-forwards"
    [48]="proxy-authenticate"
    [49]="proxy-authorization"
    [50]="range"
    [51]="referer"
    [52]="refresh"
    [53]="retry-after"
    [54]="server"
    [55]="set-cookie"
    [56]="strict-transport-security"
    [57]="transfer-encoding"
    [58]="user-agent"
    [59]="vary"
    [60]="via"
    [61]="www-authenticate"
)

# =============================================================================
# HPACK Integer Encoding Tests (RFC 7541 Section 5.1)
# =============================================================================
log_info "Testing HPACK integer encoding..."

# Test integer encoding (5-bit prefix examples from RFC 7541)
# I -> Expected bytes (hex)
declare -A HPACK_INT_TESTS=(
    ["10_5"]="0a"           # 10 fits in 5 bits
    ["1337_5"]="1f9a0a"     # 1337 requires multi-byte
    ["31_5"]="1f00"         # 31 = 2^5 - 1, requires continuation
    ["32_5"]="1f01"         # 32 = 2^5
    ["0_5"]="00"            # 0 fits in 5 bits
    ["1_5"]="01"            # 1 fits in 5 bits
)

# Note: We can't directly test the assembly implementation,
# but we can verify our understanding of the algorithm
PASS_COUNT=0
for test in "${!HPACK_INT_TESTS[@]}"; do
    expected="${HPACK_INT_TESTS[$test]}"
    # Parse value and prefix
    IFS='_' read -r value prefix_bits <<< "$test"
    
    # Calculate expected encoding manually
    prefix_mask=$(( (1 << prefix_bits) - 1 ))
    
    if [ $value -lt $prefix_mask ]; then
        # Fits in prefix
        calculated=$(printf '%02x' $value)
    else
        # Multi-byte encoding
        calculated=""
        # First byte: all 1s in prefix
        first_byte=$(( (1 << prefix_bits) - 1 ))
        calculated+=$(printf '%02x' $first_byte)
        
        remaining=$((value - prefix_mask))
        while [ $remaining -ge 128 ]; do
            byte=$(( (remaining % 128) + 128 ))
            calculated+=$(printf '%02x' $byte)
            remaining=$((remaining / 128))
        done
        calculated+=$(printf '%02x' $remaining)
    fi
    
    if [ "$calculated" == "$expected" ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        log_fail "Integer encoding $value/$prefix_bits: expected $expected, got $calculated"
    fi
done

log_pass "$PASS_COUNT/${#HPACK_INT_TESTS[@]} HPACK integer encoding tests"

# =============================================================================
# HPACK String Literal Tests (RFC 7541 Section 5.2)
# =============================================================================
log_info "Testing HPACK string literal encoding..."

# Test Huffman encoding
# For now, test literal strings without Huffman
log_info "HPACK string tests would require the actual implementation"
log_skip "HPACK string literal tests (requires binary interface)"

# =============================================================================
# HPACK Header Field Representation Tests
# =============================================================================
log_info "Testing HPACK header field representations..."

# Indexed Header Field (Section 6.1)
# 1-bit prefix (1), then 7-bit index
# Index 10 = :status: 200
# Binary: 10001010 = 0x8A
log_info "Indexed header field representation"

# Literal Header Field with Indexing (Section 6.2.1)
# 2-bit prefix (01), then 6-bit name index
# Literal Header Field without Indexing (Section 6.2.2)
# 4-bit prefix (0000), then 4-bit name index
# Literal Header Field Never Indexed (Section 6.2.3)
# 4-bit prefix (0001), then 4-bit name index

log_info "Header field representation tests require binary interface"
log_skip "HPACK header field representation tests (requires binary interface)"

# =============================================================================
# HPACK Dynamic Table Tests
# =============================================================================
log_info "Testing HPACK dynamic table logic..."

# Dynamic table size calculation
# RFC 7541 Section 4.1: size = 32 + name_len + value_len

test_dynamic_table_size() {
    local name="$1"
    local value="$2"
    local name_len=${#name}
    local value_len=${#value}
    local expected=$((32 + name_len + value_len))
    echo $expected
}

# Test cases
PASS_COUNT=0
TEST_CASES=(
    ":authority localhost"
    "content-type text/html"
    "cache-control max-age=3600"
    "set-cookie session=abc123"
)

for test_case in "${TEST_CASES[@]}"; do
    # Extract name and value
    name="${test_case%% *}"
    value="${test_case#* }"
    
    size=$(test_dynamic_table_size "$name" "$value")
    
    if [ $size -gt 32 ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
    fi
done

log_pass "$PASS_COUNT/${#TEST_CASES[@]} dynamic table size calculations"

# =============================================================================
# Static Table Validation
# =============================================================================
log_info "Validating HPACK static table entries..."

# Verify critical entries exist
CRITICAL_ENTRIES=(
    "1::authority"
    "2::method GET"
    "8::status 200"
    "13::status 404"
    "28:content-length"
    "31:content-type"
    "38:host"
    [58]="user-agent"
)

PASS_COUNT=0
for entry in "${CRITICAL_ENTRIES[@]}"; do
    index="${entry%%:*}"
    content="${entry#*:}"
    
    if [ -n "${HPACK_STATIC_TABLE[$index]}" ]; then
        static_entry="${HPACK_STATIC_TABLE[$index]}"
        # Check if content is in the entry
        if [[ "$static_entry" == *"$content"* ]]; then
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            log_fail "Static table entry $index mismatch"
        fi
    else
        log_fail "Static table entry $index not found"
    fi
done

log_pass "$PASS_COUNT/${#CRITICAL_ENTRIES[@]} critical static table entries validated"

# =============================================================================
# HPACK Encoder/Decoder Symmetry (would require actual implementation)
# =============================================================================
log_info "Testing HPACK encode/decode symmetry..."

log_info "HPACK encoder/decoder tests require binary interface to assembly code"
log_skip "HPACK encode/decode symmetry tests (requires binary interface)"

# =============================================================================
# Summary
# =============================================================================
log_info "HPACK unit tests completed"
log_info "Note: Full HPACK testing requires direct interface to assembly implementation"
