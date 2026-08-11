/* src/cache.s - in-memory static-file cache (B8)
 *
 * Every small static file the server actually serves is read once into a
 * private arena (per worker; pages are COW after fork, nothing is shared
 * mutable) and replayed from RAM with zero file syscalls on the hot path.
 *
 * Correctness contract (mirrors the route-time stat in http.s):
 *   - The invalidation key is (size, st_mtim.tv_sec, st_mtim.tv_nsec) taken
 *     from the NEWFSTATAT the router performed for THIS request. The .gz probe
 *     in serve_file only overwrites stat_buffer on success, and success
 *     branches to gzip serving before serve_file_direct, so at lookup time
 *     stat_buffer still holds the fresh route stat. Lookup costs zero syscalls.
 *   - Range requests, CGI-mapped extensions (.py/.sh/.cgi) and the dynamic
 *     gzip path never take the cache (guards live in http.s).
 *   - Only regular files 1..CACHE_MAX_SIZE are cached; the content is read
 *     from the fd the normal path would sendfile, so it is byte-identical to
 *     what sendfile would have shipped.
 *
 * Layout: CACHE_ENTRIES direct-mapped slots indexed by (hash & (N-1)). A
 * collision evicts the previous occupant - correctness is preserved because
 * the (size, mtime) key is re-validated on every lookup and fill, and the
 * NUL-terminated path is stored at slot+CACHE_PATH_OFF and strcmp'd on every
 * hit, so a slot only ever serves what its key says it holds. A full 64-bit
 * hash collision between two different paths is servable by neither: the
 * strcmp bails to the normal path.
 *
 * API (preserve x19-x28, clobber x0-x18, like every other bl target):
 *   cache_lookup(x0=path, x1=size, x2=mtime_sec, x3=mtime_nsec)
 *       -> x0 = entry ptr, or 0 on miss. No syscalls.
 *   cache_maybe_fill(x0=path, x1=size, x2=mtime_sec, x3=mtime_nsec)
 *       -> x0 = 1 entry fresh/filled, 0 skipped (empty, too big, CGI, or I/O
 *       error). Runs on every file request, so it first re-checks the slot
 *       in memory and only opens/reads when the slot is empty or stale.
 */

.include "src/defs.s"

.global cache_lookup
.global cache_maybe_fill
.extern get_extension
.extern strcmp
.extern cache_arena
.extern cache_entries

.text

/* ---------------------------------------------------------------------------
 * cache_hash(x0 = NUL-terminated str) -> x1 = FNV-1a 64
 * Clobbers x0-x3 only. Callee-saved registers are not touched.
 * ------------------------------------------------------------------------- */
.global cache_hash
cache_hash:
    mov x1, #0x2325
    movk x1, #0x8422, lsl #16
    movk x1, #0x9ce4, lsl #32
    movk x1, #0xcbf2, lsl #48      /* offset basis 0xcbf29ce484222325 */
    mov x2, #0x01b3
    movk x2, #0x0001, lsl #32      /* FNV prime 0x0000000100000001b3 */
ch_loop:
    ldrb w3, [x0], #1
    cbz w3, ch_done
    eor x1, x1, x3
    mul x1, x1, x2
    b ch_loop
ch_done:
    ret

/* ---------------------------------------------------------------------------
 * cache_lookup(x0=path, x1=size, x2=mtime_sec, x3=mtime_nsec)
 *   -> x0 = entry ptr, or 0. Pure memory: no syscalls.
 * ------------------------------------------------------------------------- */
