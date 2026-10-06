"""Starting work for a card: create a pane in the card's workspace, start the
agent, submit the prompt.

Kept out of the UI so the sequence (and its failure modes) can be reasoned about
and tested on its own. Every herdr call is reported as a `Step`, so the board can
show the user exactly how far a dispatch got before it stopped — an
`agent_not_ready` half-way through is a different situation from a failed
workspace lookup.
"""

from __future__ import annotations

import re
import time
from collections.abc import Callable
from dataclasses import dataclass, field, replace

from . import git
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
    # The branch a *fresh* fork would get (`feature/<slug>` / `fix/<slug>`).
    # The card's own `worktree_branch` above is the branch it already has; this
    # is read only by the two calls that create a checkout (a first fork, or a
    # reopen that fell back to forking), and is filled in whether or not this
    # plan forks so the send form can tick the box after the plan is built.
    worktree_new_branch: str = ""

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

# The repo's worktree rule asks for `feature/<slug>` or `fix/<slug>`; a title
# that opens with one of these markers is the fix, everything else is a feature.
FIX_MARKERS: tuple[str, ...] = ("fix:", "fix(", "bug:", "bugfix:", "hotfix:")
BRANCH_SLUG_LIMIT = 40

PROTOCOL_TEMPLATE = """---
herdr kanban: this card is {task_id}. Keep it current as you work:
  finished?        {cli} status {review}
  waiting on me?   {cli} block "what you need"
  worth noting?    {cli} note "what you found or changed"
  name this card:  {cli} title "<concise title, once you know the real work>"
  found more work? {cli} add "<title>" --notes "why it is separate"
Run those from this pane — no task id needed, because the board finds the card
by the pane its dispatch recorded. If a command cannot find your card (that pane
link only comes from a dispatch), pass the id above. Only I close cards. If you
find unrelated work, add a card for it instead of doing it here; if the board
says a card already covers it, note that one instead of filing a second.

When you finish, the last `note` before you move the card is the handoff —
a short fixed block, not a summary:
  files changed · tests run and counts · commits (short hashes) or `uncommitted`
  follow-up cards filed or `none` · anything only I must decide, or `none`

Your turn is not over until the card is moved — `note` records progress, it does
not move the card, and a turn that only notes leaves the card saying you are
still working. Move it before your final message:
  task done, even if you offer to do more -> {cli} status {review}
  stopped, cannot continue without me     -> {cli} block "what you need"
  still working                           -> leave it; the card stays In Progress"""


def protocol_block(task_id: str, cli: str = CLI, review: str = "review") -> str:
    """How an agent keeps its own card current (appended to the prompt).

    `review` is the board's own review column (`Config.review_column`), so the
    command an agent is told to run names the column this board actually has
    rather than a literal `review` that a rename would make fail.
    """
    return PROTOCOL_TEMPLATE.format(task_id=task_id, cli=cli, review=review)


def _branch_slug(title: str, limit: int = BRANCH_SLUG_LIMIT) -> str:
    """A branch-safe slug out of a card title, cut on a word boundary."""
    slug = re.sub(r"[^a-z0-9]+", "-", (title or "").lower()).strip("-")
    if limit > 0 and len(slug) > limit:
        slug = slug[:limit].rsplit("-", 1)[0]
    return slug.strip("-")


def worktree_branch_name(task: Task) -> str:
    """`feature/<slug>` or `fix/<slug>` for a worktree forked for `task`.

    Not herdr's generated `worktree/<name>`: a branch outlives the run and is
    read months later, and `feature/dispatch-into-a-worktree-by-default` says
    what it is about where `worktree/quiet-cloud-0ecd` says only that herdr
    made it. The card's title is the slug, and a title that opens with a fix
    marker gets the `fix/` prefix (the repo's worktree rule names both shapes);
    everything else is a `feature/`. The slug falls back to the card id when a
    title is all punctuation.
    """
    lowered = (task.title or "").strip().lower()
    prefix = "fix" if lowered.startswith(FIX_MARKERS) else "feature"
    slug = _branch_slug(task.title) or task.slug
    return f"{prefix}/{slug}"


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


