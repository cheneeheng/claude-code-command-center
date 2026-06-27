"""docket core: registry, plan discovery/read, manual command, headless runner, batch."""

from __future__ import annotations

import importlib.resources
import json
import os
import re
import shutil
import subprocess
import threading
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from queue import Empty, Queue

from docket import frontmatter, tracker

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

DEFAULT_PORT = 8765
DEFAULT_MAX_TURNS = 30
DEFAULT_PERMISSION_MODE = "acceptEdits"
# The Claude Code permission modes; kept in sync with the schema enum + cmd_doctor.
PERMISSION_MODES = ("acceptEdits", "default", "plan", "bypassPermissions")
DEFAULT_PLANNING_DIR = ".agents_workspace/planning"
DEFAULT_IMPL_DIR = ".agents_workspace/implementation"
DEFAULT_CLAUDE_BIN = "claude"
DEFAULT_CLAUDE_EXTRA: list[str] = []

# The bottom layer of the per-knob resolution cascade: code constant -> defaults -> project.
CODE_DEFAULTS = {
    "allowed_tools": DEFAULT_ALLOWED_TOOLS,
    "instruction_template": DEFAULT_INSTRUCTION_TEMPLATE,
    "model": None,
    "max_turns": DEFAULT_MAX_TURNS,
    "permission_mode": DEFAULT_PERMISSION_MODE,
    "planning_dir": DEFAULT_PLANNING_DIR,
    "implementation_dir": DEFAULT_IMPL_DIR,
    "claude_bin": DEFAULT_CLAUDE_BIN,
    "claude_extra_args": DEFAULT_CLAUDE_EXTRA,
}

_SEGMENT = re.compile(r"^[A-Za-z0-9._-]+$")


@dataclass
class Project:
    name: str
    path: str
    allowed_tools: list[str] = field(
        default_factory=lambda: list(DEFAULT_ALLOWED_TOOLS)
    )
    instruction_template: str = DEFAULT_INSTRUCTION_TEMPLATE
    model: str | None = None
    max_turns: int = DEFAULT_MAX_TURNS
    permission_mode: str = DEFAULT_PERMISSION_MODE
    planning_dir: str = DEFAULT_PLANNING_DIR
    implementation_dir: str = DEFAULT_IMPL_DIR
    claude_bin: str = DEFAULT_CLAUDE_BIN
    claude_extra_args: list[str] = field(default_factory=list)


@dataclass
class Config:
    port: int
    projects: list[Project]


@dataclass
class Plan:
    project: str
    slug: str  # relative path under planning/, sans .md; may contain "/"
    title: str
    status: str  # ready|running|implemented — sourced from the sidecar, NOT the plan
    body: str = ""  # "" for list summaries; full markdown from read_plan
    history: list = field(default_factory=list)


def safe_slug(slug: str) -> str:
    """Validate a plan slug used as both a relative path and a URL/query value.

    Accept one or more `/`-separated segments each matching ^[A-Za-z0-9._-]+$;
    reject `.`/`..` segments, leading/trailing `/`, empty slugs, and absolute paths.
    Makes it impossible to escape planning/. Returns the slug unchanged on success.
    """
    if not slug or slug.startswith("/") or slug.endswith("/"):
        raise ValueError(f"invalid slug: {slug!r}")
    segments = slug.split("/")
    for seg in segments:
        if seg in ("", ".", "..") or not _SEGMENT.match(seg):
            raise ValueError(f"invalid slug segment {seg!r} in {slug!r}")
    return slug


def _registry_search_paths(path: str | None) -> list[Path]:
    """First match wins: --registry → $DOCKET_REGISTRY → ./.docket.json → ~/.config."""
    candidates: list[str] = []
    if path:
        candidates.append(path)
    if os.environ.get("DOCKET_REGISTRY"):
        candidates.append(os.environ["DOCKET_REGISTRY"])
    candidates.append("./.docket.json")
    candidates.append("~/.config/docket/.docket.json")
    return [Path(os.path.expanduser(c)) for c in candidates]


def registry_search_paths(path: str | None = None) -> list[str]:
    """The resolved search paths, for the frontends' empty-state display."""
    return [str(p) for p in _registry_search_paths(path)]


