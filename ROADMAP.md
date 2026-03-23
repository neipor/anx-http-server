# ANX HTTP Server — 开发规划

> 纯 AArch64 汇编 HTTP 服务器路线图

---

## 当前状态：v0.3.0-dev

### 已完成功能

| 功能 | 状态 | 说明 |
|------|------|------|
| HTTP/1.1 完整实现 | ✅ | 请求解析、静态文件、目录列表、keep-alive |
| 零拷贝文件服务 | ✅ | sendfile() syscall |
| 反向代理 | ✅ | IP 级转发至上游 |
| 配置文件 | ✅ | INI 格式，支持 CLI 覆盖 |
| Prefork + epoll | ✅ | worker 进程 + I/O 多路复用 |
| 安全路径检查 | ✅ | 禁止 `../` 目录穿越 |
| NEON SIMD 优化 | ✅ | memcpy/memset/base64，30-60 GB/s |
| SHA-1 (RFC 3174) | ✅ | 80 轮纯汇编 |
| Base64 (RFC 4648) | ✅ | 标量 + NEON 双实现 |
| WebSocket 握手 | ✅ | RFC 6455，Sec-WebSocket-Accept 生成 |
| HTTP/2 框架 | ✅ | 连接、流、帧、HPACK 骨架 |
| 国际化 | ✅ | 中文/英文消息 |
| CGI 支持 | ✅ | fork+exec 执行脚本 |
| 守护进程模式 | ✅ | `--daemon` 后台运行 |

---

## v0.4.0 — WebSocket 完整实现

**目标：** 支持双向实时通信

### 任务清单

- [ ] **WS 消息收发循环**
  - 文件：`src/protocol/websocket/frames.s`
  - 实现完整帧读取（含分片重组）
  - 实现帧发送（TEXT / BINARY）

- [ ] **Ping/Pong 心跳**
  - 响应客户端 Ping，发送 Pong
  - 超时断连逻辑

- [ ] **优雅关闭（Opcode 0x8）**
  - 发送/接收 CLOSE 帧
  - 状态码传递（RFC 6455 §7.4）

- [ ] **消息分片重组**
  - CONTINUATION 帧拼接
  - 最大消息尺寸限制

- [ ] **HTTP 升级路由集成**
  - 文件：`src/http.s`
  - 检测 `Upgrade: websocket` 后切换协议栈

- [ ] **测试用例**
  - `tests/websocket_test.sh`
  - 使用 `websocat` 或 Python 客户端验证

---

## v0.5.0 — HTTP/2 完整实现

**目标：** RFC 7540 完整协议支持

### 任务清单

- [ ] **连接前言验证**
  - 文件：`src/protocol/http2/connection.s`
  - 验证客户端 24 字节 Magic：`PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n`

- [ ] **SETTINGS 帧完整处理**
  - 解析并应用所有 6 个参数
  - 发送 SETTINGS ACK

- [ ] **HPACK 完整编解码**
  - 文件：`src/protocol/http2/hpack.s`
  - 动态表插入/淘汰（LRU）
  - 整数变长编码（RFC 7541 §5.1）
  - Huffman 解码（可选优化）

- [ ] **HEADERS 帧处理**
  - 请求头解压缩
  - 路由到 HTTP 处理逻辑

- [ ] **DATA 帧处理**
  - 请求体接收
  - 流量控制窗口更新（WINDOW_UPDATE）

- [ ] **响应流程**
  - 将 HTTP/1.1 响应逻辑适配为 HTTP/2 帧发送
  - 多路复用：多个流并发响应

- [ ] **RST_STREAM / GOAWAY**
  - 错误流关闭
  - 连接级关闭

- [ ] **ALPN 协商（需 TLS）**
  - `h2` 协议标识
  - 作为 TLS 前置需求

- [ ] **测试用例**
  - 使用 `nghttp` 或 `curl --http2` 验证
  - `tests/http2_test.sh`

---

## v0.6.0 — TLS 1.3

**目标：** 加密传输支持（HTTPS / WSS）

> ⚠️ 这是最复杂的阶段，纯汇编实现 TLS 1.3 工作量极大，建议分子任务迭代。

### 任务清单

- [ ] **密码学基础**
  - AES-GCM（对称加密）
  - ChaCha20-Poly1305（备选）
  - ECDH（密钥交换，X25519 曲线）
  - HKDF（密钥派生）
  - HMAC-SHA256

- [ ] **TLS 记录层**
  - 新文件：`src/tls/record.s`
  - 记录头解析（type, version, length）
  - 加密/解密记录

- [ ] **TLS 握手**
  - 新文件：`src/tls/handshake.s`
  - ClientHello / ServerHello
  - 证书发送（Certificate）
  - 密钥协商（KeyShare）
  - Finished 验证

- [ ] **证书管理**
  - 新文件：`src/tls/cert.s`
  - PEM 文件读取（DER 解码）
  - 证书链验证（可选）

- [ ] **集成**
  - 在 `network.s` accept 后判断是否 TLS
  - 提供 `-t/--tls` CLI 参数和配置项

---

## v0.7.0 — 性能优化

**目标：** 推进至极限性能

### 任务清单

- [ ] **io_uring 集成**
  - 文件：`src/io/uring.s`（骨架已有）
  - 完整 io_uring 提交/完成队列操作
  - 替换 epoll 作为默认 I/O 引擎
  - 目标：减少 syscall 次数 >50%

- [ ] **多 worker 调优**
  - 可配置 worker 数量（当前固定为 1）
  - CPU 亲和性绑定（`sched_setaffinity`）
  - SO_REUSEPORT 负载均衡

- [ ] **连接池 / 对象复用**
  - 内存池支持连接对象复用
  - 减少 `mmap`/`munmap` 频率

- [ ] **sendfile 优化**
  - 文件描述符缓存（避免重复 openat）
  - 大文件分块传输

- [ ] **性能基准**
  - 集成 `wrk` / `ab` 基准测试
  - `tests/bench.sh` 自动化跑分
  - 目标：HTTP/1.1 > 100k RPS（单核）

---

## v1.0.0 — 稳定发布

**目标：** 生产可用

- [ ] 完整错误处理（所有 syscall 返回值检查）
- [ ] 访问日志文件（`access_log=` 配置项）
- [ ] 进程限制（最大连接数、超时）
- [ ] 优雅重载（SIGHUP 重新加载配置）
- [ ] man page / 完整文档
- [ ] 发布包（`make release` 产出正式 tarball）

---

## 设计原则

1. **纯汇编优先** — 不引入任何 C 代码或外部库
2. **最小内存占用** — 目标静态内存 < 10 MB
3. **安全第一** — 用户输入全部验证，防止注入和越界
4. **模块化** — 每个协议独立模块，互不耦合
5. **可测试** — 每个功能配套 shell 测试用例

---

## 性能目标

| 指标 | 目标 |
|------|------|
| HTTP/1.1 吞吐 | > 100,000 RPS（单核） |
| HTTP/2 吞吐 | > 50,000 RPS（多路复用） |
| WebSocket 延迟 | < 1 ms |
| 静态内存 | < 10 MB |
| 二进制大小 | < 500 KB |

---

## 参考规范

- HTTP/1.1：RFC 7230–7235
- HTTP/2：RFC 7540、RFC 7541（HPACK）
- WebSocket：RFC 6455
- TLS 1.3：RFC 8446
- SHA-1：RFC 3174
- Base64：RFC 4648
