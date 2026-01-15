.global msg_version_current, len_version_current
.data
msg_version_current: .ascii "725b603-dirty"
len_version_current = . - msg_version_current
