/* src/io/uring.s - io_uring I/O Engine for Maximum Performance */

.include "src/defs.s"
.include "src/core/types.s"

.global uring_init
.global uring_submit_read
.global uring_submit_write
.global uring_submit_accept
.global uring_submit_sendfile
.global uring_poll
.global uring_close

/* ========================================================================
 * io_uring Constants (Linux 5.1+)
 * ======================================================================== */

/* io_uring_setup flags */
.equ IORING_SETUP_IOPOLL,       1       /* Use io_uring polled IO */
.equ IORING_SETUP_SQPOLL,       2       /* Use submission queue polling */
.equ IORING_SETUP_SQ_AFF,       4       /* Force SQ thread on specific CPU */
.equ IORING_SETUP_CQSIZE,       8       /* Set CQ ring size */
.equ IORING_SETUP_CLAMP,        16      /* Clamp CQ ring size */
.equ IORING_SETUP_ATTACH_WQ,    32      /* Attach to existing wq */
.equ IORING_SETUP_R_DISABLED,   64      /* Start with ring disabled */

/* io_uring opcodes */
.equ IORING_OP_NOP,             0
.equ IORING_OP_READV,           1
.equ IORING_OP_WRITEV,          2
.equ IORING_OP_FSYNC,           3
.equ IORING_OP_READ_FIXED,      4
.equ IORING_OP_WRITE_FIXED,     5
.equ IORING_OP_POLL_ADD,        6
.equ IORING_OP_POLL_REMOVE,     7
.equ IORING_OP_SYNC_FILE_RANGE, 8
.equ IORING_OP_SENDMSG,         9
.equ IORING_OP_RECVMSG,         10
.equ IORING_OP_TIMEOUT,         11
.equ IORING_OP_TIMEOUT_REMOVE,  12
.equ IORING_OP_ACCEPT,          13
.equ IORING_OP_ASYNC_CANCEL,    14
.equ IORING_OP_LINK_TIMEOUT,    15
.equ IORING_OP_CONNECT,         16
.equ IORING_OP_FALLOCATE,       17
.equ IORING_OP_OPENAT,          18
.equ IORING_OP_CLOSE,           19
.equ IORING_OP_FILES_UPDATE,    20
.equ IORING_OP_STATX,           21
.equ IORING_OP_READ,            22
.equ IORING_OP_WRITE,           23
.equ IORING_OP_FADVISE,         24
.equ IORING_OP_MADVISE,         25
.equ IORING_OP_SEND,            26
.equ IORING_OP_RECV,            27
.equ IORING_OP_OPENAT2,         28
.equ IORING_OP_EPOLL_CTL,       29
.equ IORING_OP_SPLICE,          30
.equ IORING_OP_PROVIDE_BUFFERS, 31
.equ IORING_OP_REMOVE_BUFFERS,  32
.equ IORING_OP_TEE,             33
.equ IORING_OP_SHUTDOWN,        34
.equ IORING_OP_RENAMEAT,        35
.equ IORING_OP_UNLINKAT,        36
.equ IORING_OP_MKDIRAT,         37
.equ IORING_OP_SYMLINKAT,       38
.equ IORING_OP_LINKAT,          39
.equ IORING_OP_MSG_RING,        40
.equ IORING_OP_FSETXATTR,       41
.equ IORING_OP_SETXATTR,        42
.equ IORING_OP_FGETXATTR,       43
.equ IORING_OP_GETXATTR,        44
.equ IORING_OP_SOCKET,          45
.equ IORING_OP_URING_CMD,       46
.equ IORING_OP_SEND_ZC,         47
.equ IORING_OP_SENDMSG_ZC,      48

/* sqe flags */
.equ IOSQE_FIXED_FILE,          1       /* Use fixed fileset */
.equ IOSQE_IO_DRAIN,            2       /* Drain prior to running */
.equ IOSQE_IO_LINK,             4       /* Linked sqe */
.equ IOSQE_IO_HARDLINK,         8       /* Linked sqe that won't be broken */
.equ IOSQE_ASYNC,               16      /* Force async */
.equ IOSQE_BUFFER_SELECT,       32      /* Select buffer from provided buffers */

/* cqe flags */
.equ IORING_CQE_F_BUFFER,       1       /* Buffer selection from provided buffers */
.equ IORING_CQE_F_MORE,         2       /* More data coming */
.equ IORING_CQE_F_SOCK_NONEMPTY, 4      /* Socket had non-zero data before splice */
.equ IORING_CQE_F_NOTIF,        8       /* Notification event */

/* Ring sizes */
.equ IORING_QUEUE_SIZE,         4096    /* Queue depth */

/* ========================================================================
 * io_uring Structures
 * ======================================================================== */

/* SQE - 64 bytes */
.struct 0
sqe_opcode:     .byte 0         /* Operation code */
sqe_flags:      .byte 0         /* IOSQE_ flags */
sqe_ioprio:     .word 0         /* I/O priority */
sqe_fd:         .word 0         /* File descriptor */
sqe_off:        .quad 0         /* Offset */
sqe_addr:       .quad 0         /* Address */
sqe_len:        .word 0         /* Buffer length or count */
sqe_rw_flags:   .word 0         /* Flags for read/write */
sqe_user_data:  .quad 0         /* User data (stream pointer, etc) */
sqe_buf_index:  .word 0         /* Buffer index */
sqe_personality: .word 0        /* Personality */
sqe_file_index: .word 0         /* File index for splice */
sqe_pad:        .word 0         /* Padding */
.struct 64

/* CQE - 16 bytes */
.struct 0
cqe_user_data:  .quad 0         /* User data */
cqe_res:        .word 0         /* Result code */
cqe_flags:      .word 0         /* CQE flags */
.struct 16

