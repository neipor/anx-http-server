# ANX Web Server v0.6.0 Development Plan

**Version**: v0.6.0-alpha  
**Goal**: Complete HTTP/2, io_uring, and TLS Foundation  
**Timeline**: 8 weeks  
**Target Date**: April 2026

---

## Project State Analysis

### ✅ Currently Working (Production Ready)
- HTTP/1.1 complete implementation
- WebSocket handshake (RFC 6455)
- SHA-1 and Base64 crypto
- Epoll-based I/O multiplexing
- Static file serving with sendfile
- CGI and reverse proxy support

### ⚠️ Framework Only (Needs Completion)
- **io_uring**: Structures defined, all submission functions are empty stubs
- **HTTP/2**: Frame parsing complete, request/response handling incomplete
- **HPACK**: Integer encoding works, header field decoding incomplete
- **TLS**: Empty directory, not started

### 🔧 Partial Implementation
- **SIMD**: memcpy/memset working, strlen/strcmp reverted to scalar (bugs)

---

## Phase 1: HTTP/2 Completion (Weeks 1-3)

### Week 1: HPACK Decoder
**Priority**: Critical  
**Goal**: Complete HPACK header decompression

#### Tasks
1. **Implement hpack_decode** (`src/protocol/http2/hpack.s`)
   - Decode indexed header field representation
   - Decode literal header field with/without indexing
   - Decode dynamic table size update
   - Handle Huffman decoding (RFC 7541 Appendix C)

2. **Header Field Decoding** (`src/protocol/http2/hpack_impl.s`)
   - `hpack_decode_indexed`: Look up static/dynamic table by index
   - `hpack_decode_literal`: Decode name-value pairs
   - `hpack_decode_dynamic_update`: Update dynamic table size

3. **Huffman Decoding**
   - Implement HPACK Huffman table (RFC 7541 Appendix C)
   - Decode Huffman-encoded string literals
   - Handle EOS (End of String) symbol

#### Deliverables
- [ ] `hpack_decode()` function complete
- [ ] All HPACK representation types supported
- [ ] Unit tests for header decoding
- [ ] Performance: < 1μs per header field

#### Files to Modify
- `src/protocol/http2/hpack.s` (add decode logic)
- `src/protocol/http2/hpack_impl.s` (complete implementations)
- `tests/unit/test_hpack.sh` (expand tests)

---

### Week 2: HTTP/2 Request Processing
**Priority**: Critical  
**Goal**: Complete HTTP/2 to HTTP/1.1 request translation

#### Tasks
1. **Complete h2_handle_headers** (`src/protocol/http2/handler.s`)
   - Decode all pseudo-headers (:method, :scheme, :authority, :path)
   - Validate HTTP/2 request requirements
   - Build HTTP/1.1 request buffer from HTTP/2 headers
   - Route to appropriate handler (file, CGI, proxy)

2. **Request Validation** (`src/protocol/http2/handler.s`)
   - Check for mandatory pseudo-headers
   - Validate :method values
   - Handle :authority vs Host header
   - Reject malformed requests with appropriate error codes

3. **Stream State Management** (`src/protocol/http2/streams.s`)
   - Complete `h2_stream_send_response` stub
   - Implement `h2_stream_process_request` stub
   - Handle stream half-closure

#### Deliverables
- [ ] HTTP/2 HEADERS frame → HTTP/1.1 request buffer
- [ ] Request validation complete
- [ ] Stream processing integrated
- [ ] Integration test: HTTP/2 request → file serving

#### Files to Modify
- `src/protocol/http2/handler.s` (complete TODOs)
- `src/protocol/http2/streams.s` (implement stubs)

---

### Week 3: HTTP/2 Response Building
**Priority**: Critical  
**Goal**: Complete HTTP/2 response generation

#### Tasks
1. **Response Building** (`src/protocol/http2/response.s`)
   - Encode HTTP/1.1 response as HTTP/2 HEADERS frame
   - Convert status line to :status pseudo-header
   - Encode response headers using HPACK
   - Handle content-length and transfer-encoding

2. **DATA Frame Streaming** (`src/protocol/http2/streams.s`)
   - Build DATA frames for response body
   - Respect MAX_FRAME_SIZE setting
   - Implement flow control for DATA frames
   - Handle END_STREAM flag correctly

3. **Error Responses** (`src/protocol/http2/handler.s`)
   - HTTP/2 error codes mapping
   - RST_STREAM for stream errors
   - GOAWAY for connection errors

#### Deliverables
- [ ] HTTP/2 response generation working
- [ ] File serving via HTTP/2 functional
- [ ] CGI execution via HTTP/2 functional
- [ ] End-to-end HTTP/2 tests passing

