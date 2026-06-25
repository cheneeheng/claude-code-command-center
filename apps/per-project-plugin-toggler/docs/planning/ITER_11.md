---
artifact: ITER_11
status: ready
created: 2026-05-15
scope: CI — server smoke test (with fixture data) and cross-platform matrix for the release packaging job
sections_changed: [03, 04]
sections_unchanged: [01, 02, 05]
---

## §01 · Concept
> Unchanged — see SKELETON.md §01

---

## §02 · Architecture
> Unchanged — see ITER_06.md §02

---

## §03 · Tech Stack

No new runtime dependencies for the application itself.

**New test infrastructure (CI only):**
- `python3` / `python` — already required. Smoke test assertions use inline Python one-liners. On Windows CI runners the executable is `python`, not `python3` — see note in `smoke.ps1` section.
- Fixture files — static JSON files committed under `tests/fixtures/`. No test framework; just data files and shell scripts.

**New CI concerns:**
- `windows-latest` and `macos-latest` runners — added to the smoke test matrix in `ci.yml`.
- `windows-latest` — added to the release packaging matrix in `release.yml`.
- `tests/smoke.sh` — smoke test script for Linux/macOS.
- `tests/smoke.ps1` — smoke test script for Windows.

---

## §04 · Backend / CI

### File structure (additions only)

```
project root/
├── tests/
│   ├── fixtures/
│   │   ├── installed_plugins.json    ← fixture: one local plugin, one global plugin
│   │   └── settings.local.json      ← fixture: local plugin enabled=true
│   ├── smoke.sh                      ← smoke test (Linux/macOS)
│   └── smoke.ps1                     ← smoke test (Windows)
└── .github/
    └── workflows/
        ├── ci.yml                    ← updated: smoke-test job added
        └── release.yml               ← updated: cross-platform matrix
```

---

### Fixture files

**`tests/fixtures/installed_plugins.json`**

Minimal valid data exercising both the local and global code paths in `load_installed_plugins()`. `installPath` is left empty — `load_plugin_skills()` and `load_plugin_agents()` return `[]` for empty paths (confirmed behaviour from ITER_03 §04).

```json
{
  "smoke-local@smoke-market": [
    {
      "scope": "local",
      "projectPath": "__PROJECT_ROOT__",
      "installPath": "",
      "version": "1.0.0",
      "installedAt": "2026-01-01T00:00:00.000Z",
      "lastUpdated": "2026-01-01T00:00:00.000Z"
    }
  ],
  "smoke-global@smoke-market": [
    {
      "scope": "global",
      "installPath": "",
      "version": "2.0.0",
      "installedAt": "2026-01-01T00:00:00.000Z",
      "lastUpdated": "2026-01-01T00:00:00.000Z"
    }
  ]
}
```

> **`__PROJECT_ROOT__` placeholder:** both smoke scripts replace this token with the actual temp directory path before writing the fixture to `~/.claude/plugins/installed_plugins.json`. This avoids hardcoding absolute paths in a committed file. On Windows the replacement must also escape backslashes to produce valid JSON (see `smoke.ps1`).

**`tests/fixtures/settings.local.json`**

```json
{
  "enabledPlugins": {
    "smoke-local@smoke-market": true
  }
}
```

---

### Smoke test — `tests/smoke.sh` (Linux/macOS)

The script:
1. Prepares fixture files in the locations `server.py` expects
2. Starts `server.py` in the background
3. Polls until the server is ready (max 10s)
4. Asserts the `/api/plugins` response shape and data
5. Round-trips `POST /api/toggle` and verifies persistence
6. Cleans up on exit (server kill + fixture removal)

