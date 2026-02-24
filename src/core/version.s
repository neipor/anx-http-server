/* version.s - Version Information */

.global version_major, version_minor, version_patch
.global version_string, version_string_len
.global version_full, version_full_len
.global build_date, build_date_len

.data
    /* Semantic Version: 0.1.0-alpha */
    version_major:  .byte 0
    version_minor:  .byte 1
    version_patch:  .byte 0
    version_stage:  .asciz "alpha"
    
    /* Version String: "0.1.0-alpha" */
    version_string: .ascii "0.1.0-alpha"
    version_string_len = . - version_string
    
    /* Full Version with Build Info */
    version_full:   .ascii "ANX/0.1.0-alpha (AArch64 Assembly HTTP Server)"
    version_full_len = . - version_full
    
    /* Build Date - will be updated by build script */
    build_date:     .ascii __DATE__
    build_date_len = . - build_date

/* Version constants for feature flags */
.equ HTTP2_ENABLED, 1
.equ WEBSOCKET_ENABLED, 1
.equ TLS_ENABLED, 0      /* TLS will be in v0.2.0 */
