"""Modal screens: the add/edit form, task detail, dispatch, filter, help, confirm.

Every dialog follows the same shape — a centred box with a title, a body, a hint
line, and buttons — so the board's chrome stays consistent and each screen only
declares what it adds.
"""

from __future__ import annotations

import contextlib
from collections.abc import Iterator
from dataclasses import dataclass, replace
from typing import TYPE_CHECKING, cast

from textual import events, work
from textual.app import ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical, VerticalScroll
from textual.css.query import NoMatches
from textual.screen import ModalScreen
from textual.widgets import Button, Input, Select, Static, TextArea

from . import icons
from .config import Config
from .dispatch import Plan, agent_args
from .herdr import Herdr, Workspace
from .render import format_age, truncate
from .store import Task

if TYPE_CHECKING:  # pragma: no cover - typing only
    from .app import KanbanApp

PRIORITY_ORDER = ("urgent", "high", "normal", "low")


@dataclass
class TaskDraft:
    """Form output: the fields a user can set."""

    title: str
    notes: str
    status: str
    workspace_id: str
    workspace_label: str
    agent_kind: str
    priority: str
    labels: list[str]
    # The model the card asks for, as the CLI names it. Empty = the kind's own
    # configured args decide (see `dispatch.agent_args`).
    agent_model: str = ""
    # The add form's "Send now": write the card down and start its agent in one
    # keystroke. Always False from the edit form — an edit is not a dispatch.
    send_now: bool = False


class Dialog(ModalScreen):
    """Shared chrome for the board's dialogs."""

    BINDINGS = [Binding("escape", "cancel", "cancel", show=False)]

    box_id = "dialog"

    def dialog_title(self) -> str:
        return ""

    def hint_text(self) -> str:
        return ""

    def build_body(self) -> Iterator[object]:
        return iter(())

    def build_buttons(self) -> Iterator[object]:
        yield Button("Close", variant="primary", id="close")

    def compose(self) -> ComposeResult:
        with Vertical(id=self.box_id):
            yield Static(self.dialog_title(), id="dialog-title")
            with VerticalScroll(id="dialog-body"):
                yield from self.build_body()
            hint = self.hint_text()
            if hint:
                yield Static(hint, id="dialog-hint")
            with Horizontal(id="dialog-buttons"):
                yield from self.build_buttons()

    def action_cancel(self) -> None:
        self.dismiss(None)

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "close":
            self.dismiss(None)


# Box drawing, block elements and the rules a TUI draws with.
_CHROME = " \t│┃║╭╮╰╯┌┐└┘├┤┬┴┼─━═╌╍▏▕▁▔░▒▓"


def _tidy_pane_text(text: str) -> str:
    """Turn raw terminal output into something readable.

    A pane is a screen, not a document: it comes back with boxes, rule lines,
    status bars and vertical padding. Drop the lines that are only chrome, strip
    the borders off the ones that carry words, and squeeze blank runs.
    """
    kept: list[str] = []
    blanks = 0
    for line in text.splitlines():
        stripped = line.strip(_CHROME)
        if not stripped or not any(ch.isalnum() for ch in stripped):
            blanks += 1
            if blanks <= 1 and kept:
                kept.append("")
            continue
        blanks = 0
        kept.append(stripped)
    while kept and not kept[-1]:
        kept.pop()
    return "\n".join(kept[-40:]) or "(no output yet)"


# -- add / edit --------------------------------------------------------------


def workspace_options(
    workspaces: list[Workspace],
    task: Task | None = None,
    extra_id: str = "",
    extra_label: str = "",
) -> list[tuple[str, str]]:
    """Select options for the live workspaces, plus any we must still offer.

    `Select` raises if handed a value that is not among its options, so an id we
    were seeded with — the card's own workspace, or the one the board was opened
    from — has to be added explicitly. Without this, opening a dialog while
    herdr is unreachable (no workspaces listed at all) takes the dialog down.
    """
    options: list[tuple[str, str]] = [
        (f"{workspace.number}. {workspace.label}", workspace.id)
        for workspace in workspaces
    ]
    for candidate, label in (
        (task.workspace_id if task else "", task.workspace_label if task else ""),
        (extra_id, extra_label),
    ):
        if candidate and not any(value == candidate for _, value in options):
            options.append((f"(unavailable) {label or candidate}", candidate))
    return options


def agent_options(mode: str, selected: str = "") -> list[tuple[str, str]]:
    options = [
        (f"{icons.agent_glyph(kind, mode)}  {label}  ({kind})", kind)
        for kind, label in icons.AGENT_KINDS
    ]
    if selected and not any(value == selected for _, value in options):
        options.insert(
            0, (f"{icons.agent_glyph(selected, mode)}  {selected}", selected)
        )
    return options


def model_options(
    config: Config, kind: str, selected: str = ""
) -> list[tuple[str, str]]:
    """The Model select's options for one agent kind.

    `default` is always first and always means "say nothing about the model":
    `[agents.<kind>] args` already carries whatever you run that CLI with
    interactively, and a card should not have to repeat it. Only kinds with a
    `[models]` list get anything else, and a value that is not on the list (an
    older card, or one you typed into the config and then removed) is inserted
    rather than silently dropped — `Select` raises on a value it does not have.
    """
    options: list[tuple[str, str]] = [("·  default", "")]
    options += [(name, name) for name in config.models_for(kind)]
    if selected and not any(value == selected for _, value in options):
        options.append((f"{selected}  (not in [models])", selected))
    return options


class TaskFormModal(Dialog):
    """Add a task, or edit an existing one. Both fields and defaults are shared."""

    BINDINGS = [
        Binding("escape", "cancel", "cancel", show=False),
        Binding("ctrl+s", "save", "save", show=False),
        Binding("ctrl+n", "send_now", "send now", show=False),
    ]

    def __init__(
        self,
        config: Config,
        workspaces: list[Workspace],
        mode: str = "brand",
        task: Task | None = None,
        default_workspace: str = "",
        default_kind: str = "",
        default_workspace_label: str = "",
    ) -> None:
        super().__init__()
        self.config = config
        self.workspaces = workspaces
        self.icon_mode = mode
        self.subject = task
        self.default_workspace = default_workspace
        self.default_kind = default_kind
        self.default_workspace_label = default_workspace_label
        self.box_id = "task-form"

    def dialog_title(self) -> str:
        if self.subject is None:
            return "＋  New task"
        return f"✎  Edit {self.subject.id}"

    def hint_text(self) -> str:
        if self.subject is not None:
            return "⏎ in the title saves  ·  ^s saves  ·  esc cancels"
        return "⏎ in the title saves  ·  ^s saves  ·  ^n sends now  ·  esc cancels"

    def build_body(self) -> Iterator[object]:
        task = self.subject
        workspace_id = (task.workspace_id if task else self.default_workspace) or ""
        kind = (
            (task.agent_kind if task else "")
            or self.default_kind
            or (self.config.default_agent)
        )
        status = (task.status if task else "") or self.config.default_column
        priority = (task.priority if task else "") or "normal"

        yield Static("Title", classes="field-label")
        yield Input(
            value=task.title if task else "",
            placeholder="what needs doing?",
            id="field-title",
        )
        yield Static("Notes", classes="field-label")
        yield TextArea(task.notes if task else "", id="field-notes")

        yield Static("Workspace", classes="field-label")
        options = workspace_options(
            self.workspaces,
            task,
            extra_id=workspace_id,
            extra_label=self.default_workspace_label,
        )
        if not options:
            yield Static(
                "no open herdr workspaces — open one, then add the task",
                classes="field-note",
            )
        yield Select(
            options,
            prompt="no workspace",
            allow_blank=True,
            value=workspace_id or Select.NULL,
            id="field-workspace",
        )

        with Horizontal(classes="field-row"):
            with Vertical(classes="field-col"):
                yield Static("Agent", classes="field-label")
                yield Select(
                    agent_options(self.icon_mode, kind),
                    allow_blank=False,
                    value=kind,
                    id="field-agent",
                )
            with Vertical(classes="field-col"):
                # Beside the agent it belongs to, and in the row that already
                # existed: model names are per CLI, so the two fields are one
                # answer and reading them apart would be working against that.
                yield Static("Model", classes="field-label")
                yield Select(
                    model_options(self.config, kind, task.agent_model if task else ""),
                    allow_blank=False,
                    value=(task.agent_model if task else "") or "",
                    id="field-model",
                )

        with Horizontal(classes="field-row"):
            with Vertical(classes="field-col"):
                yield Static("Column", classes="field-label")
                yield Select(
                    [(column.label, column.id) for column in self.config.columns],
                    allow_blank=False,
                    value=status
                    if any(c.id == status for c in self.config.columns)
                    else self.config.columns[0].id,
                    id="field-status",
                )
            with Vertical(classes="field-col"):
                yield Static("Priority", classes="field-label")
                yield Select(
                    [
                        (
                            f"{icons.priority_glyph(value) or '·'}  {value}",
                            value,
                        )
                        for value in PRIORITY_ORDER
                    ],
                    allow_blank=False,
                    value=priority,
                    id="field-priority",
                )
        yield Static("Labels", classes="field-label")
        yield Input(
            value=", ".join(task.labels) if task else "",
            placeholder="comma separated, optional",
            id="field-labels",
        )

    def build_buttons(self) -> Iterator[object]:
        yield Button("Save", variant="primary", id="save")
        # Only when adding: sending a card that already exists is the board's own
        # `s`, with its dispatch form and its wip warning.
        if self.subject is None:
            yield Button("Send now", variant="success", id="send-now")
        yield Button("Cancel", id="cancel")

    def on_mount(self) -> None:
        self.query_one("#field-title", Input).focus()

    def on_select_changed(self, event: Select.Changed) -> None:
        """Keep the model list in step with the agent it belongs to.

        The two fields are one answer: model names are per CLI, so switching the
        agent has to offer that CLI's names — and if the model already chosen is
        not one of them, `Select.set_options` falls back to the first entry,
        which is `default`. That is the right outcome: a model the newly chosen
        agent has never heard of would fail at `agent start`.
        """
        if event.select.id != "field-agent":
            return
        model = self.query_one("#field-model", Select)
        model.set_options(model_options(self.config, str(event.value)))

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "save":
            self.action_save()
        elif event.button.id == "send-now":
            self.action_send_now()
        elif event.button.id == "cancel":
            self.dismiss(None)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if event.input.id == "field-title":
            self.action_save()

    def action_save(self) -> None:
        self._submit(send_now=False)

    def action_send_now(self) -> None:
        """Save the card and start its agent (the add form's `^n`).

        On the edit form there is nothing to send — the card may already have an
        agent, and re-prompting one is the board's `s` — so `^n` there saves,
        which is the one thing the key can usefully mean.
        """
        self._submit(send_now=self.subject is None)

    def _submit(self, send_now: bool) -> None:
        title = self.query_one("#field-title", Input).value.strip()
        if not title:
            self.query_one("#field-title", Input).focus()
            self.notify("a task needs a title", severity="warning")
            return

        workspace = self.query_one("#field-workspace", Select).value
        workspace_id = (
            "" if workspace is Select.NULL or workspace is None else str(workspace)
        )
        label = next(
            (w.label for w in self.workspaces if w.id == workspace_id),
            self.default_workspace_label or workspace_id,
        )
        if self.subject is not None and workspace_id == self.subject.workspace_id:
            label = self.subject.workspace_label or label

        self.dismiss(
            TaskDraft(
                title=title,
                notes=self.query_one("#field-notes", TextArea).text.strip(),
                status=str(self.query_one("#field-status", Select).value),
                workspace_id=workspace_id,
                workspace_label=label,
                agent_kind=str(self.query_one("#field-agent", Select).value),
                agent_model=str(self.query_one("#field-model", Select).value),
                priority=str(self.query_one("#field-priority", Select).value),
                labels=[
                    part.strip()
                    for part in self.query_one("#field-labels", Input).value.split(",")
                    if part.strip()
                ],
                send_now=send_now,
            )
        )


