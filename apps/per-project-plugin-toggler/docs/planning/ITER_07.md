---
artifact: ITER_07
status: ready
created: 2026-05-15
scope: Install progress streaming — stream claude plugin install stdout/stderr line-by-line into the install panel during install
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
| `POST` | `/api/install-stream` | Replaces `POST /api/install` — runs install as subprocess, streams stdout/stderr line-by-line via SSE |

`POST /api/install` from ITER_04 is **removed** and replaced by `POST /api/install-stream`. The frontend no longer calls `/api/install`.

> **Why SSE via POST?** The browser's native `EventSource` only supports GET. Since the install request requires a POST body (`{ "id": "..." }`), we use `fetch()` with `ReadableStream` parsing on the client side. This is the correct pattern per implementation-gotchas.md §SSE.

**`POST /api/install-stream` request body:**
```json
{ "id": "ceh-dev-tools@ceh-plugins" }
```

**`POST /api/install-stream` response:**

Content-Type: `text/event-stream`. Each line of subprocess output is sent as an SSE event. Two special events signal completion:

```
data: {"type":"line","text":"Installing ceh-dev-tools@ceh-plugins...\n"}\n\n
data: {"type":"line","text":"Plugin installed successfully.\n"}\n\n
data: {"type":"done","ok":true}\n\n
```

On failure:
```
data: {"type":"line","text":"Error: repository not found\n"}\n\n
data: {"type":"done","ok":false,"error":"Exit code 1: Error: repository not found"}\n\n
```

Validation errors (bad id format, unknown marketplace) are returned as a normal `400` JSON response before the stream starts — same guards as ITER_04's `/api/install`.

---

## §03 · Tech Stack
> Unchanged — see ITER_01.md §03

`subprocess` with `stdout=PIPE, stderr=STDOUT` and `iter(proc.stdout.readline, b"")` — all stdlib, no new dependencies.

---

## §04 · Backend

### `server.py` — replace `/api/install` with `/api/install-stream`

**Remove** the `POST /api/install` handler from ITER_04.

**Add `POST /api/install-stream`:**

```python
elif parsed.path == "/api/install-stream":
    body = self._read_json_body()
    plugin_id = body.get("id", "")

    # --- Validation (same guards as ITER_04 /api/install) ---
    if "@" not in plugin_id:
        self._respond_json({"ok": False, "error": "Invalid plugin id format"}, status=400)
        return

    marketplace_key = plugin_id.split("@", 1)[1]
    known = load_known_marketplaces()
    if marketplace_key not in {m["key"] for m in known}:
        self._respond_json({"ok": False, "error": f"Unknown marketplace: {marketplace_key}"}, status=400)
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

    # --- Spawn subprocess ---
    try:
        proc = subprocess.Popen(
            ["claude", "plugin", "install", plugin_id, "--scope", "local"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,   # merge stderr into stdout
            cwd=self.server.project_root,
        )
    except FileNotFoundError:
        send_event({"type": "done", "ok": False, "error": "'claude' CLI not found on PATH"})
        return

    # --- Stream output line by line ---
    try:
        for raw_line in iter(proc.stdout.readline, b""):
            text = raw_line.decode("utf-8", errors="replace")
            send_event({"type": "line", "text": text})
    except (BrokenPipeError, ConnectionResetError):
        # Client disconnected mid-stream — kill the subprocess
        proc.kill()
        proc.wait()
        return

    proc.wait()

    if proc.returncode == 0:
        send_event({"type": "done", "ok": True})
    else:
        send_event({"type": "done", "ok": False, "error": f"Exit code {proc.returncode}"})
```

> **`stderr=subprocess.STDOUT`:** merges stderr into stdout so both streams are read from a single pipe. This avoids the deadlock risk of reading stdout and stderr on separate threads. `claude plugin install` writes its output to stderr in some versions — merging ensures nothing is missed.

> **`iter(proc.stdout.readline, b"")`:** reads one line at a time until EOF. This is the canonical stdlib pattern for streaming subprocess output. Each line is sent to the client immediately after it is read.

> **Timeout:** No explicit timeout on the subprocess in this version — the 60-second timeout from ITER_04 is dropped because the stream gives the user live feedback. If the install hangs, the user can close the panel or the tab, which triggers the `BrokenPipeError` path and kills the subprocess. A UI-side timeout can be added in a future iteration.

> **`ThreadingMixIn` required:** as noted in ITER_06, `SkillsServer` must use `ThreadingMixIn`. A streaming handler blocks its thread for the duration of the install — without threading, no other requests (including `GET /api/events` keepalives) can be served during an install. ITER_06 already mandates `ThreadingMixIn`; confirm it is in place before implementing this endpoint.

