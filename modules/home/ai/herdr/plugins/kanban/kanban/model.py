"""Joins the task store with live herdr state into a `BoardView`.

This is the only place that decides what a card *shows*: the live agent status
reported by herdr, whether the card's workspace still exists, and which tasks a
filter hides. Keeping it out of the widgets means `--snapshot` and the live app
can never disagree.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field

from . import icons
from .config import Column, Config
from .herdr import Agent, Workspace
from .render import BoardView, CardView, ColumnView, format_age
from .store import Task

# The archive as a board column. It is not a configured column — its cards live
# in `Store.archived`, not in `tasks` — so it is built here rather than read from
# `config.columns`, and shown only when `UiState.show_archived` is on. The id is
# reserved: a configured column called `archived` would collide with it.
ARCHIVED_COLUMN = Column("archived", "Archived")


@dataclass
class LiveState:
    """The last snapshot of herdr's world."""

    workspaces: dict[str, Workspace] = field(default_factory=dict)
    agents: dict[str, Agent] = field(default_factory=dict)
    agents_by_pane: dict[str, Agent] = field(default_factory=dict)
    down: bool = False
    error: str = ""
    # task id -> the monotonic time its live status was first seen in its
    # current value. Maintained by `Syncer.read_live` across ticks; empty for a
    # state built by hand (the demo, the tests, the first tick of a process),
    # which is exactly "untimed" and keeps a card's old behaviour. Monotonic,
    # not wall time: it only ever measures an interval, and a machine sleeping
    # or a clock stepping must not turn it negative.
    status_since: dict[str, float] = field(default_factory=dict)

    def lookup(self, task: Task) -> Agent | None:
        """The live agent for a task, or None when nothing can be confirmed.

        A card is linked to a run by two things, and neither is enough alone:

          - the pane the dispatch opened (`task.pane_id`), which is what the
            board re-prompts, focuses and closes; and
          - the name the dispatch started the agent under (`task.agent_name`,
            the card's slug), which herdr keeps unique among live agents.

        The pane is tried first, because it keeps working after the agent is
        renamed, but it is only trusted once `owns` confirms the agent in it is
        this card's. herdr's own guarantee is that a *closed* pane number is not
        reused (`src/workspace.rs`: "Closed pane numbers are not reused") and
        that numbering survives a normal restart — but that guarantee belongs to
        one herdr session, and the card's pane link lives in `board.json`, which
        does not. A replaced session (a lost `session.json`, a legacy snapshot
        renumbered on restore, a board pointed at another named session) starts
        its counters at `w1`/`p1` again, so a recorded pane id can name a live
        stranger. Trusting it there is not a cosmetic error: `settle_columns`
        would carry the card into Blocked on the stranger's state.

        The name is the identity because it cannot collide — `agent start`
        refuses a duplicate — so a live agent answering to `task.agent_name` is
        the agent this card started, wherever it now sits. `task.slug` is the
        same name for a card whose `agent_name` was never written (an older
        record, or one whose link was cleared): the dispatch names the agent
        after the card, so a lost pane link heals here without re-dispatching.

        Not compared: the tab label, which is the strongest check the board
        makes before *closing* a tab (`KanbanApp.agent_tab`), because it is not
        in the `agent list` snapshot and a third herdr read per tick to
        duplicate what the name already proves is not worth it; and
        `dispatched_at` against the agent's start, because herdr reports no
        start time for an agent at all.
        """
        if task.pane_id:
            agent = self.agents_by_pane.get(task.pane_id)
            if agent is not None and self.owns(task, agent):
                return agent
        if task.agent_name and task.agent_name != task.slug:
            agent = self.agents.get(task.agent_name)
            if agent is not None:
                return agent
        return self.agents.get(task.slug)

    def owns(self, task: Task, agent: Agent) -> bool:
        """Whether the agent herdr reports in `task.pane_id` is this card's.

        Only what `agent list` gives can be checked: the name the agent was
        started under, and the workspace it is in. A card that recorded no name
        (an old record, or one whose link was cleared) has nothing to compare,
        so its pane is trusted the way it always was — the alternative would be
        to disown every dispatch whose record the board did not write, which is
        worse than the reuse this guards against.
        """
        # Strict, including a live agent with no name at all: a card that says
        # its agent was started under one is not answered by a pane holding a
        # screen-detected stranger (`Agent.name` is then the kind label, or "").
        if task.agent_name and agent.name != task.agent_name:
            return False
        if task.workspace_id and agent.workspace_id:
            # A worktree dispatch is the exception: the card's `workspace_id`
            # stays the repo the checkout was forked from, while the agent runs
            # in the workspace `herdr worktree create` opened for it.
            allowed = {task.workspace_id}
            if task.worktree_workspace_id:
                allowed.add(task.worktree_workspace_id)
            if agent.workspace_id not in allowed:
                return False
        return True

    def for_task(self, task: Task) -> tuple[str, bool]:
        """(live status, agent online) for a task."""
        agent = self.lookup(task)
        if agent is not None:
            return agent.status, True
        if task.dispatched_at:
            return "exited", False
        return "", False

    def workspace_ok(self, task: Task) -> bool:
        if not task.workspace_id:
            return True
        if self.down or not self.workspaces:
            return True  # cannot tell; do not cry wolf
        return task.workspace_id in self.workspaces

    def workspace_label(self, task: Task) -> str:
        workspace = self.workspaces.get(task.workspace_id)
        if workspace is not None:
            return workspace.label
        return task.workspace_label or task.workspace_id

    def workspace_number(self, task: Task) -> int:
        workspace = self.workspaces.get(task.workspace_id)
        return workspace.number if workspace else 0

    def kind_hint(self, task: Task) -> str:
        """What kind of agent this card's agent is, as far as anything knows.

        The task's own record is authoritative when the board dispatched it.
        Otherwise the live agent is asked — its `harness_logo` token is the
        vendor mark herdr-radar published for it, and its terminal title
        usually names the tool — and only then does the title get guessed at,
        which is the weakest signal on the card and the reason the kind is
        shown at all: a wrong guess is visible instead of silent.
        """
        if task.agent_kind:
            return task.agent_kind
        agent = self.lookup(task)
        if agent is not None:
            guessed = icons.infer_kind(
                name=agent.name, title=agent.title, logo=agent.logo
            )
            if guessed:
                return guessed
        return icons.infer_kind(task.title)


