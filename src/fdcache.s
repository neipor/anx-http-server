/* src/fdcache.s - per-worker open-file-descriptor cache (B9)
 *
 * Goal: kill the openat + close syscalls on the sendfile path for files that
 * fall outside the in-memory body cache (>= ~14.5KB), where anx was measured
 * ~20us/req behind nginx open_file_cache.
 *
 * Model: SHARED fd, owned by the cache table, referenced-counted by conns.
 *   - fdc_get(path,size,mt_sec,mt_nsec) -> x0 = fd (>=0) or -1 (miss),
 *     x1 = table slot index (valid with the fd).
 *     On hit: bump the entry refcount; the caller borrows the fd and MUST
 *     later call fdc_put_slot(slot). The fd is NEVER closed while refs > 0.
 *   - fdc_put(fd,path,size,mt_sec,mt_nsec) -> w1 = slot or -1: INSERT ONLY,
 *     called at an INLINE completion where path_buffer/stat_buffer are still
 *     THIS request's. Picks the hash slot; invalid -> store; valid+borrowed
 *     (refc>0) -> skip; valid+idle -> evict + store; size == 0 -> skip.
 *     NEVER closes the fd on skip: the caller owns it and decides (inline
 *     completion closes it, event-loop handoff keeps serving with it).
 *   - fdc_put_borrow(...): fdc_put + bump the entry refcount to 1. For
 *     event-loop handoffs where the conn keeps using the freshly inserted
 *     fd: cf_finish returns the borrow via fdc_put_slot, so eviction can
 *     never close a mid-flight fd. Returns slot or -1 (fd left open).
 *   - fdc_put_slot(slot): decrement a borrow's refcount. No key, no scan:
 *     the slot recorded at fdc_get time IS the identity. Floor at 0.
 *
 * Correctness contract (mirrors cache.s): key = (size, st_mtim.tv_sec,
 * st_mtim.tv_nsec) from the route-time NEWFSTATAT, plus an exact NUL-terminated
 * path strcmp to guard 64-bit hash collisions. File replacement changes the key,
 * force-missing the next fdc_get; the stale fd is evicted at the next insert.
 *
 * sendfile(offset_ptr) does NOT advance the fd's file position, so N conns may
 * sendfile the same cached fd concurrently, each with its own offset pointer
 * (the global sendfile_offset is only live inside one inline loop; the event
 * loop resumes from per-conn CONN_FILE_OFF_OFF).
 *
 * Deferred completions (cf_finish / conn_close, where the worker may have
 * parsed other requests and overwritten the path/stat globals) MUST NOT call
 * fdc_put: a borrow returns via fdc_put_slot(slot) (key-free), an openat fd
 * is native-closed. Only the inline site may insert.
 *
 * API (preserve x19-x28, clobber x0-x18):
 *   fdc_get(x0=path,x1=size,x2=mt_sec,x3=mt_nsec) -> x0=fd/-1, x1=slot
 *   fdc_put(x0=fd,x1=path,x2=size,x3=mt_sec,x4=mt_nsec)
 *   fdc_put_slot(x0=slot)
 *   fdc_discard(fd) -> unlink an entry by fd (master reload safety)
 */

.include "src/defs.s"

.global fdc_get
.global fdc_put
.global fdc_put_borrow
.global fdc_put_slot
.global fdc_discard
.extern cache_hash

.text