def close_agent_tab(store: Store, task: Task, herdr: Herdr | None = None) -> str:
    """Stop a card's agent by closing the tab its dispatch opened; "" on success.

    The board's own housekeeping for a caller with no board behind it: the CLI's
    `archive`, which honours `auto_archive_agent` the same way the `A` key does,
    so "the agent stopped" means the same thing whichever door was used. It
    mirrors `KanbanApp.close_agent`, including the rule that only a tab whose
    label is still the one the board last wrote is ours to close — the same pane
    may have been closed and reused for something else since, and a card leaving
    the board must not take that with it. Returns the phrase for the caller's
    notice ("closed w1:t9", or the error that left the tab open), or "" when
    there was no tab of ours, in which case the card's pane fields are cleared
    and nothing else happens.
    """
    if not task.tab_id:
        store.update_any(task.id, pane_id="", tab_id="", tab_label="", agent_name="")
        return ""
    # Held in a local because the card's own `tab_id` is cleared below, and the
    # phrase this returns is built from the tab it closed.
    tab_id = task.tab_id
    label = task.tab_label or tab_label_for(task)
    client = herdr or Herdr()
    # `tab_label` reports "" for a tab herdr no longer has, so a tab closed by
    # hand reads the same as one that was repurposed: not ours. Either way the
    # card's pointer at it is worthless, so it is cleared exactly as
    # `KanbanApp.close_agent` clears it — the caller's notice then has nothing to
    # say about an agent that was never stopped.
    if client.tab_label(tab_id) != label:
        store.update_any(task.id, pane_id="", tab_id="", tab_label="", agent_name="")
        return ""
    result = client.close_tab(tab_id)
    if not result.ok:
        return f"could not close {tab_id}: {result.error_text()}"
    store.update_any(task.id, pane_id="", tab_id="", tab_label="", agent_name="")
    return f"closed {tab_id}"


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


def review_prompt(task: Task, comment: str, config: Config | None = None) -> str:
    """The prompt a review bounce hands back: the reviewer's comment, then the protocol.

    A bounce is a second round, not a fresh dispatch, and the first line says
    so: the agent's own turn ended with the card in Review, so a bare repeat of
    the task would read as work it had already finished. The column line names
    where the same dispatch is about to put the card, so "still working" and
    "done" in the protocol below mean what they say. The comment is quoted as
    written and the protocol is appended exactly as a first send appends it —
    the way the agent moves its card does not change because it is round two.
    """
    where = (config.send_column(task.status) if config else "") or "In Progress"
    lines = [
        f"Changes requested on {task.id} — {task.title}",
        f"The card is back in {config.label_for(where) if config else where} for"
        " another round.",
        "",
        (comment or "").strip(),
    ]
    if config is None or config.announce_protocol:
        review = config.review_column if config is not None else "review"
        lines += ["", protocol_block(task.id, review=review or "review")]
    return "\n".join(lines)


def reply_prompt(task: Task, text: str, config: Config | None = None) -> str:
    """The prompt that answers a Blocked card's question: the answer, then the protocol.

    A reply is a second round like a bounce, but the card was parked because
    the agent asked for something rather than because the work was wrong, so
    the first line says "answer" where `review_prompt` says "changes
    requested". The column line names where the same dispatch is about to put
    the card, and the protocol is appended exactly as a first send appends it,
    so the agent still knows how to move its card. The board's UI answer box
    (nixos-95) reuses this prompt, so the two ways into a blocked agent's pane
    hand over the same text.
    """
    where = (config.send_column(task.status) if config else "") or "In Progress"
    lines = [
        f"Answer on {task.id} — {task.title}",
        f"The card is back in {config.label_for(where) if config else where} —"
        " carry on with the task.",
        "",
        (text or "").strip(),
    ]
    if config is None or config.announce_protocol:
        review = config.review_column if config is not None else "review"
        lines += ["", protocol_block(task.id, review=review or "review")]
    return "\n".join(lines)


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
    prompt: str | None = None,
) -> Plan:
    """Decide what a dispatch of `task` would do, without doing any of it.

    `prompt` replaces the ordinary title/notes/protocol prompt for one run —
    what a review bounce needs, since the text handed back is the reviewer's
    comment rather than the task again (`review_prompt`). Prompt assembly stays
    in this function so a caller cannot build a plan whose text disagrees with
    the plan's own fields.
    """
    agent = live.lookup(task)

    kind = task.agent_kind or fallback_kind or config.default_agent
    workspace_id = task.workspace_id or fallback_workspace
    workspace = live.workspaces.get(workspace_id)
    workspace_label = (
        workspace.label
        if workspace is not None
        else task.workspace_label or workspace_id
    )

    # The worktree decision, resolved here and nowhere else so the send form,
    # `send` and its `--dry-run` cannot disagree about what a run will do. Two
    # cases fork nothing:
    #   * the card already owns a checkout — that checkout is where its work
    #     lives, so a re-send reuses it rather than scattering one card's work
    #     across two checkouts;
    #   * the workspace is not a plain git checkout. A linked worktree is
    #     already somebody else's isolation, and a workspace herdr cannot see
    #     must not be assumed to be a repo (`workspace_ok` keeps the same
    #     "cannot tell, do not act" rule).
    # `--no-worktree` and an unticked box override this for one run.
    owns_checkout = bool(task.worktree_path)
    fork_by_default = bool(
        config.worktree
        and workspace is not None
        and workspace.checkout_path
        and not workspace.is_linked_worktree
    )
    worktree = owns_checkout or fork_by_default
    # A card being reused keeps the branch it has; a fresh fork gets a
    # descriptive one rather than herdr's generated default. Computed whether
    # or not this plan forks: the send form can tick the box after the plan was
    # built (a non-git workspace that owns no checkout), and the branch has to
    # be there when it does instead of empty.
    worktree_new_branch = task.worktree_branch or worktree_branch_name(task)

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
        prompt=prompt if prompt is not None else build_prompt(task, config),
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
        worktree=worktree,
        worktree_path=task.worktree_path,
        worktree_branch=task.worktree_branch,
        worktree_workspace_id=task.worktree_workspace_id,
        worktree_new_branch=worktree_new_branch,
    )