def load_registry(path: str | None = None) -> Config:
    """Resolve and load .docket.json, merging the three config layers into a Config.

    Per-knob cascade (lowest → highest): CODE_DEFAULTS → defaults.<key> → project.<key>.
    No registry found -> Config(DEFAULT_PORT, []) (empty state, not an error). Not cached:
    resolve fresh each call so a changed --registry / $DOCKET_REGISTRY is picked up.
    """
    found = next((p for p in _registry_search_paths(path) if p.is_file()), None)
    if found is None:
        return Config(port=DEFAULT_PORT, projects=[])

    with open(found, encoding="utf-8") as fh:
        data = json.load(fh)

    if not isinstance(data, dict) or not isinstance(data.get("projects"), list):
        raise ValueError(f'{found}: expected top-level shape {{"projects": [...]}}')

    defaults = dict(data.get("defaults", {}))
    # Lenient v1 carry-over: a top-level instruction_template seeds defaults if absent.
    if "instruction_template" in data and "instruction_template" not in defaults:
        defaults["instruction_template"] = data["instruction_template"]

    def pick(raw: dict, key: str):
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
                allowed_tools=pick(entry, "allowed_tools"),
                instruction_template=pick(entry, "instruction_template"),
                model=pick(entry, "model"),
                max_turns=pick(entry, "max_turns"),
                permission_mode=pick(entry, "permission_mode"),
                planning_dir=pick(entry, "planning_dir"),
                implementation_dir=pick(entry, "implementation_dir"),
                claude_bin=pick(entry, "claude_bin"),
                claude_extra_args=list(pick(entry, "claude_extra_args")),
            )
        )
    return Config(port=data.get("port", DEFAULT_PORT), projects=projects)


def _planning_root(project: Project) -> Path:
    return Path(project.path) / project.planning_dir


def list_plans(project: Project) -> list[Plan]:
    """Recursively discover planning/**/*.md -> Plan summaries (body=""), sorted."""
    root = _planning_root(project)
    if not root.is_dir():
        return []

    plans: list[Plan] = []
    for md in root.rglob("*.md"):
        if not md.is_file():
            continue
        slug = md.relative_to(root).with_suffix("").as_posix()
        meta, _ = frontmatter.parse(md.read_text(encoding="utf-8"))
        status = tracker.read_record(project, slug)["status"]
        plans.append(
            Plan(
                project=project.name,
                slug=slug,
                title=meta.get("title") or slug,
                status=status,
            )
        )
    plans.sort(key=lambda p: (p.status, p.slug))
    return plans


def read_plan(project: Project, slug: str) -> Plan:
    """Full plan body + status + history. Missing file -> FileNotFoundError."""
    slug = safe_slug(slug)
    md = _planning_root(project) / f"{slug}.md"
    if not md.is_file():
        raise FileNotFoundError(f"plan not found: {project.name}/{slug}")
    text = md.read_text(encoding="utf-8")
    meta, _ = frontmatter.parse(text)
    rec = tracker.read_record(project, slug)
    return Plan(
        project=project.name,
        slug=slug,
        title=meta.get("title") or slug,
        status=rec["status"],
        body=text,
        history=rec["history"],
    )


def manual_command(project: Project, slug: str) -> str:
    """Copy-pasteable command for running the plan yourself (feeds the plan body)."""
    slug = safe_slug(slug)
    plan_rel = f"{project.planning_dir}/{slug}.md"
    return (
        f"cd {project.path} && claude -p < {plan_rel}\n"
        f"# or: cd {project.path} && claude   (then paste / @-mention the plan file)"
    )


# --- Config authoring: init / doctor (ITER_02_v2) -----------------------------


def _schema_path() -> str:
    """Absolute path to the shipped JSON Schema, for the .docket.json $schema pointer."""
    res = importlib.resources.files("docket") / "schema" / "docket.schema.json"
    return str(Path(str(res)).resolve())


def _suffix(name: str) -> str:
    """foo -> foo-2, foo-2 -> foo-3, ... — deterministic name-collision disambiguation."""
    base, _, n = name.rpartition("-")
    return f"{base}-{int(n) + 1}" if base and n.isdigit() else f"{name}-2"


def discover_repos(root: str) -> list[dict]:
    """Find git repos under ROOT that contain the default planning dir → [{name, path}].

    Names are deduped deterministically; paths are ~-relative when under $HOME for
    portability, else absolute. Discovered entries carry only name + path (rest inherits
    defaults). Sorted by name.
    """
    base = Path(root).expanduser()
    home = Path.home()
    found: list[dict] = []
    names: set[str] = set()
    for git in base.rglob(".git"):
        repo = git.parent
        if not (repo / DEFAULT_PLANNING_DIR).is_dir():
            continue
        # Resolve first so the name is the real dir name even when root is "." (whose
        # unresolved .name is "") and so the path is portable (posix-separated under $HOME).
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


def _default_config(discovered: list[dict]) -> dict:
    """A complete, valid config with every key at its default (the fresh-init body)."""
    return {
        "$schema": _schema_path(),
        "port": DEFAULT_PORT,
        "defaults": {
            "allowed_tools": DEFAULT_ALLOWED_TOOLS,
            "instruction_template": DEFAULT_INSTRUCTION_TEMPLATE,
            "model": None,
            "max_turns": DEFAULT_MAX_TURNS,
            "permission_mode": DEFAULT_PERMISSION_MODE,
            "planning_dir": DEFAULT_PLANNING_DIR,
            "implementation_dir": DEFAULT_IMPL_DIR,
            "claude_bin": DEFAULT_CLAUDE_BIN,
            "claude_extra_args": DEFAULT_CLAUDE_EXTRA,
        },
        "projects": discovered,
    }


def cmd_init(
    output: str = ".docket.json",
    scan: str | None = None,
    force: bool = False,
    merge: bool = False,
    dry_run: bool = False,
) -> str:
    """Generate a fresh .docket.json or (--merge) add only newly-found repos in place.

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
    tmp = target.with_suffix(target.suffix + ".tmp")  # atomic write (sidecar pattern)
    tmp.write_text(rendered, encoding="utf-8")
    os.replace(tmp, target)
    return summary


def cmd_doctor(registry: str | None = None) -> int:
    """Load the registry and report config problems; return 1 on any error-level finding."""
    try:
        cfg = load_registry(registry)
    except (ValueError, OSError) as exc:
        print(f"error: {exc}")
        return 1
    errors = warns = 0
    if not cfg.projects:
        print("warn: no projects configured")
        warns += 1
    for pr in cfg.projects:  # paths/dupes already validated by load_registry
        plan_dir = Path(pr.path) / pr.planning_dir
        if not plan_dir.is_dir():
            print(f"warn: {pr.name}: no planning dir at {plan_dir}")
            warns += 1
        if pr.permission_mode not in PERMISSION_MODES:
            print(f"error: {pr.name}: unknown permission_mode {pr.permission_mode!r}")
            errors += 1
        if not pr.allowed_tools:
            print(
                f"warn: {pr.name}: allowed_tools is empty — every tool will be denied"
            )
            warns += 1
        bin_ = os.path.expandvars(os.path.expanduser(pr.claude_bin))
        if shutil.which(bin_) is None and not os.path.isfile(bin_):
            print(f"error: {pr.name}: claude_bin {pr.claude_bin!r} not found on PATH")
            errors += 1
    print(f"{len(cfg.projects)} project(s): {errors} error(s), {warns} warning(s)")
    return 1 if errors else 0


# --- Headless run (ITER_03) ---------------------------------------------------

_locks: dict[str, threading.Lock] = {}
_locks_guard = threading.Lock()


def project_lock(path: str) -> threading.Lock:
    """Per-project lock so two headless runs on the same repo can't collide."""
    with _locks_guard:
        return _locks.setdefault(path, threading.Lock())