# -- detail ------------------------------------------------------------------


class TaskDetailModal(Dialog):
    """Everything about one task, plus the live agent's recent output."""

    BINDINGS = [
        Binding("escape,q", "cancel", "close", show=False),
        Binding("s", "dispatch", "send", show=False),
        Binding("e", "edit", "edit", show=False),
        Binding("f", "focus_agent", "agent", show=False),
        Binding("x", "close_agent", "stop agent", show=False),
        Binding("o", "focus_workspace", "workspace", show=False),
        Binding("r", "toggle_tail", "agent output", show=False),
        Binding("d", "delete", "delete", show=False),
    ]

    def __init__(
        self,
        task: Task,
        config: Config,
        herdr: Herdr,
        live_status: str = "",
        agent_online: bool = False,
        workspace_label: str = "",
        workspace_ok: bool = True,
        icon_mode: str = "brand",
        agent_title: str = "",
        interval: float = 2.0,
    ) -> None:
        super().__init__()
        self.subject = task
        self.config = config
        self.herdr = herdr
        self.interval = max(0.5, interval)
        self._polls = 0
        # The raw pane is a terminal, not a report: it arrives full of box
        # drawing, status bars and rewrapped text. Hidden unless asked for.
        self.show_tail = False
        self.live_status = live_status
        self.agent_online = agent_online
        self.workspace_label = workspace_label
        self.workspace_ok = workspace_ok
        self.icon_mode = icon_mode
        self.agent_title = agent_title

    @property
    def target(self) -> str:
        # Pane first: herdr accepts a pane ID anywhere it accepts a live agent
        # name, and its reported `agent` value is a kind label, not our name.
        return self.subject.pane_id or self.subject.agent_name

    def dialog_title(self) -> str:
        return f"{self.subject.id}  {truncate(self.subject.title, 60)}"

    def hint_text(self) -> str:
        steps = "1-9 tick a step · " if self.subject.steps else ""
        return (
            f"{steps}s send · e edit · f agent · o workspace · x stop agent"
            " · r agent output · d delete · esc close"
        )

    @property
    def kanban(self) -> KanbanApp:
        return cast("KanbanApp", self.app)

    def on_key(self, event: events.Key) -> None:
        """Digits tick the matching checklist entry, without reaching for the CLI."""
        if len(event.key) != 1 or not event.key.isdigit() or event.key == "0":
            return
        index = int(event.key)
        if not 1 <= index <= len(self.subject.steps):
            return
        event.stop()
        updated = self.kanban.toggle_step(self.subject.id, index)
        if updated is not None:
            self.subject = updated
            self.refresh_dynamic()

    def refresh_dynamic(self) -> None:
        """Re-draw the parts a step tick or a status move can change."""
        for static_id, render in (
            ("#detail-facts", self._facts),
            ("#detail-label-steps", self._steps_label),
            ("#detail-steps", self._steps),
            ("#detail-history", self._history),
        ):
            with contextlib.suppress(NoMatches):
                self.query_one(static_id, Static).update(render())

    def _steps_label(self) -> str:
        return f"Steps ({self.subject.steps_done}/{len(self.subject.steps)})"

    def _steps(self) -> str:
        lines = []
        for index, step in enumerate(self.subject.steps, start=1):
            mark = "☑" if step.get("done") else "☐"
            who = step.get("by") if step.get("done") else ""
            suffix = f"   ({who})" if who else ""
            lines.append(f"{index}. {mark} {step.get('text', '')}{suffix}")
        return "\n".join(lines)

    def build_body(self) -> Iterator[object]:
        task = self.subject
        yield Static(self._facts(), id="detail-facts")
        if task.notes:
            yield Static("Notes", classes="field-label")
            yield Static(task.notes, id="detail-notes")
        if task.steps:
            yield Static(
                self._steps_label(), classes="field-label", id="detail-label-steps"
            )
            yield Static(self._steps(), id="detail-steps")
        if task.progress:
            yield Static("Updates", classes="field-label")
            yield Static(self._updates(), id="detail-updates")
        if task.history:
            yield Static("History", classes="field-label")
            yield Static(self._history(), id="detail-history")
        if self.target:
            yield Static("Agent output", classes="field-label")
            yield Static("", id="detail-tail")
        else:
            yield Static(
                "no agent has been started for this card yet — press s to send it",
                classes="field-note",
            )

    def _updates(self) -> str:
        lines = []
        for entry in self.subject.progress[-8:]:
            age = format_age(float(entry.get("at") or 0))
            who = str(entry.get("by", "?"))
            lines.append(f"{age:>4} ago  {who:<5}  {entry.get('text', '')}")
        return "\n".join(lines)

    def _history(self) -> str:
        """What happened to the card itself: every column, every rename.

        `Updates` above is what the agent chose to say; this is the board's own
        record — who filed it, when it moved and where, when it was renamed and
        by whom. Worth having on screen because it is the only place the
        difference between "an agent renamed this" and "I renamed this" is
        written down.
        """
        entries = self.subject.history
        shown = entries[-12:]
        lines = []
        if len(entries) > len(shown):
            lines.append(f"      … {len(entries) - len(shown)} earlier")
        for entry in shown:
            age = format_age(float(entry.get("at") or 0))
            lines.append(f"{age:>4} ago  {entry.get('what', '')}")
        return "\n".join(lines)

    def _facts(self) -> str:
        task = self.subject
        if self.live_status:
            state = (
                f"{icons.status_glyph(self.live_status, mode=self.icon_mode)} "
                f"{icons.status_label(self.live_status)}"
            )
            if self.live_status == "exited":
                state += "   (started earlier, not running now)"
        elif task.dispatched_at:
            state = f"{icons.status_glyph('exited', mode=self.icon_mode)} no agent"
        else:
            state = "never started"
        agent = task.agent_kind or "—"
        if self.agent_title:
            agent += f"   running: {self.agent_title}"
        elif task.agent_name:
            agent += f"   ({task.agent_name})"
        rows = [
            f"column   {self.config.label_for(task.status)}"
            + (f"   priority {task.priority}" if task.priority != "normal" else ""),
            f"agent    {agent}"
            + (f"   model {task.agent_model}" if task.agent_model else ""),
            f"state    {state}",
            f"space    {self.workspace_label or '—'}"
            + ("" if self.workspace_ok else "   ⚠ workspace closed"),
            f"pane     {task.pane_id or '—'}   tab {task.tab_id or '—'}",
            f"age      created {format_age(task.created_at)} ago"
            + (" by an agent" if task.created_by == "agent" else "")
            + f"   updated {format_age(task.updated_at)} ago",
        ]
        if task.labels:
            rows.append("labels   " + ", ".join(task.labels))
        if task.parent_id:
            rows.append(f"found    while working on {task.parent_id}")
        children = self.kanban.children_of(task.id)
        if children:
            rows.append(
                "spawned  "
                + ", ".join(
                    f"{child.id} ({self.config.label_for(child.status)})"
                    for child in children
                )
            )
        if task.dispatched_at:
            rows.append(f"sent     {format_age(task.dispatched_at)} ago")
        if task.title_source == "agent" and task.original_title:
            rows.append(
                "title    named by the agent   (was: "
                + truncate(task.original_title, 44)
                + ")"
            )
        return "\n".join(rows)

    def on_mount(self) -> None:
        # A watch view: the board polls in the background anyway, so the card
        # in front of you should not be a frozen snapshot of it. Facts, steps
        # and ages refresh every tick; the agent's own output is a subprocess,
        # so it is re-read every third tick — and only when it is on screen.
        self.set_interval(self.interval, self.poll)
        if self.target:
            self._show_tail(self._tail_hint())

    def poll(self) -> None:
        """Re-read the card and the live state while the dialog is open."""
        self._polls += 1
        updated = self.kanban.task(self.subject.id)
        if updated is not None:
            self.subject = updated
        live = self.kanban.live
        self.live_status, self.agent_online = live.for_task(self.subject)
        self.workspace_label = live.workspace_label(self.subject)
        self.workspace_ok = live.workspace_ok(self.subject)
        agent = live.lookup(self.subject)
        self.agent_title = agent.title if agent else ""
        self.refresh_dynamic()
        if self.show_tail and self.target and self._polls % 3 == 0:
            self.load_tail()

    def _tail_hint(self) -> str:
        return "hidden — press r to show the agent's recent output"

    @work(thread=True, exclusive=True, group="tail")
    def load_tail(self) -> None:
        result = self.herdr.read_agent(self.target, lines=60)
        text = (
            result.text
            if result.ok
            else f"could not read output: {result.error_text()}"
        )
        self.app.call_from_thread(self._show_tail, _tidy_pane_text(text))

    def _show_tail(self, text: str) -> None:
        try:
            self.query_one("#detail-tail", Static).update(text)
        except Exception:  # pragma: no cover - dialog closed while loading
            pass

    def action_toggle_tail(self) -> None:
        """`r`: show the agent's output, or hide it again."""
        if not self.target:
            return
        self.show_tail = not self.show_tail
        if self.show_tail:
            self._show_tail("loading…")
            self.load_tail()
        else:
            self._show_tail(self._tail_hint())

    def action_dispatch(self) -> None:
        self.dismiss("dispatch")

    def action_edit(self) -> None:
        self.dismiss("edit")

    def action_focus_agent(self) -> None:
        self.dismiss("focus_agent")

    def action_close_agent(self) -> None:
        self.dismiss("close_agent")

    def action_focus_workspace(self) -> None:
        self.dismiss("focus_workspace")

    def action_delete(self) -> None:
        self.dismiss("delete")


