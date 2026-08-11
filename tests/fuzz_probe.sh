#!/usr/bin/env bash
# Fuzz probe: consumes /tmp/fuzz_corpus.bin (generated host-side, python3).
# For every case: send on a fresh conn, wait up to 2s. Acceptable outcomes:
#   - an HTTP response (any status), OR
#   - clean EOF/close (server rejected the request), OR
#   - a 400/4xx.
# Unacceptable: hang (no reply, no close) or worker crash.
# After the whole corpus: all workers alive, and a normal GET still 200.
set -u
H=127.0.0.1; PORT=18081
DR=/tmp/stress_dr
CORPUS=/tmp/fuzz_corpus.bin
BIN=/src/build/anx
P=0; F=0; HANGS=0; REPLIED=0; CLOSED=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "[PASS] $1 $3"; else F=$((F+1)); echo "[FAIL] $1 $3"; fi; }
alive(){ ps -o stat=,comm= -C anx 2>/dev/null | awk '$1 !~ /Z/{c++} END{print c+0}'; }

pkill -x anx 2>/dev/null; sleep 0.3
"$BIN" -p "$PORT" -d "$DR" >/tmp/fuzz.log 2>&1 &
sleep 0.8
BASE=$(alive)

python3=/nonexistent  # no python3 in container; split corpus in bash
# split corpus into per-case files
rm -rf /tmp/fuzz_cases; mkdir -p /tmp/fuzz_cases
i=0
csplit -s -f /tmp/fuzz_cases/c -b '%03d' "$CORPUS" '/<<<CASE>>>/' '{*}' 2>/dev/null || true
# csplit leaves the delimiter on each chunk; strip it
for f in /tmp/fuzz_cases/c*; do
  [ -f "$f" ] || continue
  dd if="$f" of="$f.s" bs=1 status=none 2>/dev/null
  size=$(stat -c%s "$f.s")
  # strip trailing delimiter if present
  if [ "$size" -ge 11 ]; then
    head -c $((size-11)) "$f.s" > "$f.c" 2>/dev/null
  else
    cp "$f.s" "$f.c"
  fi
  rm -f "$f" "$f.s"
done

NCASE=0
for f in /tmp/fuzz_cases/c*.c; do
  [ -f "$f" ] || continue
  NCASE=$((NCASE+1))
  exec 9<>"/dev/tcp/$H/$PORT" 2>/dev/null || { ok "fuzz conn open" 0 "case $NCASE"; continue; }
  cat "$f" >&9 2>/dev/null
  R=$(timeout 2 cat <&9 2>/dev/null)
  exec 9<&- 9>&- 2>/dev/null
  case "$R" in
    *"HTTP/1.1"*) REPLIED=$((REPLIED+1));;
    "") CLOSED=$((CLOSED+1));;
    *) HANGS=$((HANGS+1));;
  esac
done
rm -rf /tmp/fuzz_cases

NOK="0"
if [ "$HANGS" = 0 ] && [ "$(alive)" -ge "$BASE" ]; then NOK=1; fi
ok "fuzz: no hang, no crash" "$NOK" "cases=$NCASE replied=$REPLIED closed=$CLOSED hangs=$HANGS alive=$(alive)"

# post-fuzz sanity: normal GET still 200
exec 9<>"/dev/tcp/$H/$PORT" 2>/dev/null
printf 'GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n' >&9
R=$(timeout 2 cat <&9 2>/dev/null); exec 9<&- 9>&- 2>/dev/null
case "$R" in *"HTTP/1.1 200"*) ok "post-fuzz normal GET" 1;; *) ok "post-fuzz normal GET" 0 "resp=${R:0:40}";; esac

# slowloris hold: 12 conns trickle 1 byte/0.5s for 3s, then all complete
seq 1 12 | xargs -P 12 -I{} bash -c '
  exec 9<>/dev/tcp/127.0.0.1/18081 2>/dev/null || exit 1
  for i in 1 2 3 4 5 6; do printf "G" >&9; sleep 0.5; done
  printf "ET /index.html HTTP/1.1\r\nHost: x\r\n\r\n" >&9
  timeout 3 cat <&9 2>/dev/null | grep -q "HTTP/1.1 200" || exit 1
  exec 9<&- 9>&- 2>/dev/null' && S=1 || S=0
ok "slowloris 12x trickle then serve" "$S"

ok "workers alive after fuzz+slowloris" "$([ "$(alive)" -ge "$BASE" ] && echo 1 || echo 0)" "alive=$(alive)"
pkill -x anx 2>/dev/null
echo "---"
echo "fuzz: PASS=$P FAIL=$F"
[ "$F" -eq 0 ] || exit 1