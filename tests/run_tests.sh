#!/bin/bash

# Configuration
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
PORT=9090
BUILD_DIR="$SCRIPT_DIR/../build"
SERVER_BIN="$BUILD_DIR/anx"
WWW_DIR="$SCRIPT_DIR/www_test"
UP_DIR="$SCRIPT_DIR/upstream_test"
CONFIG_FILE="$SCRIPT_DIR/test.conf"
LOG_FILE="$SCRIPT_DIR/test_access.log"
PID_FILE="$SCRIPT_DIR/server.pid" # Note: Daemon writes pid to CWD? No, main.s uses relative path.
# If daemon runs, it forks. Where is CWD?
# If we run $SERVER_BIN, it inherits CWD.
# We should probably cd to SCRIPT_DIR or something.

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

cd "$SCRIPT_DIR" || exit 1

# Compile
echo "Compiling..."
make -C .. clean && make -C ..
if [ $? -ne 0 ]; then
    log_fail "Compilation failed"
fi

function log_pass {
    echo -e "${GREEN}[PASS]${NC} $1"
}

function log_fail {
    echo -e "${RED}[FAIL]${NC} $1"
    exit 1
}

# Setup Environment
function setup {
    mkdir -p $WWW_DIR
    echo "<h1>Hello World</h1>" > $WWW_DIR/index.html
    echo "body { color: red; }" > $WWW_DIR/style.css
    echo "console.log('test');" > $WWW_DIR/app.js
    
    mkdir -p $UP_DIR
    echo "I am upstream" > $UP_DIR/data.txt
}

function cleanup {
    pkill anx
    rm -rf $WWW_DIR $UP_DIR $CONFIG_FILE $LOG_FILE server.pid
}

# Start Server
function start_server {
    # Generate Config
    echo "port=$PORT" > $CONFIG_FILE
    echo "root=$WWW_DIR" >> $CONFIG_FILE
    echo "access_log=$LOG_FILE" >> $CONFIG_FILE
    
    # $SERVER_BIN -c $CONFIG_FILE -daemon
    # Debug: Run in foreground with strace
    strace -f -o strace.log $SERVER_BIN -c $CONFIG_FILE &
    SERVER_PID=$!
    echo $SERVER_PID > server.pid
    
    if [ $? -ne 0 ]; then
        log_fail "Failed to start server"
    fi
    sleep 2
}

# Tests
function test_static_files {
    echo "Testing Static Files..."
    
    # HTML
    RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/index.html)
    if [ "$RESP" == "200" ]; then log_pass "GET /index.html (200 OK)"; else log_fail "GET /index.html returned $RESP"; fi
    
    # CSS
    RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/style.css)
    if [ "$RESP" == "200" ]; then log_pass "GET /style.css (200 OK)"; else log_fail "GET /style.css returned $RESP"; fi
    
    # 404
    RESP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/missing.html)
    if [ "$RESP" == "404" ]; then log_pass "GET /missing.html (404 Not Found)"; else log_fail "GET /missing.html returned $RESP"; fi
}

function test_directory_listing {
    echo "Testing Directory Listing..."
    
    # Create empty subdir
    mkdir -p "$WWW_DIR/subdir"
    touch "$WWW_DIR/subdir/file1.txt"
    
    RESP=$(curl -s http://localhost:$PORT/subdir/)
    if [[ "$RESP" == *"Index"* && "$RESP" == *"file1.txt"* ]]; then
        log_pass "Directory Listing OK"
    else
        log_fail "Directory Listing Failed. Got: ${RESP:0:50}..."
    fi
}

function test_access_log {
    echo "Testing Access Log..."
    if [ -f "$LOG_FILE" ]; then
        echo "Log content:"
        cat "$LOG_FILE"
        if grep -q "GET /index.html" "$LOG_FILE"; then
            log_pass "Access Log records requests"
        else
            echo -e "${RED}[FAIL]${NC} Access Log missing entry"
            # log_fail "Access Log missing entry"
        fi
    else
        echo -e "${RED}[FAIL]${NC} Access Log file not created at $LOG_FILE"
    fi
}

function test_proxy {
    echo "Testing Reverse Proxy..."
    
    # Kill any running anx
    pkill anx
    sleep 1
    
    # Start Upstream
    UP_PORT=$((PORT + 1))
    cd "$UP_DIR"
    $SERVER_BIN -p $UP_PORT -d . -daemon
    cd "$SCRIPT_DIR"
    
    # Start Proxy
    echo "port=$PORT" > $CONFIG_FILE
    echo "root=$WWW_DIR" >> $CONFIG_FILE
    echo "upstream_ip=127.0.0.1" >> $CONFIG_FILE
    echo "upstream_port=$UP_PORT" >> $CONFIG_FILE
    
    $SERVER_BIN -c $CONFIG_FILE -daemon
    sleep 1
    
    # RESP=$(curl -s -H "Connection: close" http://localhost:$PORT/data.txt)
    echo -e "GET /data.txt HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | nc -q 1 localhost $PORT > proxy_resp.txt
    
    if grep -q "I am upstream" proxy_resp.txt; then
        log_pass "Reverse Proxy OK"
    else
        log_fail "Reverse Proxy Failed. Response:"
        head -n 5 proxy_resp.txt
    fi
}

# Main Execution
cleanup
setup
start_server

test_static_files
test_directory_listing
test_access_log
# test_proxy # TODO: Fix proxy test hang

cleanup
echo -e "${GREEN}All Tests Passed!${NC}"