# -- dispatch ----------------------------------------------------------------


class DispatchModal(Dialog):
    """Confirm and edit what will be sent, then start it."""

    BINDINGS = [
        Binding("escape", "cancel", "cancel", show=False),
        Binding("ctrl+s", "send", "send", show=False),
    ]

    def __init__(
        self,
        plan: Plan,
        config: Config,
        workspaces: list[Workspace],
        icon_mode: str = "brand",
        wip_warning: str = "",
    ) -> None:
        super().__init__()
        self.plan = plan
        self.config = config
        self.workspaces = workspaces
        self.icon_mode = icon_mode
        self.wip_warning = wip_warning
        self.box_id = "dispatch-form"

    def dialog_title(self) -> str:
        return f"⇢  Send {self.plan.task_id} to an agent"

    def hint_text(self) -> str:
        if self.plan.reuses_running_agent:
            return "an agent is already running for this card — this sends it another prompt  ·  ^s send"
        return (
            "opens a new tab in the workspace and starts the agent there; the prompt "
            "ends with the board protocol  ·  ^s send"
        )

    def build_body(self) -> Iterator[object]:
        plan = self.plan
        if self.wip_warning:
            yield Static(self.wip_warning, id="dispatch-wip")
        if plan.reuses_running_agent:
            yield Static(
                f"reusing running agent  {plan.reuse_name or plan.reuse_target}"
                + (f"  in {plan.reuse_pane}" if plan.reuse_pane else ""),
                id="dispatch-reuse",
            )
        else:
            yield Static("Workspace", classes="field-label")
            yield Select(
                workspace_options(
                    self.workspaces,
                    extra_id=plan.workspace_id,
                    extra_label=plan.workspace_label,
                ),
                allow_blank=True,
                value=plan.workspace_id or Select.NULL,
                id="dispatch-workspace",
            )
            yield Static("Agent", classes="field-label")
            yield Select(
                agent_options(self.icon_mode, plan.kind),
                allow_blank=False,
                value=plan.kind,
                id="dispatch-agent",
            )
            yield Static("Agent name", classes="field-label")
            yield Input(value=plan.name, id="dispatch-name")
            # Always rendered, even when there is nothing to pass: the send form
            # can change the agent kind, and that changes the flags.
            yield Static(
                "flags   " + (" ".join(plan.args) or "—"),
                classes="field-note",
                id="dispatch-args",
            )
        yield Static("Prompt", classes="field-label")
        yield TextArea(plan.prompt, id="dispatch-prompt")

    def build_buttons(self) -> Iterator[object]:
        yield Button("Send", variant="primary", id="send")
        yield Button("Cancel", id="cancel")

    def on_mount(self) -> None:
        self.query_one("#dispatch-prompt", TextArea).focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "send":
            self.action_send()
        elif event.button.id == "cancel":
            self.dismiss(None)

    def on_select_changed(self, event: Select.Changed) -> None:
        """Re-derive the flags when the send form's agent kind is changed.

        It used to keep the flags computed for the agent the card was planned
        with, so switching from pi to claude in this form started claude with
        pi's `--model deepseek-v4-flash`. The model on the plan follows the kind:
        a name the new agent has no list entry for is dropped, because sending it
        would be sending a flag the CLI does not understand.
        """
        if event.select.id != "dispatch-agent":
            return
        kind = str(event.value)
        model = (
            self.plan.model if self.plan.model in self.config.models_for(kind) else ""
        )
        self.plan = replace(
            self.plan, kind=kind, model=model, args=agent_args(self.config, kind, model)
        )
        with contextlib.suppress(NoMatches):
            self.query_one("#dispatch-args", Static).update(
                "flags   " + (" ".join(self.plan.args) or "—")
            )

    def action_send(self) -> None:
        plan = self.plan
        prompt = self.query_one("#dispatch-prompt", TextArea).text.strip()
        if not self.plan.reuses_running_agent:
            workspace = self.query_one("#dispatch-workspace", Select).value
            workspace_id = (
                "" if workspace is Select.NULL or workspace is None else str(workspace)
            )
            kind = str(self.query_one("#dispatch-agent", Select).value)
            name = self.query_one("#dispatch-name", Input).value.strip() or plan.name
            label = next(
                (w.label for w in self.workspaces if w.id == workspace_id), workspace_id
            )
            plan = Plan(
                task_id=plan.task_id,
                workspace_id=workspace_id,
                workspace_label=label,
                kind=kind,
                name=name,
                prompt=prompt or plan.prompt,
                tab_label=plan.tab_label,
                args=agent_args(self.config, kind, plan.model),
                model=plan.model,
            )
        else:
            plan = replace(plan, prompt=prompt or plan.prompt)
        self.dismiss(plan)


