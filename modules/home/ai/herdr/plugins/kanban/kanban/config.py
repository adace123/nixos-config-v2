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
# card simply stays where it is. `todo` is kept in the queued list because this
# board's own column used to have that id, and a card stored before the rename
# should still be queued rather than sent straight to In Progress.
NOT_STARTED_COLUMNS: tuple[str, ...] = ("backlog", "later", "icebox")
QUEUED_COLUMNS: tuple[str, ...] = ("queued", "todo", "next", "ready")
DOING_COLUMNS: tuple[str, ...] = ("doing", "in-progress", "progress", "started")


@dataclass(frozen=True)
class Column:
    """One board column: `id` is stored on tasks, `label` is the heading."""

    id: str
    label: str


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
    # Raise a herdr notification when a card's agent newly blocks on you. Only
    # transitions are announced — a board that opens onto a blocked card stays
    # quiet, because nothing has changed since you last looked.
    notify_on_block: bool = True
    # Append the board protocol (how to update the card) to every dispatch
    # prompt, so the agent can keep its own card current.
    announce_protocol: bool = True
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

    def send_column(self, current: str) -> str:
        """Where a send moves a card, given the column it is sitting in.

        A card still in the backlog has not been committed to anything yet, so
        sending it queues it in Queued — the column that means "an agent should
        pick this up". Anything already in the flow goes straight to In Progress,
        which is where the agent it just started belongs. Both fall back to the
        card's own column on a board that has neither, and an empty `current`
        (the auto-move case, which is not a send) means In Progress.
        """
        if current in NOT_STARTED_COLUMNS:
            queued = self.column_named(QUEUED_COLUMNS)
            if queued:
                return queued
        return self.column_named(DOING_COLUMNS) or current

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
            column = Column(str(entry["id"]), str(entry.get("label") or entry["id"]))
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

    config.sync_seconds = max(0.5, _number(behavior.get("sync_seconds"), 2.0))
    config.workspace_sync_seconds = max(
        1.0, _number(behavior.get("workspace_sync_seconds"), 10.0)
    )
    if isinstance(behavior.get("auto_move"), bool):
        config.auto_move = behavior["auto_move"]
    if isinstance(behavior.get("notify_on_block"), bool):
        config.notify_on_block = behavior["notify_on_block"]
    if isinstance(behavior.get("announce_protocol"), bool):
        config.announce_protocol = behavior["announce_protocol"]

    return config
