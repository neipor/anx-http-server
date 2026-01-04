/* src/defs.s - System Call Constants & Definitions */

/* Syscalls */
.equ SYS_OPENAT, 56
.equ SYS_CLOSE, 57
.equ SYS_GETDENTS64, 61
.equ SYS_LSEEK, 62
.equ SYS_READ, 63
.equ SYS_WRITE, 64
.equ SYS_SENDFILE, 71
.equ SYS_EXIT, 93
.equ SYS_SOCKET, 198
.equ SYS_BIND, 200
.equ SYS_LISTEN, 201
.equ SYS_ACCEPT, 202
.equ SYS_SETSOCKOPT, 208

/* Constants */
.equ STDIN, 0
.equ STDOUT, 1
.equ STDERR, 2
.equ AF_INET, 2
.equ SOCK_STREAM, 1
.equ SOL_SOCKET, 1
.equ SO_REUSEADDR, 2
.equ O_RDONLY, 0
.equ O_DIRECTORY, 0x4000  /* 040000 octal */
.equ AT_FDCWD, -100
.equ SEEK_END, 2
.equ SEEK_SET, 0

/* Dirent Type */
.equ DT_REG, 8
.equ DT_DIR, 4