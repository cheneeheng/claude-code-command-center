#!/usr/bin/env bash
set -euo pipefail

# Smoke test for statusline-hook: pipe a sample of the JSON blob Claude Code
# feeds the hook on stdin and assert the happy path — it exits 0, prints a
# colour-coded status line carrying the model/context/cost, and (with the
# opt-in export on) appends the turn to the per-project/per-session JSONL log
# the dashboard reads. Guards the "green ruff but the hook won't actually run"
# failure class that static checks miss. The hook is copied into a throwaway
# dir first so its export writes there, not into the repo tree.

HOOK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"

cleanup() {
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

cp "$HOOK_DIR/statusline-hook.py" "$WORK/statusline-hook.py"

# A representative stdin payload (Pro/Max shape, incl. rate limits).
read -r -d '' PAYLOAD <<'EOF' || true
{"model":{"id":"claude-opus-4-8"},"session_id":"sess1234","cwd":"/home/u/proj",
 "cost":{"total_duration_ms":90000,"total_cost_usd":1.2345},
 "context_window":{"used_percentage":42,"context_window_size":200000},
 "rate_limits":{"five_hour":{"used_percentage":10,"resets_at":0},
                "seven_day":{"used_percentage":20,"resets_at":0}}}
EOF

# Happy path: emits a status line carrying model, context %, and cost.
out="$(printf '%s' "$PAYLOAD" | C4_STATUSLINE_EXPORT=1 python3 "$WORK/statusline-hook.py")" \
  || fail "hook exited non-zero"
echo "$out" | grep -q "claude-opus-4-8" || fail "model missing from status line"
echo "$out" | grep -q "42%" || fail "context percentage missing"
echo "$out" | grep -q '\$1.2345' || fail "cost missing from status line"

# Export path: the turn was appended as one JSONL record the dashboard can read.
log="$(find "$WORK/statusline" -name '*.jsonl' 2>/dev/null | head -n1)"
[ -n "$log" ] || fail "export enabled but no JSONL log written"
python3 -c "import json,sys; json.loads(open(sys.argv[1]).readline())" "$log" \
  || fail "JSONL log line is not valid JSON"

echo "PASS"
