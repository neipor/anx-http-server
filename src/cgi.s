/* src/cgi.s - Common Gateway Interface (CGI) Support */

.include "src/defs.s"

.global handle_cgi

.text

/* handle_cgi(client_fd, path_ptr, req_ptr) */
handle_cgi:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    
    mov x19, x0     /* client_fd */
    mov x20, x1     /* script path */
    /* x2 is req_ptr, ignored for now */
    
    /* 1. Pipe */
    /* Allocate 8 bytes for pipe fds */
    sub sp, sp, #16
    mov x0, sp
    mov x1, #0      /* flags */
    mov x8, SYS_PIPE2
    svc #0
    
    cmp x0, #0
    blt cgi_fail
    
    ldr w21, [sp]       /* read end */
    ldr w22, [sp, #4]   /* write end */
    add sp, sp, #16
    
    /* 2. Fork */
    mov x0, SIGCHLD_FLAG
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x4, #0
    mov x8, SYS_CLONE
    svc #0
    
    cmp x0, #0
    blt cgi_fork_fail
    beq cgi_child
    
    /* Parent */
    /* Close write end */
    mov x0, x22
    mov x8, SYS_CLOSE
    svc #0
    
    /* Read loop from pipe (x21) -> Write to client (x19) */
    /* We need a buffer. Reuse req_buffer? No, unsafe if threaded (but we are prefork). */
    /* Or allocate on stack. */
    sub sp, sp, #4096
    mov x23, sp         /* buffer */
    
    /* Send HTTP 200 Header first */
    /* Wait, CGI script might output headers? */
    /* Usually CGI outputs "Content-type: ...\n\nBody". */
    /* Server should parse headers or just forward? */
    /* For simplicity, let's assume script outputs FULL response or just Body? */
    /* Standard CGI: Script outputs Headers + Body. Server adds Status line if missing? */
    /* Let's send "HTTP/1.1 200 OK\r\n" then forward everything. */
    
    mov x0, x19
    ldr x1, =http_status_200
    ldr x2, =len_status_200
    mov x8, SYS_WRITE
    svc #0
    
    /* Forward Loop */
cgi_fwd_loop:
    mov x0, x21         /* pipe read */
    mov x1, x23         /* buf */
    mov x2, #4096
    mov x8, SYS_READ
    svc #0
    
    cmp x0, #0
    ble cgi_fwd_done    /* EOF or Error */
    
    mov x2, x0          /* len */
    mov x0, x19         /* client */
    mov x1, x23
    mov x8, SYS_WRITE
    svc #0
    
    b cgi_fwd_loop

cgi_fwd_done:
    add sp, sp, #4096   /* Free buffer */
    
    /* Close read end */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    
    /* Wait for child? */
    mov x0, #-1
    mov x1, #0
    mov x2, #0
    mov x3, #0
    mov x8, SYS_WAIT4
    svc #0
    
    mov x0, #0      /* Success */
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

cgi_child:
    /* Close read end */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    
    /* Dup write end to STDOUT (1) */
    mov x0, x22
    mov x1, #1
    mov x2, #0
    mov x8, SYS_DUP3
    svc #0
    
    /* Close write end (original) */
    mov x0, x22
    mov x8, SYS_CLOSE
    svc #0
    
    /* Prepare execve */
    /* argv = { "/usr/bin/python3", script_path, NULL } */
    sub sp, sp, #32
    ldr x0, =python_path
    str x0, [sp]
    str x20, [sp, #8]
    str xzr, [sp, #16]
    
    /* envp = { NULL } for now */
    mov x2, #0
    
    mov x0, x20         /* filename (script? No, python3) */
    ldr x0, =python_path
    mov x1, sp          /* argv */
    mov x8, SYS_EXECVE
    svc #0
    
    /* If execve fails */
    mov x0, #1
    mov x8, SYS_EXIT
    svc #0

cgi_fork_fail:
    /* Close pipe ends */
    mov x0, x21
    mov x8, SYS_CLOSE
    svc #0
    mov x0, x22
    mov x8, SYS_CLOSE
    svc #0
    
cgi_fail:
    mov x0, #-1
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

    .data
python_path: .asciz "/usr/bin/python3"
