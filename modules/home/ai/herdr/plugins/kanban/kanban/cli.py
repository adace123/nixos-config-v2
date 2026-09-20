"""The agent-facing half of `herdr-kanban`.

Dispatch tells an agent how to keep its card current; these are the commands
that make it possible. Everything goes through `Store`, so a board that is open
picks the change up on its next tick — there is no server, socket, or callback
involved.

The card is found from the caller's pane (`HERDR_PANE_ID`, injected into every
herdr pane and recorded on dispatch), so a dispatched agent never needs to be
told its task id:

    herdr-kanban status review
    herdr-kanban block "need the production DSN"
    herdr-kanban note "the drift is in flake.lock:190"
    herdr-kanban title "Fix flake lock drift after the nixpkgs bump"

Humans can use the same commands with an explicit id (`K3` or `3`).
"""

from __future__ import annotations

import json
import os
import sys
from collections.abc import Callable
from typing import Any

from . import notify
from .config import Config, load_config
from .dispatch import CLI, protocol_block, retitle_tab
from .model import LiveState
from .render import format_age, truncate
from .store import (
    Store,
    Task,
    board_path,
    looks_like_id,
    workspace_code,
)

USAGE_COMMANDS = """  {cli} status [<task>] <column>   move a card
  {cli} block  [<task>] [message]  park it in Blocked + say what you need
  {cli} note   [<task>] <text>     record progress on the card
  {cli} title  [<task>] <text>     name the card (kept if the human named it,
                                    unless agent_title_overrides lets agents)
  {cli} step   [<task>]            show the checklist
  {cli} step   [<task>] add <text> | done <n> | undo <n> | rm <n>
  {cli} add    <title> [--workspace <id>] [--agent <kind>] [--column <col>]
                       [--notes <text…>] [--priority <p>] [--label <l>] [--json]
                       [--from <task>] [--model <name>] [--force]
  {cli} send   [<task>] [--agent <kind>] [--workspace <id>] [--model <name>]
                       [--worktree|--no-worktree] [--dry-run]
  {cli} archive   [<task>]         archive a card, keeping its record
  {cli} unarchive [<task>]         restore an archived card to the board
  {cli} list   [--mine] [--json]   list cards (--archived: the archive)
  {cli} show   [<task>] [--json]   one card in full
  {cli} help                       this text

  <task> is a board id (cfg-8, or K3 on a card filed with no workspace) or its
  number (8); inside the pane a card was dispatched to it can be omitted to mean
  "the card for this pane". Columns may be ids or labels."""


def usage() -> str:
    return (
        "herdr-kanban — the board's task commands (and the board itself)\n\n"
        f"{USAGE_COMMANDS.format(cli=CLI)}\n\n"
        f"Protocol for a card dispatched to you:\n{protocol_block('<task>')}"
    )


AGENT_COMMANDS = (
    "status",
    "block",
    "note",
    "title",
    "step",
    "add",
    "send",
    "archive",
    "unarchive",
    "list",
    "show",
    "help",
)


def _pane_id() -> str:
    return os.environ.get("HERDR_PANE_ID", "").strip()


def _from_agent() -> bool:
    return bool(_pane_id())


def _split_task(args: list[str], allow_lone_id: bool = True) -> tuple[str, list[str]]:
    """Peel a leading `cfg-8`/`K3`/`3` off the arguments, when there is one.

    `allow_lone_id=False` is for a verb whose argument is free text (`title`):
    a one-word title that reads like an id — `eslint-9`, the shape a workspace
    code makes ordinary — is the title, not the card to rename. A verb that
    takes an id on its own (`block`, `step`) keeps the default, so
    `herdr-kanban block cfg-8` still means the card.
    """
    if args and (allow_lone_id or len(args) > 1) and looks_like_id(args[0]):
        return args[0], args[1:]
    return "", list(args)


def _column_of(config: Config, wanted: str) -> tuple[str, str]:
    """(column id, error) for a column id or label."""
    wanted = (wanted or "").strip()
    if not wanted:
        return "", "which column? one of: " + ", ".join(config.column_ids)
    lowered = wanted.lower()
    for column in config.columns:
        if column.id == lowered or column.label.lower() == lowered:
            return column.id, ""
    return "", (
        f"unknown column {wanted!r}; this board has: "
        + ", ".join(f"{column.id} ({column.label})" for column in config.columns)
    )


