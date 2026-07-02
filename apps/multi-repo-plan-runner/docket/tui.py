"""docket TUI — a three-pane Textual app over the shared core + tracker.

Left: project/plan tree with a status badge per plan. Right-top: read-only plan view.
Right-bottom: live run log. The MVP TUI streams one run at a time.
"""

from __future__ import annotations

from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.screen import ModalScreen
from textual.widgets import Footer, Header, Input, RichLog, Static, Tree

from docket import core, tracker

_BADGE = {"ready": "○", "running": "▶", "implemented": "●"}


class PlanTree(Tree):
    """Tree that frees `space` for batch-select. The stock Tree binds `space` to
    `toggle_node` and consumes it, so the app-level binding never fires; remap it to
    the app action instead."""

    BINDINGS = [Binding("space", "app.toggle_select", "Select for batch", show=False)]


class InstructionModal(ModalScreen[str | None]):
    """Prompt for the headless instruction, pre-filled with the resolved template."""

    BINDINGS = [("escape", "cancel", "Cancel")]

    def __init__(self, default: str) -> None:
        super().__init__()
        self._default = default

    def compose(self) -> ComposeResult:
        yield Static("Instruction (names the plan file) — Enter to run, Esc to cancel:")
        yield Input(value=self._default, id="instruction")

    def on_input_submitted(self, event: Input.Submitted) -> None:
        self.dismiss(event.value)

    def action_cancel(self) -> None:
        self.dismiss(None)