/* io_uring_params - 120 bytes */
.struct 0
params_sq_entries:      .word 0
params_cq_entries:      .word 0
params_flags:           .word 0
params_sq_thread_cpu:   .word 0
params_sq_thread_idle:  .word 0
params_features:        .word 0
params_wq_fd:           .word 0
params_resv:            .skip 24
params_sq_off:          .skip 40
params_cq_off:          .skip 40
.struct 120

/* ========================================================================
 * io_uring State
 * ======================================================================== */

.data
.align 12                         /* Page alignment */
uring_ring_fd:      .word -1      /* Ring file descriptor */
uring_sq_head:      .quad 0       /* Submission queue head */
uring_sq_tail:      .quad 0       /* Submission queue tail */
uring_cq_head:      .quad 0       /* Completion queue head */
uring_cq_tail:      .quad 0       /* Completion queue tail */
uring_sq_mask:      .word 0       /* Submission queue mask */
uring_cq_mask:      .word 0       /* Completion queue mask */
uring_sq_entries:   .quad 0       /* Submission queue entries pointer */
uring_cq_entries:   .quad 0       /* Completion queue entries pointer */
uring_sqes:         .quad 0       /* SQE array pointer */
uring_initialized:  .byte 0       /* Initialization flag */

.text

/* ========================================================================
 * io_uring Initialization
 * ======================================================================== */

/*
 * uring_init() - Initialize io_uring
 * Returns: x0 = 0 on success, -1 on failure
 */
uring_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    /* Check if already initialized */
    ldr     x0, =uring_initialized
    ldrb    w0, [x0]
    cbnz    w0, uring_already_init
    
    /* Allocate io_uring_params on stack */
    sub     sp, sp, #128
    mov     x19, sp
    
    /* Clear params */
    mov     x0, x19
    mov     x1, #0
    mov     x2, #120
    bl      memset
    
    /* Setup flags: IORING_SETUP_SQPOLL for kernel polling */
    mov     w0, #IORING_SETUP_SQPOLL
    str     w0, [x19, #8]           /* params.flags */
    
    /* io_uring_setup(entries, params) */
    mov     x0, #IORING_QUEUE_SIZE  /* entries */
    mov     x1, x19                 /* params */
    mov     x8, #425                /* SYS_IO_URING_SETUP */
    svc     #0
    
    cmp     x0, #0
    blt     uring_setup_fail
    
    /* Save ring fd */
    ldr     x1, =uring_ring_fd
    str     w0, [x1]
    mov     w20, w0                 /* Save fd */
    
    /* Extract offsets from params */
    /* TODO: Map ring memory using mmap */
    /* For now, this is a simplified implementation */
    
    /* Mark as initialized */
    ldr     x0, =uring_initialized
    mov     w1, #1
    strb    w1, [x0]
    
    add     sp, sp, #128
    mov     x0, #0
    b       uring_init_done

uring_already_init:
    mov     x0, #0
    b       uring_init_done

uring_setup_fail:
    add     sp, sp, #128
    mov     x0, #-1

uring_init_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * Submit Read Operation
 * ======================================================================== */

/*
 * uring_submit_read(fd, buf, len, offset, user_data) - Submit async read
 * x0 = file descriptor
 * x1 = buffer pointer
 * x2 = length
 * x3 = offset (use -1 for current position)
 * x4 = user data
 * Returns: x0 = 0 on success
 */
uring_submit_read:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Get next SQE and fill it */
    /* For now, stub implementation */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Submit Write Operation
 * ======================================================================== */

/*
 * uring_submit_write(fd, buf, len, offset, user_data) - Submit async write
 * x0 = file descriptor
 * x1 = buffer pointer
 * x2 = length
 * x3 = offset
 * x4 = user data
 */
uring_submit_write:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Implement */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Submit Accept Operation
 * ======================================================================== */

/*
 * uring_submit_accept(listen_fd, addr, addrlen, user_data) - Submit async accept
 * x0 = listen socket fd
 * x1 = sockaddr pointer
 * x2 = addrlen pointer
 * x3 = user data
 */
uring_submit_accept:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Implement */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Submit Sendfile Operation
 * ======================================================================== */

/*
 * uring_submit_sendfile(out_fd, in_fd, offset, count, user_data)
 * x0 = output fd (socket)
 * x1 = input fd (file)
 * x2 = offset pointer
 * x3 = count
 * x4 = user data
 */
uring_submit_sendfile:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Use IORING_OP_SPLICE for sendfile-like operation */
    /* TODO: Implement */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Poll for Completions
 * ======================================================================== */

/*
 * uring_poll(cqe_array, max_cqe, timeout) - Poll for completed operations
 * x0 = CQE array to fill
 * x1 = max CQEs to return
 * x2 = timeout in ms (-1 for infinite)
 * Returns: x0 = number of CQEs returned
 */
uring_poll:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Implement CQ polling */
    /* Check if kernel has CQEs ready */
    /* Copy to user array */
    
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Close io_uring
 * ======================================================================== */

/*
 * uring_close() - Close io_uring ring
 */
uring_close:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* TODO: Unmap ring memory */
    /* Close ring fd */
    
    ldr     x0, =uring_ring_fd
    ldr     w0, [x0]
    cmp     w0, #0
    blt     uring_close_done
    
    mov     x8, #57                 /* SYS_CLOSE */
    svc     #0
    
    /* Clear state */
    ldr     x0, =uring_initialized
    strb    wzr, [x0]

uring_close_done:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Helper: memset
 * ======================================================================== */
memset:
    cmp     x2, #0
    beq     memset_done
    mov     x3, #0
memset_loop:
    strb    w1, [x0, x3]
    add     x3, x3, #1
    cmp     x3, x2
    blt     memset_loop
memset_done:
    ret

