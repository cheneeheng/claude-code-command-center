---
artifact: ITER_12
status: ready
created: 2026-05-24
scope: Install/Uninstall toggle — marketplace plugin rows show a single button that switches between "Install ↓" and "Uninstall" based on installed state; uninstall streams output via the same SSE pattern as install
sections_changed: [02, 04, 05]
sections_unchanged: [01, 03]
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
| `POST` | `/api/uninstall-stream` | Runs `claude plugin uninstall <id> --scope <scope>` as a subprocess, streams stdout/stderr line-by-line via SSE |

All prior endpoints unchanged.

**`POST /api/uninstall-stream` request body:**
```json
{ "id": "ceh-dev-tools@ceh-plugins", "scope": "local" }
```

`scope` is required and must be `"local"` or `"global"`. It is provided by the frontend from the `installedScope` field that `GET /api/marketplace` already returns — no new data fetching needed.

**`POST /api/uninstall-stream` response:** SSE stream, identical event shape to `/api/install-stream`:

```
data: {"type":"line","text":"Uninstalling ceh-dev-tools@ceh-plugins...\n"}\n\n
data: {"type":"line","text":"Plugin uninstalled successfully.\n"}\n\n
data: {"type":"done","ok":true}\n\n
```

On failure:
```
data: {"type":"line","text":"Error: plugin not found\n"}\n\n
data: {"type":"done","ok":false,"error":"Exit code 1: Error: plugin not found"}\n\n
```

Validation errors (missing/invalid `id` or `scope`) are returned as a `400` JSON response before the stream starts — same guard pattern as `/api/install-stream`.

---

## §03 · Tech Stack
> Unchanged — see ITER_01.md §03

---

## §04 · Backend

### `server.py` — add `/api/uninstall-stream`

Add the following handler block after the `/api/install-stream` block. The structure is an exact mirror — same SSE scaffolding, same error handling, different CLI command and request validation.

```python
elif parsed.path == "/api/uninstall-stream":
    body = self._read_json_body()
    plugin_id = body.get("id", "")
    scope     = body.get("scope", "")

    # --- Validation ---
    if "@" not in plugin_id:
        self._respond_json({"ok": False, "error": "Invalid plugin id format"}, status=400)
        return
    if scope not in ("local", "global"):
        self._respond_json({"ok": False, "error": "scope must be 'local' or 'global'"}, status=400)
        return

    # --- Start SSE response ---
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
            ["claude", "plugin", "uninstall", plugin_id, "--scope", scope],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=self.server.project_root,
        )

        for raw_line in iter(proc.stdout.readline, b""):
            send_event({"type": "line", "text": raw_line.decode("utf-8", errors="replace")})

        proc.stdout.close()
        proc.wait()

        if proc.returncode == 0:
            send_event({"type": "done", "ok": True})
        else:
            send_event({"type": "done", "ok": False,
                        "error": f"Exit code {proc.returncode}"})

    except BrokenPipeError:
        # Client disconnected mid-stream — kill the subprocess and exit cleanly
        proc.kill()
    except Exception as e:
        try:
            send_event({"type": "done", "ok": False, "error": str(e)})
        except BrokenPipeError:
            pass
```

> **`scope` validation before stream start:** unlike install (where the marketplace key is validated against `known_marketplaces.json`), uninstall only needs `scope` to be `"local"` or `"global"`. The CLI will report its own error if the plugin is not actually installed — that error arrives as a `line` event in the stream, same as any other failure.

> **`ThreadingMixIn` requirement:** same as `/api/install-stream`. The handler blocks its thread for the subprocess duration. `ThreadingMixIn` must be present on `SkillsServer` (confirmed from ITER_06).

---

### `extension.js` — uninstall message handler and `streamUninstall()`

**`streamUninstall(pluginId, scope, projectRoot, onLine)` — new:**

Near-mirror of `streamInstall` from ITER_07, with the CLI args changed to `['plugin', 'uninstall', pluginId, '--scope', scope]`:

