#!/bin/bash
# Security Penetration Tests
# Tests for common vulnerabilities, injection attacks, and fuzzing

source "$(dirname "$0")/../utils/common.sh"

log_section "Security Penetration Tests"

# Create test data
mkdir -p "$TEST_DATA_DIR/security"
echo "Test content" > "$TEST_DATA_DIR/security/index.html"
echo "Secret data" > "$TEST_DATA_DIR/security/.htpasswd"
echo "config=value" > "$TEST_DATA_DIR/security/config.ini"

# =============================================================================
# Test 1: Path Traversal Attacks
# =============================================================================
log_info "Test 1: Path Traversal Attacks"

start_test_server || exit 1

# Path traversal payloads
PATH_TRAVERSAL_PAYLOADS=(
    "../../../etc/passwd"
    "..%2f..%2f..%2fetc%2fpasswd"
    "..\\..\\..\\windows\\system32\\config\\sam"
    "....//....//....//etc/passwd"
    "%2e%2e/%2e%2e/%2e%2e/etc/passwd"
    "%252e%252e/%252e%252e/%252e%252e/etc/passwd"
    "..%c0%af..%c0%af..%c0%afetc/passwd"
    "..%5c..%5c..%5cwindows%5csystem.ini"
    "/etc/passwd"
    "/windows/system32/config/sam"
)

TRAVERSAL_BLOCKED=0
TRAVERSAL_PASSED=0

for payload in "${PATH_TRAVERSAL_PAYLOADS[@]}"; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/$payload" 2>/dev/null)
    
    # Should return 400, 403, or 404 (not 200)
    if [ "$RESPONSE" == "200" ]; then
        log_fail "Path traversal not blocked: $payload (HTTP 200)"
        TRAVERSAL_PASSED=$((TRAVERSAL_PASSED + 1))
    else
        TRAVERSAL_BLOCKED=$((TRAVERSAL_BLOCKED + 1))
    fi
done

log_info "Path traversal attacks: $TRAVERSAL_BLOCKED blocked, $TRAVERSAL_PASSED passed through"

if [ $TRAVERSAL_PASSED -eq 0 ]; then
    log_pass "All path traversal attacks blocked"
else
    log_warn "$TRAVERSAL_PASSED path traversal attempts may have succeeded"
fi

stop_test_server
sleep 2

# =============================================================================
# Test 2: HTTP Header Injection
# =============================================================================
log_info "Test 2: HTTP Header Injection"

start_test_server || exit 1

# Header injection payloads
HEADER_INJECTION_PAYLOADS=(
    "/index.html%0d%0aX-Injected: malicious"
    "/index.html%0aX-Injected: malicious"
    "/index.html%0dX-Injected: malicious"
)

for payload in "${HEADER_INJECTION_PAYLOADS[@]}"; do
    RESPONSE=$(curl -s -I "$BASE_URL$payload" 2>/dev/null)
    
    if echo "$RESPONSE" | grep -qi "X-Injected"; then
        log_fail "Header injection possible: $payload"
    else
        log_pass "Header injection blocked: ${payload:0:30}..."
    fi
done

stop_test_server
sleep 2

# =============================================================================
# Test 3: SQL Injection Simulation (URL Parameters)
# =============================================================================
log_info "Test 3: SQL Injection Patterns"

start_test_server || exit 1

SQL_PAYLOADS=(
    "/?id=1' OR '1'='1"
    "/?id=1; DROP TABLE users--"
    "/?id=1 UNION SELECT * FROM passwords"
    "/?id=1' AND 1=1--"
    "/?search='; exec xp_cmdshell('dir')--"
)

for payload in "${SQL_PAYLOADS[@]}"; do
    # URL encode the payload
    ENCODED_PAYLOAD=$(echo "$payload" | curl -Gso /dev/null -w %{url_effective} --data-urlencode "" "http://localhost/" 2>/dev/null | sed 's/.*\?//')
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$payload" 2>/dev/null)
    
    # Server should not crash or return 500
    if [ "$RESPONSE" == "500" ]; then
        log_warn "SQL injection may have caused server error: ${payload:0:40}"
    else
        log_info "SQL injection handled: ${payload:0:40}... (HTTP $RESPONSE)"
    fi
done

stop_test_server
sleep 2

# =============================================================================
# Test 4: Cross-Site Scripting (XSS) in URLs
# =============================================================================
log_info "Test 4: XSS Pattern Detection"

start_test_server || exit 1

XSS_PAYLOADS=(
    "/?q=<script>alert(1)</script>"
    "/?q=javascript:alert(1)"
    "/?q=<img src=x onerror=alert(1)>"
    "/?q='><script>alert(1)</script>"
    "/?q=<body onload=alert(1)>"
)

for payload in "${XSS_PAYLOADS[@]}"; do
    RESPONSE=$(curl -s "$BASE_URL$payload" 2>/dev/null)
    
    # Check if XSS payload is reflected without encoding
    if echo "$RESPONSE" | grep -qi "<script>"; then
        log_warn "Possible XSS (script tag not encoded): ${payload:0:40}"
    elif echo "$RESPONSE" | grep -qi "javascript:"; then
        log_warn "Possible XSS (javascript protocol): ${payload:0:40}"
    fi
done

log_pass "XSS pattern tests completed"

stop_test_server
sleep 2

# =============================================================================
# Test 5: Buffer Overflow / Long Input Tests
# =============================================================================
log_info "Test 5: Buffer Overflow Tests"

start_test_server || exit 1

# Test various long inputs
LONG_INPUT_TESTS=(
    "/$(python3 -c 'print("A"*1000)')"
    "/$(python3 -c 'print("A"*10000)')"
    "/?x=$(python3 -c 'print("B"*5000)')"
)

