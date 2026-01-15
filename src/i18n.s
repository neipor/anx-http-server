/* src/i18n.s - Internationalization Module */

.include "src/defs.s"

/* Exports: Init Function */
.global i18n_init

/* Exports: Global Pointers (Points to the active language string) */
.global p_msg_welcome_title, p_len_welcome_title
.global p_msg_welcome_desc, p_len_welcome_desc
.global p_msg_help, p_len_help

/* Exports: Pointer Variables (for main.s to read) */
.data
    p_msg_welcome_title: .quad 0
    p_len_welcome_title: .quad 0
    p_msg_welcome_desc:  .quad 0
    p_len_welcome_desc:  .quad 0
    p_msg_help:          .quad 0
    p_len_help:          .quad 0

/* Internal Strings */
.data
    /* --- Constants --- */
    str_lang_key:   .asciz "LANG="
    str_zh_sign:    .asciz "zh"

    /* --- English (Default) --- */
    txt_welcome_title_en:
        .byte 10
        .ascii " \x1b[1;36m✨ ANX Web Server\x1b[0m \x1b[90m"
    len_txt_welcome_title_en = . - txt_welcome_title_en

    txt_welcome_desc_en:
        .ascii "\x1b[0m"
        .byte 10
        .ascii " \x1b[32mHigh-Performance AArch64 Assembly Server\x1b[0m"
        .byte 10, 10
        .ascii " \x1b[1;34m[SYSTEM]\x1b[0m Architecture: \x1b[1mPrefork + Epoll\x1b[0m"
        .byte 10
    len_txt_welcome_desc_en = . - txt_welcome_desc_en

    txt_help_en:
        .byte 10
        .ascii "\x1b[1mUSAGE:\x1b[0m    anx [OPTIONS] [serve-path]"
        .byte 10, 10
        .ascii "\x1b[1mDESCRIPTION:\x1b[0m"
        .byte 10
        .ascii "    High-performance, industrial-grade HTTP/1.1 web server written in"
        .byte 10
        .ascii "    pure AArch64 Assembly."
        .byte 10, 10
        .ascii "\x1b[1mOPTIONS:\x1b[0m"
        .byte 10
        .ascii "    \x1b[33m-p, --port\x1b[0m \x1b[36m<port>\x1b[0m    Port to listen on [default: 8080]"
        .byte 10
        .ascii "    \x1b[33m-d, --dir\x1b[0m \x1b[36m<path>\x1b[0m     Path to directory to serve"
        .byte 10
        .ascii "    \x1b[33m-s, --silent\x1b[0m         Disable access logging"
        .byte 10
        .ascii "    \x1b[33m-c, --config\x1b[0m \x1b[36m<file>\x1b[0m  Load configuration file"
        .byte 10
        .ascii "    \x1b[33m-x, --proxy\x1b[0m          Enable reverse proxy"
        .byte 10
        .ascii "    \x1b[33m-h, --help\x1b[0m           Print this help message"
        .byte 10, 10
    len_txt_help_en = . - txt_help_en

    /* --- Chinese --- */
    txt_welcome_title_zh:
        .byte 10
        .ascii " \x1b[1;36m✨ ANX Web Server\x1b[0m \x1b[90m"
    len_txt_welcome_title_zh = . - txt_welcome_title_zh

    txt_welcome_desc_zh:
        .ascii "\x1b[0m"
        .byte 10
        .ascii " \x1b[32m高性能 AArch64 汇编 Web 服务器\x1b[0m"
        .byte 10, 10
        .ascii " \x1b[1;34m[系统架构]\x1b[0m \x1b[1m多进程预派生 (Prefork) + Epoll\x1b[0m"
        .byte 10
    len_txt_welcome_desc_zh = . - txt_welcome_desc_zh

    txt_help_zh:
        .byte 10
        .ascii "\x1b[1m用法:\x1b[0m    anx [选项] [服务路径]"
        .byte 10, 10
        .ascii "\x1b[1m简介:\x1b[0m"
        .byte 10
        .ascii "    基于纯 AArch64 汇编编写的工业级高性能 HTTP/1.1 Web 服务器。"
        .byte 10
        .ascii "    特性：Prefork 多进程、Epoll 事件驱动、零拷贝传输 (Zero-Copy)。"
        .byte 10, 10
        .ascii "\x1b[1m选项:\x1b[0m"
        .byte 10
        .ascii "    \x1b[33m-p, --port\x1b[0m \x1b[36m<端口>\x1b[0m    监听端口 [默认: 8080]"
        .byte 10
        .ascii "    \x1b[33m-d, --dir\x1b[0m \x1b[36m<路径>\x1b[0m     静态文件服务根目录"
        .byte 10
        .ascii "    \x1b[33m-s, --silent\x1b[0m         静默模式 (禁用访问日志以提升性能)"
        .byte 10
        .ascii "    \x1b[33m-c, --config\x1b[0m \x1b[36m<文件>\x1b[0m  加载配置文件"
        .byte 10
        .ascii "    \x1b[33m-x, --proxy\x1b[0m          启用反向代理模式"
        .byte 10
        .ascii "    \x1b[33m-h, --help\x1b[0m           打印此帮助信息"
        .byte 10, 10
    len_txt_help_zh = . - txt_help_zh


