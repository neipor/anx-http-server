/* src/io/engine.s - I/O Engine Abstraction Layer */

.include "src/defs.s"
.include "src/core/types.s"

.global io_engine_init
.global io_engine_register_fd
.global io_engine_unregister_fd
.global io_engine_wait_events
.global io_engine_close

/* ========================================================================
 * I/O Engine Interface
 * 
 * This module provides an abstraction over epoll/io_uring
 * Current implementation: epoll (for compatibility)
 * Future: io_uring for Linux 5.1+
 * ======================================================================== */

/* Engine Types */
.equ ENGINE_EPOLL, 1
.equ ENGINE_IOURING, 2

/* Engine Structure (32 bytes) */
.struct 0
engine_type:    .word 0         /* Engine type */
engine_fd:      .word 0         /* Engine fd (epoll_fd or ring_fd) */
engine_flags:   .word 0         /* Engine flags */
engine_reserved: .word 0        /* Padding */
engine_data:    .quad 0         /* Engine-specific data */
engine_ops:     .quad 0         /* Operations table pointer */
engine_max_events: .word 0      /* Max events per wait */
.struct 32

/* Event Structure (16 bytes) */
.struct 0
event_fd:       .word 0         /* File descriptor */
event_flags:    .word 0         /* Event flags (EPOLLIN, EPOLLOUT, etc) */
event_data:     .quad 0         /* User data */
.struct 16

/* Engine Operations Table */
.struct 0
op_init:        .quad 0
op_register:    .quad 0
op_unregister:  .quad 0
op_wait:        .quad 0
op_close:       .quad 0
.struct 40

/* Current engine instance */
.data
.align 3
current_engine: .skip 32
epoll_events:   .skip 512       /* 32 events * 16 bytes */

.text

/* ========================================================================
 * Engine Initialization
 * ======================================================================== */

/*
 * io_engine_init(engine_type) - Initialize I/O engine
 * x0 = engine type (ENGINE_EPOLL or ENGINE_IOURING)
 * Returns: x0 = 0 on success, error code on failure
 */
io_engine_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Store engine type */
    ldr     x1, =current_engine
    str     w0, [x1]                /* engine_type */
    
    cmp     x0, #ENGINE_EPOLL
    beq     init_epoll
    cmp     x0, #ENGINE_IOURING
    beq     init_iouring
    
    /* Unknown engine type */
    mov     x0, #ERR_INVALID
    b       engine_init_done

