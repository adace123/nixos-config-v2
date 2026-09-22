"""The board file: one JSON document the plugin owns.

Layout:

```json
{"version": 1, "seq": 4, "tasks": [{"id": "cfg-4", ...}]}
```

`seq` only ever grows, so ids are stable and never reused. An id is
`<code>-<seq>`: a short code for the workspace the card was *filed* in, then
that counter — `cfg-8`. The code is frozen with the id, the way `parent_id`
freezes where a card came from: a card is redispatched into another workspace
(and a workspace can be renamed), and neither may rewrite a name other cards
and panes already refer to. A card filed with no workspace keeps the plain
`K<seq>`. See `workspace_code` for how a code is chosen, and
`Config.workspace_aliases` for the `[workspaces]` overrides.

Order inside a column is list order, which is what `j`/`k` reorder and what
`H`/`L` preserve when a card changes column.

Writes are atomic (temp file + rename) and serialised with an `flock`, and every
mutation re-reads the file first — two boards open at once (an overlay and a
popup) cannot silently clobber each other. Tasks are user data, so the file is
meant to be readable, diffable, and hand-editable.
"""

from __future__ import annotations

import contextlib
import fcntl
import json
import os
import re
import shutil
import time
from collections.abc import Collection, Iterator, Mapping
from contextlib import contextmanager
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from .config import PLUGIN_ID

SCHEMA_VERSION = 1
HISTORY_LIMIT = 25
PROGRESS_LIMIT = 50
STEP_LIMIT = 40

PRIORITIES = ("low", "normal", "high", "urgent")

# How much of a workspace label an automatic id code keeps, and how long a
# configured `[workspaces]` alias may be. Both are about the card's top rule:
# ` cfg-8 ` shares ~15 cells with the priority and quill badges at the widths
# the board is actually read at, while an alias is an explicit choice and only
# has to stay inside herdr's 32-character agent-name budget. Both are applied
# to a *slug*, so a label loses its separators either way.
CODE_LIMIT = 6
ALIAS_LIMIT = 12

# A card id: `<code>-<seq>` (`cfg-8`, `nixos-1`), or the plain `K8` this board
# wrote before codes existed — and still writes for a card filed with no
# workspace. Two patterns rather than one `code?seq` because the counter has to
# be the *last* run of digits: a single greedy match reads `cfg-123` as code
# `cfg-12` and counter `3`, and a board-wide counter that can be misread is
# worse than no counter at all. The plain form keeps the old, narrow shape
# (`K8`, `8`) so a bare `v2` in an argument is still a word and not a card.
_CODED_ID = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*?-(\d+)$")
_PLAIN_ID = re.compile(r"^[Kk]?(\d+)$")


def slug_code(text: str, limit: int = CODE_LIMIT) -> str:
    """A short id code out of a workspace label.

    `nixos-config-v2` -> `nixos`, `snowflake-reporting` -> `snowfl`. Everything
    that is not an ascii letter or digit becomes a separator, runs collapse, and
    the result is trimmed of separators at both ends — so a truncation never
    ends in a dash. A leading digit is dropped rather than kept: an id doubles
    as the dispatched agent's name, and herdr requires those to start with a
    letter (`[a-z][a-z0-9_-]{0,31}`).

    Returned empty when the text yields nothing usable (all punctuation, or
    nothing but digits). `workspace_code` then tries herdr's workspace id, and a
    card filed with no workspace at all keeps the plain `K` id instead of an
    invented code — a card that says `K12` is honest about not knowing where it
    was filed, and `[workspaces]` is how you give that workspace a code.
    """
    slug = re.sub(r"[^a-z0-9]+", "-", (text or "").lower())
    slug = slug.strip("-").lstrip("0123456789").strip("-")
    return slug[:limit].rstrip("-") if limit > 0 else slug


def task_seq(task_id: str) -> int:
    """The counter in an id (`cfg-8` and `K8` are both 8), or 0 for a
    hand-edited id that is not one."""
    text = (task_id or "").strip()
    for pattern in (_CODED_ID, _PLAIN_ID):
        match = pattern.match(text)
        if match:
            return int(match.group(1))
    return 0


def looks_like_id(text: str) -> bool:
    """Whether an argument is a task reference rather than a column or a word."""
    return task_seq(text) > 0


