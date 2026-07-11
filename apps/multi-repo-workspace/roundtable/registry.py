"""Registry: 3-layer config cascade -> Config/Project, plus init/doctor and app state.

Cross-reference: forked at birth from docket (apps/multi-repo-plan-runner/docket/core.py)
registry machinery; only the sidecar format is a kept-in-sync contract (see tracker.py).
"""

from __future__ import annotations

import importlib.resources
import json
import os
import shutil
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

DEFAULT_PORT = 8640

DEFAULT_ALLOWED_TOOLS = [
    "Read",
    "Edit",
    "Write",
    "Bash(pytest:*)",
    "Bash(npm test:*)",
    "Bash(npm run test:*)",
]

# {path} is filled with the plan's repo-relative path: <planning_dir>/<slug>.md
DEFAULT_INSTRUCTION_TEMPLATE = (
    "Read the plan at {path} and implement it fully. The plan may reference sibling "
    "files (e.g. a SKELETON or earlier iterations) — read those as needed. Make the "
    "code changes the plan describes."
)

# {request} is the user's planning prompt; {planning_dir} the repo-relative planning dir.
DEFAULT_PLANNING_TEMPLATE = (
    "You are in planning mode for this repository. Work with me to produce an "
    "implementation plan. When the plan is agreed, write it as a markdown file under "
    "`{planning_dir}/` and tell me its path. Do not implement anything in this "
    "session.\n\nRequest: {request}"
)

DEFAULT_MAX_TURNS = 30
DEFAULT_PERMISSION_MODE = "acceptEdits"
DEFAULT_PLANNING_PERMISSION_MODE = "acceptEdits"
# The Claude Code permission modes; kept in sync with the schema enum + cmd_doctor.
PERMISSION_MODES = ("acceptEdits", "default", "plan", "bypassPermissions")
DEFAULT_PLANNING_DIR = ".agents_workspace/planning"
DEFAULT_IMPL_DIR = ".agents_workspace/implementation"
DEFAULT_CLAUDE_BIN = "claude"
DEFAULT_CLAUDE_EXTRA: list[str] = []

# The bottom layer of the per-knob resolution cascade: code constant -> defaults -> project.
CODE_DEFAULTS: dict[str, Any] = {
    "allowed_tools": DEFAULT_ALLOWED_TOOLS,
    "instruction_template": DEFAULT_INSTRUCTION_TEMPLATE,
    "planning_template": DEFAULT_PLANNING_TEMPLATE,
    "model": None,
    "max_turns": DEFAULT_MAX_TURNS,
    "permission_mode": DEFAULT_PERMISSION_MODE,
    "planning_permission_mode": DEFAULT_PLANNING_PERMISSION_MODE,
    "planning_dir": DEFAULT_PLANNING_DIR,
    "implementation_dir": DEFAULT_IMPL_DIR,
    "claude_bin": DEFAULT_CLAUDE_BIN,
    "claude_extra_args": DEFAULT_CLAUDE_EXTRA,
}


@dataclass
class Project:
    name: str
    path: str
    allowed_tools: list[str] = field(
        default_factory=lambda: list(DEFAULT_ALLOWED_TOOLS)
    )
    instruction_template: str = DEFAULT_INSTRUCTION_TEMPLATE
    planning_template: str = DEFAULT_PLANNING_TEMPLATE
    model: str | None = None
    max_turns: int = DEFAULT_MAX_TURNS
    permission_mode: str = DEFAULT_PERMISSION_MODE
    planning_permission_mode: str = DEFAULT_PLANNING_PERMISSION_MODE
    planning_dir: str = DEFAULT_PLANNING_DIR
    implementation_dir: str = DEFAULT_IMPL_DIR
    claude_bin: str = DEFAULT_CLAUDE_BIN
    claude_extra_args: list[str] = field(default_factory=list)


@dataclass
class Config:
    port: int
    projects: list[Project]


def state_home() -> Path:
    """The app state dir: `$C4_ROUNDTABLE_HOME` else `~/.roundtable/`."""
    override = os.environ.get("C4_ROUNDTABLE_HOME")
    return Path(override).expanduser() if override else Path.home() / ".roundtable"


