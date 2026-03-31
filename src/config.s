/* src/config.s - Configuration File Parser */

.include "src/defs.s"

.global read_config_file

.text

/* read_config_file(filename) */
read_config_file:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!
    
    /* Open Config */
    mov x1, O_RDONLY
    mov x2, #0
    mov x8, SYS_OPENAT    /* openat */
    mov x1, x0            /* filename */
    mov x0, AT_FDCWD
    svc #0
    cmp x0, #0
    blt rcf_error
    mov x19, x0           /* fd */
    
    /* Read Config */
    ldr x1, =config_buffer
    mov x2, #4095         /* Read max 4095 bytes */
    mov x8, SYS_READ
    mov x0, x19           /* Ensure x0 is fd */
    svc #0
    mov x20, x0           /* Store result in x20 immediately */
    
    /* Debug Print */
    mov x0, STDOUT
    ldr x1, =msg_conf_read
    ldr x2, =len_conf_read
    mov x8, SYS_WRITE
    svc #0
    
    cmp x20, #0
    ble close_config
    
    /* Null terminate */
    ldr x1, =config_buffer
    strb wzr, [x1, x20]

close_config:
    mov x0, x19
    mov x8, SYS_CLOSE
    svc #0
    
    cmp x20, #0
    ble rcf_end
    
    /* Parse "port=" */
    ldr x0, =config_buffer
    ldr x1, =key_port
    bl strstr
    cmp x0, #0
    beq try_root
    
    /* Found port=, parse number */
    add x0, x0, #5        /* Skip "port=" */
    bl atoi
    bl htons
    ldr x1, =server_port
    strh w0, [x1]

try_root:
    /* Parse "root=" */
    ldr x0, =config_buffer
    ldr x1, =key_root
    bl strstr
    cmp x0, #0
    beq try_access_log
    
    add x0, x0, #5        /* Skip "root=" */
    mov x1, x0            /* src */
    ldr x0, =server_root  /* dest */
    bl copy_value_until_newline

try_access_log:
    ldr x0, =config_buffer
    ldr x1, =key_access_log
    bl strstr
    cmp x0, #0
    beq try_upstream_ip
    
    add x0, x0, #11       /* Skip "access_log=" */
    mov x1, x0            /* src */
    ldr x0, =access_log_path /* dest */
    bl copy_value_until_newline

try_upstream_ip:
    ldr x0, =config_buffer
    ldr x1, =key_upstream_ip
    bl strstr
    cmp x0, #0
    beq try_upstream_port
    
    add x0, x0, #12       /* "upstream_ip=" */
    mov x1, x0            /* Start of IP str */
    
    /* Copy IP to temporary buffer */
    ldr x0, =path_buffer
    bl copy_value_until_newline
    
    ldr x0, =path_buffer
    bl inet_aton
    ldr x1, =upstream_ip
    str w0, [x1]

try_upstream_port:
    ldr x0, =config_buffer
    ldr x1, =key_upstream_port
    bl strstr
    cmp x0, #0
    beq try_worker_processes
    
    add x0, x0, #14       /* "upstream_port=" */
    bl atoi
    bl htons
    ldr x1, =upstream_port
    strh w0, [x1]

try_worker_processes:
    ldr x0, =config_buffer
    ldr x1, =key_worker_processes
    bl strstr
    cmp x0, #0
    beq try_keepalive_timeout
    
    add x0, x0, #17       /* Skip "worker_processes=" */
    bl atoi
    /* Clamp to 1-128 */
    cmp x0, #1
    blt wc_min
    cmp x0, #128
    bgt wc_max
    b wc_store
wc_min:
    mov x0, #1
    b wc_store
wc_max:
    mov x0, #128
wc_store:
    ldr x1, =worker_count
    str w0, [x1]

try_keepalive_timeout:
    ldr x0, =config_buffer
    ldr x1, =key_keepalive_timeout
    bl strstr
    cmp x0, #0
    beq try_client_max_body
    
    add x0, x0, #18       /* Skip "keepalive_timeout=" */
    bl atoi
    ldr x1, =keepalive_timeout_val
    str x0, [x1]
    
    /* Also update timeout_tv */
    ldr x1, =timeout_tv
    str x0, [x1]           /* tv_sec */

try_client_max_body:
    ldr x0, =config_buffer
    ldr x1, =key_client_max_body
    bl strstr
    cmp x0, #0
    beq try_server_tokens
    
    add x0, x0, #21       /* Skip "client_max_body_size=" */
    bl atoi
    ldr x1, =client_max_body_val
    str x0, [x1]

try_server_tokens:
    ldr x0, =config_buffer
    ldr x1, =key_server_tokens
    bl strstr
    cmp x0, #0
    beq try_autoindex
    
    add x0, x0, #14       /* Skip "server_tokens=" */
    /* Check if "on" or "off" */
    mov x1, x0
    ldr x0, =path_buffer
    bl copy_value_until_newline
    ldr x0, =path_buffer
    ldr x1, =str_on
    bl strcmp
    cmp x0, #0
    beq st_on
    /* Default to off */
    ldr x0, =server_tokens_flag
    str wzr, [x0]
    b try_autoindex
st_on:
    ldr x0, =server_tokens_flag
    mov w1, #1
    str w1, [x0]

try_autoindex:
    ldr x0, =config_buffer
    ldr x1, =key_autoindex
    bl strstr
    cmp x0, #0
    beq try_gzip_static
    
    add x0, x0, #10       /* Skip "autoindex=" */
    mov x1, x0
    ldr x0, =path_buffer
    bl copy_value_until_newline
    ldr x0, =path_buffer
    ldr x1, =str_on
    bl strcmp
    cmp x0, #0
    beq ai_on
    ldr x0, =autoindex_flag
    str wzr, [x0]
    b try_gzip_static
ai_on:
    ldr x0, =autoindex_flag
    mov w1, #1
    str w1, [x0]

try_gzip_static:
    ldr x0, =config_buffer
    ldr x1, =key_gzip_static
    bl strstr
    cmp x0, #0
    beq rcf_end
    
    add x0, x0, #12       /* Skip "gzip_static=" */
    mov x1, x0
    ldr x0, =path_buffer
    bl copy_value_until_newline
    ldr x0, =path_buffer
    ldr x1, =str_on
    bl strcmp
    cmp x0, #0
    beq gz_on
    ldr x0, =gzip_static_flag
    str wzr, [x0]
    b rcf_end
gz_on:
    ldr x0, =gzip_static_flag
    mov w1, #1
    str w1, [x0]

    b rcf_end

rcf_error:
    mov x0, STDOUT
    ldr x1, =msg_config_fail
    ldr x2, =len_config_fail
    mov x8, SYS_WRITE
    svc #0
    b rcf_end

rcf_end:
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret
