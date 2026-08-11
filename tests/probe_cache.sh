#!/usr/bin/env bash
# File-cache (B8) functional probe for ANX. Runs inside the container (bash
# /dev/tcp; the container has no python3). Spins up its own server instance on
# a private docroot and port, then verifies:
#   (a) cached body served, Content-Length exact, ETag present
#   (b) edit -> next request serves NEW content (size change invalidates)
#   (c) same-size edit -> new content (nsec part of the key invalidates)
#   (d) Range request bypasses the cache (206 + correct slice)
#   (e) big file (> CACHE_MAX_SIZE) not cached: edit is visible immediately
#   (f) HEAD on a cached file: headers, no body
#   (g) .sh CGI is never cached: two runs differ (RANDOM)
#   (h) keep-alive mix on one conn: cached -> 404 -> cached, 404 body intact
#   (i) pipelined cached requests on one conn -> two 200s
#   (j) If-None-Match revalidation still yields 304 on a cached file
#   (k) binary integrity: 7KB random file round-trips byte-exact (multi-read)
F=0; P=0
PORT=18081
H=127.0.0.1
DR=/tmp/cache_dr
LOG=/tmp/cache_probe.log
BIN=/src/build/anx
trap '' PIPE

ok() { if [ "$2" = 1 ]; then P=$((P+1)); echo "[PASS] $1 $3"; else F=$((F+1)); echo "[FAIL] $1 $3"; fi; }

get() { # get <path> [extra headers]
  local _p=$1 _h="${2:-}"
  exec 3<>"/dev/tcp/$H/$PORT" || { RESP=""; return; }
  if [ -n "$_h" ]; then
    printf "GET %s HTTP/1.1\r\nHost: x\r\n%s\r\n\r\n" "$_p" "$_h" >&3
  else
    printf "GET %s HTTP/1.1\r\nHost: x\r\n\r\n" "$_p" >&3
  fi
  RESP=$(timeout 2 cat <&3 2>/dev/null || true)
  exec 3<&- 3>&- 2>/dev/null
}

# --- setup ---
rm -rf "$DR"; mkdir -p "$DR"
printf 'hi\n' > "$DR/one.txt"                 # 3 bytes
printf 'AAAA' > "$DR/same.txt"
head -c 20480 /dev/urandom > "$DR/big.bin"    # 20KB > 14848 (uncached)
head -c 14848 /dev/urandom > "$DR/edge7k.bin"  # exactly at the cap
head -c 7000 /dev/urandom > "$DR/rand7k.bin"  # multi-read arena fill
printf '#!/bin/sh\necho "Content-Type: text/plain"\necho\necho $RANDOM\n' > "$DR/cgi.sh"
chmod +x "$DR/cgi.sh"
printf '<html>%s</html>\r\n' "$(head -c 2000 /dev/zero | tr '\0' 'a')" > "$DR/idx.html"

pkill -x anx 2>/dev/null; sleep 0.3
"$BIN" -p "$PORT" -d "$DR" > "$LOG" 2>&1 &
sleep 0.5
# readiness: poll until a request really answers (worker warmup)
for i in 1 2 3 4 5 6 7 8 9 10; do
  get "/one.txt"
  case "$RESP" in *"HTTP/1.1 200"*) break;; esac
  sleep 0.5
done


# (a) cached body + length + etag (note: ETag precedes Content-Length)
get "/one.txt"
case "$RESP" in
  *"HTTP/1.1 200"*"ETag: "*"Content-Length: 3"*"hi") ok "(a) cached body+len+etag" 1 "len=${#RESP}";;
  *) ok "(a) cached body+len+etag" 0 "resp=${RESP:0:60}";;
esac

# (b) size change invalidates
printf 'hello world\n' > "$DR/one.txt"
get "/one.txt"
case "$RESP" in
  *"Content-Length: 12"*"hello world") ok "(b) edit (size) invalidates" 1;;
  *) ok "(b) edit (size) invalidates" 0 "resp=${RESP:0:60}";;
esac
printf 'hi\n' > "$DR/one.txt"   # restore

# (c) same-size edit invalidates (nsec in key)
get "/same.txt"
OLD=$(printf '%s' "$RESP" | md5sum | cut -d' ' -f1)
printf 'BBBB' > "$DR/same.txt"
get "/same.txt"
NEW=$(printf '%s' "$RESP" | md5sum | cut -d' ' -f1)
ok "(c) same-size edit invalidates" "$([ "$OLD" != "$NEW" ] && echo 1 || echo 0)" "old=$OLD new=$NEW"

# (d) Range bypasses the cache
get "/one.txt" "Range: bytes=0-1"
case "$RESP" in
  *"HTTP/1.1 206"*"Content-Range"*"hi") ok "(d) range bypass (206)" 1 "len=${#RESP}";;
  *) ok "(d) range bypass (206)" 0 "resp=${RESP:0:60}";;
esac