---

### `extension.js` — streaming install

Replace the `execFileAsync` call in `runInstall()` with a `spawn`-based streaming approach. Output lines are posted to the webview as they arrive so the install panel can display them.

**Updated `_onMessage` install case:**

```js
if (msg.type === 'install') {
  const { id } = msg;
  const confirmed = await vscode.window.showWarningMessage(
    `Install "${id}" locally for this project?`,
    'Install', 'Cancel'
  );
  if (confirmed !== 'Install') {
    this._refresh(webviewView.webview);
    return;
  }

  // Signal the webview to enter streaming mode for this plugin
  webviewView.webview.postMessage({ type: 'installStart', id });

  try {
    await streamInstall(id, projectRoot, (line) => {
      webviewView.webview.postMessage({ type: 'installLine', id, text: line });
    });
    // Success — full refresh re-renders plugin list and install panel
    this._refresh(webviewView.webview);
  } catch (err) {
    webviewView.webview.postMessage({ type: 'installDone', id, ok: false, error: err.message });
    this._refresh(webviewView.webview);
  }
}
```

**`streamInstall(pluginId, projectRoot, onLine)` — new:**

```js
const { spawn } = require('child_process');

function streamInstall(pluginId, projectRoot, onLine) {
  return new Promise((resolve, reject) => {
    const proc = spawn('claude', ['plugin', 'install', pluginId, '--scope', 'local'], {
      cwd: projectRoot,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    // Read stdout line by line
    let stdoutBuf = '';
    proc.stdout.on('data', (chunk) => {
      stdoutBuf += chunk.toString('utf8');
      const lines = stdoutBuf.split('\n');
      stdoutBuf = lines.pop();          // keep incomplete last line in buffer
      lines.forEach(l => onLine(l + '\n'));
    });

    // Merge stderr into the same line stream
    let stderrBuf = '';
    proc.stderr.on('data', (chunk) => {
      stderrBuf += chunk.toString('utf8');
      const lines = stderrBuf.split('\n');
      stderrBuf = lines.pop();
      lines.forEach(l => onLine(l + '\n'));
    });

    proc.on('close', (code) => {
      // Flush remaining buffer content
      if (stdoutBuf) onLine(stdoutBuf);
      if (stderrBuf) onLine(stderrBuf);
      if (code === 0) resolve();
      else reject(new Error(`Exit code ${code}`));
    });

    proc.on('error', (err) => {
      reject(err);
    });
  });
}
```

**New webview message types** handled in `panel.html`:

| Message type | Payload | Action |
|---|---|---|
| `installStart` | `{ id }` | Enter streaming mode for the row: show log area, set button to "Installing…" |
| `installLine` | `{ id, text }` | Append `text` to the log area for this plugin row |
| `installDone` | `{ id, ok, error? }` | Exit streaming mode — on ok: wait for next `load` message to re-render; on error: show error, re-enable button |

> Note: on success the extension posts `installDone` implicitly via `_refresh()` re-sending `{ type: 'load' }`. There is no explicit `installDone` success message — the `load` re-render clears the streaming state. The `installDone` message is only sent on error (see `_onMessage` catch block above).

---

## §05 · Frontend

### Install panel — streaming log area

Each `MarketplacePluginRow` gains a hidden log area that becomes visible during install.

**Updated `renderMpPluginRow(p)` — add log area:**

```js
// Inside the returned HTML string, add after .mp-install-error:
<div class="mp-install-log" id="mp-log-${CSS.escape(p.id)}"></div>
```

```css
/* Add to styles.css (then run make sync-css) */
.mp-install-log {
  display: none;
  grid-column: 1 / 3;
  margin-top: 6px;
  padding: 6px 8px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 3px;
  font-size: 0.7rem;
  font-family: monospace;
  color: var(--fg-muted);
  max-height: 120px;
  overflow-y: auto;
  white-space: pre-wrap;
  word-break: break-all;
}

.mp-install-log.is-open {
  display: block;
}
```

### HTML version — `installPlugin()` updated

Replace the ITER_04 `installPlugin()` with a `fetch`-based SSE reader using `ReadableStream`:

