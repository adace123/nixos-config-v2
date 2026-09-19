"""Entry point for the board: `python -m kanban`.

The same module backs the plugin pane, the `herdr-kanban` CLI, and the
development helpers:

* `--snapshot` prints the board as plain text — how the UI is reviewed and
  regression-checked without a terminal.
* `--demo` swaps in sample tasks, workspaces, and agents.
* `--selftest` drives the real app headlessly and asserts the interaction
  contract (add, move, filter, dispatch planning).
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from . import __version__, icons
from .config import load_config
from .herdr import Herdr
from .model import LiveState, UiState, build_view
from .store import Store, board_path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="kanban", description="Herdr kanban board")
    parser.add_argument("--version", action="store_true", help="print version and exit")
    parser.add_argument(
        "--snapshot",
        action="store_true",
        help="print the board as plain text at --width/--height and exit",
    )
    parser.add_argument(
        "--selftest",
        action="store_true",
        help="run headless interaction checks and exit",
    )
    parser.add_argument(
        "--demo", action="store_true", help="use sample data instead of the real board"
    )
    parser.add_argument(
        "--screen",
        metavar="DIALOG",
        nargs="?",
        const="board",
        help=(
            "development aid: render the real Textual screen at --width/--height "
            "and print it as text. DIALOG may be board (default), add, dispatch, "
            "detail, filter, help, or delete."
        ),
    )
    parser.add_argument(
        "--keys",
        help=(
            "development aid: comma-separated keys to press after opening "
            "--screen, e.g. --screen detail --keys l,enter"
        ),
    )
    parser.add_argument("--width", type=int, default=0, help="snapshot width in cells")
    parser.add_argument(
        "--height", type=int, default=0, help="snapshot height in cells"
    )
    parser.add_argument(
        "--board-file", help="use this board file instead of the default"
    )
    parser.add_argument(
        "--quick-add",
        action="store_true",
        help="open the board with the add-task form already up",
    )
    return parser


def quick_add_requested(args: argparse.Namespace) -> bool:
    if args.quick_add:
        return True
    return os.environ.get("KANBAN_QUICK_ADD", "").strip().lower() in (
        "1",
        "true",
        "yes",
    )


def _terminal_size() -> tuple[int, int]:
    try:
        size = os.get_terminal_size()
        return size.columns, size.lines
    except OSError:
        return 120, 40


def run_snapshot(args: argparse.Namespace) -> int:
    config = load_config()
    width = args.width or min(140, _terminal_size()[0])
    height = args.height or min(44, _terminal_size()[1])

    if args.demo:
        from .demo import demo_live, demo_tasks

        tasks, live = demo_tasks(), demo_live()
        board_file = "~/.local/state/herdr/plugins/herdr-kanban/board.json (demo)"
    else:
        store = Store(Path(args.board_file) if args.board_file else board_path())
        store.load()
        tasks = list(store.tasks)
        client = Herdr()
        workspaces, workspace_result = client.workspaces()
        agents, agent_result = client.agents()
        live = LiveState(
            workspaces={w.id: w for w in workspaces},
            agents={a.name: a for a in agents},
            agents_by_pane={a.pane_id: a for a in agents},
            down=not (workspace_result.ok or agent_result.ok),
        )
        board_file = str(store.path)

    ui = UiState()
    view = build_view(
        config,
        tasks,
        live,
        ui,
        width=width,
        height=height,
        board_path=board_file,
        icon_mode=icons.icon_mode(config.icon_mode),
    )
    # Select the first card on the board so the snapshot shows focus styling.
    for index, column in enumerate(view.columns):
        if column.cards:
            ui.selected_id = column.cards[0].task.id
            ui.selected_column = index
            view = build_view(
                config,
                tasks,
                live,
                ui,
                width=width,
                height=height,
                board_path=board_file,
                icon_mode=icons.icon_mode(config.icon_mode),
            )
            break
    from .render import render_plain

    print(render_plain(view))
    return 0


def run_screen_snapshot(args: argparse.Namespace) -> int:
    """Print what the real Textual screen renders, dialogs included.

    The plain `--snapshot` renderer draws the board's own canvas; this one goes
    through Textual's compositor, so dialog chrome (borders, buttons, selects)
    can be reviewed without a terminal.
    """
    import asyncio

    from .app import KanbanApp

    keys = {
        "board": None,
        "add": "a",
        "dispatch": "s",
        "detail": "enter",
        "filter": "slash",
        "help": "question_mark",
        "delete": "d",
    }
    dialog = args.screen or "board"
    if dialog not in keys:
        print(
            f"unknown dialog {dialog!r}; expected one of {', '.join(keys)}",
            file=sys.stderr,
        )
        return 2
    width = args.width or 140
    height = args.height or 40
    store = Store(Path(args.board_file) if args.board_file else board_path())

    async def _render() -> str:
        app = KanbanApp(
            config=load_config(),
            store=store,
            herdr=Herdr(binary="/nonexistent-herdr"),
            demo=True,
        )
        async with app.run_test(size=(width, height)) as pilot:
            await pilot.pause()
            key = keys[dialog]
            if key:
                await pilot.press(key)
                await pilot.pause()
            for extra in (args.keys or "").split(","):
                if extra.strip():
                    await pilot.press(extra.strip())
                    await pilot.pause()
            strips = app.screen._compositor.render_strips()
            return "\n".join(
                "".join(segment.text for segment in strip) for strip in strips
            )

    print(asyncio.run(_render()).rstrip())
    return 0


def main(argv: list[str] | None = None) -> int:
    raw = list(sys.argv[1:] if argv is None else argv)

    # The board's task verbs (what a dispatched agent calls back with) come
    # before the flag parser: `herdr-kanban status review`, `... note "..."`.
    from .cli import AGENT_COMMANDS, run_agent_command

    if raw and raw[0] in AGENT_COMMANDS:
        return run_agent_command(raw)

    args = build_parser().parse_args(raw)

    if args.version:
        print(f"herdr-kanban {__version__}")
        return 0
    if args.snapshot:
        return run_snapshot(args)
    if args.screen:
        return run_screen_snapshot(args)
    if args.selftest:
        from .selftest import run_selftest

        return run_selftest(args)

    from .app import KanbanApp

    store = Store(Path(args.board_file) if args.board_file else board_path())
    app = KanbanApp(
        config=load_config(),
        store=store,
        herdr=Herdr(),
        quick_add=quick_add_requested(args),
        demo=args.demo,
    )
    app.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