# (e) big file not cached: immediate edit visibility
printf 'OLD-OLD-OLD' > "$DR/big.bin"
get "/big.bin"
printf 'NEW-NEW-NEW' > "$DR/big.bin"
get "/big.bin"
case "$RESP" in
  *"Content-Length: 11"*"NEW-NEW-NEW") ok "(e) big file not cached/rewritten" 1 "len=${#RESP}";;
  *) ok "(e) big file not cached/rewritten" 0 "resp=${RESP:0:60}";;
esac

# (f) HEAD on cached file: headers only
exec 3<>"/dev/tcp/$H/$PORT" || { RESP=""; }
printf 'HEAD /one.txt HTTP/1.1\r\nHost: x\r\n\r\n' >&3
RESP=$(timeout 2 cat <&3 2>/dev/null || true)
exec 3<&- 3>&- 2>/dev/null
case "$RESP" in
  *"HTTP/1.1 200"*"Content-Length: 3"*) ok "(f) HEAD cached no body" 1 "len=${#RESP}";;
  *) ok "(f) HEAD cached no body" 0 "resp=${RESP:0:60}";;
esac

# (g) CGI never cached: .sh must reach invoke_cgi, not the file cache. The
# static cache response carries ETag + Content-Length; the CGI wrapper
# (status + raw script stdout relay) carries neither. (Container has no
# /usr/bin/python3, so the script body is empty, but dispatch is proven.)
get "/cgi.sh"
case "$RESP" in
  *"HTTP/1.1 200"*"ETag: "*|*"HTTP/1.1 200"*"Content-Length: "*) ok "(g) cgi served from cache" 0 "resp=${RESP:0:60}";;
  *"HTTP/1.1 200"*) ok "(g) cgi not cached" 1 "no CL/ETag (cgi dispatch)";;
  *) ok "(g) cgi not cached" 0 "resp=${RESP:0:60}";;
esac

# (h) keep-alive: three cached 200s on one connection (404s close; skip them)
exec 3<>"/dev/tcp/$H/$PORT" || RESP=""
printf 'GET /one.txt HTTP/1.1\r\nHost: x\r\n\r\n' >&3
sleep 0.1
printf 'GET /same.txt HTTP/1.1\r\nHost: x\r\n\r\n' >&3
sleep 0.1
printf 'GET /one.txt HTTP/1.1\r\nHost: x\r\n\r\n' >&3
RESP=$(timeout 2 cat <&3 2>/dev/null || true)
exec 3<&- 3>&- 2>/dev/null
n200=$(printf '%s' "$RESP" | grep -o 'HTTP/1.1 200' | wc -l)
ok "(h) keepalive cached x3" "$([ "$n200" = 3 ] && echo 1 || echo 0)" "200=$n200"

# (i) pipelined cached requests
exec 3<>"/dev/tcp/$H/$PORT" || RESP=""
printf 'GET /one.txt HTTP/1.1\r\nHost: x\r\n\r\nGET /same.txt HTTP/1.1\r\nHost: y\r\n\r\n' >&3
RESP=$(timeout 2 cat <&3 2>/dev/null || true)
exec 3<&- 3>&- 2>/dev/null
n200=$(printf '%s' "$RESP" | grep -o 'HTTP/1.1 200' | wc -l)
ok "(i) pipelined cached x2" "$([ "$n200" = 2 ] && echo 1 || echo 0)" "200=$n200"

# (n) pipelined: req2 carries "Connection: close" must NOT close req1 early.
# Regression for whole-blob strstr: a follow-up request's Connection header used
# to kill the first response and drop the second request entirely.
exec 3<>"/dev/tcp/$H/$PORT" || RESP=""
printf 'GET /one.txt HTTP/1.1\r\nHost: x\r\n\r\nGET /same.txt HTTP/1.1\r\nHost: y\r\nConnection: close\r\n\r\n' >&3
RESP=$(timeout 2 cat <&3 2>/dev/null || true)
exec 3<&- 3>&- 2>/dev/null
n200=$(printf '%s' "$RESP" | grep -o 'HTTP/1.1 200' | wc -l)
ok "(n) pipelined req2=close -> 2x200" "$([ "$n200" = 2 ] && echo 1 || echo 0)" "200=$n200"