for url in "${LONG_INPUT_TESTS[@]}"; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$url" --max-time 5 2>/dev/null)
    
    if [ "$RESPONSE" == "000" ]; then
        log_fail "Server may have crashed on long input"
    elif [ "$RESPONSE" == "414" ]; then
        log_pass "URI Too Long (414) correctly returned"
    elif [ "$RESPONSE" == "413" ]; then
        log_pass "Payload Too Large (413) correctly returned"
    else
        log_info "Long input handled (HTTP $RESPONSE)"
    fi
done

stop_test_server
sleep 2

# =============================================================================
# Test 6: HTTP Method Fuzzing
# =============================================================================
log_info "Test 6: HTTP Method Fuzzing"

start_test_server || exit 1

HTTP_METHODS=(
    "DELETE"
    "PUT"
    "PATCH"
    "TRACE"
    "CONNECT"
    "OPTIONS"
    "CUSTOM"
    "INVALID"
    ""
)

for method in "${HTTP_METHODS[@]}"; do
    if [ -n "$method" ]; then
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X "$method" "$BASE_URL/security/index.html" 2>/dev/null)
    else
        RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X "" "$BASE_URL/security/index.html" 2>/dev/null)
    fi
    
    case "$RESPONSE" in
        405|501)
            log_pass "Method $method rejected (HTTP $RESPONSE)"
            ;;
        200)
            log_warn "Method $method accepted (HTTP 200)"
            ;;
        000)
            log_fail "Method $method may have crashed server"
            ;;
        *)
            log_info "Method $method returned HTTP $RESPONSE"
            ;;
    esac
done

stop_test_server
sleep 2

# =============================================================================
# Test 7: Malformed HTTP Requests
# =============================================================================
log_info "Test 7: Malformed HTTP Requests"

start_test_server || exit 1

# Send malformed requests using nc/telnet
echo "Testing malformed HTTP requests..."

# Request without HTTP version
(
    exec 3<>/dev/tcp/localhost/$TEST_PORT
    echo -e "GET /\r" >&3
    cat <&3 > "$TEST_RESULTS_DIR/malformed1.log" 2>/dev/null
    exec 3>&-
) 2>/dev/null

# Request with invalid characters
(
    exec 3<>/dev/tcp/localhost/$TEST_PORT
    echo -e "GET /index.html HTTP/1.1\r\nHost: localhost\r\n\x00\r\n" >&3
    cat <&3 > "$TEST_RESULTS_DIR/malformed2.log" 2>/dev/null
    exec 3>&-
) 2>/dev/null

sleep 1

# Check if server is still responsive
if curl -s -o /dev/null --max-time 5 "$BASE_URL/security/index.html" 2>/dev/null; then
    log_pass "Server survived malformed requests"
else
    log_fail "Server may have crashed on malformed requests"
fi

stop_test_server
sleep 2

# =============================================================================
# Test 8: File Extension Filtering
# =============================================================================
log_info "Test 8: Dangerous File Extension Access"

start_test_server || exit 1

# Try to access sensitive files
SENSITIVE_FILES=(
    "/.htpasswd"
    "/.htaccess"
    "/config.ini"
    "/web.config"
    "/admin.php"
    "/config.php"
    "/.env"
    "/.git/config"
    "/.svn/entries"
)

for file in "${SENSITIVE_FILES[@]}"; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/security$file" 2>/dev/null)
    
    if [ "$RESPONSE" == "200" ]; then
        log_warn "Sensitive file accessible: $file"
    else
        log_info "Sensitive file protected: $file (HTTP $RESPONSE)"
    fi
done

stop_test_server
sleep 2

# =============================================================================
# Test 9: Character Encoding Attacks
# =============================================================================
log_info "Test 9: Character Encoding Attacks"

start_test_server || exit 1

ENCODING_PAYLOADS=(
    "/%2e%2e/%2e%2e/%2e%2e/etc/passwd"      # Double URL encoding
    "/%252e%252e/%252e%252e/etc/passwd"    # Triple URL encoding
    "/..%c0%af../..%c0%af../etc/passwd"    # Unicode/UTF-8 encoding
    "/..%5c..%5c..%5cwindows%5csystem.ini" # Backslash encoding
    "/%uff0e%uff0e/%uff0e%uff0e/etc/passwd" # Full-width unicode
)

for payload in "${ENCODING_PAYLOADS[@]}"; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL$payload" 2>/dev/null)
    
    if [ "$RESPONSE" == "200" ]; then
        log_fail "Encoding attack succeeded: ${payload:0:40}"
    else
        log_info "Encoding attack blocked: ${payload:0:40}"
    fi
done

stop_test_server
sleep 2

# =============================================================================
# Test 10: Rate Limiting Detection
# =============================================================================
log_info "Test 10: Rate Limiting Detection"

start_test_server || exit 1

log_info "Sending 50 rapid requests to detect rate limiting..."
RATE_LIMITED=0
for i in $(seq 1 50); do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/security/index.html" 2>/dev/null)
    if [ "$RESPONSE" == "429" ]; then
        RATE_LIMITED=$((RATE_LIMITED + 1))
    fi
done

if [ $RATE_LIMITED -gt 0 ]; then
    log_pass "Rate limiting detected ($RATE_LIMITED requests blocked)"
else
    log_info "No rate limiting detected"
fi

stop_test_server

# =============================================================================
# Cleanup
# =============================================================================
rm -rf "$TEST_DATA_DIR/security"

# =============================================================================
# Summary
# =============================================================================
log_info "Security penetration tests completed"
