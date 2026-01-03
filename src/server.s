/* 
 * ANX AArch64 Pure Assembly Static File Server v3.0
 * Features: 
 * - Static file serving (sendfile zero-copy)
 * - CLI args parsing (-p port, -d dir, -c config)
 * - Basic Config file parsing
 */

/* Syscalls */
.equ SYS_OPENAT, 56
.equ SYS_CLOSE, 57
.equ SYS_LSEEK, 62
.equ SYS_READ, 63
.equ SYS_WRITE, 64
.equ SYS_SENDFILE, 71
.equ SYS_EXIT, 93
.equ SYS_SOCKET, 198
.equ SYS_BIND, 200
.equ SYS_LISTEN, 201
.equ SYS_ACCEPT, 202
.equ SYS_SETSOCKOPT, 208

/* Constants */
.equ STDIN, 0
.equ STDOUT, 1
.equ STDERR, 2
.equ AF_INET, 2
.equ SOCK_STREAM, 1
.equ SOL_SOCKET, 1
.equ SO_REUSEADDR, 2
.equ O_RDONLY, 0
.equ AT_FDCWD, -100
.equ SEEK_END, 2
.equ SEEK_SET, 0

.data
    /* Defaults */
    default_port:   .hword 0x901f       /* 8080 (Big Endian) */
    default_root:   .asciz "./www"
    
    .align 4
    /* Runtime Config (Initialized with defaults) */
    server_port:    .hword 0x901f
    server_root:    .skip 256
    
    .align 4
    /* Socket Address */
    sockaddr:
        .hword AF_INET
        .hword 0                /* Port (filled at runtime) */
        .word 0                 /* INADDR_ANY */
        .quad 0

    optval: .word 1

    /* Strings */
    msg_start:      .ascii "[INFO] ANX Server starting...\n"
    len_start = . - msg_start
    msg_port:       .ascii "[INFO] Port: "
    len_msg_port = . - msg_port
    msg_root:       .ascii "[INFO] Root: "
    len_msg_root = . - msg_root
    msg_newline:    .ascii "\n"
    
    /* Config Keys */
    key_port:       .asciz "port="
    key_root:       .asciz "root="
    
    msg_config_fail: .ascii "[DEBUG] Config file not found or unreadable\n"
    len_config_fail = . - msg_config_fail

    msg_conf_read: .ascii "[DEBUG] Config read\n"
    len_conf_read = . - msg_conf_read

    /* CLI Flags */
    flag_p:         .asciz "-p"
    flag_d:         .asciz "-d"
    flag_c:         .asciz "-c"

    /* HTTP Headers */
    http_200:       .ascii "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: "
    len_200 = . - http_200
    http_end:       .ascii "\r\n\r\n"
    
    http_404:       .ascii "HTTP/1.1 404 Not Found\r\nContent-Length: 13\r\nConnection: close\r\n\r\n404 Not Found"
    len_404 = . - http_404
    
    http_403:       .ascii "HTTP/1.1 403 Forbidden\r\nContent-Length: 9\r\nConnection: close\r\n\r\nForbidden"
    len_403 = . - http_403

    index_file:     .asciz "/index.html"

.bss
    .align 4
    req_buffer:     .skip 2048
    file_path:      .skip 512
    num_buffer:     .skip 32
    config_buffer:  .skip 4096      /* Buffer for config file */
    
.text
.global _start

/* =========================================================================
   Entry Point & Argument Parsing
   ========================================================================= */
_start:
    /* Initialize defaults */
    ldr x0, =default_root
    ldr x1, =server_root
    bl strcpy

    /* Parse CLI Arguments - Pass 1: Check for -c config_file */
    /* Stack: [sp]=argc, [sp+8]=argv[0], [sp+16]=argv[1]... */
    ldr x19, [sp]           /* x19 = argc */
    add x20, sp, #8         /* x20 = &argv[0] */
    
    mov x21, #1             /* index = 1 */