def _find(
    store: Store, reference: str, include_archived: bool = False
) -> tuple[Task | None, str]:
    task = store.resolve(reference, _pane_id())
    if task is not None:
        return task, ""
    # `show`, `archive` and `unarchive` may name a card that is off the board;
    # every other verb must not, or an agent could move a card nobody sees.
    if include_archived and reference:
        task = store.resolve_archived(reference)
        if task is not None:
            return task, ""
    if reference:
        return None, f"no task {reference!r} on the board — try: {CLI} list"
    pane = _pane_id()
    if pane:
        # The pane is the whole link, and only a dispatch writes one
        # (`Store.resolve`). A card that reached the agent any other way —
        # handed over by hand, or filed outside the board — is not found here,
        # and the bare "no card" that used to answer this was indistinguishable
        # from "that card does not exist": the protocol says the id is never
        # needed, so an agent had nothing left to try. Name the situation and
        # the way back instead (nixos-47).
        return None, (
            f"no card is dispatched to pane {pane} — the board matches a card to the "
            f"pane its dispatch recorded, and no dispatch recorded this one. If "
            f"you were handed a card, pass its id ({CLI} status <id> review, "
            f"{CLI} show <id>) — {CLI} list shows the board"
        )
    return None, f"pass a task id: {CLI} status K3 review (or {CLI} list)"


def _describe(task: Task, config: Config) -> str:
    where = task.workspace_label or task.workspace_id or "no workspace"
    meta = (
        f"{where} · {task.agent_kind or 'agent?'} · updated"
        f" {format_age(task.updated_at)} ago"
    )
    if task.created_by == "agent":
        meta += " · filed by an agent"
    if task.agent_model:
        meta += f" · model {task.agent_model}"
    if task.parent_id:
        meta += f" · found during {task.parent_id}"
    lines = [
        f"{task.id}  [{config.label_for(task.status)}]  {truncate(task.title, 70)}",
        f"     {meta}",
    ]
    if task.archived_at:
        lines.append(
            f"     archived {format_age(task.archived_at)} ago"
            + (
                f" from {config.label_for(task.archived_from)}"
                if task.archived_from
                else ""
            )
        )
    if task.worktree_path:
        lines.append(
            f"     worktree {task.worktree_path}"
            + (f" ({task.worktree_branch})" if task.worktree_branch else "")
        )
    if task.title_source == "agent" and task.original_title:
        lines.append(
            f"     title from the agent (was: {truncate(task.original_title, 60)})"
        )
    if task.steps:
        lines.append(f"     steps {task.steps_done}/{len(task.steps)}")
    if task.progress:
        latest = str(task.progress[-1].get("text", ""))
        lines.append(f"     last update: {truncate(latest, 70)}")
    return "\n".join(lines)


def _task_json(task: Task, config: Config) -> dict[str, Any]:
    return {
        "id": task.id,
        "title": task.title,
        "original_title": task.original_title,
        "title_source": task.title_source,
        "created_by": task.created_by,
        "parent_id": task.parent_id,
        "status": task.status,
        "status_label": config.label_for(task.status),
        "workspace": task.workspace_id,
        "workspace_label": task.workspace_label,
        "worktree_path": task.worktree_path,
        "worktree_branch": task.worktree_branch,
        "worktree_workspace": task.worktree_workspace_id,
        "agent_kind": task.agent_kind,
        "agent_model": task.agent_model,
        "agent_name": task.agent_name,
        "pane_id": task.pane_id,
        "tab_id": task.tab_id,
        "priority": task.priority,
        "labels": task.labels,
        "notes": task.notes,
        "progress": task.progress,
        "steps": task.steps,
        "steps_done": task.steps_done,
        # The card's own record of what happened to it: who created it, every
        # column it has been in, every title it has had. `progress` above is the
        # agent's narrative; this is the audit trail.
        "history": task.history,
        "created_at": task.created_at,
        "updated_at": task.updated_at,
        "dispatched_at": task.dispatched_at,
        "archived": bool(task.archived_at),
        "archived_at": task.archived_at,
        "archived_from": task.archived_from,
        "columns": config.column_ids,
        "agent_may_set": config.agent_statuses,
    }