#### Files to Modify
- `src/protocol/http2/response.s` (complete encoding)
- `src/protocol/http2/streams.s` (DATA frame handling)

---

## Phase 2: io_uring Completion (Weeks 4-5)

### Week 4: io_uring Core Implementation
**Priority**: High  
**Goal**: Complete io_uring ring operations

#### Tasks
1. **Ring Memory Mapping** (`src/io/uring.s`)
   - Complete `uring_init` TODO for mmap ring memory
   - Map SQ ring, CQ ring, and SQEs
   - Handle page alignment requirements
   - Setup kernel communication channels

2. **SQE Submission Functions** (`src/io/uring_impl.s`)
   - `uring_submit_read`: Queue read operation
   - `uring_submit_write`: Queue write operation
   - `uring_submit_accept`: Queue accept operation
   - `uring_submit_sendfile`: Queue sendfile operation

3. **Submission Queue Management**
   - Update SQ tail index
   - Handle SQ ring wrapping
   - Memory barrier for visibility
   - Batch submission optimization

#### Deliverables
- [ ] Ring memory mapped correctly
- [ ] All SQE submission functions working
- [ ] Basic I/O operations via io_uring
- [ ] Unit tests for ring operations

#### Files to Modify
- `src/io/uring.s` (complete init)
- `src/io/uring_impl.s` (implement stubs)

---

### Week 5: io_uring Completion Polling
**Priority**: High  
**Goal**: Complete io_uring event handling

#### Tasks
1. **CQE Polling** (`src/io/uring_impl.s`)
   - Complete `uring_poll` stub
   - Poll completion queue for events
   - Handle CQ ring wrapping
   - Batch process completions

2. **Event Handling**
   - Map CQE user_data to file descriptors
   - Handle errors (res < 0)
   - Update connection state
   - Trigger callbacks

3. **Engine Integration** (`src/io/engine.s`)
   - Auto-detect kernel version
   - Select io_uring for Linux 5.1+
   - Fallback to epoll for older kernels
   - Graceful degradation

#### Deliverables
- [ ] io_uring fully functional
- [ ] Event-driven I/O working
- [ ] Performance: 30-50% improvement over epoll
- [ ] Integration with HTTP/1.1 and HTTP/2

#### Files to Modify
- `src/io/uring_impl.s` (complete poll)
- `src/io/engine.s` (auto-selection)

---

## Phase 3: SIMD Optimization (Week 6)

### Week 6: Fix SIMD String Operations
**Priority**: Medium  
**Goal**: Re-enable NEON strlen/strcmp

#### Tasks
1. **Debug NEON strlen** (`src/core/simd.s`)
   - Find and fix alignment issues
   - Handle null byte detection
   - Fix early termination bugs
   - Compare with scalar implementation

2. **Debug NEON strcmp** (`src/core/simd.s`)
   - Fix comparison logic
   - Handle different length strings
   - Ensure proper return values
   - Edge case testing

3. **Re-enable in Wrapper** (`src/core/simd_wrapper.s`)
   - Remove scalar fallback
   - Set threshold appropriately
   - Benchmark performance
   - Regression testing

#### Deliverables
- [ ] NEON strlen working correctly
- [ ] NEON strcmp working correctly
- [ ] 2-3x performance improvement for string ops
- [ ] No regressions in existing tests

#### Files to Modify
- `src/core/simd.s` (fix bugs)
- `src/core/simd_wrapper.s` (re-enable)

---

## Phase 4: TLS Foundation (Weeks 7-8)

### Week 7: TLS Record Layer
**Priority**: Medium  
**Goal**: Implement TLS 1.3 record layer

#### Tasks
1. **TLS Structures** (`src/tls/tls_init.s` - new file)
   - Define TLS context structure
   - Setup TLS record header parsing
   - Define cipher suite constants
   - Create TLS state machine

2. **AES-GCM Implementation** (`src/tls/aes_gcm.s` - new file)
   - ARMv8 crypto extensions
   - AES encryption/decryption
   - GCM authenticated encryption
   - Optimized for AArch64

3. **Record Layer** (`src/tls/record.s` - new file)
   - TLSPlaintext parsing
   - TLSCiphertext building
   - Content type handling
   - Fragment management

#### Deliverables
- [ ] TLS record structures defined
- [ ] AES-GCM working with ARMv8 crypto
- [ ] Record parsing/building functional
- [ ] Unit tests for crypto operations

#### Files to Create
- `src/tls/tls_init.s`
- `src/tls/aes_gcm.s`
- `src/tls/record.s`

---

