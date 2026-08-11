#!/usr/bin/env bash
# Stress/safety probe for ANX (B8 cache build). Runs in-container.
#   (1) connection storm:  200 parallel conns, one GET each
#   (2) slow-client:       10 conns trickling a request 1 byte/0.4s, then complete
#   (3) malformed fuzz:    garbage/bad-header/oversize/traversal requests all
#                          answered without crash (every worker still alive)
#   (4) keepalive abuse:   100 requests over one conn, x5 conns
#   (5) pipeline burst:    50 pipelined requests in one write
#   (6) worker SIGKILL:    master respawns it; next request still 200
#   (7) cache hit during storm: repeats of (1) against a cached file must stay
#                          byte-identical (hash churn stress)
set -u
H=127.0.0.1; PORT=18081
DR=/tmp/stress_dr; LOG=/tmp/stress.log
BIN=/src/build/anx
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "[PASS] $1 $3"; else F=$((F+1)); echo "[FAIL] $1 $3"; fi; }
alive(){ # count live anx workers (non-zombie)
  ps -o stat=,comm= -C anx 2>/dev/null | awk '$1 !~ /Z/{c++} END{print c+0}'
}

# --- setup ---
rm -rf "$DR"; mkdir -p "$DR"
printf 'hi\n' > "$DR/index.html"
head -c 7000 /dev/urandom > "$DR/rand.bin"
pkill -x anx 2>/dev/null; sleep 0.3
"$BIN" -p "$PORT" -d "$DR" >"$LOG" 2>&1 &
sleep 0.8
# readiness
exec 3<>"/dev/tcp/$H/$PORT" 2>/dev/null
printf 'GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n' >&3
timeout 2 cat <&3 >/dev/null 2>&1
exec 3<&- 3>&- 2>/dev/null
BASE=$(alive)

# (1) storm: 200 parallel conns
seq 1 200 | xargs -P 50 -I{} bash -c '
  exec 9<>/dev/tcp/127.0.0.1/18081 2>/dev/null || exit 1
  printf "GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n" >&9
  timeout 2 cat <&9 2>/dev/null | grep -q "HTTP/1.1 200" || exit 1
  exec 9<&- 9>&- 2>/dev/null' && S1=1 || S1=0
ok "(1) 200-conn storm all 200" "$S1"

# (2) slow-client: trickle then finish
seq 1 10 | xargs -P 10 -I{} bash -c '
  exec 9<>/dev/tcp/127.0.0.1/18081 2>/dev/null || exit 1
  printf "G" >&9; sleep 0.25; printf "ET /ind" >&9; sleep 0.25
  printf "ex.html HTTP/1.1\r\nHost: x\r\n\r\n" >&9
  timeout 2 cat <&9 2>/dev/null | grep -q "HTTP/1.1 200" || exit 1
  exec 9<&- 9>&- 2>/dev/null' && S2=1 || S2=0
ok "(2) slow-client x10" "$S2"

# (3) malformed fuzz: every case must get a response (any 4xx/2xx) and all
# workers must survive. No response at all = hang = FAIL.
bad() { # bad <bytes-with-%b-escapes>  (expect: some reply, any code)
  exec 9<>/dev/tcp/127.0.0.1/18081 2>/dev/null || { ok "(3f) $1" 0 "conn"; return; }
  printf '%b' "$2" >&9 2>/dev/null
  R=$(timeout 2 cat <&9 2>/dev/null)
  exec 9<&- 9>&- 2>/dev/null
  case "$R" in
    *"HTTP/1.1"*) ok "(3f) $1" 1;;
    *) ok "(3f) $1" 0 "no-reply";;
  esac
}
bad "garbage"          '\x01\x02\x03\xff\x00GET'
bad "no-host"          'GET /index.html HTTP/1.1\r\n\r\n'
bad "http09"           'GET /index.html\r\n\r\n'
bad "bad-method"       'BREW /index.html HTTP/1.1\r\nHost: x\r\n\r\n'
bad "traversal"        'GET /../../etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n'
bad "traversal2"       'GET /subdir/../../etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n'
bad "percent-enc"      'GET /%2e%2e/%2e%2e/etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n'
bad "ctrl-in-header"   'GET /index.html HTTP/1.1\r\nHost: x\r\nX-A: \x01\x02\x03\r\n\r\n'
bad "crlf-inject"      'GET /index.html HTTP/1.1\r\nHost: x\r\nX-A: 1\r\nInjected: yes\r\n\r\n'
bad "double-get"       'GET /index.html HTTP/1.1\r\nHost: x\r\n\r\nGET /index.html HTTP/1.1\r\nHost: x\r\n\r\n'
bad "NUL-in-path"      'GET /ind\x00ex.html HTTP/1.1\r\nHost: x\r\n\r\n'
oversize() { # header past REQ_BUF_MAX -> server must close without response (not hang)
  exec 9<>/dev/tcp/127.0.0.1/18081 2>/dev/null || { ok "(3) oversize hdr" 0 "conn"; return; }
  { printf 'GET /index.html HTTP/1.1\r\nHost: x\r\nX-Big: '; head -c 9000 /dev/zero | tr '\0' 'A'; printf '\r\n\r\n'; } >&9
  R=$(timeout 2 cat <&9 2>/dev/null)
  exec 9<&- 9>&- 2>/dev/null
  [ -z "$R" ] && ok "(3) oversize hdr closed" 1 || ok "(3) oversize hdr closed" 0 "replied len=${#R}"
}
oversize
ok "(3) workers alive after fuzz" "$([ "$(alive)" -ge "$BASE" ] && echo 1 || echo 0)" "alive=$(alive)"