.text

/* i18n_init(envp) */
i18n_init:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    
    /* Detect Language */
    bl detect_language
    cmp x0, #1
    beq load_zh
    
    /* Default: English */
load_en:
    ldr x0, =p_msg_welcome_title
    ldr x1, =txt_welcome_title_en
    str x1, [x0]
    ldr x0, =p_len_welcome_title
    ldr x1, =len_txt_welcome_title_en
    str x1, [x0]

    ldr x0, =p_msg_welcome_desc
    ldr x1, =txt_welcome_desc_en
    str x1, [x0]
    ldr x0, =p_len_welcome_desc
    ldr x1, =len_txt_welcome_desc_en
    str x1, [x0]
    
    ldr x0, =p_msg_help
    ldr x1, =txt_help_en
    str x1, [x0]
    ldr x0, =p_len_help
    ldr x1, =len_txt_help_en
    str x1, [x0]
    
    b i18n_done

load_zh:
    ldr x0, =p_msg_welcome_title
    ldr x1, =txt_welcome_title_zh
    str x1, [x0]
    ldr x0, =p_len_welcome_title
    ldr x1, =len_txt_welcome_title_zh
    str x1, [x0]

    ldr x0, =p_msg_welcome_desc
    ldr x1, =txt_welcome_desc_zh
    str x1, [x0]
    ldr x0, =p_len_welcome_desc
    ldr x1, =len_txt_welcome_desc_zh
    str x1, [x0]
    
    ldr x0, =p_msg_help
    ldr x1, =txt_help_zh
    str x1, [x0]
    ldr x0, =p_len_help
    ldr x1, =len_txt_help_zh
    str x1, [x0]

i18n_done:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret


/* detect_language(envp_ptr) -> 0 (en) or 1 (zh) */
detect_language:
    stp x29, x30, [sp, #-32]!
    mov x29, sp
    stp x19, x20, [sp, #16]
    
    mov x19, x0     /* x19 = envp array */
    
dl_loop:
    ldr x20, [x19], #8   /* x20 = current env string */
    cmp x20, #0
    beq dl_default
    
    /* Check prefix "LANG=" */
    ldr x1, =str_lang_key
    mov x0, x20
    bl check_prefix
    cmp x0, #0
    beq dl_loop     /* Not LANG= */
    
    /* Found LANG=, check for "zh" */
    mov x0, x20
    ldr x1, =str_zh_sign
    bl find_substring
    cmp x0, #0
    bne dl_zh
    
    b dl_loop

dl_zh:
    mov x0, #1
    b dl_end
dl_default:
    mov x0, #0
dl_end:
    ldp x19, x20, [sp, #16]
    ldp x29, x30, [sp], #32
    ret

/* check_prefix(str, prefix) -> 1 if match, 0 if not */
check_prefix:
    mov x2, x0
    mov x3, x1
cp_loop:
    ldrb w4, [x3], #1   /* prefix char */
    cmp w4, #0
    beq cp_match        /* prefix ended */
    ldrb w5, [x2], #1   /* str char */
    cmp w4, w5
    bne cp_fail
    b cp_loop
cp_match:
    mov x0, #1
    ret
cp_fail:
    mov x0, #0
    ret

/* find_substring(haystack, needle) -> 1 if found, 0 if not */
find_substring:
    stp x29, x30, [sp, #-16]!
    mov x9, x0          /* haystack */
    mov x10, x1         /* needle */
    
fs_outer:
    ldrb w11, [x9]
    cmp w11, #0
    beq fs_fail
    
    /* Check match starting here */
    mov x12, x9         /* temp haystack */
    mov x13, x10        /* temp needle */
fs_inner:
    ldrb w14, [x13], #1
    cmp w14, #0
    beq fs_found        /* needle ended = match */
    ldrb w15, [x12], #1
    cmp w14, w15
    bne fs_next
    b fs_inner
    
fs_next:
    add x9, x9, #1
    b fs_outer
    
fs_found:
    mov x0, #1
    ldp x29, x30, [sp], #16
    ret
fs_fail:
    mov x0, #0
    ldp x29, x30, [sp], #16
    ret