def worktree_removable(task: Task) -> tuple[bool, str]:
    """Whether the board may offer to remove `task`'s checkout, and why not.

    Only the git half of the question: whether the card's agent still needs the
    checkout is the caller's, because delete and archive answer it from
    different config keys. "Why not" is empty when the card simply has no
    checkout to remove, so a caller can tell "nothing to remove" from "there is
    something here worth keeping".
    """
    if not task.worktree_path or not task.worktree_workspace_id:
        return False, ""
    state = git.inspect(task.worktree_path, task.worktree_branch)
    return state.removable, state.reason


def remove_worktree(herdr: Herdr, task: Task, demo: bool = False) -> str:
    """Remove `task`'s checkout and branch when that cannot lose work.

    Returns a phrase for the delete/archive notice. Never forces: a checkout
    with uncommitted or unmerged work is kept, with the reason, and one herdr
    cannot remove (its workspace was closed by hand) names the git command that
    will. The branch is deleted only after the checkout is really gone and only
    with `git branch -d` — git's own safe delete refuses an unmerged branch, so
    there is a second lock behind `worktree_removable`.
    """
    state = git.inspect(task.worktree_path, task.worktree_branch)
    if not state.removable:
        return f"worktree kept — {state.reason}"
    if not task.worktree_workspace_id:
        return "worktree kept (its workspace is already gone)"
    if demo:
        return f"demo: would remove worktree {task.worktree_path}"
    result = herdr.remove_worktree(task.worktree_workspace_id)
    if not result.ok:
        # `worktree remove` takes only a workspace id, so a workspace closed by
        # hand leaves the checkout for `git worktree remove` to take.
        return (
            f"worktree kept — {result.error_text()}; remove it with:"
            f" git worktree remove {task.worktree_path}"
        )
    phrase = f"worktree removed ({task.worktree_path})"
    if state.repo_root and state.branch:
        deleted, detail = git.delete_branch(state.repo_root, state.branch)
        phrase += (
            f" · branch {detail} removed"
            if deleted
            else f" · branch kept — {detail}"
        )
    return phrase


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

    def run(
        self,
        plan: Plan,
        on_step: Callable[[Step], None] | None = None,
        on_record: Callable[[Outcome], None] | None = None,
    ) -> Outcome:
        """Plan against herdr. `on_record` is the durable half of a dispatch.

        `on_record` is called once, the moment this run has something the board
        must not lose: an agent started in a pane it owns. That is *before* the
        prompt is confirmed, because the confirmation can take seconds and the
        process running it can die inside that window — a card whose pane, tab
        and agent name were never written is a running agent the board cannot
        find and cannot re-dispatch. The outcome handed over is not `ok` (the
        turn is not confirmed yet), so a recorder writes the fields without
        moving the card; the caller's own write after `run` returns does the
        move.
        """
        steps: list[Step] = []

        def step(label: str, detail: str = "", ok: bool = True) -> Step:
            entry = Step(label, detail, ok)
            steps.append(entry)
            if on_step is not None:
                on_step(entry)
            return entry

        def commit(outcome: Outcome) -> None:
            if on_record is not None:
                on_record(outcome)

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

        # 4b. The agent exists: write that down before waiting on the prompt.
        #     A worker killed mid-confirmation (the nixos-82 pane died 0.8s
        #     after `agent prompt` reported success) must still leave the card
        #     linked to the agent it started. Not `ok`: the turn is unconfirmed,
        #     so this records the run without claiming the card is in progress.
        commit(
            Outcome(
                False,
                list(steps),
                agent_name=plan.name,
                pane_id=pane_id,
                tab_id=tab_id,
                **worktree_fields,
            )
        )

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
                    workspace_id=plan.workspace_id,
                    label=plan.tab_label,
                    branch=plan.worktree_new_branch,
                )
                action = "created"
        else:
            result = self.herdr.create_worktree(
                workspace_id=plan.workspace_id,
                label=plan.tab_label,
                branch=plan.worktree_new_branch,
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
    "close_agent_tab",
    "plan_for",
    "protocol_block",
    "reply_prompt",
    "result_summary",
    "retitle_tab",
    "review_prompt",
    "remove_worktree",
    "worktree_branch_name",
    "worktree_from_result",
    "worktree_removable",
]
