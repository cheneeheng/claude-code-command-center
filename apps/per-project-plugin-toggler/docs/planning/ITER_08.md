---
artifact: ITER_08
status: ready
created: 2026-05-15
scope: Marketplace refresh from UI + .vsix packaging workflow
sections_changed: [02, 03, 04, 05]
sections_unchanged: [01]
---

## §01 · Concept
> Unchanged — see SKELETON.md §01

---

## §02 · Architecture

### Component diagram
> Unchanged — see ITER_06.md §02

### New API endpoint (HTML version only)

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/marketplace-refresh` | Runs `claude plugin marketplace update` as a subprocess, streams output via SSE |

All prior endpoints unchanged.

**`POST /api/marketplace-refresh` request body:** empty `{}` (no parameters — updates all known marketplaces).

**`POST /api/marketplace-refresh` response:** SSE stream, same event shape as `/api/install-stream` from ITER_07:

```
data: {"type":"line","text":"Updating ceh-plugins...\n"}\n\n
data: {"type":"line","text":"Done.\n"}\n\n
data: {"type":"done","ok":true}\n\n
```

On failure:
```
data: {"type":"done","ok":false,"error":"Exit code 1: ..."}\n\n
```

---

## §03 · Tech Stack

**New dev dependency (VSCode extension only):**
- `@vscode/vsce` — the official VSCode extension packaging tool. Install globally or as a project dev dependency:
  ```bash
  npm install --save-dev @vscode/vsce
  ```
  Used only for `vsce package` to produce the `.vsix` file. Not shipped in the extension itself.

No new runtime dependencies for either surface.

---

## §04 · Backend

### `server.py` — marketplace refresh endpoint

The subprocess command is `claude plugin marketplace update`. It updates `known_marketplaces.json` and re-fetches each marketplace's plugin list. The response is streamed line-by-line using the same pattern as `/api/install-stream` from ITER_07.

```python
elif parsed.path == "/api/marketplace-refresh":
    self.send_response(200)
    self.send_header("Content-Type", "text/event-stream")
    self.send_header("Cache-Control", "no-cache")
    self.send_header("Connection", "keep-alive")
    self.end_headers()

    def send_event(payload: dict):
        line = json.dumps(payload, ensure_ascii=False)
        self.wfile.write(f"data: {line}\n\n".encode("utf-8"))
        self.wfile.flush()

    try:
        proc = subprocess.Popen(
            ["claude", "plugin", "marketplace", "update"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=self.server.project_root,
        )
    except FileNotFoundError:
        send_event({"type": "done", "ok": False, "error": "'claude' CLI not found on PATH"})
        return

    try:
        for raw_line in iter(proc.stdout.readline, b""):
            text = raw_line.decode("utf-8", errors="replace")
            send_event({"type": "line", "text": text})
    except (BrokenPipeError, ConnectionResetError):
        proc.kill()
        proc.wait()
        return

    proc.wait()

    if proc.returncode == 0:
        send_event({"type": "done", "ok": True})
    else:
        send_event({"type": "done", "ok": False, "error": f"Exit code {proc.returncode}"})
```

> After a successful marketplace refresh, the file watcher introduced in ITER_06 will detect that `installed_plugins.json` (or related files) changed on disk and send a `refresh` SSE event to the browser, which calls `fetchPlugins()` and `fetchMarketplace()`. No explicit re-fetch is needed in the marketplace-refresh success handler — the watcher handles it. The frontend should still call `fetchMarketplace()` directly on success as a fallback in case the watcher event arrives late.

---

### `extension.js` — marketplace refresh

**`_onMessage` — new `marketplaceRefresh` case:**

```js
if (msg.type === 'marketplaceRefresh') {
  webviewView.webview.postMessage({ type: 'marketplaceRefreshStart' });
  try {
    await streamMarketplaceRefresh(projectRoot, (line) => {
      webviewView.webview.postMessage({ type: 'marketplaceRefreshLine', text: line });
    });
    this._refresh(webviewView.webview);
  } catch (err) {
    webviewView.webview.postMessage({
      type: 'marketplaceRefreshDone',
      ok: false,
      error: err.message,
    });
    this._refresh(webviewView.webview);
  }
}
```

**`streamMarketplaceRefresh(projectRoot, onLine)` — new:**

Same pattern as `streamInstall` from ITER_07, but runs `claude plugin marketplace update`:

```js
function streamMarketplaceRefresh(projectRoot, onLine) {
  return new Promise((resolve, reject) => {
    const proc = spawn('claude', ['plugin', 'marketplace', 'update'], {
      cwd: projectRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let stdoutBuf = '', stderrBuf = '';

    proc.stdout.on('data', (chunk) => {
      stdoutBuf += chunk.toString('utf8');
      const lines = stdoutBuf.split('\n');
      stdoutBuf = lines.pop();
      lines.forEach(l => onLine(l + '\n'));
    });

    proc.stderr.on('data', (chunk) => {
      stderrBuf += chunk.toString('utf8');
      const lines = stderrBuf.split('\n');
      stderrBuf = lines.pop();
      lines.forEach(l => onLine(l + '\n'));
    });

    proc.on('close', (code) => {
      if (stdoutBuf) onLine(stdoutBuf);
      if (stderrBuf) onLine(stderrBuf);
      if (code === 0) resolve();
      else reject(new Error(`Exit code ${code}`));
    });

    proc.on('error', reject);
  });
}
```

---

### `.vsix` packaging

**`vscode-extension/package.json` — required fields for packaging:**

Add the following fields. `vsce package` will error if they are missing:

```json
{
  "name": "skills-toggle",
  "displayName": "Skills Toggle",
  "description": "Manage Claude Code skill plugins per project from a VSCode sidebar.",
  "version": "0.1.0",
  "publisher": "ceh-plugins",
  "repository": {
    "type": "git",
    "url": "https://github.com/<your-org>/skills-toggle"
  },
  "license": "MIT",
  "icon": "icon.png",
  "engines": { "vscode": "^1.80.0" },
  "categories": ["Other"],
  "keywords": ["claude", "plugins", "skills", "claude code"],
  "activationEvents": [],
  "main": "./extension.js",
  "contributes": { ... }
}
```

> **`icon`:** `vsce` requires a `.png` icon (128×128px minimum). The current `icon.svg` must be exported to `icon.png`. Keep `icon.svg` as the source; add `icon.png` as the packaging artifact. Add `icon.png` to `.gitignore` if it is large; or commit it as a binary asset — either is acceptable.

> **`publisher`:** must match a publisher registered on the VS Marketplace, or any non-empty string for local `.vsix` install. For local distribution (no Marketplace publish), any value works.

**`.vscodeignore`** — controls what is excluded from the `.vsix`. Create `vscode-extension/.vscodeignore`:

```
.vscode/**
node_modules/**
**/*.ts
**/*.map
**/.gitignore
**/tsconfig.json
**/eslint*
```

> Keep `webview/styles.css` and `webview/panel.html` included (do not ignore them). Keep `icon.png` and `extension.js` included. Keep `package.json` included.

**`package.json` scripts — full set:**

```json
{
  "scripts": {
    "sync-css":    "make sync-css || powershell -ExecutionPolicy Bypass -File ../scripts/sync-css.ps1",
    "prepackage":  "npm run sync-css",
    "package":     "vsce package --out dist/skills-toggle.vsix",
    "install-ext": "code --install-extension dist/skills-toggle.vsix"
  },
  "devDependencies": {
    "@vscode/vsce": "^3.0.0"
  }
}
```

**Build and install (local):**

```bash
cd vscode-extension
npm install               # installs @vscode/vsce into node_modules
npm run package           # → dist/skills-toggle.vsix
npm run install-ext       # installs into the running VSCode instance
```

Or manually from VSCode: `Extensions` sidebar → `···` menu → `Install from VSIX…` → select `dist/skills-toggle.vsix`.

**`dist/` directory:** add `vscode-extension/dist/` to `.gitignore`. The `.vsix` is a build artifact, not source.

---

## §05 · Frontend

### Marketplace refresh — install panel UI

Add a **"↻ Refresh"** button to the install panel header, next to the "✕ Close" button. While refreshing, show a streaming log area in the panel body (same `.mp-install-log` component from ITER_07, reused at panel level).

**Updated install panel header:**

```html
<div class="install-panel-header">
  <span class="install-panel-title">Install plugin</span>
  <div style="display:flex;gap:8px;align-items:center;">
    <button class="marketplace-refresh-btn" id="marketplace-refresh-btn"
            onclick="triggerMarketplaceRefresh()">↻ Refresh</button>
    <button class="install-panel-close" onclick="closeInstallPanel()">✕ Close</button>
  </div>
</div>
<div class="mp-install-log" id="marketplace-refresh-log"></div>
```

```css
/* Add to styles.css (then run make sync-css) */
.marketplace-refresh-btn {
  font-size: 0.72rem;
  padding: 2px 8px;
  border-radius: 4px;
  border: 1px solid var(--border);
  background: transparent;
  color: var(--fg-muted);
  cursor: pointer;
}

.marketplace-refresh-btn:hover:not(:disabled) {
  border-color: var(--accent);
  color: var(--accent);
}

.marketplace-refresh-btn:disabled {
  color: var(--fg-muted);
  cursor: default;
  opacity: 0.5;
}
```

**`triggerMarketplaceRefresh()` — HTML version:**

Uses the same `fetch` + `ReadableStream` SSE parsing pattern from ITER_07's `installPlugin()`:

```js
async function triggerMarketplaceRefresh() {
  const btn    = document.getElementById('marketplace-refresh-btn');
  const logEl  = document.getElementById('marketplace-refresh-log');

  btn.disabled = true;
  btn.textContent = '↻ Refreshing…';
  logEl.textContent = '';
  logEl.classList.add('is-open');

  try {
    const res = await fetch('/api/marketplace-refresh', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });

    if (!res.ok) {
      const data = await res.json();
      throw new Error(data.error || `HTTP ${res.status}`);
    }

    const reader  = res.body.getReader();
    const decoder = new TextDecoder();
    let   buffer  = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const parts = buffer.split('\n\n');
      buffer = parts.pop();

      for (const part of parts) {
        const dataLine = part.split('\n').find(l => l.startsWith('data: '));
        if (!dataLine) continue;
        const payload = JSON.parse(dataLine.slice(6));

        if (payload.type === 'line') {
          logEl.textContent += payload.text;
          logEl.scrollTop = logEl.scrollHeight;
        } else if (payload.type === 'done') {
          if (!payload.ok) throw new Error(payload.error || 'Refresh failed');
        }
      }
    }

    logEl.classList.remove('is-open');
    // Re-fetch marketplace data to update install-status badges
    await fetchMarketplace();

  } catch (err) {
    logEl.textContent += `\nError: ${err.message}`;
  } finally {
    btn.disabled = false;
    btn.textContent = '↻ Refresh';
  }
}
```

**VSCode version — webview message handler additions:**

```js
case 'marketplaceRefreshStart': {
  const btn   = document.getElementById('marketplace-refresh-btn');
  const logEl = document.getElementById('marketplace-refresh-log');
  if (btn)   { btn.disabled = true; btn.textContent = '↻ Refreshing…'; }
  if (logEl) { logEl.textContent = ''; logEl.classList.add('is-open'); }
  break;
}
case 'marketplaceRefreshLine': {
  const logEl = document.getElementById('marketplace-refresh-log');
  if (logEl) { logEl.textContent += event.data.text; logEl.scrollTop = logEl.scrollHeight; }
  break;
}
case 'marketplaceRefreshDone': {
  const btn   = document.getElementById('marketplace-refresh-btn');
  const logEl = document.getElementById('marketplace-refresh-log');
  if (btn)   { btn.disabled = false; btn.textContent = '↻ Refresh'; }
  if (!event.data.ok && logEl) {
    logEl.textContent += `\nError: ${event.data.error}`;
  } else if (logEl) {
    logEl.classList.remove('is-open');
  }
  // _refresh() is called by the extension after streaming completes,
  // which sends a new { type: 'load' } that re-renders the install panel.
  break;
}
```

**VSCode — webview trigger:** the "↻ Refresh" button posts to the extension:

```js
function triggerMarketplaceRefresh() {
  if (typeof acquireVsCodeApi !== 'undefined') {
    vscodeApi.postMessage({ type: 'marketplaceRefresh' });
    return;
  }
  // HTML version handled by the async function body above
}
```

> In `panel.html`, `triggerMarketplaceRefresh()` only posts the message and returns immediately. All streaming output arrives via `marketplaceRefreshLine` messages. The single function handles both surfaces via the `acquireVsCodeApi` guard, same pattern as `installPlugin()` from ITER_04.

---

## Deferred

- Marketplace publish to VS Marketplace — requires a publisher PAT and `vsce publish`; out of scope for now.
- Plugin metadata (description, icon per plugin) — blocked on plugin manifest format definition.
- Cancel in-progress marketplace refresh — same as install cancel, deferred.
- File watching for `known_marketplaces.json` — deferred from ITER_06.
- Animated expand/collapse for marketplace refresh log — the log area uses the same `max-height` approach from ITER_05; no additional animation work needed.
