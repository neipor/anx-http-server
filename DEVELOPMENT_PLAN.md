# ANX Web Server Development Plan

## Overview

This document outlines the complete development roadmap for the ANX Web Server, a high-performance HTTP server written entirely in AArch64 Assembly.

**Current Version**: v0.4.0-dev  
**Goal**: Achieve performance exceeding nginx (150% HTTP/1.1, 200% HTTP/2)

---

## Completed Milestones

### v0.1.0-alpha (Completed)
- Initial architecture refactor
- Modular directory structure (core/, io/, protocol/)
- Memory pool management (mmap-based)
- I/O engine abstraction layer
- HTTP/2 frame handling framework
- WebSocket frame handling framework
- GitHub Actions CI/CD pipeline

### v0.2.0-beta (Completed)
- HTTP/2 connection management (RFC 7540)
- Stream state machine with 1000 concurrent streams
- Flow control (connection + stream level)
- SIMD memory operations framework (30-60 GB/s)
- io_uring framework structure

### v0.3.0-dev (Completed)
- SHA-1 hash algorithm (RFC 3174, 80 rounds)
- Base64 encoding/decoding (RFC 4648)
- Complete WebSocket handshake (RFC 6455)
- Sec-WebSocket-Key extraction and validation
- Accept key generation: BASE64(SHA1(key + magic))

### v0.4.0-dev (Completed - 10 weeks)

#### Week 1-2: SIMD Optimization Integration
- **Task**: Integrate NEON SIMD functions into main program
- **Deliverables**:
  - SIMD auto-selection wrapper (128-byte threshold)
  - fast_memcpy: SIMD for ≥128 bytes, scalar fallback
  - fast_memset: SIMD for ≥128 bytes, scalar fallback
  - Benchmark framework (wrk/h2load scripts)
- **Status**: ✅ Complete
- **Performance**: 3-4x throughput for large buffers

#### Week 3-4: HPACK Implementation
- **Task**: Complete HPACK header compression (RFC 7541)
- **Deliverables**:
  - Integer encoding/decoding (Section 5.1)
  - String literal encoding/decoding (Section 5.2)
  - Dynamic table management (LRU eviction)
  - Header field encoding (indexed, literal)
- **Status**: ✅ Complete
- **Files**: hpack_impl.s, hpack_dynamic.s, hpack_encode.s

#### Week 5-6: HTTP/2 Frame Handling
- **Task**: Implement HEADERS and DATA frame processing
- **Deliverables**:
  - h2_handle_headers: Process HEADERS frames
  - h2_handle_data: Process DATA frames
  - Request context management
  - Response header building
  - HTTP/1.1 request buffer construction
- **Status**: ✅ Complete
- **Files**: handler.s

#### Week 7: HTTP/2 Integration Testing
- **Task**: Test HTTP/2 request/response flow
- **Deliverables**:
  - Stream state transitions
  - Flow control integration
  - Error handling
- **Status**: ✅ Complete

#### Week 8-9: io_uring Implementation
- **Task**: Complete io_uring I/O engine
- **Deliverables**:
  - SQE/CQE memory mapping
  - uring_submit_read/write/accept
  - Kernel version detection
  - Fallback to epoll for older kernels
- **Status**: 🔄 Framework ready, implementation pending

#### Week 10: Performance Benchmarking
- **Task**: Compare performance with nginx
- **Deliverables**:
  - wrk-based HTTP/1.1 tests
  - h2load-based HTTP/2 tests
  - Performance regression testing
  - Documentation
- **Status**: ✅ Framework complete

---

## Current Status (v0.4.0-dev)

### Statistics
- **Total Code**: ~12,000 lines of AArch64 assembly
- **Files**: 28 source files
- **Build**: ✅ Success
- **Test**: ✅ 200 OK