def default_instruction_template(path: str | None = None) -> str:
    """The global default template (defaults-layer value or the code constant), {path}
    left literal — for the param-less /api/instruction-template pre-fill."""
    found = next((p for p in _registry_search_paths(path) if p.is_file()), None)
    if found is None:
        return DEFAULT_INSTRUCTION_TEMPLATE
    data = json.loads(Path(found).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return DEFAULT_INSTRUCTION_TEMPLATE
    defaults = data.get("defaults", {})
    template = (
        defaults.get("instruction_template") if isinstance(defaults, dict) else None
    )
    # v1 carry-over: a top-level instruction_template stands in for the defaults layer.
    return template or data.get("instruction_template") or DEFAULT_INSTRUCTION_TEMPLATE


def resolve_instruction(project: Project, slug: str, override: str | None) -> str:
    """Build the stdin instruction that names the plan file. {path} is substituted.

    Template precedence: per-plan override → the resolved project.instruction_template
    (which already encodes defaults → code constant from load_registry's cascade).
    """
    slug = safe_slug(slug)
    path = f"{project.planning_dir}/{slug}.md"
    template = override or project.instruction_template
    if "{path}" in template:
        return template.format(path=path)
    return template


def format_event(raw: str) -> str | None:
    """Parse one NDJSON stream-json event into a short display line, or None to skip."""
    raw = raw.rstrip("\n")
    if not raw.strip():
        return None
    try:
        ev = json.loads(raw)
    except json.JSONDecodeError:
        return raw  # defensive: pass non-JSON through verbatim

    etype = ev.get("type")
    if etype == "system":
        return None  # init event — skip
    if etype == "assistant":
        parts = []
        for block in ev.get("message", {}).get("content", []):
            btype = block.get("type")
            if btype == "text":
                text = block.get("text", "").strip()
                if text:
                    parts.append(text)
            elif btype == "tool_use":
                name = block.get("name", "tool")
                digest = _tool_digest(block.get("input", {}))
                parts.append(f"▸ {name}{(' ' + digest) if digest else ''}")
        return "\n".join(parts) if parts else None
    if etype == "result":
        if ev.get("is_error") or ev.get("subtype") not in (None, "success"):
            return f"[error] {ev.get('subtype', 'error')}"
        return "[done]"
    return None


def _tool_digest(inp: dict) -> str:
    """One-line arg digest for a tool_use event (e.g. the edited path or command)."""
    for key in ("file_path", "path", "pattern", "command", "url"):
        val = inp.get(key)
        if isinstance(val, str):
            return val.splitlines()[0][:80] if val else ""
    return ""


def run_implement(
    project: Project,
    slug: str,
    instruction: str,
    *,
    on_spawn=None,
    run_id: str | None = None,
):
    """Generator: spawn `claude -p`, pipe the INSTRUCTION (names the plan file) on stdin,
    yield human-readable display lines. The plan body is never piped. on_spawn(proc) hands
    the Popen handle to the caller for stop()."""
    slug = safe_slug(slug)
    rec = tracker.read_record(project, slug)
    if rec["status"] not in ("ready", "implemented"):
        raise ValueError(f"{project.name}/{slug} is '{rec['status']}', not runnable")

    # Preflight the binary BEFORE flipping status / taking the lock — a bad claude_bin
    # must not strand the plan as 'running' or hold the project lock.
    bin_ = os.path.expandvars(os.path.expanduser(project.claude_bin))
    if shutil.which(bin_) is None and not os.path.isfile(bin_):
        raise FileNotFoundError(f"claude_bin {project.claude_bin!r} not found on PATH")

    lock = project_lock(project.path)
    if not lock.acquire(blocking=False):
        raise RuntimeError("a run is already active for this project")
    try:
        tracker.set_status(project, slug, "running", trigger="headless", run_id=run_id)
        allow = ",".join(project.allowed_tools)
        cmd = [
            bin_,
            "-p",
            "--output-format",
            "stream-json",
            "--verbose",
            "--permission-mode",
            project.permission_mode,
            "--max-turns",
            str(project.max_turns),
            "--allowedTools",
            allow,
        ]
        if project.model:
            cmd += ["--model", project.model]
        cmd += project.claude_extra_args  # additive escape hatch, appended last

        proc = subprocess.Popen(
            cmd,
            cwd=project.path,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
        if on_spawn:
            on_spawn(proc)
        proc.stdin.write(instruction)
        proc.stdin.close()
        try:
            for raw in proc.stdout:
                line = format_event(raw)
                if line is not None:
                    yield line
            proc.wait()
        finally:
            proc.stdout.close()

        ok = proc.returncode == 0
        tracker.set_status(
            project,
            slug,
            "implemented" if ok else "ready",
            trigger="headless",
            run_id=run_id,
            rc=proc.returncode,
        )
        yield f"[docket] run {'completed' if ok else f'ended (rc={proc.returncode})'}"
    finally:
        lock.release()


# --- Batch orchestration (ITER_03, server side) -------------------------------


@dataclass
class Run:
    run_id: str
    project: str
    slug: str
    instruction: str
    state: str = "queued"  # queued|running|done|failed|stopped|skipped
    proc: object | None = None
    queue: Queue = field(default_factory=Queue)


_SENTINEL = object()


class RunManager:
    """Server-side run + batch orchestrator: group by project, sequential per project,
    concurrent across projects, stop-on-failure within a project."""

    def __init__(self, projects: list[Project]):
        self._projects = {p.name: p for p in projects}
        self._runs: dict[str, Run] = {}
        self._guard = threading.Lock()

    def set_projects(self, projects: list[Project]) -> None:
        self._projects = {p.name: p for p in projects}

    def submit(self, items: list[dict]) -> list[Run]:
        """Validate every item, create a Run for each up front, group by project, and
        spawn one daemon thread per project. Returns all runs (state queued/running)."""
        validated: list[tuple[Project, str, str]] = []
        for item in items:
            project = self._projects.get(item.get("project"))
            if project is None:
                raise ValueError(f"unknown project: {item.get('project')!r}")
            slug = safe_slug(item.get("slug", ""))
            rec = tracker.read_record(project, slug)
            if rec["status"] not in ("ready", "implemented"):
                raise ValueError(
                    f"{project.name}/{slug} is '{rec['status']}', not runnable"
                )
            instruction = resolve_instruction(project, slug, item.get("instruction"))
            validated.append((project, slug, instruction))

        runs: list[Run] = []
        by_project: dict[str, list[Run]] = {}
        for project, slug, instruction in validated:
            run = Run(
                run_id=uuid.uuid4().hex,
                project=project.name,
                slug=slug,
                instruction=instruction,
            )
            runs.append(run)
            by_project.setdefault(project.name, []).append(run)

        with self._guard:
            for run in runs:
                self._runs[run.run_id] = run

        for project_name, project_runs in by_project.items():
            t = threading.Thread(
                target=self._run_project_batch,
                args=(self._projects[project_name], project_runs),
                daemon=True,
            )
            t.start()
        return runs

    def _run_project_batch(self, project: Project, runs: list[Run]) -> None:
        failed = False
        for run in runs:
            if failed:
                run.state = "skipped"
                run.queue.put(_SENTINEL)
                continue
            run.state = "running"
            try:
                gen = run_implement(
                    project,
                    run.slug,
                    run.instruction,
                    on_spawn=lambda p, r=run: setattr(r, "proc", p),
                    run_id=run.run_id,
                )
                for line in gen:
                    run.queue.put(line)
                if run.state != "stopped":
                    run.state = (
                        "done"
                        if (run.proc is None or run.proc.returncode == 0)
                        else "failed"
                    )
            except (ValueError, RuntimeError) as exc:
                run.queue.put(f"[docket] {exc}")
                run.state = "failed"
            run.queue.put(_SENTINEL)
            if run.state in ("failed", "stopped"):
                failed = True

    def stream(self, run_id: str, keepalive: float = 15.0):
        """Look up the run and return the SSE generator. Raises KeyError eagerly for an
        unknown run_id (so the handler can answer 404 before sending stream headers — a
        generator function would defer that raise until first iteration)."""
        run = self._runs.get(run_id)
        if run is None:
            raise KeyError(run_id)
        return self._stream(run, keepalive)

    def _stream(self, run: Run, keepalive: float):
        """Drain one run's queue: yields ('data', line), ('keepalive', None) while idle,
        and finally ('end', state). A queued run just emits keep-alives until its turn in
        its project batch arrives."""
        while True:
            try:
                item = run.queue.get(timeout=keepalive)
            except Empty:
                yield ("keepalive", None)
                continue
            if item is _SENTINEL:
                break
            yield ("data", item)
        yield ("end", run.state)

    def stop(self, run_id: str) -> None:
        run = self._runs.get(run_id)
        if run is None:
            raise KeyError(run_id)
        if run.state not in ("queued", "running"):
            raise ValueError(f"run {run_id} is '{run.state}', not stoppable")
        run.state = "stopped"
        proc = run.proc
        if proc is not None:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