# -- verbs -------------------------------------------------------------------


def _parse_status(args: list[str], config: Config) -> tuple[str, str, str, str]:
    """Split `[<task>] <column> [message]` however it was written.

    The column is located by *name* rather than by position, so an unanchored
    `status blocked "why"` and an anchored `status K3 blocked "why"` both work.
    """
    for index, arg in enumerate(args):
        column, _ = _column_of(config, arg)
        if not column:
            continue
        if index > 1:
            return (
                "",
                "",
                "",
                f"unexpected argument {args[0]!r} before the column {arg!r}",
            )
        reference = args[0] if index == 1 else ""
        return reference, column, " ".join(args[index + 1 :]).strip(), ""
    wanted = " ".join(args) or "(nothing)"
    return (
        "",
        "",
        "",
        (
            f"no column in {wanted!r}; this board has: "
            + ", ".join(f"{column.id} ({column.label})" for column in config.columns)
        ),
    )


def _status(args: list[str], store: Store, config: Config) -> int:
    force = "--force" in args
    args = [arg for arg in args if arg != "--force"]
    if not args:
        print(f"usage: {CLI} status [<task>] <column>", file=sys.stderr)
        return 2

    reference, column, message, error = _parse_status(args, config)
    if error:
        print(error, file=sys.stderr)
        return 2

    task, error = _find(store, reference)
    if task is None:
        print(error, file=sys.stderr)
        return 1

    # `status blocked "why"` is shorthand for block + reason.
    if message and column != config.blocked_column:
        print(
            f"unexpected extra arguments after {column!r}: {message!r}",
            file=sys.stderr,
        )
        return 2

    _, outcome = store.set_status_from_agent(
        task.id,
        column,
        config.human_only_columns,
        force=force,
        # `status blocked` is the shorthand for an explicit park, so it gets the
        # same hold as `block` below.
        hold=column == config.blocked_column,
    )
    if message:
        store.add_progress(task.id, message)
    print(outcome)
    return 1 if column in config.human_only_columns and not force else 0


def _block(args: list[str], store: Store, config: Config) -> int:
    reference, rest = _split_task(args)
    message = " ".join(rest).strip()
    task, error = _find(store, reference)
    if task is None:
        print(error, file=sys.stderr)
        return 1

    if config.blocked_column:
        _, outcome = store.set_status_from_agent(
            task.id,
            config.blocked_column,
            config.human_only_columns,
            hold=True,
        )
        print(outcome)
    else:
        print(
            f"{task.id}: this board has no Blocked column; recorded the block as an"
            " update and left the card in " + config.label_for(task.status)
        )
    print(f"  waiting on: {message or 'the human'}")
    store.add_progress(task.id, message or "blocked, waiting on the human")
    return 0


def _note(args: list[str], store: Store, _config: Config) -> int:
    reference, rest = _split_task(args)
    text = " ".join(rest).strip()
    if not text:
        print(f"usage: {CLI} note [<task>] <text>", file=sys.stderr)
        return 2
    task, error = _find(store, reference)
    if task is None:
        print(error, file=sys.stderr)
        return 1
    _, outcome = store.add_progress(
        task.id, text, by="agent" if _from_agent() else "user"
    )
    print(outcome)
    return 0