```js
function streamUninstall(pluginId, scope, projectRoot, onLine) {
  return new Promise((resolve, reject) => {
    const proc = spawn('claude', ['plugin', 'uninstall', pluginId, '--scope', scope], {
      cwd: projectRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let stdoutBuf = '';
    proc.stdout.on('data', (chunk) => {
      stdoutBuf += chunk.toString('utf8');
      const lines = stdoutBuf.split('\n');
      stdoutBuf = lines.pop();
      lines.forEach(l => onLine(l + '\n'));
    });

    let stderrBuf = '';
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

**Updated `_onMessage` — add `uninstall` case:**

```js
if (msg.type === 'uninstall') {
  const { id, scope } = msg;
  const confirmed = await vscode.window.showWarningMessage(
    `Uninstall "${id}" from ${scope} scope?`,
    { modal: true },
    'Uninstall'
  );
  if (confirmed !== 'Uninstall') {
    this._refresh(webviewView.webview);
    return;
  }

  webviewView.webview.postMessage({ type: 'uninstallStart', id });

  try {
    await streamUninstall(id, scope, projectRoot, (line) => {
      webviewView.webview.postMessage({ type: 'uninstallLine', id, text: line });
    });
    // Success — full refresh re-renders plugin list and marketplace panel
    this._refresh(webviewView.webview);
  } catch (err) {
    webviewView.webview.postMessage({ type: 'uninstallDone', id, ok: false, error: err.message });
    this._refresh(webviewView.webview);
  }
}
```

> **`{ modal: true }` on the warning dialog:** uninstall is more destructive than install, so forcing the user to dismiss a modal (rather than a dismissible toast) is appropriate. Install uses a non-modal warning; uninstall uses modal.

> **`scope` in the message payload:** the webview sends `{ type: 'uninstall', id, scope }` where `scope` comes from `p.installedScope` baked into the button's `onclick` at render time (see §05). The extension does not re-derive scope from disk — it trusts the value from the last marketplace fetch, which is always fresh (marketplace is re-fetched after every install/uninstall via `_refresh()`).

---

## §05 · Frontend

### Marketplace plugin row — Install/Uninstall toggle button

**Updated `renderMpPluginRow(p)` — button becomes a conditional toggle:**

Replace the three existing `btnLabel` / `btnDisabled` / `btnOnclick` constants and the `<button>` element in the returned HTML. Key changes from ITER_04:

- `btnDisabled` is **removed** — the Uninstall button must be clickable, so `disabled` is no longer set when `installed === true`.
- `btnOnclick` now calls `uninstallPlugin` for the installed state.
- `btnClass` switches the button modifier to signal destructive intent.

```js
// Replace the three existing constants:
//   const btnLabel    = installed ? 'Installed' : 'Install ↓';
//   const btnDisabled = installed ? 'disabled' : '';
//   const btnOnclick  = installed ? '' : `onclick="installPlugin('${escapeHtml(p.id)}')"`;
//
// With:
const btnLabel   = p.installed ? 'Uninstall' : 'Install ↓';
const btnOnclick = p.installed
  ? `uninstallPlugin('${escapeHtml(p.id)}','${escapeHtml(p.installedScope)}')`
  : `installPlugin('${escapeHtml(p.id)}')`;
const btnClass   = p.installed ? 'mp-install-btn mp-install-btn--uninstall' : 'mp-install-btn';