# -- filter ------------------------------------------------------------------


class FilterModal(Dialog):
    BINDINGS = [
        Binding("escape", "cancel", "cancel", show=False),
        Binding("ctrl+s", "apply", "apply", show=False),
    ]

    def __init__(self, current: str = "") -> None:
        super().__init__()
        self.current = current
        self.box_id = "filter-form"

    def dialog_title(self) -> str:
        return "／  Filter the board"

    def hint_text(self) -> str:
        return (
            "words are ANDed and match title, notes, labels, workspace and agent"
            '  ·  "quoted phrases" match exactly  ·  empty clears'
        )

    def build_body(self) -> Iterator[object]:
        yield Input(value=self.current, placeholder="e.g. flake  pi", id="filter-input")

    def build_buttons(self) -> Iterator[object]:
        yield Button("Apply", variant="primary", id="apply")
        yield Button("Clear", id="clear")
        yield Button("Cancel", id="cancel")

    def on_mount(self) -> None:
        self.query_one("#filter-input", Input).focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "apply":
            self.action_apply()
        elif event.button.id == "clear":
            self.dismiss("")
        elif event.button.id == "cancel":
            self.dismiss(None)

    def on_input_submitted(self, event: Input.Submitted) -> None:
        del event
        self.action_apply()

    def action_apply(self) -> None:
        self.dismiss(self.query_one("#filter-input", Input).value.strip())


