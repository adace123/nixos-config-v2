"""Starting work for a card: create a pane in the card's workspace, start the
agent, submit the prompt.

Kept out of the UI so the sequence (and its failure modes) can be reasoned about
and tested on its own. Every herdr call is reported as a `Step`, so the board can
show the user exactly how far a dispatch got before it stopped — an
`agent_not_ready` half-way through is a different situation from a failed
workspace lookup.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from dataclasses import dataclass, field

from .config import Config
from .herdr import Herdr
from .model import LiveState
from .render import truncate
from .store import Store, Task


@dataclass
class Plan:
    task_id: str
    workspace_id: str
    workspace_label: str
    kind: str
    name: str
    prompt: str
    tab_label: str = ""
    args: tuple[str, ...] = ()
    # The model this card asked for, kept on the plan so the send form can
    # re-derive `args` when its agent kind is changed (see `agent_args`).
    model: str = ""
    reuse_target: str = ""
    reuse_name: str = ""
    reuse_pane: str = ""
    reuse_tab: str = ""

    @property
    def reuses_running_agent(self) -> bool:
        return bool(self.reuse_target)


@dataclass
class Step:
    label: str
    detail: str = ""
    ok: bool = True


@dataclass
class Outcome:
    ok: bool
    steps: list[Step] = field(default_factory=list)
    agent_name: str = ""
    pane_id: str = ""
    tab_id: str = ""
    error: str = ""

    def detail(self) -> str:
        parts = [f"{step.label}: {step.detail}" for step in self.steps if step.detail]
        if self.error:
            parts.append(self.error)
        return " · ".join(parts)


CLI = "herdr-kanban"

# How long to wait for an agent to react to a prompt before assuming it did not.
# herdr considers an agent "ready for interactive input" before every agent's
# input handler agrees, and a prompt written in that window sits in the composer
# unsubmitted while `agent prompt` still reports success.
PROMPT_CONFIRM_SECONDS = 6.0
PROMPT_POLL_SECONDS = 0.35

PROTOCOL_TEMPLATE = """---
herdr kanban: this card is {task_id}. Keep it current as you work:
  finished?        {cli} status review
  waiting on me?   {cli} block "what you need"
  worth noting?    {cli} note "what you found or changed"
  name this card:  {cli} title "<concise title, once you know the real work>"
  found more work? {cli} add "<title>" --notes "why it is separate"
