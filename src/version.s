.global msg_version_current, len_version_current
.data
msg_version_current: .ascii "8c34b8c-dirty"
len_version_current = . - msg_version_current