```js
async function installPlugin(id) {
  const btn    = document.getElementById(`mp-btn-${CSS.escape(id)}`);
  const errEl  = document.getElementById(`mp-err-${CSS.escape(id)}`);
  const logEl  = document.getElementById(`mp-log-${CSS.escape(id)}`);

  btn.textContent = 'Installing…';
  btn.disabled = true;
  errEl.textContent = '';
  errEl.classList.remove('visible');
  logEl.textContent = '';
  logEl.classList.add('is-open');

  try {
    const res = await fetch('/api/install-stream', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id }),
    });

    if (!res.ok) {
      // Validation error — plain JSON response (not a stream)
      const data = await res.json();
      throw new Error(data.error || `HTTP ${res.status}`);
    }

    // Parse the SSE stream from the response body
    const reader  = res.body.getReader();
    const decoder = new TextDecoder();
    let   buffer  = '';
    let   success = false;

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const parts = buffer.split('\n\n');
      buffer = parts.pop();   // keep incomplete last chunk

      for (const part of parts) {
        const dataLine = part.split('\n').find(l => l.startsWith('data: '));
        if (!dataLine) continue;
        const payload = JSON.parse(dataLine.slice(6));

        if (payload.type === 'line') {
          logEl.textContent += payload.text;
          logEl.scrollTop = logEl.scrollHeight;   // auto-scroll to bottom
        } else if (payload.type === 'done') {
          if (payload.ok) {
            success = true;
          } else {
            throw new Error(payload.error || 'Install failed');
          }
        }
      }
    }

    if (success) {
      logEl.classList.remove('is-open');
      await Promise.all([fetchPlugins(), fetchMarketplace()]);
    }

  } catch (err) {
    btn.textContent = 'Install ↓';
    btn.disabled = false;
    logEl.classList.remove('is-open');
    errEl.textContent = `Install failed: ${err.message}`;
    errEl.classList.add('visible');
  }
}
```

> **`ReadableStream` + SSE parsing:** `fetch()` returns the response body as a `ReadableStream`. We read chunks, accumulate them in a buffer, split on `\n\n` (SSE event delimiter), and parse each `data:` line as JSON. This is the correct pattern for POST-based SSE (see implementation-gotchas.md §SSE).

### VSCode version — webview message handler additions

In the `window.addEventListener('message', ...)` handler in `panel.html`, add cases for the new message types:

```js
case 'installStart': {
  const { id } = event.data;
  const btn   = document.getElementById(`mp-btn-${CSS.escape(id)}`);
  const logEl = document.getElementById(`mp-log-${CSS.escape(id)}`);
  if (btn) { btn.textContent = 'Installing…'; btn.disabled = true; }
  if (logEl) { logEl.textContent = ''; logEl.classList.add('is-open'); }
  break;
}
case 'installLine': {
  const { id, text } = event.data;
  const logEl = document.getElementById(`mp-log-${CSS.escape(id)}`);
  if (logEl) {
    logEl.textContent += text;
    logEl.scrollTop = logEl.scrollHeight;
  }
  break;
}
case 'installDone': {
  const { id, ok, error } = event.data;
  if (!ok) {
    const btn   = document.getElementById(`mp-btn-${CSS.escape(id)}`);
    const errEl = document.getElementById(`mp-err-${CSS.escape(id)}`);
    const logEl = document.getElementById(`mp-log-${CSS.escape(id)}`);
    if (btn)   { btn.textContent = 'Install ↓'; btn.disabled = false; }
    if (logEl) logEl.classList.remove('is-open');
    if (errEl) { errEl.textContent = `Install failed: ${error}`; errEl.classList.add('visible'); }
  }
  // On success: the subsequent { type: 'load' } message from _refresh()
  // re-renders the panel — no action needed here.
  break;
}
```

### Loading / error states

- Log area scrolls automatically to the bottom as lines arrive (`scrollTop = scrollHeight`).
- Log area is hidden on success (collapsed before the re-render from `fetchPlugins()`/`fetchMarketplace()`).
- Log area is hidden on error too — error message takes its place in the existing `.mp-install-error` element.
- If the install panel is closed while an install is in progress (user clicks "✕ Close"), the log area continues receiving lines silently — the DOM elements still exist, they're just not visible. On completion the full re-render resets the row to its final state.

---

## Deferred

- UI-side install timeout — if `claude plugin install` hangs indefinitely, the user must close the panel/tab. A configurable timeout with a "Cancel" button is deferred.
- Cancel in-progress install — killing the subprocess from the client side requires a separate `/api/install-cancel` endpoint or a process handle registry. Deferred.
- Marketplace refresh — see ITER_08.
- `.vsix` packaging — see ITER_08.
- Plugin metadata — see ITER_05 deferred.
- File watching edge cases (debounce, marketplace files) — see ITER_06 deferred.
