.global msg_version_current, len_version_current
.data
msg_version_current: .ascii "49142e0-dirty"
len_version_current = . - msg_version_current
