"""Plugin configuration: `config.toml`, with the same values as built-in defaults.

The repo's `plugins/kanban/config.toml` is copied to the plugin config dir on
every activation, so it is the source of truth for a Nix-managed install. This
module still carries defaults for every key so a bare checkout, a missing file,
or a hand-edited file with keys removed all keep working.
"""

from __future__ import annotations

import os
import tomllib
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

PLUGIN_ID = "herdr-kanban"

DEFAULT_COLUMNS: tuple[tuple[str, str], ...] = (
    ("backlog", "Backlog"),
    ("queued", "Queued"),
    ("doing", "In Progress"),
    ("blocked", "Blocked"),
    ("review", "Review"),
    ("done", "Done"),
)

# Column ids the board understands by meaning rather than position, so that a
# dispatch can pick a target on a board whose columns are named differently —
# `in-progress` instead of `doing`, `queued` instead of `todo`. Ids, not labels:
# these are the names tasks store. A board with none of them still works; the
# card simply stays where it is.
DOING_COLUMNS: tuple[str, ...] = ("doing", "in-progress", "progress", "started")

# Columns that mean "committed, waiting for an agent". Nothing the board
# dispatches rests in one — a send starts the card's agent, so it lands in In
# Progress — but the board still reads them as a set, because a card whose agent
# is already working must not be left sitting in one (`Syncer.settle_columns`).
# `todo` is kept in the list because this board's own column used to have that id,
# and a card stored before the rename is still a queued card.
QUEUED_COLUMNS: tuple[str, ...] = ("queued", "todo", "next", "ready")

# Columns that mean "an agent is waiting on you", "work is ready for review", and
# "closed". `blocked` is where `herdr-kanban block` parks a card and where the
# board's reconciliation carries one whose agent asked a question; `review` is
# what the dispatch protocol calls finished work; `done` is the column only you
# may close into. Matched against the board's own columns, so a rename does not
# move the meaning — and a column can say what it means outright with
# `role = "…"` (see `ROLE_CANDIDATES`).
BLOCKED_COLUMNS: tuple[str, ...] = ("blocked", "waiting", "on-hold", "hold")
REVIEW_COLUMNS: tuple[str, ...] = ("review", "reviewing", "verify", "validation")
DONE_COLUMNS: tuple[str, ...] = ("done", "closed", "complete", "completed")

# A column's `role` says what it *means*, so behaviour follows the meaning rather
# than the id: a board that renames `done` to `closed` but keeps `role = "done"`
# still refuses to let an agent close a card. The candidate lists above are the
# fallback for a board written before roles existed — the same shape
# `send_column` has always used.
ROLE_CANDIDATES: dict[str, tuple[str, ...]] = {
    "doing": DOING_COLUMNS,
    "queued": QUEUED_COLUMNS,
    "blocked": BLOCKED_COLUMNS,
    "review": REVIEW_COLUMNS,
    "done": DONE_COLUMNS,
}


@dataclass(frozen=True)
class Column:
    """One board column: `id` is stored on tasks, `label` is the heading.

    `role` is optional and names what the column means (`doing`, `queued`,
    `blocked`, `review`, `done`). It is what lets a board rename an id without
    changing behaviour.
    """

    id: str
    label: str
    role: str = ""