# (4) keepalive abuse: 100 reqs per conn, x5
seq 1 5 | xargs -P 5 -I{} bash -c '
  exec 9<>/dev/tcp/127.0.0.1/18081 2>/dev/null || exit 1
  for i in $(seq 1 100); do printf "GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n" >&9; done
  timeout 4 cat <&9 2>/dev/null | grep -o "HTTP/1.1 200" | wc -l' > /tmp/ka_counts.txt
SUM=0; while read n; do SUM=$((SUM+n)); done < /tmp/ka_counts.txt
ok "(4) keepalive 5x100 all 200" "$([ "$SUM" = 500 ] && echo 1 || echo 0)" "got=$SUM"

# (5) pipeline burst: 50 reqs in one write
exec 9<>/dev/tcp/127.0.0.1/18081 2>/dev/null
for i in $(seq 1 50); do printf 'GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n' >&9; done
timeout 4 cat <&9 2>/dev/null | grep -o "HTTP/1.1 200" | wc -l > /tmp/pipe_count.txt
exec 9<&- 9>&- 2>/dev/null
PIPE=$(cat /tmp/pipe_count.txt)
ok "(5) 50 pipelined all 200" "$([ "$PIPE" = 50 ] && echo 1 || echo 0)" "got=$PIPE"

# (6) worker SIGKILL -> respawn -> still serves
WPID=$(ps -o pid=,stat=,comm= -C anx 2>/dev/null | awk '$1 !~ /Z/ && $3=="anx"{print $2}' | head -1)
[ -n "$WPID" ] && kill -9 "$WPID" 2>/dev/null
sleep 1.0
exec 9<>/dev/tcp/127.0.0.1/18081 2>/dev/null
printf 'GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n' >&9
R=$(timeout 2 cat <&9 2>/dev/null); exec 9<&- 9>&- 2>/dev/null
case "$R" in *"HTTP/1.1 200"*) ok "(6) worker respawn serves" 1;; *) ok "(6) worker respawn serves" 0 "resp=${R:0:40}";; esac

# (7) cached-file storm: 300 GETs of rand.bin (7000B), bodies must be identical
seq 1 300 | xargs -P 50 -I{} bash -c '
  exec 9<>/dev/tcp/127.0.0.1/18081 2>/dev/null || exit 1
  printf "GET /rand.bin HTTP/1.1\r\nHost: x\r\n\r\n" >&9
  timeout 2 cat <&9 2>/dev/null | tail -c 7000 | md5sum | cut -d" " -f1' 2>/dev/null | sort -u > /tmp/storm_md5.txt
N=$(wc -l < /tmp/storm_md5.txt)
ok "(7) 300x cached 7000B identical" "$([ "$N" = 1 ] && echo 1 || echo 0)" "distinct=$N"
head -1 /tmp/storm_md5.txt | sed 's/^/      body-md5=/'

# workers still alive at end
ok "(end) workers alive" "$([ "$(alive)" -ge "$BASE" ] && echo 1 || echo 0)" "alive=$(alive)"
pkill -x anx 2>/dev/null
echo "---"
echo "stress: PASS=$P FAIL=$F"
[ "$F" -eq 0 ] || exit 1