def _title(args: list[str], store: Store, config: Config) -> int:
    force = "--force" in args
    args = [arg for arg in args if arg != "--force"]
    # The title is free text, so a lone argument is never a card reference: see
    # `_split_task`. `herdr-kanban title "eslint-9"` names the card.
    reference, rest = _split_task(args, allow_lone_id=False)
    title = " ".join(rest).strip()
    if not title:
        print(f"usage: {CLI} title [<task>] <new title>", file=sys.stderr)
        return 2
    task, error = _find(store, reference)
    if task is None:
        print(error, file=sys.stderr)
        return 1
    was = task.title
    updated, outcome = store.set_title(
        task.id,
        title,
        source="agent" if _from_agent() else "user",
        # `agent_title_overrides` is a standing `--force` for the agent's own
        # titles: on a board where the work names the card, an agent's title is
        # the better one, and the title it replaces is kept in the card's
        # history. A human renaming by hand never needs it — that title wins
        # either way.
        force=force or (_from_agent() and config.agent_title_overrides),
    )
    print(outcome)
    if updated is not None and updated.title != was:
        # The card's tab carries the same name (`dispatch.tab_label_for`), and
        # the board finds its own tab by that label: a rename that left the tab
        # behind would leave the two disagreeing. A tab the board cannot reach
        # is not a failed rename — the card was renamed, which is what was
        # asked — so this is a warning, not the exit code.
        problem = retitle_tab(store, updated)
        if problem:
            print(f"{updated.id}: could not rename its tab: {problem}", file=sys.stderr)
    return 0


def _list(args: list[str], store: Store, config: Config) -> int:
    as_json = "--json" in args
    archived = "--archived" in args
    pane = _pane_id()
    if archived:
        tasks = list(store.archived)
        mine = "--mine" in args
    else:
        # Default to the caller's card only when the caller is actually in a
        # card's pane: a human running this in an ordinary herdr shell wants the
        # board, not "no cards for this pane".
        in_task_pane = bool(pane) and store.resolve("", pane) is not None
        mine = "--mine" in args or (in_task_pane and not args)
        tasks = list(store.tasks)
    if mine:
        tasks = [
            task
            for task in tasks
            if task.pane_id and (not pane or task.pane_id == pane)
        ]
    if as_json:
        print(json.dumps([_task_json(task, config) for task in tasks], indent=2))
        return 0
    if not tasks:
        if archived:
            print("no archived cards")
        elif mine and pane:
            # Same dead end as `_find`: "no cards for this pane" reads as "the
            # board is empty" when the card simply was never dispatched here.
            print(
                "no cards for this pane — the board matches a card to the pane"
                f" its dispatch recorded; pass a task id ({CLI} show <id>) or run"
                f" {CLI} list for the whole board"
            )
        else:
            print("no cards")
        return 0
    if archived:
        # Archived cards keep their column, but grouping them by it would put a
        # live-looking board under a heading nobody expects to see columns in.
        print(f"Archived ({len(tasks)})")
        for task in tasks:
            marker = "*" if pane and task.pane_id == pane else " "
            print(f" {marker} {_describe(task, config)}")
        return 0
    for column in config.columns:
        column_tasks = [task for task in tasks if task.status == column.id]
        if not column_tasks:
            continue
        print(f"{column.label} ({len(column_tasks)})")
        for task in column_tasks:
            marker = "*" if pane and task.pane_id == pane else " "
            print(f" {marker} {_describe(task, config)}")
    return 0


def _show(args: list[str], store: Store, config: Config) -> int:
    as_json = "--json" in args
    reference = next((arg for arg in args if not arg.startswith("--")), "")
    task, error = _find(store, reference, include_archived=True)
    if task is None:
        print(error, file=sys.stderr)
        return 1
    if as_json:
        print(json.dumps(_task_json(task, config), indent=2))
        return 0
    print(_describe(task, config))
    if task.notes:
        print("\nnotes:")
        for line in task.notes.splitlines():
            print(f"  {line}")
    if task.steps:
        print(f"\nsteps ({task.steps_done}/{len(task.steps)}):")
        for step_line in store.step_lines(task):
            print(f"  {step_line}")
    if task.progress:
        print("\nupdates:")
        for entry in task.progress[-10:]:
            age = format_age(float(entry.get("at") or 0))
            print(f"  {age:>4} ago  {entry.get('by', '?')}: {entry.get('text', '')}")
    if task.history:
        print("\nhistory:")
        for entry in task.history[-12:]:
            age = format_age(float(entry.get("at") or 0))
            print(f"  {age:>4} ago  {entry.get('what', '')}")
    if task.pane_id:
        print(f"\npane: {task.pane_id}   tab: {task.tab_id or '-'}")
    allowed = ", ".join(config.agent_statuses)
    print(f"columns: {', '.join(config.column_ids)}   (agents may set: {allowed})")
    return 0


