#!/usr/bin/env bash
set -euo pipefail

# Smoke test for usage-report: point it at a throwaway Claude dir holding one
# fabricated session (via $C4_CLAUDE_DIR, honoured by the claude-usage library),
# run the real CLI entrypoint, and assert the happy path — it exits 0 and prints
# the summary/rankings — plus the empty-dir path. Guards the "green mypy but the
# CLI won't actually run" failure class that static checks miss. Run via
# `uv run bash tests/smoke.sh` so the `usage-report` console script is on PATH.

CDIR="$(mktemp -d)"      # a throwaway Claude dir with one session transcript
EMPTY="$(mktemp -d)"     # a throwaway Claude dir with no sessions

cleanup() {
  rm -rf "$CDIR" "$EMPTY"
}
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

# One session transcript so the report has usage to summarise.
mkdir -p "$CDIR/projects/smoke-project"
cat > "$CDIR/projects/smoke-project/sess1234abcd.jsonl" <<'EOF'
{"type":"assistant","uuid":"a1","timestamp":"2026-01-01T00:00:00Z","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":200,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
EOF

# Happy path: one session, non-empty summary and rankings.
out="$(C4_CLAUDE_DIR="$CDIR" usage-report)" || fail "usage-report exited non-zero"
echo "$out" | grep -q "1 sessions" || fail "summary line missing session count"
echo "$out" | grep -qi "by model" || fail "model ranking missing"
echo "$out" | grep -q "claude-opus-4-8" || fail "model row missing"

# Empty path: no sessions, graceful message (still exit 0).
empty_out="$(C4_CLAUDE_DIR="$EMPTY" usage-report)" || fail "usage-report (empty) exited non-zero"
echo "$empty_out" | grep -qi "No Claude Code sessions" || fail "empty-dir message missing"

echo "PASS"
