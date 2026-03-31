/* src/config_nginx.s - Nginx-Compatible Configuration Parser */
/* Parses nginx-style config: directives, server{}, location{} blocks */

.include "src/defs.s"

.global nginx_read_config
.global nginx_parse_config

.text

/* =========================================================================
 * nginx_read_config(filename) - Read and parse nginx-style config file
 * x0 = path to config file
 * Returns: 0 on success, -1 on error
 * ========================================================================= */
nginx_read_config:
    stp x29, x30, [sp, #-48]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    
    /* Open config file */
    mov x1, x0             /* filename */
    mov x0, AT_FDCWD
    mov x2, O_RDONLY
    mov x3, #0
    mov x8, SYS_OPENAT
    svc #0
    cmp x0, #0
    blt nrc_error
    mov x19, x0            /* fd */
    
    /* Read file into config_buffer */
    mov x0, x19
    ldr x1, =nginx_config_buf
    mov x2, #16383         /* Max 16KB config */
    mov x8, SYS_READ
    svc #0
    mov x20, x0            /* bytes read */
    
    /* Close */
    mov x0, x19
    mov x8, SYS_CLOSE
    svc #0
    
    cmp x20, #0
    ble nrc_error
    
    /* Null terminate */
    ldr x0, =nginx_config_buf
    strb wzr, [x0, x20]
    
    /* Parse the config */
    ldr x0, =nginx_config_buf
    mov x1, x20
    bl nginx_parse_config
    
    mov x0, #0
    b nrc_done

nrc_error:
    /* Print error */
    mov x0, STDOUT
    ldr x1, =msg_nginx_conf_err
    ldr x2, =len_nginx_conf_err
    mov x8, SYS_WRITE
    svc #0
    mov x0, #-1

nrc_done:
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #48
    ret

/* =========================================================================
 * nginx_parse_config(buf, len) - Parse nginx config buffer
 * x0 = buffer pointer, x1 = length
 * Parses: worker_processes, events{}, http{}, server{}, location{}
 * ========================================================================= */
nginx_parse_config:
    stp x29, x30, [sp, #-80]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    stp x21, x22, [sp, #32]
    stp x23, x24, [sp, #48]
    stp x25, x26, [sp, #64]
    
    mov x19, x0            /* x19 = buf ptr */
    add x20, x0, x1        /* x20 = buf end */
    mov x21, #0             /* x21 = current context (0=global, 1=events, 2=http, 3=server, 4=location) */
    mov x22, #0             /* x22 = brace depth */

npc_loop:
    cmp x19, x20
    bge npc_done
    
    /* Skip whitespace and newlines */
    bl npc_skip_ws
    cmp x19, x20
    bge npc_done
    
    /* Check for comment (#) */
    ldrb w0, [x19]
    cmp w0, #'#'
    beq npc_skip_line
    
    /* Check for closing brace */
    cmp w0, #'}'
    beq npc_close_brace
    
    /* Check for opening brace (skip it) */
    cmp w0, #'{'
    beq npc_open_brace
    
    /* Read directive name */
    mov x23, x19           /* x23 = directive start */
    bl npc_read_token       /* x0 = token length, x19 advances */
    mov x24, x0            /* x24 = directive name length */
    
    cbz x24, npc_loop      /* Empty token, skip */
    
    /* Match directives based on context */
    /* Global context */
    cmp x21, #0
    beq npc_global_dir
    
    /* Events context */
    cmp x21, #1
    beq npc_events_dir
    
    /* HTTP context */
    cmp x21, #2
    beq npc_http_dir
    
    /* Server context */
    cmp x21, #3
    beq npc_server_dir
    
    /* Location context */
    cmp x21, #4
    beq npc_location_dir
    
    /* Unknown context, skip to semicolon or brace */
    bl npc_skip_to_semi
    b npc_loop

/* --- Global directives --- */
npc_global_dir:
    /* Check "worker_processes" */
    mov x0, x23
    ldr x1, =dir_worker_processes
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_worker_procs
    
    /* Check "error_log" */
    mov x0, x23
    ldr x1, =dir_error_log
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_error_log
    
    /* Check "pid" */
    mov x0, x23
    ldr x1, =dir_pid
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_pid
    
    /* Check "events" block */
    mov x0, x23
    ldr x1, =dir_events
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_enter_events
    
    /* Check "http" block */
    mov x0, x23
    ldr x1, =dir_http
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_enter_http
    
    /* Unknown directive, skip */
    bl npc_skip_to_semi
    b npc_loop

/* --- Events directives --- */
npc_events_dir:
    /* Check "worker_connections" */
    mov x0, x23
    ldr x1, =dir_worker_connections
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_worker_conn
    
    bl npc_skip_to_semi
    b npc_loop

/* --- HTTP directives --- */
npc_http_dir:
    /* Check "server" block */
    mov x0, x23
    ldr x1, =dir_server
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_enter_server
    
    /* Check "access_log" */
    mov x0, x23
    ldr x1, =dir_access_log
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_access_log
    
    /* Check "sendfile" */
    mov x0, x23
    ldr x1, =dir_sendfile
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_sendfile
    
    /* Check "keepalive_timeout" */
    mov x0, x23
    ldr x1, =dir_keepalive_timeout
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_keepalive
    
    /* Check "gzip" */
    mov x0, x23
    ldr x1, =dir_gzip
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_gzip
    
    /* Check "default_type" */
    mov x0, x23
    ldr x1, =dir_default_type
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_skip_to_semi  /* Just skip for now */
    
    /* Check "include" */
    mov x0, x23
    ldr x1, =dir_include
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_skip_to_semi  /* Just skip includes for now */
    
    bl npc_skip_to_semi
    b npc_loop

/* --- Server directives --- */
npc_server_dir:
    /* Check "listen" */
    mov x0, x23
    ldr x1, =dir_listen
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_listen
    
    /* Check "server_name" */
    mov x0, x23
    ldr x1, =dir_server_name
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_server_name
    
    /* Check "root" */
    mov x0, x23
    ldr x1, =dir_root
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_root
    
    /* Check "index" */
    mov x0, x23
    ldr x1, =dir_index
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_index
    
    /* Check "access_log" */
    mov x0, x23
    ldr x1, =dir_access_log
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_access_log
    
    /* Check "error_page" */
    mov x0, x23
    ldr x1, =dir_error_page
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_error_page
    
    /* Check "location" block */
    mov x0, x23
    ldr x1, =dir_location
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_enter_location
    
    /* Check "proxy_pass" */
    mov x0, x23
    ldr x1, =dir_proxy_pass
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_proxy_pass
    
    /* Check "client_max_body_size" */
    mov x0, x23
    ldr x1, =dir_client_max_body
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_body_size
    
    bl npc_skip_to_semi
    b npc_loop

/* --- Location directives --- */
npc_location_dir:
    /* Check "root" */
    mov x0, x23
    ldr x1, =dir_root
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_root
    
    /* Check "proxy_pass" */
    mov x0, x23
    ldr x1, =dir_proxy_pass
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_proxy_pass
    
    /* Check "index" */
    mov x0, x23
    ldr x1, =dir_index
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_parse_index
    
    /* Check "try_files" */
    mov x0, x23
    ldr x1, =dir_try_files
    mov x2, x24
    bl npc_match_dir
    cbnz x0, npc_skip_to_semi /* TODO: implement */
    
    bl npc_skip_to_semi
    b npc_loop

/* === Directive Handlers === */

npc_parse_worker_procs:
    bl npc_skip_ws
    /* Check "auto" */
    ldrb w0, [x19]
    cmp w0, #'a'
    beq npc_wp_auto
    /* Parse number */
    mov x0, x19
    bl atoi
    ldr x1, =worker_count
    str w0, [x1]
    bl npc_skip_to_semi
    b npc_loop
npc_wp_auto:
    /* Auto = use detect_cpu_count later */
    bl npc_skip_to_semi
    b npc_loop

npc_parse_error_log:
    bl npc_skip_ws
    ldr x0, =error_log_path
    bl npc_copy_value
    b npc_loop

npc_parse_pid:
    bl npc_skip_ws
    ldr x0, =pid_file_path
    bl npc_copy_value
    b npc_loop

npc_parse_worker_conn:
    bl npc_skip_ws
    mov x0, x19
    bl atoi
    ldr x1, =max_connections
    str w0, [x1]
    bl npc_skip_to_semi
    b npc_loop

npc_parse_listen:
    bl npc_skip_ws
    mov x0, x19
    bl atoi
    bl htons
    ldr x1, =server_port
    strh w0, [x1]
    bl npc_skip_to_semi
    b npc_loop

npc_parse_server_name:
    bl npc_skip_ws
    ldr x0, =server_name_buf
    bl npc_copy_value
    b npc_loop

npc_parse_root:
    bl npc_skip_ws
    ldr x0, =server_root
    bl npc_copy_value
    b npc_loop

npc_parse_index:
    bl npc_skip_ws
    ldr x0, =index_files_buf
    bl npc_copy_value
    b npc_loop

npc_parse_access_log:
    bl npc_skip_ws
    ldr x0, =access_log_path
    bl npc_copy_value
    b npc_loop

npc_parse_error_page:
    /* error_page 404 /404.html; */
    bl npc_skip_ws
    mov x0, x19
    bl atoi
    /* Store error code */
    ldr x1, =custom_error_code
    str w0, [x1]
    bl npc_skip_ws
    /* Read the path */
    ldr x0, =custom_error_path
    bl npc_copy_value
    b npc_loop

npc_parse_proxy_pass:
    bl npc_skip_ws
    /* Parse http://IP:PORT format */
    /* Skip "http://" if present */
    ldrb w0, [x19]
    cmp w0, #'h'
    bne npc_pp_direct
    /* Skip http:// (7 chars) */
    add x19, x19, #7
npc_pp_direct:
    /* Parse IP:PORT */
    ldr x0, =path_buffer     /* temp buffer for IP string */
    mov x1, #0
npc_pp_ip:
    ldrb w2, [x19]
    cmp w2, #':'
    beq npc_pp_got_ip
    cmp w2, #';'
    beq npc_pp_noport
    cmp w2, #' '
    beq npc_pp_noport
    cbz w2, npc_pp_noport
    strb w2, [x0, x1]
    add x1, x1, #1
    add x19, x19, #1
    b npc_pp_ip
npc_pp_got_ip:
    strb wzr, [x0, x1]
    add x19, x19, #1         /* skip ':' */
    /* Parse IP */
    ldr x0, =path_buffer
    bl inet_aton
    ldr x1, =upstream_ip
    str w0, [x1]
    /* Parse port */
    mov x0, x19
    bl atoi
    bl htons
    ldr x1, =upstream_port
    strh w0, [x1]
    bl npc_skip_to_semi
    b npc_loop
npc_pp_noport:
    strb wzr, [x0, x1]
    ldr x0, =path_buffer
    bl inet_aton
    ldr x1, =upstream_ip
    str w0, [x1]
    bl npc_skip_to_semi
    b npc_loop

npc_parse_sendfile:
    bl npc_skip_ws
    /* Just skip, sendfile is always on */
    bl npc_skip_to_semi
    b npc_loop

npc_parse_keepalive:
    bl npc_skip_ws
    mov x0, x19
    bl atoi
    ldr x1, =keepalive_timeout
    str w0, [x1]
    bl npc_skip_to_semi
    b npc_loop

npc_parse_gzip:
    bl npc_skip_ws
    ldrb w0, [x19]
    cmp w0, #'o'              /* "on" */
    bne npc_gzip_off
    ldr x0, =gzip_enabled
    mov w1, #1
    str w1, [x0]
    b npc_gzip_done
npc_gzip_off:
    ldr x0, =gzip_enabled
    str wzr, [x0]
npc_gzip_done:
    bl npc_skip_to_semi
    b npc_loop

npc_parse_body_size:
    bl npc_skip_ws
    mov x0, x19
    bl atoi
    /* Check for 'm' suffix (megabytes) */
    ldr x1, =client_max_body
    /* Multiply by 1MB if 'm' suffix */
    ldr x2, =num_buffer
    ldrb w2, [x19]          /* Peek at current char */
    cmp w2, #'m'
    beq npc_body_mb
    cmp w2, #'M'
    beq npc_body_mb
    str w0, [x1]
    b npc_body_done
npc_body_mb:
    lsl w0, w0, #20         /* * 1MB */
    str w0, [x1]
npc_body_done:
    bl npc_skip_to_semi
    b npc_loop

/* === Context transitions === */

npc_enter_events:
    mov x21, #1
    bl npc_skip_to_brace
    b npc_loop

npc_enter_http:
    mov x21, #2
    bl npc_skip_to_brace
    b npc_loop

npc_enter_server:
    mov x21, #3
    ldr x0, =npc_saved_ctx
    str w21, [x0]           /* save parent context */
    bl npc_skip_to_brace
    b npc_loop

npc_enter_location:
    /* Read location path */
    bl npc_skip_ws
    /* Check for = prefix (exact match) */
    ldrb w0, [x19]
    cmp w0, #'='
    beq npc_loc_exact
    /* Prefix match - read path */
    ldr x0, =location_path_buf
    mov x1, #0
npc_loc_path:
    ldrb w2, [x19]
    cmp w2, #'{'
    beq npc_loc_path_done
    cmp w2, #' '
    beq npc_loc_path_done
    cmp w2, #0x09            /* tab */
    beq npc_loc_path_done
    cmp w2, #0x0A            /* newline */
    beq npc_loc_path_done
    strb w2, [x0, x1]
    add x1, x1, #1
    add x19, x19, #1
    b npc_loc_path
npc_loc_path_done:
    strb wzr, [x0, x1]
    mov x21, #4
    bl npc_skip_to_brace
    b npc_loop
npc_loc_exact:
    add x19, x19, #1        /* skip '=' */
    bl npc_skip_ws
    ldr x0, =location_path_buf
    mov x1, #0
    b npc_loc_path

npc_open_brace:
    add x22, x22, #1
    add x19, x19, #1
    b npc_loop

npc_close_brace:
    sub x22, x22, #1
    add x19, x19, #1
    /* Return to parent context */
    cmp x21, #4              /* location -> server */
    beq npc_ctx_to_server
    cmp x21, #3              /* server -> http */
    beq npc_ctx_to_http
    cmp x21, #2              /* http -> global */
    beq npc_ctx_to_global
    cmp x21, #1              /* events -> global */
    beq npc_ctx_to_global
    b npc_loop

npc_ctx_to_server:
    mov x21, #3
    b npc_loop
npc_ctx_to_http:
    mov x21, #2
    b npc_loop
npc_ctx_to_global:
    mov x21, #0
    b npc_loop

npc_skip_line:
    /* Skip to end of line */
    ldrb w0, [x19]
    cbz w0, npc_loop
    add x19, x19, #1
    cmp w0, #0x0A
    bne npc_skip_line
    b npc_loop

npc_done:
    /* Print config loaded message */
    mov x0, STDOUT
    ldr x1, =msg_nginx_conf_ok
    ldr x2, =len_nginx_conf_ok
    mov x8, SYS_WRITE
    svc #0
    
    ldp x25, x26, [sp, #64]
    ldp x23, x24, [sp, #48]
    ldp x21, x22, [sp, #32]
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #80
    ret

/* === Helper functions === */

/* npc_skip_ws - skip whitespace, tabs, newlines */
npc_skip_ws:
    cmp x19, x20
    bge npc_sw_done
    ldrb w0, [x19]
    cmp w0, #' '
    beq npc_sw_next
    cmp w0, #0x09            /* tab */
    beq npc_sw_next
    cmp w0, #0x0A            /* newline */
    beq npc_sw_next
    cmp w0, #0x0D            /* carriage return */
    beq npc_sw_next
    ret
npc_sw_next:
    add x19, x19, #1
    b npc_skip_ws
npc_sw_done:
    ret

/* npc_read_token - read a word token, return length in x0 */
/* x19 advances past the token */
npc_read_token:
    mov x0, #0
npc_rt_loop:
    cmp x19, x20
    bge npc_rt_done
    ldrb w1, [x19]
    cmp w1, #' '
    beq npc_rt_done
    cmp w1, #0x09
    beq npc_rt_done
    cmp w1, #0x0A
    beq npc_rt_done
    cmp w1, #0x0D
    beq npc_rt_done
    cmp w1, #';'
    beq npc_rt_done
    cmp w1, #'{'
    beq npc_rt_done
    cmp w1, #'}'
    beq npc_rt_done
    add x0, x0, #1
    add x19, x19, #1
    b npc_rt_loop
npc_rt_done:
    ret

/* npc_skip_to_semi - skip to next semicolon or closing brace */
npc_skip_to_semi:
    cmp x19, x20
    bge npc_sts_done
    ldrb w0, [x19]
    cmp w0, #';'
    beq npc_sts_found
    cmp w0, #'}'
    beq npc_sts_done          /* Don't consume the brace */
    cbz w0, npc_sts_done
    add x19, x19, #1
    b npc_skip_to_semi
npc_sts_found:
    add x19, x19, #1         /* Skip the semicolon */
npc_sts_done:
    ret

/* npc_skip_to_brace - skip to next opening brace */
npc_skip_to_brace:
    cmp x19, x20
    bge npc_stb_done
    ldrb w0, [x19]
    cmp w0, #'{'
    beq npc_stb_found
    cbz w0, npc_stb_done
    add x19, x19, #1
    b npc_skip_to_brace
npc_stb_found:
    add x22, x22, #1
    add x19, x19, #1
npc_stb_done:
    ret

/* npc_match_dir(token, dir_str, token_len) -> 1=match, 0=no */
/* x0 = token ptr, x1 = directive string, x2 = token length */
npc_match_dir:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x3, #0
npc_md_loop:
    cmp x3, x2
    bge npc_md_check_end
    ldrb w4, [x0, x3]
    ldrb w5, [x1, x3]
    cmp w4, w5
    bne npc_md_no
    add x3, x3, #1
    b npc_md_loop
npc_md_check_end:
    /* Check dir_str is also ended (null byte) */
    ldrb w5, [x1, x3]
    cbnz w5, npc_md_no
    mov x0, #1
    ldp x29, x30, [sp], #16
    ret
npc_md_no:
    mov x0, #0
    ldp x29, x30, [sp], #16
    ret

/* npc_copy_value(dest) - copy value until semicolon/newline to dest */
/* x0 = destination, x19 = source (advanced) */
npc_copy_value:
    mov x1, #0
npc_cv_loop:
    cmp x19, x20
    bge npc_cv_done
    ldrb w2, [x19]
    cmp w2, #';'
    beq npc_cv_semi
    cmp w2, #0x0A
    beq npc_cv_done
    cmp w2, #0x0D
    beq npc_cv_done
    cbz w2, npc_cv_done
    strb w2, [x0, x1]
    add x1, x1, #1
    add x19, x19, #1
    cmp x1, #254
    bge npc_cv_done
    b npc_cv_loop
npc_cv_semi:
    add x19, x19, #1        /* Skip semicolon */
npc_cv_done:
    /* Trim trailing spaces */
npc_cv_trim:
    cbz x1, npc_cv_null
    sub x1, x1, #1
    ldrb w2, [x0, x1]
    cmp w2, #' '
    beq npc_cv_trim
    add x1, x1, #1
npc_cv_null:
    strb wzr, [x0, x1]
    ret

/* =========================================================================
 * Data Section
 * ========================================================================= */
.data
    /* Directive names */
    dir_worker_processes:   .asciz "worker_processes"
    dir_error_log:          .asciz "error_log"
    dir_pid:                .asciz "pid"
    dir_events:             .asciz "events"
    dir_http:               .asciz "http"
    dir_server:             .asciz "server"
    dir_location:           .asciz "location"
    dir_worker_connections: .asciz "worker_connections"
    dir_access_log:         .asciz "access_log"
    dir_sendfile:           .asciz "sendfile"
    dir_keepalive_timeout:  .asciz "keepalive_timeout"
    dir_gzip:               .asciz "gzip"
    dir_default_type:       .asciz "default_type"
    dir_include:            .asciz "include"
    dir_listen:             .asciz "listen"
    dir_server_name:        .asciz "server_name"
    dir_root:               .asciz "root"
    dir_index:              .asciz "index"
    dir_error_page:         .asciz "error_page"
    dir_proxy_pass:         .asciz "proxy_pass"
    dir_try_files:          .asciz "try_files"
    dir_client_max_body:    .asciz "client_max_body_size"
    
    /* Messages */
    msg_nginx_conf_err:     .ascii "\x1b[1;31m[ERROR]\x1b[0m Failed to read nginx config file\n"
    len_nginx_conf_err = . - msg_nginx_conf_err
    
    msg_nginx_conf_ok:      .ascii " \x1b[1;32m[CONFIG]\x1b[0m Nginx-style configuration loaded\n"
    len_nginx_conf_ok = . - msg_nginx_conf_ok

    /* Config defaults */
    .global keepalive_timeout, gzip_enabled, client_max_body
    .global max_connections, server_name_buf, error_log_path
    .global custom_error_code, custom_error_path
    .global location_path_buf, index_files_buf
    .global npc_saved_ctx

    keepalive_timeout:  .word 65
    gzip_enabled:       .word 0
    client_max_body:    .word 1048576   /* 1MB default */
    max_connections:    .word 1024

.bss
    .align 4
    nginx_config_buf:   .skip 16384
    server_name_buf:    .skip 256
    error_log_path:     .skip 256
    custom_error_code:  .skip 4
    custom_error_path:  .skip 256
    location_path_buf:  .skip 256
    index_files_buf:    .skip 256
    npc_saved_ctx:      .skip 4