def _step(args: list[str], store: Store, _config: Config) -> int:
    """The card's checklist: show it, or add/tick/untick/remove one entry."""
    reference, rest = _split_task(args)
    action = rest[0].lower() if rest else "list"
    operand = rest[1:]
    task, error = _find(store, reference)
    if task is None:
        print(error, file=sys.stderr)
        return 1

    if action in ("list", "show"):
        _print_steps(store, task)
        return 0

    if action in ("add", "append"):
        text = " ".join(operand).strip()
        if not text:
            print(f"usage: {CLI} step [<task>] add <text>", file=sys.stderr)
            return 2
        _, message = store.add_step(
            task.id, text, by="agent" if _from_agent() else "user"
        )
        print(message)
        _print_steps(store, store.by_id(task.id))
        return 0

    if action in ("done", "undo", "rm", "remove", "undone"):
        if len(operand) != 1 or not operand[0].isdigit():
            print(f"usage: {CLI} step [<task>] {action} <number>", file=sys.stderr)
            return 2
        index = int(operand[0])
        # Range-checked here rather than in the store, so a script gets a
        # non-zero exit instead of having to parse the message.
        if not task.steps:
            print(
                f'{task.id} has no steps yet — {CLI} step {task.id} add "first step"',
                file=sys.stderr,
            )
            return 1
        if not 1 <= index <= len(task.steps):
            print(
                f"{task.id} has {len(task.steps)} step(s); {index} is out of range",
                file=sys.stderr,
            )
            return 1
        if action in ("rm", "remove"):
            _, message = store.remove_step(task.id, index)
        else:
            _, message = store.set_step(
                task.id,
                index,
                done=action == "done",
                by="agent" if _from_agent() else "user",
            )
        print(message)
        _print_steps(store, store.by_id(task.id))
        return 0

    print(
        f"unknown step action {action!r} — try add, done, undo, rm",
        file=sys.stderr,
    )
    return 2


def _print_steps(store: Store, task: Task | None) -> None:
    if task is None:
        return
    if not task.steps:
        print(f'{task.id} has no steps — {CLI} step {task.id} add "first step"')
        return
    print(f"{task.id} steps ({task.steps_done}/{len(task.steps)}):")
    for line in store.step_lines(task):
        print(f"  {line}")


