"""Keeping the board honest about its agents, with or without the board open.

The reconciliation that follows a card's agent — a working agent carries its
card into In Progress, an agent that asked you something puts its card in
Blocked and says so — used to run only on the board's own tick, and the board
is an overlay you open and close. So the one state that costs something to
ignore was only noticed while you were already looking. `Syncer` is that
reconciliation on its own, and `run_daemon` runs it in the background process
the plugin's `[[startup]]` hook starts (`herdr-kanban --sync --detach`).

Exactly one process reconciles at a time: whoever holds the sync lock beside
the board file (`SyncLock`). The daemon holds it for as long as it runs; an open
board takes it for one tick at a time, so with the daemon up the board only
draws, and with it down the board reconciles as it always did. That is also what
keeps two reconcilers from announcing the same block twice.
"""

from __future__ import annotations

import contextlib
import fcntl
import os
import signal
import sys
import time
from collections.abc import Callable
from pathlib import Path

from . import notify
from .config import Config
from .herdr import Herdr
from .model import LiveState
from .store import Store, Task

# How long herdr may be unreachable before the daemon gives up. herdr stopping
# is the usual reason, and the next server start runs the startup hook again,
# so exiting is the way to come back with a fresh process rather than poll a
# socket nobody is going to answer.
DOWN_GRACE_SECONDS = 60.0


def lock_path(board: Path) -> Path:
    return board.with_name(f".{board.name}.sync.lock")


def pid_path(board: Path) -> Path:
    return board.with_name(f".{board.name}.sync.pid")


def log_path(board: Path) -> Path:
    return board.with_name("sync.log")


