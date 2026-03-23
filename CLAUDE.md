# CLAUDE.md — ANX HTTP Server 开发指南

本文件为 Claude Code 提供项目上下文与开发规范，确保 AI 辅助开发行为一致。

---

## 项目概述

**ANX Web Server** 是一个完全用 **AArch64 汇编（GNU Assembler / GAS）** 编写的高性能 HTTP 服务器，运行于 Linux。

- 无任何外部依赖（无 libc），全部使用原始 Linux syscall
- 支持 HTTP/1.1（完整）、HTTP/2（框架）、WebSocket（RFC 6455）
- 当前版本：`v0.3.0-dev`
- 架构：AArch64 only

---

## 构建与运行

```bash
# 构建
make

# 运行（默认 8080 端口）
./build/anx -p 8080 -d www

# 使用配置文件
./build/anx -c configs/anx.conf

# 反向代理模式
./build/anx -x

# 运行测试
make test

# 完整 CI 流水线
make ci

# 清理
make clean
```

**构建产物：** `build/anx`（静态链接二进制）

---

## 目录结构

```
src/
├── main.s                    # 入口点：CLI 解析、初始化、信号处理
├── network.s                 # TCP socket、accept 循环、worker 进程
├── http.s                    # HTTP/1.1 请求解析、响应、代理逻辑
├── utils.s                   # 字符串/整数工具（strcpy、atoi 等）
├── config.s                  # INI 配置文件解析
├── data.s                    # 全局缓冲区和常量（所有全局变量在此定义）
├── listing.s                 # 目录列表 HTML 生成
├── error.s                   # HTTP 错误页面生成（400/403/404/502 等）
├── cgi.s                     # CGI 脚本执行
├── i18n.s                    # 国际化（英文/中文）
├── defs.s                    # syscall 号和常量定义
├── core/
│   ├── memory.s              # 内存池（mmap 分配）
│   ├── simd.s                # NEON SIMD 优化（memcpy/memset/base64）
│   ├── types.s               # 类型定义
│   └── version.s             # 版本信息（构建时自动生成）
├── io/
│   ├── engine.s              # I/O 引擎抽象（epoll / io_uring 接口）
│   └── uring.s               # io_uring 实现（计划 v0.4.0）
├── crypto/
│   ├── sha1.s                # SHA-1 哈希（RFC 3174，80 轮纯汇编）
│   └── base64.s              # Base64 编解码（标量 + NEON）
└── protocol/
    ├── http2/
    │   ├── connection.s      # HTTP/2 连接状态机
    │   ├── streams.s         # 流管理（支持 1000 并发流）
    │   ├── frames.s          # 帧处理（10 种帧类型）
    │   └── hpack.s           # HPACK 头部压缩（RFC 7541）
    └── websocket/
        ├── handshake.s       # WebSocket 握手（RFC 6455）
        └── frames.s          # 帧解析/构造（NEON 掩码加速）

configs/                      # 配置文件示例
tests/                        # 测试脚本
www/                          # 默认静态文件目录
```

---

## 编码规范

### 汇编风格

- **注释语言：** 中英文均可，保持与周围代码一致
- **标签命名：** `snake_case`（如 `handle_client`、`parse_request`）
- **节声明：** 每个源文件明确标注 `.text` / `.data` / `.bss`
- **寄存器使用：** 遵循 AArch64 ABI（x0-x7 参数/返回值，x19-x28 保存寄存器，x29 帧指针，x30 链接寄存器）
- **函数结构：**
  ```asm
  function_name:
      stp x29, x30, [sp, #-16]!    // 保存帧指针和链接寄存器
      mov x29, sp
      // ... 函数体 ...
      ldp x29, x30, [sp], #16      // 恢复
      ret
  ```
- **全局符号：** 在 `data.s` 中定义，其他文件用 `.extern` 引用

### 全局数据

所有全局缓冲区和变量定义在 `src/data.s`，修改时注意：
- `req_buffer` (8192 字节) — 原始 HTTP 请求
- `req_path` (512 字节) — 解析后的请求路径
- `path_buffer` (512 字节) — 完整文件系统路径
- `server_port`, `server_root`, `upstream_ip`, `upstream_port` — 服务器配置

### 系统调用约定

```asm
// AArch64 syscall: x8=syscall_nr, x0-x5=参数, x0=返回值
mov x8, #SYS_WRITE    // syscall 号（见 defs.s）
mov x0, #1            // fd
ldr x1, =buffer       // buf
mov x2, #len          // count
svc #0                // 触发 syscall
```

所有 syscall 常量定义在 `src/defs.s`，添加新 syscall 时在此文件追加。

---

## 架构要点

### 并发模型

- **Prefork + epoll：** 父进程通过 `clone()` 派生 worker，每个 worker 独立 epoll 实例
- 父进程用 `wait4()` 监视子进程，崩溃自动重启
- 监听 socket 由父子进程共享

### 请求生命周期

```
accept() → handle_client(fd)
  → SYS_READ (8192B)
  → 解析 method/path/version/headers
  → 安全检查（禁止 ../）
  → 路径解析（server_root + req_path）
  → SYS_NEWFSTATAT (stat)
  → 目录 → listing.s | 文件 → sendfile() | 其他 → 403
  → HTTP 响应头 + body
  → keep-alive 判断 → 循环或关闭
```

### 关键约束

- **缓冲区固定大小：** 请求最大 8192 字节，路径最大 512 字节
- **无动态分配：** 请求处理期间不调用 mmap，所有缓冲预分配
- **零拷贝：** 文件服务用 `sendfile()`，禁止 read+write 方式
- **安全：** 所有用户输入路径必须经过 `check_traversal()` 检查

---

## 开发工作流

### 添加新功能

1. 确定功能归属模块（协议层改动放 `protocol/`，基础设施放 `core/`，应用逻辑放根目录）
2. 如需新全局变量，在 `data.s` 中添加
3. 如需新 syscall 常量，在 `defs.s` 中添加
4. 在 `Makefile` 的 `SRCS` 列表中追加新 `.s` 文件
5. 运行 `make` 验证编译通过
6. 运行 `make test` 验证功能正确

### 版本号管理

版本在 `Makefile` 顶部修改：
```makefile
VERSION_MAJOR = 0
VERSION_MINOR = 3
VERSION_PATCH = 0
VERSION_STAGE = dev    # dev / alpha / beta / stable
```

`src/core/version.s` 由构建系统自动生成，**不要手动编辑**。

### 分支策略

- `master` — 稳定发布分支
- `dev/vX.Y.Z-stage` — 功能开发分支
- `claude/...` — Claude Code 工作分支

---

## 测试

```bash
make test          # 完整测试套件（tests/run_tests.sh）
./tests/quick_test.sh  # 快速验证
```

测试覆盖：HTTP 基本请求、静态文件服务、目录列表、错误响应、代理模式、keep-alive。

---

## 常见问题

**Q: 构建失败 "undefined reference"**
- 检查 `data.s` 中是否有对应的 `.global` 声明
- 检查 `Makefile` 的 `SRCS` 是否包含该源文件

**Q: `version.s` 编译报错**
- 运行 `make clean && make` 重新生成

**Q: 测试端口被占用**
- 杀掉旧进程：`pkill anx` 或 `kill $(cat server.pid)`

**Q: 如何调试**
- 构建已包含 `-g` 调试符号
- 使用 `gdb ./build/anx` 或 `strace ./build/anx`