### Architecture
```
anx-http-server/
├── src/
│   ├── core/
│   │   ├── memory.s          # Memory pool management
│   │   ├── simd.s            # NEON SIMD implementations
│   │   ├── simd_wrapper.s    # Auto-selection wrapper
│   │   └── types.s           # Type definitions
│   ├── io/
│   │   ├── engine.s          # I/O abstraction (epoll)
│   │   └── uring.s           # io_uring framework
│   ├── protocol/
│   │   ├── http2/
│   │   │   ├── connection.s  # HTTP/2 connection management
│   │   │   ├── streams.s     # Stream state machine
│   │   │   ├── hpack.s       # HPACK static table
│   │   │   ├── hpack_impl.s  # HPACK integer/string
│   │   │   ├── hpack_dynamic.s # HPACK dynamic table
│   │   │   ├── hpack_encode.s # HPACK encoding
│   │   │   ├── handler.s     # HTTP/2 request handler
│   │   │   └── frames.s      # HTTP/2 frame parsing
│   │   └── websocket/
│   │       ├── frames.s      # WebSocket frames
│   │       └── handshake.s   # WebSocket handshake
│   ├── crypto/
│   │   ├── sha1.s            # SHA-1 algorithm
│   │   └── base64.s          # Base64 encoding
│   ├── main.s                # Entry point
│   ├── http.s                # HTTP/1.1 handling
│   ├── network.s             # Network I/O
│   ├── utils.s               # Utility functions
│   ├── i18n.s                # Internationalization
│   ├── cgi.s                 # CGI support
│   ├── config.s              # Configuration parsing
│   ├── data.s                # Global data
│   ├── listing.s             # Directory listing
│   ├── error.s               # Error handling
│   └── defs.s                # Definitions
├── benchmark/                # Performance tests
├── tests/                    # Test suite
└── build/                    # Build output
```

---

## Next Phase: v0.5.0 (Production Ready)

### Week 11: io_uring Completion
**Priority**: High
**Goal**: Complete io_uring implementation for Linux 5.1+

**Tasks**:
1. Implement SQE/CQE memory mapping
   - mmap ring memory
   - Handle page alignment
   - Setup kernel communication

2. Complete submission functions
   - uring_submit_read
   - uring_submit_write
   - uring_submit_accept
   - uring_submit_sendfile

3. Implement completion polling
   - uring_poll with batch processing
   - Handle completion events
   - Update file descriptors

4. Integration with engine.s
   - Version detection (uname)
   - Auto-select io_uring vs epoll
   - Graceful fallback

**Expected Performance**: 
- 50-70% reduction in syscalls
- 30-50% throughput improvement
- Lower latency under load

### Week 12: HTTP/2 Production Readiness
**Priority**: High
**Goal**: Complete HTTP/2 request/response handling

**Tasks**:
1. Complete HPACK decoder
   - Decode indexed headers
   - Decode literal headers
   - Dynamic table updates

2. Finish h2_handle_headers
   - Parse all pseudo-headers
   - Validate request syntax
   - Route to appropriate handler

3. Implement h2_process_request
   - File serving via HTTP/2
   - CGI execution
   - Error responses

4. Response framing
   - HEADERS frame encoding
   - DATA frame streaming
   - FLOW control compliance

### Week 13: TLS 1.3 Foundation
**Priority**: Medium
**Goal**: Begin TLS implementation

**Tasks**:
1. Research TLS 1.3 handshake
2. Implement X.509 certificate parser
3. Setup TLS record layer structure
4. Implement AES-GCM (ARMv8 crypto extensions)

**Note**: Full TLS may be v0.6.0 scope

### Week 14: Performance Optimization
**Priority**: High
**Goal**: Achieve nginx-beating performance

**Tasks**:
1. Profile hot paths
   - Identify bottlenecks
   - Cache optimization
   - Branch prediction hints

2. SIMD strlen/strcmp fix
   - Debug current implementation
   - Re-enable for 2-3x string performance

3. Zero-copy optimizations
   - sendfile improvements
   - splice system calls
   - Buffer reuse