def _add(args: list[str], store: Store, config: Config) -> int:
    """File a new card. Lets an agent that finds more work record it.

    herdr-kanban add "Flake lock drift" --workspace w1 --agent pi --column todo
    """
    title_parts: list[str] = []
    options: dict[str, str] = {}
    labels: list[str] = []
    as_json = False
    force = False
    value_flags = {
        "--workspace": "workspace",
        "-w": "workspace",
        "--agent": "agent",
        "-a": "agent",
        "--column": "column",
        "-c": "column",
        "--status": "column",
        "--notes": "notes",
        "-n": "notes",
        "--priority": "priority",
        "-p": "priority",
        "--from": "from",
        "--model": "model",
        "-m": "model",
        "--label": "label",
        "-l": "label",
    }
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--json":
            as_json = True
            index += 1
            continue
        if arg == "--force":
            force = True
            index += 1
            continue
        if arg in value_flags:
            if index + 1 >= len(args):
                print(f"{arg} needs a value", file=sys.stderr)
                return 2
            key = value_flags[arg]
            if key == "label":
                labels.append(args[index + 1])
                index += 2
            elif key == "notes":
                # A note is free text, so it takes every following token up to
                # the next flag — the same rule `note`, `title` and `block` use
                # (`" ".join(rest)`). Quoting is therefore optional: an
                # unquoted `--notes why it is separate` files the whole note
                # instead of cutting it to `why` and pushing `it is separate`
                # into the card's title, which is what a one-argument `--notes`
                # did — the one free-text value in this CLI that silently
                # required quotes. A following flag still ends the note, so
                # `--notes why --priority high` keeps working; a dash-word that
                # is not a flag falls through to the unknown-option error below
                # rather than being swallowed into the note.
                note = [args[index + 1]]
                index += 2
                while index < len(args) and not args[index].startswith("-"):
                    note.append(args[index])
                    index += 1
                options[key] = " ".join(note)
            else:
                options[key] = args[index + 1]
                index += 2
            continue
        if arg.startswith("-"):
            print(f"unknown option {arg!r}", file=sys.stderr)
            return 2
        title_parts.append(arg)
        index += 1

    title = " ".join(title_parts).strip()
    if not title:
        print(
            f'usage: {CLI} add "<title>" [--workspace <id>] [--agent <kind>]'
            " [--column <col>] [--notes <text…>] [--force]",
            file=sys.stderr,
        )
        return 2

    # One card per thing. An agent that reports the same finding on every run
    # would otherwise fill the backlog with it, and the second card costs the
    # human more than the first one saved: the existing card is named here so
    # the agent can add to it (`note`) instead. `--force` is for the real case
    # of two cards that genuinely share a title.
    existing = store.find_by_title(title)
    if existing is not None and not force:
        print(
            f'{existing.id} already covers this: "{existing.title}"'
            f" ({config.label_for(existing.status)}) — pass --force to file it anyway",
            file=sys.stderr,
        )
        return 1

    column, error = _column_of(config, options.get("column", config.default_column))
    if error:
        print(error, file=sys.stderr)
        return 2
    # Filing straight into the human-only column is setting it, so the same rule
    # as `status` applies: an agent may not, unless it means it (`--force`). A
    # human at a shell is not an agent here even if the shell is a herdr pane —
    # `_from_agent` is the one test every verb uses.
    if _from_agent() and column in config.human_only_columns and not force:
        print(
            f"refusing to file into {column} — that column is yours to close, not"
            " the agent's; pass --force if you mean it",
            file=sys.stderr,
        )
        return 1

    # Which card this one came out of. An agent never has to say: the pane it is
    # working in *is* a card, and that is the card that found the work. An
    # explicit --from wins, because a human filing on someone else's behalf
    # knows better than the pane does.
    parent_id = ""
    wanted_parent = options.get("from", "")
    if wanted_parent:
        parent = store.resolve(wanted_parent)
        if parent is None:
            print(f"no task {wanted_parent} on the board", file=sys.stderr)
            return 1
        parent_id = parent.id
    elif _from_agent():
        current = store.resolve("", _pane_id())
        parent_id = current.id if current is not None else ""

    workspace_id = options.get("workspace") or os.environ.get("HERDR_WORKSPACE_ID", "")
    label = ""
    if workspace_id:
        from .herdr import Herdr

        workspaces, result = Herdr().workspaces()
        if result.ok:
            match = next((w for w in workspaces if w.id == workspace_id), None)
            if match is not None:
                label = match.label
            else:
                print(
                    f"note: workspace {workspace_id} is not open right now",
                    file=sys.stderr,
                )

    task = store.add(
        title=title,
        notes=options.get("notes", ""),
        status=column,
        workspace_id=workspace_id,
        workspace_label=label,
        # The id's workspace code, frozen here for good: `[workspaces]` if this
        # label has an alias, otherwise the label's own slug.
        workspace_code=workspace_code(config.workspace_aliases, label, workspace_id),
        agent_kind=options.get("agent", config.default_agent),
        agent_model=options.get("model", ""),
        priority=options.get("priority", "normal"),
        labels=labels,
        parent_id=parent_id,
        # Provenance: a backlog full of agent guesses should be separable from
        # your own list. `_from_agent` is the same test the other verbs use to
        # decide whether a title change is the agent's — one convention, not
        # two — and the board's add form never sets this at all.
        created_by="agent" if _from_agent() else "user",
    )
    # An agent filing a card is reporting work it found while doing something
    # else: the one way a card appears without you having asked for it, and —
    # unlike the board's own capture — with nothing on screen to confirm it. So
    # the CLI says so where you actually are. No herdr toast goes with it: a
    # toast only reaches someone looking at herdr, and a board that is running
    # is about to show the card anyway.
    if task.created_by == "agent" and config.notify_on_add and config.notify_system:
        into = f" · found during {task.parent_id}" if task.parent_id else ""
        notify.system(f"{task.id} filed", f"{task.title}{into}")
    if as_json:
        print(json.dumps(_task_json(task, config), indent=2))
        return 0
    where = label or workspace_id or "no workspace"
    origin = f"  ·  from {task.parent_id}" if task.parent_id else ""
    print(
        f"{task.id}  {task.title}\n"
        f"     {where} · {task.agent_kind} · {config.label_for(task.status)}{origin}"
    )
    return 0


