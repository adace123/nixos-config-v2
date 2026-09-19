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
from dataclasses import dataclass, field, replace

from .config import Config
from .herdr import Herdr, Result, Workspace, Worktree
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
    # Provision (or reuse) a git worktree for this run, so two cards on the
    # same repo never share one checkout. `worktree_path` and friends are the
    # card's own record of a checkout it already has: with `worktree` set, a
    # re-dispatch reopens or reuses it instead of forking a second one.
    worktree: bool = False
    worktree_path: str = ""
    worktree_branch: str = ""
    worktree_workspace_id: str = ""

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
    # The checkout a worktree dispatch provisioned (empty otherwise). Recorded
    # even when a later step failed, so a card that owns a worktree can always
    # clean it up.
    worktree_path: str = ""
    worktree_branch: str = ""
    worktree_workspace_id: str = ""
    error: str = ""

    def detail(self) -> str:
        parts = [f"{step.label}: {step.detail}" for step in self.steps if step.detail]
        if self.error:
            parts.append(self.error)
        return " · ".join(parts)


CLI = "herdr-kanban"

# The tab a dispatch opens exists to host an agent, not to be a dev session, and
# the shell it launches is interactive: in this repo the direnv hook would load
# the flake dev shell there — seconds of `nix print-dev-env` and the dev-shell
# banner printed into the pane — while herdr's `agent start` waits for that same
# shell to reach a prompt. The marker lets shell config skip the hook for a pane
# that only ever runs an agent (modules/home/zsh.nix, docs/kanban.md).
DISPATCH_ENV: dict[str, str] = {"HERDR_KANBAN_DISPATCH": "1"}

# How long to wait for an agent to react to a prompt before assuming it did not.
# herdr considers an agent "ready for interactive input" before every agent's
# input handler agrees, and a prompt written in that window sits in the composer
# unsubmitted while `agent prompt` still reports success.
PROMPT_CONFIRM_SECONDS = 6.0
PROMPT_POLL_SECONDS = 0.35

PROTOCOL_TEMPLATE = """---
herdr kanban: this card is {task_id}. Keep it current as you work:
  finished?        {cli} status {review}
  waiting on me?   {cli} block "what you need"
  worth noting?    {cli} note "what you found or changed"
  name this card:  {cli} title "<concise title, once you know the real work>"
  found more work? {cli} add "<title>" --notes "why it is separate"
Run those from this pane — no task id needed, the board finds the card by its
pane. Move it to {review} when the work is ready for me; only I close cards.
If you find unrelated work, add a card for it instead of doing it here. If the
board says a card already covers it, note that one instead of filing a second."""


def protocol_block(task_id: str, cli: str = CLI, review: str = "review") -> str:
    """How an agent keeps its own card current (appended to the prompt).

    `review` is the board's own review column (`Config.review_column`), so the
    command an agent is told to run names the column this board actually has
    rather than a literal `review` that a rename would make fail.
    """
    return PROTOCOL_TEMPLATE.format(task_id=task_id, cli=cli, review=review)


def tab_label_for(task: Task) -> str:
    """The tab label a dispatch of `task` creates (and the app closes by)."""
    return f"{task.id} {truncate(task.title, 28)}"


def retitle_tab(store: Store, task: Task, herdr: Herdr | None = None) -> str:
    """Rename a card's dispatched tab to match its title; return "" on success.

    The tab is the board's, not the agent's, so the two names a card has — the
    one on the column and the one in herdr's tab bar — are kept in step here
    rather than by asking the agent to remember. Leaving it behind is worse than
    untidy: `KanbanApp.agent_tab` recognises its own tab by the label it last
    wrote, so a tab still labelled with the old title would look repurposed, and
    deleting the card would leave its agent running.

    The label is written back onto the card only when herdr accepted it, so a
    rename that never landed (herdr not answering, the tab closed by hand) does
    not record a label that is not on the tab. Returns the error text, or ""
    when there was nothing to do or the rename worked.
    """
    if not task.tab_id:
        return ""
    label = tab_label_for(task)
    if label == task.tab_label:
        return ""
    result = (herdr or Herdr()).rename_tab(task.tab_id, label)
    if not result.ok:
        return result.error_text()
    store.update(task.id, tab_label=label)
    return ""


def build_prompt(task: Task, config: Config | None = None) -> str:
    """The text handed to the agent: the task, then the board protocol."""
    parts = [task.title]
    notes = (task.notes or "").strip()
    if notes:
        parts.append(notes)
    if config is None or config.announce_protocol:
        # `or "review"` keeps the default board's prompt byte-for-byte what it
        # has always been (and what docs/kanban.md quotes) when the board has no
        # column to call Review.
        review = config.review_column if config is not None else "review"
        parts.append(protocol_block(task.id, review=review or "review"))
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
        # A card that already has a checkout defaults to using it: the checkout
        # is where its work lives, so a re-send that dropped it would scatter
        # one card's work across two checkouts. The form and `send --worktree`
        # can still turn it off for the run.
        worktree=bool(task.worktree_path),
        worktree_path=task.worktree_path,
        worktree_branch=task.worktree_branch,
        worktree_workspace_id=task.worktree_workspace_id,
    )


