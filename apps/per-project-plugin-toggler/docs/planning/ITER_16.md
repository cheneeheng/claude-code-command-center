---
artifact: ITER_16
status: ready
created: 2026-06-06
scope: Show each installed plugin's hooks alongside its skills and agents — read hooks/hooks.json from the plugin's installPath, normalize it into (event, matcher, actions) rows, and render as read-only structured text in a disclosure.
sections_changed: [02, 04, 05]
sections_unchanged: [01, 03]
depends_on: [SKELETON, ITER_01, ITER_02, ITER_03, ITER_04, ITER_05, ITER_06, ITER_07, ITER_08, ITER_09, ITER_10, ITER_11, ITER_12, ITER_13, ITER_14, ITER_15]
---

# ITER_16 · Hooks display (item 7)

> Hooks are read and rendered as a third component type next to skills and agents (ITER_02 / ITER_03). The JSON is normalized into structured text rather than summarized — a faithful, scannable transform that keeps the events and commands and drops the JSON scaffolding.

## §01 · Concept
> Unchanged — see ITER_13 § 01.

---

## §02 · Architecture

### Where hooks come from

`<installPath>/hooks/hooks.json` — the per-plugin hooks config, in the plugin root, parallel to `skills/` and `agents/` (ITER_03 §02). Confirmed against the Claude Code plugins reference. Like skills/agents, hooks are only available for **installed** rows (`installed: true`); `installed: false` rows get an empty `hooks: []`.

`hooks.json` structure:

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|clear|compact",
        "hooks": [ { "type": "command", "command": "node \"${CLAUDE_PLUGIN_ROOT}/hooks/load-contract.js\"" } ] }
    ]
  }
}
```

Top-level `hooks` object keyed by **event name**; each event maps to an array of **matcher-groups**; each group has an optional `matcher` and a `hooks` array of **actions**; each action has a `type` (`command` | `http` | `mcp_tool` | `prompt` | `agent`) plus type-specific fields.

### Data model

New entity **Hook** — a normalized matcher-group, ready to render:

- `event` — string, the lifecycle event (e.g. `SessionStart`, `PostToolUse`)
- `matcher` — string, may be `""` (some events have no matcher)
- `actions` — array of `{ "type": string, "detail": string }`, one per action in the group

New field on the plugin row (next to `skills`, `agents` from ITER_13 §02):

- `hooks` — `Hook[]`, may be empty

`GET /api/plugins` response gains `hooks` on each row; shape otherwise unchanged from ITER_13 §02.

---

## §03 · Tech Stack
> Unchanged — see SKELETON § 03.

---

## §04 · Backend

### HTML version — `server.py`

**New helper `load_plugin_hooks(install_path)`** — mirror of `load_plugin_skills` / `load_plugin_agents` (ITER_03 §04), reading one JSON file instead of a directory of `.md` files:

```python
def load_plugin_hooks(install_path):
    """Reads <install_path>/hooks/hooks.json.
    Returns [] if missing/unparseable. Each item:
      { "event": str, "matcher": str, "actions": [ { "type": str, "detail": str } ] }"""
    if not install_path:
        return []
    path = pathlib.Path(install_path) / "hooks" / "hooks.json"
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, OSError):
        return []
    result = []
    for event, groups in (data.get("hooks") or {}).items():
        for group in groups or []:
            actions = [
                {"type": h.get("type", ""), "detail": _hook_detail(h)}
                for h in group.get("hooks", [])
            ]
            result.append({"event": event, "matcher": group.get("matcher", ""), "actions": actions})
    return result

def _hook_detail(h):
    # 'command' is the common case (and the documented example); render its command string.
    if h.get("type") == "command":
        return h.get("command", "")
    # http / mcp_tool / prompt / agent: field names vary — show a compact dump of the
    # non-type fields rather than inventing key names. Refine when real examples appear.
    return json.dumps({k: v for k, v in h.items() if k != "type"}, ensure_ascii=False)
```

**Wire into `build_sections`** (ITER_13 §04) alongside skills/agents:

```python
"hooks":  load_plugin_hooks(install_path) if installed else [],
```

> **Plugin manifest fallback (deferred).** Hooks can also be declared inline under a `hooks` key in `plugin.json`. This iteration reads only `hooks/hooks.json` (the common form, and the user's example). Reading the inline `plugin.json` variant is a deferred secondary source — see Deferred.

### VSCode extension — `extension.js`

Add `loadPluginHooks(installPath)` mirroring the Python helper (read `path.join(installPath, 'hooks', 'hooks.json')`, same normalization and the same `_hookDetail` fallback), and include `hooks` in each row in `buildSections` (ITER_13 §04), exactly as skills/agents are.

---

## §05 · Frontend

### Hooks disclosure (parallel to skills / agents)

Add a third collapsible disclosure on each installed plugin row, after Agents, labelled **Hooks** with a count (hidden when `hooks` is empty, same as the skills/agents disclosures from ITER_02/ITER_03 §05). Inside, render the normalized rows as read-only **structured text**, grouped by event:

```
SessionStart   matcher: startup|clear|compact
  • command — node "${CLAUDE_PLUGIN_ROOT}/hooks/load-contract.js"

PostToolUse    matcher: Write|Edit
  • command — "${CLAUDE_PLUGIN_ROOT}"/scripts/format-code.sh
```

Rendering rules:

- One block per `Hook` entry: the `event` as a heading, and `matcher` shown as `matcher: <value>` only when non-empty.
- Under it, one line per action: `<type> — <detail>`.
- `detail` is plain text; escape it (`escapeHtml`) — hook commands contain `"`, `$`, `{}`, etc. Use a monospace style for the detail so paths/commands read cleanly.
- Empty `hooks` → the disclosure is not rendered (matches skills/agents behaviour).

No interactivity — hooks are display-only this iteration (mirroring skills/agents).

---

## Deferred

- **Inline hooks in `plugin.json`** — read the `hooks` key from the plugin manifest as a secondary source when `hooks/hooks.json` is absent. Deferred; most plugins use `hooks/hooks.json`.
- **Richer detail for non-`command` hook types** (`http`, `mcp_tool`, `prompt`, `agent`) — currently shown as a compact field dump; give each a tailored one-line rendering once real examples are available.
- **Other plugin components** surfaced by the plugins reference (MCP servers, LSP servers, monitors, themes) — out of scope; only hooks were requested.
- **Smoke-test fixture** with a `hooks/hooks.json` (extends ITER_11) — recommended follow-up.