cache_lookup:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    mov x19, x0                     /* path */
    mov x20, x1                     /* size */
    mov x21, x2                     /* mtime_sec */
    mov x22, x3                     /* mtime_nsec */

    bl cache_hash                   /* x1 = hash */
    and x2, x1, #(CACHE_ENTRIES-1)
    ldr x0, =cache_entries
    mov x3, #CACHE_ENTRY_SIZE
    madd x0, x2, x3, x0             /* x0 = entry */

    ldr w4, [x0, #CACHE_VALID_OFF]
    cbz w4, cl_miss
    ldr x5, [x0, #CACHE_HASH_OFF]
    cmp x5, x1
    bne cl_miss
    ldr w5, [x0, #CACHE_SIZE_OFF]
    cmp w5, w20
    bne cl_miss
    ldr x5, [x0, #CACHE_MTSEC_OFF]
    cmp x5, x21
    bne cl_miss
    ldr x5, [x0, #CACHE_MTNSEC_OFF]
    cmp x5, x22
    bne cl_miss

    /* Exact-path check: stored NUL-terminated path (slot+7168) vs request.
     * Guards the remaining possibility of a full 64-bit hash collision.
     * Bail (miss) on mismatch; never evict, never serve. */
    ldr x5, [x0, #CACHE_CONTENT_OFF]
    add x5, x5, #0x3000            /* +CACHE_PATH_OFF=14848 (too big for one imm) */
    add x5, x5, #0x0a00
    mov x8, x19                     /* path cursor */
cl_pcmp:
    ldrb w6, [x5], #1
    ldrb w7, [x8], #1
    cmp w6, w7
    bne cl_miss
    cbnz w6, cl_pcmp

    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret
cl_miss:
    mov x0, #0
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

/* ---------------------------------------------------------------------------
 * cache_maybe_fill(x0=path, x1=size, x2=mtime_sec, x3=mtime_nsec)
 *   -> x0 = 1 entry fresh (early-out) or freshly stored; 0 = skipped.
 *   Called on every file request, so the slot is re-checked in memory first:
 *   a fresh entry returns without a single syscall. open+read+close happens
 *   only when the slot is empty or its key no longer matches the disk.
 * ------------------------------------------------------------------------- */
cache_maybe_fill:
    stp x29, x30, [sp, #-96]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    mov x19, x0                     /* path */
    mov x20, x1                     /* size */
    mov x21, x2                     /* mtime_sec */
    mov x22, x3                     /* mtime_nsec */

    cbz x20, cmf_skip               /* never cache empty files */
    mov x9, #CACHE_MAX_SIZE
    cmp x20, x9
    bgt cmf_skip                    /* too big for the arena */

    /* CGI exclusion: .py / .sh / .cgi are never cached */
    mov x0, x19
    bl get_extension
    cbz x0, cmf_ext_ok
    mov x23, x0
    ldr x1, =ext_py
    bl strcmp
    cbz x0, cmf_skip
    mov x0, x23
    ldr x1, =ext_sh
    bl strcmp
    cbz x0, cmf_skip
    mov x0, x23
    ldr x1, =ext_cgi
    bl strcmp
    cbz x0, cmf_skip
cmf_ext_ok:

    mov x0, x19
    bl cache_hash                   /* x1 = hash */
    and x24, x1, #(CACHE_ENTRIES-1) /* slot index */
    mov x25, x1                     /* keep the hash: x1 is clobbered below */

    /* ---- early-out: slot already holds exactly this file ---- */
    ldr x9, =cache_entries
    mov x10, #CACHE_ENTRY_SIZE
    madd x9, x24, x10, x9
    ldr w10, [x9, #CACHE_VALID_OFF]
    cbz w10, cmf_load
    ldr x10, [x9, #CACHE_HASH_OFF]
    cmp x10, x1
    bne cmf_load
    ldr w10, [x9, #CACHE_SIZE_OFF]
    cmp w10, w20
    bne cmf_load
    ldr x10, [x9, #CACHE_MTSEC_OFF]
    cmp x10, x21
    bne cmf_load
    ldr x10, [x9, #CACHE_MTNSEC_OFF]
    cmp x10, x22
    bne cmf_load
    mov x0, #1                      /* already fresh: nothing to do */
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret

cmf_load:
    /* path must fit beside the body: skip caching if too long */
    mov x26, x19                    /* strlen(path_buffer) */
cl_len:
    ldrb w13, [x26], #1
    cbnz w13, cl_len
    sub x26, x26, x19
    sub x26, x26, #1                /* x26 = length (without NUL) */
    cmp x26, #CACHE_PATH_CAP
    bhs cmf_skip

    mov x0, AT_FDCWD
    mov x1, x19
    mov x2, O_RDONLY
    mov x3, #0
    mov x8, SYS_OPENAT
    svc #0
    cmp x0, #0
    blt cmf_skip
    mov x23, x0                     /* fd */

    ldr x9, =cache_arena
    mov x10, #CACHE_SLOT
    madd x9, x24, x10, x9           /* x9 = content base */

    mov x11, #0                     /* total read */
cmf_rloop:
    cmp x11, x20
    bhs cmf_read_done
    mov x0, x23
    add x1, x9, x11
    sub x2, x20, x11
    mov x8, SYS_READ
    svc #0
    cmp x0, #0
    ble cmf_read_err
    add x11, x11, x0
    b cmf_rloop
cmf_read_err:
    mov x0, x23
    mov x8, SYS_CLOSE
    svc #0
    b cmf_skip
cmf_read_done:
    mov x0, x23
    mov x8, SYS_CLOSE
    svc #0

    /* store the path at content+CACHE_PATH_OFF for the exact-key check */
    ldr x9, =cache_arena
    mov x10, #CACHE_SLOT
    madd x9, x24, x10, x9
    add x9, x9, #0x3000            /* +CACHE_PATH_OFF=14848 */
    add x9, x9, #0x0a00            /* dest */
    mov x10, x19                     /* src */
    mov x11, #0
cmf_pcopy:
    cmp x11, x26
    bhs cmf_pdone
    ldrb w12, [x10], #1
    strb w12, [x9], #1
    add x11, x11, #1
    b cmf_pcopy
cmf_pdone:
    strb wzr, [x9]

    /* ---- publish the entry ---- */
    ldr x9, =cache_entries
    mov x10, #CACHE_ENTRY_SIZE
    madd x9, x24, x10, x9
    str x25, [x9, #CACHE_HASH_OFF]      /* x25 = hash */
    str x21, [x9, #CACHE_MTSEC_OFF]
    str x22, [x9, #CACHE_MTNSEC_OFF]
    str w20, [x9, #CACHE_SIZE_OFF]
    mov w10, #1
    str w10, [x9, #CACHE_VALID_OFF]
    ldr x10, =cache_arena
    mov x11, #CACHE_SLOT
    madd x10, x24, x11, x10             /* content ptr */
    str x10, [x9, #CACHE_CONTENT_OFF]

    mov x0, #1
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret
cmf_skip:
    mov x0, #0
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #96
    ret