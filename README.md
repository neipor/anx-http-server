# ANX AArch64 Pure Assembly Server

A high-performance HTTP server written entirely in **AArch64 Assembly**. 

## Features
- **Zero Dependencies**: No C standard library (libc), no runtimes. Pure Linux Syscalls.
- **Static Linking**: Compiled into a single, tiny static binary.
- **High Performance**: Optimized for AArch64 architecture.
- **Log Management**: Includes a monitoring script with automatic log rotation (1MB limit).

## Prerequisites
- AArch64 (ARM64) Linux environment.
- `as` (Assembler) and `ld` (Linker).
- `make` build tool.

## Build
```bash
make
```

## Run
Use the provided monitoring script to run the server in the background:
```bash
./start_server.sh
```

The server listens on **port 8080**. You can test it with:
```bash
curl http://localhost:8080
```

## Architecture
The server directly invokes Linux Kernel syscalls:
- `socket` (198)
- `bind` (200)
- `listen` (201)
- `accept` (202)
- `write` (64)
- `close` (57)