// Replace the <button> element in the returned HTML string:
`<button class="${btnClass}" id="mp-btn-${CSS.escape(p.id)}" onclick="${btnOnclick}">
  ${btnLabel}
</button>`
```

No change to the log area (`mp-install-log`) or error element (`mp-install-error`) — both are already present in the row from ITER_07 and are reused for uninstall output.

**New CSS for the Uninstall button variant** (add to `styles.css`, then run `make sync-css`):

```css
.mp-install-btn--uninstall {
  border-color: var(--error, #c0392b);
  color: var(--error, #c0392b);
}

.mp-install-btn--uninstall:hover:not(:disabled) {
  background: var(--error, #c0392b);
  color: #fff;
}
```

> The modifier `.mp-install-btn--uninstall` stacks on top of the existing `.mp-install-btn` base styles (padding, border-radius, font-size, cursor, disabled state) already defined in ITER_04 §05. No new base class is needed.

> The `--error` CSS variable is expected to already be defined in `styles.css` (used by `.mp-install-error`). The fallback `#c0392b` is a safe red for both light and dark schemes if the variable is absent.

---

### `uninstallPlugin()` — single shared function (both surfaces)

Following the same pattern as `installPlugin()` from ITER_04: one async function with a VSCode guard at the top. In `panel.html` the guard fires and returns immediately after posting the message; in `index.html` the guard is skipped and the full SSE body runs. Add this function alongside `installPlugin()` in the shared JS block.

```js
async function uninstallPlugin(id, scope) {
  const btn   = document.getElementById(`mp-btn-${CSS.escape(id)}`);
  const errEl = document.getElementById(`mp-err-${CSS.escape(id)}`);
  const logEl = document.getElementById(`mp-log-${CSS.escape(id)}`);

  btn.textContent = 'Uninstalling…';
  btn.disabled = true;
  errEl.textContent = '';
  errEl.classList.remove('visible');
  logEl.textContent = '';
  logEl.classList.add('is-open');

  // VSCode surface: delegate to extension; UI updates arrive as
  // uninstallStart / uninstallLine / uninstallDone messages.
  if (typeof acquireVsCodeApi !== 'undefined') {
    vscodeApi.postMessage({ type: 'uninstall', id, scope });
    return;
  }

  // HTML surface: stream via fetch SSE.
  try {
    const res = await fetch('/api/uninstall-stream', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, scope }),
    });

    if (!res.ok) {
      const data = await res.json();
      throw new Error(data.error || `HTTP ${res.status}`);
    }

    const reader  = res.body.getReader();
    const decoder = new TextDecoder();
    let   buffer  = '';
    let   success = false;

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
          if (payload.ok) {
            success = true;
          } else {
            throw new Error(payload.error || 'Uninstall failed');
          }
        }
      }
    }

    if (success) {
      logEl.classList.remove('is-open');
      await Promise.all([fetchPlugins(), fetchMarketplace()]);
    }

  } catch (err) {
    // Plugin is still installed — restore button immediately; row will
    // re-render correctly on the next fetchMarketplace() call.
    btn.textContent = 'Uninstall';
    btn.disabled = false;
    logEl.classList.remove('is-open');
    errEl.textContent = `Uninstall failed: ${err.message}`;
    errEl.classList.add('visible');
  }
}
```

---

### VSCode version — webview message handler additions

In the `window.addEventListener('message', ...)` handler in `panel.html`, add the three new cases alongside the existing `installStart`/`installLine`/`installDone` cases:

```js
case 'uninstallStart': {
  const { id } = event.data;
  const btn   = document.getElementById(`mp-btn-${CSS.escape(id)}`);
  const logEl = document.getElementById(`mp-log-${CSS.escape(id)}`);
  if (btn)   { btn.textContent = 'Uninstalling…'; btn.disabled = true; }
  if (logEl) { logEl.textContent = ''; logEl.classList.add('is-open'); }
  break;
}
case 'uninstallLine': {
  const { id, text } = event.data;
  const logEl = document.getElementById(`mp-log-${CSS.escape(id)}`);
  if (logEl) {
    logEl.textContent += text;
    logEl.scrollTop = logEl.scrollHeight;
  }
  break;
}
case 'uninstallDone': {
  const { id, ok, error } = event.data;
  if (!ok) {
    const btn   = document.getElementById(`mp-btn-${CSS.escape(id)}`);
    const errEl = document.getElementById(`mp-err-${CSS.escape(id)}`);
    const logEl = document.getElementById(`mp-log-${CSS.escape(id)}`);
    if (btn)   { btn.textContent = 'Uninstall'; btn.disabled = false; }
    if (logEl) logEl.classList.remove('is-open');
    if (errEl) { errEl.textContent = `Uninstall failed: ${error}`; errEl.classList.add('visible'); }
  }
  // On success: the subsequent { type: 'load' } from _refresh() re-renders the row.
  break;
}
```

---

### New webview message types — summary

| Message direction | Type | Payload | Action |
|---|---|---|---|
| extension → webview | `uninstallStart` | `{ id }` | Disable button, set label "Uninstalling…", clear + open log area |
| extension → webview | `uninstallLine` | `{ id, text }` | Append `text` to log area |
| extension → webview | `uninstallDone` | `{ id, ok, error? }` | On error: restore button to "Uninstall", re-enable, show error; on success: no-op (next `load` message re-renders) |
| webview → extension | `uninstall` | `{ id, scope }` | Show modal confirmation, then stream uninstall |

---

## Deferred

- Smoke test coverage of `POST /api/uninstall-stream` — same complexity as install-stream smoke test; deferred alongside it.
- Smoke test coverage of `GET /api/marketplace` — deferred from ITER_11.
- Smoke test coverage of `POST /api/install-stream` — deferred from ITER_11.
- Cancel in-progress uninstall — same as install cancel; deferred.
- Plugin installed in both local and global scope simultaneously — `installedScope` is a single string in the current data model. If a plugin has entries for both scopes in `installed_plugins.json`, the current loader picks one. A future iteration could show two rows or a scope picker. Deferred.
- Debounce for rapid file-watcher events — deferred from ITER_06.
- ESLint for inline HTML scripts — deferred from ITER_10.
- VS Marketplace publish — deferred from ITER_08.
- Plugin metadata — deferred from ITER_05.