@dataclass
class Config:
    columns: list[Column] = field(
        default_factory=lambda: [Column(i, label) for i, label in DEFAULT_COLUMNS]
    )
    default_agent: str = "pi"
    default_column: str = "backlog"
    wip_limits: dict[str, int] = field(default_factory=dict)
    placement: str = "overlay"
    width: str = "95%"
    height: str = "90%"
    animate: bool = True
    icon_mode: str = "brand"
    sync_seconds: float = 2.0
    # Workspaces are opened and closed by hand a few times an hour, and every
    # read is a herdr subprocess, so they are re-read on their own slower clock
    # while agent state keeps to `sync_seconds`.
    workspace_sync_seconds: float = 10.0
    auto_move: bool = False
    # Deleting a card (`d`) also stops its agent and closes the tab its dispatch
    # opened: a card is the record of a run, and a card that is gone should not
    # leave an agent nobody is tracking. Set to false to delete the card and
    # keep the agent — the delete confirmation says which one it will do.
    auto_delete_agent: bool = True
    # Raise a herdr notification when a card's agent newly blocks on you. Only
    # transitions are announced — a board that opens onto a blocked card stays
    # quiet, because nothing has changed since you last looked.
    notify_on_block: bool = True
    # Say so when an *agent* files a card (`herdr-kanban add`, which is what the
    # dispatch protocol tells an agent to do with work it found). What counts as
    # an agent is the `created_by` the CLI already records, so a card captured
    # in the board's own form is never announced.
    notify_on_add: bool = True
    # The delivery switch for every notification above: whether the desktop is
    # asked too (macOS Notification Center, or notify-send on Linux). It is the
    # `...and` of each event key, because the other delivery — herdr's own
    # toast — only reaches someone already looking at herdr, and both events
    # are for the times you are not. A card an agent files has no toast at all,
    # so for that one this key is the only delivery there is.
    notify_system: bool = True
    # Append the board protocol (how to update the card) to every dispatch
    # prompt, so the agent can keep its own card current.
    announce_protocol: bool = True
    # Whether a title an *agent* generates replaces one you set by hand. Off by
    # default: a title you typed is yours, and an agent's later name is recorded
    # under Updates as a suggestion instead. On, the agent's title wins on a
    # card you retitled by hand too — the replaced title is kept in the card's
    # history (`was: …`) — which is what names a board by the work rather than
    # by its first capture. `--force` on one `herdr-kanban title` call means the
    # same thing for that call alone.
    agent_title_overrides: bool = False
    # Whether the dispatch form's **Git worktree** option is on to begin with.
    # Off by default: a worktree changes where the agent runs (a fresh checkout
    # instead of the workspace you are in), which is worth a deliberate click.
    # A card that already owns a worktree always defaults to reusing it, whatever
    # this says — the checkout is where its work lives.
    worktree: bool = False
    # Extra flags per agent kind, handed to `herdr agent start … -- <args>`.
    # Without these a dispatched agent runs with none of the flags you use
    # interactively (no --model, no --permission-mode).
    agent_args: dict[str, list[str]] = field(default_factory=dict)
    # Model names the add/edit form offers per agent kind (`[models]`). Passed to
    # `agent start` verbatim as `--model <name>`; the board never checks them
    # against a registry, because there is no registry to check them against —
    # each CLI has its own names, and only the person running it knows them.
    models: dict[str, list[str]] = field(default_factory=dict)
    # Card meta row: show how long the card has been sitting there.
    show_age: bool = True
    # ...and what it is waiting on an agent to do: the agent's kind beside its
    # mark on the meta row (`π pi`), and the live status word on the card's
    # bottom rule (`◐ working`). Each key hides a *word*; a mark is never hidden,
    # and the kind drops on a narrow column before its mark does.
    show_agent_kind: bool = True
    show_status_word: bool = True
    # Short id codes per workspace (`[workspaces]`), keyed by label or by
    # herdr's workspace id — `nixos-config-v2 = "cfg"` makes the cards filed
    # there `cfg-8`. Unlisted workspaces fall back to the label's own slug
    # (`workspace_code`), which is why this table is optional.
    workspace_aliases: dict[str, str] = field(default_factory=dict)
    # Past this age an untouched card's age is tinted (yellow, then red at 2x).
    stale_after_days: float = 3.0
    path: Path | None = None
    load_error: str = ""

    @property
    def column_ids(self) -> list[str]:
        return [c.id for c in self.columns]

    def column_named(self, candidates: tuple[str, ...]) -> str:
        """The first of `candidates` this board actually has, or ""."""
        return next((id for id in candidates if id in self.column_ids), "")

    def columns_with_role(self, role: str) -> list[str]:
        """The ids of the columns that mean `role`, in board order.

        A column that declares `role` outright wins over id matching, so the
        behaviour travels with the column and a rename cannot change it. Only
        when no column declares the role do the id candidates apply — which is
        how a board written before roles existed keeps working.
        """
        explicit = [column.id for column in self.columns if column.role == role]
        if explicit:
            return explicit
        candidates = ROLE_CANDIDATES.get(role, ())
        return [column.id for column in self.columns if column.id in candidates]

    def role_column(self, role: str) -> str:
        """The first column that means `role`, or "" when the board has none."""
        ids = self.columns_with_role(role)
        return ids[0] if ids else ""

    @property
    def human_only_columns(self) -> list[str]:
        """Columns only you may move a card into — the board's Done.

        Derived from the board rather than a literal id: a column says
        `role = "done"` (or is named in `DONE_COLUMNS`), and renaming it leaves
        the rule where it was. Every other column an agent may set.
        """
        return self.columns_with_role("done")

    @property
    def agent_statuses(self) -> list[str]:
        """The columns an agent may set: every column that is not human-only.

        The single source of truth for both the guard that refuses a `status`
        and the `agent_may_set` the CLI advertises, so the two cannot drift.
        """
        human_only = set(self.human_only_columns)
        return [column.id for column in self.columns if column.id not in human_only]

    @property
    def blocked_column(self) -> str:
        """Where `herdr-kanban block` parks a card, or "" if the board has none."""
        return self.role_column("blocked")

    @property
    def review_column(self) -> str:
        """Where the protocol sends finished work, or "" if the board has none."""
        return self.role_column("review")

    def send_column(self, current: str) -> str:
        """Where a send moves a card: In Progress, wherever it came from.

        A send starts (or re-prompts) the card's agent, and the board only calls
        it a success once the agent has actually begun a turn — so the card is
        in progress the moment the dispatch returns, whether it was sitting in
        the backlog or already in the flow. Queued is a column you park
        committed-but-unstarted work in by hand; nothing the board dispatches
        rests there. `current` is the fallback for a board with no In Progress
        column, where the card stays where it is, and an empty `current` (the
        auto-move case, which is not a send) also means In Progress.
        """
        return self.role_column("doing") or current

    def agent_args_for(self, kind: str) -> list[str]:
        return list(self.agent_args.get(kind, ()))

    def models_for(self, kind: str) -> list[str]:
        """The model names offered for `kind`, in the order to offer them."""
        return list(self.models.get(kind, ()))

    def label_for(self, column_id: str) -> str:
        for column in self.columns:
            if column.id == column_id:
                return column.label
        return column_id

    def wip_limit(self, column_id: str) -> int | None:
        limit = self.wip_limits.get(column_id)
        return limit if isinstance(limit, int) and limit > 0 else None


