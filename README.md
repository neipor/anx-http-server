# ANX — AArch64 Assembly HTTP Server

<p align="center">
  <img src="https://img.shields.io/badge/version-v0.6.0-blue" alt="version">
  <img src="https://img.shields.io/badge/language-AArch64_Assembly-orange" alt="language">
  <img src="https://img.shields.io/badge/binary_size-~308KB-green" alt="size">
  <img src="https://img.shields.io/badge/license-GPL--3.0-red" alt="license">
  <img src="https://img.shields.io/badge/platform-Linux_AArch64-lightgrey" alt="platform">
</p>

<p align="center">
  <b>English</b> | <a href="#中文文档">中文</a>
</p>

---

A production-grade, high-performance HTTP/1.1 web server written entirely in **pure AArch64 assembly** for Linux. Zero C library, zero external dependencies — raw syscalls only. Delivers nginx-level feature parity in a **~230 KB static binary**.

## Features

| Feature | Status |
|---|---|
| HTTP/1.1 (GET, HEAD, OPTIONS, POST) | ✅ |
| Zero-copy static file serving (`sendfile`) | ✅ |
| 30+ MIME types | ✅ |
| Directory listing | ✅ |
| ETag / 304 Not Modified | ✅ |
| Range requests / 206 Partial Content | ✅ |
| Gzip compression (static `.gz` + dynamic pipe) | ✅ |
| Keep-alive with configurable timeout | ✅ |
| Multi-worker prefork (auto CPU count) | ✅ |
| Epoll event loop (EPOLLEXCLUSIVE, accept storm) | ✅ |
| TCP_NODELAY per connection | ✅ |
| SIMD header scan (NEON `\r\n\r\n`) | ✅ |
| Nginx-style config parser (`server{}`, `location{}`) | ✅ |
| Location routing (prefix + exact match) | ✅ |
| `try_files` directive | ✅ |
| Custom error pages (`error_page 404 /404.html`) | ✅ |
| IP access control (allow/deny with CIDR) | ✅ |
| Token-bucket rate limiting | ✅ |
| Reverse proxy | ✅ |
| CGI execution | ✅ |
| WebSocket upgrade | ✅ |
| Nginx combined access log (file + colorized console) | ✅ |
| `/server-status` JSON endpoint (live request counter) | ✅ |
| Graceful reload (`kill -HUP <pid>`) | ✅ |
| Log rotation (`kill -USR1 <pid>`) | ✅ |
| `return` directive (301/302/307 redirects) | ✅ |
| `add_header` directive (custom response headers) | ✅ |
| `expires` directive (Cache-Control header) | ✅ |
| `gzip_min_length` (skip compression for small files) | ✅ |
| `server_tokens off` (hide Server header) | ✅ |
| X-Forwarded-For in reverse proxy mode | ✅ |
| PID file | ✅ |
| Config test (`-t` / `--test`) | ✅ |
| Systemd service file | ✅ |
| HTTP/2 framework | 🚧 |
| io_uring async I/O | 🚧 |

## Quick Start

### Build
```bash
make
```

### Run
```bash
# Serve ./www on port 8080 with 4 workers
./build/anx

# Custom port and document root
./build/anx -p 8099 -d /var/www/html

# Nginx-style config file
./build/anx -n configs/anx.conf

# Test config without starting
./build/anx -t -n configs/anx.conf

# Reverse proxy to upstream
./build/anx -x
```

### Install (systemd)
```bash
sudo make install       # installs to /usr/local/bin/anx + systemd unit
sudo systemctl enable --now anx
```

## Nginx-Style Config
```nginx
worker_processes auto;
pid /run/anx.pid;

events {
    worker_connections 1024;
}

server {
    listen 8080;
    server_name example.com;
    root /var/www/html;
    index index.html;
    access_log /var/log/anx/access.log;
    error_page 404 /404.html;

    location / {
        try_files $uri $uri/ =404;
    }

    location /api {
        allow 192.168.1.0/24;
        deny all;
    }
}
```

## CLI Flags

| Flag | Description |
|---|---|
| `-p <port>` | Listen port (default: 8080) |
| `-d <dir>` | Document root (default: ./www) |
| `-w <n>` | Worker count (default: CPU count) |
| `-c <file>` | ANX config file |
| `-n <file>` | Nginx-style config file |
| `-t` / `--test` | Test config and exit |
| `-x` | Enable reverse proxy mode |
| `-s` | Silent mode (no console log) |
| `-v` | Print version and exit |

## Performance

ANX is built to beat nginx on the workloads that matter. Measured on a 4-core
AArch64 host (anx-dev container), wrk driving from a separate core pair,
anx pinned to 2 workers on 2 cores, nginx (stock + `open_file_cache`) as the
mirror.