check_config_arg:
    cmp x21, x19
    bge parse_cli_opts      /* Done checking args for config */
    
    ldr x0, [x20, x21, lsl #3] /* x0 = argv[index] */
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
    bge start_server
    
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
    bge start_server
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
    bge start_server
    ldr x1, [x20, x21, lsl #3] /* src: dir string */
    ldr x0, =server_root       /* dest */
    bl strcpy
    add x21, x21, #1
    b parse_cli_loop

/* =========================================================================
   Server Initialization
   ========================================================================= */
start_server:
    /* Print Info */
    mov x0, STDOUT
    ldr x1, =msg_start
    mov x2, len_start
    mov x8, SYS_WRITE
    svc #0
    
    /* Print Port */
    mov x0, STDOUT
    ldr x1, =msg_port
    mov x2, len_msg_port
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
    mov x2, len_msg_root
    mov x8, SYS_WRITE
    svc #0
    
    ldr x0, =server_root    /* Fix: x0 = str for strlen */
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

    /* 1. Socket */
    mov x0, AF_INET
    mov x1, SOCK_STREAM
    mov x2, #0
    mov x8, SYS_SOCKET
    svc #0
    mov x19, x0             /* x19 = listen_fd */
    
    /* 2. Setsockopt */
    mov x0, x19
    mov x1, SOL_SOCKET
    mov x2, SO_REUSEADDR
    ldr x3, =optval
    mov x4, #4
    mov x8, SYS_SETSOCKOPT
    svc #0
    
    /* 3. Bind */
    ldr x1, =sockaddr
    ldr x2, =server_port
    ldrh w2, [x2]
    strh w2, [x1, #2]       /* Set port in sockaddr */
    
    mov x0, x19
    ldr x1, =sockaddr
    mov x2, #16
    mov x8, SYS_BIND
    svc #0
    
    /* 4. Listen */
    mov x0, x19
    mov x1, #128
    mov x8, SYS_LISTEN
    svc #0

/* =========================================================================
   Main Accept Loop
   ========================================================================= */
accept_loop:
    mov x0, x19
    mov x1, #0
    mov x2, #0
    mov x8, SYS_ACCEPT
    svc #0
    mov x20, x0             /* x20 = client_fd */
    
    /* Read Request */
    mov x0, x20
    ldr x1, =req_buffer
    mov x2, #2048
    mov x8, SYS_READ
    svc #0
    cmp x0, #0
    ble close_conn
    
    /* Parse Request Path (Simple: assume "GET <path> HTTP...") */
    ldr x1, =req_buffer
    
    /* Skip "GET " */
    add x1, x1, #4
    
    /* Find end of path (space) */
    mov x2, x1
find_path_end:
    ldrb w3, [x2]
    cmp w3, #' '
    beq path_found
    add x2, x2, #1
    b find_path_end

path_found:
    mov w3, #0
    strb w3, [x2]           /* Null terminate path */
    
    /* Construct full path: root + path */
    ldr x0, =file_path
    ldr x1, =server_root
    bl strcpy

    /* If path is "/", append "/index.html" */
    ldr x1, =req_buffer
    add x1, x1, #4          /* x1 points to path */
    
    ldrb w3, [x1]
    cmp w3, #0              /* Empty path? */
    beq append_index
    
    ldr x2, =req_buffer
    add x2, x2, #4
    ldrb w3, [x2]
    ldrb w4, [x2, #1]
    cmp w3, #'/'
    bne append_path
    cmp w4, #0
    beq append_index

append_path:
    ldr x0, =file_path
    /* x1 is already path */
    bl strcat
    b open_file

append_index:
    ldr x0, =file_path
    ldr x1, =index_file
    bl strcat

open_file:
    /* x0 (file_path) is ready */
    mov x1, O_RDONLY
    mov x2, #0
    mov x8, SYS_OPENAT
    mov x0, AT_FDCWD
    ldr x1, =file_path
    svc #0
    
    cmp x0, #0
    blt send_404
    mov x21, x0             /* x21 = file_fd */
    
    /* Get File Size using LSEEK */
    mov x0, x21
    mov x1, #0
    mov x2, SEEK_END
    mov x8, SYS_LSEEK
    svc #0
    mov x22, x0             /* x22 = file size */
    
    /* Reset File Ptr */
    mov x0, x21
    mov x1, #0
    mov x2, SEEK_SET
    mov x8, SYS_LSEEK
    svc #0
    
    /* Send 200 Header */
    mov x0, x20
    ldr x1, =http_200
    mov x2, len_200
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Size */
    mov x0, x22
    ldr x1, =num_buffer
    bl itoa
    mov x2, x0
    mov x0, x20
    ldr x1, =num_buffer
    mov x8, SYS_WRITE
    svc #0
    
    /* Send Header End */
    mov x0, x20
    ldr x1, =http_end
    mov x2, #4
    mov x8, SYS_WRITE
    svc #0
    
    /* Send File (sendfile) */
    /* sendfile(out_fd, in_fd, offset, count) */
    mov x0, x20
    mov x1, x21
    mov x2, #0              /* offset = NULL */
    mov x3, x22             /* count = size */
    mov x8, SYS_SENDFILE
    svc #0
    
    /* Close file */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    
    b close_conn

send_404:
    mov x0, x20
    ldr x1, =http_404
    mov x2, len_404
    mov x8, SYS_WRITE
    svc #0

close_conn:
    mov x0, x20
    mov x8, SYS_CLOSE
    svc #0
    b accept_loop

/* =========================================================================
   Helper: Read Config File
   Simple parser: looks for "port=" and "root=" in the file buffer.
   x0 = filename
   ========================================================================= */
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
    mov x2, len_conf_read
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
    beq rcf_end
    
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

rcf_error:
    mov x0, STDOUT
    ldr x1, =msg_config_fail
    mov x2, len_config_fail
    mov x8, SYS_WRITE
    svc #0
    b rcf_end

rcf_end:
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

/* =========================================================================
   String Utilities
   ========================================================================= */

/* strcpy(dest, src) */
strcpy:
    mov x2, x0
scp_loop:
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    bne scp_loop
    ret

/* strcat(dest, src) */
strcat:
    mov x2, x0
sct_find_end:
    ldrb w3, [x2]
    cmp w3, #0
    beq sct_copy
    add x2, x2, #1
    b sct_find_end
sct_copy:
    ldrb w3, [x1], #1
    strb w3, [x2], #1
    cmp w3, #0
    bne sct_copy
    ret

/* strlen(str) -> len */
strlen:
    mov x1, x0
sl_loop:
    ldrb w2, [x1], #1
    cmp w2, #0
    bne sl_loop
    sub x0, x1, x0
    sub x0, x0, #1
    ret

/* strcmp(s1, s2) -> 0 if eq */
strcmp:
    ldrb w2, [x0], #1
    ldrb w3, [x1], #1
    cmp w2, #0
    beq scmp_done
    cmp w2, w3
    beq strcmp
    sub x0, x2, x3
    ret
scmp_done:
    sub x0, x2, x3
    ret

/* strstr(haystack, needle) -> ptr or NULL */
strstr:
    stp x19, x20, [sp, #-16]!
    mov x19, x0     /* haystack */
    mov x20, x1     /* needle */
    
    /* needle len */
    mov x0, x20
    bl strlen
    mov x3, x0      /* x3 = needle len */
    cmp x3, #0
    beq strstr_found_immediate
    
strstr_loop:
    ldrb w4, [x19]
    cmp w4, #0
    beq strstr_not_found
    
    /* Compare x3 bytes */
    mov x5, #0      /* index */
cmp_loop:
    cmp x5, x3
    beq strstr_found
    
    ldrb w6, [x19, x5]
    ldrb w7, [x20, x5]
    cmp w6, w7
    bne next_char
    
    /* Safety: if w6 was 0 (end of haystack), and we matched? 
       No, needle contains chars. If w6 is 0, w7 is not (unless end of needle).
       If end of needle, we would have exited cmp_loop.
       So if w6 is 0, w7 != 0, so bne taken. Safe. */
       
    add x5, x5, #1
    b cmp_loop

next_char:
    add x19, x19, #1
    b strstr_loop

strstr_found:
    mov x0, x19
    b strstr_exit
strstr_found_immediate:
    mov x0, x19
    b strstr_exit
strstr_not_found:
    mov x0, #0
strstr_exit:
    ldp x19, x20, [sp], #16
    ret

/* atoi(str) -> int */
atoi:
    mov x1, #0      /* result */
    mov x2, #10
at_loop:
    ldrb w3, [x0], #1
    sub w3, w3, #'0'
    cmp w3, #0
    blt at_done
    cmp w3, #9
    bgt at_done
    mul x1, x1, x2
    add x1, x1, x3
    b at_loop
at_done:
    mov x0, x1
    ret

/* itoa(int, buf) -> len */
itoa:
    mov x2, x1
    mov x3, x0
    mov x4, #0
    mov x5, #10
    cmp x3, #0
    bne itoa_loop_l
    mov w6, #'0'
    strb w6, [x2]
    mov x0, #1
    ret
itoa_loop_l:
    cmp x3, #0
    beq itoa_rev_l
    udiv x6, x3, x5
    msub x7, x6, x5, x3
    add w7, w7, #'0'
    strb w7, [x2, x4]
    add x4, x4, #1
    mov x3, x6
    b itoa_loop_l
itoa_rev_l:
    mov x0, x4
    mov x8, #0
    sub x9, x4, #1
rv_loop_l:
    cmp x8, x9
    bge rv_dn_l
    ldrb w10, [x2, x8]
    ldrb w11, [x2, x9]
    strb w11, [x2, x8]
    strb w10, [x2, x9]
    add x8, x8, #1
    sub x9, x9, #1
    b rv_loop_l
rv_dn_l: ret

/* htons(short) -> short (swap bytes) */
htons:
    rev16 w0, w0
    ret

/* ntohs(short) -> short */
ntohs:
    rev16 w0, w0
    ret