# -- help --------------------------------------------------------------------


class HelpModal(Dialog):
    BINDINGS = [
        Binding("escape,q,question_mark", "cancel", "close", show=False),
    ]

    def __init__(
        self, config: Config, board_path: str = "", icon_mode: str = "brand"
    ) -> None:
        super().__init__()
        self.config = config
        self.board_path = board_path
        self.icon_mode = icon_mode
        self.box_id = "help-dialog"

    def dialog_title(self) -> str:
        return "?  herdr kanban"

    def build_body(self) -> Iterator[object]:
        yield Static(
            "\n".join(
                [
                    "[b]Cards[/b] carry a workspace and an agent. Press [b]s[/b] to send one:",
                    "the board opens a tab in that workspace, starts the agent there, and",
                    "hands it the task. The card then shows the agent's real state.",
                    "",
                    "[b]Keys[/b]",
                    "  h l ← →      previous / next column      1-9  jump to column",
                    "  j k ↑ ↓      previous / next card          g G  first / last card",
                    "  H L          move card between columns     J K  reorder inside a column",
                    "  ⏎            detail (with the agent's output)",
                    "  a e d        add / edit / delete a task",
                    "  s            send the card to its agent",
                    "  f o p        focus the agent / workspace / pane in herdr",
                    "  / w c        filter · workspace filter · clear filters",
                    "  !            only the cards whose agents need an answer",
                    "  r ? q        refresh live state · this help · quit",
                    "",
                    "[b]Agent state[/b]",
                    "  ⣷ working   ▲ needs you   ○ idle   ✓ done   ∅ no agent   · unknown",
                    "  ✎          the agent named this card (its capture title is in ⏎)",
                    "  The K3 badge is tinted while an agent is running, the bottom rule",
                    "  spells the state out, and ▴/▾ on a column heading mean more cards",
                    "  than fit: scroll with j / k.",
                    "",
                    "[b]Cards keep themselves current[/b]",
                    "  A dispatched agent is told how to move its own card, with the same",
                    "  binary you are running — and it needs no task id, because the board",
                    "  finds the card from the pane the agent runs in:",
                    "    herdr-kanban status review",
                    '    herdr-kanban block "what it needs from you"',
                    '    herdr-kanban note "…"     (lands in ⏎ under Updates)',
                    '    herdr-kanban title "…"    (only while you have not retitled it)',
                    '    herdr-kanban add "…"      (found work becomes a backlog card,',
                    "                               linked back to this one)",
                    "  Agents may set doing / blocked / review; only you close a card.",
                    "  x stops a card's agent (its tab) without deleting the card; deleting",
                    "  a card stops its agent too.",
                    "",
                    "[b]Where tasks live[/b]",
                    f"  {self.board_path or 'the plugin state directory'}",
                ]
            ),
            id="help-text",
        )


