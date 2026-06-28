"""Local web browser for the Claude Code skills, agents, and hooks on this machine.

Reads ``<claude_dir>/plugins/installed_plugins.json``, buckets plugins by scope
(local / project / user, matched against the project root the server is launched
from), enumerates each plugin's skills (``skills/<name>/SKILL.md``), agents
(``agents/*.md``) and hooks (``hooks/hooks.json``), and serves a searchable
single-page UI. The plugin-reading logic lives in the ``claude-plugins`` library.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from claude_plugins import (
    PluginHook,
    load_installed_plugins,
    load_plugin_agents,
    load_plugin_hooks,
    load_plugin_skills,
    loose_bases,
)

HERE = Path(__file__).parent

# Skills first, then agents, then hooks within each plugin.
_KIND_ORDER = {"skill": 0, "agent": 1, "hook": 2}


@dataclass
class Member:
    """One browsable member. ``path``/``body`` are server-side only.

    For skills and agents the body is read on demand from ``path``; for hooks
    (no single source file) a rendered ``body`` is precomputed at scan time.
    ``source`` distinguishes plugin members from loose (non-plugin) ones authored
    directly under a ``.claude`` dir; ``shadowed`` marks an entry overridden by a
    higher-precedence one of the same kind+name (loose wins over plugin).
    """

    id: int
    kind: str
    scope: str
    plugin: str
    marketplace: str
    version: str
    name: str
    description: str
    path: str
    body: str
    source: str = "plugin"
    shadowed: bool = False


def _render_hook(hook: PluginHook) -> str:
    """Render a hook group to a readable detail body."""
    lines = [f"event:   {hook.event}", f"matcher: {hook.matcher or '(any)'}", "", "actions:"]
    for action in hook.actions:
        lines.append(f"  - type: {action['type']}")
        if action.get("detail"):
            lines.append(f"    {action['detail']}")
    return "\n".join(lines)


def _precedence(member: Member) -> int:
    """Rank for shadow resolution (lower wins): loose project, loose user, plugin."""
    if member.source == "loose":
        return 0 if member.scope == "project" else 1
    return 2


def _mark_shadowed(members: list[Member]) -> None:
    """Flag each member overridden by a higher-precedence kind+name (in place).

    Loose components win over plugin ones; loose project wins over loose user.
    """
    best: dict[tuple[str, str], int] = {}
    for m in members:
        key = (m.kind, m.name)
        rank = _precedence(m)
        if key not in best or rank < best[key]:
            best[key] = rank
    for m in members:
        m.shadowed = _precedence(m) > best[(m.kind, m.name)]


def load_members(project_root: Path) -> list[Member]:
    """Enumerate every skill, agent, and hook across scopes, sorted for display."""
    buckets = load_installed_plugins(project_root)
    members: list[Member] = []
    for scope in ("user", "project", "local"):
        for entry in buckets.get(scope, []):
            plugin, _, marketplace = entry["id"].partition("@")
            install_path = entry["installPath"]
            version = entry["version"]
            for skill in load_plugin_skills(install_path):
                members.append(
                    Member(0, "skill", scope, plugin, marketplace, version,
                           skill.name, skill.description, skill.path, "")
                )
            for agent in load_plugin_agents(install_path):
                members.append(
                    Member(0, "agent", scope, plugin, marketplace, version,
                           agent.name, agent.description, agent.path, "")
                )
            for hook in load_plugin_hooks(install_path):
                name = hook.event + (f" [{hook.matcher}]" if hook.matcher else "")
                desc = ", ".join(a["type"] for a in hook.actions) or "no actions"
                members.append(
                    Member(0, "hook", scope, plugin, marketplace, version,
                           name, desc, "", _render_hook(hook))
                )
    # Loose (non-plugin) skills/agents authored directly under a .claude dir.
    for scope, base in loose_bases(project_root).items():
        for skill in load_plugin_skills(base):
            members.append(
                Member(0, "skill", scope, "", "", "",
                       skill.name, skill.description, skill.path, "", source="loose")
            )
        for agent in load_plugin_agents(base):
            members.append(
                Member(0, "agent", scope, "", "", "",
                       agent.name, agent.description, agent.path, "", source="loose")
            )
    _mark_shadowed(members)
    # Loose components grouped together at the top, then plugins by name; the UI
    # groups on plugin name, so plugin is the primary key for non-loose members.
    members.sort(
        key=lambda m: (m.source != "loose", m.plugin, m.scope, _KIND_ORDER[m.kind], m.name)
    )
    for index, member in enumerate(members):
        member.id = index
    return members


class Handler(BaseHTTPRequestHandler):
    """Serves the SPA, the member index, and a single member's body by id."""

    members: list[Member] = []

    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802  (http.server's required name)
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self._send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")
        elif parsed.path == "/styles.css":
            self._send(200, (HERE / "styles.css").read_bytes(), "text/css; charset=utf-8")
        elif parsed.path in ("/app.js", "/markdown-it.min.js"):
            self._send(200, (HERE / parsed.path.lstrip("/")).read_bytes(),
                       "text/javascript; charset=utf-8")
        elif parsed.path == "/api/members":
            payload = [
                {k: v for k, v in asdict(m).items() if k not in ("path", "body")}
                for m in self.members
            ]
            self._send(200, json.dumps(payload).encode("utf-8"), "application/json")
        elif parsed.path == "/api/member":
            self._send_member_body(parse_qs(parsed.query))
        else:
            self._send(404, b"not found", "text/plain; charset=utf-8")

    def _send_member_body(self, query: dict[str, list[str]]) -> None:
        # id indexes our own scan results — no user-supplied path, so no traversal.
        try:
            mid = int(query.get("id", ["-1"])[0])
        except ValueError:
            mid = -1
        if not 0 <= mid < len(self.members):
            self._send(404, b"not found", "text/plain; charset=utf-8")
            return
        member = self.members[mid]
        if member.path:
            try:
                body = Path(member.path).read_text(encoding="utf-8")
            except OSError:
                self._send(404, b"unreadable", "text/plain; charset=utf-8")
                return
        else:
            body = member.body
        self._send(200, body.encode("utf-8"), "text/plain; charset=utf-8")

    # Any: BaseHTTPRequestHandler's signature passes through arbitrary args.
    def log_message(self, format: str, *args: Any) -> None:
        pass  # keep the console quiet


def main() -> None:
    """Entry point for the claude-component-browser server."""
    parser = argparse.ArgumentParser(prog="claude-component-browser")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=7780)
    parser.add_argument(
        "--project-dir",
        type=Path,
        default=None,
        help="Project root to resolve project-scoped components from (default: cwd).",
    )
    args = parser.parse_args()

    project_root = (args.project_dir or Path.cwd()).resolve()
    Handler.members = load_members(project_root)
    kinds = {m.kind for m in Handler.members}
    by_kind = ", ".join(f"{sum(m.kind == k for m in Handler.members)} {k}s" for k in sorted(kinds))
    print(f"  Plugin Component Browser — {len(Handler.members)} members indexed ({by_kind or 'none'})")
    print(f"  Project root: {project_root}")
    print(f"  Open: http://{args.host}:{args.port}  (Ctrl+C to stop)")
    try:
        ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
    except KeyboardInterrupt:
        print("\n  Stopped.")


if __name__ == "__main__":
    main()