```bash
#!/usr/bin/env bash
set -euo pipefail

PORT=17779
PROJECT_DIR="$(mktemp -d)"
PLUGINS_DIR="$HOME/.claude/plugins"
SERVER_PID=""

cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null || true
  rm -rf "$PROJECT_DIR"
  rm -f "$PLUGINS_DIR/installed_plugins.json"
}
trap cleanup EXIT

# ── Set up fixture files ────────────────────────────────────────────

mkdir -p "$PLUGINS_DIR"
mkdir -p "$PROJECT_DIR/.claude"

# Substitute __PROJECT_ROOT__ with the actual temp dir.
# The | delimiter is safe here — mktemp paths never contain |.
sed "s|__PROJECT_ROOT__|$PROJECT_DIR|g" \
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

if [ "$READY" -eq 0 ]; then
  echo "FAIL: server did not start within 10 seconds"
  exit 1
fi

# ── Assertions ──────────────────────────────────────────────────────

RESPONSE=$(curl -sf "http://localhost:$PORT/api/plugins")

# 1. Response is valid JSON
echo "$RESPONSE" | python3 -c "import sys, json; json.load(sys.stdin)" \
  || { echo "FAIL: /api/plugins did not return valid JSON"; exit 1; }

# 2. Required top-level keys present
echo "$RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'local'        in d, 'missing key: local'
assert 'global'       in d, 'missing key: global'
assert 'project_root' in d, 'missing key: project_root'
" || { echo "FAIL: response shape incorrect"; exit 1; }

# 3. Exactly one local plugin, exactly one global plugin
echo "$RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert len(d['local'])  == 1, f'expected 1 local plugin,  got {len(d[\"local\"])}'
assert len(d['global']) == 1, f'expected 1 global plugin, got {len(d[\"global\"])}'
" || { echo "FAIL: plugin counts incorrect"; exit 1; }

# 4. Local plugin has correct id, pluginScope, and enabled state
echo "$RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
p = d['local'][0]
assert p['id']          == 'smoke-local@smoke-market', f'wrong id: {p[\"id\"]}'
assert p['pluginScope'] == 'local',                    f'wrong pluginScope: {p[\"pluginScope\"]}'
assert p['enabled']     == True,                       f'expected enabled=True, got {p[\"enabled\"]}'
" || { echo "FAIL: local plugin data incorrect"; exit 1; }

# 5. Global plugin has correct pluginScope and no 'enabled' key
echo "$RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
p = d['global'][0]
assert p['pluginScope'] == 'global', f'wrong pluginScope: {p[\"pluginScope\"]}'
assert 'enabled' not in p,           'global plugin must not have enabled key'
" || { echo "FAIL: global plugin data incorrect"; exit 1; }

# 6. POST /api/toggle — set local plugin to disabled
curl -sf -X POST "http://localhost:$PORT/api/toggle" \
  -H "Content-Type: application/json" \
  -d '{"id":"smoke-local@smoke-market","enabled":false}' \
  | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d.get('ok') == True, f'toggle response not ok: {d}'
" || { echo "FAIL: POST /api/toggle did not return ok:true"; exit 1; }

# Verify toggle was persisted (re-fetch)
RESPONSE2=$(curl -sf "http://localhost:$PORT/api/plugins")
echo "$RESPONSE2" | python3 -c "
import sys, json
d = json.load(sys.stdin)
p = d['local'][0]
assert p['enabled'] == False, f'expected enabled=False after toggle, got {p[\"enabled\"]}'
" || { echo "FAIL: toggle was not persisted"; exit 1; }

echo "OK: all smoke tests passed"
```

---

### Smoke test — `tests/smoke.ps1` (Windows)

Mirrors `smoke.sh` using PowerShell. Uses `Invoke-WebRequest` + `ConvertFrom-Json` for HTTP calls — cleaner than parsing `curl.exe` output in PowerShell.

