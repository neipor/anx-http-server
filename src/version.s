/* version.s - Auto-generated version information */
.global msg_version_current, len_version_current
.global version_major, version_minor, version_patch
.data
msg_version_current: .ascii "v0.4.0-dev"
len_version_current = . - msg_version_current
version_major: .byte 0
version_minor: .byte 4
version_patch: .byte 0
