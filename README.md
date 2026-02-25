# AArch64 Assembly HTTP Server

A high-performance, concurrent web server written entirely in AArch64 Assembly for Linux. No C library (libc), no external dependencies. Just raw syscalls.

## Features

- **Pure Assembly**: Written in GNU Assembler (GAS) for AArch64.
- **Concurrent**: Uses `fork` (via `clone` syscall) to handle multiple clients simultaneously.
- **Zero-Copy Serving**: Uses `sendfile` syscall for high-performance static file delivery.
- **MIME Support**: Automatically detects and sets Content-Type for `.html`, `.css`, `.js`, `.png`, `.jpg`.
- **Directory Listing**: Auto-generates HTML indexes for directories.
- **Reverse Proxy**: Can forward requests to an upstream backend (IP-based).
- **Configuration**: Supports CLI flags and a configuration file.

## Architecture

- **`src/main.s`**: Entry point, argument parsing.
- **`src/network.s`**: Socket creation, binding, listening, and connection handling.
- **`src/http.s`**: HTTP request parsing, response generation, proxy logic.
- **`src/utils.s`**: String manipulation, integer conversion, memory helpers.
- **`src/config.s`**: Config file parser.
- **`src/data.s`**: Global constants and buffers.

## Usage

### Build
```bash
make
```

### Run
```bash
# Start on default port 8080 serving ./www
./build/anx_asm_demo

# Start on port 8099 serving /var/www
./build/anx_asm_demo -p 8099 -d /var/www

# Start with Config File
./build/anx_asm_demo -c configs/anx.conf
```

### Reverse Proxy Mode
To enable the reverse proxy (forwarding to `127.0.0.1:9005`):
```bash
./build/anx_asm_demo -x
```
Useful for forwarding requests to an application server (e.g., Python, Node.js).

## Configuration File (`anx.conf`)
```ini
port=8080
root=./www
```

## Syscalls Used
- `socket`, `bind`, `listen`, `accept`, `connect`
- `read`, `write`, `openat`, `close`
- `sendfile`
- `clone` (fork), `wait4` (via signal handling)
- `getdents64`
- `exit`

## License
MIT

## Version History

### v0.2.0-beta (Current)
**HTTP/2 Core + SIMD Optimizations**

- HTTP/2 connection management (RFC 7540)
- Stream state machine with 1000 concurrent streams  
- Flow control (connection + stream level)
- SIMD memory operations: 30-60 GB/s throughput
- io_uring framework for async I/O
- ~8,000 lines of pure AArch64 assembly

[Download v0.2.0-beta](https://github.com/neipor/anx-http-server/releases/tag/v0.2.0-beta)

### v0.1.0-alpha
**Architecture Refactor**

- Modular architecture (core/, io/, protocol/)
- Memory pool management
- I/O engine abstraction  
- WebSocket frame handling
- ~6,250 lines of assembly

### v0.0.x (Original)
Initial HTTP/1.1 server implementation

---

**GitHub**: https://github.com/neipor/anx-http-server
