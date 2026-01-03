#!/bin/bash

SERVER_BIN="./anx_asm_demo"
LOG_FILE="server.log"
PID_FILE="server.pid"
MAX_SIZE=$((1024 * 1024)) # 1MB

# Ensure we are in the right directory or binary exists
if [ ! -f "$SERVER_BIN" ]; then
    echo "Error: Server binary '$SERVER_BIN' not found. Please build it first."
    exit 1
fi

if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Server is already running with PID $OLD_PID"
        exit 1
    else
        echo "Removing stale PID file."
        rm "$PID_FILE"
    fi
fi

# Start server in background
echo "Starting server..."
$SERVER_BIN >> "$LOG_FILE" 2>&1 &
PID=$!
echo "$PID" > "$PID_FILE"
echo "Server started with PID $PID"

# Monitor loop
while kill -0 "$PID" 2>/dev/null; do
    if [ -f "$LOG_FILE" ]; then
        SIZE=$(stat -c%s "$LOG_FILE")
        if [ "$SIZE" -gt "$MAX_SIZE" ]; then
            TIMESTAMP=$(date +%Y%m%d-%H%M%S)
            echo "[MONITOR] Rotating log file at $(date)" >> "$LOG_FILE"
            
            # Simple rotation: copy and truncate
            # Note: This is not atomic and might lose log lines, but sufficient for this demo.
            # A better approach would be to signal the server to reopen logs, 
            # but our server uses printf/stdout.
            cp "$LOG_FILE" "$LOG_FILE.$TIMESTAMP.old"
            > "$LOG_FILE"
            
            # Keep only last 5 logs
            ls -t $LOG_FILE.*.old 2>/dev/null | tail -n +6 | xargs -r rm
        fi
    fi
    sleep 5
done

echo "Server stopped."
rm -f "$PID_FILE"