Run those from this pane — no task id needed, the board finds the card by its
pane. Move it to review when the work is ready for me; only I close cards.
If you find unrelated work, add a card for it instead of doing it here. If the
board says a card already covers it, note that one instead of filing a second."""


def protocol_block(task_id: str, cli: str = CLI) -> str:
    """How an agent keeps its own card current (appended to the prompt)."""
    return PROTOCOL_TEMPLATE.format(task_id=task_id, cli=cli)


def tab_label_for(task: Task) -> str:
    """The tab label a dispatch of `task` creates (and the app closes by)."""
    return f"{task.id} {truncate(task.title, 28)}"


def build_prompt(task: Task, config: Config | None = None) -> str:
    """The text handed to the agent: the task, then the board protocol."""
    parts = [task.title]
    notes = (task.notes or "").strip()
    if notes:
        parts.append(notes)
    if config is None or config.announce_protocol:
        parts.append(protocol_block(task.id))
    return "\n\n".join(parts)


def agent_args(config: Config, kind: str, model: str = "") -> tuple[str, ...]:
    """The flags `agent start` gets for `kind`, with the card's `model` applied.

    A model on the card *replaces* a `--model` pair in the kind's configured
    args rather than being appended to it: two of them in one argv is a last-wins
    coin toss, not a preference, and `--model=sonnet` is the same flag spelled the
    other way. Kinds whose CLI has no such flag simply have no `--model` to
    replace — the value is passed verbatim either way, and a name the CLI rejects
    fails at `agent start`, where the board reports the step that broke.
    """
    args = list(config.agent_args_for(kind))
    if not model:
        return tuple(args)
    kept: list[str] = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--model":
            index += 2  # the flag and the name it takes
            continue
        if arg.startswith("--model="):
            index += 1
            continue
        kept.append(arg)
        index += 1
    return tuple([*kept, "--model", model])


def plan_for(
    task: Task,
    config: Config,
    live: LiveState,
    fallback_workspace: str = "",
    fallback_kind: str = "",
) -> Plan:
    """Decide what a dispatch of `task` would do, without doing any of it."""
    agent = live.lookup(task)

    kind = task.agent_kind or fallback_kind or config.default_agent
    workspace_id = task.workspace_id or fallback_workspace
    workspace_label = (
        live.workspaces[workspace_id].label
        if workspace_id in live.workspaces
        else task.workspace_label or workspace_id
    )

    # No collision check here: herdr rejects a duplicate live name itself and
    # the executor reports that as a step. The names herdr *reports* are kind
    # labels ("pi"), not the names we started agents with, so anything derived
    # from them would be comparing against the wrong set.
    name = task.slug[:32]

    return Plan(
        task_id=task.id,
        workspace_id=workspace_id,
        workspace_label=workspace_label,
        kind=kind,
        name=name,
        prompt=build_prompt(task, config),
        tab_label=tab_label_for(task),
        args=agent_args(config, kind, task.agent_model),
        model=task.agent_model,
        # Prompt an agent that is already running by its pane: herdr accepts a
        # pane ID everywhere it accepts a live agent name, and the reported
        # `agent` value is a kind label, not the name we started it with.
        reuse_target=(agent.pane_id or agent.name) if agent else "",
        reuse_name=agent.name if agent else "",
        reuse_pane=agent.pane_id if agent else "",
        reuse_tab=agent.tab_id if agent else "",
    )


def dispatch_fields(plan: Plan, outcome: Outcome) -> dict[str, object]:
    """The card fields a dispatch outcome implies (pane, tab, name, time)."""
    fields: dict[str, object] = {"workspace_id": plan.workspace_id}
    if plan.workspace_label:
        fields["workspace_label"] = plan.workspace_label
    if outcome.agent_name:
        fields["agent_name"] = outcome.agent_name
    if outcome.pane_id:
        fields["pane_id"] = outcome.pane_id
        fields["dispatched_at"] = time.time()
    if outcome.tab_id:
        fields["tab_id"] = outcome.tab_id
    return fields


def record_outcome(
    store: Store, task_id: str, plan: Plan, outcome: Outcome, target: str
) -> Task | None:
    """Write what a dispatch did onto its card, and move it when it worked.

    One implementation for the board and for `herdr-kanban send`, because "sent"
    has to mean the same thing whether a key or a script did it: which pane and
    tab belong to the run, which agent name to look for later, and which column
    the card lands in. A dispatch that failed records what it learned (a pane
    that did open, say) but does not claim the card is in progress.
    """
    fields = dispatch_fields(plan, outcome)
    if outcome.ok and target:
        return store.hand_over(task_id, target, **fields)
    return store.update(task_id, **fields)


class Executor:
    """Runs a `Plan` against herdr, reporting each step as it goes."""

    def __init__(self, herdr: Herdr) -> None:
        self.herdr = herdr

    def run(self, plan: Plan, on_step: Callable[[Step], None] | None = None) -> Outcome:
        steps: list[Step] = []

        def step(label: str, detail: str = "", ok: bool = True) -> Step:
            entry = Step(label, detail, ok)
            steps.append(entry)
            if on_step is not None:
                on_step(entry)
            return entry

        # 1. An agent already running for this card: just hand it more work.
        if plan.reuses_running_agent:
            step(
                "workspace",
                f"{plan.workspace_label or plan.workspace_id} (reusing agent)",
            )
            handed_over, error = self._hand_over(plan.reuse_target, plan.prompt, step)
            return Outcome(
                handed_over,
                steps,
                agent_name=plan.reuse_name,
                pane_id=plan.reuse_pane,
                tab_id=plan.reuse_tab,
                error=error,
            )

        # 2. Check the target workspace still exists before touching anything.
        if not plan.workspace_id:
            step("workspace", "the task has no workspace", ok=False)
            return Outcome(False, steps, error="no workspace on this task")

        workspaces, result = self.herdr.workspaces()
        if not result.ok:
            step("workspace", result.error_text(), ok=False)
            return Outcome(False, steps, error=result.error_text())
        workspace = next((w for w in workspaces if w.id == plan.workspace_id), None)
        if workspace is None:
            message = f"workspace {plan.workspace_id} is not open"
            step("workspace", message, ok=False)
            return Outcome(False, steps, error=message)
        step("workspace", f"{workspace.label} ({workspace.id})")

        # 3. A fresh tab gives us a shell pane that is safe to start an agent in
        #    (an existing pane may be mid-command, and agent start requires a
        #    prompt).
        result = self.herdr.create_tab(
            plan.workspace_id,
            label=plan.tab_label,
            cwd=self._workspace_cwd(plan.workspace_id),
            focus=False,
        )
        if not result.ok:
            step("tab", result.error_text(), ok=False)
            return Outcome(False, steps, error=result.error_text())
        tab = result.data.get("tab") or {}
        root = result.data.get("root_pane") or {}
        tab_id = str(tab.get("tab_id") or "")
        pane_id = str(root.get("pane_id") or "")
        step("tab", f"{tab_id} {plan.tab_label}".strip())

        if not pane_id:
            message = "herdr did not return a pane for the new tab"
            step("pane", message, ok=False)
            return Outcome(False, steps, tab_id=tab_id, error=message)

        # 4. Start the agent in that pane (with whatever flags the config
        #    gives this kind).
        result = self.herdr.start_agent(plan.name, plan.kind, pane_id, args=plan.args)
        if not result.ok:
            step("agent", result.error_text(), ok=False)
            return Outcome(
                False,
                steps,
                pane_id=pane_id,
                tab_id=tab_id,
                error=result.error_text(),
            )
        step("agent", f"{plan.name} ({plan.kind}) ready in {pane_id}")
        if plan.args:
            step("flags", " ".join(plan.args))

        # 5. Hand it the work, and make sure it actually took.
        handed_over, error = self._hand_over(plan.name, plan.prompt, step)
        return Outcome(
            handed_over,
            steps,
            agent_name=plan.name,
            pane_id=pane_id,
            tab_id=tab_id,
            error=error,
        )

    def _hand_over(
        self, target: str, prompt: str, step: Callable[..., Step]
    ) -> tuple[bool, str]:
        """Prompt `target` and confirm the agent started a turn.

        `agent prompt` succeeds once the text *and* the Enter have been written,
        which is not the same as the agent acting on them: prompt pi in the
        moment before its input handler is live and the text is left sitting in
        its composer, the pane stays idle, and a board that trusted the call
        would mark the card as started while nothing runs.

        The signal is the agent lifecycle: a started turn shows `working` or
        `blocked`, or a moved `state_change_seq` if it already finished. If
        nothing happens, the text is submitted with a bare Enter — which is what
        a human would press — and only then is the dispatch called a failure, so
        the card is not marked as in progress.
        """
        before = self.herdr.agent_state(target)
        result = self.herdr.prompt_agent(target, prompt)
        if not result.ok:
            step("prompt", result.error_text(), ok=False)
            return False, result.error_text()
        if self._await_reaction(target, before):
            step("prompt", "task submitted")
            return True, ""

        step("prompt", "text written but the agent did not start — pressing Enter")
        self.herdr.send_keys(target, "enter")
        if self._await_reaction(target, before):
            step("prompt", "task submitted")
            return True, ""

        message = (
            f"{target} received the prompt but never started; its pane is still"
            " open with the text in it — press Enter there, or check the pane"
        )
        step("prompt", message, ok=False)
        return False, message

    def _await_reaction(self, target: str, before: tuple[str, int]) -> bool:
        """True once the agent is working, blocked, or has changed state."""
        deadline = time.monotonic() + PROMPT_CONFIRM_SECONDS
        while True:
            status, seq = self.herdr.agent_state(target)
            if status in ("working", "blocked"):
                return True
            if status and seq != before[1]:
                return True  # it reacted; it may already have finished
            if time.monotonic() >= deadline:
                return False
            time.sleep(PROMPT_POLL_SECONDS)

    def _workspace_cwd(self, workspace_id: str) -> str:
        panes, result = self.herdr.panes(workspace_id)
        if not result.ok:
            return ""
        for pane in panes:
            if pane.cwd:
                return pane.cwd
        return ""


def result_summary(outcome: Outcome) -> str:
    if outcome.ok:
        return (
            f"dispatched to {outcome.agent_name}"
            if outcome.agent_name
            else "dispatched"
        )
    return outcome.error or "dispatch failed"


__all__ = [
    "CLI",
    "tab_label_for",
    "Executor",
    "Outcome",
    "Plan",
    "Step",
    "build_prompt",
    "plan_for",
    "protocol_block",
    "result_summary",
]
