# ANX AArch64 Pure Assembly Server

A high-performance HTTP static file server written entirely in **AArch64 Assembly**.

## Features
- **Zero Dependencies**: No C standard library (libc), no runtimes. Pure Linux Syscalls.
- **Static Linking**: Compiled into a single, tiny static binary.
- **High Performance**: Optimized for AArch64 architecture using `sendfile` for zero-copy transfer.
- **Configuration**: Supports CLI arguments and configuration files.
- **Log Management**: Includes a monitoring script with automatic log rotation.

## Prerequisites
- AArch64 (ARM64) Linux environment.
- `as` (Assembler) and `ld` (Linker).
- `make` build tool.

## Build
```bash
make
```

## Usage

### Basic Run
Run the server in the background using the helper script (default port 8080):
```bash
./start_server.sh
```

### CLI Arguments
You can run the binary directly with arguments:
- `-p <port>`: Set listening port (default: 8080).
- `-d <dir>`: Set root directory for static files (default: `./www`).
- `-c <file>`: Load configuration from file.

**Example:**
```bash
./build/anx_asm_demo -p 9090 -d /var/www/html
```

### Configuration File
Create a config file (e.g., `my.conf`):
```ini
port=8080
root=./www
```
Run with config:
```bash
./build/anx_asm_demo -c my.conf
```
*Note: CLI arguments override config file settings.*

## Architecture
The server directly invokes Linux Kernel syscalls:
- **Networking**: `socket`, `bind`, `listen`, `accept`, `setsockopt`.
- **I/O**: `openat`, `read`, `write`, `close`.
- **File Serving**: `sendfile` (Zero Copy), `lseek`.
- **Process**: `exit`.

## Directory Structure
- `src/server.s`: Main assembly source code.
- `www/`: Default web root directory.
- `configs/`: Example configuration files.
- `build/`: Build artifacts (ignored by git).