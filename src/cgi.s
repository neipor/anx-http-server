/* src/cgi.s - Common Gateway Interface (CGI) Support */

.include "src/defs.s"

.global handle_cgi

.text

/* handle_cgi(client_fd, path_ptr, req_ptr) */
/*
   x0: client_fd
   x1: path_ptr (absolute path to script)
   x2: req_ptr (request buffer, for body/env?)
*/
handle_cgi:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    
    mov x19, x0     /* client_fd */
    mov x20, x1     /* script path */
    
    /* TODO: Implementation */
    /* 1. Pipe */
    /* 2. Fork */
    /* 3. Child: dup2, execve */
    /* 4. Parent: read pipe, write to client */
    
    /* For now, just return 501 Not Implemented */
    /* But http.s doesn't have send_501. Send 502 for now. */
    mov x0, #-1
    
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret
