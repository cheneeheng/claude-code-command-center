"""Local web browser for the Claude Code skills installed on this machine.

Reads ``<claude_dir>/plugins/installed_plugins.json``, finds each plugin's
``skills/<name>/SKILL.md``, parses the name/description frontmatter, and serves a
searchable single-page UI. Stdlib only.
"""

from __future__ import annotations

import argparse
import json
import os
from dataclasses import asdict, dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).parent


def plugins_root() -> Path:
    """Return ``<claude_dir>/plugins``, honouring the first ``$CLAUDE_DIR`` entry."""
    env = os.environ.get("CLAUDE_DIR", "")
    base = Path(env.split(os.pathsep)[0].strip()) if env else Path.home() / ".claude"
    return base / "plugins"


@dataclass
class Skill:
    """One installed skill. ``path`` is server-side only and never sent to the UI."""

    id: int
    plugin: str
    marketplace: str
    version: str
    name: str
    description: str
    path: str


def _parse_frontmatter(text: str) -> tuple[str, str]:
    """Return ``(name, description)`` from a SKILL.md's leading YAML frontmatter."""
    name = ""
    description = ""
    if not text.startswith("---"):
        return name, description
    end = text.find("\n---", 3)
    block = text[3:end] if end != -1 else ""
    for line in block.splitlines():
        key, sep, val = line.partition(":")
        if not sep:
            continue
        cleaned = val.strip().strip('"').strip("'")
        if key.strip() == "name" and not name:
            name = cleaned
        elif key.strip() == "description" and not description:
            description = cleaned
    return name, description


def load_skills() -> list[Skill]:
    """Scan installed plugins and return every skill, sorted by plugin then name."""
    root = plugins_root()
    try:
        data = json.loads((root / "installed_plugins.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []

    skills: list[Skill] = []
    for key, entries in (data.get("plugins") or {}).items():
        if not entries:
            continue
        plugin, _, marketplace = key.partition("@")
        entry = entries[0]
        for skill_md in sorted(Path(entry.get("installPath", "")).glob("skills/*/SKILL.md")):
            try:
                name, desc = _parse_frontmatter(skill_md.read_text(encoding="utf-8"))
            except OSError:
                continue
            skills.append(
                Skill(
                    id=0,
                    plugin=plugin,
                    marketplace=marketplace,
                    version=entry.get("version", ""),
                    name=name or skill_md.parent.name,
                    description=desc,
                    path=str(skill_md),
                )
            )
    skills.sort(key=lambda s: (s.plugin, s.name))
    for index, skill in enumerate(skills):
        skill.id = index
    return skills


class Handler(BaseHTTPRequestHandler):
    """Serves the SPA, the skill index, and a single skill's body by id."""

    skills: list[Skill] = []

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
        elif parsed.path == "/api/skills":
            # Strip the server-side file path before sending the list to the UI.
            payload = [
                {k: v for k, v in asdict(s).items() if k != "path"} for s in self.skills
            ]
            self._send(200, json.dumps(payload).encode("utf-8"), "application/json")
        elif parsed.path == "/api/skill":
            self._send_skill_body(parse_qs(parsed.query))
        else:
            self._send(404, b"not found", "text/plain; charset=utf-8")

    def _send_skill_body(self, query: dict[str, list[str]]) -> None:
        # id indexes our own scan results — no user-supplied path, so no traversal.
        try:
            sid = int(query.get("id", ["-1"])[0])
        except ValueError:
            sid = -1
        if not 0 <= sid < len(self.skills):
            self._send(404, b"not found", "text/plain; charset=utf-8")
            return
        try:
            body = Path(self.skills[sid].path).read_text(encoding="utf-8")
        except OSError:
            self._send(404, b"unreadable", "text/plain; charset=utf-8")
            return
        self._send(200, body.encode("utf-8"), "text/plain; charset=utf-8")

    # Any: BaseHTTPRequestHandler's signature passes through arbitrary args.
    def log_message(self, format: str, *args: Any) -> None:
        pass  # keep the console quiet


def main() -> None:
    """Entry point for the skill-browser server."""
    parser = argparse.ArgumentParser(prog="skill-browser")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=7780)
    args = parser.parse_args()

    Handler.skills = load_skills()
    print(f"  Skill Browser — {len(Handler.skills)} skills indexed")
    print(f"  Open: http://{args.host}:{args.port}  (Ctrl+C to stop)")
    try:
        ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
    except KeyboardInterrupt:
        print("\n  Stopped.")


if __name__ == "__main__":
    main()
