/* src/io/uring_impl.s - io_uring Implementation (Linux 5.1+) */

.include "src/defs.s"
.include "src/core/types.s"

.global uring_setup_rings
.global uring_map_rings
.global uring_unmap_rings
.global uring_kernel_version_check

/* ========================================================================
 * io_uring Ring Memory Management
 * ======================================================================== */

/* Ring offsets from params (simplified from Linux kernel) */
.struct 0
ring_off_head:      .word 0
ring_off_tail:      .word 0
ring_off_ring_mask: .word 0
ring_off_entries:   .word 0
ring_off_flags:     .word 0
ring_off_drop:      .word 0
ring_off_array:     .word 0
.struct 32

/* Ring State Structure */
.struct 0
uring_ring_fd:      .word 0         /* Ring file descriptor */
uring_flags:        .word 0         /* Setup flags */
uring_sq_head:      .quad 0         /* SQ head pointer (kernel updated) */
uring_sq_tail:      .quad 0         /* SQ tail pointer (user updated) */
uring_sq_mask:      .word 0         /* SQ ring mask */
uring_sq_entries:   .word 0         /* SQ entries count */
uring_sq_array:     .quad 0         /* SQ array pointer (indices into SQEs) */
uring_sqes:         .quad 0         /* SQE array pointer */
uring_cq_head:      .quad 0         /* CQ head pointer (user updated) */
uring_cq_tail:      .quad 0         /* CQ tail pointer (kernel updated) */
uring_cq_mask:      .word 0         /* CQ ring mask */
uring_cq_entries:   .word 0         /* CQ entries count */
uring_cq_overflow:  .word 0         /* CQ overflow count */
uring_cq_flags:     .word 0         /* CQ flags */
uring_cqes:         .quad 0         /* CQE array pointer */
uring_sq_khead:     .quad 0         /* Kernel SQ head mapping */
uring_sq_ktail:     .quad 0         /* Kernel SQ tail mapping */
uring_cq_khead:     .quad 0         /* Kernel CQ head mapping */
uring_cq_ktail:     .quad 0         /* Kernel CQ tail mapping */
.struct 160

.data
.align 4
uring_ring_state:   .skip 160       /* Global ring state */

.text

/* ========================================================================
 * Kernel Version Check
 * ======================================================================== */

/*
 * uring_kernel_version_check() - Check if kernel supports io_uring
 * Returns: x0 = 1 if supported, 0 if not
 */
