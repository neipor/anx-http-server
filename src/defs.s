/* src/defs.s - System Call Constants & Definitions */

/* Syscalls */
.equ SYS_EPOLL_CREATE1, 20
.equ SYS_EPOLL_CTL, 21
.equ SYS_EPOLL_WAIT, 22
.equ SYS_DUP3, 24
.equ SYS_FCNTL, 25
.equ SYS_PIPE2, 59
.equ SYS_UNLINKAT, 35
.equ SYS_OPENAT, 56
.equ SYS_CLOSE, 57
.equ SYS_GETDENTS64, 61
.equ SYS_LSEEK, 62
.equ SYS_READ, 63
.equ SYS_WRITE, 64
.equ SYS_WRITEV, 66
.equ SYS_SENDFILE, 71
.equ SYS_PSELECT6, 72
.equ SYS_NEWFSTATAT, 79
.equ SYS_FSTAT, 80
.equ SYS_EXIT, 93
.equ SYS_SETSID, 157
.equ SYS_GETPID, 172
.equ SYS_RT_SIGACTION, 134
.equ SYS_SOCKET, 198
.equ SYS_BIND, 200
.equ SYS_LISTEN, 201
.equ SYS_ACCEPT, 202
.equ SYS_CONNECT, 203
.equ SYS_GETPEERNAME, 205
.equ SYS_EXECVE, 221
.equ SYS_ACCEPT4, 242
.equ SYS_SETSOCKOPT, 208
.equ SYS_CLONE, 220
.equ SYS_FORK, 107
.equ SYS_WAIT4, 260
.equ SYS_GETPPID, 173
.equ SYS_PRCTL, 167
.equ SYS_NANOSLEEP, 101
.equ SYS_KILL, 129
.equ PR_SET_PDEATHSIG, 1
.equ SIGKILL, 9

/* Fcntl */
.equ F_GETFL, 3
.equ F_SETFL, 4
.equ O_NONBLOCK, 2048

/* Epoll */
.equ EPOLL_CTL_ADD, 1
.equ EPOLL_CTL_DEL, 2
.equ EPOLL_CTL_MOD, 3
.equ EPOLLIN, 1
.equ EPOLLOUT, 4
.equ EPOLLET, 0x80000000
.equ EPOLLEXCLUSIVE, 0x10000000
.equ MAX_EVENTS, 32

/* Socket Options */
.equ TCP_NODELAY, 1
.equ TCP_DEFER_ACCEPT, 9
.equ IPPROTO_TCP, 6
.equ SOCK_NONBLOCK, 2048
.equ SOCK_CLOEXEC, 524288

/* Constants */
.equ STDIN, 0
.equ STDOUT, 1
.equ STDERR, 2
.equ AF_INET, 2
.equ SOCK_STREAM, 1
.equ SOL_SOCKET, 1
.equ SO_REUSEADDR, 2
.equ SO_RCVTIMEO, 20
.equ SO_SNDTIMEO, 21
.equ O_RDONLY, 0
.equ O_WRONLY, 1
.equ O_CREAT, 0x40
.equ O_TRUNC, 0x200
.equ O_APPEND, 0x400
.equ O_DIRECTORY, 0x4000  /* 040000 octal */
.equ AT_FDCWD, -100
.equ SEEK_END, 2
.equ SEEK_SET, 0

/* Dirent Type */
.equ DT_REG, 8
.equ DT_DIR, 4

/* Stat Mode */
.equ S_IFMT, 0xF000
.equ S_IFDIR, 0x4000
.equ S_IFREG, 0x8000

/* Signals */
.equ SIGCHLD, 17
.equ SIGPIPE, 13
.equ SIG_IGN, 1
.equ EINTR, 4
.equ EAGAIN, 11

/* Clone Flags */
.equ SIGCHLD_FLAG, 17     /* Exit signal for clone */

/* Mmap */
.equ SYS_MMAP, 222
.equ SYS_SCHED_YIELD, 124
.equ PROT_READ, 1
.equ PROT_WRITE, 2
.equ MAP_SHARED, 0x01
.equ MAP_PRIVATE, 0x02
.equ MAP_ANONYMOUS, 0x20
.equ MAP_STACK, 0x20000

/* ========================================================================= */
/* Event-driven connection layer (conn.s)                                    */
/* ========================================================================= */
.equ SYS_EPOLL_PWAIT, 22   /* epoll_pwait: timeout in ms (not pwait2/441) */
.equ SYS_CLOCK_GETTIME, 113
.equ EPOLLERR, 0x8
.equ EPOLLHUP, 0x10
.equ EPOLLRDHUP, 0x2000
.equ MAX_EVENTS, 128

/* Connection pool */
.equ CONN_MAX,        512
.equ CONN_READ_CAP,   16384
.equ CONN_OUT_CAP,    16384	/* response head + cached body coalesce into one write */
.equ CONN_SLOW_MAX,   8        /* max slow-path children per worker */