def config_dir() -> Path:
    """Where herdr puts this plugin's config (`plugin config-dir herdr-kanban`)."""
    env = os.environ.get("HERDR_PLUGIN_CONFIG_DIR")
    if env:
        return Path(env).expanduser()
    xdg = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    root = os.environ.get("HERDR_CONFIG_HOME") or str(Path(xdg) / "herdr")
    return Path(root).expanduser() / "plugins" / "config" / PLUGIN_ID


def config_path() -> Path:
    env = os.environ.get("KANBAN_CONFIG_FILE")
    return Path(env).expanduser() if env else config_dir() / "config.toml"


def _section(data: dict[str, Any], name: str) -> dict[str, Any]:
    value = data.get(name)
    return value if isinstance(value, dict) else {}


def _columns(raw: Any) -> list[Column]:
    if not isinstance(raw, list) or not raw:
        return [Column(i, label) for i, label in DEFAULT_COLUMNS]
    columns: list[Column] = []
    for entry in raw:
        if isinstance(entry, str):
            columns.append(Column(entry, entry.replace("-", " ").title()))
        elif isinstance(entry, dict) and entry.get("id"):
            column = Column(
                str(entry["id"]),
                str(entry.get("label") or entry["id"]),
                str(entry.get("role") or ""),
            )
            if column not in columns:
                columns.append(column)
    return columns or [Column(i, label) for i, label in DEFAULT_COLUMNS]


