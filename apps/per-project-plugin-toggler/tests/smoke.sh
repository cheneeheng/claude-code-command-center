#!/usr/bin/env bash
set -euo pipefail

# Smoke tests for html/server.py (three-scope plugin model: local / project / user).
#
# Covered:
#   - /api/plugins shape, three-scope bucketing, cross-project exclusion,
#     row fields, enabled defaults, installedScopes map, mock fallback
#   - /api/toggle happy path (local + project persistence) and all 400 validations
#   - /api/marketplace shape
#   - /api/set-project validation
# Not covered (shell out to the real `claude` CLI, non-deterministic in CI):
#   - /api/install-stream, /api/uninstall-stream, /api/marketplace-refresh
# User-scope toggle writes ~/.claude/settings.json (the real user file), so we
# verify user-scope *reads* only and never POST a user-scope toggle here.

PORT=17779
PROJECT_DIR="$(mktemp -d)"
OTHER_DIR="${PROJECT_DIR}-other"   # a different project root; its plugin must be excluded
PLUGINS_DIR="$HOME/.claude/plugins"
SERVER_PID=""

cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "$PROJECT_DIR"
  rm -f "$PLUGINS_DIR/installed_plugins.json"
}
trap cleanup EXIT

fail() { echo "FAIL: $1"; exit 1; }

# Assert that a POST returns a given HTTP status. Args: desc, status, json-body
assert_post_status() {
  local desc="$1" want="$2" body="$3"
  local got
  got=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "http://localhost:$PORT/api/toggle" \
        -H "Content-Type: application/json" -d "$body")
  [ "$got" = "$want" ] || fail "$desc: expected HTTP $want, got $got"
}

# ── Set up fixture files ────────────────────────────────────────────

mkdir -p "$PLUGINS_DIR"
mkdir -p "$PROJECT_DIR/.claude"

# Substitute the project-root placeholders with real temp dirs.
# The | delimiter is safe — mktemp paths never contain |.
sed -e "s|__PROJECT_ROOT__|$PROJECT_DIR|g" \
    -e "s|__OTHER_ROOT__|$OTHER_DIR|g" \
  tests/fixtures/installed_plugins.json > "$PLUGINS_DIR/installed_plugins.json"

cp tests/fixtures/settings.local.json "$PROJECT_DIR/.claude/settings.local.json"

# ── Start server ────────────────────────────────────────────────────

python3 html/server.py "$PORT" "$PROJECT_DIR" &
SERVER_PID=$!

# Poll until ready (max 10s)
READY=0
for i in $(seq 1 10); do
  sleep 1
  if curl -sf "http://localhost:$PORT/" > /dev/null 2>&1; then
    READY=1
    break
  fi
done
[ "$READY" -eq 1 ] || fail "server did not start within 10 seconds"

# ── /api/plugins ────────────────────────────────────────────────────

RESPONSE=$(curl -sf "http://localhost:$PORT/api/plugins")

# 1. Valid JSON
echo "$RESPONSE" | python3 -c "import sys, json; json.load(sys.stdin)" \
  || fail "/api/plugins did not return valid JSON"

# 2. Shape, three-scope bucketing, cross-project exclusion, row fields, defaults
echo "$RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)

for k in ('local', 'project', 'user', 'installedScopes', 'project_root'):
    assert k in d, f'missing key: {k}'
assert 'mock' not in d, 'unexpected mock flag with fixture present'

# local + project read temp settings we control → exact. user reads the real
# ~/.claude/settings.json (server design), so assert containment there.
assert [p['id'] for p in d['local']]   == ['smoke-local@smoke-market'],   d['local']
assert [p['id'] for p in d['project']] == ['smoke-project@smoke-market'], d['project']
user_ids = [p['id'] for p in d['user']]
assert 'smoke-user@smoke-market' in user_ids, user_ids
all_ids = [p['id'] for s in ('local','project','user') for p in d[s]]
assert 'smoke-other@smoke-market' not in all_ids, 'cross-project plugin not excluded'

# Local row: full field shape + values from settings.local.json
lp = d['local'][0]
for f in ('id','name','marketplace','version','scope','enabled','installed','skills','agents','hooks'):
    assert f in lp, f'local row missing field: {f}'
