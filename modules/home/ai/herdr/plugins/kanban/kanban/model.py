"""Joins the task store with live herdr state into a `BoardView`.

This is the only place that decides what a card *shows*: the live agent status
reported by herdr, whether the card's workspace still exists, and which tasks a
filter hides. Keeping it out of the widgets means `--snapshot` and the live app
can never disagree.
"""

from __future__ import annotations

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

    def lookup(self, task: Task) -> Agent | None:
        """The live agent for a task.

        Looked up by pane first: herdr's `agent` field is a kind label for an
        agent started without a name (it reports "pi"), so the recorded pane is
        the dependable link between a card and a running agent.
        """
        if task.pane_id:
            agent = self.agents_by_pane.get(task.pane_id)
            if agent is not None:
                return agent
        if task.agent_name:
            return self.agents.get(task.agent_name)
        return None

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


def _card_view(task: Task, live: LiveState, ui: UiState) -> CardView:
    """One card's live state, resolved once. Live and archived cards alike."""
    status, online = live.for_task(task)
    return CardView(
        task=task,
        status=status,
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
        cards = [
            _card_view(task, live, ui) for task in shown if task.status == column.id
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
        for task in archived:
            if task_visible(task, live, ui):
                archived_cards.append(_card_view(task, live, ui))
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
    "task_matches",
    "task_visible",
    "visible_tasks",
]
