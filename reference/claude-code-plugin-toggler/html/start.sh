#!/usr/bin/env bash
PORT=${1:-7779}
PROJECT_ROOT="$(pwd)"
cd "$(dirname "$0")"
python3 server.py "$PORT" "$PROJECT_ROOT" &
SERVER_PID=$!
READY=0
for i in 1 2 3; do
  sleep 1
  if curl -sf "http://localhost:$PORT/" > /dev/null; then
    READY=1
    break
  fi
done
if [ $READY -eq 0 ]; then
  echo "Warning: server may not be ready yet"
fi
xdg-open "http://localhost:$PORT/" 2>/dev/null || open "http://localhost:$PORT/"
echo "Skills Toggle running on http://localhost:$PORT (PID $SERVER_PID)"