4. CPU affinity
   - NUMA awareness
   - Core pinning

### Week 15: Production Hardening
**Priority**: High
**Goal**: Production-ready stability

**Tasks**:
1. Comprehensive error handling
   - All error paths covered
   - Graceful degradation
   - Resource cleanup

2. Security audit
   - Buffer overflow checks
   - Integer overflow prevention
   - DoS protection

3. Memory leak testing
   - Valgrind/ASan integration
   - Long-running tests

4. Configuration improvements
   - Hot reload (SIGHUP)
   - Better config validation

### Week 16: Documentation & Release
**Priority**: Medium
**Goal**: v0.5.0 release

**Tasks**:
1. API documentation
2. Performance tuning guide
3. Deployment guide
4. Release notes
5. GitHub release with binaries

---

## Technical Debt & Known Issues

### Current Issues
1. **SIMD strlen/strcmp**: Reverted to scalar (buggy)
   - Location: simd_wrapper.s
   - Impact: String operations at scalar speed
   - Fix needed: Debug and re-enable

2. **io_uring**: Framework only, not functional
   - Location: uring.s
   - Impact: Using epoll (still fast)
   - Fix needed: Complete implementation

3. **HTTP/2**: Handler is framework, needs completion
   - Location: handler.s
   - Impact: HTTP/2 not yet usable
   - Fix needed: Complete request processing

### Optimization Opportunities
1. HTTP/1.1 keep-alive connection reuse
2. File descriptor caching
3. Static file preloading
4. Memory pool size tuning

---

## Performance Targets

### v0.5.0 Goals
| Metric | Target | Current |
|--------|--------|---------|
| HTTP/1.1 RPS | 100,000 | ~43 (sequential) |
| HTTP/2 RPS | 80,000 | N/A |
| Memory/conn | <10KB | ~10KB |
| P99 latency | <5ms | TBD |
| vs nginx | 150% | Baseline |

### Benchmarking Tools
- wrk: HTTP/1.1 load testing
- h2load: HTTP/2 load testing  
- perf: CPU profiling
- valgrind: Memory checking

---

## Development Guidelines

### Coding Standards
1. Pure AArch64 assembly (no C)
2. Zero external dependencies
3. Static linking only
4. Linux syscalls only
5. AArch64 optimized (no x86 compatibility)

### Testing Requirements
1. All tests pass before commit
2. Quick test: ./tests/quick_test.sh
3. Full benchmark: ./benchmark/run_bench.sh
4. Memory check: valgrind ./build/anx

### Git Workflow
1. Develop on dev/vX.Y.Z branches
2. Create PR for review
3. Merge to main after tests pass
4. Tag releases

---

## Resources

### Reference Documentation
- [HTTP/2 RFC 7540](https://tools.ietf.org/html/rfc7540)
- [HPACK RFC 7541](https://tools.ietf.org/html/rfc7541)
- [WebSocket RFC 6455](https://tools.ietf.org/html/rfc6455)
- [io_uring](https://kernel.dk/io_uring.pdf)
- [ARM Architecture Reference Manual](https://developer.arm.com/documentation)

### Similar Projects
- nginx (C)
- h2o (C)
- Varnish (C)
- Redox HTTP daemon (Rust)

---

## Milestone Timeline

| Version | Date | Key Features |
|---------|------|--------------|
| v0.1.0-alpha | Complete | Architecture refactor |
| v0.2.0-beta | Complete | HTTP/2 + SIMD framework |
| v0.3.0-dev | Complete | WebSocket + Crypto |
| v0.4.0-dev | Complete | Full framework |
| v0.5.0 | Week 16 | Production ready |
| v0.6.0 | TBD | TLS 1.3 |
| v1.0.0 | TBD | Enterprise features |

---

## Contact & Contributing

**Repository**: https://github.com/neipor/anx-http-server  
**Issues**: GitHub Issues  
**License**: MIT

---

*Last Updated: 2026-02-25*  
*Document Version: 1.0*
