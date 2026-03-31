/* src/main.s - Main Entry Point */

.include "src/defs.s"

.global _start

.text

_start:
    /* Initialize defaults */
    ldr x0, =server_root    /* dest */
    ldr x1, =default_root   /* src */
    bl strcpy
    
    /* Initialize pid_file_path from default */
    ldr x0, =pid_file_path
    ldr x1, =pid_file_default
    bl strcpy

    /* Parse CLI Arguments */
    ldr x19, [sp]           /* x19 = argc */
    add x20, sp, #8         /* x20 = &argv[0] */
    
    /* Calculate envp: argv + (argc + 1) * 8 */
    add x21, x19, #1
    lsl x21, x21, #3
    add x21, x20, x21       /* x21 = envp */
    
    /* Initialize I18N (Detects Lang and sets pointers) */
    mov x0, x21
    bl i18n_init
    
    mov x21, #1             /* index = 1 */

parse_cli_loop:
    cmp x21, x19
    bge start_server_label
    
    ldr x22, [x20, x21, lsl #3] /* x22 = argv[index] */
    
    /* Check -h / --help */
    mov x0, x22
    ldr x1, =flag_h
    bl strcmp
    cmp x0, #0
    beq print_help
    
    mov x0, x22
    ldr x1, =flag_help_long
    bl strcmp
    cmp x0, #0
    beq print_help

    /* Check -v / --version */
    mov x0, x22
    ldr x1, =flag_v
    bl strcmp
    cmp x0, #0
    beq print_version
    
    mov x0, x22
    ldr x1, =flag_vers_long
    bl strcmp
    cmp x0, #0
    beq print_version

    /* Check -p / --port */
    mov x0, x22
    ldr x1, =flag_p
    bl strcmp
    cmp x0, #0
    beq handle_p
    
    mov x0, x22
    ldr x1, =flag_port_long
    bl strcmp
    cmp x0, #0
    beq handle_p
    
    /* Check -d / --dir */
    mov x0, x22
    ldr x1, =flag_d
    bl strcmp
    cmp x0, #0
    beq handle_d

    mov x0, x22
    ldr x1, =flag_dir_long
    bl strcmp
    cmp x0, #0
    beq handle_d
    
    /* Check -c / --config (legacy key=value format) */
    mov x0, x22
    ldr x1, =flag_c
    bl strcmp
    cmp x0, #0
    beq handle_c

    mov x0, x22
    ldr x1, =flag_conf_long
    bl strcmp
    cmp x0, #0
    beq handle_c

    /* Check -n / --nginx-config (nginx-style format) */
    mov x0, x22
    ldr x1, =flag_n
    bl strcmp
    cmp x0, #0
    beq handle_n

    mov x0, x22
    ldr x1, =flag_nginx_long
    bl strcmp
    cmp x0, #0
    beq handle_n

    /* Check -x / --proxy */
    mov x0, x22
    ldr x1, =flag_x
    bl strcmp
    cmp x0, #0
    beq handle_x

    mov x0, x22
    ldr x1, =flag_proxy_long
    bl strcmp
    cmp x0, #0
    beq handle_x
    
    /* Check -s / --silent */
    mov x0, x22
    ldr x1, =flag_silent
    bl strcmp
    cmp x0, #0
    beq handle_s
    
    mov x0, x22
    ldr x1, =flag_silent_long
    bl strcmp
    cmp x0, #0
    beq handle_s
    
    /* Check -daemon / --daemon */
    mov x0, x22
    ldr x1, =flag_daemon
    bl strcmp
    cmp x0, #0
    beq handle_daemon
    
    mov x0, x22
    ldr x1, =flag_daemon_long
    bl strcmp
    cmp x0, #0
    beq handle_daemon
    
    /* Check if Positional Arg (Does not start with -) */
    ldrb w0, [x22]
    cmp w0, #'-'
    bne handle_positional
    
    /* Unknown flag? Ignore. */
    add x21, x21, #1
    b parse_cli_loop

handle_p:
    add x21, x21, #1
    cmp x21, x19
    bge start_server_label
    ldr x0, [x20, x21, lsl #3] /* port string */
    bl atoi
    bl htons
    ldr x1, =server_port
    strh w0, [x1]
    add x21, x21, #1
    b parse_cli_loop

handle_d:
    add x21, x21, #1
    cmp x21, x19
    bge start_server_label
    ldr x1, [x20, x21, lsl #3] /* src: dir string */
    ldr x0, =server_root       /* dest */
    bl strcpy
    add x21, x21, #1
    b parse_cli_loop

handle_c:
    add x21, x21, #1
    cmp x21, x19
    bge start_server_label
    ldr x0, [x20, x21, lsl #3] /* config file path */
    bl read_config_file
    add x21, x21, #1
    b parse_cli_loop

handle_n:
    add x21, x21, #1
    cmp x21, x19
    bge start_server_label
    ldr x0, [x20, x21, lsl #3] /* nginx config file path */
    bl nginx_read_config
    add x21, x21, #1
    b parse_cli_loop

handle_x:
    /* Enable Proxy (default to 127.0.0.1) */
    mov x0, #0x7F
    mov x1, #0x01
    lsl x1, x1, #24
    orr x0, x0, x1
    ldr x1, =upstream_ip
    str w0, [x1]
    
    add x21, x21, #1
    b parse_cli_loop

handle_s:
    /* Set Silent Mode */
    ldr x0, =is_silent
    mov w1, #1
    str w1, [x0]
    add x21, x21, #1
    b parse_cli_loop

handle_daemon:
    ldr x0, =is_daemon
    mov w1, #1
    str w1, [x0]
    add x21, x21, #1
    b parse_cli_loop

handle_positional:
    /* Treat as Root Dir */
    ldr x1, [x20, x21, lsl #3]
    ldr x0, =server_root
    bl strcpy
    add x21, x21, #1
    b parse_cli_loop

print_help:
    mov x0, STDOUT
    ldr x1, =p_msg_help
    ldr x1, [x1]        /* Load pointer to string */
    ldr x2, =p_len_help
    ldr x2, [x2]        /* Load length */
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, #0
    mov x8, SYS_EXIT
    svc #0

print_version:
    mov x0, STDOUT
    ldr x1, =msg_version_current
    ldr x2, =len_version_current
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, #10
    strb w0, [sp, #-16]!
    mov x0, STDOUT
    mov x1, sp
    mov x2, #1
    mov x8, SYS_WRITE
    svc #0
    add sp, sp, #16

    mov x0, #0
    mov x8, SYS_EXIT
    svc #0

start_server_label:
    /* 1. Print Banner Title "✨ ANX Web Server " */
    mov x0, STDOUT
    ldr x1, =p_msg_welcome_title
    ldr x1, [x1]
    ldr x2, =p_len_welcome_title
    ldr x2, [x2]
    mov x8, SYS_WRITE
    svc #0
    
    /* 2. Print Dynamic Git Version */
    mov x0, STDOUT
    ldr x1, =msg_version_current
    ldr x2, =len_version_current
    mov x8, SYS_WRITE
    svc #0

    /* 3. Print Banner Description */
    mov x0, STDOUT
    ldr x1, =p_msg_welcome_desc
    ldr x1, [x1]
    ldr x2, =p_len_welcome_desc
    ldr x2, [x2]
    mov x8, SYS_WRITE
    svc #0
    
    /* Port */
    mov x0, STDOUT
    ldr x1, =msg_port
    ldr x2, =len_msg_port
    mov x8, SYS_WRITE
    svc #0
    
    ldr x0, =server_port
    ldrh w0, [x0]
    bl ntohs
    ldr x1, =num_buffer
    bl itoa
    mov x2, x0
    mov x0, STDOUT
    ldr x1, =num_buffer
    mov x8, SYS_WRITE
    svc #0
    
    /* Root */
    mov x0, STDOUT
    ldr x1, =msg_root
    ldr x2, =len_msg_root
    mov x8, SYS_WRITE
    svc #0
    
    ldr x0, =server_root
    bl strlen
    mov x2, x0
    mov x0, STDOUT
    ldr x1, =server_root
    mov x8, SYS_WRITE
    svc #0

    /* Detect CPU count */
    bl detect_cpu_count
    ldr x1, =worker_count
    str w0, [x1]
    
    /* Print Workers Message */
    mov x0, STDOUT
    ldr x1, =msg_workers_prefix
    ldr x2, =len_workers_prefix
    mov x8, SYS_WRITE
    svc #0
    
    ldr x0, =worker_count
    ldr w0, [x0]
    ldr x1, =num_buffer
    bl itoa
    mov x2, x0
    mov x0, STDOUT
    ldr x1, =num_buffer
    mov x8, SYS_WRITE
    svc #0
    
    mov x0, STDOUT
    ldr x1, =msg_workers_suffix
    ldr x2, =len_workers_suffix
    mov x8, SYS_WRITE
    svc #0

    /* Check Daemon */
    ldr x0, =is_daemon
    ldr w0, [x0]
    cbz w0, skip_daemon
    
    /* Print Daemon Msg */
    mov x0, STDOUT
    ldr x1, =msg_daemon
    ldr x2, =len_msg_daemon
    mov x8, SYS_WRITE
    svc #0
    
    bl daemonize
    
skip_daemon:

    /* Write PID File */
    mov x0, AT_FDCWD
    ldr x1, =pid_file_path
    mov x2, #0x241          /* O_WRONLY | O_CREAT | O_TRUNC */
    mov x3, #420            /* 0644 */
    mov x8, SYS_OPENAT
    svc #0
    
    cmp x0, #0
    blt pid_fail
    mov x19, x0             /* pid_fd */
    
    /* Get PID */
    mov x8, SYS_GETPID
    svc #0
    
    /* Convert to String */
    ldr x1, =num_buffer
    bl itoa
    mov x2, x0              /* len */
    
    /* Write to file */
    mov x0, x19
    ldr x1, =num_buffer
    mov x8, SYS_WRITE
    svc #0
    
    /* Close */
    mov x0, x19
    mov x8, SYS_CLOSE
    svc #0
    
pid_fail:

    /* Initialize Server (create listen socket) */
    bl setup_signals
    bl server_init
    mov x19, x0             /* x19 = listen_fd */

    /* Fork worker processes */
    ldr x0, =worker_count
    ldr w20, [x0]           /* x20 = number of workers to fork */
    mov x21, #0              /* x21 = worker index */

fork_workers:
    cmp w21, w20
    bge master_loop          /* All workers forked, go to master */
    
    /* clone(SIGCHLD, 0, 0, 0, 0) - equivalent to fork() on aarch64 */
    mov x0, #SIGCHLD_FLAG    /* SIGCHLD */
    mov x1, #0               /* stack = NULL (use parent's) */
    mov x2, #0               /* parent_tid */
    mov x3, #0               /* tls */
    mov x4, #0               /* child_tid */
    mov x8, SYS_CLONE
    svc #0
    
    cmp x0, #0
    beq worker_start         /* Child -> become worker */
    blt fork_failed          /* Error (negative) */
    
    /* Parent: save child PID */
    ldr x1, =worker_pids
    str w0, [x1, x21, lsl #2]
    add x21, x21, #1
    b fork_workers

fork_failed:
    /* Log and continue with fewer workers */
    add x21, x21, #1
    b fork_workers

worker_start:
    /* Child process: run accept loop */
    mov x0, x19              /* listen_fd */
    bl accept_loop
    /* Should not return */
    mov x0, #0
    mov x8, SYS_EXIT
    svc #0

master_loop:
    /* Master process: monitor workers, restart crashed ones */
    /* Wait for any child to exit */
    sub sp, sp, #16
    mov x0, #-1              /* Wait for any child */
    mov x1, sp               /* &wstatus */
    mov x2, #0               /* options: block */
    mov x3, #0               /* rusage */
    mov x8, SYS_WAIT4
    svc #0
    add sp, sp, #16          /* Restore stack */
    
    cmp x0, #0
    blt master_check_signal  /* Error (maybe EINTR from signal) */
    
    mov x22, x0              /* x22 = exited child PID */
    
    /* Find which worker slot this was */
    mov x23, #0
find_slot:
    cmp w23, w20
    bge respawn_skip         /* Not found, skip */
    ldr x1, =worker_pids
    ldr w2, [x1, x23, lsl #2]
    cmp w2, w22
    beq respawn_worker
    add x23, x23, #1
    b find_slot

respawn_worker:
    /* clone(SIGCHLD, 0, 0, 0, 0) - fork a replacement worker */
    mov x0, #SIGCHLD_FLAG
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov x8, SYS_CLONE
    svc #0
    
    cmp x0, #0
    beq worker_start         /* Child -> become worker */
    blt respawn_skip         /* Fork failed, skip */
    
    /* Save new PID in the slot */
    ldr x1, =worker_pids
    str w0, [x1, x23, lsl #2]

respawn_skip:
    b master_loop

master_check_signal:
    /* Check if it was EINTR (signal interruption) */
    /* Check reload flag (SIGHUP sets this) */
    ldr x1, =reload_requested
    ldr w1, [x1]
    cbnz w1, do_reload

    mov x1, #-EINTR
    cmp x0, x1
    beq master_loop          /* Retry on EINTR */
    /* Other error - still keep looping */
    b master_loop

do_reload:
    /* Clear reload flag */
    ldr x0, =reload_requested
    str wzr, [x0]

    /* Kill all current workers */
    ldr x0, =worker_count
    ldr w1, [x0]
    mov x2, #0
reload_kill_loop:
    cmp w2, w1
    bge reload_kill_done
    ldr x3, =worker_pids
    ldr w0, [x3, x2, lsl #2]
    cbz w0, reload_kill_next
    mov x8, #129              /* SYS_KILL */
    mov x1, #15               /* SIGTERM */
    svc #0
    /* Restore w1 = worker_count */
    ldr x0, =worker_count
    ldr w1, [x0]
reload_kill_next:
    add x2, x2, #1
    b reload_kill_loop

reload_kill_done:
    /* Wait for all workers to exit */
reload_wait_loop:
    sub sp, sp, #16
    mov x0, #-1
    mov x1, sp
    mov x2, #0
    mov x3, #0
    mov x8, SYS_WAIT4
    svc #0
    add sp, sp, #16
    cmp x0, #0
    bgt reload_wait_loop

    /* Re-read config (uses saved config path if any) */
    /* Re-fork workers */
    ldr x0, =worker_count
    ldr w20, [x0]
    mov x21, #0
    b fork_workers

/* detect_cpu_count() -> count in x0 */
detect_cpu_count:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    str x21, [sp, #32]
    
    /* Read /sys/devices/system/cpu/online */
    mov x0, AT_FDCWD
    ldr x1, =cpu_online_path
    mov x2, O_RDONLY
    mov x3, #0
    mov x8, SYS_OPENAT
    svc #0
    
    cmp x0, #0
    blt cpu_default           /* Can't read, use default */
    
    mov x19, x0              /* fd */
    ldr x1, =config_buffer    /* use config_buffer as temp */
    mov x2, #15
    mov x0, x19
    mov x8, SYS_READ
    svc #0
    
    mov x20, x0              /* bytes read */
    
    /* Close fd */
    mov x0, x19
    mov x8, SYS_CLOSE
    svc #0
    
    cmp x20, #0
    ble cpu_default
    
    /* Null-terminate */
    ldr x0, =config_buffer
    strb wzr, [x0, x20]
    
    /* Parse "0-N" format -> N+1 CPUs */
    mov x1, #0
cpu_find_dash:
    ldrb w2, [x0, x1]
    cbz w2, cpu_single        /* No dash = single CPU */
    cmp w2, #'-'
    beq cpu_found_dash
    add x1, x1, #1
    cmp x1, x20
    blt cpu_find_dash
    b cpu_single

cpu_found_dash:
    add x0, x0, x1
    add x0, x0, #1           /* Skip '-' */
    bl atoi
    add x0, x0, #1           /* N+1 */
    b cpu_done

cpu_single:
    mov x0, #1
    b cpu_done

cpu_default:
    mov x0, #4                /* Default 4 workers */

cpu_done:
    /* Clamp to 1-64 */
    cmp x0, #1
    blt cpu_clamp_min
    cmp x0, #64
    bgt cpu_clamp_max
    b cpu_ret
cpu_clamp_min:
    mov x0, #1
    b cpu_ret
cpu_clamp_max:
    mov x0, #64
cpu_ret:
    ldr x21, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

setup_signals:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    
    ldr x0, =shutdown_handler
    str x0, [sp, #16]       /* handler */
    str xzr, [sp, #24]      /* flags/mask */
    
    /* SIGINT */
    mov x0, #2
    add x1, sp, #16
    mov x2, #0
    mov x3, #8
    mov x8, SYS_RT_SIGACTION
    svc #0
    
    /* SIGTERM */
    mov x0, #15
    add x1, sp, #16
    mov x2, #0
    mov x3, #8
    mov x8, SYS_RT_SIGACTION
    svc #0

    /* SIGHUP - graceful reload */
    ldr x0, =sighup_handler
    str x0, [sp, #16]       /* handler */
    str xzr, [sp, #24]      /* flags/mask */
    mov x0, #1              /* SIGHUP */
    add x1, sp, #16
    mov x2, #0
    mov x3, #8
    mov x8, SYS_RT_SIGACTION
    svc #0
    
    ldp x29, x30, [sp], #32
    ret

sighup_handler:
    ldr x0, =reload_requested
    mov w1, #1
    str w1, [x0]
    ret

shutdown_handler:
    /* Send SIGTERM to all worker processes */
    ldr x0, =worker_count
    ldr w1, [x0]
    mov x2, #0               /* index */
shutdown_kill_loop:
    cmp w2, w1
    bge shutdown_cleanup
    ldr x3, =worker_pids
    ldr w0, [x3, x2, lsl #2]
    cbz w0, shutdown_next
    /* kill(pid, SIGTERM) */
    mov x8, #129              /* SYS_KILL */
    mov x1, #15               /* SIGTERM */
    svc #0
shutdown_next:
    add x2, x2, #1
    b shutdown_kill_loop

shutdown_cleanup:
    /* Unlink PID file */
    mov x0, AT_FDCWD
    ldr x1, =pid_file_path
    mov x2, #0
    mov x8, SYS_UNLINKAT
    svc #0
    
    /* Exit */
    mov x0, #0
    mov x8, SYS_EXIT
    svc #0
