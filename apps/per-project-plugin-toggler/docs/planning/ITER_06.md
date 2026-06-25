---
artifact: ITER_06
status: ready
created: 2026-05-15
scope: File watching — auto-refresh both surfaces when settings.local.json or installed_plugins.json changes on disk
sections_changed: [02, 04, 05]
sections_unchanged: [01, 03]
---

## §01 · Concept
> Unchanged — see SKELETON.md §01

---

## §02 · Architecture

### Component diagram (updated)

```
~/.claude/plugins/installed_plugins.json   (read + watched)
~/.claude/plugins/known_marketplaces.json  (read only)
        │
        ▼
  [ Plugin loader + File watcher ]
        │
        ├──▶ [ HTML version ]
        │       server.py ◀──▶ index.html
        │       GET /api/events  ← new SSE endpoint
        │
        └──▶ [ VSCode version ]
                extension.js ◀──▶ panel.html
                FileSystemWatcher ← new
                        │
                        ▼
        ./.claude/settings.local.json      (read + write + watched)
```

### New API endpoint (HTML version only)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/events` | SSE stream — sends `data: refresh\n\n` when a watched file changes |

All prior endpoints unchanged.

**`GET /api/events` behaviour:**
- Response headers: `Content-Type: text/event-stream`, `Cache-Control: no-cache`, `Connection: keep-alive`
- On connect: immediately sends `data: connected\n\n` (lets the client confirm the stream is live)
- On file change: sends `data: refresh\n\n`
- On disconnect (client closes tab/navigates): server cleans up the connection from its subscriber list
- No auth, localhost only (same policy as all other endpoints)
- Multiple browser tabs may connect simultaneously — each gets its own SSE connection, all receive the refresh event

### What is watched

| File | Who watches | Surfaces affected |
|------|------------|-------------------|
| `./.claude/settings.local.json` | server.py (HTML), extension.js (VSCode) | Both — plugin enabled state |
| `~/.claude/plugins/installed_plugins.json` | server.py (HTML), extension.js (VSCode) | Both — plugin list |

`known_marketplaces.json` and individual `marketplace.json` files are not watched in this iteration — marketplace data is less likely to change mid-session. Deferred.

---

## §03 · Tech Stack
> Unchanged — see ITER_01.md §03

No new dependencies. File watching uses:
- **Python:** `threading.Timer` polling loop (stdlib). `watchdog` is not used — it requires a pip install, which violates the stdlib-only constraint from SKELETON §03.
- **Node.js/VSCode:** `vscode.workspace.createFileSystemWatcher` (VSCode Extension API, already available).

---

## §04 · Backend

### `server.py` — file watcher + SSE

**Strategy: polling with `threading.Timer`**

Poll both watched files every 1 second. On each tick, compare the file's `mtime` (modification time) to the previously recorded value. If it changed, broadcast a refresh event to all connected SSE clients.

> **Why polling, not `inotify`/`kqueue`?** The stdlib-only constraint rules out `watchdog`. Python's `os.stat()` polling at 1-second intervals is sufficient for this use case — the UI does not need sub-second refresh latency.

**New module-level state (on the `HTTPServer` subclass):**

