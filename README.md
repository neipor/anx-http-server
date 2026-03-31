# ANX Web Server

A high-performance, industrial-grade HTTP/1.1 web server written entirely in **AArch64 Assembly** for Linux. No C library (libc), no external dependencies — just raw syscalls and pure assembly.

## Features

### Core
- **Pure AArch64 Assembly**: Written in GNU Assembler (GAS), zero C code
- **No Dependencies**: No libc, no external libraries — 100% self-contained
- **Prefork + Epoll**: Multi-process architecture with epoll event loop
- **Zero-Copy**: Uses `sendfile` syscall for high-performance file delivery
- **Static Linking**: Single binary, no shared library dependencies

### HTTP Features
- **HTTP/1.1** with Keep-Alive support
- **HEAD Method** support (headers only, no body)
- **Range Requests** (HTTP 206 Partial Content) for resumable downloads
- **ETag / If-None-Match** conditional requests (304 Not Modified)
- **Cache-Control** headers for static assets
- **Accept-Ranges** header advertisement
- **40+ MIME Types** auto-detected by extension (html, css, js, json, png, jpg, gif, webp, avif, mp4, webm, mp3, woff2, wasm, zip, and more)
- **Directory Listing** with sortable columns (toggleable via `autoindex`)
- **Health Check** endpoint (`/health` returns JSON)

### Server Features
- **Configurable Workers** (1-128 processes, default 4)
- **Reverse Proxy** with X-Forwarded-For and X-Real-IP injection
- **gzip_static** support (serve pre-compressed `.gz` files)
- **CGI** support for Python scripts
- **Daemon Mode** (background execution with PID file)
- **Graceful Shutdown** (SIGINT/SIGTERM handling with PID cleanup)
- **Access Logging** to stdout or file
- **Silent Mode** for maximum performance
- **Configurable Timeouts** (keepalive, send, receive)
- **Server Tokens** toggle (hide/show version in headers)
- **Internationalization** (English/Chinese auto-detection)

### Networking
- **SO_REUSEPORT** for multi-worker socket sharing
- **SO_REUSEADDR** for fast restart
- **TCP_DEFER_ACCEPT** to reduce unnecessary wake-ups
- **TCP_NODELAY** for low-latency responses
- **EPOLLEXCLUSIVE** for thundering herd prevention

### Security
- **Path Traversal Prevention** (`..` detection)
- **IP-based Access Control** (allow/deny lists)
- **Client Body Size Limits** (configurable)
- **SIGPIPE** handling

### Protocol Frameworks (In Development)
- **HTTP/2** connection management, stream state machine, HPACK
- **WebSocket** RFC 6455 handshake with SHA-1 + Base64
- **io_uring** async I/O framework

## Quick Start

### Build
```bash
make
```

### Run
```bash
# Serve current directory on port 8080
./build/anx

# Custom port and directory
./build/anx -p 9000 -d /var/www/html

# With configuration file
./build/anx -c configs/anx.conf

# Reverse proxy mode
./build/anx -x

# Background daemon
./build/anx --daemon -p 80 -d /var/www
```

### Test
```bash
make test
```

## Configuration

Configuration file format (key=value):

```ini
# Server Basics
port=8080
root=./www

# Worker Configuration
worker_processes=4

# Timeouts
keepalive_timeout=65

# Request Limits
client_max_body_size=1048576

# Server Identity
server_tokens=on

# Directory Listing
autoindex=on

# Compression
gzip_static=off

# Logging
access_log=/var/log/anx/access.log

# Reverse Proxy
upstream_ip=127.0.0.1
upstream_port=9005
```

## CLI Options

| Flag | Description |
|------|-------------|
| `-p, --port <port>` | Listen port (default: 8080) |
| `-d, --dir <path>` | Document root |
| `-c, --config <file>` | Configuration file |
| `-x, --proxy` | Enable reverse proxy |
| `-s, --silent` | Disable access logging |
| `--daemon` | Run as background daemon |
| `-v, --version` | Print version |
| `-h, --help` | Print help |

## Architecture

```
src/
├── main.s                    # Entry point, CLI parsing, signal handling
├── network.s                 # TCP socket, epoll, worker processes
├── http.s                    # HTTP/1.1 request/response, proxy, Range
├── utils.s                   # String/integer utilities, logging
├── config.s                  # Configuration file parser (18 directives)
├── data.s                    # Global buffers, constants, MIME types
├── listing.s                 # Directory listing HTML generation
├── error.s                   # HTTP error page generation
├── cgi.s                     # CGI script execution
├── i18n.s                    # Internationalization (EN/ZH)
├── defs.s                    # Syscall numbers and constants
├── core/
│   ├── memory.s              # Memory pool (mmap)
│   ├── simd.s                # NEON SIMD optimizations
│   ├── types.s               # Type definitions
│   └── version.s             # Auto-generated version info
├── io/
│   ├── engine.s              # I/O engine abstraction
│   └── uring.s               # io_uring implementation
├── crypto/
│   ├── sha1.s                # SHA-1 hash (RFC 3174)
│   └── base64.s              # Base64 encode/decode + NEON
├── protocol/
│   ├── http2/                # HTTP/2 framework
│   └── websocket/            # WebSocket framework
└── security/
    ├── acl.s                 # IP access control lists
    └── redirect.s            # URL redirect rules
```

## Syscalls Used

`socket`, `bind`, `listen`, `accept4`, `connect`, `setsockopt`, `getpeername`,
`read`, `write`, `writev`, `sendfile`, `openat`, `close`, `lseek`, `newfstatat`,
`getdents64`, `epoll_create1`, `epoll_ctl`, `epoll_wait`, `clone`, `wait4`,
`execve`, `pipe2`, `dup3`, `fcntl`, `rt_sigaction`, `clock_gettime`, `getpid`,
`setsid`, `unlinkat`, `exit`

## License
MIT

## Version History

### v0.4.0-dev (Current)
**Major Feature Release**

- 30+ new MIME types (40+ total)
- HEAD method support
- HTTP Range requests (206 Partial Content)
- gzip_static support
- Cache-Control and Accept-Ranges headers
- Configurable worker processes (1-128)
- 18 configuration directives
- X-Forwarded-For / X-Real-IP proxy headers
- SO_REUSEPORT, TCP_NODELAY networking
- Server tokens toggle
- Autoindex toggle
- IP access control lists
- URL redirect module
- Enhanced help text (EN/ZH)
- 35 automated tests

### v0.3.0-dev
**WebSocket Handshake + SHA1 + Base64**

- SHA-1 hash algorithm (RFC 3174) - 80 rounds, pure assembly
- Base64 encoding/decoding (RFC 4648) - scalar + NEON
- Complete WebSocket handshake (RFC 6455)
- ~9,000 lines of pure AArch64 assembly

### v0.2.0-beta
**HTTP/2 Core + SIMD Optimizations**

- HTTP/2 connection management (RFC 7540)
- Stream state machine with 1000 concurrent streams  
- SIMD memory operations: 30-60 GB/s throughput
- io_uring framework for async I/O

### v0.1.0-alpha
**Architecture Refactor**

- Modular architecture (core/, io/, protocol/)
- Memory pool management
- I/O engine abstraction  

---

**GitHub**: https://github.com/neipor/anx-http-server
