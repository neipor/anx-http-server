/* src/defs.s - System Call Constants & Definitions */

/* Syscalls */
.equ SYS_EPOLL_CREATE1, 20
.equ SYS_EPOLL_CTL, 21
.equ SYS_EPOLL_WAIT, 22
.equ SYS_FCNTL, 25
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
.equ SYS_RT_SIGACTION, 134
.equ SYS_SOCKET, 198
.equ SYS_BIND, 200
.equ SYS_LISTEN, 201
.equ SYS_ACCEPT, 202
.equ SYS_CONNECT, 203
.equ SYS_GETPEERNAME, 205
.equ SYS_ACCEPT4, 242
.equ SYS_SETSOCKOPT, 208
.equ SYS_CLONE, 220
.equ SYS_WAIT4, 260

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

/* Clone Flags */
.equ SIGCHLD_FLAG, 17     /* Exit signal for clone */