/* Memory file cache (cache.s) */
.equ CACHE_ENTRIES,     256
.equ CACHE_ENTRY_SIZE,  64
.equ CACHE_HASH_OFF,    0    /* u64 */
.equ CACHE_MTSEC_OFF,   8    /* u64 st_mtim.tv_sec */
.equ CACHE_MTNSEC_OFF,  16   /* u64 st_mtim.tv_nsec */
.equ CACHE_SIZE_OFF,    24   /* u32 st_size */
.equ CACHE_VALID_OFF,   28   /* u32 1 = occupied */
.equ CACHE_CONTENT_OFF, 32   /* u64 absolute arena ptr */
.equ CACHE_SLOT,        16384 /* arena stride (power of two) */
.equ CACHE_MAX_SIZE,    14848 /* body cap: fits out_buf beside the head */
/* Open-file-descriptor cache (fdcache.s) - nginx open_file_cache equivalent */
.equ FDC_ENTRIES,     256
.equ FDC_ENTRY_SIZE,  128
.equ FDC_HASH_OFF,    0    /* u64 */
.equ FDC_MTSEC_OFF,   8    /* u64 st_mtim.tv_sec */
.equ FDC_MTNSEC_OFF,  16   /* u64 st_mtim.tv_nsec */
.equ FDC_SIZE_OFF,    24   /* u32 st_size */
.equ FDC_FD_OFF,      28   /* u32 fd, -1 = empty */
.equ FDC_REFC_OFF,    32   /* u32 borrow refcount */
.equ FDC_VALID_OFF,   36   /* u32 1 = occupied */
.equ FDC_PATH_OFF,    40   /* NUL-terminated path (exact-key check) */
.equ FDC_PATH_CAP,    80   /* path storage cap; longer paths skip the cache */
.equ CACHE_PATH_CAP,    1024 /* path storage cap; fills exceeding it skip */

/* Connection states */
.equ CONN_FREE,       0
.equ CONN_READ_HEAD,  1
.equ CONN_WRITE_HEAD, 2
.equ CONN_WRITE_BODY, 3

/* conn->flags bits */
.equ CONN_F_KEEPALIVE, 1
.equ CONN_F_ABORT,     2
/* fd-cache (fdcache.s): a conn that entered the fast file path sets
 * CONN_F_FD_CACHED so the completion close-sites hand the fd to the cache
 * instead of closing. CONN_F_FD_BORROWED marks that the fd came from an
 * fdc_get HIT (slot recorded in CONN_FDC_SLOT_OFF): the completion must
 * decrement the borrow via fdc_put_slot, never close. An openat MISS leaves
 * BORROWED clear: the fd may only be INSERTED at an inline completion where
 * path_buffer/stat_buffer still belong to this request (sfl_sent_all);
 * deferred completions (cf_finish/conn_close/sendfile_done) native-close it.
 * Both flags are cleared at request start (serve_file) and cf_reset. */
.equ CONN_F_FD_CACHED,  0x40
.equ CONN_F_FD_BORROWED, 0x80
.equ CONN_F_FILE_BODY, 4
.equ CONN_F_PTR_BODY,  8

/* conn struct offsets (base = conn pointer) */
.equ CONN_STATE_OFF,    0    /* u32 */
.equ CONN_FD_OFF,       4    /* u32 */
.equ CONN_FLAGS_OFF,    8    /* u32 */
.equ CONN_RLEN_OFF,     12   /* u32 */
.equ CONN_RPOS_OFF,     16   /* u32 */
.equ CONN_HLEN_OFF,     20   /* u32 */
.equ CONN_STATUS_OFF,   24   /* u32 */
.equ CONN_FILE_FD_OFF,  32   /* u32, -1 = none */
.equ CONN_FILE_OFF_OFF, 40   /* u64 sendfile offset */
.equ CONN_FILE_REM_OFF, 48   /* u64 sendfile remaining */
.equ CONN_OUT_LEN_OFF,  56   /* u32 */
.equ CONN_OUT_POS_OFF,  60   /* u32 */
.equ CONN_LAST_ACT_OFF, 64   /* u64 last active (seconds) */
.equ CONN_WPTR_OFF,     72   /* u64 WRITE_BODY source ptr */
.equ CONN_WLEN_OFF,     80   /* u64 WRITE_BODY total len */
.equ CONN_WPOS_OFF,     88   /* u64 WRITE_BODY written */
.equ CONN_FDC_SLOT_OFF, 100  /* u32 fdcache slot index, -1 = none (borrow) */
.equ CONN_MASK_OFF,     104  /* u32 shadow of the live epoll mask, detects divergence */
.equ CONN_OUT_BUF_OFF,  128  /* 16384 bytes */
.equ CONN_READ_BUF_OFF, 16512 /* 16384 bytes */
.equ CONN_SIZE,         32896