assert lp['name']        == 'smoke-local',  lp['name']
assert lp['marketplace'] == 'smoke-market', lp['marketplace']
assert lp['scope']       == 'local',        lp['scope']
assert lp['version']     == '1.0.0',        lp['version']
assert lp['enabled']     is True,           lp['enabled']
assert lp['installed']   is True,           lp['installed']
assert lp['skills'] == [] and lp['agents'] == [] and lp['hooks'] == []

# Project + user rows: enabled defaults to True (no settings entries for them)
assert d['project'][0]['scope'] == 'project'
assert d['project'][0]['enabled'] is True, 'project enabled should default True'
su = next(p for p in d['user'] if p['id'] == 'smoke-user@smoke-market')
assert su['scope'] == 'user'
assert su['enabled'] is True, 'user enabled should default True'

# installedScopes map
assert d['installedScopes'].get('smoke-local@smoke-market')   == ['local']
assert d['installedScopes'].get('smoke-project@smoke-market') == ['project']
assert d['installedScopes'].get('smoke-user@smoke-market')    == ['user']
assert 'smoke-other@smoke-market' not in d['installedScopes']
" || fail "/api/plugins shape/bucketing incorrect"

# ── /api/marketplace ────────────────────────────────────────────────

curl -sf "http://localhost:$PORT/api/marketplace" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'marketplaces' in d, 'missing marketplaces key'
assert isinstance(d['marketplaces'], list), 'marketplaces must be a list'
" || fail "/api/marketplace shape incorrect"

# ── /api/toggle happy paths ─────────────────────────────────────────

# 3. Toggle local plugin off, verify persisted
curl -sf -X POST "http://localhost:$PORT/api/toggle" \
  -H "Content-Type: application/json" \
  -d '{"id":"smoke-local@smoke-market","enabled":false,"scope":"local"}' \
  | python3 -c "import sys, json; assert json.load(sys.stdin).get('ok') is True" \
  || fail "POST /api/toggle (local) did not return ok:true"

# 4. Toggle project plugin off (creates <project>/.claude/settings.json), verify persisted
curl -sf -X POST "http://localhost:$PORT/api/toggle" \
  -H "Content-Type: application/json" \
  -d '{"id":"smoke-project@smoke-market","enabled":false,"scope":"project"}' \
  | python3 -c "import sys, json; assert json.load(sys.stdin).get('ok') is True" \
  || fail "POST /api/toggle (project) did not return ok:true"

curl -sf "http://localhost:$PORT/api/plugins" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['local'][0]['enabled']   is False, 'local toggle not persisted'
assert d['project'][0]['enabled'] is False, 'project toggle not persisted'
" || fail "toggles were not persisted"

# ── /api/toggle validation (all expect HTTP 400) ────────────────────

assert_post_status "invalid id (no @)"      400 '{"id":"noatsign","enabled":true,"scope":"local"}'
assert_post_status "missing scope"          400 '{"id":"smoke-local@smoke-market","enabled":true}'
assert_post_status "invalid scope"          400 '{"id":"smoke-local@smoke-market","enabled":true,"scope":"global"}'
assert_post_status "non-bool enabled"       400 '{"id":"smoke-local@smoke-market","enabled":"yes","scope":"local"}'
assert_post_status "id not in given scope"  400 '{"id":"smoke-user@smoke-market","enabled":true,"scope":"local"}'

# ── /api/set-project validation ─────────────────────────────────────

assert_set_project_status() {
  local got
  got=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "http://localhost:$PORT/api/set-project" \
        -H "Content-Type: application/json" -d "$1")
  [ "$got" = "$2" ] || fail "set-project ($1): expected HTTP $2, got $got"
}
assert_set_project_status '{"path":"/no/such/dir/smoke-xyz"}' 400

# ── mock fallback (run last: removes the installed_plugins.json fixture) ──

rm -f "$PLUGINS_DIR/installed_plugins.json"
curl -sf "http://localhost:$PORT/api/plugins" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d.get('mock') is True, 'expected mock:true when installed_plugins.json is missing'
# build_sections unions mock-installed with settings, so use containment.
assert 'ceh-dev-tools@ceh-plugins'  in [p['id'] for p in d['local']], d['local']
assert 'frontend-design@anthropic' in [p['id'] for p in d['user']],  d['user']
" || fail "mock fallback incorrect"

echo "OK: all smoke tests passed"