uring_kernel_version_check:
    stp     x29, x30, [sp, #-128]!
    mov     x29, sp
    
    /* Use uname to get kernel version */
    mov     x0, sp                  /* utsname buffer */
    mov     x8, #160                /* SYS_UNAME */
    svc     #0
    
    cmp     x0, #0
    blt     uring_version_unsupported
    
    /* Parse release string at offset 65 (after sysname, nodename) */
    add     x0, sp, #65             /* release field */
    
    /* Parse major version number */
    ldrb    w1, [x0]                /* First digit */
    sub     w1, w1, #'0'            /* Convert to number */
    
    /* Check if major >= 5 */
    cmp     w1, #5
    blt     uring_version_unsupported
    bgt     uring_version_supported
    
    /* Major == 5, check minor */
    add     x0, x0, #2              /* Skip '.' */
    ldrb    w1, [x0]
    sub     w1, w1, #'0'
    
    cmp     w1, #1
    blt     uring_version_unsupported

uring_version_supported:
    mov     x0, #1
    b       uring_version_done

uring_version_unsupported:
    mov     x0, #0

uring_version_done:
    ldp     x29, x30, [sp], #128
    ret

/* ========================================================================
 * Ring Setup
 * ======================================================================== */

/*
 * uring_setup_rings(entries, flags) - Setup io_uring rings
 * x0 = number of entries (must be power of 2)
 * x1 = flags (IORING_SETUP_*)
 * Returns: x0 = 0 on success, -1 on failure
 */
uring_setup_rings:
    stp     x29, x30, [sp, #-144]!
    mov     x29, sp
    stp     x19, x20, [sp, #128]
    
    mov     x19, x0                 /* entries */
    mov     x20, x1                 /* flags */
    
    /* Validate entries is power of 2 */
    sub     x1, x0, #1
    and     x1, x0, x1
    cbnz    x1, uring_setup_fail
    
    /* Validate entries <= 4096 */
    cmp     x0, #4096
    bgt     uring_setup_fail
    
    /* Prepare params structure on stack */
    mov     x0, sp                  /* params buffer */
    mov     x1, #0
    mov     x2, #120                /* sizeof(io_uring_params) */
    bl      memset
    
    str     w20, [sp, #8]           /* params.flags */
    
    /* Call io_uring_setup */
    mov     x0, x19                 /* entries */
    mov     x1, sp                  /* params */
    mov     x8, #425                /* SYS_IO_URING_SETUP */
    svc     #0
    
    cmp     x0, #0
    blt     uring_setup_fail
    
    /* Save ring fd */
    ldr     x1, =uring_ring_state
    str     w0, [x1]                /* uring_ring_fd */
    str     w20, [x1, #4]           /* uring_flags */
    str     w19, [x1, #12]          /* uring_sq_entries */
    str     w19, [x1, #44]          /* uring_cq_entries */
    
    /* Calculate masks (entries - 1) */
    sub     w2, w19, #1
    str     w2, [x1, #10]           /* uring_sq_mask */
    str     w2, [x1, #42]           /* uring_cq_mask */
    
    mov     x0, #0
    b       uring_setup_done

uring_setup_fail:
    mov     x0, #-1

uring_setup_done:
    ldp     x19, x20, [sp, #128]
    ldp     x29, x30, [sp], #144
    ret

/* ========================================================================
 * Ring Memory Mapping
 * ======================================================================== */

/*
 * uring_map_rings(params) - Map io_uring rings to user space
 * x0 = pointer to io_uring_params from setup
 * Returns: x0 = 0 on success, -1 on failure
 */
uring_map_rings:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    
    mov     x19, x0                 /* params */
    ldr     x20, =uring_ring_state
    ldr     w21, [x20]              /* ring fd */
    
    /* Extract offsets from params (at offset 40 for sq_off, 80 for cq_off) */
    add     x22, x19, #40           /* sq_off */
    add     x23, x19, #80           /* cq_off */
    
    /* Calculate SQ ring size */
    ldr     w0, [x22, #12]          /* sq_off.ring_entries */
    mov     x1, #4
    mul     x24, x0, x1             /* entries * sizeof(uint32_t) */
    add     x24, x24, #8192         /* Add page for head/tail */
    
    /* Map SQ ring */
    mov     x0, #0                  /* addr (kernel chooses) */
    mov     x1, x24                 /* length */
    mov     x2, #3                  /* prot = PROT_READ | PROT_WRITE */
    mov     x3, #0x11               /* flags = MAP_SHARED | MAP_POPULATE */
    mov     x4, x21                 /* fd */
    ldr     w5, [x22]               /* sq_off.head (mmap offset) */
    mov     x8, #222                /* SYS_MMAP2 */
    svc     #0
    
    cmp     x0, #0
    blt     uring_map_fail
    
    str     x0, [x20, #72]          /* uring_sq_khead (base) */
    
    /* Setup SQ pointers */
    ldr     w1, [x22]               /* sq_off.head */
    add     x2, x0, x1
    str     x2, [x20, #16]          /* uring_sq_head ptr */
    
    ldr     w1, [x22, #4]           /* sq_off.tail */
    add     x2, x0, x1
    str     x2, [x20, #24]          /* uring_sq_tail ptr */
    
    ldr     w1, [x22, #24]          /* sq_off.array */
    add     x2, x0, x1
    str     x2, [x20, #32]          /* uring_sq_array ptr */
    
    /* Calculate CQ ring size */
    ldr     w0, [x23, #12]          /* cq_off.ring_entries */
    mov     x1, #16                 /* sizeof(io_uring_cqe) */
    mul     x24, x0, x1
    add     x24, x24, #8192
    
    /* Map CQ ring */
    mov     x0, #0
    mov     x1, x24
    mov     x2, #3
    mov     x3, #0x11
    mov     x4, x21
    ldr     w5, [x23]               /* cq_off.head */
    mov     x8, #222
    svc     #0
    
    cmp     x0, #0
    blt     uring_map_fail
    
    str     x0, [x20, #88]          /* uring_cq_khead (base) */
    
    /* Setup CQ pointers */
    ldr     w1, [x23]               /* cq_off.head */
    add     x2, x0, x1
    str     x2, [x20, #48]          /* uring_cq_head ptr */
    
    ldr     w1, [x23, #4]           /* cq_off.tail */
    add     x2, x0, x1
    str     x2, [x20, #56]          /* uring_cq_tail ptr */
    
    ldr     w1, [x23, #32]          /* cq_off.cqes */
    add     x2, x0, x1
    str     x2, [x20, #64]          /* uring_cqes ptr */
    
    /* Map SQE array */
    ldr     w0, [x20, #12]          /* sq_entries */
    mov     x1, #64                 /* sizeof(io_uring_sqe) */
    mul     x24, x0, x1
    
    mov     x0, #0
    mov     x1, x24
    mov     x2, #3
    mov     x3, #0x11
    mov     x4, x21
    mov     x5, #0x10000000         /* IORING_OFF_SQES */
    mov     x8, #222
    svc     #0
    
    cmp     x0, #0
    blt     uring_map_fail
    
    str     x0, [x20, #40]          /* uring_sqes ptr */
    
    /* Initialize head/tail pointers */
    ldr     x0, [x20, #16]
    str     wzr, [x0]               /* sq_head = 0 */
    ldr     x0, [x20, #24]
    str     wzr, [x0]               /* sq_tail = 0 */
    ldr     x0, [x20, #48]
    str     wzr, [x0]               /* cq_head = 0 */
    
    mov     x0, #0
    b       uring_map_done

uring_map_fail:
    mov     x0, #-1

uring_map_done:
    ldp     x19, x20, [sp, #16]
    ldp     x21, x22, [sp, #32]
    ldp     x23, x24, [sp, #48]
    ldp     x29, x30, [sp], #64
    ret

/* ========================================================================
 * Ring Unmapping
 * ======================================================================== */

/*
 * uring_unmap_rings() - Unmap io_uring rings
 */
uring_unmap_rings:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    ldr     x0, =uring_ring_state
    
    /* Unmap SQ ring */
    ldr     x1, [x0, #72]           /* sq_khead base */
    cbz     x1, uring_unmap_sq_skip
    mov     x0, x1
    mov     x1, #8192               /* Approximate size */
    mov     x8, #215                /* SYS_MUNMAP */
    svc     #0

uring_unmap_sq_skip:
    /* Unmap CQ ring */
    ldr     x1, [x0, #88]           /* cq_khead base */
    cbz     x1, uring_unmap_cq_skip
    mov     x0, x1
    mov     x1, #8192
    mov     x8, #215
    svc     #0

uring_unmap_cq_skip:
    /* Unmap SQEs */
    ldr     x1, [x0, #40]           /* sqes */
    cbz     x1, uring_unmap_done
    mov     x0, x1
    ldr     w2, [x0, #12]           /* sq_entries */
    mov     x3, #64
    mul     x1, x2, x3
    mov     x8, #215
    svc     #0

uring_unmap_done:
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

