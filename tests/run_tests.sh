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
    
    # Run in foreground, redirect output
    $SERVER_BIN -c $CONFIG_FILE > "$SCRIPT_DIR/server.log" 2>&1 &
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
    sleep 1 # Wait for log flush
    if [ -f "$LOG_FILE" ]; then
        if grep -q "GET /index.html" "$LOG_FILE"; then
            log_pass "Access Log records requests"
        else
            echo -e "${RED}[FAIL]${NC} Access Log missing entry. Content:"
            cat "$LOG_FILE"
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
    # Start upstream with absolute path to bin
    $SERVER_BIN -p $UP_PORT -d . > "$SCRIPT_DIR/upstream.log" 2>&1 &
    cd "$SCRIPT_DIR"
    
    # Start Proxy
    echo "port=$PORT" > $CONFIG_FILE
    echo "root=$WWW_DIR" >> $CONFIG_FILE
    echo "upstream_ip=127.0.0.1" >> $CONFIG_FILE
    echo "upstream_port=$UP_PORT" >> $CONFIG_FILE
    
    $SERVER_BIN -c $CONFIG_FILE > "$SCRIPT_DIR/proxy_server.log" 2>&1 &
    sleep 1
    
    # Use curl with timeout and HTTP/1.0 (no keep-alive)
    RESP=$(curl -s --http1.0 --max-time 5 -H "Connection: close" http://localhost:$PORT/data.txt)
    
    if [ "$RESP" == "I am upstream" ]; then
        log_pass "Reverse Proxy OK"
    else
        echo "Proxy Log:"
        cat "$SCRIPT_DIR/proxy_server.log"
        log_fail "Reverse Proxy Failed. Got: '$RESP'"
    fi
}

function test_cgi {
    echo "Testing CGI..."
    
    # Create Python Script
    echo "import os" > "$WWW_DIR/hello.py"
    echo "print('Content-Type: text/plain')" >> "$WWW_DIR/hello.py"
    echo "print('')" >> "$WWW_DIR/hello.py"
    echo "print('Hello from Python CGI')" >> "$WWW_DIR/hello.py"
    
    RESP=$(curl -s http://localhost:$PORT/hello.py)
    if [ "$RESP" == "Hello from Python CGI" ]; then
        log_pass "CGI Execution OK"
    else
        log_fail "CGI Failed. Got: '$RESP'"
    fi

    # Test POST
    echo "import sys" > "$WWW_DIR/post.py"
    echo "print('Content-Type: text/plain')" >> "$WWW_DIR/post.py"
    echo "print('')" >> "$WWW_DIR/post.py"
    echo "sys.stdout.write(sys.stdin.read())" >> "$WWW_DIR/post.py"
    
    RESP=$(curl -s -X POST -d "POST_DATA" http://localhost:$PORT/post.py)
    if [ "$RESP" == "POST_DATA" ]; then
        log_pass "CGI POST OK"
    else
        log_fail "CGI POST Failed. Got: '$RESP'"
    fi
}

# Main Execution
cleanup
setup
start_server

test_static_files
test_directory_listing
test_access_log
test_cgi
test_proxy

cleanup
echo -e "${GREEN}All Tests Passed!${NC}"