```powershell
$ErrorActionPreference = 'Stop'
$Port = 17779
$ProjectDir = Join-Path $env:TEMP "smoke-$(Get-Random)"
$PluginsDir = Join-Path $env:USERPROFILE ".claude\plugins"
$ServerProcess = $null

function Cleanup {
  if ($null -ne $ServerProcess -and -not $ServerProcess.HasExited) {
    $ServerProcess.Kill()
    $ServerProcess.WaitForExit(3000) | Out-Null
  }
  Remove-Item -Recurse -Force $ProjectDir -ErrorAction SilentlyContinue
  Remove-Item -Force "$PluginsDir\installed_plugins.json" -ErrorAction SilentlyContinue
}

try {
  # ── Set up fixture files ──────────────────────────────────────────

  New-Item -ItemType Directory -Force -Path $PluginsDir | Out-Null
  New-Item -ItemType Directory -Force -Path "$ProjectDir\.claude" | Out-Null

  # Replace __PROJECT_ROOT__ with the actual temp dir.
  # Backslashes in the path must be doubled to produce valid JSON.
  $fixture = Get-Content tests\fixtures\installed_plugins.json -Raw
  $escapedPath = $ProjectDir.Replace('\', '\\')
  $fixture = $fixture.Replace('__PROJECT_ROOT__', $escapedPath)
  $fixture | Set-Content "$PluginsDir\installed_plugins.json" -Encoding UTF8

  Copy-Item tests\fixtures\settings.local.json "$ProjectDir\.claude\settings.local.json"

  # ── Start server ──────────────────────────────────────────────────
  # On Windows CI runners (actions/setup-python), the executable is 'python',
  # not 'python3'. Use 'python' here; the setup-python action adds it to PATH.

  $ServerProcess = Start-Process python `
    -ArgumentList "html\server.py", $Port, "`"$ProjectDir`"" `
    -PassThru -WindowStyle Hidden -WorkingDirectory (Get-Location)

  # Poll until ready (max 10s)
  $ready = $false
  for ($i = 0; $i -lt 10; $i++) {
    Start-Sleep 1
    try {
      $null = Invoke-WebRequest "http://localhost:$Port/" -UseBasicParsing -ErrorAction Stop
      $ready = $true
      break
    } catch { }
  }
  if (-not $ready) { throw "Server did not start within 10 seconds" }

  # ── Assertions ────────────────────────────────────────────────────

  $resp = Invoke-WebRequest "http://localhost:$Port/api/plugins" -UseBasicParsing
  $data = $resp.Content | ConvertFrom-Json

  # 1. Required top-level keys
  if ($null -eq $data.local)        { throw "Missing key: local" }
  if ($null -eq $data.global)       { throw "Missing key: global" }
  if ($null -eq $data.project_root) { throw "Missing key: project_root" }

  # 2. Plugin counts
  if ($data.local.Count  -ne 1) { throw "Expected 1 local plugin, got $($data.local.Count)" }
  if ($data.global.Count -ne 1) { throw "Expected 1 global plugin, got $($data.global.Count)" }

  # 3. Local plugin fields
  $lp = $data.local[0]
  if ($lp.id          -ne 'smoke-local@smoke-market') { throw "Wrong local id: $($lp.id)" }
  if ($lp.pluginScope -ne 'local')                    { throw "Wrong pluginScope: $($lp.pluginScope)" }
  if ($lp.enabled     -ne $true)                      { throw "Expected enabled=true" }

  # 4. Global plugin has pluginScope and no 'enabled' key
  $gp = $data.global[0]
  if ($gp.pluginScope -ne 'global') { throw "Wrong pluginScope: $($gp.pluginScope)" }
  if ($gp.PSObject.Properties['enabled']) { throw "Global plugin must not have enabled key" }

  # 5. POST /api/toggle round-trip
  $body = '{"id":"smoke-local@smoke-market","enabled":false}'
  $tr   = Invoke-WebRequest "http://localhost:$Port/api/toggle" `
            -Method Post -ContentType "application/json" -Body $body -UseBasicParsing
  $td   = $tr.Content | ConvertFrom-Json
  if ($td.ok -ne $true) { throw "Toggle response not ok: $($tr.Content)" }

  # 6. Verify toggle persisted
  $resp2 = Invoke-WebRequest "http://localhost:$Port/api/plugins" -UseBasicParsing
  $data2 = $resp2.Content | ConvertFrom-Json
  if ($data2.local[0].enabled -ne $false) { throw "Toggle was not persisted" }

  Write-Host "OK: all smoke tests passed"

} finally {
  Cleanup
}
```

> **`python` not `python3` on Windows:** `actions/setup-python` registers the executable as `python` on Windows runners. Using `python3` would cause a `FileNotFoundException`. The Linux/macOS script uses `python3` (standard on those platforms). This is the one deliberate asymmetry between the two scripts.

> **`-WorkingDirectory (Get-Location)`:** `Start-Process` does not inherit the caller's working directory by default on Windows. Passing it explicitly ensures `html\server.py` is resolved relative to the repo root, matching the behaviour of the bash `&` backgrounding.

> **Backslash escaping:** the `$ProjectDir.Replace('\', '\\')` call doubles backslashes before embedding the path into JSON. Without this, a path like `C:\Users\runner\AppData\Local\Temp\smoke-12345` produces invalid JSON.

---

### CI workflow — `ci.yml` smoke test job

