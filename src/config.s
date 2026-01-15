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
        
        /* Found root=, parse string until newline */
        add x0, x0, #5        /* Skip "root=" */
        mov x1, x0            /* Start of path */
        
    find_nl:
        ldrb w2, [x0]
        cmp w2, #10           /* \n */
        beq found_nl
        cmp w2, #0
        beq found_nl
        add x0, x0, #1
        b find_nl
    found_nl:
        mov w2, #0
        strb w2, [x0]         /* Null terminate */
        
        mov x0, x1            /* Source */
        ldr x1, =server_root
        /* Need to swap args for strcpy(dest, src) */
        mov x2, x0            /* x2 = src */
        mov x0, x1            /* x0 = dest */
        mov x1, x2            /* x1 = src */
        bl strcpy
    
    try_access_log:
        ldr x0, =config_buffer
        ldr x1, =key_access_log
        bl strstr
        cmp x0, #0
        beq try_upstream_ip
        
        add x0, x0, #11       /* Skip "access_log=" */
        mov x1, x0            /* Start of path */
        
    find_nl_log:
        ldrb w2, [x0]
        cmp w2, #10
        beq found_nl_log
        cmp w2, #0
        beq found_nl_log
        add x0, x0, #1
        b find_nl_log
    found_nl_log:
        mov w2, #0
        strb w2, [x0]
        
        mov x0, x1            /* src start */
        ldr x1, =access_log_path
        /* strcpy(dest, src) */
        /* setup args: x0=dest, x1=src */
        mov x2, x0            /* x2 = src ptr */
        mov x0, x1            /* x0 = dest ptr */
            mov x1, x2            /* x1 = src ptr */
            bl strcpy
            
        try_upstream_ip:
            ldr x0, =config_buffer
            ldr x1, =key_upstream_ip
            bl strstr
            cmp x0, #0
            beq try_upstream_port
            
            add x0, x0, #12       /* "upstream_ip=" */
            mov x1, x0            /* Start of IP str */
            
            /* Find newline to terminate */
        find_nl_ip:
            ldrb w2, [x0]
            cmp w2, #10
            beq found_nl_ip
            cmp w2, #0
            beq found_nl_ip
            add x0, x0, #1
            b find_nl_ip
        found_nl_ip:
            mov w2, #0
            strb w2, [x0]
            
            /* Convert String IP to int (inet_addr) - wait, we don't have inet_addr */
            /* We have inet_ntoa (int -> str). Do we have str -> int? No. */
            /* Use simple parser or just hardcode for now? */
            /* I need `inet_aton` or similar. */
            /* For now, let's implement a basic IP parser? Or just skip validation and assume 127.0.0.1? */
            /* Actually, just parsing "127.0.0.1" manually is annoying. */
            /* Let's skip parsing IP string to int for now and assume the user provides... wait. */
            /* upstream_ip is .word (4 bytes). We need to convert "1.2.3.4" to integer. */
            /* Implementation of inet_aton: */
            /* Parse A.B.C.D */
            
            mov x0, x1
            bl inet_aton
            ldr x1, =upstream_ip
            str w0, [x1]
        
        try_upstream_port:
            ldr x0, =config_buffer
            ldr x1, =key_upstream_port
            bl strstr
            cmp x0, #0
            beq rcf_end
            
            add x0, x0, #14       /* "upstream_port=" */
            bl atoi
            bl htons
            ldr x1, =upstream_port
            strh w0, [x1]
        
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
