# ANX Web Server - Complete Test Documentation

## 📋 Test Suite Overview

ANX Web Server now includes comprehensive testing infrastructure with two main test suites:

### 1. Standard Test Suite (30 minutes)
Located at: `tests/run_standard_tests.sh`

**Purpose**: Daily development and CI/CD validation

**Coverage**:
- Build verification
- Unit tests (SIMD, Crypto, HPACK)
- HTTP/1.1 integration tests
- WebSocket handshake
- Performance benchmarks
- Quick security scan

**Expected Results**:
- ~50 test cases
- >95% pass rate
- RPS > 40,000 (HTTP/1.1)
- No critical security issues

### 2. Comprehensive Test Suite (2 hours)
Located at: `tests/run_comprehensive_tests.sh`

**Purpose**: Release validation and regression testing

**Coverage**:
- All standard tests
- HTTP/2 deep testing (h2load)
- Full WebSocket testing
- SIMD verification (all buffer sizes)
- Cryptographic vector tests
- Stress testing (1K-10K concurrent)
- Security penetration testing
- Memory leak detection (Valgrind)
- Performance comparison (vs nginx)

**Expected Results**:
- ~200 test cases
- >98% pass rate
- HTTP/1.1 RPS > 50,000
- HTTP/2 RPS > 30,000
- SIMD memcpy > 30 GB/s
- 0 memory leaks

---

## 🚀 Quick Start

### Run Standard Tests
```bash
cd /home/hu/code/aarch64_http_server
./tests/run_standard_tests.sh
```

### Run Comprehensive Tests
```bash
cd /home/hu/code/aarch64_http_server
./tests/run_comprehensive_tests.sh
```

### Run Quick Test Only
```bash
./tests/quick_test.sh
```

---

## 📁 Test Directory Structure

```
tests/
├── run_standard_tests.sh         # Main entry: Standard suite
├── run_comprehensive_tests.sh    # Main entry: Comprehensive suite
├── quick_test.sh                 # Quick sanity check
├── run_tests.sh                  # Legacy test suite
├── utils/
│   └── common.sh                 # Test framework utilities
├── unit/                         # Unit tests
│   ├── test_simd.sh             # SIMD function tests
│   ├── test_crypto.sh           # Crypto algorithm tests
│   └── test_hpack.sh            # HPACK encoding tests
├── integration/                  # Integration tests
│   ├── test_http1.sh            # HTTP/1.1 tests
│   ├── test_http2.sh            # HTTP/2 tests
│   └── test_websocket.sh        # WebSocket tests
├── performance/                  # Performance benchmarks
│   ├── benchmark_throughput.sh  # Throughput tests
│   └── benchmark_latency.sh     # Latency tests
├── security/                     # Security tests
│   ├── test_path_traversal.sh   # Path traversal tests
│   ├── test_dos.sh              # DoS protection tests
│   └── test_input_validation.sh # Input validation tests
├── stress/                       # Stress tests
│   ├── test_load.sh             # Load testing
│   └── test_stability.sh        # Long-running tests
└── results/                      # Test results
    ├── *.json                   # JSON reports
    ├── *.html                   # HTML reports
    └── *.log                    # Log files
```

---

## 🔧 Test Framework Features

### Built-in Utilities

#### Logging Functions
```bash
log_info "Message"    # Blue [INFO]
log_pass "Message"    # Green [PASS]
log_fail "Message"    # Red [FAIL]
log_warn "Message"    # Yellow [WARN]
log_skip "Message"    # Yellow [SKIP]
log_section "Title"   # Cyan header
```

#### Assertion Functions
```bash
assert_equals "expected" "actual" "message"
assert_contains "haystack" "needle" "message"
assert_status_code "URL" "200"
assert_server_running
```

#### Server Management
```bash
start_test_server [port] [docroot]
stop_test_server
cleanup_test_env
```

#### Reporting
```bash
generate_json_report "suite_name" duration
print_summary duration
```

---

## 📊 Test Categories

### Level 1: Build Tests
- Clean build verification
- Static linking check
- Binary size validation
- Dependency check

### Level 2: Unit Tests
**SIMD Module**:
- Aligned/unaligned memory copy
- Buffer size boundaries (0, 1, 64, 127, 128, 129, 1024, 8192, 65536)
- Memset functionality
- Auto-selection (scalar vs SIMD)

**Crypto Module**:
- SHA1 known vectors (RFC 3174)
- Base64 encoding/decoding
- WebSocket accept key generation

**HPACK Module**:
- Integer encoding/decoding
- String literal encoding
- Dynamic table operations

### Level 3: Integration Tests
**HTTP/1.1**:
- GET/HEAD methods
- Static file serving
- Directory listing
- MIME type detection
- Keep-Alive connections
- Concurrent requests (100-1000)

**HTTP/2**:
- Connection preface
- SETTINGS exchange
- HEADERS frame processing
- DATA frame streaming
- Stream multiplexing (100 concurrent streams)
- Flow control
- HPACK compression

**WebSocket**:
- Handshake validation (RFC 6455)
- Frame parsing
- Text/binary messages
- Ping/Pong heartbeat
- Close handshake

### Level 4: Performance Tests
**Metrics**:
- Requests per second (RPS)
- Latency (P50, P99, P999)
- Memory usage per connection
- CPU utilization
- Throughput (MB/s)

**Tools**:
- curl (basic)
- wrk/wrk2 (HTTP/1.1)
- h2load (HTTP/2)
- Custom scripts

### Level 5: Security Tests
**Input Validation**:
- Path traversal (`../`, `%2e%2e`, encoding variations)
- NULL byte injection (`%00`)
- Long URLs (>2000 chars)
- Invalid UTF-8
- Control characters

**Attack Protection**:
- Slowloris (slow headers)
- Connection flooding
- Resource exhaustion
- HTTP request smuggling

### Level 6: Stress Tests
**Load Testing**:
- 1,000 concurrent connections
- 10,000 concurrent connections (if resources allow)
- 100,000 total requests
- Sustained load (1 hour)

**Stability Testing**:
- 24-hour uptime test
- Memory leak detection (Valgrind)
- File descriptor exhaustion
- CPU throttling

### Level 7: Acceptance Tests
**Scenarios**:
- Static website hosting
- API backend
- File upload/download
- Real-time WebSocket chat
- Reverse proxy configuration

**Comparison**:
- vs nginx (same hardware)
- vs Apache
- Previous ANX versions

---

## 🔍 Expected Performance Benchmarks

### HTTP/1.1
```
Small files (1KB):
- Target: >50,000 RPS
- Latency P99: <5ms

Medium files (100KB):
- Target: >10,000 RPS
- Throughput: >1GB/s

Large files (1MB):
- Target: >1,000 RPS
- Throughput: >10GB/s (sendfile)
```

### HTTP/2
```
Multiplexing (100 streams):
- Target: >30,000 RPS aggregate
- Latency P99: <10ms

Single stream:
- Target: ~80% of HTTP/1.1 performance
```

### SIMD Operations
```
memcpy:
- Small (<128B): ~5 GB/s (scalar)
- Large (≥128B): >30 GB/s (SIMD)
- Huge (>1MB): >40 GB/s

memset:
- Similar to memcpy performance
```

### Resource Usage
```
Memory per 1000 connections:
- Target: <10MB

CPU utilization at max load:
- Target: >80% (efficient)
- Ideal: 100% (no bottlenecks)
```

---

## 🐛 Debugging Failed Tests

### Build Failures
```bash
# Check build log
cat tests/results/build.log

# Manual build
make clean
make -j$(nproc) 2>&1 | tee build.log

# Check for missing dependencies
ldd build/anx  # Should show "not a dynamic executable"
```

### Server Won't Start
```bash
# Check if port is in use
sudo lsof -i :18080

# Check server logs
cat tests/results/server.log

# Try different port
./build/anx -p 18081 -d www
```

### Test Failures
```bash
# Run specific test with debug
bash -x tests/unit/test_simd.sh

# Check test results
cat tests/results/*.log

# Manual curl test
curl -v http://localhost:18080/
```

### Memory Issues
```bash
# Run with Valgrind
valgrind --leak-check=full ./build/anx -p 18080 -d www

# Check memory usage
watch -n 1 'ps aux | grep anx'
```

---

## 📈 Continuous Integration

### GitHub Actions Example
```yaml
name: Test Suite

on: [push, pull_request]

jobs:
  standard-tests:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - name: Install dependencies
      run: sudo apt-get install -y curl valgrind
    
    - name: Run standard tests
      run: ./tests/run_standard_tests.sh
    
    - name: Upload results
      uses: actions/upload-artifact@v2
      with:
        name: test-results
        path: tests/results/
```

### Pre-commit Hook
```bash
#!/bin/bash
# .git/hooks/pre-commit

./tests/quick_test.sh || exit 1
```

---

## 📝 Test Checklist

### Before Commit
- [ ] Quick test passes
- [ ] No compiler warnings
- [ ] Code compiles on clean build

### Before PR
- [ ] Standard test suite passes (>95%)
- [ ] No memory leaks (Valgrind)
- [ ] Performance not degraded

### Before Release
- [ ] Comprehensive test suite passes (>98%)
- [ ] All security tests pass
- [ ] Stress test (1 hour) stable
- [ ] Performance meets targets
- [ ] Documentation updated

---

## 🎯 Test Priorities

**P0 (Critical)**: Must always pass
- Build verification
- HTTP/1.1 basic functionality
- Security (path traversal, injection)

**P1 (High)**: Should pass for releases
- HTTP/2 functionality
- SIMD optimization
- Memory leak free

**P2 (Medium)**: Nice to have
- Performance benchmarks
- WebSocket full tests
- TLS handshake

**P3 (Low)**: Optional
- Extreme stress tests (100K connections)
- Comparison with nginx
- Platform-specific tests

---

## 📞 Support

**Test Framework Issues**:
- Check `tests/results/*.log`
- Review `tests/utils/common.sh`
- Open issue with test output

**Performance Issues**:
- Run with `perf stat`
- Check `tests/results/*.json`
- Compare with baseline

**Security Concerns**:
- Run comprehensive security suite
- Review failed test details
- Check input validation

---

*Document Version: 1.0*  
*Last Updated: 2026-02-26*  
*Test Framework Version: v0.5.0*