def _live_now() -> LiveState:
    """herdr's current world, for a command with no board behind it."""
    from .herdr import Herdr

    herdr = Herdr()
    workspaces, workspace_result = herdr.workspaces()
    agents, agent_result = herdr.agents()
    return LiveState(
        workspaces={workspace.id: workspace for workspace in workspaces},
        agents={agent.name: agent for agent in agents},
        agents_by_pane={agent.pane_id: agent for agent in agents},
        down=not (workspace_result.ok or agent_result.ok),
        error="" if workspace_result.ok else workspace_result.error_text(),
    )


def _send(args: list[str], store: Store, config: Config) -> int:
    """Start an agent for a card without opening the board.

    The board's `s`, for a script: `herdr-kanban send K5` from anywhere, or
    `herdr-kanban send` from the card's own pane. `--dry-run` prints the plan the
    board would have built and stops, which is how you check what an automation
    is about to do. The dispatch itself is `Executor.run`, the same code path the
    board uses, prompt-confirmation and all.
    """
    from dataclasses import replace

    from .dispatch import Executor, plan_for, record_outcome
    from .herdr import Herdr

    as_json = "--json" in args
    dry_run = "--dry-run" in args
    # `--worktree` forces a checkout for this run; `--no-worktree` sends into the
    # card's own workspace instead. Unset follows the card: a card that already
    # owns a checkout reuses it.
    worktree_override: bool | None = None
    options: dict[str, str] = {}
    value_flags = {
        "--agent": "agent",
        "-a": "agent",
        "--workspace": "workspace",
        "-w": "workspace",
        "--model": "model",
        "-m": "model",
    }
    words: list[str] = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in ("--json", "--dry-run"):
            index += 1
            continue
        if arg == "--worktree":
            worktree_override = True
            index += 1
            continue
        if arg == "--no-worktree":
            worktree_override = False
            index += 1
            continue
        if arg in value_flags and index + 1 < len(args):
            options[value_flags[arg]] = args[index + 1]
            index += 2
            continue
        if arg.startswith("-"):
            print(f"unknown option {arg!r}", file=sys.stderr)
            return 2
        words.append(arg)
        index += 1

    task, error = _find(store, " ".join(words).strip())
    if task is None:
        print(error, file=sys.stderr)
        return 1
    if task.pane_id and task.dispatched_at:
        # Re-sending prompts the agent that is already there — the board does the
        # same — so this is a note, not a refusal.
        print(
            f"note: {task.id} already has an agent ({task.agent_name or task.pane_id})"
            " — this prompts it again",
            file=sys.stderr,
        )
    if options.get("workspace"):
        # An explicit workspace is an override, not a fallback: "run it here
        # instead" is the whole reason to pass one, and the card follows the run.
        task = replace(task, workspace_id=options["workspace"], workspace_label="")
    if options.get("model"):
        # Same for the model: `send --model X` sends *this run* on X, and the card
        # records it, so a later re-send does not quietly go back to the default.
        task = replace(task, agent_model=options["model"])

    live = _live_now()
    plan = plan_for(
        task,
        config,
        live,
        fallback_workspace=os.environ.get("HERDR_WORKSPACE_ID", ""),
        fallback_kind=options.get("agent", ""),
    )
    if worktree_override is not None:
        plan = replace(plan, worktree=worktree_override)
    if not plan.workspace_id and not plan.reuses_running_agent:
        print(f"{task.id} has no workspace to run in", file=sys.stderr)
        return 1

    target = config.send_column(task.status)
    limit = config.wip_limit(target)
    if limit:
        counted = sum(1 for other in store.tasks if other.status == target)
        if counted >= limit and task.status != target:
            print(
                f"warning: {config.label_for(target)} is at its limit "
                f"({counted}/{limit})",
                file=sys.stderr,
            )

    if dry_run:
        where = plan.workspace_label or plan.workspace_id
        if plan.worktree:
            where = f"a worktree of {where}" if where else "a worktree"
        print(
            f"would send {plan.task_id} to {plan.name} ({plan.kind}) in {where}\n"
            f"     {task.status} -> {target or task.status}"
            + (f"   flags: {' '.join(plan.args)}" if plan.args else "")
            + ("   (reusing the running agent)" if plan.reuses_running_agent else "")
        )
        if as_json:
            print(
                json.dumps(
                    {
                        "task": plan.task_id,
                        "name": plan.name,
                        "kind": plan.kind,
                        "model": plan.model,
                        "args": list(plan.args),
                        "workspace": plan.workspace_id,
                        "worktree": plan.worktree,
                        "worktree_path": plan.worktree_path,
                        "column": target or task.status,
                        "reuses_agent": plan.reuses_running_agent,
                        "dry_run": True,
                    },
                    indent=2,
                )
            )
        return 0

    outcome = Executor(Herdr()).run(plan)
    if not outcome.ok:
        # The card is left where it was: a dispatch that never started must not
        # claim otherwise (see `record_outcome`).
        print(
            f"{task.id} not sent — {outcome.error or outcome.detail()}", file=sys.stderr
        )
        return 1
    updated = record_outcome(store, task.id, plan, outcome, target)
    if as_json:
        print(json.dumps(_task_json(updated or task, config), indent=2))
        return 0
    where = plan.workspace_label or plan.workspace_id
    if outcome.worktree_path:
        where = f"worktree {outcome.worktree_path}"
    print(
        f"{task.id}  {task.title}\n"
        f"     sent to {outcome.agent_name or plan.name} · "
        f"{where} · "
        f"{config.label_for(target or task.status)}"
    )
    return 0