def atomic_write_text(path: Path, text: str) -> None:
    """Write to a temp file in the same directory, then os.replace over the target."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
    # newline="" disables \n -> os.linesep translation: content lands byte-exact.
    with open(tmp, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    # On Windows a just-written target can be transiently locked by AV/indexer, making
    # the atomic os.replace fail with PermissionError; retry briefly before giving up.
    for _ in range(9):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            time.sleep(0.05)
    os.replace(tmp, path)  # final attempt; let a persistent PermissionError propagate


def atomic_write_json(path: Path, obj: dict[str, Any]) -> None:
    """Atomically serialize OBJ as pretty JSON to PATH."""
    atomic_write_text(path, json.dumps(obj, indent=2))


def read_json(path: Path) -> dict[str, Any]:
    """Read a JSON object, retrying briefly on Windows PermissionError.

    The mirror image of atomic_write_text's retry: on Windows a read can land
    mid-os.replace (or mid-AV scan) and fail transiently.
    """
    for _ in range(9):
        try:
            data: dict[str, Any] = json.loads(path.read_text(encoding="utf-8"))
            return data
        except PermissionError:
            time.sleep(0.05)
    data = json.loads(path.read_text(encoding="utf-8"))  # final attempt; may propagate
    return data


def _registry_search_paths(path: str | None) -> list[Path]:
    """First match wins: --registry -> $C4_ROUNDTABLE_REGISTRY -> ./ -> ~/.config."""
    candidates: list[str] = []
    if path:
        candidates.append(path)
    if os.environ.get("C4_ROUNDTABLE_REGISTRY"):
        candidates.append(os.environ["C4_ROUNDTABLE_REGISTRY"])
    candidates.append("./.roundtable.json")
    candidates.append("~/.config/roundtable/.roundtable.json")
    return [Path(os.path.expanduser(c)) for c in candidates]


def registry_search_paths(path: str | None = None) -> list[str]:
    """The resolved search paths, for the frontend's empty-state display."""
    return [str(p) for p in _registry_search_paths(path)]


def load_registry(path: str | None = None) -> Config:
    """Resolve and load .roundtable.json, merging the three config layers into a Config.

    Per-knob cascade (lowest -> highest): CODE_DEFAULTS -> defaults.<key> -> project.<key>.
    No registry found -> Config(DEFAULT_PORT, []) (empty state, not an error). Not cached:
    resolve fresh each call so a changed --registry / $C4_ROUNDTABLE_REGISTRY is picked up.
    """
    found = next((p for p in _registry_search_paths(path) if p.is_file()), None)
    if found is None:
        return Config(port=DEFAULT_PORT, projects=[])

    with open(found, encoding="utf-8") as fh:
        data = json.load(fh)

    if not isinstance(data, dict) or not isinstance(data.get("projects"), list):
        raise ValueError(f'{found}: expected top-level shape {{"projects": [...]}}')

    defaults = dict(data.get("defaults", {}))

    def pick(raw: dict[str, Any], key: str) -> Any:  # cascade value; shape varies
        return raw.get(key, defaults.get(key, CODE_DEFAULTS[key]))

    projects: list[Project] = []
    seen: set[str] = set()
    for entry in data["projects"]:
        name = entry.get("name")
        if not name:
            raise ValueError(f"{found}: a project entry is missing 'name'")
        if name in seen:
            raise ValueError(f"{found}: duplicate project name {name!r}")
        seen.add(name)

        raw_path = entry.get("path")
        if not raw_path:
            raise ValueError(f"{found}: project {name!r} is missing 'path'")
        abspath = os.path.abspath(os.path.expanduser(os.path.expandvars(raw_path)))
        if not os.path.isdir(abspath):
            raise ValueError(
                f"{found}: project {name!r} path is not a directory: {abspath}"
            )

        projects.append(
            Project(
                name=name,
                path=abspath,
                allowed_tools=list(pick(entry, "allowed_tools")),
                instruction_template=pick(entry, "instruction_template"),
                planning_template=pick(entry, "planning_template"),
                model=pick(entry, "model"),
                max_turns=pick(entry, "max_turns"),
                permission_mode=pick(entry, "permission_mode"),
                planning_permission_mode=pick(entry, "planning_permission_mode"),
                planning_dir=pick(entry, "planning_dir"),
                implementation_dir=pick(entry, "implementation_dir"),
                claude_bin=pick(entry, "claude_bin"),
                claude_extra_args=list(pick(entry, "claude_extra_args")),
            )
        )
    return Config(port=int(data.get("port", DEFAULT_PORT)), projects=projects)


# --- Config authoring: init / doctor -------------------------------------------


def _schema_path() -> str:
    """Absolute path to the shipped JSON Schema, for the $schema pointer."""
    res = importlib.resources.files("roundtable") / "schema" / "roundtable.schema.json"
    return str(Path(str(res)).resolve())


def _suffix(name: str) -> str:
    """foo -> foo-2, foo-2 -> foo-3, ... — deterministic name-collision disambiguation."""
    base, _, n = name.rpartition("-")
    return f"{base}-{int(n) + 1}" if base and n.isdigit() else f"{name}-2"


def discover_repos(root: str) -> list[dict[str, str]]:
    """Find git repos under ROOT that contain the default planning dir.

    Names are deduped deterministically; paths are ~-relative when under $HOME for
    portability, else absolute. Discovered entries carry only name + path (rest
    inherits defaults). Sorted by name.
    """
    base = Path(root).expanduser()
    home = Path.home()
    found: list[dict[str, str]] = []
    names: set[str] = set()
    for git in base.rglob(".git"):
        repo = git.parent
        if not (repo / DEFAULT_PLANNING_DIR).is_dir():
            continue
        p = repo.resolve()
        name = p.name
        while name in names:
            name = _suffix(name)
        names.add(name)
        disp = (
            f"~/{p.relative_to(home).as_posix()}" if p.is_relative_to(home) else str(p)
        )
        found.append({"name": name, "path": disp})
    return sorted(found, key=lambda e: e["name"])