### Week 8: TLS Integration
**Priority**: Medium  
**Goal**: Basic TLS handshake framework

#### Tasks
1. **Handshake Framework** (`src/tls/handshake.s` - new file)
   - ClientHello parsing
   - ServerHello generation
   - Key exchange setup
   - Certificate handling stubs

2. **TLS Socket Wrapper** (`src/tls/tls_socket.s` - new file)
   - Wrap existing socket operations
   - Encrypt/decrypt data transparently
   - Handle TLS vs non-TLS connections
   - Integration with main loop

3. **Configuration** (`src/config.s`)
   - Add TLS certificate options
   - Add TLS key options
   - Add cipher suite configuration
   - TLS enable/disable flag

#### Deliverables
- [ ] TLS handshake framework
- [ ] Certificate loading working
- [ ] Basic HTTPS serving (self-signed)
- [ ] Configuration options integrated

#### Files to Create
- `src/tls/handshake.s`
- `src/tls/tls_socket.s`

---

## Performance Targets

### v0.6.0 Goals

| Metric | v0.5.0 (Current) | v0.6.0 Target | Improvement |
|--------|------------------|---------------|-------------|
| HTTP/1.1 RPS | ~43 (sequential) | 10,000 | 230x |
| HTTP/2 RPS | N/A | 5,000 | New feature |
| Memory/conn | ~10KB | <10KB | Maintain |
| P99 latency | TBD | <10ms | Define |
| io_uring syscalls | epoll level | -50% | Efficiency |

### Benchmarking
- **HTTP/1.1**: `wrk -t12 -c400 -d30s http://localhost:8080/`
- **HTTP/2**: `h2load -n100000 -c100 -m10 http://localhost:8080/`
- **TLS**: `openssl s_time -connect localhost:443`

---

## Testing Strategy

### Week-by-Week Testing

**Week 1-3 (HTTP/2)**:
- Unit tests for HPACK decoder
- Integration tests for HTTP/2 frames
- End-to-end HTTP/2 file serving
- h2load benchmark comparison

**Week 4-5 (io_uring)**:
- Unit tests for ring operations
- Syscall count comparison
- Throughput benchmarks
- Regression tests for epoll fallback

**Week 6 (SIMD)**:
- String operation benchmarks
- Correctness verification
- Performance comparison charts

**Week 7-8 (TLS)**:
- AES-GCM test vectors
- Handshake protocol tests
- Certificate validation
- OpenSSL compatibility tests

---

## Risk Assessment

### High Risk
1. **HPACK Huffman decoding**: Complex bit manipulation
2. **io_uring kernel compatibility**: Different kernel behaviors
3. **TLS handshake security**: Must be cryptographically correct

### Medium Risk
1. **HTTP/2 flow control**: Deadlock potential
2. **SIMD string bugs**: Already failed once
3. **Memory alignment issues**: AArch64 requirements

### Mitigation
- Extensive unit testing
- Integration tests with real clients
- Code reviews for crypto/TLS
- Kernel version testing matrix

---

## Documentation

### Week 8 Deliverables
1. **API Documentation**: Update for new functions
2. **HTTP/2 Guide**: How to test with h2load
3. **io_uring Guide**: Performance tuning
4. **TLS Setup**: Certificate generation
5. **Performance Report**: Benchmark results

---

## Git Workflow

### Branch Strategy
```
main
├── dev/v0.6.0 (integration branch)
│   ├── feature/http2-hpack
│   ├── feature/http2-handler
│   ├── feature/io-uring-core
│   ├── feature/io-uring-poll
│   ├── feature/simd-strings
│   ├── feature/tls-record
│   └── feature/tls-handshake
```

### Commit Message Format
```
Week N: Brief description

- Detailed change 1
- Detailed change 2

Tests: pass/fail
Benchmark: X RPS (if applicable)
```

---

## Success Criteria

### v0.6.0 Release Requirements
- [ ] HTTP/2 serving files and CGI
- [ ] io_uring functional with 30%+ performance gain
- [ ] SIMD strlen/strcmp working
- [ ] TLS record layer complete
- [ ] All tests passing
- [ ] Documentation updated
- [ ] Performance targets met

---

## Post-v0.6.0 (v0.7.0 Preview)

### Features to Consider
1. **HTTP/3 (QUIC)**: UDP-based HTTP
2. **WebSocket Messages**: Frame processing complete
3. **HTTP/2 Server Push**: Preemptive resource sending
4. **Advanced TLS**: Client certificates, OCSP
5. **Load Balancing**: Upstream health checks

---

**Last Updated**: 2026-02-26  
**Document Version**: 1.0