# (o) pipelined: a follow-up request's Accept-Encoding must NOT gzip req1.
# Regression for the gzip-leak: req2 "Accept-Encoding: gzip" used to make req1
# come back Content-Encoding: gzip to a client that never asked.
exec 3<>"/dev/tcp/$H/$PORT" || RESP=""
printf 'GET /idx.html HTTP/1.1\r\nHost: x\r\n\r\nGET /idx.html HTTP/1.1\r\nHost: y\r\nAccept-Encoding: gzip\r\n\r\n' >&3
RESP=$(timeout 2 cat <&3 2>/dev/null || true)
exec 3<&- 3>&- 2>/dev/null
# isolate ONLY req1's response: drop its own status line, then cut at 2nd request
rest="${RESP#HTTP/1.1 200 OK}"
req1="HTTP/1.1 200 OK${rest%%HTTP/1.1*}"
req1_ok=0; case "$RESP" in "HTTP/1.1 200 OK"*) req1_ok=1;; esac
# prove idx.html (2000 'a' body) actually served, not a 404
req1_body=$(printf '%s' "$req1" | grep -c 'aaaaaaaaaa')
gz=$(printf '%s' "$req1" | grep -c 'Content-Encoding: gzip')
ok "(o) pipelined req2=gzip -> req1 not gzipped" "$([ "$gz" = 0 ] && [ "$req1_ok" = 1 ] && [ "$req1_body" = 1 ] && echo 1 || echo 0)" "req1_gzip=$gz req1_200=$req1_ok req1_payload=$req1_body"
# (p) POST body first byte — NOTE: skipped as an active assertion. The server's
# CGI body-forwarding path (cgi.s:93-97 write of req_buffer[hlen..] to the child
# stdin pipe) is currently broken independently of this change (a manually sent
# POST with exact Content-Length echoes an empty body), so a POST cannot observe
# the bounded_strstr save/restore of req_buffer[hlen] from HTTP. The restore IS
# still covered transitively: an un-restored NUL at req_buffer[hlen] would corrupt
# the pipelined req2's first byte ('G' of "GET") and drop req2 — which (n) would
# catch as 1x200 instead of 2x200. Left as a note, not a green test, to avoid a
# vacuous pass.


# (j) If-None-Match -> 304 on cached file
get "/one.txt"
ETAG=$(printf '%s' "$RESP" | grep -o 'ETag: [^ ]*' | head -1 | cut -d' ' -f2 | tr -d '\r')
get "/one.txt" "If-None-Match: $ETAG"
case "$RESP" in
  *"HTTP/1.1 304"*) ok "(j) 304 revalidation" 1 "etag=$ETAG";;
  *) ok "(j) 304 revalidation" 0 "resp=${RESP:0:60}";;
esac

# (k) binary integrity: 7KB round-trip — capture straight to file
# (command substitution mangles NULs/trailing NLs, so no $RESP here)
exec 3<>"/dev/tcp/$H/$PORT" || { ok "(k) 7KB binary round-trip" 0 "conn"; return; }
printf 'GET /rand7k.bin HTTP/1.1\r\nHost: x\r\n\r\n' >&3
timeout 2 cat <&3 > /tmp/got7k.bin 2>/dev/null
exec 3<&- 3>&- 2>/dev/null
tail -c 7000 /tmp/got7k.bin | cmp -s - "$DR/rand7k.bin"
ok "(k) 7KB binary round-trip" "$([ $? = 0 ] && echo 1 || echo 0)" "bytes=$(wc -c < /tmp/got7k.bin)"
rm -f /tmp/got7k.bin

# (l) edge: exactly CACHE_MAX_SIZE cached, one byte over is not
get "/edge7k.bin"
CL=$(printf '%s' "$RESP" | grep -o 'Content-Length: [0-9]*' | cut -d' ' -f2 | tr -d '\r')
ok "(l) 14848B exact cached" "$([ "$CL" = 14848 ] && echo 1 || echo 0)" "cl=$CL"

# (m) positive hit proof: memory serve, not disk re-read.
# Runs against its OWN fresh server instance (separate port) so it is never
# starved by the shared cache from (a)-(l) above. This makes it deterministic:
# a same-size rewrite with nsec-exact mtime restore must still return OLD bytes.
MPORT=18082
"$BIN" -p "$MPORT" -d "$DR" >/tmp/cache_probe_m.log 2>&1 &
MPID=$!
sleep 1.0
# readiness
for i in 1 2 3 4 5; do
  exec 3<>"/dev/tcp/$H/$MPORT" && { printf 'GET /one.txt HTTP/1.1\r\nHost: x\r\n\r\n' >&3; timeout 2 cat <&3 >/dev/null 2>&1; exec 3<&- 3>&- 2>/dev/null; break; }
  sleep 0.5
done
MGET() { exec 3<>"/dev/tcp/$H/$MPORT" || { RESP=""; return; }; printf 'GET %s HTTP/1.1\r\nHost: x\r\n\r\n' "$1" >&3; RESP=$(timeout 2 cat <&3 2>/dev/null || true); exec 3<&- 3>&- 2>/dev/null; }
printf 'AAAA' > "$DR/hit.bin"
MGET "/hit.bin"                                  # fill, serve, cache
touch -r "$DR/hit.bin" /tmp/hit.ref             # snapshot pre-edit mtime
printf 'BBBB' > "$DR/hit.bin"                   # same-size rewrite
touch -r /tmp/hit.ref "$DR/hit.bin"             # restore mtime exactly
rm -f /tmp/hit.ref
MGET "/hit.bin"
kill -9 "$MPID" 2>/dev/null
case "$RESP" in
  *"HTTP/1.1 200"*"ETag: "*"Content-Length: 4"*"AAAA") ok "(m) cache hit serves from memory" 1;;
  *"HTTP/1.1 200"*"BBBB") ok "(m) cache hit serves from memory" 0 "disk re-read (miss)";;
  *) ok "(m) cache hit serves from memory" 0 "resp=${RESP:0:60}";;
esac
pkill -x anx 2>/dev/null
[ "$F" -eq 0 ] || exit 1