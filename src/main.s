/* src/main.s - Main Entry Point */

.include "src/defs.s"

.global _start

.text

_start:
    /* Initialize defaults */
    ldr x0, =server_root    /* dest */
    ldr x1, =default_root   /* src */
    bl strcpy

    /* Parse CLI Arguments - Pass 1: Check for -c config_file */
    ldr x19, [sp]           /* x19 = argc */
    add x20, sp, #8         /* x20 = &argv[0] */
    
    mov x21, #1             /* index = 1 */
check_config_arg:
    cmp x21, x19
    bge parse_cli_opts
    
    ldr x0, [x20, x21, lsl #3]
    ldr x1, =flag_c
    bl strcmp
    cmp x0, #0
    beq load_config_file
    
    add x21, x21, #1
    b check_config_arg

load_config_file:
    /* Found -c, next arg is filename */
    add x21, x21, #1
    cmp x21, x19
    bge parse_cli_opts      /* Missing filename */
    
    ldr x0, [x20, x21, lsl #3] /* Filename */
    bl read_config_file
    
    /* Fallthrough to reset index */

parse_cli_opts:
    mov x21, #1             /* Reset index for CLI parsing */
parse_cli_loop:
    cmp x21, x19
    bge start_server_label
    
    /* Check -p */
    ldr x0, [x20, x21, lsl #3] /* argv[index] */
    ldr x1, =flag_p
    bl strcmp
    cmp x0, #0
    beq handle_p
    
    /* Check -d */
    ldr x0, [x20, x21, lsl #3] /* Reload argv[index] */
    ldr x1, =flag_d
    bl strcmp
    cmp x0, #0
    beq handle_d
    
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

start_server_label:
    /* Print Info */
    mov x0, STDOUT
    ldr x1, =msg_start
    ldr x2, =len_start
    mov x8, SYS_WRITE
    svc #0
    
    /* Print Port */
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
    
    mov x0, STDOUT
    ldr x1, =msg_newline
    mov x2, #1
    mov x8, SYS_WRITE
    svc #0
    
    /* Print Root */
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