def worktree_from_result(result: Result) -> Worktree:
    """The `Worktree` a `worktree create`/`open` result describes.

    `open_workspace_id` is present on the worktree record, but a just-created
    one can report it only on the `workspace` object, so the workspace id is
    filled in from there when the worktree record is missing it.
    """
    payload = result.data
    raw = payload.get("worktree")
    worktree = (
        Worktree.from_dict(raw)
        if isinstance(raw, dict)
        else Worktree("", "", "", False)
    )
    if not worktree.workspace_id:
        workspace = payload.get("workspace")
        if isinstance(workspace, dict):
            worktree = replace(
                worktree, workspace_id=str(workspace.get("workspace_id") or "")
            )
    return worktree


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
        # The label `tab create` was handed, recorded on the card: it is what
        # the board matches against to tell its own tab from a repurposed one
        # (`KanbanApp.agent_tab`). Only a tab this dispatch created — a re-prompt
        # of a running agent did not write a label, so the one standing on the
        # card stays the truth for the tab it points at.
        if not plan.reuses_running_agent and plan.tab_label:
            fields["tab_label"] = plan.tab_label
    # Only written when this run actually has a worktree: a dispatch into the
    # card's own workspace must not erase the record of a checkout the card
    # still owns (that record is how the card is cleaned up later).
    if outcome.worktree_path:
        fields["worktree_path"] = outcome.worktree_path
    if outcome.worktree_branch:
        fields["worktree_branch"] = outcome.worktree_branch
    if outcome.worktree_workspace_id:
        fields["worktree_workspace_id"] = outcome.worktree_workspace_id
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

        # 2b. A worktree, when this run asked for one: fork (or reopen) a
        #     checkout of the repo the card sits in, and target that workspace
        #     from here on. Two cards on one repo then never share a checkout.
        target_workspace_id = plan.workspace_id
        target_cwd = self._workspace_cwd(plan.workspace_id)
        worktree_fields: dict[str, object] = {}
        if plan.worktree:
            worktree, error = self._provision_worktree(plan, workspaces, step)
            if error:
                return Outcome(False, steps, error=error)
            target_workspace_id = worktree.workspace_id or plan.workspace_id
            target_cwd = worktree.path or target_cwd
            worktree_fields = {
                "worktree_path": worktree.path,
                "worktree_branch": worktree.branch,
                "worktree_workspace_id": worktree.workspace_id,
            }

        # 3. A fresh tab gives us a shell pane that is safe to start an agent in
        #    (an existing pane may be mid-command, and agent start requires a
        #    prompt).
        result = self.herdr.create_tab(
            target_workspace_id,
            label=plan.tab_label,
            cwd=target_cwd,
            focus=False,
            env=DISPATCH_ENV,
        )
        if not result.ok:
            step("tab", result.error_text(), ok=False)
            return Outcome(False, steps, error=result.error_text(), **worktree_fields)
        tab = result.data.get("tab") or {}
        root = result.data.get("root_pane") or {}
        tab_id = str(tab.get("tab_id") or "")
        pane_id = str(root.get("pane_id") or "")
        step("tab", f"{tab_id} {plan.tab_label}".strip())

        if not pane_id:
            message = "herdr did not return a pane for the new tab"
            step("pane", message, ok=False)
            return Outcome(
                False, steps, tab_id=tab_id, error=message, **worktree_fields
            )

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
                **worktree_fields,
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
            **worktree_fields,
        )

    def _provision_worktree(
        self, plan: Plan, workspaces: list[Workspace], step: Callable[..., Step]
    ) -> tuple[Worktree, str]:
        """Fork (or reopen) the checkout this plan asked for. (worktree, error).

        A card that already has a checkout gets that one back: herdr still has
        the workspace open, or the checkout is on disk and `worktree open` can
        put it back. Only a card with no checkout gets a fresh fork, and a
        reopen that fails (the path was removed by hand) falls back to one
        rather than stranding the dispatch.
        """
        if plan.worktree_workspace_id:
            for workspace in workspaces:
                if workspace.id != plan.worktree_workspace_id:
                    continue
                reused = Worktree(
                    plan.worktree_path, plan.worktree_branch, workspace.id, True
                )
                step("worktree", f"reusing {plan.worktree_path or workspace.id}")
                return reused, ""

        if plan.worktree_path:
            result = self.herdr.open_worktree(
                plan.worktree_path,
                workspace_id=plan.workspace_id,
                label=plan.tab_label,
            )
            action = "reopened"
            if not result.ok:
                step("worktree", f"{result.error_text()} — forking a new checkout")
                result = self.herdr.create_worktree(
                    workspace_id=plan.workspace_id, label=plan.tab_label
                )
                action = "created"
        else:
            result = self.herdr.create_worktree(
                workspace_id=plan.workspace_id, label=plan.tab_label
            )
            action = "created"

        if not result.ok:
            step("worktree", result.error_text(), ok=False)
            return Worktree("", "", "", False), result.error_text()
        worktree = worktree_from_result(result)
        if not worktree.workspace_id:
            message = "herdr did not return a workspace for the new worktree"
            step("worktree", message, ok=False)
            return Worktree("", "", "", False), message
        step("worktree", f"{action} {worktree.path} ({worktree.branch})".strip())
        return worktree, ""

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
    "DISPATCH_ENV",
    "tab_label_for",
    "Executor",
    "Outcome",
    "Plan",
    "Step",
    "build_prompt",
    "plan_for",
    "protocol_block",
    "result_summary",
    "retitle_tab",
    "worktree_from_result",
]