def _number(value: Any, fallback: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return fallback


def load_config(path: Path | None = None) -> Config:
    """Read config.toml, falling back to defaults for anything missing."""
    config = Config(path=path or config_path())
    try:
        with open(config.path, "rb") as handle:
            data = tomllib.load(handle)
    except FileNotFoundError:
        return config
    except (tomllib.TOMLDecodeError, OSError) as exc:
        config.load_error = f"{config.path}: {exc}"
        return config

    ui = _section(data, "ui")
    board = _section(data, "board")
    behavior = _section(data, "behavior")

    config.columns = _columns(board.get("columns"))
    column_ids = {c.id for c in config.columns}

    if isinstance(board.get("default_agent"), str):
        config.default_agent = board["default_agent"]
    if isinstance(board.get("default_column"), str):
        config.default_column = board["default_column"]
    if config.default_column not in column_ids:
        config.default_column = config.columns[0].id

    limits = board.get("wip_limits")
    if isinstance(limits, dict):
        config.wip_limits = {
            str(key): int(value)
            for key, value in limits.items()
            if isinstance(value, (int, float)) and not isinstance(value, bool)
        }

    if isinstance(ui.get("placement"), str):
        config.placement = ui["placement"]
    for key in ("width", "height"):
        value = ui.get(key)
        # bool is an int, so `width = true` would otherwise become the string
        # "True" and reach herdr as a popup size.
        if isinstance(value, (str, int)) and not isinstance(value, bool):
            setattr(config, key, str(value))
    if isinstance(ui.get("animate"), bool):
        config.animate = ui["animate"]
    if isinstance(ui.get("show_age"), bool):
        config.show_age = ui["show_age"]
    if isinstance(ui.get("show_agent_kind"), bool):
        config.show_agent_kind = ui["show_agent_kind"]
    if isinstance(ui.get("show_status_word"), bool):
        config.show_status_word = ui["show_status_word"]
    if ui.get("icon_mode") in ("brand", "unicode"):
        config.icon_mode = ui["icon_mode"]

    staleness = board.get("stale_after_days")
    if isinstance(staleness, (int, float)) and not isinstance(staleness, bool):
        config.stale_after_days = max(0.1, float(staleness))

    # [agents.<kind>] args = ["…"] — flags for dispatch, per agent kind.
    agents = data.get("agents")
    if isinstance(agents, dict):
        for kind, spec in agents.items():
            if not isinstance(spec, dict):
                continue
            args = spec.get("args")
            if isinstance(args, list):
                cleaned = [str(arg) for arg in args if str(arg).strip()]
                if cleaned:
                    config.agent_args[str(kind)] = cleaned

    # [models] claude = ["sonnet", "opus"] — the picker's options, per kind.
    models = data.get("models")
    if isinstance(models, dict):
        for kind, names in models.items():
            if not isinstance(names, list):
                continue
            cleaned = [str(name).strip() for name in names if str(name).strip()]
            if cleaned:
                config.models[str(kind)] = cleaned

    # [workspaces] label-or-id = "code" — the id prefix for cards filed there.
    # The value is slugified like a label is (`slug_code` in store.py), so a
    # typo'd separator cannot produce an id that is not a herdr agent name.
    aliases = data.get("workspaces")
    if isinstance(aliases, dict):
        config.workspace_aliases = {
            str(key): str(value)
            for key, value in aliases.items()
            if isinstance(value, str) and value.strip()
        }

    config.sync_seconds = max(0.5, _number(behavior.get("sync_seconds"), 2.0))
    config.workspace_sync_seconds = max(
        1.0, _number(behavior.get("workspace_sync_seconds"), 10.0)
    )
    if isinstance(behavior.get("auto_move"), bool):
        config.auto_move = behavior["auto_move"]
    if isinstance(behavior.get("auto_delete_agent"), bool):
        config.auto_delete_agent = behavior["auto_delete_agent"]
    if isinstance(behavior.get("notify_on_block"), bool):
        config.notify_on_block = behavior["notify_on_block"]
    if isinstance(behavior.get("notify_on_add"), bool):
        config.notify_on_add = behavior["notify_on_add"]
    if isinstance(behavior.get("notify_system"), bool):
        config.notify_system = behavior["notify_system"]
    if isinstance(behavior.get("announce_protocol"), bool):
        config.announce_protocol = behavior["announce_protocol"]
    if isinstance(behavior.get("agent_title_overrides"), bool):
        config.agent_title_overrides = behavior["agent_title_overrides"]
    if isinstance(behavior.get("worktree"), bool):
        config.worktree = behavior["worktree"]

    return config