```python
class SkillsServer(HTTPServer):
    def __init__(self, *args, project_root, **kwargs):
        super().__init__(*args, **kwargs)
        self.project_root = project_root
        self.sse_clients = []          # list of queue.Queue, one per connected client
        self.sse_clients_lock = threading.Lock()
        self._watch_mtimes = {}        # { filepath_str: float mtime }
        self._start_watcher()

    def _watched_paths(self):
        return [
            pathlib.Path.home() / ".claude" / "plugins" / "installed_plugins.json",
            pathlib.Path(self.project_root) / ".claude" / "settings.local.json",
        ]

    def _start_watcher(self):
        # Record initial mtimes
        for p in self._watched_paths():
            self._watch_mtimes[str(p)] = p.stat().st_mtime if p.exists() else None
        self._schedule_watch()

    def _schedule_watch(self):
        t = threading.Timer(1.0, self._poll)
        t.daemon = True   # dies with the server process
        t.start()

    def _poll(self):
        changed = False
        for p in self._watched_paths():
            key = str(p)
            try:
                mtime = p.stat().st_mtime if p.exists() else None
            except OSError:
                mtime = None
            if mtime != self._watch_mtimes.get(key):
                self._watch_mtimes[key] = mtime
                changed = True
        if changed:
            self._broadcast_refresh()
        self._schedule_watch()   # re-arm

    def _broadcast_refresh(self):
        with self.sse_clients_lock:
            dead = []
            for q in self.sse_clients:
                try:
                    q.put_nowait("refresh")
                except Exception:
                    dead.append(q)
            for q in dead:
                self.sse_clients.remove(q)

    def add_sse_client(self, q):
        with self.sse_clients_lock:
            self.sse_clients.append(q)

    def remove_sse_client(self, q):
        with self.sse_clients_lock:
            if q in self.sse_clients:
                self.sse_clients.remove(q)
```

> **Thread safety:** `sse_clients` is a plain list protected by `threading.Lock`. The polling timer runs on a daemon thread. `queue.Queue` is thread-safe; `put_nowait` from the watcher thread, `get` from the handler thread.

**New handler: `GET /api/events`**

```python
# Inside RequestHandler.do_GET:
elif parsed.path == "/api/events":
    import queue
    q = queue.Queue()
    self.server.add_sse_client(q)

    self.send_response(200)
    self.send_header("Content-Type", "text/event-stream")
    self.send_header("Cache-Control", "no-cache")
    self.send_header("Connection", "keep-alive")
    self.end_headers()

    try:
        # Send initial connected confirmation
        self.wfile.write(b"data: connected\n\n")
        self.wfile.flush()

        while True:
            try:
                msg = q.get(timeout=15)    # 15s timeout doubles as keepalive
                self.wfile.write(f"data: {msg}\n\n".encode())
                self.wfile.flush()
            except queue.Empty:
                # Send SSE comment as keepalive to prevent proxy/browser timeouts
                self.wfile.write(b": keepalive\n\n")
                self.wfile.flush()
    except (BrokenPipeError, ConnectionResetError):
        pass    # client disconnected
    finally:
        self.server.remove_sse_client(q)
```

> **Blocking handler caveat:** `BaseHTTPRequestHandler` handles one request per thread by default (`ThreadingMixIn` must be used). Ensure `SkillsServer` uses `ThreadingMixIn` — if it doesn't already, add it:
> ```python
> from http.server import HTTPServer
> from socketserver import ThreadingMixIn
>
> class SkillsServer(ThreadingMixIn, HTTPServer):
>     daemon_threads = True
>     ...
> ```
> Without `ThreadingMixIn`, a long-lived SSE connection would block all other requests.

**`project_root` change handling:** when `POST /api/set-project` succeeds and `self.server.project_root` is updated, also reset the watcher's `_watch_mtimes` for the old `settings.local.json` path and add the new one:

```python
# In POST /api/set-project, after updating self.server.project_root:
# Re-seed the watcher so it picks up the new project's settings file
self.server._watch_mtimes = {}   # reset; _poll will re-seed on next tick
```

---

### `extension.js` — file watching

**Use `vscode.workspace.createFileSystemWatcher`:**

```js
// Inside SkillsViewProvider.resolveWebviewView(), after calling this._refresh():

const settingsPattern = new vscode.RelativePattern(
  vscode.workspace.workspaceFolders[0],
  '.claude/settings.local.json'
);
const installedPath = path.join(os.homedir(), '.claude', 'plugins', 'installed_plugins.json');

// Watch project-local settings
const settingsWatcher = vscode.workspace.createFileSystemWatcher(settingsPattern);
// Watch global installed_plugins.json via an absolute path glob
const installedWatcher = vscode.workspace.createFileSystemWatcher(installedPath);

const onchange = () => this._refresh(webviewView.webview);

settingsWatcher.onDidChange(onchange);
settingsWatcher.onDidCreate(onchange);
settingsWatcher.onDidDelete(onchange);

installedWatcher.onDidChange(onchange);
installedWatcher.onDidCreate(onchange);
installedWatcher.onDidDelete(onchange);

// Register watchers for disposal when the extension is deactivated
context.subscriptions.push(settingsWatcher, installedWatcher);
```

