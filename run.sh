#!/bin/bash
PORT=${1:-18102}
DIR=${2:-test_www}

if [ ! -f "./build/anx" ]; then
    make
fi

echo "Starting ANX Server on port $PORT serving $DIR..."
nohup strace -f -o strace.log ./build/anx -p $PORT -d $DIR > server.log 2>&1 &
PID=$!
echo $PID > server.pid
echo "Server PID: $PID"
sleep 1