**fd-cache (B9)** — ANX eliminates `openat`+`close` on the sendfile path via a
per-worker open-fd cache (nginx `open_file_cache` equivalent). Verified by
strace: 30 requests → **4 `openat`** (one cold open per worker), vs 30 without
the cache. Multi-file eviction soak (500 unique files, 16-way churn, 256 slots):
**0 byte mismatches, 0 errors** under load.

| Workload | ANX | nginx stock | nginx tuned | Note |
|----------|-----|-------------|-------------|------|
| index.html (3B) | **15.7k rps** | 10.4k | 16.2k | beats stock, ties tuned |
| f16k.bin (16KB)  | **12.5k rps** (c300) | 10.5k | — | beats nginx at every concurrency |
| f1m.bin (1MB)    | 1.2k→0.8k (c8→c300) | 1.08k | — | wins at low c; ~30% behind at c300 |
| cached (≤8KB)    | **36 µs/req** | 71 µs/req | 56 µs/req | −49% vs stock |

**Wins:** cached/small files and 16 KB sendfile at all concurrency levels.
**Known frontier:** 1 MB bulk transfer at high concurrency degrades as connection
count rises (single-connection bulk send briefly holds a worker); under 2 worker
cores nginx stays flat ~1080 rps while ANX drops to ~780. Deep event-loop
fairness tuning is the next optimization pass — not a correctness issue.

Stability: 300-connection soak at 17,890 rps, 14.4 ms p50 latency, **zero
spin-storm events**. 18/18 probe-suite + 15/15 cache-probe checks pass.

## Architecture

```
src/
├── main.s          Entry point, CLI, worker lifecycle, SIGHUP reload
├── network.s       Socket setup, accept loop, accept mutex (LDAXR/STLXR)
├── http.s          HTTP parsing, routing, file serving, gzip, Range, CGI
├── utils.s         String ops, logging (nginx combined format), date
├── data.s          Global strings, BSS buffers
├── config.s        ANX config parser (key=value)
├── config_nginx.s  Nginx-style block config parser
├── location.s      Location routing (longest prefix match, 16 locations)
├── access.s        IP allow/deny + token-bucket rate limiter
├── cgi.s           CGI execution via pipe+fork+execve
├── error.s         Custom error page lookup
├── listing.s       Directory listing HTML generator
├── defs.s          Syscall numbers and constants
├── version.s       Version string (auto-generated by make)
├── core/           Memory pool, SIMD helpers
├── io/             io_uring framework
├── protocol/
│   ├── http2/      HTTP/2 (HPACK, streams, flow control) — framework
│   └── websocket/  WebSocket handshake + frames
└── crypto/
    ├── sha1.s      SHA-1 (RFC 3174)
    └── base64.s    Base64 encode/decode (RFC 4648)
```

## Syscalls Used
`socket` · `bind` · `listen` · `accept4` · `connect` · `read` · `write` · `openat` · `close` · `sendfile` · `clone` · `wait4` · `getdents64` · `mmap` · `mprotect` · `sched_yield` · `pipe2` · `dup3` · `execve` · `kill` · `setsockopt` · `epoll_create1` · `epoll_ctl` · `epoll_pwait` · `newfstatat` · `exit_group`

## License
MIT

## Version History

### v0.5.1 (Current)
**Stability & Completeness Pass**

- Range/206: fixed `.asciz` null-termination for header matching; fixed double-CRLF header corruption
- Dynamic gzip: pipe2+clone+execve `/bin/gzip -c`; chunked Transfer-Encoding
- Nginx combined access log: dual output (colorized console + log file)
- Worker stack isolation: per-worker private 64 KB mmap stack
- Accept mutex: LDAXR/STLXR thundering-herd prevention
- Keep-alive timeout via `SO_RCVTIMEO`
- `/server-status` JSON endpoint
- `-t`/`--test` config validation flag
- Custom error pages via `error_page` directive
- PID file management
- Fixed `beq` out-of-range conditional branch (> ±1 MB)

### v0.5.0
**Production-Grade Nginx-Compatible Server**

- 30+ MIME types; access logging fixed
- Multi-worker prefork (SO_REUSEPORT + epoll)
- Nginx-style config parser (server{}/location{}/events{})
- Location routing, try_files, custom error pages
- HEAD/OPTIONS/405 Method Not Allowed
- Date header, ETag/304, graceful reload (SIGHUP)
- Gzip static file serving, IP allow/deny, rate limiting
- Systemd service, PID file, make install

### v0.4.0-dev
HTTP/2 framework, HPACK, SIMD, io_uring framework (~13,000 lines)

### v0.3.0-dev
WebSocket handshake, SHA-1, Base64 (~9,000 lines)

### v0.2.0-beta
HTTP/2 core, stream multiplexing, SIMD memory ops (~8,000 lines)

### v0.1.0-alpha
Modular architecture refactor (~6,250 lines)

### v0.0.x
Initial HTTP/1.1 server

---

**GitHub**: https://github.com/neipor/anx-http-server
