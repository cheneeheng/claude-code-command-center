#!/usr/bin/env bash
set -euo pipefail

# Smoke test for usage-dashboard: boot the server against a throwaway Claude dir
# holding one fabricated session, then exercise the happy path end to end — the
# static assets (/, /dashboard.css, /dashboard.js) and the /api/data payload
# assembled through the claude-usage library. Guards the "green mypy but it
# won't actually boot/serve" failure class that static checks miss.

PORT=17781
CDIR="$(mktemp -d)"      # a throwaway Claude dir with one session transcript
SERVER_PID=""

cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "$CDIR"
}
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

# One session transcript so /api/data returns a non-empty sessions list.
mkdir -p "$CDIR/projects/smoke-project"
cat > "$CDIR/projects/smoke-project/sess1234abcd.jsonl" <<'EOF'
{"type":"assistant","uuid":"a1","timestamp":"2026-01-01T00:00:00Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":200,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
EOF

python3 usage-dashboard.py --port "$PORT" --claude-dir "$CDIR" &
SERVER_PID=$!

for _ in $(seq 1 10); do
  curl -sf "http://127.0.0.1:$PORT/api/data" >/dev/null 2>&1 && break
  sleep 1
done

curl -sf "http://127.0.0.1:$PORT/api/data" | python3 -c "
import sys, json
p = json.load(sys.stdin)
assert set(p) >= {'stats', 'sessions', 'live'}, p.keys()
assert isinstance(p['sessions'], list) and len(p['sessions']) == 1, p['sessions']
" || fail "/api/data payload shape"

curl -sf "http://127.0.0.1:$PORT/" | grep -qi '<html' || fail "/ did not serve HTML"
curl -sf "http://127.0.0.1:$PORT/dashboard.css" >/dev/null || fail "/dashboard.css"
curl -sf "http://127.0.0.1:$PORT/dashboard.js" >/dev/null || fail "/dashboard.js"

# Live fast-poll endpoint: statusline only, must return a JSON object.
curl -sf "http://127.0.0.1:$PORT/api/live" | python3 -c "
import sys, json
p = json.load(sys.stdin)
assert 'available' in p, p
" || fail "/api/live payload shape"

# Markdown report: 200 with a non-empty body carrying the report title.
curl -sf "http://127.0.0.1:$PORT/api/report.md" | grep -q '# Claude Code Usage Report' \
  || fail "/api/report.md body"

echo "PASS"
