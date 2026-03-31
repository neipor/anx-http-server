/* src/io/uring_submit.s - io_uring SQE Submission and CQE Polling */

.include "src/defs.s"
.include "src/core/types.s"

.global uring_submit_read
.global uring_submit_write
.global uring_submit_accept
.global uring_submit_sendfile
.global uring_submit_barrier
.global uring_poll
.global uring_peek_cqe
.global uring_wait_cqe
.global uring_cq_advance

/* External data */
.extern uring_ring_state

/* io_uring_op constants */
.set IORING_OP_NOP,          0
.set IORING_OP_READV,        1
.set IORING_OP_WRITEV,       2
.set IORING_OP_FSYNC,        3
.set IORING_OP_READ_FIXED,   4
.set IORING_OP_WRITE_FIXED,  5
.set IORING_OP_POLL_ADD,     6
.set IORING_OP_POLL_REMOVE,  7
.set IORING_OP_SYNC_FILE_RANGE, 8
.set IORING_OP_SENDMSG,      9
.set IORING_OP_RECVMSG,      10
.set IORING_OP_TIMEOUT,      11
.set IORING_OP_TIMEOUT_REMOVE, 12
.set IORING_OP_ACCEPT,       13
.set IORING_OP_ASYNC_CANCEL, 14
.set IORING_OP_LINK_TIMEOUT, 15
.set IORING_OP_CONNECT,      16
.set IORING_OP_FALLOCATE,    17
.set IORING_OP_OPENAT,       18
.set IORING_OP_CLOSE,        19
.set IORING_OP_FILES_UPDATE, 20
.set IORING_OP_STATX,        21
.set IORING_OP_READ,         22
.set IORING_OP_WRITE,        23
.set IORING_OP_FADVISE,      24
.set IORING_OP_MADVISE,      25
.set IORING_OP_SEND,         26
.set IORING_OP_RECV,         27
.set IORING_OP_OPENAT2,      28
.set IORING_OP_EPOLL_CTL,    29
.set IORING_OP_SPLICE,       30
.set IORING_OP_PROVIDE_BUFFERS, 31
.set IORING_OP_REMOVE_BUFFERS, 32
.set IORING_OP_TEE,          33
.set IORING_OP_SHUTDOWN,     34
.set IORING_OP_RENAMEAT,     35
.set IORING_OP_UNLINKAT,     36
.set IORING_OP_MKDIRAT,      37
.set IORING_OP_SYMLINKAT,    38
.set IORING_OP_LINKAT,       39
.set IORING_OP_MSG_RING,     40
.set IORING_OP_FSETXATTR,    41
.set IORING_OP_SETXATTR,     42
.set IORING_OP_FGETXATTR,    43
.set IORING_OP_GETXATTR,     44
.set IORING_OP_SOCKET,       45
.set IORING_OP_URING_CMD,    46
.set IORING_OP_SEND_ZC,      47
.set IORING_OP_SENDMSG_ZC,   48

/* SQE flags */
.set IOSQE_FIXED_FILE,       (1 << 0)
.set IOSQE_IO_DRAIN,         (1 << 1)
.set IOSQE_IO_LINK,          (1 << 2)
.set IOSQE_IO_HARDLINK,      (1 << 3)
.set IOSQE_ASYNC,            (1 << 4)
.set IOSQE_BUFFER_SELECT,    (1 << 5)
.set IOSQE_CQE_SKIP_SUCCESS, (1 << 6)

/* ================================================================================================
 * Code Section
 * ================================================================================================ */
.text
.align 2

/* ================================================================================================
 * uring_get_sqe() - Get next available SQE
 * Internal helper function
 * Returns: x0 = pointer to SQE, or 0 if ring is full
 * ================================================================================================ */