# -- confirm -----------------------------------------------------------------


class ConfirmModal(Dialog):
    BINDINGS = [
        Binding("escape", "cancel", "cancel", show=False),
        Binding("ctrl+s", "confirm", "confirm", show=False),
    ]

    def __init__(
        self,
        title: str,
        message: str,
        confirm_label: str = "Confirm",
        danger: bool = False,
    ) -> None:
        super().__init__()
        self._title = title
        self.message = message
        self.confirm_label = confirm_label
        self.danger = danger
        self.box_id = "confirm-dialog"

    def dialog_title(self) -> str:
        return self._title

    def build_body(self) -> Iterator[object]:
        yield Static(self.message, id="confirm-message")

    def build_buttons(self) -> Iterator[object]:
        yield Button(
            self.confirm_label,
            variant="error" if self.danger else "primary",
            id="confirm",
        )
        yield Button("Cancel", id="cancel")

    def on_mount(self) -> None:
        self.query_one("#confirm" if not self.danger else "#cancel", Button).focus()

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "confirm":
            self.dismiss(True)
        elif event.button.id == "cancel":
            self.dismiss(False)

    def action_confirm(self) -> None:
        self.dismiss(True)


__all__ = [
    "ConfirmModal",
    "DispatchModal",
    "FilterModal",
    "HelpModal",
    "TaskDetailModal",
    "TaskDraft",
    "TaskFormModal",
    "agent_options",
    "workspace_options",
]