init_epoll:
    /* Create epoll instance */
    mov     x0, #0                  /* flags = 0 */
    mov     x8, #20                 /* SYS_EPOLL_CREATE1 */
    svc     #0
    
    cmp     x0, #0
    blt     engine_init_fail
    
    /* Store epoll fd */
    ldr     x1, =current_engine
    str     w0, [x1, #4]            /* engine_fd */
    mov     w2, #32
    str     w2, [x1, #28]           /* engine_max_events */
    
    mov     x0, #0                  /* Success */
    b       engine_init_done

init_iouring:
    /* io_uring not implemented yet, fall back to epoll */
    mov     x0, #ENGINE_EPOLL
    bl      io_engine_init
    b       engine_init_done

engine_init_fail:
    mov     x0, #ERR_IO

engine_init_done:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * File Descriptor Registration
 * ======================================================================== */

/*
 * io_engine_register_fd(fd, events, data) - Register fd with engine
 * x0 = file descriptor
 * x1 = events (EPOLLIN, EPOLLOUT, etc)
 * x2 = user data
 * Returns: x0 = 0 on success, error code on failure
 */
io_engine_register_fd:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* fd */
    mov     x20, x1                 /* events */
    
    /* Get engine fd */
    ldr     x3, =current_engine
    ldr     w21, [x3, #4]           /* engine_fd */
    
    /* Prepare epoll_event structure on stack */
    sub     sp, sp, #16
    str     w20, [sp]               /* events */
    str     x2, [sp, #8]            /* data.ptr */
    
    /* epoll_ctl(EPOLL_CTL_ADD) */
    mov     x0, x21                 /* epfd */
    mov     x1, #1                  /* EPOLL_CTL_ADD */
    mov     x2, x19                 /* fd */
    mov     x3, sp                  /* event pointer */
    mov     x8, #21                 /* SYS_EPOLL_CTL */
    svc     #0
    
    add     sp, sp, #16
    
    cmp     x0, #0
    blt     register_fail
    mov     x0, #0
    b       register_done

register_fail:
    mov     x0, #ERR_IO

register_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/*
 * io_engine_unregister_fd(fd) - Unregister fd from engine
 * x0 = file descriptor
 * Returns: x0 = 0 on success, error code on failure
 */
io_engine_unregister_fd:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    mov     x19, x0                 /* fd */
    
    /* Get engine fd */
    ldr     x1, =current_engine
    ldr     w20, [x1, #4]           /* engine_fd */
    
    /* epoll_ctl(EPOLL_CTL_DEL) */
    mov     x0, x20                 /* epfd */
    mov     x1, #2                  /* EPOLL_CTL_DEL */
    mov     x2, x19                 /* fd */
    mov     x3, #0                  /* event = NULL */
    mov     x8, #21                 /* SYS_EPOLL_CTL */
    svc     #0
    
    cmp     x0, #0
    blt     unregister_fail
    mov     x0, #0
    b       unregister_done

unregister_fail:
    mov     x0, #ERR_IO

unregister_done:
    ldp     x29, x30, [sp], #16
    ret

/* ========================================================================
 * Event Waiting
 * ======================================================================== */

/*
 * io_engine_wait_events(events, max_events, timeout) - Wait for I/O events
 * x0 = pointer to event array
 * x1 = max events
 * x2 = timeout in milliseconds (-1 = infinite)
 * Returns: x0 = number of events, or error code on failure
 */
io_engine_wait_events:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    
    mov     x19, x0                 /* events array */
    mov     x20, x1                 /* max events */
    
    /* Get engine fd */
    ldr     x3, =current_engine
    ldr     w21, [x3, #4]           /* engine_fd */
    
    /* epoll_wait */
    mov     x0, x21                 /* epfd */
    ldr     x1, =epoll_events       /* events buffer */
    cmp     x20, #32
    csel    x2, x20, x2, le         /* min(max_events, 32) */
    mov     x3, x2                  /* timeout */
    mov     x4, #0                  /* sigmask = NULL */
    mov     x5, #0
    mov     x8, #22                 /* SYS_EPOLL_WAIT */
    svc     #0
    
    cmp     x0, #0
    blt     wait_fail
    
    /* Convert epoll_events to generic event format */
    mov     x21, x0                 /* num_events */
    mov     x22, #0                 /* event index */
    ldr     x23, =epoll_events
    
convert_loop:
    cmp     x22, x21
    bge     convert_done
    
    /* Calculate offsets */
    mov     x24, x22, lsl #4        /* index * 16 */
    add     x25, x19, x24           /* dst event */
    add     x26, x23, x24           /* src epoll_event */
    
    /* Copy and convert */
    ldr     w4, [x26, #8]           /* epoll_event.data.fd */
    str     w4, [x25]               /* event.fd */
    
    ldr     w4, [x26]               /* epoll_event.events */
    /* Mask to get relevant flags */
    and     w4, w4, #0xFFF
    str     w4, [x25, #4]           /* event.flags */
    
    ldr     x4, [x26, #8]           /* data */
    str     x4, [x25, #8]           /* event.data */
    
    add     x22, x22, #1
    b       convert_loop

convert_done:
    mov     x0, x21                 /* Return number of events */
    b       wait_done

wait_fail:
    /* Check if EINTR */
    cmp     x0, #-4                 /* -EINTR */
    beq     wait_eintr
    mov     x0, #ERR_IO
    b       wait_done

wait_eintr:
    mov     x0, #0                  /* No events, retry */

wait_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ========================================================================
 * Engine Cleanup
 * ======================================================================== */

/*
 * io_engine_close() - Close I/O engine
 */
io_engine_close:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    
    /* Get engine fd */
    ldr     x1, =current_engine
    ldr     w0, [x1, #4]            /* engine_fd */
    
    cmp     w0, #0
    blt     engine_close_done
    
    /* Close epoll fd */
    mov     x8, #57                 /* SYS_CLOSE */
    svc     #0
    
    /* Clear engine structure */
    ldr     x1, =current_engine
    mov     x2, #0
    str     x2, [x1]                /* Clear all 32 bytes */
    str     x2, [x1, #8]
    str     x2, [x1, #16]
    str     x2, [x1, #24]

engine_close_done:
    ldp     x29, x30, [sp], #16
    ret