class SyncLock:
    """The right to reconcile the board, held by one process at a time.

    An `flock`, so a daemon that dies — killed, crashed, the machine slept and
    woke without it — releases it with its file descriptor: there is no stale
    pid file to judge.
    """

    def __init__(self, board: Path) -> None:
        self.path = lock_path(board)
        self._fd: int | None = None

    @property
    def held(self) -> bool:
        return self._fd is not None

    def acquire(self) -> bool:
        """Take the lock without waiting. True when this process now holds it."""
        if self._fd is not None:
            return True
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(self.path, os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            return False
        self._fd = fd
        return True

    def release(self) -> None:
        if self._fd is None:
            return
        with contextlib.suppress(OSError):
            fcntl.flock(self._fd, fcntl.LOCK_UN)
        os.close(self._fd)
        self._fd = None


def daemon_pid(board: Path) -> int:
    """The running daemon's pid, or 0 when none holds the lock."""
    probe = SyncLock(board)
    if probe.acquire():
        probe.release()
        return 0
    try:
        return int(pid_path(board).read_text().strip() or 0)
    except (OSError, ValueError):
        return -1  # held, but by a process that has not written its pid yet


class Syncer:
    """Read herdr, then settle each card's column and announce new blocks.

    Everything it touches it is handed, so the same rules run against the store
    in the daemon and against the board's own view in the app (whose demo mode
    edits cards in memory rather than on disk).
    """

    def __init__(
        self,
        config: Config,
        herdr: Herdr,
        tasks: Callable[[], list[Task]],
        set_status: Callable[[Task, str, bool], None],
        toast: Callable[[str, str], None] | None = None,
    ) -> None:
        self.config = config
        self.herdr = herdr
        self.tasks = tasks
        self.set_status = set_status
        self.toast = toast or (lambda title, body: herdr.notify(title, body))
        self.live = LiveState()
        # The last read of each half of herdr's world, so the slow half can be
        # re-read on its own clock (`workspace_sync_seconds`) and the fast half
        # (`sync_seconds`) never waits for it.
        self._workspaces: dict = {}
        self._workspaces_ok = False
        self._workspaces_error = ""
        self._workspaces_read_at = 0.0
        # task id -> the live status it had last reconcile, for the transition
        # announcements in `announce_transitions`.
        self.last_status: dict[str, str] = {}

    def read_live(self, force: bool = False) -> LiveState:
        """Read herdr, on two clocks, and return it as a `LiveState`.

        Two clocks because they are two different costs: agent state is what
        changes and what the board is for, while workspaces are opened and
        closed by hand a few times an hour. Reading both every tick meant a
        `herdr workspace list` nobody needed on every tick — which is exactly
        what `workspace_sync_seconds` was documented to prevent. Blocking.
        """
        now = time.monotonic()
        due = now - self._workspaces_read_at >= self.config.workspace_sync_seconds
        if force or due or not self._workspaces_ok:
            workspaces, workspace_result = self.herdr.workspaces()
            self._workspaces = {workspace.id: workspace for workspace in workspaces}
            self._workspaces_ok = workspace_result.ok
            self._workspaces_error = (
                "" if workspace_result.ok else workspace_result.error_text()
            )
            self._workspaces_read_at = now
        agents, agent_result = self.herdr.agents()
        return LiveState(
            workspaces=self._workspaces,
            agents={agent.name: agent for agent in agents},
            agents_by_pane={agent.pane_id: agent for agent in agents},
            down=not (self._workspaces_ok or agent_result.ok),
            error=self._workspaces_error,
        )

    def reconcile(self, live: LiveState) -> None:
        """One tick of the rules, against `live`."""
        self.live = live
        self.announce_transitions()
        self.settle_columns()
        if self.config.auto_move:
            self.auto_move()

    def _task(self, task_id: str) -> Task | None:
        return next((task for task in self.tasks() if task.id == task_id), None)

    def announce_transitions(self) -> None:
        """Say so when an agent newly starts waiting on you.

        Blocked is the one state that costs something to ignore — the agent is
        stopped until you answer. So the first time a card arrives in it, a
        herdr notification is raised and — unless `notify_system` is off — a
        desktop one.

        Only *transitions*: the first tick just records where everything
        stands, or starting a reconciler onto a blocked card would ping every
        single time, having learned nothing new.
        """
        if not self.config.notify_on_block:
            return
        current = {task.id: self.live.for_task(task)[0] for task in self.tasks()}
        if self.last_status:
            for task_id, status in current.items():
                if status != "blocked" or self.last_status.get(task_id) == "blocked":
                    continue
                task = self._task(task_id)
                if task is not None:
                    self.toast(f"{task.id} needs you", task.title)
                    if self.config.notify_system:
                        # The toast only reaches someone already looking at
                        # herdr; the desktop banner reaches them anywhere.
                        notify.system(f"{task.id} needs you", task.title)
        self.last_status = current

    def holding_block(self, task: Task, status: str) -> bool:
        """Whether an explicit park outranks the agent's live status.

        A card parked in Blocked by hand — `herdr-kanban block`, or the human
        moving it — stays there for the rest of the working phase it was parked
        in. `settle_columns` and `auto_move` both ask this, so the two doors the
        live agent has into a card's column cannot disagree about which card it
        may carry.
        """
        return bool(
            task.blocked_hold
            and status == "working"
            and task.status == self.config.blocked_column
        )

    def settle_columns(self) -> None:
        """Keep each card's column honest about what its agent is doing.

        These two rules are unconditional, unlike `auto_move`, which is the
        opt-in tail of the lifecycle (idle/done -> Review). Each is a card
        saying the opposite of what is true:

          - a card whose agent has stopped to ask you something belongs in
            Blocked, wherever it was — that is what "the agent asked a
            question" looks like from outside;
          - a card whose agent is working belongs in In Progress, so a card
            parked in a queued column is carried on rather than left with a
            label that says the opposite. A card in Blocked is carried on too,
            once its agent starts working again — *unless* it was parked there
            by an explicit act while the agent was still working: `herdr-kanban
            block`, or the human moving it. That is `blocked_hold`, and it wins
            for the rest of that working phase. It is spent the moment the agent
            leaves working (its turn ended, or the block was answered), so a
            later turn lifts the card the way any answered block does.

        A card the human has closed (the `role = "done"` column) is never
        reopened by a live agent, and a board with no Blocked column leaves a
        blocked card where it is — the same bargain `herdr-kanban block` makes.
        """
        doing = self.config.send_column("")
        blocked_column = self.config.blocked_column
        human_only = set(self.config.human_only_columns)
        queued = set(self.config.columns_with_role("queued"))
        for task in self.tasks():
            status, _ = self.live.for_task(task)
            # An explicit park outranks the agent only while the agent is still
            # in the phase it was parked in. Computed before anything below can
            # release the hold, so a same-tick release cannot enable the lift it
            # exists to prevent.
            holding = self.holding_block(task, status)
            if task.blocked_hold and not holding:
                # The hold is spent — release it, quietly (the card is not
                # moving). A card answered out of Blocked follows its agent
                # again on the next tick.
                self.set_status(task, task.status, False)
            if status == "blocked":
                if (
                    blocked_column
                    and task.status != blocked_column
                    and task.status not in human_only
                ):
                    self.set_status(task, blocked_column, False)
                continue
            if status == "working" and doing:
                if task.status in queued:
                    self.set_status(task, doing, False)
                elif task.status == blocked_column and not holding:
                    self.set_status(task, doing, False)

    def auto_move(self) -> None:
        """Opt-in: follow the agent's own progress through the columns.

        The second half of the lifecycle, after `settle_columns`: a card the
        agent has picked up shows as In Progress, and one it has finished shows
        as Review. An explicit park still wins — `auto_move` must not be a
        second door back out of Blocked, or turning it on would undo
        `herdr-kanban block` exactly as the unconditional reconciliation once
        did.
        """
        # "" rather than the card's column: this is not a send, so it always
        # means In Progress — a running agent is never queued in Todo.
        doing = self.config.send_column("")
        review_column = self.config.review_column
        for task in self.tasks():
            if not task.dispatched_at:
                continue
            status, _ = self.live.for_task(task)
            if status == "working" and doing and task.status != doing:
                if self.holding_block(task, status):
                    continue
                self.set_status(task, doing, False)
            elif status in ("idle", "done") and review_column and task.status == doing:
                self.set_status(task, review_column, False)


def store_syncer(config: Config, store: Store, herdr: Herdr) -> Syncer:
    """A `Syncer` that reads and writes the board file directly."""
    return Syncer(
        config,
        herdr,
        tasks=lambda: store.tasks,
        set_status=lambda task, status, hold: store.set_status(
            task.id, status, hold=hold
        ),
    )


def run_daemon(
    config: Config,
    store: Store,
    herdr: Herdr,
    max_ticks: int = 0,
    sleep: Callable[[float], None] = time.sleep,
) -> int:
    """Reconcile the board until herdr goes away. 0 when another daemon has it.

    `max_ticks` and `sleep` exist for the selftest; the startup hook runs this
    unbounded.
    """
    lock = SyncLock(store.path)
    if not lock.acquire():
        print(f"herdr-kanban sync: already running (pid {daemon_pid(store.path)})")
        return 0
    pid_file = pid_path(store.path)
    pid_file.write_text(f"{os.getpid()}\n")
    # SIGTERM (activation restarting it, herdr shutting down) should run the
    # `finally` that removes the pid file, not just drop the process.
    previous = signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    syncer = store_syncer(config, store, herdr)
    down_since: float | None = None
    ticks = 0
    try:
        while True:
            store.reload()
            live = syncer.read_live()
            if live.down:
                now = time.monotonic()
                down_since = down_since if down_since is not None else now
                if now - down_since >= DOWN_GRACE_SECONDS:
                    print(f"herdr-kanban sync: herdr unreachable, exiting ({live.error})")
                    return 0
            else:
                down_since = None
                syncer.reconcile(live)
            ticks += 1
            if max_ticks and ticks >= max_ticks:
                return 0
            sleep(config.sync_seconds)
    finally:
        with contextlib.suppress(OSError):
            pid_file.unlink()
        lock.release()
        signal.signal(signal.SIGTERM, previous)


def detach(board: Path) -> bool:
    """Fork into the background. True in the daemon, False in the caller.

    A double fork with `setsid` between, so the daemon outlives the startup
    hook that ran it and has no terminal to lose. Output goes to `sync.log`
    beside the board, truncated on every start, which is where to look when the
    board says nothing is moving.
    """
    if os.fork() > 0:
        return False
    os.setsid()
    if os.fork() > 0:
        os._exit(0)
    log = log_path(board)
    log.parent.mkdir(parents=True, exist_ok=True)
    out = os.open(log, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
    null = os.open(os.devnull, os.O_RDONLY)
    os.dup2(null, 0)
    os.dup2(out, 1)
    os.dup2(out, 2)
    os.close(null)
    os.close(out)
    sys.stdout = os.fdopen(1, "w", buffering=1)
    sys.stderr = os.fdopen(2, "w", buffering=1)
    return True
