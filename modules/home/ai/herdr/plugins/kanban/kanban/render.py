"""Board rendering.

The whole board is drawn as a list of styled `rich.text.Text` lines computed from
a `BoardView` — one code path for the live Textual widget, the `--snapshot` text
dump, and hit-testing: the same function computes the rectangles it drew, so a
click can never disagree with what is on screen.
"""

from __future__ import annotations

import textwrap
import time
from dataclasses import dataclass, field
from pathlib import Path

from rich.cells import cell_len, chop_cells
from rich.text import Text

from . import icons
from .config import Column
from .store import Task, task_seq

CARD_HEIGHT = 5
TITLE_LINES = 2
COLUMN_GAP = 1
MIN_COLUMN_WIDTH = 14
MAX_COLUMN_WIDTH = 34
HEADER_Y = 0
COLUMN_HEADER_Y = 1
CARDS_Y = 2


def format_age(timestamp: float | None) -> str:
    """Compact relative age, e.g. "2h" — for the detail view and cards."""
    if not timestamp:
        return "—"
    seconds = max(0.0, time.time() - timestamp)
    if seconds < 90:
        return f"{int(seconds)}s"
    minutes = seconds / 60
    if minutes < 90:
        return f"{int(minutes)}m"
    hours = minutes / 60
    if hours < 36:
        return f"{int(hours)}h"
    days = hours / 24
    if days < 14:
        return f"{int(days)}d"
    return f"{int(days / 7)}w"


@dataclass
class CardView:
    """A task plus the live herdr state the card shows."""

    task: Task
    status: str = ""  # live herdr status; "" when no agent is running for it
    agent_online: bool = False
    workspace_ok: bool = True
    # The kind this card's agent is (or was started as), resolved once in
    # `model.build_view`: the task's own kind when the board dispatched it, else
    # a guess from the live agent's mark and title. Empty means nobody knows,
    # and the card says so by showing no agent mark at all rather than a
    # stand-in that would read as the wrong vendor.
    agent_kind: str = ""
    # herdr's workspace number, for the dot's colour. 0 = not in the live list.
    workspace_number: int = 0
    frame: int = 0

    @property
    def is_blocked(self) -> bool:
        return self.status == "blocked"

    @property
    def is_done(self) -> bool:
        return self.status == "done"


@dataclass
class ColumnView:
    column: Column
    cards: list[CardView] = field(default_factory=list)
    accent: str = ""
    wip_limit: int | None = None
    scroll: int = 0

    @property
    def count(self) -> int:
        return len(self.cards)


@dataclass
class BoardView:
    columns: list[ColumnView]
    width: int
    height: int
    selected_id: str = ""
    selected_column: int = 0
    tasks_total: int = 0
    hidden_total: int = 0
    filter_text: str = ""
    workspace_filter: str = ""
    only_blocked: bool = False
    # Whether the archive is drawn as a column at the right edge (`v`).
    show_archived: bool = False
    icon_mode: str = "unicode"
    show_age: bool = True
    stale_after_days: float = 3.0
    show_agent_kind: bool = True
    show_status_word: bool = True
    notice: str = ""
    board_path: str = ""
    herdr_down: bool = False

    @property
    def cards_height(self) -> int:
        return max(CARD_HEIGHT, self.height - 3)

    @property
    def visible_cards(self) -> int:
        return max(1, self.cards_height // CARD_HEIGHT)

    def cards(self) -> list[CardView]:
        return [card for column in self.columns for card in column.cards]

    def card(self, task_id: str) -> CardView | None:
        return next((card for card in self.cards() if card.task.id == task_id), None)


@dataclass
class CardRect:
    task_id: str
    column: int
    x: int
    y: int
    width: int
    height: int = CARD_HEIGHT


@dataclass
class Layout:
    width: int
    height: int
    column_x: list[int] = field(default_factory=list)
    column_width: int = 0
    cards: dict[str, CardRect] = field(default_factory=dict)
    order: list[tuple[int, str]] = field(default_factory=list)

    def card_at(self, x: int, y: int) -> str | None:
        for task_id, rect in self.cards.items():
            if rect.x <= x < rect.x + rect.width and rect.y <= y < rect.y + rect.height:
                return task_id
        return None

    def column_at(self, x: int, y: int) -> int | None:
        for index, left in enumerate(self.column_x):
            if y < COLUMN_HEADER_Y:
                continue
            right = left + self.column_width
            if left <= x < right:
                return index
        return None


# -- text helpers ------------------------------------------------------------


def chop(text: str, width: int) -> str:
    """The longest prefix of `text` that fits in `width` cells.

    `rich.cells.chop_cells` returns a list of chunks (it splits at the cut), so
    the first element is the part that fits. Centralised here because every
    call site wants a string back, not a list.
    """
    if width <= 0:
        return ""
    if cell_len(text) <= width:
        return text
    return chop_cells(text, width)[0]


def truncate(text: str, width: int) -> str:
    """Collapse whitespace and clip to `width` *cells* with an ellipsis.

    Cells, not characters: a wide glyph (CJK, emoji) occupies two of them, and
    measuring with `len()` would let the card underneath a title overflow its
    own box.
    """
    text = " ".join(text.split())
    if width <= 0:
        return ""
    if cell_len(text) <= width:
        return text
    if width == 1:
        return "…"
    return chop(text, width - 1) + "…"


def pad(text: str, width: int) -> str:
    return text if cell_len(text) >= width else text + " " * (width - cell_len(text))


def wrap_title(text: str, width: int, lines: int = TITLE_LINES) -> list[str]:
    """Word-wrap a title into at most `lines` rows, ellipsising the overflow."""
    text = " ".join(text.split())
    if width <= 1:
        return [""] * lines
    # textwrap counts characters, so a line of wide glyphs can still be too
    # wide for the card; chop each line to the cell budget afterwards.
    wrapped = [
        chop(row, width)
        for row in (textwrap.wrap(text, width=width, break_long_words=True) or [""])
    ]
    if len(wrapped) > lines:
        head = wrapped[: lines - 1]
        head.append(truncate(" ".join(wrapped[lines - 1 :]), width))
        wrapped = head
    return wrapped + [""] * (lines - len(wrapped))


def short_path(path: str, width: int = 40) -> str:
    """~/…-style path, keeping the last two components when it is long."""
    if not path:
        return ""
    home = str(Path.home())
    shown = path.replace(home, "~") if path.startswith(home) else path
    if len(shown) <= width:
        return shown
    parts = [part for part in shown.split("/") if part]
    if len(parts) >= 2:
        return "…/" + "/".join(parts[-2:])
    return truncate(shown, width)


def spread(left: Text, right: Text, width: int) -> Text:
    """One line with `left` flush left and `right` flush right.

    When there is not enough room the right side is ellipsized rather than
    dropped: a squeezed column header should still say which numbers belong to
    it. `left` always wins, since it carries the label.
    """
    gap = width - left.cell_len - right.cell_len
    line = Text()
    if gap >= 1 or not right.cell_len:
        line.append_text(left)
        if gap >= 1:
            line.append(" " * gap)
            line.append_text(right)
        return line

    room = width - left.cell_len - 1
    if room <= 0:
        # No room for anything but the label; crop it to the pane.
        line.append_text(left)
        line.truncate(width, overflow="crop")
        return line
    trimmed = right.copy()
    trimmed.truncate(room, overflow="ellipsis")
    line.append_text(left)
    line.append(" ")
    line.append_text(trimmed)
    return line


def fit(runs: list[tuple[str, str]], width: int) -> Text:
    """Pack (text, style) runs into exactly `width` cells (never more)."""
    line = Text()
    remaining = max(0, width)
    for text, style in runs:
        if remaining <= 0:
            break
        chunk = chop(text, remaining)
        if chunk:
            line.append(chunk, style=style)
            remaining -= cell_len(chunk)
    if remaining > 0:
        line.append(" " * remaining)
    return line


# -- geometry ----------------------------------------------------------------


def compute_layout(view: BoardView) -> Layout:
    layout = Layout(width=view.width, height=view.height)
    count = max(1, len(view.columns))
    usable = max(1, view.width - (count - 1) * COLUMN_GAP)
    width = max(MIN_COLUMN_WIDTH, min(MAX_COLUMN_WIDTH, usable // count))
    layout.column_width = width
    layout.column_x = [index * (width + COLUMN_GAP) for index in range(count)]

    for index, column in enumerate(view.columns):
        offset = max(0, column.scroll)
        for position in range(min(view.visible_cards, max(0, column.count - offset))):
            card = column.cards[offset + position]
            rect = CardRect(
                task_id=card.task.id,
                column=index,
                x=layout.column_x[index],
                y=CARDS_Y + position * CARD_HEIGHT,
                width=width,
            )
            layout.cards[card.task.id] = rect
            layout.order.append((index, card.task.id))
    return layout


# -- cards -------------------------------------------------------------------


def _staleness_style(age_seconds: float, stale_after_days: float) -> str:
    """Age tint: quiet, then yellow, then red at twice the stale window."""
    if stale_after_days <= 0:
        return icons.PALETTE["overlay0"]
    days = age_seconds / 86400
    if days >= stale_after_days * 2:
        return icons.PALETTE["red"]
    if days >= stale_after_days:
        return icons.PALETTE["yellow"]
    return icons.PALETTE["overlay0"]


def id_badge_style(
    card: CardView, selected: bool, show_age: bool, stale_after_days: float
) -> str:
    """The colour of the `K3` in a card's top rule.

    Two things can claim it. A live state that the border has no colour of its
    own for — a working agent, an idle one, one that has exited — because the
    badge sits in the same place on every card, so scanning a column of them
    answers "what is running". And a card that has gone stale, but only when the
    age is hidden: `stale_after_days` should not go quiet just because its usual
    home (`show_age`) did. Blocked and done are left alone; they already colour
    the whole border, and a second copy of the same news is noise.
    """
    if selected:
        return f"bold {icons.PALETTE['lavender']}"
    if card.status in ("working", "idle", "unknown", "exited"):
        return f"bold {icons.status_color(card.status)}"
    if not card.status and not show_age and card.task.updated_at:
        age_seconds = time.time() - card.task.updated_at
        if stale_after_days > 0 and age_seconds >= stale_after_days * 86400:
            return f"bold {_staleness_style(age_seconds, stale_after_days)}"
    return "bold"


# How long a tail token lives as the column narrows: a token is dropped once
# the stage reaches its level. The numbers therefore *are* the drop order, and
# the order is an argument, not a preference.
#
# The age goes first — it is the least specific thing on the card and comes back
# the moment the column is wider, but nothing else says "this has been sitting
# here three days". Then the step counter, which nothing else carries either.
# The agent's kind goes before its mark: a mark needs no room, and `π` alone
# still reads as pi. Nothing here is a state token — the live state lives on the
# card's bottom rule, which is empty at every card width (see `_card_rule`).
_DROP_AGE = 1
_DROP_STEPS = 2
_DROP_AGENT_KIND = 3
_DROP_AGENT_MARK = 4


def card_meta_runs(
    card: CardView,
    inner: int,
    mode: str,
    show_age: bool = True,
    stale_after_days: float = 3.0,
    show_agent_kind: bool = True,
) -> list[tuple[str, str]]:
    """The card's second row: workspace on the left, the agent on the right.

    The tail reads, in order: step progress, age, then the agent's mark and kind
    (`π pi`). It shrinks from the least specific end as the column narrows — see
    the levels above. The workspace label is never dropped, it just truncates.
    An age under 90s is omitted entirely: "0s" is noise that would otherwise
    crowd the tail on every fresh card. The live state is deliberately *not*
    here; it is on the bottom rule where there is always room for it.
    """
    task = card.task
    kind = card.agent_kind or task.agent_kind or icons.infer_kind(task.title)
    agent_glyph = icons.agent_glyph(kind, mode) if kind else ""

    # (text, style, drop level) in visual order. The kind's own name is shown
    # exactly as herdr spells it (`--kind`), so what the card says is what the
    # dispatch would have said.
    tokens: list[tuple[str, str, int]] = []
    if task.steps:
        tokens.append(
            (
                f"{task.steps_done}/{len(task.steps)}",
                icons.PALETTE["green"]
                if task.steps_done == len(task.steps)
                else icons.PALETTE["teal"],
                _DROP_STEPS,
            )
        )
    if show_age and task.updated_at:
        age_seconds = time.time() - task.updated_at
        if age_seconds >= 90:
            tokens.append(
                (
                    format_age(task.updated_at),
                    _staleness_style(age_seconds, stale_after_days),
                    _DROP_AGE,
                )
            )
    if agent_glyph:
        tokens.append((agent_glyph, icons.agent_color(kind), _DROP_AGENT_MARK))
        if show_agent_kind:
            tokens.append((kind, icons.PALETTE["overlay2"], _DROP_AGENT_KIND))

    # The dot carries its workspace's colour, so a board of several workspaces
    # is scannable without reading a single label. The label itself stays neutral
    # (or red, when the workspace is gone) so that the agent's mark is the only
    # other coloured thing on the row.
    dot_style = (
        icons.workspace_accent(card.workspace_number)
        if card.workspace_ok
        else icons.PALETTE["red"]
    )
    label_style = icons.PALETTE["overlay2" if card.workspace_ok else "red"]
    dot = "▪" if task.workspace_id else "▫"
    if not card.workspace_ok:
        dot = "⚠"
    prefix_width = 2  # dot + space

    # The tail is fitted first and the label keeps what is left, both measured
    # in cells. A workspace label that is already short (`argo`) hands its unused
    # budget to the tail rather than leaving a gap, which is the difference
    # between a card still showing its age and one that has already dropped it.
    # The loop drops one level at a time, while the label is being cut below its
    # own minimum.
    levels = sorted({level for _, _, level in tokens})
    workspace = task.workspace_label or task.workspace_id or "no workspace"
    label_minimum = min(len("workspace"), cell_len(workspace), max(4, inner // 3))

    def tail_tokens(stage: int) -> list[tuple[str, str]]:
        return [(text, style) for text, style, level in tokens if level > stage]

    def label_for(tail: list[tuple[str, str]]) -> str:
        room = inner - prefix_width - (_tail_width(tail) + 1 if tail else 0)
        return truncate(workspace, max(0, room))

    stage = 0
    tail = tail_tokens(stage)
    label = label_for(tail)
    while tail and cell_len(label) < label_minimum:
        wider = [level for level in levels if level > stage]
        if not wider:
            break
        stage = wider[0]
        tail = tail_tokens(stage)
        label = label_for(tail)
    tail_width = _tail_width(tail)
    label_width = cell_len(label)

    runs: list[tuple[str, str]] = [(dot, dot_style)]
    if inner > prefix_width:
        runs.append((" ", ""))
    runs.append((label, label_style))
    filler = max(
        0, inner - prefix_width - label_width - tail_width - (1 if tail else 0)
    )
    runs.append((" " * filler, ""))
    if tail:
        runs.append((" ", ""))
        for index, (text, style) in enumerate(tail):
            if index:
                runs.append((" ", ""))
            runs.append((text, style))
    return runs


def _tail_width(tail: list[tuple[str, str]]) -> int:
    """Cells a run of tail tokens occupies, including single-space separators.

    Cells, not characters: radar's `text` register has a double-width mark in it
    (kimi's `✨`), and a `len()` here would hand the workspace label one cell too
    many and push the tail past the card's border.
    """
    if not tail:
        return 0
    return sum(cell_len(text) for text, _ in tail) + len(tail) - 1


def _card_rule(
    card: CardView, width: int, mode: str, border_style: str, show_status_word: bool
) -> Text:
    """The card's bottom rule, which carries its live state.

    The state mark and its word live here rather than in the meta row because the
    row is where the scarce cells are: a six-column board gives a card about
    twenty of them, already shared between the workspace label, the age, the step
    counter and the agent's kind — which is why a status word in the row only
    ever survived on a 210-column terminal. The rule below the row is empty at
    every card width, so the state can always be spelled out. A card with no
    agent keeps a plain rule, and the word alone drops when the rule is too
    narrow for it (`ui.show_status_word = false` drops it everywhere).
    """
    line = Text("╰", style=border_style)
    inner = max(0, width - 2)
    lead = 2
    room = inner - lead - 2  # the spaces either side of the content are content
    content = ""
    if card.status:
        mark = icons.status_glyph(card.status, card.frame, mode)
        word = f"{mark} {icons.status_label(card.status)}"
        if show_status_word and cell_len(word) <= room:
            content = word
        elif cell_len(mark) <= room:
            content = mark
    if content:
        line.append("─" * lead, style=border_style)
        line.append(" ")
        line.append(content, style=icons.status_color(card.status))
        line.append(" ")
        # Measured rather than computed: the closing ╯ and the trimmed card
        # width are the only things that matter, and the arithmetic that gets
        # there is not worth re-deriving by hand.
        line.append("─" * max(0, width - line.cell_len - 1), style=border_style)
    else:
        line.append("─" * inner, style=border_style)
    line.append("╯", style=border_style)
    return line


def render_card(
    card: CardView,
    width: int,
    selected: bool,
    mode: str,
    show_age: bool = True,
    stale_after_days: float = 3.0,
    show_agent_kind: bool = True,
    show_status_word: bool = True,
) -> list[Text]:
    """A 4-row boxed card: id badge in the top rule, title, meta, state rule."""
    task = card.task
    inner = max(0, width - 4)
    # Border badges: priority, and a quill when the agent named the card. No space
    # between them — the top rule is the only place a card can be short of cells.
    priority_glyph = icons.priority_glyph(task.priority)
    quill = "✎" if task.title_source == "agent" else ""
    badges = priority_glyph + quill
    label = f" {task.id} "
    # The id shares the top rule with the badges, and a coded id is four cells
    # longer than the `K8` it replaced. When it will not fit, the *code* is what
    # goes: the counter behind it is board-wide unique, so ` 8 ` still names one
    # card, and the meta row below still spells the workspace out. Same rule as
    # the meta row's tokens — the least important one drops first — and the same
    # reason: a clipped rule loses its `╮` corner, which reads as a broken card.
    room = width - 3 - cell_len(badges)
    if cell_len(label) > room:
        counter = f" {task_seq(task.id)} "
        if cell_len(counter) <= room:
            label = counter

    if selected:
        border_style = f"bold {icons.PALETTE['text']}"
    elif card.is_blocked:
        border_style = icons.PALETTE["red"]
    elif card.is_done:
        border_style = icons.PALETTE["green"]
    elif card.status == "working":
        border_style = icons.PALETTE["surface2"]
    else:
        border_style = icons.PALETTE["surface1"]

    top = Text()
    top.append("╭", style=border_style)
    top.append(label, style=id_badge_style(card, selected, show_age, stale_after_days))
    if priority_glyph:
        top.append(priority_glyph, style=icons.priority_color(task.priority))
    if quill:
        # The agent's mark on the name gets its own colour and not the
        # priority's: borrowing that made a quill on an urgent card look urgent
        # and a quill on a normal card all but invisible.
        top.append(quill, style=icons.PALETTE["lavender"])
    top.append(
        "─" * max(0, width - 2 - cell_len(label) - cell_len(badges)),
        style=border_style,
    )
    top.append("╮", style=border_style)

    bottom = _card_rule(card, width, mode, border_style, show_status_word)

    title_style = "bold" if selected and not card.is_done else ""
    if card.is_done:
        title_style = "dim"
    title_rows = [
        fit([(row, title_style)], inner) for row in wrap_title(task.title, inner)
    ]
    meta = fit(
        card_meta_runs(
            card,
            inner,
            mode,
            show_age,
            stale_after_days,
            show_agent_kind,
        ),
        inner,
    )

    background = "on " + icons.PALETTE["surface0"] if selected else ""

    def body(content: Text) -> Text:
        if background:
            content.stylize(background)
        line = Text()
        line.append("│", style=border_style)
        line.append(" ")
        line.append_text(content)
        line.append(" ")
        line.append("│", style=border_style)
        return line

    return [top, *(body(row) for row in title_rows), body(meta), bottom]


def render_column_header(
    column: ColumnView, width: int, index: int, selected: bool, visible: int = 0
) -> Text:
    """A column's heading: its label, how full it is, and what is off screen.

    `visible` is how many cards fit in the pane. When a column holds more than
    that — or has been scrolled down — the count is flanked by `▴`/`▾`, because a
    column of cards that starts mid-list looks exactly like a column that starts
    at the top.
    """
    accent = column.accent or icons.column_accent(index)
    left = Text()
    left.append("▎", style=f"bold {accent}")
    left.append(column.column.label, style=f"bold {accent}" if selected else accent)
    right = Text()
    above = column.scroll > 0
    below = visible > 0 and column.scroll + visible < column.count
    if above:
        right.append("▴", style=icons.PALETTE["overlay1"])
    if column.wip_limit:
        style = (
            icons.PALETTE["red"]
            if column.count >= column.wip_limit
            else icons.PALETTE["overlay0"]
        )
        right.append(f"{column.count}/{column.wip_limit}", style=style)
    else:
        right.append(str(column.count), style=icons.PALETTE["overlay0"])
    if below:
        right.append("▾", style=icons.PALETTE["overlay1"])
    if selected:
        right.append(" ▸", style=f"bold {accent}")
    return spread(left, right, width)


def _empty_marker(width: int, label: str = "·") -> Text:
    return fit([(label, icons.PALETTE["surface2"])], width)


def _empty_slot(width: int) -> list[Text]:
    """A faint marker in the middle of a column that has no cards at all."""
    rows = [Text() for _ in range(CARD_HEIGHT)]
    rows[CARD_HEIGHT // 2] = _empty_marker(width)
    return rows


# -- board -------------------------------------------------------------------


def header_line(view: BoardView) -> Text:
    left = Text()
    left.append("▦ ", style=f"bold {icons.PALETTE['mauve']}")
    left.append("Kanban", style=f"bold {icons.PALETTE['text']}")
    left.append(
        f"  ·  {view.workspace_filter or 'all workspaces'}",
        style=icons.PALETTE["overlay1"],
    )
    if view.filter_text:
        left.append(f"  ·  /{view.filter_text}", style=icons.PALETTE["yellow"])
    if view.only_blocked:
        left.append("  ·  needs you", style=icons.PALETTE["red"])
    if view.notice:
        left.append(f"  ·  {view.notice}", style=icons.PALETTE["lavender"])

    right = Text()
    cards = view.cards()
    bits: list[tuple[str, str]] = []
    total = f"{view.tasks_total} tasks"
    if view.hidden_total:
        total += f" ({view.hidden_total} hidden)"
    bits.append((total, icons.PALETTE["overlay2"]))
    working = sum(1 for card in cards if card.status == "working")
    blocked = sum(1 for card in cards if card.status == "blocked")
    if working:
        bits.append((f"● {working} working", icons.PALETTE["yellow"]))
    if blocked:
        bits.append((f"▲ {blocked} needs you", icons.PALETTE["red"]))
    if view.herdr_down:
        bits.append(("herdr unreachable", icons.PALETTE["red"]))
    for index, (text, style) in enumerate(bits):
        if index:
            right.append("  ", style=icons.PALETTE["surface1"])
        right.append(text, style=style)
    return spread(left, right, view.width)


def footer_line(view: BoardView) -> Text:
    left = Text()
    selected = view.card(view.selected_id)
    archived = selected is not None and bool(selected.task.archived_at)
    hints: tuple[tuple[str, str], ...]
    if selected is None:
        hints = (
            ("a", "add"),
            ("/", "filter"),
            ("w", "workspace"),
            ("v", "archive"),
            ("r", "refresh"),
            ("?", "help"),
            ("q", "quit"),
        )
    elif archived:
        # An archived card is out of play: the only move it has is back (`u`),
        # plus stopping a run that was left going and deleting the record.
        hints = (
            ("⏎", "detail"),
            ("u", "unarchive"),
            ("x", "stop agent"),
            ("d", "delete"),
            ("v", "archive"),
            ("?", "help"),
        )
    elif view.width < 116:
        hints = (
            ("⏎", "detail"),
            ("a", "add"),
            ("s", "send"),
            ("!", "needs you"),
            ("e", "edit"),
            ("d", "delete"),
            ("v", "archive"),
            ("?", "help"),
        )
    else:
        hints = (
            ("h/l", "column"),
            ("j/k", "card"),
            ("⏎", "detail"),
            ("a", "add"),
            ("s", "send"),
            ("!", "needs you"),
            ("H/L", "move"),
            ("o", "workspace"),
            ("f", "agent"),
            ("e", "edit"),
            ("d", "delete"),
            ("v", "archive"),
            ("/", "filter"),
            ("?", "help"),
        )
    for index, (key, label) in enumerate(hints):
        if index:
            left.append("  ", style=icons.PALETTE["surface1"])
        left.append(key, style=icons.PALETTE["lavender"])
        left.append(" " + label, style=icons.PALETTE["overlay0"])
    right = Text(short_path(view.board_path, 44), style=icons.PALETTE["surface2"])
    return spread(left, right, view.width)


def render_board(view: BoardView) -> tuple[list[Text], Layout]:
    """Draw the board. Returns exactly `height` lines plus their rectangles."""
    layout = compute_layout(view)
    if view.width < 24 or view.height < 6:
        return [Text("kanban: pane too small")], layout

    lines: list[Text] = [header_line(view)]

    headers = Text()
    for index, column in enumerate(view.columns):
        if index:
            headers.append(" " * COLUMN_GAP)
        headers.append_text(
            render_column_header(
                column,
                layout.column_width,
                index,
                index == view.selected_column,
                view.visible_cards,
            )
        )
    lines.append(headers)

    for row in range(view.visible_cards):
        blank = [Text() for _ in range(CARD_HEIGHT)]
        column_rows: list[list[Text]] = []
        for column in view.columns:
            position = column.scroll + row
            if position < column.count:
                card = column.cards[position]
                column_rows.append(
                    render_card(
                        card,
                        layout.column_width,
                        selected=card.task.id == view.selected_id,
                        mode=view.icon_mode,
                        show_age=view.show_age,
                        stale_after_days=view.stale_after_days,
                        show_agent_kind=view.show_agent_kind,
                        show_status_word=view.show_status_word,
                    )
                )
            elif column.count == 0 and row == 0:
                column_rows.append(_empty_slot(layout.column_width))
            else:
                column_rows.append(blank)
        for line_index in range(CARD_HEIGHT):
            line = Text()
            for index, rows in enumerate(column_rows):
                if index:
                    line.append(" " * COLUMN_GAP)
                chunk = rows[line_index]
                if chunk.cell_len < layout.column_width:
                    chunk = chunk.copy()
                    chunk.append(" " * (layout.column_width - chunk.cell_len))
                line.append_text(chunk)
            lines.append(line)

    if view.tasks_total == 0:
        message = Text()
        message.append(
            "nothing on the board yet", style=f"bold {icons.PALETTE['text']}"
        )
        message.append("   press  ", style=icons.PALETTE["overlay1"])
        message.append("a", style=f"bold {icons.PALETTE['lavender']}")
        message.append("  to add a task for an agent", style=icons.PALETTE["overlay1"])
        row = CARDS_Y + max(0, view.visible_cards // 2)
        while len(lines) <= row:
            lines.append(Text())
        filler = Text(" " * max(0, (view.width - message.cell_len) // 2))
        filler.append_text(message)
        lines[row] = spread(filler, Text(), view.width)

    lines.append(footer_line(view))
    while len(lines) < view.height:
        lines.append(Text())
    # Clip to the pane: a Text wider than the widget wraps, which would push the
    # footer off the bottom and break the one-line-per-row contract.
    for line in lines:
        line.truncate(view.width, overflow="crop")
    return lines[: view.height], layout


def render_plain(view: BoardView) -> str:
    """The board as plain text — used by `--snapshot` and the tests."""
    lines, _ = render_board(view)
    return "\n".join(line.plain for line in lines)
