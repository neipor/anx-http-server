.global msg_version_current, len_version_current
.data
msg_version_current: .ascii "5a215f0-dirty"
len_version_current = . - msg_version_current
