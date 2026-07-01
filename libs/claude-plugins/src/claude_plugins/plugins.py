"""Read Claude Code's installed-plugins registry, bucketed by scope.

Models one external contract: ``<claude_dir>/plugins/installed_plugins.json``,
the file Claude Code writes to record which plugins are installed at which scope.
"""

from __future__ import annotations

import json
from pathlib import Path

__all__ = [
    "claude_dir",
    "load_installed_plugins",
    "loose_bases",
    "normalise_path",
    "plugins_base",
]


def claude_dir() -> Path:
    """Return the default Claude config dir, ``~/.claude``.

    Returns:
        The Claude config directory path.
    """
    return Path.home() / ".claude"


def plugins_base(claude_dir: Path | None = None) -> Path:
    """Return ``<claude_dir>/plugins``.

    Args:
        claude_dir: Explicit Claude config dir. Defaults to ``~/.claude``.

    Returns:
        The plugins directory path.
    """
    base = claude_dir if claude_dir is not None else Path.home() / ".claude"
    return base / "plugins"


def loose_bases(project_root: Path, claude_dir: Path | None = None) -> dict[str, str]:
    """Map scope to the ``.claude`` base dir holding loose (non-plugin) components.

    Loose skills and agents live under ``<base>/skills/<name>/SKILL.md`` and
    ``<base>/agents/<name>.md`` — the same on-disk layout as a plugin, so the
    plugin member readers accept these bases directly. Loose components exist
    only at user and project scope; ``local`` is a plugin/settings concept with
    no loose equivalent on disk.

    Args:
        project_root: The project directory whose ``.claude`` dir holds
            project-scope loose components.
        claude_dir: Explicit Claude config dir for the user-scope base. Defaults
            to ``~/.claude``.

    Returns:
        ``{"user": <claude_dir>, "project": <project_root>/.claude}``.
    """
    base = claude_dir if claude_dir is not None else Path.home() / ".claude"
    return {
        "user": str(base),
        "project": str(Path(project_root) / ".claude"),
    }


def normalise_path(p: str) -> str:
    """Normalise a filesystem path for reliable cross-platform comparison.

    Resolves symlinks and relative segments, and on Windows lower-cases the drive
    letter so ``C:\\...`` and ``c:\\...`` compare equal.

    Args:
        p: The path to normalise.

    Returns:
        The normalised path, the empty string for empty input, or the original
        string unchanged if resolution fails.
    """
    if not p:
        return ""
    try:
        s = str(Path(p).resolve())
        if len(s) >= 2 and s[1] == ":":  # Windows: lower-case the drive letter
            s = s[0].lower() + s[1:]
        return s
    except OSError:
        return str(p)


def load_installed_plugins(
    project_root: Path, claude_dir: Path | None = None
) -> dict[str, list[dict[str, str]]]:
    """Bucket installed plugins by scope (local/project/user) for ``project_root``.

    Reads ``<plugins_base>/installed_plugins.json`` (schema
    ``{"version": ..., "plugins": {id: [entries]}}``, each entry carrying a
    ``scope``, optional ``projectPath``, ``installPath`` and ``version``).
    ``local``/``project`` entries are kept only when their ``projectPath``
    matches ``project_root``; ``user`` entries always apply. A plugin may appear
    in more than one bucket (one entry per scope).

    Args:
        project_root: The project directory to match local/project entries against.
        claude_dir: Explicit Claude config dir whose
            ``plugins/installed_plugins.json`` is read. Defaults to ``~/.claude``.

    Returns:
        ``{"local": [...], "project": [...], "user": [...]}``; each entry is
        ``{"id", "version", "installPath", "scope"}``. Empty buckets if the
        registry is missing or unreadable.
    """
    buckets: dict[str, list[dict[str, str]]] = {"local": [], "project": [], "user": []}
    installed_path = plugins_base(claude_dir) / "installed_plugins.json"
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