> **`context` availability:** `resolveWebviewView` does not receive `context` directly. Pass it into `SkillsViewProvider`'s constructor and store as `this._context`. The `activate` function already has `context` and passes it to the provider constructor.

> **`vscode.RelativePattern` for settings.local.json:** Using a workspace-relative pattern ensures VSCode watches the correct project directory. `installedPath` is an absolute path string — `createFileSystemWatcher` accepts both glob strings and `RelativePattern` objects.

> **Debounce:** `_refresh()` reads files synchronously. If the watcher fires multiple times in quick succession (e.g. an editor that writes a temp file then renames), each event triggers a separate refresh. This is acceptable — refreshes are cheap. A debounce timer can be added in a future iteration if it proves noisy.

---

## §05 · Frontend

### HTML version — SSE client

Add to `index.html` inline script, called once on page load after the initial `fetchPlugins()`:

```js
function connectEventStream() {
  const es = new EventSource('/api/events');

  es.onmessage = (event) => {
    if (event.data === 'refresh') {
      fetchPlugins();
      if (installPanelOpen) fetchMarketplace();
    }
    // 'connected' message is silently ignored
  };

  es.onerror = () => {
    // EventSource auto-reconnects on error. Close and reopen after a short
    // delay to avoid a tight reconnect loop if the server is restarting.
    es.close();
    setTimeout(connectEventStream, 3000);
  };
}

// Call after initial page load
connectEventStream();
```

> **`EventSource` reconnect behaviour:** browsers automatically reconnect `EventSource` on network error. The `onerror` handler closes and reopens with a 3-second delay to avoid hammering a restarting server. If the server is stopped entirely, the 3-second retry loop continues until the user closes the tab — this is acceptable for a localhost dev tool.

> **No auth headers needed:** `EventSource` is a GET request to localhost with no auth. No `fetch()`-with-`ReadableStream` workaround is required here (that pattern is only needed when custom headers are required — see implementation-gotchas.md §SSE).

### UI indicator (optional but recommended)

Show a small "Live" dot in the header when the SSE connection is established, and a "Reconnecting…" label when it's in the error/retry state. This makes it clear to the user that the UI will auto-refresh.

```html
<!-- In the header area -->
<span id="live-indicator" class="live-dot" title="Live updates active"></span>
```

```css
.live-dot {
  display: inline-block;
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #3a8a3a;
  margin-left: 8px;
  vertical-align: middle;
  opacity: 0;
  transition: opacity 200ms;
}

.live-dot.connected {
  opacity: 1;
}

.live-dot.reconnecting {
  background: #cc8800;
  opacity: 1;
}
```

```js
function setLiveIndicator(state) {  // state: 'connected' | 'reconnecting' | 'off'
  const el = document.getElementById('live-indicator');
  el.className = 'live-dot' + (state !== 'off' ? ` ${state}` : '');
}

// In connectEventStream():
// es.onopen → setLiveIndicator('connected')
// es.onerror → setLiveIndicator('reconnecting'), then after setTimeout → setLiveIndicator('off') briefly
```

### VSCode version

No frontend changes required. `_refresh(webview)` already posts a full `{ type: 'load' }` message when called by the file watcher. The webview re-renders from that message — same code path as the initial load.

---

## Deferred

- Watching `known_marketplaces.json` and marketplace plugin files — deferred; these change rarely.
- Debounce for rapid successive file-change events — not needed yet; refreshes are cheap.
- SSE reconnect indicator in VSCode webview — the VSCode surface has no equivalent of the live dot; the watcher fires silently and refreshes are invisible to the user (correct behaviour for a sidebar).
- Plugin metadata — see ITER_05 deferred.
- `.vsix` packaging — see ITER_08.
- Install progress streaming — see ITER_07.
- Marketplace refresh — see ITER_08.