def _archive(args: list[str], store: Store, _config: Config) -> int:
    """Take a card off the board, keeping its record (`unarchive` puts it back)."""
    force = "--force" in args
    args = [arg for arg in args if arg != "--force"]
    reference, rest = _split_task(args)
    if rest:
        print(f"unexpected argument {rest[0]!r}", file=sys.stderr)
        return 2
    task, error = _find(store, reference, include_archived=True)
    if task is None:
        print(error, file=sys.stderr)
        return 1
    if task.archived_at:
        print(f"{task.id} is already archived — {CLI} unarchive {task.id} puts it back")
        return 0
    # Taking a card off the board is the human's call, like closing one
    # (`status <done>`); an agent that means it says so with `--force`.
    if _from_agent() and not force:
        print(
            f"refusing to archive {task.id} — taking a card off the board is"
            " yours to decide, not the agent's; pass --force if you mean it",
            file=sys.stderr,
        )
        return 1
    _, message = store.archive(task.id)
    print(message)
    return 0


def _unarchive(args: list[str], store: Store, _config: Config) -> int:
    """Put an archived card back on the board, in the column it left."""
    reference, rest = _split_task(args)
    if rest:
        print(f"unexpected argument {rest[0]!r}", file=sys.stderr)
        return 2
    task, error = _find(store, reference, include_archived=True)
    if task is None:
        print(error, file=sys.stderr)
        return 1
    if not task.archived_at:
        print(f"{task.id} is not archived")
        return 0
    _, message = store.unarchive(task.id)
    print(message)
    return 0


def _help(_args: list[str], _store: Store, _config: Config) -> int:
    print(usage())
    return 0


def run_agent_command(argv: list[str]) -> int:
    """Entry point for the board task verbs (`status`, `add`, `step`, ...)."""
    command, args = argv[0], list(argv[1:])
    handlers: dict[str, Callable[[list[str], Store, Config], int]] = {
        "status": _status,
        "block": _block,
        "note": _note,
        "title": _title,
        "step": _step,
        "add": _add,
        "send": _send,
        "archive": _archive,
        "unarchive": _unarchive,
        "list": _list,
        "show": _show,
        "help": _help,
    }
    store = Store.open(board_path())
    try:
        return handlers[command](args, store, load_config())
    except BrokenPipeError:  # pragma: no cover - piping into head
        return 0
