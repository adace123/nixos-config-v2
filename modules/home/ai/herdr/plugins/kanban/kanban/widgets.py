"""The board widget: one focusable canvas that draws itself and hit-tests itself.

Bindings live here (the widget holds focus) and every one of them delegates to a
`KanbanApp` method, so the app stays the single owner of state.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, cast

from rich.text import Text
from textual import events
from textual.binding import Binding
from textual.widget import Widget

from .render import Layout, render_board

if TYPE_CHECKING:  # pragma: no cover - typing only
    from .app import KanbanApp


class BoardWidget(Widget):
    """The kanban canvas: draws the whole board, maps clicks back to cards."""

    can_focus = True
    BINDINGS = [
        Binding("h,left", "prev_column", "column", show=False),
        Binding("l,right", "next_column", "column", show=False),
        Binding("j,down", "next_card", "card", show=False),
        Binding("k,up", "prev_card", "card", show=False),
        Binding("g", "first_card", "first", show=False),
        Binding("G", "last_card", "last", show=False),
        Binding("H", "move_column(-1)", "move left", show=False),
        Binding("L", "move_column(1)", "move right", show=False),
        Binding("J", "reorder_card(1)", "move down", show=False),
        Binding("K", "reorder_card(-1)", "move up", show=False),
        Binding("tab", "next_column", "next column", show=False),
        Binding("shift+tab", "prev_column", "previous column", show=False),
        Binding("enter", "detail", "detail", show=False),
        Binding("a", "add_task", "add", show=False),
        Binding("e", "edit_task", "edit", show=False),
        Binding("d", "delete_task", "delete", show=False),
        Binding("A", "archive_task", "archive", show=False),
        Binding("s", "dispatch", "send", show=False),
        Binding("f", "focus_agent", "agent", show=False),
        Binding("o", "focus_workspace", "workspace", show=False),
        Binding("p", "focus_pane", "pane", show=False),
        Binding("x", "close_agent", "stop agent", show=False),
        Binding("slash", "filter", "filter", show=False),
        Binding("w", "cycle_workspace", "workspace filter", show=False),
        Binding("c", "clear_filters", "clear filters", show=False),
        Binding("exclamation_mark", "only_blocked", "needs you", show=False),
        Binding("r", "refresh_live", "refresh", show=False),
        Binding("question_mark", "help", "help", show=False),
        Binding("q,escape", "quit", "quit", show=False),
    ]

    def __init__(self, id: str | None = None) -> None:
        super().__init__(id=id)
        self.layout_box: Layout | None = None

    @property
    def kanban(self) -> KanbanApp:
        return cast("KanbanApp", self.app)

    # -- drawing ---------------------------------------------------------

    def render(self) -> Text:
        lines, layout = render_board(self.kanban.current_view())
        self.layout_box = layout
        text = Text()
        for index, line in enumerate(lines):
            if index:
                text.append("\n")
            text.append_text(line)
        return text

    # -- mouse -----------------------------------------------------------

    def on_click(self, event: events.Click) -> None:
        layout = self.layout_box
        if layout is None:
            return
        event.stop()
        task_id = layout.card_at(event.x, event.y)
        if task_id:
            self.kanban.select_card(task_id)
            if event.chain >= 2:
                self.kanban.action_detail()
            return
        column = layout.column_at(event.x, event.y)
        if column is not None:
            self.kanban.select_column(column)

    def on_key(self, event: events.Key) -> None:
        """`1`-`9` jump straight to a column (bindings cannot see the digit)."""
        if len(event.key) == 1 and event.key.isdigit() and event.key != "0":
            self.kanban.select_column(int(event.key) - 1)
            event.stop()

    def on_mouse_scroll_down(self, event: events.MouseScrollDown) -> None:
        self._wheel(event, 1)

    def on_mouse_scroll_up(self, event: events.MouseScrollUp) -> None:
        self._wheel(event, -1)

    def _wheel(
        self, event: events.MouseScrollDown | events.MouseScrollUp, delta: int
    ) -> None:
        layout = self.layout_box
        if layout is None:
            return
        event.stop()
        column = layout.column_at(event.x, event.y)
        if column is not None:
            self.kanban.select_column(column)
        self.kanban.move_selection(0, delta)

    # -- key actions -----------------------------------------------------

    def action_prev_column(self) -> None:
        self.kanban.move_selection(-1, 0)

    def action_next_column(self) -> None:
        self.kanban.move_selection(1, 0)

    def action_prev_card(self) -> None:
        self.kanban.move_selection(0, -1)

    def action_next_card(self) -> None:
        self.kanban.move_selection(0, 1)

    def action_first_card(self) -> None:
        self.kanban.select_edge(first=True)

    def action_last_card(self) -> None:
        self.kanban.select_edge(first=False)

    def action_move_column(self, delta: int) -> None:
        self.kanban.move_card_column(int(delta))

    def action_reorder_card(self, delta: int) -> None:
        self.kanban.reorder_card(int(delta))

    def action_detail(self) -> None:
        self.kanban.action_detail()

    def action_add_task(self) -> None:
        self.kanban.action_add_task()

    def action_edit_task(self) -> None:
        self.kanban.action_edit_task()

    def action_delete_task(self) -> None:
        self.kanban.action_delete_task()

    def action_archive_task(self) -> None:
        self.kanban.action_archive_task()

    def action_dispatch(self) -> None:
        self.kanban.action_dispatch()

    def action_focus_agent(self) -> None:
        self.kanban.action_focus_agent()

    def action_focus_workspace(self) -> None:
        self.kanban.action_focus_workspace()

    def action_focus_pane(self) -> None:
        self.kanban.action_focus_pane()

    def action_close_agent(self) -> None:
        self.kanban.action_close_agent()

    def action_filter(self) -> None:
        self.kanban.action_filter()

    def action_cycle_workspace(self) -> None:
        self.kanban.action_cycle_workspace()

    def action_clear_filters(self) -> None:
        self.kanban.action_clear_filters()

    def action_refresh_live(self) -> None:
        self.kanban.refresh_live()

    def action_help(self) -> None:
        self.kanban.action_help()

    def action_quit(self) -> None:
        self.kanban.action_quit()
