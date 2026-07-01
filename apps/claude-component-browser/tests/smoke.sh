#!/usr/bin/env bash
set -euo pipefail

# Smoke test for claude-component-browser: boot the server, then exercise the
# happy path end to end — /api/config prefill, /api/members scanned from
# UI-supplied dirs, and /api/member body-by-id. Guards the "green mypy but it
# won't actually run/serve" failure class that static checks miss.

PORT=17780
CDIR="$(mktemp -d)"      # a throwaway Claude dir holding one loose skill
PROJ="$(mktemp -d)"      # an empty project dir (no project-scope members)
SERVER_PID=""

cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "$CDIR" "$PROJ"
}
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

# One user-scope loose skill so /api/members is deterministic (exactly one).
mkdir -p "$CDIR/skills/smoke-skill"
cat > "$CDIR/skills/smoke-skill/SKILL.md" <<'EOF'
---
name: smoke-skill
description: smoke test skill
---
SMOKE_BODY_MARKER
EOF

python3 server.py --port "$PORT" &
SERVER_PID=$!

for _ in $(seq 1 10); do
  curl -sf "http://127.0.0.1:$PORT/api/config" >/dev/null 2>&1 && break
  sleep 1
done
curl -sf "http://127.0.0.1:$PORT/api/config" \
  | python3 -c "import sys,json; c=json.load(sys.stdin); assert 'claude_dir' in c and 'project_dir' in c" \
  || fail "server did not start / /api/config missing keys"

curl -sf --get "http://127.0.0.1:$PORT/api/members" \
     --data-urlencode "claude_dir=$CDIR" --data-urlencode "project_dir=$PROJ" \
  | python3 -c "
import sys, json
m = json.load(sys.stdin)
assert isinstance(m, list) and len(m) == 1, m
assert m[0]['name'] == 'smoke-skill' and m[0]['kind'] == 'skill', m[0]
assert 'path' not in m[0], 'path must never cross the wire'
" || fail "/api/members shape"

curl -sf "http://127.0.0.1:$PORT/api/member?id=0" | grep -q SMOKE_BODY_MARKER \
  || fail "/api/member body"

echo "PASS"