class DocketApp(App):
    CSS = """
    Tree { width: 36; border-right: solid $panel; }
    #plan-view { height: 1fr; border-bottom: solid $panel; padding: 0 1; }
    #log { height: 1fr; padding: 0 1; }
    InstructionModal { align: center middle; }
    InstructionModal Static { width: 80; }
    InstructionModal Input { width: 80; }
    """

    BINDINGS = [
        ("i", "implement", "Implement"),
        ("I", "implement_selected", "Implement selected"),
        ("r", "run_myself", "Run myself"),
        ("m", "mark", "Mark implemented"),
        ("o", "reopen", "Reopen"),
        ("space", "toggle_select", "Select for batch"),
        ("s", "stop", "Stop"),
        ("q", "quit", "Quit"),
    ]

    def __init__(self, registry: str | None = None) -> None:
        super().__init__()
        self._registry_path = registry
        self._projects: list[core.Project] = []
        self._selected: set[tuple[str, str]] = set()  # (project, slug) for batch
        self._current: tuple[str, str] | None = None  # focused plan
        self._proc = None  # active headless Popen

    def compose(self) -> ComposeResult:
        yield Header()
        with Horizontal():
            yield PlanTree("docket", id="tree")
            with Vertical():
                yield Static("select a plan", id="plan-view", markup=False)
                yield RichLog(id="log", highlight=False, markup=False, wrap=True)
        yield Footer()

    def on_mount(self) -> None:
        self._projects = core.load_registry(self._registry_path).projects
        reset = tracker.reset_stale_runs(self._projects)
        if reset:
            self.query_one("#log", RichLog).write(
                f"[docket] reset {len(reset)} stale run(s)"
            )
        self._reload_tree()

    # --- tree -----------------------------------------------------------------

    def _reload_tree(self) -> None:
        tree = self.query_one("#tree", Tree)
        tree.clear()
        if not self._projects:
            tree.root.add_leaf("no projects — edit .docket.json")
            for path in core.registry_search_paths(self._registry_path):
                tree.root.add_leaf(f"  searched: {path}")
            return
        tree.root.expand()
        for project in self._projects:
            node = tree.root.add(project.name, expand=True)
            for plan in core.list_plans(project):
                key = (project.name, plan.slug)
                node.add_leaf(self._plan_label(plan, key), data=key)

    def _plan_label(self, plan, key) -> str:
        mark = "✓ " if key in self._selected else "  "
        return f"{mark}{_BADGE.get(plan.status, '?')} {plan.title} [{plan.status}]"

    def on_tree_node_highlighted(self, event: Tree.NodeHighlighted) -> None:
        # Track the cursor (not just Enter/click) so batch-select and the implement
        # actions operate on the highlighted plan and the plan view follows it.
        data = event.node.data
        if not data:
            self._current = None
            return
        self._current = data
        project = self._project(data[0])
        try:
            plan = core.read_plan(project, data[1])
        except FileNotFoundError as exc:
            self.query_one("#log", RichLog).write(f"[docket] {exc}")
            return
        view = self.query_one("#plan-view", Static)
        view.update(f"{plan.title}  [{plan.status}]\n\n{plan.body}")

    # --- helpers --------------------------------------------------------------

    def _project(self, name: str) -> core.Project:
        return next(p for p in self._projects if p.name == name)

    def _refresh(self) -> None:
        self._reload_tree()

    def _notify_log(self, msg: str) -> None:
        self.query_one("#log", RichLog).write(msg)

    # --- manual actions -------------------------------------------------------

    def action_run_myself(self) -> None:
        if not self._current:
            return
        name, slug = self._current
        cmd = core.manual_command(self._project(name), slug)
        try:
            self.copy_to_clipboard(core.read_plan(self._project(name), slug).body)
            self._notify_log("[docket] plan body copied to clipboard")
        except Exception:  # noqa: BLE001 — clipboard is best-effort
            self._notify_log("[docket] clipboard unavailable")
        self._notify_log(cmd)

    def action_mark(self) -> None:
        self._manual("implemented")

    def action_reopen(self) -> None:
        self._manual("ready")

    def _manual(self, to: str) -> None:
        if not self._current:
            return
        name, slug = self._current
        try:
            tracker.set_status(self._project(name), slug, to, trigger="manual")
            self._refresh()
        except ValueError as exc:
            self._notify_log(f"[docket] {exc}")

    def action_toggle_select(self) -> None:
        node = self.query_one("#tree", Tree).cursor_node
        if node is None or not node.data:
            return
        key = node.data
        name, slug = key
        if key in self._selected:
            self._selected.discard(key)
        elif core.read_plan(self._project(name), slug).status != "ready":
            self._notify_log("[docket] only ready plans can be selected for batch")
            return
        else:
            self._selected.add(key)
        # Relabel just this node — a full reload would reset the cursor to the root,
        # making multi-select unusable.
        node.set_label(self._plan_label(core.read_plan(self._project(name), slug), key))

    # --- headless run ---------------------------------------------------------

    def action_implement(self) -> None:
        if not self._current:
            return
        name, slug = self._current
        if core.read_plan(self._project(name), slug).status != "ready":
            self._notify_log("[docket] not runnable — reopen to run again")
            return
        default = core.resolve_instruction(self._project(name), slug, None)

        def go(instruction: str | None) -> None:
            if instruction is None:
                return
            self._run_batch([(name, slug, instruction)])

        self.push_screen(InstructionModal(default), go)

    def action_implement_selected(self) -> None:
        if not self._selected:
            self._notify_log("[docket] nothing selected (space to select)")
            return
        items = [
            (p, s, core.resolve_instruction(self._project(p), s, None))
            for (p, s) in sorted(self._selected)
        ]
        self._selected.clear()
        self._run_batch(items)

    @work(thread=True, exclusive=True)
    def _run_batch(self, items: list[tuple[str, str, str]]) -> None:
        """Stream one run at a time, project-by-project (MVP TUI). Stop-on-failure per
        project. Runs in a worker thread; UI updates via call_from_thread."""
        log = self.query_one("#log", RichLog)
        # group by project, preserving order
        by_project: dict[str, list[tuple[str, str]]] = {}
        for name, slug, instruction in items:
            by_project.setdefault(name, []).append((slug, instruction))

        for name, plans in by_project.items():
            project = self._project(name)
            for slug, instruction in plans:
                self.call_from_thread(log.write, f"[docket] ── {name}/{slug} ──")
                try:
                    gen = core.run_implement(
                        project,
                        slug,
                        instruction,
                        on_spawn=lambda p: setattr(self, "_proc", p),
                    )
                    for line in gen:
                        self.call_from_thread(log.write, line)
                    rc = self._proc.returncode if self._proc else 0
                    self._proc = None
                    if rc != 0:
                        self.call_from_thread(
                            log.write, f"[docket] {name} batch stopped (rc={rc})"
                        )
                        break
                except (ValueError, RuntimeError) as exc:
                    self.call_from_thread(log.write, f"[docket] {exc}")
                    break
                finally:
                    self.call_from_thread(self._refresh)

    def action_stop(self) -> None:
        if self._proc is not None:
            self._proc.terminate()
            self._notify_log("[docket] stop requested")
        else:
            self._notify_log("[docket] no active run")


def run_tui(registry: str | None = None) -> int:
    DocketApp(registry=registry).run()
    return 0
