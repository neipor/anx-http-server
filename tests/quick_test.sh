#!/bin/bash
# Quick validation test for CI

PORT=18080
SERVER="./build/anx"

echo "Starting ANX server..."
$SERVER -p $PORT -d www &
PID=$!
sleep 2

echo "Testing HTTP response..."
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT/)

if [ "$RESPONSE" == "200" ]; then
    echo "✓ Server responds with 200 OK"
    kill $PID 2>/dev/null
    exit 0
else
    echo "✗ Server returned: $RESPONSE"
    kill $PID 2>/dev/null
    exit 1
fi