uring_get_sqe:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]
    
    ldr     x19, =uring_ring_state
    
    /* Load current tail */
    ldr     x0, [x19, #24]          /* sq_tail ptr */
    ldr     w1, [x0]                /* tail value */
    
    /* Load kernel head */
    ldr     x2, [x19, #16]          /* sq_head ptr */
    ldr     w3, [x2]                /* head value */
    
    /* Check if ring is full: (tail + 1) & mask == head */
    add     w4, w1, #1
    ldr     w5, [x19, #10]          /* sq_mask */
    and     w4, w4, w5
    cmp     w4, w3
    beq     uring_get_sqe_full
    
    /* Get SQE pointer */
    ldr     x0, [x19, #40]          /* sqes pointer */
    mov     x2, #64                 /* sizeof(struct io_uring_sqe) */
    mul     x2, x1, x2
    add     x0, x0, x2              /* SQE address */
    
    /* Clear SQE */
    mov     x1, x0
    mov     x2, #64
    mov     x3, #0
uring_clear_sqe:
    strb    w3, [x1], #1
    subs    x2, x2, #1
    bne     uring_clear_sqe
    
    b       uring_get_sqe_done

uring_get_sqe_full:
    mov     x0, #0

uring_get_sqe_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ================================================================================================
 * uring_sqe_set_data(sqe, data)
 * Set user_data for SQE
 * x0 = SQE pointer
 * x1 = user data (typically connection pointer)
 * ================================================================================================ */
uring_sqe_set_data:
    str     x1, [x0, #24]           /* sqe->user_data */
    ret

/* ================================================================================================
 * uring_flush_sq() - Flush SQEs to kernel
 * Submit all prepared SQEs
 * Returns: x0 = number of SQEs submitted
 * ================================================================================================ */
uring_flush_sq:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    ldr     x0, =uring_ring_state
    
    /* Get current tail */
    ldr     x1, [x0, #24]           /* sq_tail ptr */
    ldr     w2, [x1]                /* old_tail */
    
    /* Load pending tail (we need to track this separately) */
    /* For now, assume tail is already updated by submit functions */
    
    /* Memory barrier to ensure SQEs are visible */
    dmb     ishst
    
    /* Update kernel tail */
    ldr     x3, [x0, #80]           /* sq_ktail ptr */
    str     w2, [x3]
    
    /* Another barrier */
    dmb     ish
    
    /* Enter kernel if needed */
    ldr     w0, [x0]                /* ring fd */
    mov     x1, #1                  /* to_submit */
    mov     x2, #0                  /* min_complete */
    mov     x3, #0                  /* flags */
    mov     x8, #426                /* SYS_IO_URING_ENTER */
    svc     #0
    
    cmp     x0, #0
    blt     uring_flush_err
    b       uring_flush_done

uring_flush_err:
    mov     x0, #-1

uring_flush_done:
    ldp     x29, x30, [sp], #16
    ret

/* ================================================================================================
 * uring_submit_read(fd, buf, len, offset, user_data)
 * Submit a read operation
 * x0 = file descriptor
 * x1 = buffer pointer
 * x2 = length
 * x3 = offset (for files)
 * x4 = user data
 * Returns: x0 = 0 on success, -1 on failure
 * ================================================================================================ */
uring_submit_read:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* fd */
    mov     x20, x4                 /* user_data */
    
    /* Get SQE */
    bl      uring_get_sqe
    cbz     x0, uring_submit_read_fail
    
    /* Fill SQE */
    mov     x5, x0                  /* sqe */
    
    mov     w0, #IORING_OP_READ
    strb    w0, [x5]                /* opcode */
    
    strb    wzr, [x5, #1]           /* flags */
    strh    wzr, [x5, #2]           /* ioprio */
    str     w19, [x5, #4]           /* fd */
    
    str     x1, [x5, #8]            /* addr (buf) */
    str     w2, [x5, #16]           /* len */
    str     x3, [x5, #20]           /* off */
    str     x20, [x5, #24]          /* user_data */

    /* Memory barrier */
    dmb     ishst

    /* Advance tail */
    ldr     x0, =uring_ring_state
    ldr     x1, [x0, #24]           /* sq_tail ptr */
    ldr     w2, [x1]
    add     w2, w2, #1
    ldr     w3, [x0, #10]           /* sq_mask */
    and     w2, w2, w3
    str     w2, [x1]
    
    mov     x0, #0
    b       uring_submit_read_done

uring_submit_read_fail:
    mov     x0, #-1

uring_submit_read_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ================================================================================================
 * uring_submit_write(fd, buf, len, offset, user_data)
 * Submit a write operation
 * x0 = file descriptor
 * x1 = buffer pointer
 * x2 = length
 * x3 = offset (for files, -1 for append)
 * x4 = user data
 * Returns: x0 = 0 on success, -1 on failure
 * ================================================================================================ */
uring_submit_write:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* fd */
    mov     x20, x4                 /* user_data */
    
    /* Get SQE */
    bl      uring_get_sqe
    cbz     x0, uring_submit_write_fail
    
    /* Fill SQE */
    mov     x5, x0                  /* sqe */
    
    mov     w0, #IORING_OP_WRITE
    strb    w0, [x5]                /* opcode */
    
    strb    wzr, [x5, #1]           /* flags */
    strh    wzr, [x5, #2]           /* ioprio */
    str     w19, [x5, #4]           /* fd */
    
    str     x1, [x5, #8]            /* addr (buf) */
    str     w2, [x5, #16]           /* len */
    str     x3, [x5, #20]           /* off */
    str     x20, [x5, #24]          /* user_data */

    /* Memory barrier */
    dmb     ishst

    /* Advance tail */
    ldr     x0, =uring_ring_state
    ldr     x1, [x0, #24]
    ldr     w2, [x1]
    add     w2, w2, #1
    ldr     w3, [x0, #10]
    and     w2, w2, w3
    str     w2, [x1]
    
    mov     x0, #0
    b       uring_submit_write_done

uring_submit_write_fail:
    mov     x0, #-1

uring_submit_write_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ================================================================================================
 * uring_submit_accept(fd, addr, addrlen, flags, user_data)
 * Submit an accept operation
 * x0 = socket fd
 * x1 = sockaddr pointer
 * x2 = addrlen pointer
 * x3 = flags (SOCK_NONBLOCK, etc)
 * x4 = user data
 * Returns: x0 = 0 on success, -1 on failure
 * ================================================================================================ */
uring_submit_accept:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* fd */
    mov     x20, x4                 /* user_data */
    
    /* Get SQE */
    bl      uring_get_sqe
    cbz     x0, uring_submit_accept_fail
    
    /* Fill SQE */
    mov     x5, x0                  /* sqe */
    
    mov     w0, #IORING_OP_ACCEPT
    strb    w0, [x5]                /* opcode */
    
    strb    wzr, [x5, #1]           /* flags */
    strh    wzr, [x5, #2]           /* ioprio */
    str     w19, [x5, #4]           /* fd */
    
    str     x1, [x5, #8]            /* addr */
    str     w3, [x5, #16]           /* accept_flags */
    str     x20, [x5, #24]          /* user_data */

    /* Memory barrier */
    dmb     ishst

    /* Advance tail */
    ldr     x0, =uring_ring_state
    ldr     x1, [x0, #24]
    ldr     w2, [x1]
    add     w2, w2, #1
    ldr     w3, [x0, #10]
    and     w2, w2, w3
    str     w2, [x1]
    
    mov     x0, #0
    b       uring_submit_accept_done

uring_submit_accept_fail:
    mov     x0, #-1

uring_submit_accept_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ================================================================================================
 * uring_poll(timeout)
 * Poll for completions with optional timeout
 * x0 = timeout in milliseconds (0 = non-blocking, -1 = wait indefinitely)
 * Returns: x0 = number of CQEs processed
 * ================================================================================================ */
uring_poll:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    
    mov     x19, x0                 /* timeout */
    mov     x20, #0                 /* count processed */
    
    /* Flush any pending SQEs first */
    bl      uring_flush_sq
    
    /* Check if we need to wait */
    cmp     x19, #0
    beq     uring_poll_check
    
    /* Wait for completions */
    ldr     x0, =uring_ring_state
    ldr     w0, [x0]                /* ring fd */
    mov     x1, #0                  /* to_submit */
    mov     x2, #1                  /* min_complete (wait for at least 1) */
    mov     x3, #0                  /* flags */
    mov     x8, #426                /* SYS_IO_URING_ENTER */
    svc     #0

uring_poll_check:
    /* Process all available CQEs */
    ldr     x21, =uring_ring_state

uring_poll_loop:
    /* Load CQ head (user) and tail (kernel) */
    ldr     x0, [x21, #48]          /* cq_head ptr */
    ldr     w1, [x0]                /* head value */
    
    ldr     x2, [x21, #56]          /* cq_tail ptr */
    dmb     ish                     /* Memory barrier */
    ldr     w3, [x2]                /* tail value */
    
    /* Check if any completions available */
    cmp     w1, w3
    beq     uring_poll_done
    
    /* Get CQE */
    and     w4, w1, w5              /* head & mask */
    
    ldr     x5, [x21, #64]          /* cqes ptr */
    mov     x6, #16                 /* sizeof(struct io_uring_cqe) */
    mul     x6, x4, x6
    add     x22, x5, x6             /* CQE address */
    
    /* Process CQE */
    ldr     x0, [x22]               /* user_data */
    ldr     w1, [x22, #8]           /* res */
    ldr     w2, [x22, #12]          /* flags */
    
    /* TODO: Dispatch to handler based on user_data */
    /* For now, just count it */
    add     x20, x20, #1
    
    /* Advance head */
    ldr     x0, [x21, #48]
    ldr     w1, [x0]
    add     w1, w1, #1
    str     w1, [x0]
    
    /* Continue processing */
    b       uring_poll_loop

uring_poll_done:
    /* Write barrier */
    dmb     ishst
    
    /* Update kernel head */
    ldr     x0, [x21, #48]
    ldr     w1, [x0]
    ldr     x2, [x21, #88]          /* cq_khead ptr */
    str     w1, [x2]
    
    mov     x0, x20                 /* return count */
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x29, x30, [sp], #48
    ret

/* ================================================================================================
 * uring_peek_cqe(cqe)
 * Peek at next CQE without removing it
 * x0 = pointer to store CQE
 * Returns: x0 = 1 if CQE available, 0 if not
 * ================================================================================================ */
uring_peek_cqe:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    ldr     x1, =uring_ring_state
    
    /* Load head and tail */
    ldr     x2, [x1, #48]           /* cq_head ptr */
    ldr     w3, [x2]
    
    ldr     x2, [x1, #56]           /* cq_tail ptr */
    dmb     ish
    ldr     w4, [x2]
    
    cmp     w3, w4
    beq     uring_peek_none
    
    /* Get CQE index */
    and     w3, w3, w5              /* head & mask */
    
    /* Copy CQE to user buffer */
    ldr     x1, [x1, #64]           /* cqes ptr */
    mov     x2, #16
    mul     x2, x3, x2
    add     x1, x1, x2
    
    /* Copy 16 bytes */
    ldr     x2, [x1]
    ldr     x3, [x1, #8]
    str     x2, [x0]
    str     x3, [x0, #8]
    
    mov     x0, #1
    b       uring_peek_done

uring_peek_none:
    mov     x0, #0

uring_peek_done:
    ldp     x29, x30, [sp], #16
    ret

/* ================================================================================================
 * uring_cq_advance(n)
 * Advance CQ ring by n entries
 * x0 = number of entries to advance
 * ================================================================================================ */
uring_cq_advance:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    ldr     x1, =uring_ring_state
    
    /* Advance head */
    ldr     x2, [x1, #48]           /* cq_head ptr */
    ldr     w3, [x2]
    add     w3, w3, w0
    str     w3, [x2]
    
    /* Write barrier and update kernel */
    dmb     ishst
    ldr     x2, [x1, #88]           /* cq_khead ptr */
    str     w3, [x2]
    
    ldp     x29, x30, [sp], #16
    ret