@dataclass
class UiState:
    """Selection and filtering, owned by the app."""

    selected_id: str = ""
    selected_column: int = 0
    filter_text: str = ""
    workspace_filter: str = ""
    # The `!` key: only the cards whose agents are blocked, wherever they live.
    only_blocked: bool = False
    # The `v` key: whether the archive is drawn as a column at the right edge.
    # Off by default — archived cards are out of play, and the board is for the
    # work in it.
    show_archived: bool = False
    notice: str = ""
    frame: int = 0
    scroll: dict[str, int] = field(default_factory=dict)


def query_terms(query: str) -> list[str]:
    """Split a filter into lowercased terms, keeping quoted phrases whole.

    `flake lock` is two terms that may appear anywhere on the card; `"flake
    lock"` is one term that must appear as written — which is what you want when
    searching for a phrase out of a note.
    """
    terms: list[str] = []
    current: list[str] = []
    quote = ""
    for character in query:
        if quote:
            if character == quote:
                quote = ""
            else:
                current.append(character)
        elif character in "\"'":
            quote = character
        elif character.isspace():
            if current:
                terms.append("".join(current))
                current = []
        else:
            current.append(character)
    if current:
        terms.append("".join(current))
    return [term.lower() for term in terms]


def sorted_cards(tasks: list[Task], mode: str) -> list[Task]:
    """`tasks` in the order the board is configured to show them.

    `manual` is the board file's list order, which is what `J`/`K` edit and
    what `Store` keeps whatever this says. `updated` — the default — puts the
    most recently touched card first, so a column answers "what is moving"
    without reading ages: a card an agent just picked up rises on its own, and
    a card nothing has happened to sinks out of the way.

    Only two things are ordered here, and neither is stored: the board file is
    not rewritten because the clock moved. The sort is stable, so cards whose
    timestamps are equal — two notes in the same tick, a hand-written file —
    keep the manual order rather than shuffling between two reads, and a card
    with no `updated_at` at all (0.0, hand-edited) sinks to the bottom instead
    of looking like the freshest work on the board.
    """
    if mode != "updated":
        return tasks
    return sorted(tasks, key=lambda task: task.updated_at, reverse=True)


def task_matches(task: Task, query: str, workspace_label: str) -> bool:
    """Every term must appear somewhere on the task (quoted phrases as one)."""
    terms = query_terms(query)
    if not terms:
        return True
    fields = (
        task.id,
        task.title,
        task.notes,
        task.workspace_id,
        workspace_label,
        task.agent_kind,
        task.agent_name,
        " ".join(task.labels),
    )
    # Collapse whitespace so a phrase can span a line break in the notes.
    haystack = " ".join(" ".join(fields).split()).lower()
    return all(term in haystack for term in terms)


def task_visible(task: Task, live: LiveState, ui: UiState) -> bool:
    """Whether a card passes the active filters.

    Shared by the live columns and the archived one, so a filter cannot mean one
    thing on the board and another in the archive.
    """
    if ui.only_blocked and live.for_task(task)[0] != "blocked":
        return False
    if ui.workspace_filter:
        if (
            task.workspace_id != ui.workspace_filter
            and live.workspace_label(task) != ui.workspace_filter
        ):
            return False
    return task_matches(task, ui.filter_text, live.workspace_label(task))


def _card_view(task: Task, live: LiveState, ui: UiState, config: Config) -> CardView:
    """One card's live state, resolved once. Live and archived cards alike.

    Two things the raw live status cannot tell on its own are decided here, both
    timed from `LiveState.status_since`:

      - a card whose agent has sat idle in In Progress for `idle_stale_minutes`
        is flagged (`idle_stale`), so a card an agent finished but forgot to
        move carries a hint instead of looking freshly picked up;
      - a card whose agent is gone stops saying `no agent` once
        `exited_decay_minutes` have passed since the board saw it exit (`status`
        decays to ""), because "exited" is news only while it is recent —
        forever it is just a card with no status.

    Both are display-only. `Syncer` and the detail modal keep the raw
    `for_task` status, so reconciliation (which never acts on `idle` or
    `exited`) and `⏎` are unchanged; this is the layer that owns "what a card
    shows", and the decay belongs here rather than in `for_task` for exactly
    that reason. A card with no entry in `status_since` — a hand-built state, or
    one the board has only just started watching — is untimed and behaves as it
    always did.
    """
    status, online = live.for_task(task)
    since = live.status_since.get(task.id)
    age = max(0.0, time.monotonic() - since) if since else 0.0
    if (
        status == "exited"
        and config.exited_decay_minutes > 0
        and age >= config.exited_decay_minutes * 60
    ):
        status = ""
    idle_stale = (
        status == "idle"
        and task.status in config.columns_with_role("doing")
        and config.idle_stale_minutes > 0
        and age >= config.idle_stale_minutes * 60
    )
    return CardView(
        task=task,
        status=status,
        status_age=age,
        idle_stale=idle_stale,
        agent_online=online,
        workspace_ok=live.workspace_ok(task),
        agent_kind=live.kind_hint(task),
        workspace_number=live.workspace_number(task),
        frame=ui.frame,
    )


def visible_tasks(
    config: Config,
    tasks: list[Task],
    live: LiveState,
    ui: UiState,
) -> tuple[list[Task], int, int]:
    """(visible tasks, hidden by filter, in unknown columns)."""
    known = set(config.column_ids)
    unknown = [task for task in tasks if task.status not in known]
    candidates = [task for task in tasks if task.status in known]
    shown = [task for task in candidates if task_visible(task, live, ui)]
    return shown, len(candidates) - len(shown), len(unknown)


def build_view(
    config: Config,
    tasks: list[Task],
    live: LiveState,
    ui: UiState,
    width: int,
    height: int,
    board_path: str = "",
    icon_mode: str = "brand",
    archived: list[Task] | None = None,
) -> BoardView:
    archived = archived or []
    shown, hidden, orphaned = visible_tasks(config, tasks, live, ui)

    columns: list[ColumnView] = []
    for index, column in enumerate(config.columns):
        # Bucket first, then sort: a column is ordered on its own terms, and
        # the one shared `sorted_cards` call means the board, the archived
        # column and `herdr-kanban list` cannot disagree about the order.
        in_column = [task for task in shown if task.status == column.id]
        cards = [
            _card_view(task, live, ui, config)
            for task in sorted_cards(in_column, config.sort)
        ]
        columns.append(
            ColumnView(
                column=column,
                cards=cards,
                accent=icons.column_accent(index),
                wip_limit=config.wip_limit(column.id),
                scroll=ui.scroll.get(column.id, 0),
            )
        )

    if ui.show_archived:
        archived_cards: list[CardView] = []
        for task in sorted_cards(archived, config.sort):
            if task_visible(task, live, ui):
                archived_cards.append(_card_view(task, live, ui, config))
            else:
                hidden += 1
        columns.append(
            ColumnView(
                column=ARCHIVED_COLUMN,
                cards=archived_cards,
                accent=icons.column_accent(len(columns)),
                scroll=ui.scroll.get(ARCHIVED_COLUMN.id, 0),
            )
        )

    notice = ui.notice
    if orphaned and not notice:
        notice = f"{orphaned} task(s) in a column this config no longer has"

    view = BoardView(
        columns=columns,
        width=width,
        height=height,
        selected_id=ui.selected_id,
        selected_column=ui.selected_column,
        tasks_total=len(tasks) + (len(archived) if ui.show_archived else 0),
        hidden_total=hidden + orphaned,
        filter_text=ui.filter_text,
        workspace_filter=ui.workspace_filter,
        only_blocked=ui.only_blocked,
        show_archived=ui.show_archived,
        icon_mode=icon_mode,
        show_age=config.show_age,
        stale_after_days=config.stale_after_days,
        show_agent_kind=config.show_agent_kind,
        show_status_word=config.show_status_word,
        notice=notice,
        board_path=board_path,
        herdr_down=live.down,
    )
    keep_selection_visible(view, ui)
    return view


def keep_selection_visible(view: BoardView, ui: UiState) -> None:
    """Scroll each column so the selected card is on screen."""
    visible = view.visible_cards
    for column in view.columns:
        count = column.count
        column.scroll = max(0, min(column.scroll, max(0, count - visible)))
        if not view.selected_id:
            ui.scroll[column.column.id] = column.scroll
            continue
        index = next(
            (
                position
                for position, card in enumerate(column.cards)
                if card.task.id == view.selected_id
            ),
            None,
        )
        if index is None:
            ui.scroll[column.column.id] = column.scroll
            continue
        if index < column.scroll:
            column.scroll = index
        elif index >= column.scroll + visible:
            column.scroll = index - visible + 1
        ui.scroll[column.column.id] = column.scroll


def selection_after_move(view: BoardView, ui: UiState) -> str:
    """Pick a sensible card to select in the (possibly changed) view."""
    if view.card(ui.selected_id):
        return ui.selected_id
    if ui.selected_column < len(view.columns):
        cards = view.columns[ui.selected_column].cards
        if cards:
            return cards[0].task.id
    for column in view.columns:
        if column.cards:
            return column.cards[0].task.id
    return ""


__all__ = [
    "ARCHIVED_COLUMN",
    "LiveState",
    "UiState",
    "build_view",
    "format_age",
    "keep_selection_visible",
    "query_terms",
    "selection_after_move",
    "sorted_cards",
    "task_matches",
    "task_visible",
    "visible_tasks",
]