def workspace_code(
    aliases: Mapping[str, str], label: str = "", workspace_id: str = ""
) -> str:
    """The id code for a card being filed in this workspace.

    `[workspaces]` wins, and may be keyed by the label (`nixos-config-v2 =
    "cfg"`) or by herdr's own workspace id (`w1 = "cfg"`) — the id survives a
    `herdr workspace rename`, the label is what you read. Otherwise the label's
    own slug serves, which is what makes the feature work with no config at all,
    falling back to herdr's workspace id when there is no label to use (a card
    filed into a closed workspace, or with herdr unreachable).
    """
    for key in (label, label.lower(), workspace_id, workspace_id.lower()):
        alias = aliases.get(key) if key else None
        if alias:
            return slug_code(str(alias), ALIAS_LIMIT)
    return slug_code(label) or slug_code(workspace_id)


def task_id(code: str, seq: int) -> str:
    """The id for a card: its workspace code, then the board's counter.

    `K<seq>` when there is no code — a card filed with no workspace, or a label
    that yields nothing slug-worthy. Composition lives here so the board file's
    ids and the demo board's ids cannot drift apart.
    """
    return f"{code}-{seq}" if code else f"K{seq}"


def _as_time(value: Any) -> float | None:
    """A timestamp out of JSON, which the user may have hand-edited.

    A board file is meant to be editable, so `"updated_at": "yesterday"` has to
    survive: the renderer does real arithmetic on these, and a string there
    takes the whole board down rather than one card.
    """
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value.strip())
        except ValueError:
            return None
    return None


# Who set a card's title, and who may set what. Agents keep their own card
# current but never close it: `done` is the human's call.
TITLE_SOURCES = ("user", "agent")
# Who *filed* a card — the same two words, because "an agent put this here" is
# the same question whether it is about a title or about the card itself.
CREATED_BY = ("user", "agent")
# Which columns an agent may move its own card into, and which are the human's,
# is the board's business, not this module's: it is derived from the configured
# columns (`Config.human_only_columns` / `Config.agent_statuses`) and handed to
# `set_status_from_agent`. A literal list here is exactly what let renaming the
# Done column quietly hand agents the power to close cards.


@dataclass
class Task:
    id: str = ""
    title: str = ""
    notes: str = ""
    status: str = "backlog"
    workspace_id: str = ""
    workspace_label: str = ""
    agent_kind: str = ""
    agent_name: str = ""
    # The model this card's agent should run on, as the CLI names it (`--model
    # <value>`). Empty means "whatever `[agents.<kind>] args` already say", which
    # is the default and the only safe default: the board cannot know what a
    # given CLI accepts. Stored on the card because the send may be tomorrow.
    agent_model: str = ""
    priority: str = "normal"
    labels: list[str] = field(default_factory=list)
    # "agent" when the filing command came from inside a herdr pane, "user"
    # when it did not — the same test `title_source` uses, because there is no
    # marker that says "an agent is typing": the pane the command runs in is
    # the only evidence herdr gives (see `cli._from_agent`). Cards you add in
    # the board itself never claim an agent filed them.
    created_by: str = "user"
    # The card this one was filed from — "found while working on K3". An agent
    # that trips over unrelated work records where it tripped, so the follow-up
    # keeps its reason after the run that produced it is over. Empty for a card
    # you thought of yourself.
    parent_id: str = ""
    created_at: float = 0.0
    updated_at: float = 0.0
    dispatched_at: float | None = None
    # Set when the card is archived: when it left the board and the column it
    # left. A live card has `archived_at == 0.0`; the board file keeps archived
    # cards in their own list, so these two are what tell one apart (and what
    # `unarchive` restores to) when a `Task` is handled outside the store.
    archived_at: float = 0.0
    archived_from: str = ""
    pane_id: str = ""
    tab_id: str = ""
    # The label the board last wrote to that tab. Kept so the board can still
    # recognise its own tab after the card is renamed: herdr's tab is labelled
    # `<id> <title>`, and a board that recomputed that label from the *current*
    # title would read its own tab as one somebody repurposed the moment an
    # agent named the card (see `KanbanApp.agent_tab`).
    tab_label: str = ""
    # The git worktree this card's agent runs in, when its dispatch asked for one
    # (`herdr worktree create`): the checkout path, the branch herdr made, and the
    # workspace it opened for it. The card's `workspace_id` stays the repo
    # workspace the worktree was forked from — that is what a later dispatch
    # forks from, and what the id's code came from — while these three say where
    # the run actually lives (the board renders and removes by them). All empty
    # for a card dispatched into its own workspace.
    worktree_path: str = ""
    worktree_branch: str = ""
    worktree_workspace_id: str = ""
    title_source: str = "user"
    # Set once the human edits the title by hand: from then on an agent's title
    # becomes a suggestion instead of an overwrite.
    title_edited: bool = False
    # True while the card sits in Blocked because someone parked it there on
    # purpose (`herdr-kanban block`, or the human moving it) rather than because
    # the board reconciled a blocked agent into it. `Syncer.settle_columns`
    # must not carry such a card back to In Progress while its agent is still in
    # the same working phase; the hold is spent the moment that phase ends.
    blocked_hold: bool = False
    # The title as it stood before the first replacement, so a rename is
    # always reversible.
    original_title: str = ""
    progress: list[dict[str, Any]] = field(default_factory=list)
    # A checklist: [{"text", "done", "at", "by"}]. A better progress signal
    # than a pile of notes, for hand-worked and agent-worked cards alike.
    steps: list[dict[str, Any]] = field(default_factory=list)
    history: list[dict[str, Any]] = field(default_factory=list)

    @property
    def slug(self) -> str:
        """A name safe to hand to `herdr agent start` (`[a-z][a-z0-9_-]{0,31}`)."""
        slug = "".join(ch for ch in self.id.lower() if ch.isalnum() or ch in "-_")
        return slug or "task"

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Task:
        known = {f for f in cls.__dataclass_fields__}
        clean = {key: value for key, value in data.items() if key in known}
        labels = clean.get("labels")
        clean["labels"] = [str(x) for x in labels] if isinstance(labels, list) else []
        history = clean.get("history")
        clean["history"] = history if isinstance(history, list) else []
        progress = clean.get("progress")
        clean["progress"] = (
            [
                {
                    "at": _as_time(item.get("at")) or 0.0,
                    "by": str(item.get("by", "")),
                    "text": str(item.get("text", "")),
                }
                for item in progress
                if isinstance(item, dict)
            ][:PROGRESS_LIMIT]
            if isinstance(progress, list)
            else []
        )
        steps = clean.get("steps")
        clean["steps"] = (
            [
                {
                    "text": str(step.get("text", "")),
                    "done": bool(step.get("done")),
                    "at": _as_time(step.get("at")) or 0.0,
                    "by": str(step.get("by", "")),
                }
                for step in steps
                if isinstance(step, dict)
            ][:STEP_LIMIT]
            if isinstance(steps, list)
            else []
        )
        clean["created_at"] = _as_time(clean.get("created_at")) or 0.0
        clean["updated_at"] = _as_time(clean.get("updated_at")) or 0.0
        clean["dispatched_at"] = _as_time(clean.get("dispatched_at"))
        clean["archived_at"] = _as_time(clean.get("archived_at")) or 0.0
        if clean.get("title_source") not in TITLE_SOURCES:
            clean["title_source"] = "user"
        if clean.get("created_by") not in CREATED_BY:
            # Missing, hand-mangled, or from a board file written before this
            # field existed: the card is as good as one you typed.
            clean["created_by"] = "user"
        for key in ("title_edited", "blocked_hold"):
            if not isinstance(clean.get(key), bool):
                clean[key] = False
        if clean.get("priority") not in PRIORITIES:
            clean["priority"] = "normal"
        for key in (
            "id",
            "title",
            "notes",
            "status",
            "workspace_id",
            "workspace_label",
            "agent_kind",
            "agent_name",
            "agent_model",
            "archived_from",
            "pane_id",
            "tab_id",
            "tab_label",
            "worktree_path",
            "worktree_branch",
            "worktree_workspace_id",
            "original_title",
            "parent_id",
        ):
            if not isinstance(clean.get(key), str):
                clean[key] = ""
        return cls(**clean)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)

    def note(self, what: str) -> None:
        self.history.append({"at": round(time.time(), 3), "what": what})
        del self.history[:-HISTORY_LIMIT]

    def update_entry(self, text: str, by: str = "agent") -> None:
        """A progress line ("found it in flake.lock:190") shown in the detail view."""
        self.progress.append({"at": round(time.time(), 3), "by": by, "text": text})
        del self.progress[:-PROGRESS_LIMIT]

    @property
    def steps_done(self) -> int:
        return sum(1 for step in self.steps if step.get("done"))


@dataclass
class Board:
    version: int = SCHEMA_VERSION
    seq: int = 0
    tasks: list[Task] = field(default_factory=list)
    # Cards taken off the board with `archive` (`A`). Same shape as a live card
    # — the record is kept whole — plus `archived_at`/`archived_from`.
    archived: list[Task] = field(default_factory=list)


