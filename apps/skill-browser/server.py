"""Local web browser for the Claude Code skills installed on this machine.

Reads ``<claude_dir>/plugins/installed_plugins.json``, buckets plugins by scope
(local / project / user, matched against the project root the server is launched
from), finds each plugin's ``skills/<name>/SKILL.md``, and serves a searchable
single-page UI. Stdlib only.

INTENTIONAL DUPLICATION: ``normalise_path``, ``load_installed_plugins`` and
``parse_skill_frontmatter`` below are deliberately copied — not shared via a
library — across three independent surfaces (this app and the plugin-toggler's
Python server + VSCode extension). Keep their behaviour in sync.
See ``docs/shared-plugin-logic.md``.
"""

from __future__ import annotations

import argparse
import json
import os
import re
from dataclasses import asdict, dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).parent


def plugins_base() -> Path:
    """Return ``<claude_dir>/plugins``, honouring the first ``$CLAUDE_DIR`` entry."""
    env = os.environ.get("CLAUDE_DIR", "")
    base = Path(env.split(os.pathsep)[0].strip()) if env else Path.home() / ".claude"
    return base / "plugins"


# ── Shared plugin-reading logic — see docs/shared-plugin-logic.md ──────────────

def normalise_path(p: str) -> str:
    """Normalise a filesystem path for reliable cross-platform comparison."""
    if not p:
        return ""
    try:
        s = str(Path(p).resolve())
        if len(s) >= 2 and s[1] == ":":  # Windows: lowercase the drive letter
            s = s[0].lower() + s[1:]
        return s
    except Exception:
        return str(p)


def load_installed_plugins(project_root: Path) -> dict[str, list[dict[str, str]]]:
    """Bucket installed plugins by scope (local/project/user) for ``project_root``.

    local/project entries are kept only when their ``projectPath`` matches
    ``project_root``; user entries always apply. Returns empty buckets if the
    registry is missing or unreadable.
    """
    buckets: dict[str, list[dict[str, str]]] = {"local": [], "project": [], "user": []}
    installed_path = plugins_base() / "installed_plugins.json"
    try:
        raw = json.loads(installed_path.read_text(encoding="utf-8"))["plugins"]
    except (OSError, KeyError, json.JSONDecodeError):
        return buckets

    norm_project = normalise_path(str(project_root))
    for plugin_id, entries in raw.items():
        for entry in entries:
            scope = entry.get("scope")
            if scope not in buckets:
                continue
            if scope in ("local", "project"):
                entry_project = entry.get("projectPath", "")
                if not entry_project or normalise_path(entry_project) != norm_project:
                    continue  # belongs to a different project
            buckets[scope].append(
                {
                    "id": plugin_id,
                    "version": entry.get("version", ""),
                    "installPath": entry.get("installPath", ""),
                    "scope": scope,
                }
            )
    return buckets


def parse_skill_frontmatter(path: Path, fallback: str = "") -> tuple[str, str]:
    """Return ``(name, description)`` from a SKILL.md's YAML frontmatter.

    Regex-based (no PyYAML); handles both inline and block (``>-``/``|``)
    description scalars. Falls back to the skill folder name when ``name`` is
    absent.
    """
    if not fallback:
        fallback = path.parent.name
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
        m = re.match(r"^---\s*\n(.*?)\n---", text, re.DOTALL)
        if not m:
            return fallback, ""
        fm = m.group(1)
        name_match = re.search(r"^name:\s*(.+)$", fm, re.MULTILINE)
        name = name_match.group(1).strip() if name_match else fallback
        block_match = re.search(
            r"^description:\s*(?:>-|>|[|][-]?)\s*\n((?:[ \t].+\n?)*)", fm, re.MULTILINE
        )
        if block_match:
            raw = block_match.group(1)
            description = " ".join(ln.strip() for ln in raw.splitlines() if ln.strip())
        else:
            inline = re.search(r"^description:\s*(.+)$", fm, re.MULTILINE)
            description = inline.group(1).strip() if inline else ""
        return name, description
    except Exception:
        return fallback, ""


# ── Skill index (skill-browser-specific composition over the shared readers) ───

@dataclass
class Skill:
    """One installed skill. ``path`` is server-side only and never sent to the UI."""

    id: int
    scope: str
    plugin: str
    marketplace: str
    version: str
    name: str
    description: str
    path: str


def load_skills(project_root: Path) -> list[Skill]:
    """Enumerate every skill across scope buckets, sorted by scope, plugin, name."""
    buckets = load_installed_plugins(project_root)
    skills: list[Skill] = []
    for scope in ("user", "project", "local"):
        for entry in buckets.get(scope, []):
            plugin, _, marketplace = entry["id"].partition("@")
            skills_dir = Path(entry["installPath"]) / "skills" if entry["installPath"] else None
            if skills_dir is None or not skills_dir.is_dir():
                continue
            for folder in sorted(skills_dir.iterdir()):
                skill_md = folder / "SKILL.md"
                if not skill_md.is_file():
                    continue
                name, desc = parse_skill_frontmatter(skill_md)
                skills.append(
                    Skill(0, scope, plugin, marketplace, entry["version"], name, desc, str(skill_md))
                )
    skills.sort(key=lambda s: (s.scope, s.plugin, s.name))
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

    project_root = Path.cwd()
    Handler.skills = load_skills(project_root)
    scopes = sorted({s.scope for s in Handler.skills})
    print(f"  Skill Browser — {len(Handler.skills)} skills indexed (scopes: {', '.join(scopes) or 'none'})")
    print(f"  Project root: {project_root}")
    print(f"  Open: http://{args.host}:{args.port}  (Ctrl+C to stop)")
    try:
        ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
    except KeyboardInterrupt:
        print("\n  Stopped.")


if __name__ == "__main__":
    main()
