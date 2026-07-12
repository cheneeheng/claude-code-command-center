#!/usr/bin/env bash
set -euo pipefail

# Smoke test for roundtable: boot the real server against a fixture git repo and a
# fake `claude` on PATH, then walk the whole round loop end to end — board, planning
# session (plan detected from the filesystem), order, end turn, review, commit,
# close, next round with the carried follow-up. Guards the "green mypy but it won't
# actually boot/serve" failure class that static checks miss.

PORT=18640
WORK="$(mktemp -d)"
# Git Bash on Windows hands out /tmp/... paths the Windows Python cannot resolve;
# cygpath -m rewrites them as C:/... (a no-op concern on Linux CI, where it is absent).
if command -v cygpath >/dev/null 2>&1; then WORK="$(cygpath -m "$WORK")"; fi
SERVER_PID=""

cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

api() { # method path [json-body]
  local method=$1 path=$2 body=${3:-}
  if [ -n "$body" ]; then
    curl -sf -X "$method" -H "Content-Type: application/json" -d "$body" \
      "http://127.0.0.1:$PORT$path"
  else
    curl -sf -X "$method" "http://127.0.0.1:$PORT$path"
  fi
}

jget() { # extract a field from stdin JSON with a python expression over `p`
  uv run python -c "import sys, json; p = json.load(sys.stdin); print($1)"
}

# --- fixture repo + registry + fake claude ------------------------------------------

REPO="$WORK/fixture-repo"
mkdir -p "$REPO/.agents_workspace/planning"
git -C "$REPO" init -q -b main
git -C "$REPO" config user.email smoke@example.com
git -C "$REPO" config user.name smoke
echo "# fixture" > "$REPO/README.md"
git -C "$REPO" add -A && git -C "$REPO" commit -qm init

# The fake claude: emits a stream-json init + result, and on a planning prompt
# writes a plan file into the planning dir (cwd is the repo). Implemented in Python
# with per-platform wrappers so Windows CreateProcess can launch it too.
FAKEBIN="$WORK/bin"
mkdir -p "$FAKEBIN"
PYBIN="$(uv run python -c "import sys; print(sys.executable)")"
cat > "$FAKEBIN/fake_claude.py" <<'EOF'
import json
import os
import sys

prompt = sys.stdin.read()
print(json.dumps({"type": "system", "subtype": "init",
                  "session_id": "sid-smoke", "model": "claude-sonnet-4-5"}))
if "planning mode" in prompt:
    os.makedirs(os.path.join(".agents_workspace", "planning"), exist_ok=True)
    with open(os.path.join(".agents_workspace", "planning", "smoke-plan.md"),
              "w", encoding="utf-8") as fh:
        fh.write("# smoke plan\n")
    text = "Plan written."
else:
    with open("implemented.txt", "w", encoding="utf-8") as fh:
        fh.write("done\n")
    text = "Done."
print(json.dumps({"type": "assistant",
                  "message": {"content": [{"type": "text", "text": text}]}}))
print(json.dumps({"type": "result", "subtype": "success", "total_cost_usd": 0.01,
                  "usage": {"input_tokens": 100, "output_tokens": 50}}))
EOF
cat > "$FAKEBIN/claude" <<EOF
#!/usr/bin/env bash
exec "$PYBIN" "$FAKEBIN/fake_claude.py" "\$@"
EOF
chmod +x "$FAKEBIN/claude"
cat > "$FAKEBIN/claude.cmd" <<EOF
@"$PYBIN" "$FAKEBIN/fake_claude.py" %*
EOF
export PATH="$FAKEBIN:$PATH"

# Pin claude_bin to the fake explicitly — PATH lookup on Windows would resolve the
# real claude.exe over an extensionless script (never spawn the real CLI in a smoke).
FAKECLAUDE="$FAKEBIN/claude"
if command -v cygpath >/dev/null 2>&1; then FAKECLAUDE="$FAKEBIN/claude.cmd"; fi

cat > "$WORK/.roundtable.json" <<EOF
{"port": $PORT,
 "defaults": {"claude_bin": "$FAKECLAUDE"},
 "projects": [{"name": "fixture", "path": "$REPO"}]}
EOF

export C4_ROUNDTABLE_HOME="$WORK/state"

# --- boot ----------------------------------------------------------------------------

uv run roundtable --registry "$WORK/.roundtable.json" serve --port "$PORT" &
SERVER_PID=$!

for _ in $(seq 1 15); do
  curl -sf "http://127.0.0.1:$PORT/api/board" >/dev/null 2>&1 && break
  sleep 1
done

# --- board + static -------------------------------------------------------------------

api GET / | grep -qi '<html' || fail "/ did not serve HTML"
BOARD=$(api GET /api/board)
echo "$BOARD" | jget "p['projects'][0]['state']['branch']" | grep -q main \
  || fail "board did not show the fixture repo's branch"

# --- planning session: fake claude writes the plan, the app detects it ---------------

SID=$(api POST /api/sessions '{"project":"fixture","prompt":"plan the smoke feature"}' \
  | jget "p['id']")
for _ in $(seq 1 15); do
  STATUS=$(api GET "/api/sessions/$SID" | jget "p['status']")
  [ "$STATUS" = "idle" ] && break
  sleep 1
done
[ "$STATUS" = "idle" ] || fail "session never reached idle ($STATUS)"
api GET "/api/sessions/$SID" | jget "p['produced_plans'][0]['slug']" \
  | grep -q smoke-plan || fail "produced plan not detected"

# --- order + end turn + review --------------------------------------------------------

api POST /api/rounds/current/orders '{"project":"fixture","slug":"smoke-plan"}' \
  >/dev/null || fail "add order"
api POST /api/rounds/current/end-turn '{}' >/dev/null || fail "end turn"
for _ in $(seq 1 20); do
  RSTATUS=$(api GET /api/rounds/current | jget "p['status']")
  [ "$RSTATUS" = "review" ] && break
  sleep 1
done
[ "$RSTATUS" = "review" ] || fail "round never reached review ($RSTATUS)"

CUR=$(api GET /api/rounds/current)
OID=$(echo "$CUR" | jget "p['orders'][0]['id']")
echo "$CUR" | jget "p['orders'][0]['state']" | grep -q succeeded \
  || fail "order did not succeed"
api GET "/api/orders/$OID/output" | jget "len(p['lines']) > 0" | grep -q True \
  || fail "order output file empty"

# --- review: flag + follow-up + commit + close -----------------------------------------

api POST "/api/orders/$OID/reviewed" '{"reviewed":true}' >/dev/null || fail "reviewed"
api POST "/api/orders/$OID/followup" '{"note":"smoke follow-up"}' >/dev/null \
  || fail "followup"
api POST /api/repos/fixture/commit '{"message":"smoke: implement plan"}' \
  | jget "p['subject']" | grep -q smoke || fail "commit"
NEXT=$(api POST /api/rounds/current/close '{}')
echo "$NEXT" | jget "p['number']" | grep -q 2 || fail "close did not open round 2"
echo "$NEXT" | jget "p['carried_followups'][0]['note']" | grep -q "smoke follow-up" \
  || fail "follow-up not carried to round 2"

echo "PASS"