/* fdc_get(path,size,mt_sec,mt_nsec) -> x0 = fd or -1, x1 = slot index */
fdc_get:
    stp x29, x30, [sp, #-64]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]

    mov x19, x0                     /* path */
    mov x20, x1                     /* size (u32) */
    mov x21, x2                     /* mt_sec (u64) */
    mov x22, x3                     /* mt_nsec (u64) */

    cbz x20, fd_miss                /* never cache empty files */

    bl cache_hash                   /* x1 = FNV-1a */
    and x2, x1, #(FDC_ENTRIES-1)
    ldr x0, =fdc_entries
    mov x3, #FDC_ENTRY_SIZE
    madd x0, x2, x3, x0             /* x0 = slot */
    mov x24, x0                     /* slot ptr */

    ldr w4, [x0, #FDC_VALID_OFF]
    cbz w4, fd_miss
    ldr x5, [x0, #FDC_HASH_OFF]
    cmp x5, x1
    bne fd_miss
    ldr w5, [x0, #FDC_SIZE_OFF]
    cmp w5, w20
    bne fd_miss
    ldr x5, [x0, #FDC_MTSEC_OFF]
    cmp x5, x21
    bne fd_miss
    ldr x5, [x0, #FDC_MTNSEC_OFF]
    cmp x5, x22
    bne fd_miss

    /* exact-path check: slot + FDC_PATH_OFF vs request path */
    add x5, x0, #FDC_PATH_OFF
    mov x8, x19
fd_pcmp:
    ldrb w6, [x5], #1
    ldrb w7, [x8], #1
    cmp w6, w7
    bne fd_miss
    cbnz w6, fd_pcmp

    /* hit: bump refcount, return the fd and the slot index */
    ldr w9, [x24, #FDC_REFC_OFF]
    add w9, w9, #1
    str w9, [x24, #FDC_REFC_OFF]
    ldr w0, [x24, #FDC_FD_OFF]      /* fd */
    mov w1, w2                      /* slot index */
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

fd_miss:
    mov x0, #-1
    mov x1, #-1
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #64
    ret

/* fdc_put(fd,path,size,mt_sec,mt_nsec): INSERT ONLY (inline completions) */
fdc_put:
    stp x29, x30, [sp, #-112]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    stp x27, x28, [sp, #80]

    mov x19, x0                     /* fd */
    mov x20, x1                     /* path */
    mov x21, x2                     /* size (u32) */
    mov x22, x3                     /* mt_sec (u64) */
    mov x23, x4                     /* mt_nsec (u64) */

    cbz w21, fdc_skip              /* size 0: never cache (caller keeps fd) */

    mov x0, x20
    bl cache_hash
    mov x27, x1                     /* save full hash (x1 clobbered below) */
    and x26, x1, #(FDC_ENTRIES-1)
    mov x25, x26                    /* slot index survives fdc_pcopy (x26 busy) */
    ldr x24, =fdc_entries
    mov x0, x26
    mov x1, #FDC_ENTRY_SIZE
    mul x0, x0, x1
    add x0, x0, x24
    mov x28, x0                     /* slot ptr */

    /* victim: if valid and borrowed (refcount > 0), never close it; skip
     * caching this fd (the caller keeps it open). valid+idle -> evict. */
    ldr w9, [x0, #FDC_VALID_OFF]
    cbz w9, fdc_store
    ldr w9, [x0, #FDC_REFC_OFF]
    cbnz w9, fdc_skip
fdc_evict:
    ldr w9, [x28, #FDC_FD_OFF]
    mov w0, w9
    mov x8, SYS_CLOSE
    svc #0
fdc_store:
    str x27, [x28, #FDC_HASH_OFF]    /* real path hash (saved in x27) */
    mov x9, x19
    str w9, [x28, #FDC_FD_OFF]
    str w21, [x28, #FDC_SIZE_OFF]
    str x22, [x28, #FDC_MTSEC_OFF]
    str x23, [x28, #FDC_MTNSEC_OFF]
    mov w9, #0
    str w9, [x28, #FDC_REFC_OFF]     /* inserted: nobody holds it yet */
    mov w9, #1
    str w9, [x28, #FDC_VALID_OFF]
    /* store path (exact-key check) */
    add x5, x28, #FDC_PATH_OFF
    mov x8, x20
    mov x26, #0
fdc_pcopy:
    cmp x26, #FDC_PATH_CAP
    bge fdc_pdone
    ldrb w6, [x8], #1
    strb w6, [x5], #1
    add x26, x26, #1
    cbnz w6, fdc_pcopy
fdc_pdone:
    strb wzr, [x5]
    b fdc_put_done
fdc_skip:
    /* cannot evict a borrowed slot (or size 0): report -1, leave the fd
     * OPEN - the caller owns it (inline completion closes it; an event-loop
     * handoff keeps serving the body with it). */
    mov x25, #-1
fdc_put_done:
    mov w1, w25                     /* slot index, or -1 on skip */
    ldp x27, x28, [sp, #80]
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #112
    ret

/* fdc_put_borrow(fd,path,size,mt_sec,mt_nsec) -> w1 = slot or -1
 * fdc_put + bump the entry refcount to 1: the caller keeps USING the fd
 * (event-loop handoff) and must fdc_put_slot(slot) at completion. On skip
 * returns -1 with the fd left open for the caller (cf_finish native-closes
 * it - FD_CACHED set, BORROWED clear). */
fdc_put_borrow:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x27, x28, [sp, #16]
    bl fdc_put
    /* w1 carries the slot; -1 arrives 32-bit zero-extended (0xFFFFFFFF), so
     * the skip test MUST be 32-bit - a 64-bit compare would fall through to
     * madd with x28 = 0xFFFFFFFF -> a ~549GB wild index. */
    mov x28, x1                     /* zero-extend: slot 0-255, or 0xFFFFFFFF */
    cmn w28, #1                     /* 32-bit test: -1 zero-extended = 0xFFFFFFFF */
    beq fpb_done
    ldr x9, =fdc_entries
    mov x1, #FDC_ENTRY_SIZE
    madd x0, x28, x1, x9
    ldr w9, [x0, #FDC_REFC_OFF]
    add w9, w9, #1
    str w9, [x0, #FDC_REFC_OFF]
fpb_done:
    mov w1, w28
    ldp x27, x28, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

/* fdc_put_slot(slot): return a borrow - decrement the slot's refcount */
fdc_put_slot:
    cmn x0, #1
    beq fps_out                    /* defensive: no slot recorded */
    ldr x1, =fdc_entries
    mov x2, #FDC_ENTRY_SIZE
    madd x0, x0, x2, x1
    ldr w9, [x0, #FDC_VALID_OFF]
    cbz w9, fps_out               /* defensive: slot not resident */
    ldr w9, [x0, #FDC_REFC_OFF]
    subs w9, w9, #1
    csel w9, w9, wzr, gt          /* floor at 0 (defensive) */
    str w9, [x0, #FDC_REFC_OFF]
fps_out:
    ret

/* fdc_discard(fd): unlink an entry by fd (master reload safety). Force-close
 * the slot (caller ensures no in-flight user). */
fdc_discard:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]

    mov x19, x0                     /* fd */
    ldr x21, =fdc_entries
    mov x22, #0
fdd_loop:
    cmp x22, #FDC_ENTRIES
    bge fdd_done
    mov x0, x22
    mov x1, #FDC_ENTRY_SIZE
    mul x0, x0, x1
    add x0, x0, x21
    ldr w9, [x0, #FDC_VALID_OFF]
    cbz w9, fdd_next
    ldr w9, [x0, #FDC_FD_OFF]
    cmp w9, w19
    bne fdd_next
    mov w0, w19
    mov x8, SYS_CLOSE
    svc #0
    mov w9, #0
    str w9, [x0, #FDC_VALID_OFF]
    mov w9, #-1
    str w9, [x0, #FDC_FD_OFF]
    str wzr, [x0, #FDC_REFC_OFF]
    b fdd_done
fdd_next:
    add x22, x22, #1
    b fdd_loop
fdd_done:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret