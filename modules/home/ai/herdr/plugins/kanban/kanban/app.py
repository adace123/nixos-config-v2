"""The board application.

State lives here: the board file (through `Store`), the last herdr snapshot
(`LiveState`), and the cursor/filter (`UiState`). Widgets only draw and forward
input; every mutation goes through a method on this class so the board, the
store, and the toast messages can never drift apart.
"""

from __future__ import annotations

import contextlib
import time

from textual import work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.worker import Worker

from . import dispatch, icons, notify
from .config import Config
from .demo import demo_live, demo_tasks
from .dispatch import (
    CLI,
    Executor,
    Outcome,
    Plan,
    dispatch_fields,
    plan_for,
    record_outcome,
    result_summary,
    retitle_tab,
)
from .herdr import Herdr
from .modals import (
    ConfirmModal,
    DispatchModal,
    FilterModal,
    HelpModal,
    TaskDetailModal,
    TaskDraft,
    TaskFormModal,
)
from .model import (
    LiveState,
    UiState,
    build_view,
    selection_after_move,
)
from .render import BoardView
from .store import Store, Task, task_id, workspace_code
from .sync import Syncer, SyncLock
from .widgets import BoardWidget


class KanbanApp(App[None]):
    """The herdr kanban board."""

    CSS_PATH = "theme.tcss"
    TITLE = "herdr kanban"
    SUB_TITLE = "workspace + agent tasks"

    # Textual spends ctrl+c on a "press q to quit" toast (it keeps the key clear
    # for copy in its text fields). The board is a terminal program, so the
    # reflex key has to exit — and `priority` makes it do so from anywhere,
    # dialogs included, where the focused field would otherwise take the key.
    BINDINGS = [
        Binding("ctrl+c", "quit", "quit", show=False, priority=True),
    ]

    def __init__(
        self,
        config: Config,
        store: Store,
        herdr: Herdr,
        quick_add: bool = False,
        demo: bool = False,
    ) -> None:
        super().__init__()
        self.config = config
        self.store = store
        self.herdr = herdr
        self.quick_add = quick_add
        self.demo_mode = demo
        self.live = LiveState()
        self.ui = UiState()
        self.icon_mode = icons.icon_mode(config.icon_mode)
        self.executor = Executor(herdr)
        self._notice_timer: object | None = None
        # The column rules and block announcements, shared with the background
        # daemon (`sync.py`); the lock decides which of the two runs them.
        self.syncer = Syncer(
            config,
            herdr,
            tasks=self.tasks,
            set_status=self._set_status,
            toast=self.herdr_notify,
        )
        self._sync_lock = SyncLock(store.path)
        self._demo_tasks: list[Task] = []
        self._demo_archived: list[Task] = []

    # -- lifecycle -------------------------------------------------------

    def compose(self) -> ComposeResult:
        yield BoardWidget(id="board")

    def on_mount(self) -> None:
        if self.demo_mode:
            self._demo_tasks = demo_tasks()
            self.live = demo_live()
        else:
            self.store.load()
        self.query_one(BoardWidget).focus()
        self.select_first()
        if not self.demo_mode:
            self.refresh_live()
            self.set_interval(self.config.sync_seconds, self.refresh_live)
        if self.config.load_error:
            self.set_notice(f"config: {self.config.load_error}", timeout=10)
        if self.quick_add:
            self.call_after_refresh(self.action_add_task)

    def on_unmount(self) -> None:
        self.ui.notice = ""

    # -- data ------------------------------------------------------------

    def tasks(self) -> list[Task]:
        return list(self._demo_tasks) if self.demo_mode else list(self.store.tasks)

    def archived_tasks(self) -> list[Task]:
        """Cards taken off the board, whether the `v` column is shown or not."""
        return (
            list(self._demo_archived) if self.demo_mode else list(self.store.archived)
        )

    def task(self, task_id: str) -> Task | None:
        """A card by id — live, or archived when that is where it is."""
        for task in self.tasks():
            if task.id == task_id:
                return task
        return next(
            (task for task in self.archived_tasks() if task.id == task_id), None
        )

    def workspaces(self) -> list:
        return sorted(self.live.workspaces.values(), key=lambda item: item.number)

    def children_of(self, task_id: str) -> list[Task]:
        """Cards filed from `task_id` — the follow-ups one run turned up.

        Scanned from `tasks()` rather than the store so `--demo` and a real board
        answer the same question the same way.
        """
        return [task for task in self.tasks() if task.parent_id == task_id]

    def current_view(self) -> BoardView:
        try:
            widget = self.query_one(BoardWidget)
            width = widget.size.width or 120
            height = widget.size.height or 40
        except Exception:  # pragma: no cover - before the first mount
            width, height = 120, 40
        return build_view(
            self.config,
            self.tasks(),
            self.live,
            self.ui,
            width=max(40, width),
            height=max(6, height),
            board_path=str(self.store.path),
            icon_mode=self.icon_mode,
            archived=self.archived_tasks(),
        )

    def refresh_board(self) -> None:
        with contextlib.suppress(Exception):
            self.query_one(BoardWidget).refresh()

    def set_notice(self, text: str, timeout: float = 5.0) -> None:
        self.ui.notice = text
        if self._notice_timer is not None:
            with contextlib.suppress(Exception):
                self._notice_timer.stop()  # type: ignore[attr-defined]
        if timeout > 0:
            self._notice_timer = self.set_timer(timeout, self.clear_notice)
        self.refresh_board()

    def clear_notice(self) -> None:
        if self.ui.notice:
            self.ui.notice = ""
            self.refresh_board()

    def post(self, callback, *args: object) -> None:
        """Hand work back from a worker thread, tolerating a shutting-down app."""
        try:
            self.call_from_thread(callback, *args)
        except Exception:  # pragma: no cover - shutdown races
            pass

    def workers_running(self) -> list[Worker]:
        """In-flight sync/dispatch/notification workers (used by the selftest)."""
        return [worker for worker in self.workers if not worker.is_finished]

    # -- selection -------------------------------------------------------

    def selected_task(self) -> Task | None:
        return self.task(self.ui.selected_id) if self.ui.selected_id else None

    def _selected_row(self, view: BoardView) -> int:
        if self.ui.selected_column >= len(view.columns):
            return 0
        cards = view.columns[self.ui.selected_column].cards
        for index, card in enumerate(cards):
            if card.task.id == self.ui.selected_id:
                return index
        return 0

    def select_first(self) -> None:
        view = self.current_view()
        for index, column in enumerate(view.columns):
            if column.cards:
                self.ui.selected_column = index
                self.ui.selected_id = column.cards[0].task.id
                break
        self.refresh_board()

    def select_card(self, task_id: str) -> None:
        view = self.current_view()
        for index, column in enumerate(view.columns):
            if any(card.task.id == task_id for card in column.cards):
                self.ui.selected_column = index
                break
        self.ui.selected_id = task_id
        self.refresh_board()

    def select_column(self, index: int) -> None:
        view = self.current_view()
        if not 0 <= index < len(view.columns):
            return
        self.ui.selected_column = index
        cards = view.columns[index].cards
        row = self._selected_row(view)
        self.ui.selected_id = cards[min(row, len(cards) - 1)].task.id if cards else ""
        self.refresh_board()

    def select_edge(self, first: bool) -> None:
        view = self.current_view()
        if self.ui.selected_column >= len(view.columns):
            return
        cards = view.columns[self.ui.selected_column].cards
        if cards:
            self.ui.selected_id = (cards[0] if first else cards[-1]).task.id
            self.refresh_board()

    def move_selection(self, dcolumn: int, dcard: int) -> None:
        view = self.current_view()
        if not view.columns:
            return
        if dcolumn:
            index = max(
                0, min(len(view.columns) - 1, self.ui.selected_column + dcolumn)
            )
            row = self._selected_row(view)
            self.ui.selected_column = index
            cards = view.columns[index].cards
            self.ui.selected_id = (
                cards[min(row, len(cards) - 1)].task.id if cards else ""
            )
        elif dcard:
            cards = view.columns[self.ui.selected_column].cards
            if not cards:
                direction = 1 if dcard > 0 else -1
                target = self._neighbour_column(direction)
                if target is not None:
                    self.ui.selected_column = target
                    cards = view.columns[target].cards
                    self.ui.selected_id = cards[0].task.id
            else:
                row = self._selected_row(view) + dcard
                row = max(0, min(len(cards) - 1, row))
                self.ui.selected_id = cards[row].task.id
        self.refresh_board()

    def _neighbour_column(self, direction: int) -> int | None:
        view = self.current_view()
        index = self.ui.selected_column + direction
        while 0 <= index < len(view.columns):
            if view.columns[index].cards:
                return index
            index += direction
        return None

    # -- card mutations --------------------------------------------------

    def _after_change(self, task_id: str = "") -> None:
        if task_id:
            self.ui.selected_id = task_id
        view = self.current_view()
        self.ui.selected_id = selection_after_move(view, self.ui)
        self.refresh_board()

    def _set_status(self, task: Task, status: str, hold: bool = False) -> None:
        if self.demo_mode:
            task.status = status
            task.blocked_hold = hold
        else:
            self.store.set_status(task.id, status, hold=hold)

    def _refuse_archived(self, task: Task, action: str) -> bool:
        """True when `task` is archived and `action` cannot apply to it.

        An archived card is off the board: moving, editing or sending it would
        write through a store that no longer holds it. `u` is the way back, and
        the notice says so.
        """
        if not task.archived_at:
            return False
        self.set_notice(
            f"{task.id} is archived — press u to restore it before you {action}",
            timeout=4,
        )
        return True

    def _refuse_sorted(self, task: Task) -> bool:
        """True when the board is sorted, so a manual reorder could not show.

        `J`/`K` edit the board file's list order, and a sorted column ignores
        that order — so the reorder would be a write nobody could see: the card
        would stay where it is while the file said otherwise. Refusing, with
        the one config line that hands the keys back, is the honest half of
        that trade; silently accepting it would make the key look broken and
        quietly diverge the file from the board.
        """
        if self.config.sort == "manual":
            return False
        self.set_notice(
            f'{task.id} · columns are sorted by {self.config.sort} — set '
            'sort = "manual" in config.toml to reorder by hand',
            timeout=4,
        )
        return True

    def _update(self, task: Task, **fields: object) -> None:
        if self.demo_mode:
            for key, value in fields.items():
                setattr(task, key, value)
        else:
            self.store.update(task.id, **fields)

    def toggle_step(self, task_id: str, index: int) -> Task | None:
        """Tick or untick step `index` (1-based). Used by the detail view."""
        task = self.task(task_id)
        if task is None or task.archived_at or not 1 <= index <= len(task.steps):
            return None
        done = not bool(task.steps[index - 1].get("done"))
        if self.demo_mode:
            task.steps[index - 1]["done"] = done
            task.steps[index - 1]["by"] = "user" if done else ""
        else:
            self.store.set_step(task_id, index, done=done, by="user")
            task = self.store.by_id(task_id)
        self.refresh_board()
        return task

    def move_card_column(self, delta: int) -> None:
        task = self.selected_task()
        if task is None:
            self.set_notice("select a card first")
            return
        if self._refuse_archived(task, "move it"):
            return
        view = self.current_view()
        index = next(
            (
                position
                for position, column in enumerate(view.columns)
                if column.column.id == task.status
            ),
            self.ui.selected_column,
        )
        target = max(0, min(len(self.config.columns) - 1, index + delta))
        if target == index:
            return
        new_status = self.config.columns[target].id
        origin = self.config.label_for(task.status)
        # Moving a card into Blocked by hand is an explicit park: a working agent
        # must not carry it back out (see `Syncer.settle_columns`).
        self._set_status(
            task, new_status, hold=new_status == self.config.blocked_column
        )
        self.ui.selected_column = target
        # Both ends of the move: the card was on screen a moment ago, but the
        # keys under the finger move it again, and "→ In Progress" alone cannot
        # say where it came from when the board is busy.
        self.set_notice(
            f"{task.id} · {origin} → {self.config.label_for(new_status)}", timeout=2.5
        )
        self.refresh_board()

    def reorder_card(self, delta: int) -> None:
        task = self.selected_task()
        if task is None:
            return
        if self._refuse_archived(task, "reorder it"):
            return
        if self._refuse_sorted(task):
            return
        if self.demo_mode:
            siblings = [t for t in self._demo_tasks if t.status == task.status]
            index = siblings.index(task)
            target = index + delta
            if 0 <= target < len(siblings):
                other = siblings[target]
                a, b = self._demo_tasks.index(task), self._demo_tasks.index(other)
                self._demo_tasks[a], self._demo_tasks[b] = (
                    self._demo_tasks[b],
                    self._demo_tasks[a],
                )
        else:
            self.store.reorder(task.id, delta)
        self.refresh_board()

    def delete_task(self, task: Task, remove_worktree: bool = False) -> None:
        # Stop the agent first: a card is the record of a run, and deleting it
        # while leaving the run going leaves an agent nobody is tracking. A
        # board can opt out (`auto_delete_agent = false`), and then deleting the
        # card leaves its agent and tab alone — the confirmation names it first
        # (`action_delete_task`).
        closed = self.close_agent(task) if self.config.auto_delete_agent else ""
        removed = self.remove_worktree(task) if remove_worktree else ""
        if self.demo_mode:
            if task.archived_at:
                self._demo_archived.remove(task)
            else:
                self._demo_tasks.remove(task)
        else:
            self.store.delete(task.id)
        self.ui.selected_id = ""
        self._after_change()
        self.notify(
            f"{task.id} deleted"
            + (f" · {closed}" if closed else "")
            + (f" · {removed}" if removed else ""),
            title="kanban",
        )

    def archive_task(self, task: Task) -> None:
        """Take a card off the board, keeping its record (`unarchive` restores).

        Archive is about the board, not the run: unlike `delete`, it does not
        stop the card's agent unless `auto_archive_agent` says it should. With
        the flag off, a card whose agent is still going is called out in the
        notice, because its card is now off the board while the work continues;
        with it on, the notice names the tab that was closed instead — or the
        error that left it open, since a card leaving the board must not report
        a stop that did not happen.
        """
        closed = self.close_agent(task) if self.config.auto_archive_agent else ""
        if self.demo_mode:
            task.archived_from = task.status
            task.archived_at = time.time()
            self._demo_tasks.remove(task)
            self._demo_archived.append(task)
        else:
            self.store.archive(task.id)
        # Asked only when nothing was closed: after a successful close the card
        # has no tab left to report, and a close that failed has said so.
        running = self.agent_tab(task)[0] if not closed else ""
        self.ui.selected_id = ""
        self._after_change()
        # A footer notice, not a toast: the one command that undoes this belongs
        # where the board's other "here is what just happened" messages go.
        if closed:
            stopped = f" · {closed}"
        elif running:
            stopped = " · its agent is still running"
        else:
            stopped = ""
        self.set_notice(
            f"{task.id} archived{stopped} — {CLI} unarchive {task.id} to restore"
        )

    def unarchive_task(self, task: Task) -> None:
        """Put an archived card back on the board, in the column it left."""
        if self.demo_mode:
            task.status = task.archived_from or task.status
            task.archived_at = 0.0
            task.archived_from = ""
            self._demo_archived.remove(task)
            self._demo_tasks.append(task)
        else:
            self.store.unarchive(task.id)
        self.ui.selected_id = task.id
        self._after_change()
        self.set_notice(f"{task.id} restored to {self.config.label_for(task.status)}")

    def may_remove_worktree(self, task: Task) -> bool:
        """Whether deleting `task` could remove its checkout.

        A worktree is removed by closing the workspace herdr opened for it, so
        there is nothing to remove without one. And if the card's agent is being
        kept (`auto_delete_agent = false`) while it is still running, the
        checkout is that agent's workspace and has to stay with it.
        """
        if not task.worktree_path or not task.worktree_workspace_id:
            return False
        if not self.config.auto_delete_agent and self.agent_tab(task)[0]:
            return False
        return True

    def remove_worktree(self, task: Task) -> str:
        """Remove `task`'s checkout; return a phrase for the delete notice."""
        if not task.worktree_workspace_id:
            return "worktree kept (its workspace is already gone)"
        if self.demo_mode:
            return f"demo: would remove worktree {task.worktree_path}"
        result = self.herdr.remove_worktree(task.worktree_workspace_id)
        if result.ok:
            return f"worktree removed ({task.worktree_path})"
        # The workspace was closed by hand: herdr's `worktree remove` takes only
        # a workspace id, so the checkout is left for `git worktree remove`.
        return (
            f"worktree kept — {result.error_text()}; remove it with:"
            f" git worktree remove {task.worktree_path}"
        )

    # -- screens ---------------------------------------------------------

    def action_add_task(self) -> None:
        # Seed from the workspace the board was opened from, then the active
        # workspace filter, then the first open workspace — so quick capture
        # (a, type, ⏎) always lands somewhere sensible.
        workspaces = self.workspaces()
        default_workspace = (
            self.herdr.current_workspace()
            or self.ui.workspace_filter
            or (workspaces[0].id if workspaces else "")
        )
        self.push_screen(
            TaskFormModal(
                config=self.config,
                workspaces=workspaces,
                mode=self.icon_mode,
                default_workspace=default_workspace,
                default_workspace_label=(
                    self.live.workspaces[default_workspace].label
                    if default_workspace in self.live.workspaces
                    else ""
                ),
                default_kind=self.config.default_agent,
            ),
            self.on_draft,
        )

    def on_draft(self, draft: TaskDraft | None) -> None:
        if draft is None:
            return
        if self.demo_mode:
            self._demo_tasks.append(
                Task(
                    # Same id rule as the real board, so a demo capture looks
                    # like a real one: the workspace's code, then the counter.
                    id=task_id(
                        workspace_code(
                            self.config.workspace_aliases,
                            draft.workspace_label,
                            draft.workspace_id,
                        ),
                        len(self._demo_tasks) + 1,
                    ),
                    title=draft.title,
                    notes=draft.notes,
                    status=draft.status,
                    workspace_id=draft.workspace_id,
                    workspace_label=draft.workspace_label,
                    agent_kind=draft.agent_kind,
                    agent_model=draft.agent_model,
                    priority=draft.priority,
                    labels=draft.labels,
                    created_at=time.time(),
                    updated_at=time.time(),
                )
            )
            created = self._demo_tasks[-1]
        else:
            created = self.store.add(
                title=draft.title,
                notes=draft.notes,
                status=draft.status,
                workspace_id=draft.workspace_id,
                workspace_label=draft.workspace_label,
                workspace_code=workspace_code(
                    self.config.workspace_aliases,
                    draft.workspace_label,
                    draft.workspace_id,
                ),
                agent_kind=draft.agent_kind,
                agent_model=draft.agent_model,
                priority=draft.priority,
                labels=draft.labels,
            )
        self.ui.selected_id = created.id
        self.ui.filter_text = ""
        self._after_change(created.id)
        # Send now: the form has already been through the workspace and the agent
        # kind, so it is the review step and a second dialog would be asking
        # twice. The dispatch's own notification is the confirmation — which is
        # also what the quick-capture toast is for. When nothing was started (no
        # workspace to run in), fall through to the ordinary capture
        # confirmation: the card exists either way.
        if draft.send_now and self.send_now(created):
            return
        workspace = draft.workspace_label or "no workspace"
        agent = icons.kind_label(draft.agent_kind) if draft.agent_kind else "no agent"
        self.notify(
            f"{created.id} · {created.title}\n{workspace} · {agent}",
            title="kanban",
        )
        # Quick capture opens in a popup that closes the moment it saves, so
        # leave the confirmation somewhere it will still be seen.
        if self.quick_add and not self.demo_mode:
            self.toast(created.id, created.title, workspace, agent)

    def action_edit_task(self) -> None:
        task = self.selected_task()
        if task is None:
            self.set_notice("select a card first")
            return
        if self._refuse_archived(task, "edit it"):
            return
        self.push_screen(
            TaskFormModal(
                config=self.config,
                workspaces=self.workspaces(),
                mode=self.icon_mode,
                task=task,
                default_kind=task.agent_kind or self.config.default_agent,
            ),
            lambda draft, task=task: self.on_edit(draft, task),
        )

    def on_edit(self, draft: TaskDraft | None, task: Task) -> None:
        if draft is None:
            return
        fields: dict[str, object] = {
            "notes": draft.notes,
            "status": draft.status,
            "workspace_id": draft.workspace_id,
            "workspace_label": draft.workspace_label,
            "agent_kind": draft.agent_kind,
            "agent_model": draft.agent_model,
            "priority": draft.priority,
            "labels": draft.labels,
        }
        # The title joins the update only when the human changed it in this form.
        # Sending it every time writes back the title the form was opened with,
        # which silently reverts an agent's rename that landed while the dialog
        # was up — the card then shows a name the agent never chose, and `✎`
        # stays because nothing claimed it. `task` is the card as the form saw
        # it, so the comparison is exactly "did you type a different title?".
        # Renaming by hand claims the title: from here on an agent's title is
        # recorded as an update instead of replacing yours.
        if draft.title.strip() != task.title:
            fields["title"] = draft.title
            fields.update(
                title_source="user",
                title_edited=True,
                original_title=task.original_title or task.title,
            )
        # The key is what says the human changed the title — not its truthiness:
        # an emptied title is still a rename, and the tab has to follow it.
        renamed = "title" in fields
        self._update(task, **fields)
        if renamed and not self.demo_mode:
            # The tab's label is the card's title too, and the board tells its
            # own tab from a repurposed one by that label: renaming the card
            # without renaming the tab would make the board disown the tab it
            # opened (see `agent_tab`).
            fresh = self.task(task.id) or task
            problem = retitle_tab(self.store, fresh, self.herdr)
            if problem:
                self.set_notice(f"could not rename {task.id}'s tab: {problem}", timeout=6)
        self._after_change(task.id)
        self.notify(f"{task.id} updated", title="kanban")

    def action_detail(self) -> None:
        task = self.selected_task()
        if task is None:
            self.set_notice("select a card first")
            return
        status, online = self.live.for_task(task)
        agent = self.live.lookup(task)
        self.push_screen(
            TaskDetailModal(
                interval=self.config.sync_seconds,
                task=task,
                config=self.config,
                herdr=self.herdr,
                live_status=status,
                agent_online=online,
                workspace_label=self.live.workspace_label(task),
                workspace_ok=self.live.workspace_ok(task),
                icon_mode=self.icon_mode,
                agent_title=agent.title if agent else "",
            ),
            lambda action, task=task: self.on_detail_action(action, task),
        )

    def on_detail_action(self, action: str | None, task: Task) -> None:
        if action == "dispatch":
            self.dispatch_task(task)
        elif action == "edit":
            self.ui.selected_id = task.id
            self.action_edit_task()
        elif action == "focus_agent":
            self.ui.selected_id = task.id
            self.action_focus_agent()
        elif action == "focus_workspace":
            self.ui.selected_id = task.id
            self.action_focus_workspace()
        elif action == "delete":
            self.action_delete_task()
        elif action == "archive":
            self.ui.selected_id = task.id
            self.action_archive_task()
        elif action == "close_agent":
            self.ui.selected_id = task.id
            self.action_close_agent()
        if not self.demo_mode and self.store.reload():
            # The detail view can tick steps, so the board behind it may be
            # showing a step counter that just changed.
            self.refresh_board()

    def action_delete_task(self) -> None:
        task = self.selected_task()
        if task is None:
            self.set_notice("select a card first")
            return
        tab_id, described = self.agent_tab(task)
        if not tab_id:
            closing = "It has no agent running."
        elif self.config.auto_delete_agent:
            closing = f"Its agent ({described}) is stopped and its tab closed with it."
        else:
            closing = (
                f"Its agent ({described}) is left running and its tab stays open "
                "— `auto_delete_agent` is off."
            )
        if task.worktree_path:
            if self.may_remove_worktree(task):
                closing += (
                    f"\n\nIts worktree {task.worktree_path} is offered for removal next."
                )
            else:
                closing += f"\n\nIts worktree {task.worktree_path} is kept."
        self.push_screen(
            ConfirmModal(
                "Delete task",
                f"Delete {task.id} — {task.title}?\n\n{closing}",
                confirm_label="Delete",
                danger=True,
            ),
            lambda confirmed, task=task: self._after_delete_confirm(confirmed, task),
        )

    def action_archive_task(self) -> None:
        task = self.selected_task()
        if task is None:
            self.set_notice("select a card first")
            return
        if task.archived_at:
            self.set_notice(f"{task.id} is already archived — press u to restore it")
            return
        # No confirmation: unlike `d`, archiving keeps the card and the notice
        # names the one command that brings it back.
        self.archive_task(task)

    def action_unarchive_task(self) -> None:
        task = self.selected_task()
        if task is None:
            self.set_notice("select a card first")
            return
        if not task.archived_at:
            self.set_notice(f"{task.id} is not archived")
            return
        self.unarchive_task(task)

    def action_toggle_archived(self) -> None:
        """Show or hide the Archived column (`v`)."""
        self.ui.show_archived = not self.ui.show_archived
        self._after_change()
        self.set_notice(
            "archived column shown — u restores a card"
            if self.ui.show_archived
            else "archived column hidden",
            timeout=3,
        )

    def _after_delete_confirm(self, confirmed: bool | None, task: Task) -> None:
        """The first confirm said delete; a checkout, if any, is asked about next.

        Worktree removal is a second question rather than a config switch
        because it is a real loss (the checkout may hold uncommitted work) and
        the card is the only thing that remembers where it is — after the card
        is gone, nothing in herdr points at it any more.
        """
        if not confirmed:
            return
        if not self.may_remove_worktree(task):
            self.delete_task(task, remove_worktree=False)
            return
        branch = f"\n\nbranch {task.worktree_branch}" if task.worktree_branch else ""
        self.push_screen(
            ConfirmModal(
                "Remove worktree",
                f"Also remove the worktree for {task.id}?\n\n"
                f"{task.worktree_path}{branch}",
                confirm_label="Remove",
                danger=True,
            ),
            lambda remove, task=task: self.delete_task(
                task, remove_worktree=bool(remove)
            ),
        )

    def agent_tab(self, task: Task) -> tuple[str, str]:
        """(tab to close, how to describe it) for a card's dispatched agent.

        Only a tab whose label is still the one the board last wrote is
        considered ours: the same pane may have been closed and reused for
        something else, and deleting a card should not take that with it. The
        label the board writes changes with the card's title (`retitle_tab`), so
        this is matched against what was written, never against a label guessed
        from the current title.
        """
        if not task.tab_id:
            return "", ""
        agent = self.live.lookup(task)
        tab_id = (agent.tab_id if agent is not None else "") or task.tab_id
        described = (
            (agent.title or agent.pane_id) if agent is not None else task.pane_id
        )
        if self.demo_mode:
            return tab_id, described or tab_id
        # The label the board last wrote, not one recomputed from the current
        # title: an agent that names the card renames the tab with it, and a
        # board that expected `tab_label_for(task)` here would read its own tab
        # as somebody else's the moment the card was renamed. Cards dispatched
        # before the label was recorded fall back to that computation.
        if self.herdr.tab_label(tab_id) != (
            task.tab_label or dispatch.tab_label_for(task)
        ):
            return "", ""
        return tab_id, described or tab_id
        return tab_id, described or tab_id

    def close_agent(self, task: Task) -> str:
        """Stop a card's agent by closing the tab its dispatch opened."""
        tab_id, described = self.agent_tab(task)
        if not tab_id:
            self._update(task, pane_id="", tab_id="", tab_label="", agent_name="")
            return ""
        result = self.herdr.close_tab(tab_id)
        if not result.ok:
            return f"could not close {tab_id}: {result.error_text()}"
        self._update(task, pane_id="", tab_id="", tab_label="", agent_name="")
        return f"closed {tab_id}"

    def action_close_agent(self) -> None:
        """Stop the agent without deleting the card."""
        task = self.selected_task()
        if task is None:
            self.set_notice("select a card first")
            return
        tab_id, described = self.agent_tab(task)
        if not tab_id:
            self.set_notice(f"{task.id} has no agent running")
            return
        self.push_screen(
            ConfirmModal(
                "Stop agent",
                f"Stop the agent for {task.id} ({described})?\n\n"
                "The card stays on the board; its tab and agent are closed.",
                confirm_label="Stop",
                danger=True,
            ),
            lambda confirmed, task=task: self.stop_agent(task) if confirmed else None,
        )

    def stop_agent(self, task: Task) -> None:
        message = self.close_agent(task)
        self.notify(
            f"{task.id}: {message or 'no agent to stop'}",
            title="kanban",
            severity="information" if message else "warning",
        )
        self._after_change(task.id)

    # -- dispatch --------------------------------------------------------

    def action_dispatch(self) -> None:
        task = self.selected_task()
        if task is None:
            self.set_notice("select a card first")
            return
        self.dispatch_task(task)

    def dispatch_task(self, task: Task) -> None:
        if self._refuse_archived(task, "send it"):
            return
        plan = self.plan_for_task(task)
        if not plan.workspace_id and not plan.reuses_running_agent:
            self.set_notice(f"{task.id} has no workspace — edit it first", timeout=6)
            return
        self.push_screen(
            DispatchModal(
                plan,
                self.config,
                self.workspaces(),
                self.icon_mode,
                wip_warning=self.wip_warning(task),
            ),
            lambda confirmed, task=task: self.on_plan(confirmed, task),
        )

    def wip_warning(self, task: Task) -> str:
        """A note when dispatching would push a column past its wip_limits.

        Silence when the card is already counted in that column: re-prompting a
        running agent does not add work in progress.
        """
        column_id = self._dispatch_column(task.status)
        limit = self.config.wip_limit(column_id)
        if not limit or task.status == column_id:
            return ""
        tasks = self._demo_tasks if self.demo_mode else self.store.tasks
        count = sum(1 for other in tasks if other.status == column_id)
        if count < limit:
            return ""
        return (
            f"⚠ {self.config.label_for(column_id)} is at its limit "
            f"({count}/{limit}) — this card makes it {count + 1}"
        )

    def plan_for_task(self, task: Task) -> Plan:
        """What sending `task` would do, with the board's own defaults filled in."""
        return plan_for(
            task,
            self.config,
            self.live,
            fallback_workspace=self.herdr.current_workspace(),
            fallback_kind=self.config.default_agent,
        )

    def send_now(self, task: Task) -> bool:
        """Start `task`'s agent straight away, without the dispatch form.

        The add form's shortcut: the card was just written down and the form has
        already been through its workspace and agent, so making the user confirm
        the same two fields again is a dialog for the sake of a dialog. Returns
        False when nothing was started, so the caller can still confirm that the
        card itself was saved.
        """
        plan = self.plan_for_task(task)
        if not plan.workspace_id and not plan.reuses_running_agent:
            self.set_notice(
                f"{task.id} saved, but it has no workspace to run in", timeout=6
            )
            return False
        warning = self.wip_warning(task)
        if warning:
            self.notify(warning, title="kanban", severity="warning")
        if self.demo_mode:
            self.set_notice(
                f"demo: would send {plan.task_id} to {plan.name} ({plan.kind})"
            )
            return True
        self.set_notice(f"sending {plan.task_id} to {plan.name}…", timeout=0)
        self.run_dispatch(plan, task.id)
        return True

    def on_plan(self, plan: Plan | None, task: Task) -> None:
        if plan is None:
            return
        if self.demo_mode:
            self.set_notice(
                f"demo: would send {plan.task_id} to {plan.name} ({plan.kind})"
            )
            return
        self.set_notice(f"sending {plan.task_id} to {plan.name}…", timeout=0)
        self.run_dispatch(plan, task.id)

    @work(thread=True, exclusive=True, group="dispatch")
    def run_dispatch(self, plan: Plan, task_id: str) -> None:
        outcome = self.executor.run(
            plan,
            on_step=lambda step: self.post(
                self.set_notice,
                f"{plan.task_id} · {step.label}: {step.detail}"[:120],
                0,
            ),
        )
        self.post(self.after_dispatch, task_id, plan, outcome)

    def after_dispatch(self, task_id: str, plan: Plan, outcome: Outcome) -> None:
        task = self.task(task_id)
        # An archived card is off the board: a dispatch that was in flight when it
        # was archived has nothing left to write onto.
        if task is None or task.archived_at:
            return
        target = self._dispatch_column(task.status)
        if self.demo_mode:
            # Demo cards live in memory, so the shared store path does not apply:
            # same fields, written straight onto the throwaway task.
            self._hand_over(task, target, **dispatch_fields(plan, outcome))
        else:
            record_outcome(self.store, task.id, plan, outcome, target)

        if outcome.ok:
            where = plan.workspace_label or plan.workspace_id
            if outcome.worktree_path:
                where = f"worktree {outcome.worktree_path}"
            self.notify(
                f"{task_id} sent to {outcome.agent_name or plan.name} in {where}",
                title="kanban dispatch",
            )
            self.set_notice(f"{task_id} {result_summary(outcome)}", timeout=6)
            if target:
                self.ui.selected_column = self.config.column_ids.index(target)
        else:
            self.notify(
                f"{task_id} dispatch failed — {outcome.error or 'see the board'}",
                title="kanban dispatch",
                severity="error",
                timeout=10,
            )
            self.set_notice(f"{task_id} failed: {outcome.detail()}"[:140], timeout=10)
        self.ui.selected_id = task_id
        self._after_change(task_id)
        self.refresh_live()

    def _hand_over(self, task: Task, status: str, **fields: object) -> None:
        if self.demo_mode:
            for key, value in fields.items():
                setattr(task, key, value)
            task.status = status
        else:
            self.store.hand_over(task.id, status, **fields)

    def _dispatch_column(self, current: str) -> str:
        """The column a send lands in — the rule itself lives with the columns
        (`Config.send_column`), since which columns exist and what they mean is
        config knowledge, not board behaviour."""
        return self.config.send_column(current)

    # -- herdr focus -----------------------------------------------------

    def _focus(self, call, description: str) -> None:
        if self.demo_mode:
            self.set_notice(f"demo: would focus {description}")
            return
        result = call()
        if result.ok:
            self.set_notice(f"focused {description}", timeout=3)
        else:
            self.notify(
                f"could not focus {description}: {result.error_text()}",
                severity="warning",
                title="herdr",
            )

    def action_focus_agent(self) -> None:
        task = self.selected_task()
        if task is None:
            return
        agent = self.live.lookup(task)
        if agent is None:
            self.set_notice(f"{task.id} has no running agent yet — press s to send it")
            return
        label = agent.title or agent.pane_id
        self._focus(lambda: self.herdr.focus_agent(agent.pane_id or agent.name), label)

    def action_focus_workspace(self) -> None:
        task = self.selected_task()
        if task is None:
            return
        # A card dispatched into a worktree is focused at its checkout: that is
        # the workspace its run is in, and the one you would open a terminal in
        # to see the work. `task.workspace_id` is only the repo it was forked
        # from, which stays the fallback when the checkout's workspace is gone.
        target = task.workspace_id
        if task.worktree_workspace_id and task.worktree_workspace_id in self.live.workspaces:
            target = task.worktree_workspace_id
        if not target:
            self.set_notice(f"{task.id} has no workspace")
            return
        label = (
            self.live.workspaces[target].label
            if target in self.live.workspaces
            else target
        )
        self._focus(lambda: self.herdr.focus_workspace(target), label)

    def action_focus_pane(self) -> None:
        task = self.selected_task()
        if task is None:
            return
        if not task.pane_id:
            self.set_notice(f"{task.id} has no pane yet")
            return
        self._focus(lambda: self.herdr.focus_pane(task.pane_id), task.pane_id)

    # -- filters and misc ------------------------------------------------

    def action_filter(self) -> None:
        self.push_screen(FilterModal(self.ui.filter_text), self.on_filter)

    def on_filter(self, text: str | None) -> None:
        if text is None:
            return
        self.ui.filter_text = text
        self._after_change()

    def action_clear_filters(self) -> None:
        self.ui.filter_text = ""
        self.ui.workspace_filter = ""
        self.ui.only_blocked = False
        self.set_notice("filters cleared", timeout=2)
        self._after_change()

    def action_only_blocked(self) -> None:
        """Show only the cards whose agents are waiting on an answer.

        The header has always counted them; this is the key that gets you to
        them, from any workspace, in one keystroke.
        """
        self.ui.only_blocked = not self.ui.only_blocked
        if self.ui.only_blocked:
            view = self.current_view()
            self.ui.selected_id = selection_after_move(view, self.ui)
            count = sum(1 for card in view.cards())
            self.set_notice(
                f"needs you: {count} card{'s' if count != 1 else ''}", timeout=3
            )
        else:
            self.set_notice("showing every card", timeout=2)
        self._after_change()

    def action_cycle_workspace(self) -> None:
        options = [""] + [workspace.id for workspace in self.workspaces()]
        current = self.ui.workspace_filter
        index = options.index(current) + 1 if current in options else 1
        self.ui.workspace_filter = options[index] if index < len(options) else ""
        label = self.ui.workspace_filter or "all workspaces"
        self.set_notice(f"workspace filter: {label}", timeout=3)
        self._after_change()

    @work(thread=True, exclusive=True, group="notify")
    def herdr_notify(self, title: str, body: str = "") -> None:
        """A toast in the running herdr session."""
        self.herdr.notify(title, body)

    def toast(self, task_id: str, title: str, workspace: str, agent: str) -> None:
        self.herdr_notify(f"{task_id} captured · {workspace}", f"{title}  ({agent})")

    def action_help(self) -> None:
        self.push_screen(
            HelpModal(
                config=self.config,
                board_path=str(self.store.path),
                icon_mode=self.icon_mode,
            )
        )

    def action_quit(self) -> None:
        self.exit()

    # -- live sync -------------------------------------------------------

    @work(thread=True, exclusive=True, group="sync")
    def refresh_live(self, force: bool = False) -> None:
        if self.demo_mode:
            return
        self.post(self.apply_live, self.read_live(force))

    def read_live(self, force: bool = False) -> LiveState:
        """Read herdr (`Syncer.read_live`). Blocking: the sync worker calls
        this, and so can a test."""
        return self.syncer.read_live(force)

    def apply_live(self, live: LiveState) -> None:
        self.live = live
        if not self.demo_mode and self.store.reload():
            self.ui.selected_id = selection_after_move(self.current_view(), self.ui)
        if live.down:
            self.set_notice(
                f"herdr unreachable: {live.error}"[:120],
                timeout=self.config.workspace_sync_seconds,
            )
        self.reconcile(live)
        self.refresh_board()

    def reconcile(self, live: LiveState) -> None:
        """Settle columns and announce blocks — unless the sync daemon does.

        The daemon (`herdr-kanban --sync`) holds the sync lock for as long as it
        runs, so while it is up the board only draws what it wrote: two
        reconcilers would announce every block twice. Without it the board takes
        the lock for this one tick and does the work itself, which is how the
        board behaved before the daemon existed. A tick the board sits out
        forgets what it last saw, so taking over later starts from a baseline
        rather than announcing blocks the daemon already announced.
        """
        if self.demo_mode:
            # Sample data: follow the columns, but nothing is news.
            self.syncer.live = live
            self.syncer.settle_columns()
            if self.config.auto_move:
                self.syncer.auto_move()
            return
        if not self._sync_lock.acquire():
            self.syncer.last_status = {}
            return
        try:
            self.syncer.reconcile(live)
        finally:
            self._sync_lock.release()

    @property
    def _live_status(self) -> dict[str, str]:
        return self.syncer.last_status

    @_live_status.setter
    def _live_status(self, value: dict[str, str]) -> None:
        self.syncer.last_status = value


def run() -> None:  # pragma: no cover - convenience for `python -m kanban.app`
    from .config import load_config
    from .herdr import Herdr as HerdrClient
    from .store import board_path

    KanbanApp(load_config(), Store(board_path()), HerdrClient()).run()


__all__ = ["KanbanApp"]