def _default_config(discovered: list[dict[str, str]]) -> dict[str, Any]:
    """A complete, valid config with every key at its default (the fresh-init body)."""
    return {
        "$schema": _schema_path(),
        "port": DEFAULT_PORT,
        "defaults": {
            "allowed_tools": DEFAULT_ALLOWED_TOOLS,
            "instruction_template": DEFAULT_INSTRUCTION_TEMPLATE,
            "planning_template": DEFAULT_PLANNING_TEMPLATE,
            "model": None,
            "max_turns": DEFAULT_MAX_TURNS,
            "permission_mode": DEFAULT_PERMISSION_MODE,
            "planning_permission_mode": DEFAULT_PLANNING_PERMISSION_MODE,
            "planning_dir": DEFAULT_PLANNING_DIR,
            "implementation_dir": DEFAULT_IMPL_DIR,
            "claude_bin": DEFAULT_CLAUDE_BIN,
            "claude_extra_args": DEFAULT_CLAUDE_EXTRA,
        },
        "projects": discovered,
    }


def cmd_init(
    output: str = ".roundtable.json",
    scan: str | None = None,
    force: bool = False,
    merge: bool = False,
    dry_run: bool = False,
) -> str:
    """Generate a fresh .roundtable.json or (--merge) add newly-found repos in place.

    Returns a one-line summary. Raises FileExistsError (no-clobber) / FileNotFoundError
    (--merge needs an existing target).
    """
    target = Path(output)
    discovered = discover_repos(scan) if scan else []

    if merge:  # update in place, preserve hand edits
        if not target.exists():
            raise FileNotFoundError(
                f"{target} does not exist — run a plain `init` first"
            )
        config = json.loads(target.read_text(encoding="utf-8"))
        existing = config.setdefault("projects", [])
        have_paths = {p.get("path") for p in existing}
        have_names = {p.get("name") for p in existing}
        added = 0
        for repo in discovered:  # add only genuinely new repos
            if repo["path"] in have_paths:
                continue
            name = repo["name"]
            while name in have_names:  # keep names unique against existing
                name = _suffix(name)
            existing.append({"name": name, "path": repo["path"]})
            have_paths.add(repo["path"])
            have_names.add(name)
            added += 1
        existing.sort(key=lambda e: e["name"])
        verb = "would add" if dry_run else "added"
        summary = f"{verb} {added} new project(s) to {target}"
    else:  # fresh file
        if target.exists() and not force and not dry_run:
            raise FileExistsError(
                f"{target} exists — pass --force to overwrite or --merge to update"
            )
        config = _default_config(discovered)
        verb = "would write" if dry_run else "wrote"
        summary = f"{verb} {target} ({len(discovered)} project(s))"

    rendered = json.dumps(config, indent=2) + "\n"
    if dry_run:
        print(rendered)
        return summary
    atomic_write_text(target, rendered)
    return summary


def _which(binary: str) -> bool:
    """True when BINARY resolves on PATH or as an explicit file (~/$VARS expanded)."""
    expanded = os.path.expandvars(os.path.expanduser(binary))
    return shutil.which(expanded) is not None or os.path.isfile(expanded)


def cmd_doctor(registry: str | None = None) -> int:
    """Load the registry and report problems; return 1 on any error-level finding."""
    try:
        cfg = load_registry(registry)
    except (ValueError, OSError) as exc:
        print(f"error: {exc}")
        return 1
    errors = warns = 0
    if not cfg.projects:
        print("warn: no projects configured")
        warns += 1
    if not _which("git"):
        print("error: git not found on PATH")
        errors += 1
    for pr in cfg.projects:  # paths/dupes already validated by load_registry
        plan_dir = Path(pr.path) / pr.planning_dir
        if not plan_dir.is_dir():
            print(f"warn: {pr.name}: no planning dir at {plan_dir}")
            warns += 1
        for knob in ("permission_mode", "planning_permission_mode"):
            mode = getattr(pr, knob)
            if mode not in PERMISSION_MODES:
                print(f"error: {pr.name}: unknown {knob} {mode!r}")
                errors += 1
        if not pr.allowed_tools:
            print(
                f"warn: {pr.name}: allowed_tools is empty — every tool will be denied"
            )
            warns += 1
        if not _which(pr.claude_bin):
            print(f"error: {pr.name}: claude_bin {pr.claude_bin!r} not found on PATH")
            errors += 1
    print(f"{len(cfg.projects)} project(s): {errors} error(s), {warns} warning(s)")
    return 1 if errors else 0
