/* src/main.s - Main Entry Point */

.include "src/defs.s"

.global _start

.text

_start:
    /* Initialize defaults */
    ldr x0, =server_root    /* dest */
    ldr x1, =default_root   /* src */
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
    
    /* Check -c / --config */
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
    
    /* Workers Message */
    mov x0, STDOUT
    ldr x1, =msg_workers
    ldr x2, =len_msg_workers
    mov x8, SYS_WRITE
    svc #0
    
    /* Newline */
    mov x0, STDOUT
    ldr x1, =msg_newline
    mov x2, #1
    mov x8, SYS_WRITE
    svc #0

    /* Initialize Server */
    bl server_init
    
    /* Enter Accept Loop */
    bl accept_loop
    
    /* Exit */
    mov x0, #0
    mov x8, SYS_EXIT
    svc #0