def state_dir() -> Path:
    """Where the board file lives.

    herdr injects `HERDR_PLUGIN_STATE_DIR` for plugin commands; the fallback
    keeps the *same* directory shape so the standalone `herdr-kanban` CLI and
    the in-herdr board open the same board instead of two look-alike files.
    """
    env = os.environ.get("HERDR_PLUGIN_STATE_DIR")
    if env:
        return Path(env).expanduser()
    xdg = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local" / "state")
    return Path(xdg).expanduser() / "herdr" / "plugins" / PLUGIN_ID


def board_path() -> Path:
    env = os.environ.get("KANBAN_BOARD_FILE")
    return Path(env).expanduser() if env else state_dir() / "board.json"


class Store:
    """Loads, mutates, and persists the board file."""

    def __init__(self, path: Path | None = None) -> None:
        self.path = path or board_path()
        self.board = Board()
        self.loaded_at: float = 0.0
        self._mtime: float | None = None
        self._dirty = False

    # -- loading ---------------------------------------------------------

    @classmethod
    def open(cls, path: Path | None = None) -> Store:
        """A store with the board already read — the common case."""
        store = cls(path)
        store.load()
        return store

    def load(self) -> None:
        self._mtime = None
        self._read()

    def _read(self) -> None:
        try:
            stat = self.path.stat()
        except OSError:
            self.board = Board()
            self._mtime = None
            self.loaded_at = time.time()
            return
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError, UnicodeDecodeError):
            # A corrupt board must not take the board down: keep the file for
            # the user to rescue and carry on with an empty in-memory board.
            self.board = Board()
            self._mtime = stat.st_mtime
            self.loaded_at = time.time()
            return
        tasks = raw.get("tasks") if isinstance(raw, dict) else None
        archived = raw.get("archived") if isinstance(raw, dict) else None
        board = Board(
            version=int(raw.get("version") or SCHEMA_VERSION),
            seq=int(raw.get("seq") or 0),
        )
        if isinstance(tasks, list):
            board.tasks = [
                Task.from_dict(item) for item in tasks if isinstance(item, dict)
            ]
        if isinstance(archived, list):
            board.archived = [
                Task.from_dict(item) for item in archived if isinstance(item, dict)
            ]
        if not board.seq:
            # A file that lost `seq` — hand-edited, or written by something else
            # — has to carry on past the highest id on the board. `len(tasks)`
            # would be a *guess* that a gap can make too low: with only `K7`
            # left after four deletions, four adds would re-issue `K7` and the
            # board would have two cards with one name. Codes do not affect
            # this: the counter after the last dash is the same board-wide one.
            # Archived cards count too — archiving `K7` must not free its number.
            board.seq = max(
                (task_seq(task.id) for task in board.tasks + board.archived),
                default=0,
            )
        self.board = board
        self._mtime = stat.st_mtime
        self.loaded_at = time.time()

    def reload(self) -> bool:
        """Re-read if the file changed underneath us. True when it did."""
        try:
            mtime = self.path.stat().st_mtime
        except OSError:
            mtime = None
        if mtime == self._mtime:
            return False
        self._read()
        return True

    @property
    def dirty(self) -> bool:
        return self._dirty

    # -- writing ---------------------------------------------------------

    def payload(self) -> dict[str, Any]:
        """The exact document that would be written right now."""
        return {
            "version": SCHEMA_VERSION,
            "seq": self.board.seq,
            "tasks": [task.to_dict() for task in self.board.tasks],
            "archived": [task.to_dict() for task in self.board.archived],
        }

    def _write(self, payload: dict[str, Any]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_name(f".{self.path.name}.{os.getpid()}.tmp")
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        # Keep the previous generation. Copied rather than renamed: a reader
        # must never see the board file missing, and `_read` treats a missing
        # file as an empty board — which the next write would then persist.
        if self.path.exists():
            with contextlib.suppress(OSError):
                shutil.copy2(self.path, self.backup_path)
        os.replace(tmp, self.path)
        try:
            self._mtime = self.path.stat().st_mtime
        except OSError:
            self._mtime = None
        self._dirty = False

    @property
    def backup_path(self) -> Path:
        return self.path.with_name(self.path.name + ".bak")

    @contextmanager
    def _locked(self) -> Iterator[None]:
        """Serialise read-modify-write across concurrent boards."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        lock_path = self.path.with_name(f".{self.path.name}.lock")
        handle = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(handle, fcntl.LOCK_EX)
            self.reload()
            before = self.payload()
            yield
            # Only write when something actually changed. Mutations that turn
            # out to be no-ops (a status set to the value it already has, an
            # edit with no effective diff, an empty note) would otherwise bump
            # the mtime — waking every other open board's reload — and, worse,
            # rotate board.json.bak so the rollback copy becomes a duplicate of
            # the live file instead of the previous generation.
            after = self.payload()
            if after != before:
                self._write(after)
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)
            os.close(handle)

    # -- queries ---------------------------------------------------------

    @property
    def tasks(self) -> list[Task]:
        return self.board.tasks

    @property
    def archived(self) -> list[Task]:
        return self.board.archived

    def by_id(self, task_id: str) -> Task | None:
        return next((task for task in self.board.tasks if task.id == task_id), None)

    def archived_by_id(self, task_id: str) -> Task | None:
        return next((task for task in self.board.archived if task.id == task_id), None)

    def in_column(self, status: str) -> list[Task]:
        return [task for task in self.board.tasks if task.status == status]

    def columns_with(self, column_ids: list[str]) -> dict[str, list[Task]]:
        """Column id -> tasks, in board order, for the given columns only."""
        grouped: dict[str, list[Task]] = {column_id: [] for column_id in column_ids}
        for task in self.board.tasks:
            if task.status in grouped:
                grouped[task.status].append(task)
        return grouped

    def orphans(self, column_ids: list[str]) -> list[Task]:
        """Tasks whose status is not a column any more (config changed)."""
        known = set(column_ids)
        return [task for task in self.board.tasks if task.status not in known]

    # -- mutations -------------------------------------------------------

    def add(self, **fields: Any) -> Task:
        title = str(fields.get("title", "")).strip() or "Untitled"
        known = {name for name in Task.__dataclass_fields__}
        extra = {key: value for key, value in fields.items() if key in known}
        extra.pop("title", None)
        status = str(extra.pop("status", "") or "backlog")
        # The code is not a field: it is already legible in the id, and storing
        # it twice would let the two disagree. Callers that have the config hand
        # in what `[workspaces]` resolved; a caller that does not (a test, the
        # demo) still gets the label's own slug rather than falling back to `K`.
        code = str(fields.get("workspace_code", "") or "") or slug_code(
            str(extra.get("workspace_label") or extra.get("workspace_id") or "")
        )
        with self._locked():
            self.board.seq += 1
            now = time.time()
            task = Task(
                id=task_id(code, self.board.seq),
                title=title,
                created_at=now,
                updated_at=now,
                status=status,
                **extra,
            )
            # Say who filed it, so the history answers the question the card
            # itself only implies. Agents are the interesting case; a card you
            # wrote reads the way it always has.
            origin = " by agent" if task.created_by == "agent" else ""
            task.note(f"created in {task.status}{origin}")
            self.board.tasks.append(task)
            return task

    def update(self, task_id: str, **fields: Any) -> Task | None:
        with self._locked():
            task = self.by_id(task_id)
            if task is None:
                return None
            changed = [
                key
                for key, value in fields.items()
                if key in Task.__dataclass_fields__ and getattr(task, key) != value
            ]
            if not changed:
                return task
            for key in changed:
                # A status among the edits is a column move, not a field like
                # the others: route it through the same placement every other
                # move uses. `on_edit` (the board's `e` form) reaches the store
                # this way, and setting `status` in place would sort the card
                # into the new column wherever it sat in the old one.
                if key == "status":
                    self._move_to_column(task, fields[key])
                    continue
                setattr(task, key, fields[key])
            task.updated_at = time.time()
            edits = sorted(key for key in changed if key != "status")
            if edits:
                task.note("edited " + ", ".join(edits))
            return task

    def delete(self, task_id: str) -> Task | None:
        """Destroy a card for good, live or archived.

        The board's `d` reaches both: deleting an archived card is how a record
        you no longer want is purged, and the caller stops its agent first just
        as it does for a live one.
        """
        with self._locked():
            task = self.by_id(task_id)
            if task is not None:
                self.board.tasks.remove(task)
                return task
            task = self.archived_by_id(task_id)
            if task is None:
                return None
            self.board.archived.remove(task)
            return task

    def archive(self, task_id: str) -> tuple[Task | None, str]:
        """Take a card off the board, keeping its record.

        The card leaves `tasks` and joins `archived` with the time and column it
        left, which is what `unarchive` restores. Nothing else about it changes:
        archiving is about the board, not the run, so a live agent is left
        running — unlike `delete`, which stops it. The record of a run should
        outlive its place on the board.
        """
        with self._locked():
            task = self.by_id(task_id)
            if task is None:
                already = self.archived_by_id(task_id)
                if already is not None:
                    return already, f"{task_id} is already archived"
                return None, f"no task {task_id} on the board"
            self.board.tasks.remove(task)
            task.archived_from = task.status
            task.archived_at = time.time()
            task.updated_at = task.archived_at
            task.note(f"archived from {task.archived_from}")
            self.board.archived.append(task)
            return task, f"{task.id} archived from {task.archived_from}"

    def unarchive(self, task_id: str) -> tuple[Task | None, str]:
        """Put an archived card back on the board, in the column it left.

        It lands at the end of that column. A card whose column no longer
        exists keeps its stored status and shows up as an orphan, the same as
        any other card the config moved out from under.
        """
        with self._locked():
            task = self.archived_by_id(task_id)
            if task is None:
                live = self.by_id(task_id)
                if live is not None:
                    return live, f"{task_id} is not archived"
                return None, f"no task {task_id} on the board or in the archive"
            self.board.archived.remove(task)
            restore = task.archived_from or task.status
            insert_at = len(self.board.tasks)
            for index, other in enumerate(self.board.tasks):
                if other.status == restore:
                    insert_at = index + 1
            self.board.tasks.insert(insert_at, task)
            task.status = restore
            task.archived_at = 0.0
            task.archived_from = ""
            task.updated_at = time.time()
            task.note(f"restored to {restore}")
            return task, f"{task.id} restored to {restore}"

    def _move_to_column(self, task: Task, status: str) -> bool:
        """Put `task` at the end of `status`, recording the transition.

        Every status change lands the card the same way — at the end of its new
        column, with `<old> -> <new>` in its history — whichever door it came
        through (`set_status`, a dispatch's `hand_over`, or an edit that moved
        the card). Three callers, one rule; a caller that set `status` in place
        would leave the card wherever it sat in the old list order, so the new
        column would be sorted by a position that belonged to another column.
        """
        if task.status == status:
            return False
        previous = task.status
        self.board.tasks.remove(task)
        insert_at = len(self.board.tasks)
        for index, other in enumerate(self.board.tasks):
            if other.status == status:
                insert_at = index + 1
        self.board.tasks.insert(insert_at, task)
        task.status = status
        # Leaving a column releases any explicit park: the hold belongs to the
        # Blocked column, and a move is the human (or the agent) deciding the
        # card is done waiting.
        task.blocked_hold = False
        task.note(f"{previous} -> {status}")
        return True

    def set_status(
        self, task_id: str, status: str, hold: bool = False
    ) -> Task | None:
        """Move a card to another column, landing at the end of it.

        `hold` marks the move as an explicit park rather than the board's own
        reconciliation, and is only meaningful for a card landing in Blocked:
        `Syncer.settle_columns` reads it so a working agent cannot carry the
        card straight back out of the column someone deliberately put it in. A
        `hold=False` on a card that already sits in its column is the release
        path (the working phase that justified the hold is over); it rewrites
        the flag but is not a move and leaves no `->` in the history.
        """
        with self._locked():
            task = self.by_id(task_id)
            if task is None:
                return task
            if self._move_to_column(task, status):
                task.updated_at = time.time()
            if task.blocked_hold != hold:
                task.blocked_hold = hold
                task.updated_at = time.time()
            return task

    def reorder(self, task_id: str, delta: int) -> Task | None:
        """Move a card up/down within its own column."""
        if delta == 0:
            return self.by_id(task_id)
        with self._locked():
            task = self.by_id(task_id)
            if task is None:
                return None
            siblings = self.in_column(task.status)
            index = siblings.index(task)
            target = index + delta
            if not 0 <= target < len(siblings):
                return task
            current_at = self.board.tasks.index(task)
            other = siblings[target]
            other_at = self.board.tasks.index(other)
            self.board.tasks[current_at], self.board.tasks[other_at] = (
                self.board.tasks[other_at],
                self.board.tasks[current_at],
            )
            task.updated_at = time.time()
            return task

    # -- agent-facing writes ---------------------------------------------

    def find_by_title(self, title: str) -> Task | None:
        """The card with this title, ignoring case and whitespace runs.

        Both are ignored because the caller is usually an agent writing a title
        from memory, and the question this answers — "is this already on the
        board?" — is worth answering generously. First match wins: any match is
        enough to stop a second card being filed for the same thing.
        """
        wanted = " ".join((title or "").split()).lower()
        if not wanted:
            return None
        return next(
            (
                task
                for task in self.board.tasks
                if " ".join(task.title.split()).lower() == wanted
            ),
            None,
        )

    def resolve(self, reference: str, pane_id: str = "") -> Task | None:
        """Find a card from `cfg-8`, `K3`, `3`, or the pane the caller runs in.

        Ids are matched case-insensitively: the code is lowercase, and typing
        `CFG-8` is not an error. The bare number is enough on its own, because
        the counter behind it is board-wide — no two cards share one, whatever
        their codes say.

        Agents get their card without being told its id: herdr injects
        `HERDR_PANE_ID` into the pane the agent runs in, and the board records
        that pane when it dispatches. The link is exactly that one recorded
        string, so a card that was never dispatched (or whose agent has exited,
        which clears `pane_id`) resolves to nothing from a pane — callers say
        so and offer the id instead of reporting the card as missing.
        """
        reference = (reference or "").strip()
        if reference:
            wanted = reference.lower()
            for task in self.board.tasks:
                if task.id.lower() == wanted:
                    return task
            number = int(reference) if reference.isdigit() else 0
            if number > 0:
                for task in self.board.tasks:
                    if task_seq(task.id) == number:
                        return task
            return self.find_by_title(reference)
        if pane_id:
            for task in self.board.tasks:
                if task.pane_id and task.pane_id == pane_id:
                    return task
        return None

    def resolve_archived(self, reference: str) -> Task | None:
        """Find an archived card from `cfg-8`, `K3`, `3`, or its title.

        The live board's `resolve` deliberately does not look here: an agent
        that calls `status`/`note` must act on a card that is still on the
        board. `show`, `archive` and `unarchive` opt in, so an archived card
        can still be named by id from a shell.
        """
        reference = (reference or "").strip()
        if not reference:
            return None
        wanted = reference.lower()
        for task in self.board.archived:
            if task.id.lower() == wanted:
                return task
        number = int(reference) if reference.isdigit() else 0
        if number > 0:
            for task in self.board.archived:
                if task_seq(task.id) == number:
                    return task
        title = " ".join(reference.split()).lower()
        return next(
            (
                task
                for task in self.board.archived
                if " ".join(task.title.split()).lower() == title
            ),
            None,
        )

    def set_status_from_agent(
        self,
        task_id: str,
        status: str,
        human_only: Collection[str],
        force: bool = False,
        hold: bool = False,
    ) -> tuple[Task | None, str]:
        """Move a card on an agent's behalf. Returns (task, message).

        `human_only` is the board's own set of columns an agent may not close a
        card into (`Config.human_only_columns`). It is passed in rather than
        hardcoded so the guard and the `agent_may_set` the CLI advertises come
        from one place, and so renaming the Done column cannot quietly hand
        agents the power to close cards.
        """
        if status in human_only and not force:
            return (
                self.by_id(task_id),
                f"{task_id}: refusing to set {status} — that column is yours to"
                " close, not the agent's; pass --force if you mean it (the board's"
                " own keys are unrestricted)",
            )
        task = self.set_status(task_id, status, hold=hold)
        if task is None:
            return None, f"no task {task_id} on the board"
        return task, f"{task.id} -> {status}"

    def set_title(
        self, task_id: str, title: str, source: str = "agent", force: bool = False
    ) -> tuple[Task | None, str]:
        """Rename a card, respecting whether the human has claimed the title.

        A title the human typed is never silently replaced: an agent's title
        then lands in the card's updates instead, where it is visible and one
        edit away from being applied. `force` is the caller saying otherwise —
        the CLI's `--force`, or the board's `agent_title_overrides`, which is a
        standing `--force` for the agent's own titles. A replaced title is kept
        in the card's history (`was: …`), so an override is reversible too.
        """
        cleaned = " ".join((title or "").split())
        with self._locked():
            task = self.by_id(task_id)
            if task is None:
                return None, f"no task {task_id} on the board"
            if not cleaned:
                return task, f"{task.id}: empty title ignored"
            if cleaned == task.title:
                # Renaming to the title the card already has is, for an agent,
                # almost always the capture text coming back: the protocol asks
                # for a name "once you know the real work", and the first thing
                # some runs do is re-send the title they were dispatched with.
                # A bare "unchanged" reads as done; name what the title still
                # is so the card gets named later, at the end of the run.
                if task.title_source != "agent" and not task.title_edited:
                    return (
                        task,
                        f"{task.id}: still the capture title {cleaned!r} — rename it"
                        " to what the work turned out to be",
                    )
                return task, f"{task.id}: title unchanged"

            if source == "user":
                task.original_title = task.original_title or task.title
                task.title = cleaned
                task.title_source = "user"
                task.title_edited = True
                task.updated_at = time.time()
                task.note("title edited by hand")
                return task, f"{task.id} title -> {cleaned}"

            if task.title_edited and not force:
                task.update_entry(f"suggested title: {cleaned}")
                task.updated_at = time.time()
                task.note("agent title suggestion kept as an update")
                return (
                    task,
                    f"{task.id}: kept your title {task.title!r}; "
                    f"recorded {cleaned!r} in its updates instead",
                )

            # The title being replaced, when that title was the human's: the
            # capture title is already kept in `original_title`, and a human
            # rename overwrites that, so without this the name you typed would
            # survive only as the card's current title — gone on the next line.
            replaced = task.title if task.title_edited else ""
            task.original_title = task.original_title or task.title
            task.title = cleaned
            task.title_source = "agent"
            task.updated_at = time.time()
            task.note(
                f"title set by {source}: {cleaned}"
                + (f" (was: {replaced})" if replaced else "")
            )
            return task, (
                f"{task.id} title -> {cleaned} (by {source}"
                + (", replacing yours)" if replaced else ")")
            )

    def add_progress(
        self, task_id: str, text: str, by: str = "agent"
    ) -> tuple[Task | None, str]:
        cleaned = " ".join((text or "").split())
        with self._locked():
            task = self.by_id(task_id)
            if task is None:
                return None, f"no task {task_id} on the board"
            if not cleaned:
                return task, f"{task.id}: empty update ignored"
            task.update_entry(cleaned, by=by)
            task.updated_at = time.time()
            return task, f"{task.id}: update recorded"

    # -- checklists ------------------------------------------------------

    def add_step(
        self, task_id: str, text: str, by: str = "agent"
    ) -> tuple[Task | None, str]:
        cleaned = " ".join((text or "").split())
        with self._locked():
            task = self.by_id(task_id)
            if task is None:
                return None, f"no task {task_id} on the board"
            if not cleaned:
                return task, f"{task.id}: empty step ignored"
            if len(task.steps) >= STEP_LIMIT:
                return task, f"{task.id}: already has {STEP_LIMIT} steps"
            task.steps.append({"text": cleaned, "done": False, "at": 0.0, "by": by})
            task.updated_at = time.time()
            task.note(f"step added: {cleaned}")
            return task, f"{task.id}: step {len(task.steps)} added"

    def set_step(
        self,
        task_id: str,
        index: int,
        done: bool | None = None,
        text: str = "",
        by: str = "agent",
    ) -> tuple[Task | None, str]:
        """Tick, untick, or rename step `index` (1-based, as typed)."""
        with self._locked():
            task = self.by_id(task_id)
            if task is None:
                return None, f"no task {task_id} on the board"
            if not task.steps:
                return task, f"{task.id} has no steps yet — add one first"
            if not 1 <= index <= len(task.steps):
                return task, (
                    f"{task.id} has {len(task.steps)} step(s); {index} is out of range"
                )
            step = task.steps[index - 1]
            if text:
                step["text"] = " ".join(text.split())
            if done is not None:
                step["done"] = done
                step["at"] = time.time() if done else 0.0
                step["by"] = by if done else ""
            task.updated_at = time.time()
            mark = "x" if step.get("done") else " "
            return task, f"{task.id} step {index}: [{mark}] {step.get('text', '')}"

    def remove_step(self, task_id: str, index: int) -> tuple[Task | None, str]:
        with self._locked():
            task = self.by_id(task_id)
            if task is None:
                return None, f"no task {task_id} on the board"
            if not 1 <= index <= len(task.steps):
                return task, (
                    f"{task.id} has {len(task.steps)} step(s); {index} is out of range"
                )
            removed = task.steps.pop(index - 1)
            task.updated_at = time.time()
            task.note(f"step removed: {removed.get('text', '')}")
            return task, f"{task.id}: step {index} removed"

    def step_lines(self, task: Task) -> list[str]:
        """Render a card's checklist, 1-based, for `show` and the detail view."""
        return [
            f"{index}. [{'x' if step.get('done') else ' '}] {step.get('text', '')}"
            for index, step in enumerate(task.steps, start=1)
        ]

    # -- convenience -----------------------------------------------------

    def hand_over(self, task_id: str, status: str, **fields: Any) -> Task | None:
        """Set fields and move columns in one write (used by dispatch)."""
        with self._locked():
            task = self.by_id(task_id)
            if task is None:
                return None
            for key, value in fields.items():
                # `status` is the column argument, not a field like the rest:
                # `_move_to_column` owns placing the card and noting the move.
                if key in Task.__dataclass_fields__ and key != "status":
                    setattr(task, key, value)
            self._move_to_column(task, status)
            task.updated_at = time.time()
            return task