Add the following job to `.github/workflows/ci.yml` from ITER_10. It is job 6 — append it after the `package-check` job. The full updated `ci.yml` is reproduced below for clarity.

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:

  python-syntax:
    name: Python syntax check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Check syntax
        run: python3 -m py_compile html/server.py

  css-sync:
    name: CSS sync check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Sync CSS
        run: cp html/styles.css vscode-extension/webview/styles.css
      - name: Assert no diff
        run: |
          git diff --exit-code vscode-extension/webview/styles.css || {
            echo "ERROR: vscode-extension/webview/styles.css is out of sync with html/styles.css"
            echo "Run: make sync-css"
            exit 1
          }

  lint-extension:
    name: ESLint — extension.js
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: vscode-extension/package-lock.json
      - name: Install dependencies
        working-directory: vscode-extension
        run: npm ci
      - name: Lint
        working-directory: vscode-extension
        run: npm run lint

  version-tag:
    name: Version matches release tag
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/v')
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - name: Assert package.json version matches tag
        run: |
          TAG="${GITHUB_REF_NAME#v}"
          PKG=$(node -p "require('./vscode-extension/package.json').version")
          if [ "$TAG" != "$PKG" ]; then
            echo "ERROR: tag is v${TAG} but package.json version is ${PKG}"
            exit 1
          fi
          echo "OK: tag and package.json both at ${PKG}"

  package-check:
    name: vsce package check
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: vscode-extension/package-lock.json
      - name: Install dependencies
        working-directory: vscode-extension
        run: npm ci
      - name: Sync CSS
        run: cp html/styles.css vscode-extension/webview/styles.css
      - name: Package
        working-directory: vscode-extension
        run: |
          mkdir -p dist
          npx vsce package --out dist/skills-toggle.vsix

  # ── 6. Server smoke test ───────────────────────────────────────────
  smoke-test:
    name: Smoke test (${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
      fail-fast: false   # always run all platforms; platform-specific failures must all be visible

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Run smoke test (Linux/macOS)
        if: runner.os != 'Windows'
        run: bash tests/smoke.sh

      - name: Run smoke test (Windows)
        if: runner.os == 'Windows'
        shell: pwsh
        run: ./tests/smoke.ps1
```

> **`./tests/smoke.ps1` not `pwsh tests/smoke.ps1`:** the `run:` step already executes under `shell: pwsh`. Calling `pwsh` again as a subprocess is redundant and launches a child process unnecessarily. The correct form is `./tests/smoke.ps1` (or equivalently `. tests/smoke.ps1`).

> **`fail-fast: false`:** all three platforms always run to completion. A fast-fail would hide platform-specific path normalisation failures on the remaining runners — the original motivation for adding the matrix.

> **No `working-directory` override:** both scripts reference `html/server.py` and `tests/fixtures/` with paths relative to the repo root. GitHub Actions runs steps from the repo root by default, so no override is needed.

---

### Release workflow — `release.yml` cross-platform matrix update

The `.vsix` is platform-agnostic (a zip of JS/HTML/CSS). The packaging step does not need to produce separate artifacts per platform. However, adding `windows-latest` validates that `npm ci` and `npx vsce package` work correctly on Windows — a useful sanity check given the path-separator differences in the codebase.

The `cp` command used for CSS sync in ITER_09 fails on Windows. The updated matrix uses a conditional sync step.

Full updated `release.yml`:

```yaml
name: Release — package VSCode extension

on:
  release:
    types: [released]

permissions:
  contents: write

jobs:
  package-and-upload:
    name: Build .vsix (${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest]
      fail-fast: false

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'
          cache-dependency-path: vscode-extension/package-lock.json

      - name: Install dependencies
        working-directory: vscode-extension
        run: npm ci

      - name: Sync CSS (Linux)
        if: runner.os != 'Windows'
        run: cp html/styles.css vscode-extension/webview/styles.css

      - name: Sync CSS (Windows)
        if: runner.os == 'Windows'
        shell: pwsh
        run: Copy-Item -Path html\styles.css -Destination vscode-extension\webview\styles.css -Force

      - name: Package extension
        working-directory: vscode-extension
        run: |
          mkdir -p dist
          npx vsce package --out dist/skills-toggle.vsix

      - name: Upload .vsix to release
        uses: softprops/action-gh-release@v2
        with:
          files: vscode-extension/dist/skills-toggle.vsix
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

> **`mkdir -p dist`:** needed on both platforms; on Windows, `mkdir -p` is supported by the Git Bash shell that GitHub Actions uses for default `run:` steps. Alternatively `New-Item -Force` could be used in a pwsh step, but the default shell handles it correctly.

> **macOS omitted from release matrix:** `macos-latest` runners cost 10× Linux minutes on GitHub Actions. The `.vsix` is platform-agnostic; Linux + Windows packaging coverage is sufficient. macOS is covered by the smoke test matrix.

> **Duplicate asset name:** both jobs upload `skills-toggle.vsix`. GitHub Releases replaces an existing asset when a second upload uses the same name — the Windows build overwrites the Linux build (or vice versa, depending on which finishes last). Both produce identical content so this is acceptable. If distinct filenames per platform are ever needed, use `${{ matrix.os }}` in the output path.

---

## §05 · Frontend
> Unchanged — see ITER_08.md §05

---

## Deferred

- Smoke test coverage of `GET /api/marketplace` — requires fixture data for `known_marketplaces.json` and a marketplace directory structure. Deferred until the marketplace feature stabilises.
- Smoke test coverage of `POST /api/install-stream` — requires mocking the `claude` CLI subprocess. Significant complexity; deferred.
- Debounce for rapid file-watcher events — deferred from ITER_06.
- ESLint for inline HTML scripts — deferred from ITER_10.
- VS Marketplace publish — deferred from ITER_08.
- Plugin metadata — deferred from ITER_05.
