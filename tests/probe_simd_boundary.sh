#!/usr/bin/env bash
# SIMD header-scan boundary probe for ANX (runs inside the container; the
# container has no python3, so this uses bash /dev/tcp).
#   (a) \r\n\r\n straddling a 16-byte window edge (offsets 0/12/13/14/15 mod
#       16 relative to scan start rpos=0)
#   (b) terminator split across two reads (read ends mid \r\n\r)
#   (c) pipelined requests: rpos != 0 for the 2nd scan (unaligned window)
#   (d) header > REQ_BUF_MAX -> server closes without a response
#   (e) keepalive: two sequential requests on one connection
#   (f) doubled CRLF: two candidates in one window, first must win
H=127.0.0.1; PORT=18080
FAILS=0; PASS=0

ok() { # name pass detail
  if [ "$2" = 1 ]; then PASS=$((PASS+1)); echo "[PASS] $1 $3"
  else FAILS=$((FAILS+1)); echo "[FAIL] $1 $3"; fi
}

# send_bytes <data>: open fresh conn, write (expanding \r\n), read until
# close or 1s idle
send_bytes() {
  exec 3<>"/dev/tcp/$H/$PORT" || { RESP=""; return; }
  printf '%b' "$1" >&3 2>/dev/null
  RESP=$(timeout 1 cat <&3 2>/dev/null || true)
  exec 3<&- 3>&- 2>/dev/null
}

# send_split <first> <second>: write first, pause, write second, then read
send_split() {
  exec 3<>"/dev/tcp/$H/$PORT" || { RESP=""; return; }
  printf '%b' "$1" >&3 2>/dev/null
  sleep 0.25
  printf '%b' "$2" >&3 2>/dev/null
  RESP=$(timeout 1 cat <&3 2>/dev/null || true)
  exec 3<&- 3>&- 2>/dev/null
}

SPINE='GET / HTTP/1.1\r\nHost: x\r\nX-L: '   # 30 bytes

# (a) terminator at offsets 0/12/13/14/15 mod 16
for target in 0 12 13 14 15; do
  pad=$(( (target - 30) % 16 ))
  [ $pad -lt 0 ] && pad=$(( pad + 16 ))
  pad_str=$(printf '%*s' "$pad" '')          # spaces only: no trailing-\n trap
  send_bytes "$SPINE$pad_str\r\n\r\n"
  case "$RESP" in
    *"HTTP/1.1 200"*"Content-Length"*) ok "(a) term@off${target} pad${pad}" 1 "len=${#RESP}";;
    *) ok "(a) term@off${target} pad${pad}" 0 "resp=${RESP:0:40}";;
  esac
done

# (b) split so the first read ends "\r\n\r", second read supplies the last \n
send_split 'GET / HTTP/1.1\r\nX: a\r\n\r' '\n'
case "$RESP" in *"HTTP/1.1 200"*) ok "(b) split mid-terminator" 1 "len=${#RESP}";;
  *) ok "(b) split mid-terminator" 0 "resp=${RESP:0:40}";; esac

# (b2) header halves in two reads, terminator whole in 2nd
send_split 'GET / HTTP/1.1\r\nX-L: ccccc\r' '\n\r\n'
case "$RESP" in *"HTTP/1.1 200"*) ok "(b2) split header half" 1 "len=${#RESP}";;
  *) ok "(b2) split header half" 0 "resp=${RESP:0:40}";; esac

# (c) pipelined: first header ends at len 39 (term@off35), 2nd scan unaligned
h1='GET / HTTP/1.1\r\nHost: x\r\nX-L: bbbbb\r\n\r\n'
h2='GET / HTTP/1.1\r\nHost: y\r\n\r\n'
send_bytes "$h1$h2"
n200=$(printf '%s' "$RESP" | grep -o 'HTTP/1.1 200' | wc -l)
ok "(c) pipelined x2 (rpos!=0)" "$([ "$n200" -ge 2 ] && echo 1 || echo 0)" "got $n200/2, len=${#RESP}"

# (d) oversized header (17KB) -> server closes, no response
pad_big=$(printf '%*s' 17000 '')
big="GET / HTTP/1.1\r\nX-Big: ${pad_big}\r\n\r\n"
send_bytes "$big"
ok "(d) header>REQ_BUF closed" "$([ -z "$RESP" ] && echo 1 || echo 0)" "resp=${RESP:0:40}"

# (e) keepalive: two sequential requests, one connection
exec 3<>"/dev/tcp/$H/$PORT" || { ok "(e) keepalive" 0 "no conn"; }
printf '%b' "$h2" >&3
sleep 0.1
printf '%b' "$h2" >&3
RESP=$(timeout 1 cat <&3 2>/dev/null || true)
exec 3<&- 3>&- 2>/dev/null
n200=$(printf '%s' "$RESP" | grep -o 'HTTP/1.1 200' | wc -l)
ok "(e) keepalive two reqs" "$([ "$n200" -ge 2 ] && echo 1 || echo 0)" "got $n200/2"

# (f) doubled CRLF in one window: first terminator must win, body not eaten
send_bytes 'GET / HTTP/1.1\r\nHost: x\r\n\r\n\r\n'
case "$RESP" in
  *"HTTP/1.1 200"*"Content-Length"*) ok "(f) doubled CRLF first wins" 1 "len=${#RESP}";;
  *) ok "(f) doubled CRLF first wins" 0 "resp=${RESP:0:40}";;
esac

echo "---"
echo "probe: PASS=$PASS FAIL=$FAILS"
[ "$FAILS" -eq 0 ] || exit 1