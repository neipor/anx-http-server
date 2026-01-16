.global msg_version_current, len_version_current
.data
msg_version_current: .ascii "06a2435-dirty"
len_version_current = . - msg_version_current
