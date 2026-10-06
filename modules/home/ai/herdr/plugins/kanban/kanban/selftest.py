"""Headless interaction checks — `python -m kanban --selftest`.

Drives the real app through Textual's test pilot against the demo dataset, so it
needs no terminal, no herdr server, and no board file. It asserts the board's
contract: cursor movement, moving cards between columns, reordering, filtering,
adding a task with a workspace and an agent, and that each dialog opens and
closes. Exit status is non-zero if any check fails.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import sys
import time
from pathlib import Path
from tempfile import TemporaryDirectory

from .app import KanbanApp
from .config import load_config
from .herdr import Herdr
from .render import render_board
from .store import Store, Task, state_dir


class Checker:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.passed = 0

    def check(self, name: str, condition: bool, detail: str = "") -> None:
        if condition:
            self.passed += 1
            print(f"  ok    {name}")
        else:
            self.failures.append(name)
            print(f"  FAIL  {name}{('  — ' + detail) if detail else ''}")


def check_store(check: Checker, tmp: str) -> None:
    """The messy half: real persistence, plans, and dispatch bookkeeping.

    The app checks below run on demo data (no disk, no herdr), so the store and
    the dispatch planner get exercised here instead.
    """
    import json
    import time

    from .dispatch import plan_for
    from .herdr import Agent, Workspace
    from .model import LiveState, UiState, build_view

    store = Store(Path(tmp) / "board.json")
    store.load()
    config = load_config()

    first = store.add(
        title="  Fix the thing  ",
        notes="details",
        workspace_id="w1",
        workspace_label="nixos-config-v2",
        # What `herdr-kanban add`/the board hand in: `[workspaces]` resolved
        # against the label, or the label's own slug when there is no alias.
        workspace_code="cfg",
        agent_kind="pi",
        status="queued",
    )
    second = store.add(title="Second", agent_kind="claude", status="queued")
    third = store.add(title="Third", agent_kind="codex", status="backlog")
    check.check(
        "store numbers each code from one, and trims titles",
        (first.id, second.id, third.id) == ("cfg-1", "K1", "K2")
        and first.title == "Fix the thing",
        f"{first.id}/{second.id}/{third.id} {first.title!r}",
    )

    store.set_status(second.id, "doing")
    store.reorder(first.id, 1)
    check.check(
        "set_status moves a card and reorder is column-local",
        [task.id for task in store.in_column("doing")] == ["K1"]
        and [task.id for task in store.in_column("queued")] == ["cfg-1"],
        str([task.id for task in store.in_column("queued")]),
    )
    store.reorder(third.id, -5)
    store.reorder(third.id, 99)
    check.check(
        "out-of-range reorders are refused",
        [task.id for task in store.in_column("backlog")] == ["K2"],
    )

    # An edit that changes the card's column (`e` in the board) reaches the
    # store through `update`, not `set_status`. It still has to move the card
    # like every other status change: last in the new column's stored order
    # (what `sort = "manual"` shows), with the transition in its history rather
    # than a bare "edited status".
    store.update(first.id, status="backlog")
    check.check(
        "editing a card's column lands it last in the stored order and records the move",
        [task.id for task in store.in_column("backlog")] == ["K2", "cfg-1"]
        and store.by_id(first.id).history[-1]["what"] == "queued -> backlog",
        f"{[task.id for task in store.in_column('backlog')]} "
        f"{store.by_id(first.id).history[-1]['what']}",
    )

    # A second reader must see exactly what was written (atomic replace + lock).
    # Order is list order, so moving a card to another column re-appends it —
    # compare per-id state instead of raw order.
    reloaded = Store(store.path)
    reloaded.load()
    check.check(
        "the board round-trips through the file",
        {task.id: task.status for task in reloaded.tasks}
        == {task.id: task.status for task in store.tasks},
        str([(task.id, task.status) for task in reloaded.tasks]),
    )
    payload = json.loads(store.path.read_text(encoding="utf-8"))
    check.check(
        "the file is versioned JSON with a counter per code",
        payload.get("version") == 2
        and payload.get("counters") == {"K": 2, "cfg": 1},
        f"{payload.get('version')} {payload.get('counters')}",
    )
    check.check(
        "and no board-wide sequence is left in it",
        "seq" not in payload,
        str(sorted(payload)),
    )
    check.check(
        "deleting a task removes it",
        store.delete(third.id) is not None and len(store.tasks) == 2,
    )
    check.check("deleting a missing task is a no-op", store.delete("K99") is None)

    # The board file path: herdr injects the state dir, and the standalone
    # fallback keeps the same shape so the CLI and the pane share one board.
    injected = os.environ.pop("HERDR_PLUGIN_STATE_DIR", None)
    try:
        fallback = state_dir()
        check.check(
            "the standalone state dir matches herdr's layout",
            fallback.parts[-3:] == ("herdr", "plugins", "herdr-kanban"),
            str(fallback),
        )
        os.environ["HERDR_PLUGIN_STATE_DIR"] = "/tmp/kanban-state-probe"
        check.check(
            "HERDR_PLUGIN_STATE_DIR wins when herdr launches the board",
            state_dir() == Path("/tmp/kanban-state-probe"),
            str(state_dir()),
        )
    finally:
        os.environ.pop("HERDR_PLUGIN_STATE_DIR", None)
        if injected is not None:
            os.environ["HERDR_PLUGIN_STATE_DIR"] = injected

    # dispatch planning ---------------------------------------------------
    # Named the way herdr reports it: the name `agent start` was given (the
    # card's, `k2-pi`), not the kind — which is what the card is verified
    # against before its pane is trusted.
    running = Agent(
        "k2-pi", "working", "w1", "w1:p9", "w1:t1", "/tmp", False, "π - w1", ""
    )
    live = LiveState(
        workspaces={"w1": Workspace("w1", "nixos-config-v2", 1, "w1:t1", "idle")},
        agents={"k2-pi": running},
        agents_by_pane={"w1:p9": running},
    )
    store.update(
        second.id, pane_id="w1:p9", agent_name="k2-pi", dispatched_at=time.time()
    )
    plan_running = plan_for(store.by_id(second.id), config, live)
    check.check(
        "a task with a live agent reuses it, targeting the pane",
        plan_running.reuses_running_agent and plan_running.reuse_target == "w1:p9",
        f"{plan_running.reuses_running_agent} {plan_running.reuse_target}",
    )
    plan_fresh = plan_for(store.by_id(first.id), config, live, fallback_workspace="w1")
    check.check(
        "a task with no agent plans a fresh start in its workspace",
        not plan_fresh.reuses_running_agent
        and plan_fresh.workspace_id == "w1"
        and plan_fresh.kind == "pi"
        and plan_fresh.name == "cfg-1"
        and plan_fresh.tab_label.startswith("cfg-1 "),
        f"{plan_fresh.workspace_id} {plan_fresh.kind} {plan_fresh.name}",
    )
    check.check(
        "the prompt leads with the title and notes, then the protocol",
        plan_fresh.prompt.startswith("Fix the thing\n\ndetails")
        and "herdr-kanban status review" in plan_fresh.prompt,
        repr(plan_fresh.prompt[:60]),
    )

    ui = UiState(selected_id=first.id, selected_column=1)
    view = build_view(
        config,
        store.tasks,
        live,
        ui,
        width=100,
        height=20,
        board_path=str(store.path),
        icon_mode="unicode",
    )
    check.check(
        "a live agent's status reaches its card",
        view.card("K1") is not None and view.card("K1").status == "working",
        str(view.card("K1").status if view.card("K1") else None),
    )
    check.check(
        "a card in a closed workspace is flagged",
        view.card("cfg-1") is not None and view.card("cfg-1").workspace_ok,
    )

    # Column order. `updated` is the default, `manual` is the board file's own
    # list order — and the file is the *only* place either one lives: sorting is
    # a view, so nothing here may rewrite the order `J`/`K` edits.
    from .config import Config

    older = store.add(title="Older", status="review")
    newer = store.add(title="Newer", status="review")
    untimed = store.add(title="Hand-written, no timestamp", status="review")
    # Fixed stamps rather than a sleep, so the check cannot go green by luck of
    # the clock (or red on a machine whose timer is coarse). `untimed` keeps the
    # 0.0 a hand-edited card has: "never touched" must not read as "newest".
    older.updated_at = 100.0
    newer.updated_at = 200.0
    untimed.updated_at = 0.0
    listed = [task.id for task in store.in_column("review")]
    check.check(
        "the store keeps list order, whatever the board is told to show",
        listed == [older.id, newer.id, untimed.id],
        str(listed),
    )
    for mode, expected, what in (
        (
            "updated",
            [newer.id, older.id, untimed.id],
            'sort = "updated" draws the card touched most recently first',
        ),
        (
            "manual",
            [older.id, newer.id, untimed.id],
            'sort = "manual" keeps the board file\'s order',
        ),
    ):
        rendered = build_view(
            Config(sort=mode), store.tasks, live, UiState(), width=120, height=30
        )
        column = next(
            entry for entry in rendered.columns if entry.column.id == "review"
        )
        check.check(
            what,
            [card.task.id for card in column.cards] == expected,
            f"{mode}: {[card.task.id for card in column.cards]}",
        )
    check.check(
        "sorting is a view, not a write: the file order survives both",
        [task.id for task in store.in_column("review")] == listed,
        str([task.id for task in store.in_column("review")]),
    )


def check_list_order(check: Checker, tmp: str) -> None:
    """`list --json` holds its order; bare `list` still follows the board.

    The configured sort is a view for an eye moving down a column, and it keys
    on `updated_at`: a card that is noted or moved rises to the top. An
    automation reading the JSON array by position — the "send the top of the
    backlog" shape — would watch the board shuffle underneath it between two
    calls, so the machine-readable form reports the board file's own list order
    instead. Bare `list` keeps drawing what the board draws.
    """
    import contextlib
    import io
    import json
    import os

    from .cli import run_agent_command

    board = Path(tmp) / "list-order-board.json"
    config_path = _pin_config(tmp, "list-order-config.toml", sort="updated")
    saved = {
        key: os.environ.get(key)
        for key in ("KANBAN_BOARD_FILE", "KANBAN_CONFIG_FILE", "HERDR_PANE_ID")
    }
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    os.environ["KANBAN_CONFIG_FILE"] = str(config_path)
    os.environ.pop("HERDR_PANE_ID", None)

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        return code, (out.getvalue() + err.getvalue()).strip()

    try:
        store = Store.open(board)
        for title in ("First in the file", "Second in the file", "Third in the file"):
            store.add(title=title, status="backlog")
        # Stamps go on the file the CLI reads, not on the objects `add` returned:
        # each add reloads, so an earlier card's in-memory stamp is gone by the
        # next one. Fixed stamps rather than a sleep, so the order being checked
        # is decided by the check and not by timer resolution.
        payload = store.payload()
        for item, stamp in zip(payload["tasks"], (100.0, 200.0, 300.0)):
            item["updated_at"] = stamp
        board.write_text(json.dumps(payload, indent=2), encoding="utf-8")

        file_order = [item["id"] for item in payload["tasks"]]
        code, out = cli("list", "--json")
        check.check(
            "list --json keeps the board file's order under sort = updated",
            code == 0 and [item["id"] for item in json.loads(out)] == file_order,
            out[:80],
        )
        code, out = cli("list")
        positions = [out.index(task_id) for task_id in file_order]
        check.check(
            "bare list still follows the configured sort",
            code == 0 and positions == sorted(positions, reverse=True),
            out,
        )
        # A touch is exactly what the view sort reacts to; the JSON must not.
        code, _ = cli("note", file_order[0], "touched, so it is the newest now")
        code2, out = cli("list", "--json")
        check.check(
            "a touch that reorders the board leaves list --json alone",
            code == 0
            and code2 == 0
            and [item["id"] for item in json.loads(out)] == file_order,
            out[:80],
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def check_assign(check: Checker, tmp: str) -> None:
    """`assign` changes the agent a card is sent to, and says what it did."""
    import contextlib
    import io
    import os
    from dataclasses import replace

    from . import cli as cli_module
    from .cli import run_agent_command
    from .config import load_config

    board = Path(tmp) / "assign-board.json"
    saved = {k: os.environ.get(k) for k in ("KANBAN_BOARD_FILE", "HERDR_PANE_ID")}
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    os.environ.pop("HERDR_PANE_ID", None)

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        return code, (out.getvalue() + err.getvalue()).strip()

    try:
        store = Store.open(board)
        card = store.add(title="reassign me", status="backlog", agent_kind="claude",
                         agent_model="sonnet")

        code, out = cli("assign", card.id, "pi")
        after = Store.open(board).by_id(card.id)
        check.check(
            "assign moves a card to another agent kind",
            code == 0 and after.agent_kind == "pi" and out.startswith(f"{card.id} -> pi"),
            out,
        )
        check.check(
            "and drops a model the new kind has no entry for",
            after.agent_model == "" and "dropped" in out,
            out,
        )
        code, out = cli("assign", card.id, "pi", "--model", "deepseek-v4-flash")
        check.check(
            "--model sets the model with it",
            code == 0 and Store.open(board).by_id(card.id).agent_model
            == "deepseek-v4-flash",
            out,
        )
        code, out = cli("assign", card.id, "pi")
        check.check(
            "the same kind again keeps the model and says nothing changed",
            code == 0 and "already assigned" in out
            and Store.open(board).by_id(card.id).agent_model == "deepseek-v4-flash",
            out,
        )
        code, out = cli("assign", card.id, "pi", "--model", "default")
        check.check(
            "--model default clears it",
            code == 0 and Store.open(board).by_id(card.id).agent_model == "",
            out,
        )
        code, out = cli("assign", card.id, "nonesuch")
        check.check(
            "an unknown kind is refused, naming the ones there are",
            code == 2 and "unknown agent kind" in out and "claude" in out,
            out,
        )
        store.hand_over(card.id, "doing", pane_id="w1:p4", dispatched_at=time.time())
        code, out = cli("assign", card.id, "claude")
        check.check(
            "a dispatched card is told the running agent is not swapped",
            code == 0 and "re-prompts it" in out,
            out,
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def check_rename(check: Checker, tmp: str) -> None:
    """`rename` moves a card to another code, and renumbers it when it must.

    A number is issued per code, so it survives the move only while the code
    being moved to has not spent it; links from follow-ups follow, the new id
    must be usable as a herdr agent name, and an agent cannot rename a card
    without `--force`.
    """
    import contextlib
    import io
    import os

    from .cli import run_agent_command
    from .store import task_seq

    board = Path(tmp) / "rename-board.json"
    saved = {k: os.environ.get(k) for k in ("KANBAN_BOARD_FILE", "HERDR_PANE_ID")}
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    os.environ.pop("HERDR_PANE_ID", None)

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        return code, (out.getvalue() + err.getvalue()).strip()

    try:
        store = Store.open(board)
        parent = store.add(title="the parent", status="doing", workspace_id="w1")
        child = store.add(title="found in it", status="backlog", parent_id=parent.id)
        other = store.add(title="someone else", status="backlog")
        number = task_seq(parent.id)

        code, out = cli("rename", parent.id, "herdr-kanban")
        after = Store.open(board)
        renamed = f"herdr-kanban-{number}"
        check.check(
            "rename into a code that has not spent the number keeps it",
            code == 0 and out == f"{parent.id} -> {renamed}"
            and after.by_id(renamed) is not None,
            out,
        )
        check.check(
            "and the cards found during it follow the new id",
            after.by_id(child.id).parent_id == renamed,
            after.by_id(child.id).parent_id,
        )
        check.check(
            "and its history says what it was",
            f"renamed from {parent.id}" in after.by_id(renamed).history[-1]["what"],
        )
        check.check(
            "and a bare number two codes have issued names neither",
            after.resolve(str(number)) is None
            and renamed in after.ids_with_seq(number)
            and child.id in after.ids_with_seq(number),
            str(after.ids_with_seq(number)),
        )
        code, out = cli("rename", renamed, f"Infra-{number}")
        check.check(
            "a full id is accepted, case-insensitively",
            code == 0 and Store.open(board).by_id(f"infra-{number}") is not None,
            out,
        )
        code, out = cli("rename", f"infra-{number}", "infra-999")
        check.check(
            "but not one that changes the number",
            code == 1
            and "renumber" in out
            and Store.open(board).by_id(f"infra-{number}") is not None,
            out,
        )
        code, out = cli("rename", f"infra-{number}", "herdr-kanban")
        current = f"herdr-kanban-{number + 1}"
        check.check(
            "a code that has already spent the number gives the card its next",
            code == 0 and out.startswith(f"infra-{number} -> {current}"),
            out,
        )
        check.check(
            "and that is what the board holds",
            Store.open(board).by_id(current) is not None
            and Store.open(board).by_id(f"infra-{number}") is None,
            out,
        )
        code, out = cli("rename", current, "9lives")
        check.check(
            "nor one herdr would not take as an agent name",
            code == 1 and "not a usable id" in out,
            out,
        )
        code2, out2 = cli("rename", other.id, other.id)
        check.check(
            "renaming to the id a card already has is a no-op, not an error",
            code2 == 0 and out2.endswith("unchanged"),
            out2,
        )
        os.environ["HERDR_PANE_ID"] = "w1:p9"
        code, out = cli("rename", current, "agent")
        forced, _ = cli("rename", current, "agent", "--force")
        check.check(
            "an agent is refused without --force",
            code == 1 and "yours to change" in out and forced == 0,
            out,
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def check_counters(check: Checker, tmp: str) -> None:
    """The per-code counters: what they are, where they come from, and `renumber`.

    The board's numbers used to come from one board-wide counter. They are
    issued per workspace code now, which makes three things worth pinning: that
    a code's counter never hands out a number it has used (not after `d`, not
    after `A`), that a `version` 1 file migrates by taking each code's counter
    from the ids it already holds, and that the one verb which rewrites ids —
    `renumber` — compacts a code without letting two cards share a name, keeps
    the archived half of a code in the same namespace, and is the human's to
    run.
    """
    import contextlib
    import io
    import json
    import os

    from .cli import run_agent_command

    saved = {k: os.environ.get(k) for k in ("KANBAN_BOARD_FILE", "HERDR_PANE_ID")}
    os.environ.pop("HERDR_PANE_ID", None)

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        return code, (out.getvalue() + err.getvalue()).strip()

    try:
        # -- a code counts on its own, and never twice ---------------------
        board = Path(tmp) / "counters-board.json"
        os.environ["KANBAN_BOARD_FILE"] = str(board)
        store = Store.open(board)
        cfg1 = store.add(title="one", workspace_code="cfg")
        cfg2 = store.add(title="two", workspace_code="cfg")
        other1 = store.add(title="elsewhere", workspace_code="pers")
        plain = store.add(title="no workspace")
        check.check(
            "each code issues its own numbers from one",
            (cfg1.id, cfg2.id, other1.id, plain.id)
            == ("cfg-1", "cfg-2", "pers-1", "K1"),
            f"{cfg1.id}/{cfg2.id}/{other1.id}/{plain.id}",
        )
        store.delete(cfg2.id)
        after_delete = store.add(title="after a delete", workspace_code="cfg")
        store.archive(other1.id)
        after_archive = store.add(title="after an archive", workspace_code="pers")
        check.check(
            "a deleted or archived number is not reissued in its code",
            after_delete.id == "cfg-3" and after_archive.id == "pers-2",
            f"{after_delete.id}/{after_archive.id}",
        )
        check.check(
            "and the counters are the file's own record of that",
            json.loads(board.read_text(encoding="utf-8")).get("counters")
            == {"K": 1, "cfg": 3, "pers": 2},
            str(json.loads(board.read_text(encoding="utf-8")).get("counters")),
        )

        # -- a version 1 file migrates from the ids it already holds -------
        old = Path(tmp) / "counters-v1.json"
        old.write_text(
            json.dumps(
                {
                    "version": 1,
                    "seq": 88,
                    "tasks": [
                        {"id": "nixos-88", "title": "newest"},
                        {"id": "pers-63", "title": "older"},
                        {"id": "K14", "title": "plain"},
                    ],
                    "archived": [{"id": "nixos-51", "title": "archived"}],
                }
            ),
            encoding="utf-8",
        )
        migrated = Store.open(old)
        check.check(
            "a version 1 board takes each code's counter from its own ids",
            migrated.board.counters == {"K": 14, "nixos": 88, "pers": 63},
            str(migrated.board.counters),
        )
        check.check(
            "and keeps every id it already had",
            [task.id for task in migrated.tasks]
            == ["nixos-88", "pers-63", "K14"],
            str([task.id for task in migrated.tasks]),
        )
        check.check(
            "so the next card in a code carries on from that code's own end",
            migrated.add(title="next", workspace_code="nixos").id == "nixos-89"
            and migrated.add(title="next", workspace_code="pers").id == "pers-64"
            and migrated.add(title="next").id == "K15",
            str(migrated.board.counters),
        )

        # -- a hand-edited counter cannot take the board down --------------
        broken = Path(tmp) / "counters-broken.json"
        broken.write_text(
            json.dumps(
                {
                    "version": 2,
                    "counters": {"nixos": "three", "cfg": -2, "K": 9},
                    "tasks": [{"id": "nixos-5", "title": "hand-edited"}],
                }
            ),
            encoding="utf-8",
        )
        check.check(
            "a counter hand-edited into a word is dropped, not raised",
            Store.open(broken).board.counters == {"K": 9, "nixos": 5},
            str(Store.open(broken).board.counters),
        )

        # -- renumber ------------------------------------------------------
        # A board whose codes are sparse, the way the real one is after years of
        # one board-wide counter: nixos has four cards numbered 85 … 89.
        board2 = Path(tmp) / "counters-renumber.json"
        board2.write_text(
            json.dumps(
                {
                    "version": 2,
                    "counters": {"nixos": 89, "pers": 63},
                    "tasks": [
                        {"id": "nixos-85", "title": "first"},
                        {
                            "id": "nixos-86",
                            "title": "found in it",
                            "parent_id": "nixos-85",
                        },
                        {"id": "nixos-89", "title": "last"},
                        {"id": "pers-63", "title": "only"},
                    ],
                    "archived": [{"id": "nixos-87", "title": "archived"}],
                }
            ),
            encoding="utf-8",
        )
        os.environ["KANBAN_BOARD_FILE"] = str(board2)
        code, out = cli("renumber")
        compacted = Store.open(board2)
        check.check(
            "renumber compacts each code to 1..n, archived cards included",
            code == 0
            and [task.id for task in compacted.tasks]
            == ["nixos-1", "nixos-2", "nixos-4", "pers-1"]
            and [task.id for task in compacted.archived] == ["nixos-3"],
            f"{code} {out} | {[task.id for task in compacted.tasks]}",
        )
        check.check(
            "and the file's own list order is left alone",
            [task.title for task in compacted.tasks]
            == ["first", "found in it", "last", "only"],
            str([task.title for task in compacted.tasks]),
        )
        check.check(
            "and a follow-up link follows the card it was found in",
            compacted.by_id("nixos-2").parent_id == "nixos-1",
            str(compacted.by_id("nixos-2").parent_id),
        )
        check.check(
            "and the counter is compacted too, not left where it was",
            compacted.board.counters == {"nixos": 4, "pers": 1}
            and compacted.add(title="next", workspace_code="nixos").id
            == "nixos-5",
            str(compacted.board.counters),
        )
        check.check(
            "and the run says what it did, per code",
            "renumbered 5 cards" in out
            and "nixos: 4 cards now nixos-1..nixos-4" in out
            and "board.json.bak" in out,
            out,
        )
        code, out = cli("renumber")
        check.check(
            "and a board that already counts 1..n has nothing to do",
            code == 0 and "nothing to renumber" in out,
            out,
        )
        os.environ["HERDR_PANE_ID"] = "w1:p9"
        code, out = cli("renumber")
        forced, _ = cli("renumber", "--force")
        check.check(
            "an agent cannot renumber the board without --force",
            code == 1 and "yours to decide" in out and forced == 0,
            out,
        )
        code, out = cli("renumber", "now")
        check.check(
            "and renumber takes no argument",
            code == 2 and "usage" in out,
            out,
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def check_archive(check: Checker, tmp: str) -> None:
    """Archive keeps a card: off the board, still on disk, restorable.

    `d` deletes (the record goes with the card); `A` archives. That distinction
    is the feature, so what is pinned here is that the card leaves `tasks`, lands
    in `archived` with where it came from, survives a reload, comes back to its
    own column, stays addressable by id and number, and cannot be taken off the
    board by an agent without `--force`.
    """
    import contextlib
    import io
    import json
    import os

    from .cli import run_agent_command
    from .store import task_seq

    board = Path(tmp) / "archive-board.json"
    saved = {k: os.environ.get(k) for k in ("KANBAN_BOARD_FILE", "HERDR_PANE_ID")}
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    os.environ.pop("HERDR_PANE_ID", None)

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        # Refusals are written to stderr; the checks care about the message
        # either way, so hand back both streams joined.
        return code, (out.getvalue() + err.getvalue()).strip()

    try:
        store = Store.open(board)
        keep = store.add(title="keep me", status="review", workspace_id="w1")
        live = store.add(title="still live", status="backlog")

        code, out = cli("archive", keep.id)
        check.check(
            "archive takes a card off the board",
            code == 0 and out == f"{keep.id} archived from review",
            out,
        )
        reloaded = Store.open(board)
        check.check(
            "the archived card is off the live board and in the archive",
            reloaded.by_id(keep.id) is None
            and reloaded.archived_by_id(keep.id) is not None,
            str([task.id for task in reloaded.tasks]),
        )
        archived = reloaded.archived_by_id(keep.id)
        check.check(
            "the archive remembers the column it came from",
            archived is not None
            and archived.archived_from == "review"
            and archived.archived_at > 0,
            archived.archived_from if archived else "-",
        )
        check.check(
            "the archive is written to the board file",
            json.loads(board.read_text(encoding="utf-8"))["archived"][0]["id"]
            == keep.id,
        )

        code, out = cli("show", keep.id)
        check.check(
            "show finds an archived card and says where it was",
            code == 0 and "archived" in out and "from Review" in out,
            out,
        )
        code, out = cli("list", "--archived")
        check.check(
            "list --archived lists it",
            keep.id in out and "Archived" in out and live.id not in out,
            out,
        )
        code, out = cli("list")
        check.check("the live list leaves it out", keep.id not in out, out)

        code, out = cli("unarchive", keep.id)
        check.check(
            "unarchive restores it to the column it left",
            code == 0 and out == f"{keep.id} restored to review",
            out,
        )
        back = Store.open(board).by_id(keep.id)
        check.check(
            "the restored card is live again, exactly once",
            back is not None
            and back.status == "review"
            and not back.archived_at
            and Store.open(board).archived_by_id(keep.id) is None,
            back.status if back else "-",
        )

        code, out = cli("archive", "K999")
        check.check("archiving a card that is not there fails", code == 1, out)
        code, out = cli("unarchive", live.id)
        check.check(
            "unarchiving a live card is a no-op",
            code == 0 and "not archived" in out,
            out,
        )
        cli("archive", keep.id)
        code, out = cli("archive", keep.id)
        check.check("archiving twice says so", "already archived" in out, out)

        # `delete` reaches a card in the archive: `d` is how a record is purged.
        doomed = Store.open(board).add(title="purge me", status="backlog")
        Store.open(board).archive(doomed.id)
        removed = Store.open(board).delete(doomed.id)
        check.check(
            "delete reaches a card in the archive",
            removed is not None and Store.open(board).archived_by_id(doomed.id) is None,
        )

        # Taking a card off the board is the human's call, like closing one.
        os.environ["HERDR_PANE_ID"] = "w1:pA"
        Store.open(board).add(title="an agent's card", status="doing", pane_id="w1:pA")
        code, out = cli("archive")
        check.check(
            "an agent cannot archive its own card without --force",
            code == 1 and "refusing" in out,
            out,
        )
        code, out = cli("archive", "--force")
        check.check("--force archives it", code == 0, out)
        os.environ.pop("HERDR_PANE_ID", None)

        # A board file that lost `seq` must carry on past an archived id too, or
        # the next card would reuse a number the archive still holds.
        stripped = Path(tmp) / "archive-noseq.json"
        stripped.write_text(
            json.dumps(
                {
                    "version": 1,
                    "tasks": [],
                    "archived": [{"id": "K7", "title": "archived", "archived_at": 1.0}],
                }
            ),
            encoding="utf-8",
        )
        bumped = Store.open(stripped).add(title="after")
        check.check(
            "an archived card's number is not reissued",
            task_seq(bumped.id) == 8,
            bumped.id,
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def check_ids(check: Checker, tmp: str) -> None:
    """Card ids: `<workspace-code>-<number>`, and every way back in.

    The code is the feature — a card's name says where it was filed, and `cfg-8`
    can be pasted into a shell and mean something — while the number behind it
    is the invariant that has to survive: it is issued per code, so `cfg-1` and
    `nixos-1` are two cards, each id still names exactly one, and a bare number
    is only a reference while it is unambiguous. Both halves are pinned here,
    along with what a badge does with a code too long for the card it sits on.
    """
    import contextlib
    import io

    from .cli import run_agent_command
    from .config import load_config
    from .model import LiveState, UiState, build_view
    from .render import render_card
    from .store import (
        Store,
        counter_key,
        id_code,
        looks_like_id,
        slug_code,
        task_seq,
        workspace_code,
    )

    labels = ("nixos-config-v2", "snowflake-reporting", "argo", "  Mixed  Case ")
    codes = [slug_code(label) for label in labels]
    check.check(
        "a workspace code is the label's own letters, so no config is needed",
        codes == ["nixos", "snowfl", "argo", "mixed"],
        str(codes),
    )
    useless = [slug_code(label) for label in ("!!!", "2026", "")]
    check.check(
        "a label that cannot make a letter-led code keeps the plain K id",
        useless == ["", "", ""],
        str(useless),
    )
    check.check(
        "an alias wins, keyed by the label or by herdr's own workspace id",
        workspace_code({"nixos-config-v2": "cfg"}, "nixos-config-v2", "w1") == "cfg"
        and workspace_code({"w1": "cfg"}, "renamed since then", "w1") == "cfg"
        and workspace_code({}, "snowflake-reporting", "w6") == "snowfl",
        str(
            (
                workspace_code({"nixos-config-v2": "cfg"}, "nixos-config-v2", "w1"),
                workspace_code({"w1": "cfg"}, "renamed since then", "w1"),
                workspace_code({}, "snowflake-reporting", "w6"),
            )
        ),
    )
    check.check(
        "an alias longer than a card badge keeps is still cut to something sane",
        workspace_code({"w1": "nixos-config-v2"}, "", "w1") == "nixos-config",
        workspace_code({"w1": "nixos-config-v2"}, "", "w1"),
    )
    check.check(
        "the number is the last number in an id, whatever the code says",
        (
            task_seq("cfg-8"),
            task_seq("K8"),
            task_seq("snowfl-123"),
            task_seq("blocked"),
        )
        == (8, 8, 123, 0),
        str([task_seq(i) for i in ("cfg-8", "K8", "snowfl-123", "blocked")]),
    )
    check.check(
        "and the code is what a number is counted in, `K` for a card with none",
        (
            id_code("cfg-8"),
            id_code("nixos-config-12"),
            id_code("K8"),
            id_code("k8"),
            id_code("blocked"),
            counter_key(""),
            counter_key("CFG"),
        )
        == ("cfg", "nixos-config", "K", "K", "", "K", "cfg"),
        str(
            [
                id_code(i)
                for i in ("cfg-8", "nixos-config-12", "K8", "k8", "blocked")
            ]
        ),
    )
    check.check(
        "only an id shape counts as a task reference, not any word with a digit",
        looks_like_id("cfg-8")
        and looks_like_id("K8")
        and looks_like_id("8")
        and not looks_like_id("v2")
        and not looks_like_id("blocked")
        and not looks_like_id("--notes"),
    )

    board = Path(tmp) / "ids-board.json"
    config_file = Path(tmp) / "ids-config.toml"
    config_file.write_text(
        # Keyed by herdr's workspace id here: the CLI has no label to key on when
        # herdr cannot answer, and this is the rename-proof spelling anyway.
        '[workspaces]\nw1 = "cfg"\nwA = "nixos-config-v2"\n',
        encoding="utf-8",
    )
    saved = {
        key: os.environ.get(key) for key in ("KANBAN_BOARD_FILE", "KANBAN_CONFIG_FILE")
    }
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    os.environ["KANBAN_CONFIG_FILE"] = str(config_file)

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        return code, (out.getvalue() + err.getvalue()).strip()

    try:
        code, out = cli("add", "Aliased card", "--workspace", "w1")
        filed = Store.open(board)
        check.check(
            "a card filed in a workspace takes that workspace's code",
            code == 0 and filed.tasks and filed.tasks[0].id == "cfg-1",
            f"{code} {out}",
        )
        cli("add", "No alias here", "--workspace", "w6")
        cli("add", "Long code", "--workspace", "wA")
        filed_ids = [task.id for task in Store.open(board).tasks]
        check.check(
            "each workspace code counts its own cards from one",
            filed_ids == ["cfg-1", "w6-1", "nixos-config-1"],
            str(filed_ids),
        )
        slipped = Store.open(Path(tmp) / "ids-loose.json").add(
            title="no explicit code", workspace_label="snowflake-reporting"
        )
        check.check(
            "a store caller with no config still codes by the label",
            slipped.id == "snowfl-1",
            slipped.id,
        )

        store = Store.open(board)
        found = [
            task.id if (task := store.resolve(reference)) else None
            for reference in ("cfg-1", "CFG-1", "w6-1")
        ]
        check.check(
            "a card answers to its id and to that id in either case",
            found == ["cfg-1", "cfg-1", "w6-1"],
            str(found),
        )
        check.check(
            "a bare number is refused while several codes have issued it",
            store.resolve("1") is None
            and store.ids_with_seq(1) == ["cfg-1", "nixos-config-1", "w6-1"],
            f"{store.resolve('1')} {store.ids_with_seq(1)}",
        )
        # A second card in one of those codes makes its next number its own.
        cli("add", "Only one", "--workspace", "w1")
        store = Store.open(board)
        check.check(
            "and a bare number resolves once only one card holds it",
            store.resolve("2") is not None and store.resolve("2").id == "cfg-2",
            str(store.resolve("2")),
        )
        check.check(
            "and a code that is not on the board is not a card",
            store.resolve("snow-1") is None,
        )
        code, out = cli("status", "cfg-1", "queued")
        check.check(
            "the CLI peels a coded id off its arguments",
            code == 0 and Store.open(board).by_id("cfg-1").status == "queued",
            f"{code} {out}",
        )
        code, out = cli("show", "1")
        check.check(
            "and the CLI names the ids an ambiguous number could have meant",
            code == 1
            and "matches cfg-1" in out
            and "nixos-config-1" in out
            and "no task" not in out,
            out,
        )
        # `--from` reads its number through `_find` like every other verb, so
        # it names the candidates too rather than reporting the card as missing
        # (nixos-91).
        code, out = cli("add", "Child of an ambiguous parent", "--from", "1")
        check.check(
            "and add --from resolves a bare number the same way",
            code == 1
            and "matches cfg-1" in out
            and "nixos-config-1" in out
            and "no task" not in out,
            out,
        )

        # A coded id is four cells longer than the `K8` it replaced, so the
        # badge has to give something up on a narrow card rather than clip the
        # rule's corner. The number is what stays: the meta row below already
        # names the workspace in full, and a badge is read rather than typed.
        view = build_view(
            load_config(config_file),
            Store.open(board).tasks,
            LiveState(),
            UiState(),
            width=200,
            height=24,
            icon_mode="unicode",
        )
        card = view.card("nixos-config-1")
        wide = str(render_card(card, 22, False, "unicode")[0])
        narrow = str(render_card(card, 13, False, "unicode")[0])
        check.check(
            "a card too narrow for its code keeps the number in the badge",
            "nixos-config-1" in wide
            and "nixos-config-1" not in narrow
            and " 1 " in narrow,
            f"{wide!r} | {narrow!r}",
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def check_agent_protocol(check: Checker, tmp: str) -> None:
    """The agent half: the prompt it is told about, and the commands it calls."""
    import contextlib
    import io
    import json
    import os
    import time
    from dataclasses import replace

    from .cli import CLI, run_agent_command
    from .config import load_config
    from .dispatch import build_prompt
    from .render import render_plain

    board = Path(tmp) / "protocol-board.json"
    keys = (
        "KANBAN_BOARD_FILE",
        "HERDR_PLUGIN_CONFIG_DIR",
        "HERDR_PANE_ID",
        "HERDR_ENV",
    )
    saved = {key: os.environ.get(key) for key in keys}
    for key in keys:
        os.environ.pop(key, None)
    os.environ["KANBAN_BOARD_FILE"] = str(board)

    # Filled in by the seed below: this check is about one card, and naming it
    # `nixos-1` here would pin the code's spelling in two places.
    card_id = ""

    def card(task_id: str = ""):
        return Store.open(board).by_id(task_id or card_id)

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        # `_find`'s "no card for this pane" goes to stderr, like every refusal;
        # the checks care about the message either way (the other checkers join
        # the two streams for the same reason).
        return code, (out.getvalue() + err.getvalue()).strip()

    try:
        config = load_config()
        seed = Store.open(board)
        task = seed.add(
            title="fix that thing",
            notes="the drift",
            workspace_id="w1",
            workspace_label="nixos-config-v2",
            agent_kind="pi",
            status="queued",
        )
        seed.hand_over(
            task.id,
            "doing",
            pane_id="w1:pTEST",
            tab_id="w1:t9",
            dispatched_at=time.time(),
        )
        card_id = task.id

        prompt = build_prompt(card(), config)
        check.check(
            "the dispatch prompt carries the protocol",
            task.id in prompt
            and "herdr-kanban status review" in prompt
            and "Only I close cards" in prompt,
        )
        check.check(
            "the protocol ends by requiring the card move",
            "Your turn is not over until the card is moved" in prompt
            and "`note` records progress" in prompt
            and "even if you offer to do more" in prompt,
        )
        # Review was slow because every wave-1 run reported differently (test
        # counts here, a hash there, nothing about commits). The handoff block
        # fixes the shape of the last note before the move so a card reads the
        # same whichever agent produced it.
        check.check(
            "the protocol pins the handoff note before the move",
            "the last `note` before you move the card is the handoff" in prompt
            and "files changed" in prompt
            and "tests run and counts" in prompt
            and "uncommitted" in prompt
            and "follow-up cards filed" in prompt
            and "anything only I must decide" in prompt,
        )
        # The prompt promises the id is never needed, and that promise holds
        # only for a card a dispatch linked to this pane. The block has to say
        # which, and how to get back, or an agent handed it another way has no
        # verb left that works (nixos-47).
        check.check(
            "the protocol ties the pane link to a dispatch and names the way back",
            "because the board finds the card" in prompt
            and "the pane its dispatch recorded" in prompt
            and "pass the id above" in prompt,
        )
        prompt_off = build_prompt(card(), replace(config, announce_protocol=False))
        check.check(
            "announce_protocol = false drops the protocol",
            "herdr-kanban" not in prompt_off
            and prompt_off.startswith("fix that thing"),
            repr(prompt_off[:40]),
        )

        os.environ["HERDR_ENV"] = "1"
        os.environ["HERDR_PANE_ID"] = "w1:pTEST"

        code, out = cli("status", "review")
        check.check(
            "status finds the card from the pane, with no id",
            code == 0 and card().status == "review",
            f"{code} {out}",
        )

        # A pane the board never dispatched into is the one case the protocol's
        # "no task id needed" cannot cover. It used to answer with a bare "no
        # card", which an agent cannot tell apart from "that card does not
        # exist" — so it guessed, or gave up and left the card claiming to be
        # in progress. The error has to name the situation and the way back.
        os.environ["HERDR_PANE_ID"] = "w9:pNONE"
        before = len(card().progress)
        code, out = cli("note", "from a pane with no dispatched card")
        check.check(
            "a pane with no dispatched card is told to pass the id",
            code == 1
            and "w9:pNONE" in out
            and "pass its id" in out
            and len(card().progress) == before,
            f"{code} {out}",
        )
        code, out = cli("list", "--mine")
        check.check(
            "list --mine from that pane offers the board instead of nothing",
            code == 0 and "no cards for this pane" in out and f"{CLI} list" in out,
            out,
        )
        os.environ["HERDR_PANE_ID"] = "w1:pTEST"
        code, out = cli("status", "done")
        check.check(
            "agents cannot close a card",
            code == 1 and card().status == "review" and "refusing" in out,
            f"{code} {out}",
        )
        code, _ = cli("status", "done", "--force")
        check.check("--force closes it", code == 0 and card().status == "done")
        code, _ = cli("status", "blocked", "need the production DSN")
        check.check(
            "status blocked parks the card and records why",
            code == 0
            and card().status == "blocked"
            and card().progress[-1]["text"] == "need the production DSN",
            str([entry["text"] for entry in card().progress]),
        )
        code, _ = cli("block", "waiting on a review")
        check.check(
            "block records an update",
            code == 0 and card().progress[-1]["text"] == "waiting on a review",
        )
        code, _ = cli("note", "the drift is in flake.lock:190")
        check.check(
            "note appends a progress line",
            code == 0 and card().progress[-1]["text"].startswith("the drift"),
        )
        code, _ = cli("status", "nowhere")
        check.check("an unknown column is refused", code == 2)

        # titles ---------------------------------------------------------
        # An agent that echoes the capture title must be told that nothing
        # changed — K6 sent back the title it was dispatched with, read
        # "title unchanged" as the step being done, and the card kept its
        # capture text for good.
        code, out = cli("title", "fix that thing")
        check.check(
            "echoing the capture title says it is still the capture title",
            code == 0 and "capture title" in out and card().title == "fix that thing",
            out[:90],
        )

        code, _ = cli("title", "Fix flake lock drift after the nixpkgs bump")
        renamed = card()
        check.check(
            "an agent may rename a card nobody has retitled",
            code == 0
            and renamed.title == "Fix flake lock drift after the nixpkgs bump"
            and renamed.title_source == "agent"
            and renamed.original_title == "fix that thing",
            f"{renamed.title!r} {renamed.title_source} {renamed.original_title!r}",
        )

        # A workspace-code id makes `eslint-9` a shape a title can have, and
        # `title` is the one verb whose argument is free text: a lone one is
        # the title, never a card to rename.
        code, _ = cli("title", "eslint-9")
        check.check(
            "a one-word id-shaped title is a title, not a card reference",
            code == 0 and card().title == "eslint-9",
            f"{code} {card().title!r}",
        )

        os.environ.pop("HERDR_PANE_ID", None)
        os.environ.pop("HERDR_ENV", None)
        code, _ = cli("title", card_id, "Fix flake lock drift")
        check.check(
            "a human rename claims the title",
            code == 0
            and card().title == "Fix flake lock drift"
            and card().title_edited
            and card().title_source == "user",
        )

        os.environ["HERDR_ENV"] = "1"
        os.environ["HERDR_PANE_ID"] = "w1:pTEST"
        code, out = cli("title", "Drift in the llm-agents input pin")
        kept = card()
        check.check(
            "an agent cannot overwrite a title the human owns",
            code == 0
            and kept.title == "Fix flake lock drift"
            and kept.progress[-1]["text"]
            == "suggested title: Drift in the llm-agents input pin",
            f"{kept.title!r} / {kept.progress[-1]['text']!r}",
        )

        # `agent_title_overrides`: that same rename, with the agent's title
        # allowed to win. The card is human-named, so there is a title to
        # replace, and what it replaces has to survive somewhere.
        saved_config = os.environ.get("KANBAN_CONFIG_FILE")
        os.environ["KANBAN_CONFIG_FILE"] = str(
            _pin_config(tmp, "pinned-overrides.toml", agent_title_overrides=True)
        )
        try:
            code, out = cli("title", "Drift in the llm-agents input pin")
            overridden = card()
            check.check(
                "agent_title_overrides lets an agent replace the human's title",
                code == 0
                and overridden.title == "Drift in the llm-agents input pin"
                and overridden.title_source == "agent"
                and any(
                    "was: Fix flake lock drift" in entry.get("what", "")
                    for entry in overridden.history
                ),
                f"{overridden.title!r} "
                f"{[e.get('what') for e in overridden.history][-1:]}",
            )
            check.check(
                "and the CLI names whose title it replaced",
                "replacing yours" in out,
                out[:90],
            )
        finally:
            if saved_config is None:
                os.environ.pop("KANBAN_CONFIG_FILE", None)
            else:
                os.environ["KANBAN_CONFIG_FILE"] = saved_config

        # Back to the default policy, so the rest of the checks read a card
        # whose title an agent may only suggest: the human names it again, and
        # the next agent title has to become an update.
        os.environ.pop("HERDR_PANE_ID", None)
        code, _ = cli("title", card_id, "Restic drift, check the lock file")
        check.check(
            "a human rename claims the title again",
            code == 0 and card().title_edited and card().title_source == "user",
            f"{code} {card().title!r} {card().title_source}",
        )
        os.environ["HERDR_PANE_ID"] = "w1:pTEST"
        code, out = cli("title", "Something the agent would rather call it")
        check.check(
            "with the option off an agent's title is a suggestion again",
            code == 0
            and card().title == "Restic drift, check the lock file"
            and card().progress[-1]["text"]
            == "suggested title: Something the agent would rather call it",
            f"{card().title!r} / {card().progress[-1]['text']!r}",
        )

        code, out = cli("list", "--json")
        payload = json.loads(out)
        check.check(
            "list --json exposes the card's state",
            code == 0
            and payload[0]["id"] == task.id
            and payload[0]["status_label"] == "Blocked"
            and "blocked" in payload[0]["agent_may_set"],
            out[:80],
        )
        code, out = cli("show")
        check.check(
            "show prints the card, its updates and its columns",
            code == 0 and "updates:" in out and "suggested title" in out,
        )

        # the board marks a card the agent named ---------------------------
        code, _ = cli("title", "Drift in the llm-agents input pin", "--force")
        check.check(
            "--force overrides the human's claim",
            code == 0 and card().title_source == "agent",
            f"{code} {card().title_source}",
        )

        # the CLI an agent checks before it trusts its prompt ---------------
        from .__main__ import main as board_main

        def run_main(*argv: str) -> tuple[int, str]:
            stream = io.StringIO()
            with contextlib.redirect_stdout(stream):
                code = board_main(list(argv))
            return code, stream.getvalue()

        code, out = run_main("--help")
        check.check(
            "--help answers with the task verbs, not just the board's flags",
            code == 0
            and "herdr-kanban title" in out
            and "herdr-kanban status" in out
            and "--snapshot" in out,
            out[:70],
        )

        # stdout is a pipe here, exactly as it is in an agent's bash tool: the
        # board must not be launched into it.
        code, out = run_main()
        check.check(
            "a bare invocation with no terminal prints usage instead of a TUI",
            code == 0 and "herdr-kanban status" in out,
            out[:70],
        )

        from .model import LiveState, UiState, build_view

        fresh = Store.open(board)
        board_view = build_view(
            config,
            fresh.tasks,
            LiveState(),
            UiState(selected_id=task.id),
            width=100,
            height=20,
            icon_mode="unicode",
        )
        lines = render_plain(board_view)
        check.check(
            "a card named by the agent carries the quill",
            "✎" in lines,
            lines.splitlines()[2] if len(lines.splitlines()) > 2 else "",
        )

        os.environ.pop("HERDR_PANE_ID", None)
        code, out = cli("list")
        check.check(
            "a shell with no task pane lists the whole board",
            code == 0 and task.id in out,
            out.splitlines()[0] if out else "",
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def check_add_notification(check: Checker, tmp: str) -> None:
    """A card an agent files is announced on the desktop; one from a shell is not.

    `herdr-kanban add` is the protocol's "found more work?" verb — the one path
    where a card appears on a board nobody is looking at — so the banner is
    raised by the CLI process itself. These checks run the CLI the way an agent
    does (`HERDR_PANE_ID` set) against a notifier and a herdr that log instead
    of popping a real banner or touching a real session.
    """
    import contextlib
    import io
    import os
    import time

    from .cli import run_agent_command
    from .store import Store

    board = Path(tmp) / "add-notify-board.json"
    log = Path(tmp) / "add-notify.txt"
    notifier = Path(tmp) / "add-notifier"
    notifier.write_text(
        f'#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "{log}"\n', encoding="utf-8"
    )
    notifier.chmod(0o755)
    herdr_log = Path(tmp) / "add-notify-herdr.txt"
    fake_herdr = Path(tmp) / "add-notify-herdr"
    fake_herdr.write_text(
        f'#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "{herdr_log}"\n'
        'echo \'{"id":"x","result":{}}\'\n',
        encoding="utf-8",
    )
    fake_herdr.chmod(0o755)

    keys = (
        "KANBAN_BOARD_FILE",
        "KANBAN_CONFIG_FILE",
        "KANBAN_NOTIFY_CMD",
        "HERDR_BIN_PATH",
        "HERDR_ENV",
        "HERDR_PANE_ID",
        "HERDR_WORKSPACE_ID",
    )
    saved = {key: os.environ.get(key) for key in keys}
    for key in keys:
        os.environ.pop(key, None)
    os.environ.update(
        {
            "KANBAN_BOARD_FILE": str(board),
            "KANBAN_NOTIFY_CMD": str(notifier),
            "HERDR_BIN_PATH": str(fake_herdr),
        }
    )

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        return code, out.getvalue().strip()

    def lines(path: Path) -> list[str]:
        if not path.exists():
            return []
        return [line for line in path.read_text(encoding="utf-8").splitlines() if line]

    def wait_for(count: int) -> list[str]:
        """The notifier is started detached, so give it a moment to land."""
        for _ in range(40):
            found = lines(log)
            if len(found) >= count:
                return found
            time.sleep(0.05)
        return lines(log)

    def silent() -> list[str]:
        """The same wait for the checks whose answer is *nothing* arrived."""
        time.sleep(0.5)
        return lines(log)

    def as_agent(pane: str) -> None:
        os.environ.update(
            {"HERDR_ENV": "1", "HERDR_PANE_ID": pane, "HERDR_WORKSPACE_ID": "w1"}
        )

    def silence(**behavior: str) -> None:
        """Point the CLI at a config with exactly these `[behavior]` keys."""
        path = Path(tmp) / "notify-config.toml"
        body = "".join(f"{key} = {value}\n" for key, value in behavior.items())
        path.write_text(f"[behavior]\n{body}", encoding="utf-8")
        os.environ["KANBAN_CONFIG_FILE"] = str(path)

    try:
        # A card in the pane, so the new one can be linked to the work that found
        # it — and that link is what the banner's second line should say.
        seed = Store.open(board)
        parent = seed.add(title="the thing being worked on", agent_kind="pi")
        seed.hand_over(
            parent.id,
            "doing",
            pane_id="w1:pAGENT",
            tab_id="w1:t1",
            dispatched_at=time.time(),
        )
        log.write_text("", encoding="utf-8")
        herdr_log.write_text("", encoding="utf-8")
        as_agent("w1:pAGENT")
        code, out = cli("add", "flake lock drifts on the llm-agents pin")
        store = Store.open(board)
        filed = store.find_by_title("flake lock drifts on the llm-agents pin")
        banners = wait_for(1)
        check.check(
            "a card an agent files is announced on the desktop",
            code == 0
            and filed is not None
            and any(f"{filed.id} filed" in line for line in banners),
            f"{code} {out[:60]} {banners}",
        )
        check.check(
            "the banner names the card the work was found on",
            filed is not None
            and any(f"found during {parent.id}" in line for line in banners),
            str(banners),
        )
        check.check(
            "no herdr toast goes with it — the board is about to show the card",
            not any("notification" in line for line in lines(herdr_log)),
            " | ".join(lines(herdr_log)),
        )

        os.environ.pop("HERDR_PANE_ID", None)
        os.environ.pop("HERDR_WORKSPACE_ID", None)
        cli("add", "a card I typed at a shell")
        check.check(
            "a card you file yourself raises nothing",
            silent() == banners,
            str(lines(log)),
        )

        as_agent("w1:pAGENT")
        code, _ = cli("add", "flake lock drifts on the llm-agents pin")
        check.check(
            "a refused duplicate is not announced",
            code == 1 and silent() == banners,
            f"{code} {lines(log)}",
        )

        silence(notify_on_add="false")
        log.write_text("", encoding="utf-8")
        cli("add", "silenced by its own key")
        check.check(
            "notify_on_add = false silences it",
            silent() == [],
            str(lines(log)),
        )

        silence(notify_on_add="true", notify_system="false")
        log.write_text("", encoding="utf-8")
        cli("add", "silenced by the delivery switch")
        check.check(
            "notify_system = false silences it too — a banner is its only delivery",
            silent() == [],
            str(lines(log)),
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def check_status_rights(check: Checker, tmp: str) -> None:
    """Agent status rights follow the board's columns, not literal ids.

    A board that renames its Done column to `closed` must still refuse to let an
    agent close a card, and the set the CLI advertises as `agent_may_set` must be
    the set the guard enforces. A column's `role` is what carries the meaning
    across a rename; the id candidate lists are the fallback.
    """
    import contextlib
    import io
    import json
    import os

    from .cli import run_agent_command
    from .dispatch import build_prompt

    config_file = Path(tmp) / "roles-config.toml"
    config_file.write_text(
        "[board]\n"
        "columns = [\n"
        '  { id = "icebox", label = "Icebox" },\n'
        '  { id = "later", label = "Later", role = "queued" },\n'
        '  { id = "started", label = "Started", role = "doing" },\n'
        '  { id = "waiting", label = "Waiting", role = "blocked" },\n'
        '  { id = "checking", label = "Checking", role = "review" },\n'
        '  { id = "closed", label = "Closed", role = "done" },\n'
        "]\n"
        'default_column = "icebox"\n'
        "[behavior]\nannounce_protocol = true\n",
        encoding="utf-8",
    )

    board = Path(tmp) / "roles-board.json"
    keys = ("KANBAN_BOARD_FILE", "KANBAN_CONFIG_FILE", "HERDR_PANE_ID", "HERDR_ENV")
    saved = {key: os.environ.get(key) for key in keys}
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    os.environ["KANBAN_CONFIG_FILE"] = str(config_file)
    os.environ.pop("HERDR_PANE_ID", None)
    os.environ.pop("HERDR_ENV", None)

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        return code, (out.getvalue() + err.getvalue()).strip()

    try:
        config = load_config()
        check.check(
            "roles name the board's Done, Blocked and Review columns",
            config.human_only_columns == ["closed"]
            and config.blocked_column == "waiting"
            and config.review_column == "checking"
            and config.send_column("icebox") == "started",
            f"{config.human_only_columns} {config.blocked_column} "
            f"{config.review_column} {config.send_column('icebox')}",
        )
        check.check(
            "agent_may_set is every column except the human-only one",
            config.agent_statuses
            == ["icebox", "later", "started", "waiting", "checking"],
            str(config.agent_statuses),
        )

        seed = Store.open(board)
        task = seed.add(title="role rights", status="started", workspace_id="w1")
        seed.hand_over(task.id, "started", pane_id="w1:pR", dispatched_at=time.time())

        def status() -> str:
            found = Store.open(board).by_id(task.id)
            return found.status if found else "-"

        os.environ["HERDR_ENV"] = "1"
        os.environ["HERDR_PANE_ID"] = "w1:pR"

        code, out = cli("status", "closed")
        check.check(
            "an agent cannot close a card when the Done id was renamed",
            code == 1 and status() == "started" and "refusing" in out,
            f"{code} {status()} {out}",
        )
        code, _ = cli("status", "closed", "--force")
        check.check(
            "and --force still closes it",
            code == 0 and status() == "closed",
            f"{code} {status()}",
        )

        Store.open(board).set_status(task.id, "started")
        code, _ = cli("status", "checking")
        check.check(
            "an agent may set the board's review column",
            code == 0 and status() == "checking",
            f"{code} {status()}",
        )

        Store.open(board).set_status(task.id, "started")
        code, _ = cli("block", "need the DSN")
        check.check(
            "block parks in the blocked-role column, not a literal `blocked`",
            code == 0 and status() == "waiting",
            f"{code} {status()}",
        )

        code, out = cli("show", "--json")
        payload = json.loads(out)
        check.check(
            "show --json advertises exactly the columns the guard allows",
            code == 0
            and payload["agent_may_set"] == config.agent_statuses
            and "closed" not in payload["agent_may_set"],
            str(payload["agent_may_set"]),
        )

        code, out = cli("add", "already closed", "--column", "closed")
        check.check(
            "an agent cannot file straight into the human-only column",
            code == 1 and "refusing" in out,
            f"{code} {out}",
        )
        code, _ = cli("add", "already closed", "--column", "closed", "--force")
        check.check("and --force files it there", code == 0, str(code))

        prompt = build_prompt(Store.open(board).by_id(task.id), config)
        check.check(
            "the protocol names the board's own review column",
            "herdr-kanban status checking" in prompt
            and "herdr-kanban status review" not in prompt,
            prompt.splitlines()[3] if len(prompt.splitlines()) > 3 else prompt[:80],
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def _pin_config(
    tmp: str,
    name: str = "pinned-config.toml",
    *,
    agent_title_overrides: bool = False,
    auto_archive_agent: bool = False,
    sort: str = "manual",
) -> Path:
    """Point every check at a config built from the defaults.

    The real board reads ~/.config/herdr/plugins/config/herdr-kanban/config.toml,
    and a self-test whose result changes when the user edits their columns is
    not a test.
    """
    from .config import DEFAULT_COLUMNS

    path = Path(tmp) / name
    columns = ", ".join(
        f'{{ id = "{column_id}", label = "{label}" }}'
        for column_id, label in DEFAULT_COLUMNS
    )
    path.write_text(
        f"[board]\ncolumns = [{columns}]\n"
        # Manual order, spelled out like the title policy below it: these checks
        # drive `J`/`K`, which is the one key the default sort hands back, and a
        # check whose answer depends on what the board's own config.toml (or the
        # built-in default) happens to say is not a check. The default sort gets
        # its own checks — `updated` in `check_store` and `check_list_order`,
        # the refusal below.
        f'sort = "{sort}"\n'
        "[behavior]\nannounce_protocol = true\nsync_seconds = 0.5\n"
        # Spelled out rather than left to the default, so this board's own
        # config.toml cannot decide what the checks exercise: the title policy
        # gets a check each way.
        f"agent_title_overrides = {'true' if agent_title_overrides else 'false'}\n"
        # The archive flag too: it decides whether a check's `archive` call also
        # reaches herdr, which must not depend on the machine's own config.toml.
        f"auto_archive_agent = {'true' if auto_archive_agent else 'false'}\n"
        # Pinned model lists, so a check that reads the picker's options does not
        # depend on what the machine's own config.toml happens to offer.
        '[models]\nclaude = ["sonnet", "opus"]\npi = ["deepseek-v4-flash"]\n',
        encoding="utf-8",
    )
    return path


def check_pane_args(check: Checker, tmp: str) -> None:
    """The pane-open flags come from the config module, not a shell re-reader.

    `launcher.sh` used to pull `placement`/`width`/`height` out of config.toml
    with awk, which matched the key in *any* section and could not strip an
    inline comment. The flags now come from `pane_open_args` over the same
    `load_config` the board uses, and this pins the shape the launcher reads
    back: one flag per line, quick capture's own popup geometry, the env marker,
    and nothing but a placement for an overlay.
    """
    from dataclasses import replace

    from .config import load_config, pane_open_args

    path = Path(tmp) / "pane-args-config.toml"
    path.write_text(
        "[board]\n"
        # Same key name in another section: the section-blind awk took this one.
        'placement = "split"\n'
        "[ui]\n"
        # Inline comment the awk kept as part of the value.
        'placement = "popup" # sized below\n'
        "width = 120\n"
        'height = "70%"\n'
        'quick_add_placement = "popup"\n'
        'quick_add_width = "55%"\n'
        'quick_add_height = "45%"\n',
        encoding="utf-8",
    )
    config = load_config(path)
    flags = pane_open_args(config)
    check.check(
        "pane flags read only [ui], ignoring a same-named key elsewhere",
        flags == ["--placement", "popup", "--width", "120", "--height", "70%"],
        f"{flags}",
    )
    quick = pane_open_args(config, quick_add=True)
    check.check(
        "quick capture gets its own popup geometry and the marker",
        quick
        == [
            "--placement",
            "popup",
            "--width",
            "55%",
            "--height",
            "45%",
            "--env",
            "KANBAN_QUICK_ADD=1",
        ],
        f"{quick}",
    )
    overlay = pane_open_args(replace(config, placement="overlay"))
    check.check(
        "an overlay board passes no size flags",
        overlay == ["--placement", "overlay"],
        f"{overlay}",
    )
    manifest_default = pane_open_args(replace(config, placement=""))
    check.check(
        "an empty placement leaves the manifest's choice alone",
        manifest_default == [],
        f"{manifest_default}",
    )


async def check_quick_capture(check: Checker, tmp: str) -> None:
    """Quick capture writes for real, and confirms itself in herdr's session.

    Runs the app against the *real* store (not demo data) with a fake herdr, so
    the shortcut's whole path is covered: the popup flag seeds the form, saving
    persists a card, and the confirmation is delivered as a herdr notification.
    """
    from dataclasses import replace

    from .app import KanbanApp
    from .config import load_config
    from .herdr import Herdr

    calls: list[list[str]] = []
    fake = Path(tmp) / "fake-herdr"
    fake.write_text(
        '#!/usr/bin/env bash\necho "$@" >> ' + str(Path(tmp) / "calls.txt") + "\n"
        'echo \'{"id":"x","result":{}}\'\n',
        encoding="utf-8",
    )
    fake.chmod(0o755)

    board = Path(tmp) / "capture-board.json"
    # Quick capture is seeded from the workspace the board was launched in, so
    # set that explicitly: the check must not depend on the ambient herdr
    # environment (it passes from a herdr pane and from a bare nix build alike).
    env_keys = (
        "KANBAN_BOARD_FILE",
        "HERDR_WORKSPACE_ID",
        "HERDR_PANE_ID",
        "HERDR_PLUGIN_CONTEXT_JSON",
        "HERDR_PLUGIN_CONFIG_DIR",
    )
    saved_env = {key: os.environ.get(key) for key in env_keys}
    for key in env_keys:
        os.environ.pop(key, None)
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    os.environ["HERDR_WORKSPACE_ID"] = "w1"

    async def drive() -> tuple[bool, str]:
        store = Store.open(board)
        app = KanbanApp(
            config=replace(load_config(), announce_protocol=True),
            store=store,
            herdr=Herdr(binary=str(fake)),
            quick_add=True,
        )
        async with app.run_test(size=(120, 36)) as pilot:
            await pilot.pause()
            opened = app.screen.__class__.__name__ == "TaskFormModal"
            await pilot.press(*"Capture this from the popup")
            await pilot.press("enter")
            await pilot.pause()
            # let the notification worker finish before the app goes away
            for _ in range(20):
                await pilot.pause(0.05)
                if app.workers_running() == []:
                    break
            return opened, app.screen.__class__.__name__

    try:
        opened, screen = await drive()
        check.check("quick capture opens straight into the add form", opened, screen)

        stored = Store.open(board)
        check.check(
            "quick capture persists a real card",
            len(stored.tasks) == 1
            and stored.tasks[0].title == "Capture this from the popup",
            str([task.title for task in stored.tasks]),
        )
        check.check(
            "a captured card is seeded from the launching workspace",
            bool(stored.tasks)
            and stored.tasks[0].workspace_id == "w1"
            and bool(stored.tasks[0].agent_kind),
            str((stored.tasks[0].workspace_id, stored.tasks[0].agent_kind))
            if stored.tasks
            else "",
        )

        calls_file = Path(tmp) / "calls.txt"
        lines = (
            calls_file.read_text(encoding="utf-8").splitlines()
            if calls_file.exists()
            else []
        )
        calls.extend(line.split() for line in lines)
        notification = next(
            (call for call in calls if call[:2] == ["notification", "show"]), None
        )
        check.check(
            "the capture confirms itself with a herdr notification",
            notification is not None
            and stored.tasks
            and stored.tasks[0].id in " ".join(notification),
            str(notification),
        )
    finally:
        for key, value in saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


async def check_multiline_notes(check: Checker, tmp: str) -> None:
    """Notes are free text, and a new line is a new line in the box that holds them.

    `TextArea` inserts a newline on `enter` only, and Textual asks the terminal
    for the kitty keyboard protocol — so on a terminal that speaks it (Ghostty
    does) `shift+enter` arrives as a key of its own, falls through to the
    screen, and does nothing. That reads as a notes field which cannot hold
    more than one line, which is what it was reported as. Driven through the
    real form and into the real store: the complaint was about typing into the
    box, not about a binding table.
    """
    from textual.widgets import Static

    from .app import KanbanApp
    from .config import load_config
    from .herdr import Herdr
    from .modals import MultilineArea

    board = Path(tmp) / "notes-board.json"
    saved = os.environ.get("KANBAN_BOARD_FILE")
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    try:
        app = KanbanApp(
            config=load_config(),
            store=Store.open(board),
            herdr=Herdr(binary="/nonexistent-herdr"),
        )
        async with app.run_test(size=(140, 44)) as pilot:
            await pilot.pause()
            await pilot.press("a")
            await pilot.pause()
            form = app.screen
            await pilot.press(*"three lines")
            notes = form.query_one("#field-notes", MultilineArea)
            notes.focus()
            await pilot.pause()
            await pilot.press(*"one")
            await pilot.press("enter")
            await pilot.press(*"two")
            await pilot.press("shift+enter")
            await pilot.press(*"three")
            typed = notes.text
            check.check(
                "shift+enter starts a new line in the notes box",
                typed == "one\ntwo\nthree",
                repr(typed),
            )
            await pilot.press("ctrl+s")
            await pilot.pause()

        card = next(
            (task for task in Store.open(board).tasks if task.title == "three lines"),
            None,
        )
        check.check(
            "and the form saves the lines as they were typed",
            card is not None and card.notes == "one\ntwo\nthree",
            repr(card.notes) if card is not None else "no such card",
        )

        # Notes are read back in one place, so a note that survives the store
        # and is flattened by the view has not survived at all.
        if card is None:
            check.check(
                "and the detail view shows them on their own lines",
                False,
                "the card was never saved",
            )
            return
        app = KanbanApp(
            config=load_config(),
            store=Store.open(board),
            herdr=Herdr(binary="/nonexistent-herdr"),
        )
        async with app.run_test(size=(140, 44)) as pilot:
            await pilot.pause()
            app.select_card(card.id)
            await pilot.press("enter")
            await pilot.pause()
            shown = str(app.screen.query_one("#detail-notes", Static).render())
            check.check(
                "and the detail view shows them on their own lines",
                shown == "one\ntwo\nthree",
                repr(shown),
            )
    finally:
        if saved is None:
            os.environ.pop("KANBAN_BOARD_FILE", None)
        else:
            os.environ["KANBAN_BOARD_FILE"] = saved


async def check_extras(check: Checker, tmp: str) -> None:
    """Steps, the board-file backup, `add`, agent args, and the card meta row."""
    import contextlib
    import io
    import json
    import os
    from dataclasses import replace

    from . import icons
    from .cli import run_agent_command
    from .config import load_config
    from .dispatch import plan_for
    from .herdr import Agent
    from .model import LiveState, UiState, build_view
    from .render import _staleness_style, card_meta_runs, render_card, render_plain

    board = Path(tmp) / "extras-board.json"
    saved = os.environ.get("KANBAN_BOARD_FILE")
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    config = load_config()

    def card(task_id: str = "K1"):
        return Store.open(board).by_id(task_id)

    def live_cards() -> list[dict]:
        return json.loads(board.read_text(encoding="utf-8"))["tasks"]

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        return code, (out.getvalue() + err.getvalue()).strip()

    for key in ("HERDR_PANE_ID", "HERDR_ENV"):
        os.environ.pop(key, None)

    try:
        # `add` -------------------------------------------------------------
        code, out = cli(
            "add", "Filed from a script", "--agent", "codex", "--column", "queued"
        )
        check.check(
            "add files a card and prints its id",
            code == 0 and out.startswith("K1"),
            out.splitlines()[0] if out else "",
        )
        added = card("K1")
        check.check(
            "add honours --agent and --column",
            added is not None
            and added.agent_kind == "codex"
            and added.status == "queued",
            f"{added.agent_kind if added else '-'} / {added.status if added else '-'}",
        )
        code, out = cli("add", "Json card", "--json")
        check.check(
            "add --json is machine readable",
            code == 0 and json.loads(out)["id"] == "K2",
            out[:60],
        )
        code, _ = cli("add", "no column", "--column", "nowhere")
        code2, _ = cli("add", "--agent")
        check.check("add refuses a bad column", code == 2)
        check.check("add refuses an empty title", code2 == 2)

        # one card per thing, and who filed it ------------------------------
        check.check(
            "a card written by hand is not attributed to an agent",
            added is not None and added.created_by == "user",
            added.created_by if added else "-",
        )
        code, out = cli("add", "  filed   from a SCRIPT ")
        check.check(
            "the same title twice is refused, naming the card that covers it",
            code == 1 and "K1 already covers this" in out and "--force" in out,
            f"{code} {out[:70]}",
        )
        check.check(
            "and nothing was filed",
            all(task.id != "K3" for task in Store.open(board).tasks),
            str([task.id for task in Store.open(board).tasks]),
        )
        code, out = cli("add", "Filed from a script", "--force")
        forced = card("K3")
        check.check(
            "--force files it anyway",
            code == 0 and forced is not None and forced.title == "Filed from a script",
            out.splitlines()[0] if out else "",
        )
        os.environ["HERDR_PANE_ID"] = "w1:pAGENT"
        try:
            code, _ = cli("add", "Filed by an agent")
        finally:
            os.environ.pop("HERDR_PANE_ID", None)
        by_agent = card("K4")
        check.check(
            "a card an agent files records that it did",
            code == 0
            and by_agent is not None
            and by_agent.created_by == "agent"
            and by_agent.history[-1]["what"] == "created in backlog by agent",
            str((by_agent.created_by, by_agent.history[-1]["what"]))
            if by_agent
            else "-",
        )
        shown = cli("show", "K4")[1]
        check.check(
            "and the CLI says so when it describes the card",
            "filed by an agent" in shown,
            shown.splitlines()[1] if len(shown.splitlines()) > 1 else "-",
        )
        check.check(
            "a title resolves case- and space-insensitively",
            Store.open(board).find_by_title("filed by   AN agent") is not None
            and Store.open(board).find_by_title("nothing like this") is None,
        )

        # provenance links, and the card's own record of itself -------------
        code, out = cli("add", "Found while reviewing", "--from", "K1")
        linked = card("K5")
        check.check(
            "--from links a new card to the card it came out of",
            code == 0
            and linked is not None
            and linked.parent_id == "K1"
            and "from K1" in out,
            out.splitlines()[-1] if out else "-",
        )
        code, out = cli("add", "From nowhere", "--from", "K99")
        check.check(
            "--from with an unknown card is refused",
            code == 1 and "no task" in out,
            f"{code} {out[:50]}",
        )
        # An agent's pane *is* a card, so the link needs no flag: the work was
        # found by the run that is working on it.
        Store.open(board).update("K1", pane_id="w1:pEXTRA")
        os.environ["HERDR_PANE_ID"] = "w1:pEXTRA"
        try:
            code, _ = cli("add", "Tripped over by the run")
        finally:
            os.environ.pop("HERDR_PANE_ID", None)
        implicit = card("K6")
        check.check(
            "a card an agent files from its own pane links itself back",
            code == 0 and implicit is not None and implicit.parent_id == "K1",
            implicit.parent_id if implicit else "-",
        )
        payload = json.loads(cli("show", "K5", "--json")[1])
        check.check(
            "show --json carries history, provenance and the link",
            payload["parent_id"] == "K1"
            and payload["created_by"] in ("user", "agent")
            and any("created in" in entry["what"] for entry in payload["history"]),
            str(sorted(payload)[:4]),
        )
        shown = cli("show", "K5")[1]
        check.check(
            "show prints the card's history, not just its updates",
            "history:" in shown and "created in" in shown,
            shown.splitlines()[-1] if shown else "-",
        )

        # the model a card asks for -----------------------------------------
        code, out = cli("add", "Card on a model", "--model", "sonnet")
        modelled = card("K7")
        payload = json.loads(cli("show", "K7", "--json")[1])
        check.check(
            "add --model puts the model on the card",
            code == 0
            and modelled is not None
            and modelled.agent_model == "sonnet"
            and payload["agent_model"] == "sonnet",
            str(modelled.agent_model) if modelled else "-",
        )
        check.check(
            "and the CLI says which model the card asks for",
            "model sonnet" in cli("show", "K7")[1],
            cli("show", "K7")[1].splitlines()[1] if cli("show", "K7")[1] else "-",
        )

        # --notes is free text -----------------------------------------------
        # The one free-text value in this CLI that used to take a single
        # argument: an unquoted note was cut to its first word, with the rest
        # pushed into the title. `note`/`title`/`block` had always joined the
        # remaining tokens, so this is the same rule, not a new one.
        code, out = cli(
            "add", "Note without quotes", "--notes", "why", "it", "is", "separate"
        )
        noted = card("K8")
        check.check(
            "add --notes takes the rest of the line, not just its first word",
            code == 0 and noted is not None and noted.notes == "why it is separate",
            f"{noted.title!r} / {noted.notes!r}" if noted else "-",
        )
        check.check(
            "and the note is not absorbed into the title",
            noted is not None and noted.title == "Note without quotes",
            noted.title if noted else "-",
        )
        code, _ = cli(
            "add",
            "Note before a flag",
            "--notes",
            "quoted or not",
            "--priority",
            "high",
        )
        flagged = card("K9")
        check.check(
            "a flag after an unquoted note is still a flag",
            code == 0
            and flagged is not None
            and flagged.notes == "quoted or not"
            and flagged.priority == "high",
            f"{flagged.notes!r} {flagged.priority}" if flagged else "-",
        )

        # steps -------------------------------------------------------------
        code, out = cli("step", "K1", "add", "first")
        cli("step", "K1", "add", "second")
        check.check(
            "step add builds a checklist",
            code == 0 and len(card("K1").steps) == 2 and "1. [ ] first" in out,
            str([step["text"] for step in card("K1").steps]),
        )
        code, _ = cli("step", "K1", "done", "2")
        check.check(
            "step done ticks and records who",
            code == 0
            and card("K1").steps_done == 1
            and card("K1").steps[1]["by"] == "user",
            f"{card('K1').steps_done} {card('K1').steps[1]['by']}",
        )
        code, _ = cli("step", "K1", "done", "9")
        code2, _ = cli("step", "K2", "done", "1")
        check.check("an out-of-range step exits non-zero", code == 1)
        check.check("a card with no steps exits non-zero", code2 == 1)
        code, _ = cli("step", "K1", "undo", "2")
        check.check("step undo unticks", code == 0 and card("K1").steps_done == 0)
        code, _ = cli("step", "K1", "rm", "1")
        check.check(
            "step rm removes and renumbers",
            code == 0 and [step["text"] for step in card("K1").steps] == ["second"],
            str([step["text"] for step in card("K1").steps]),
        )
        code, _ = cli("step", "K1", "bogus")
        check.check("an unknown step action exits 2", code == 2)

        # the board-file backup ---------------------------------------------
        backup = Store(board).backup_path
        check.check(
            "the previous generation is kept alongside the board",
            backup.exists(),
            str(backup),
        )
        previous = json.loads(backup.read_text(encoding="utf-8"))
        check.check(
            "the backup lags the live file by one write",
            len(previous["tasks"]) == len(live_cards()),
            f"{len(previous['tasks'])} vs {len(live_cards())}",
        )

        # agent args --------------------------------------------------------
        args_config = replace(config, agent_args={"claude": ["--permission-mode=auto"]})
        live = LiveState()
        plan = plan_for(card("K1"), args_config, live)
        check.check(
            "a kind without configured flags gets none",
            plan.args == (),
            f"{plan.kind} {plan.args}",
        )
        claude_task = Store(board).add(
            title="claude card", agent_kind="claude", workspace_id="w1"
        )
        plan = plan_for(Store.open(board).by_id(claude_task.id), args_config, live)
        check.check(
            "per-kind args reach the plan",
            plan.args == ("--permission-mode=auto",),
            str(plan.args),
        )

        # the card meta row --------------------------------------------------
        meta_wide = "".join(
            text for text, _ in card_meta_runs(_meta_card(2, 2, 8), 30, "unicode")
        )
        meta_narrow = "".join(
            text for text, _ in card_meta_runs(_meta_card(2, 2, 8), 10, "unicode")
        )
        meta_fresh = "".join(
            text for text, _ in card_meta_runs(_meta_card(0, 0, 0), 30, "unicode")
        )
        check.check(
            "a wide card shows step progress and age",
            "2/2" in meta_wide and "8d" in meta_wide,
            meta_wide,
        )
        check.check(
            "a narrow card drops the counter before the agent glyphs",
            "2/2" not in meta_narrow
            and "π" in meta_narrow
            and len(meta_narrow.strip("▪ ").split()[0]) >= 3,
            meta_narrow,
        )
        check.check(
            "a fresh card is not labelled 0s", "0s" not in meta_fresh, meta_fresh
        )
        check.check(
            "ages tint at the stale threshold, then go red",
            _staleness_style(10 * 86400, 3) == icons.PALETTE["red"]
            and _staleness_style(4 * 86400, 3) == icons.PALETTE["yellow"]
            and _staleness_style(600, 3) == icons.PALETTE["overlay0"],
        )

        # the agent's kind, and what it costs when the column is narrow ------
        def meta(inner: int, **kwargs: object) -> str:
            return "".join(
                text
                for text, _ in card_meta_runs(
                    _meta_card(2, 2, 8),
                    inner,
                    "unicode",
                    **kwargs,  # type: ignore[arg-type]
                )
            )

        check.check(
            "the agent's kind is spelled out beside its mark",
            "π pi" in meta(30),
            meta(30),
        )
        check.check(
            "the step counter outlives the age",
            "2/2" in meta(16) and "8d" not in meta(16),
            meta(16),
        )
        check.check(
            "the kind drops before the mark, and the mark last of all",
            "π" in meta(10) and "pi" not in meta(10) and "2/2" not in meta(10),
            meta(10),
        )
        check.check(
            "ui.show_agent_kind=false leaves the mark alone",
            "π" in meta(30, show_agent_kind=False)
            and "pi" not in meta(30, show_agent_kind=False),
            meta(30, show_agent_kind=False),
        )

        # the live state rides the bottom rule, not the meta row ------------
        def rule(width: int, **kwargs: object) -> str:
            return render_card(
                _meta_card(2, 2, 8),
                width,
                False,
                "unicode",
                **kwargs,  # type: ignore[arg-type]
            )[-1].plain

        check.check(
            "the bottom rule spells out the live state",
            "◐ working" in rule(20) and len(rule(20)) == 20,
            rule(20),
        )
        check.check(
            "a narrow card keeps the state mark and drops the word",
            rule(10) == "╰── ◐ ───╯",
            rule(10),
        )
        check.check(
            "ui.show_status_word=false drops the word everywhere",
            "◐" in rule(20, show_status_word=False)
            and "working" not in rule(20, show_status_word=False),
            rule(20, show_status_word=False),
        )
        check.check(
            "a card with no agent keeps a plain rule",
            "◐"
            not in render_card(
                replace(_meta_card(2, 2, 8), status=""), 20, False, "unicode"
            )[-1].plain,
        )
        check.check(
            "a card too narrow for even the mark still closes its box",
            rule(4) == "╰──╯",
            rule(4),
        )

        # the two icon registers --------------------------------------------
        check.check(
            "brand mode uses the font's own lifecycle marks",
            icons.status_glyph("blocked", 0, "brand") == "\ue1c1"
            and icons.status_glyph("done", 0, "brand") == "\ue1c0"
            and icons.status_glyph("idle", 0, "brand") == "\ue1c2"
            and icons.status_glyph("unknown", 0, "brand") == "\ue1c3"
            and icons.status_glyph("working", 0, "brand") == "\ue1c2"
            and icons.status_glyph("exited", 0, "brand") == "∅",
            f"{icons.status_glyph('blocked', 0, 'brand')!r} "
            f"{icons.status_glyph('exited', 0, 'brand')!r}",
        )
        check.check(
            "unicode mode keeps the plain marks",
            icons.status_glyph("blocked", 0, "unicode") == "▲"
            and icons.status_glyph("done", 0, "unicode") == "✓",
        )
        check.check(
            "the spinner outranks either register while working",
            icons.status_glyph("working", 1, "brand") in icons.SPINNER_FRAMES,
        )

        # the workspace dot's colour ----------------------------------------
        tinted = card_meta_runs(
            replace(_meta_card(0, 0, 0), status="", workspace_number=3),
            30,
            "unicode",
        )[0]
        check.check(
            "the workspace dot carries its workspace's colour",
            tinted == ("▪", icons.workspace_accent(3))
            and icons.workspace_accent(1) != icons.workspace_accent(2)
            and icons.workspace_accent(0) == icons.PALETTE["overlay2"],
            str(tinted),
        )

        # naming an agent the board did not dispatch -------------------------
        guessed = LiveState()
        guessed.agents_by_pane["p1"] = Agent(
            name="",
            status="idle",
            workspace_id="w1",
            pane_id="p1",
            tab_id="t1",
            cwd="",
            focused=False,
            title="claude",
            logo="\ue1a0",
        )
        by_pane = Task(
            id="K9", title="no kind recorded", workspace_id="w1", pane_id="p1"
        )
        by_title = Task(id="K8", title="tidy the claude config", workspace_id="w1")
        named_pi = Task(id="K6", title="bump the pi pins", workspace_id="w1")
        recorded = Task(
            id="K7", title="anything", workspace_id="w1", agent_kind="codex"
        )
        check.check(
            "the live agent's own mark names a card the board never dispatched",
            guessed.kind_hint(by_pane) == "claude",
            guessed.kind_hint(by_pane),
        )
        check.check(
            "the task's own record wins over any guess",
            guessed.kind_hint(recorded) == "codex",
            guessed.kind_hint(recorded),
        )
        check.check(
            "a title that names its agent is the last resort",
            guessed.kind_hint(by_title) == "claude",
            guessed.kind_hint(by_title),
        )
        # pi is matched by its glyph and not by its name, because "pi" is inside
        # "pins", "topic" and a dozen other words a title might use by accident.
        check.check(
            "a bare 'pi' in a title is not a kind hint",
            guessed.kind_hint(named_pi) == "",
            guessed.kind_hint(named_pi),
        )

        # and a full board still renders to shape
        fresh = Store.open(board)
        board_view = build_view(
            config,
            fresh.tasks,
            LiveState(),
            UiState(selected_id=fresh.tasks[0].id if fresh.tasks else ""),
            width=120,
            height=20,
            icon_mode="unicode",
        )
        rendered = render_plain(board_view)
        # split("\n"), not splitlines(): a trailing blank row is part of the
        # board (the renderer pads to the pane height).
        check.check(
            "the board renders exactly as tall as the pane",
            len(rendered.split("\n")) == 20 and fresh.tasks[0].id in rendered,
            str(len(rendered.split("\n"))),
        )
    finally:
        if saved is None:
            os.environ.pop("KANBAN_BOARD_FILE", None)
        else:
            os.environ["KANBAN_BOARD_FILE"] = saved


def _meta_card(steps_done: int, steps_total: int, age_days: float):
    """A throwaway CardView for exercising the card meta row."""
    from .model import CardView

    task = Task(
        id="K9",
        title="meta probe",
        workspace_id="w1",
        workspace_label="nixos-config-v2",
        agent_kind="pi",
        updated_at=time.time() - age_days * 86400,
        steps=[{"text": f"s{n}", "done": n < steps_done} for n in range(steps_total)],
    )
    return CardView(task=task, status="working")


def check_hardening(check: Checker, tmp: str) -> None:
    """The edges: poisoned board files, no-op writes, cell widths, parsing."""
    import json
    import os
    import time
    from dataclasses import replace

    from rich.cells import cell_len
    from rich.text import Text

    from . import herdr as herdr_module
    from . import icons
    from .config import Column, load_config
    from .demo import demo_tasks
    from .model import (
        CardView,
        LiveState,
        UiState,
        build_view,
        query_terms,
        task_matches,
    )
    from .render import chop, render_card, render_plain, spread
    from .store import Store

    board = Path(tmp) / "hardening-board.json"
    saved = os.environ.get("KANBAN_BOARD_FILE")
    os.environ["KANBAN_BOARD_FILE"] = str(board)

    try:
        # #2 no-op mutations must not touch the file ------------------------
        store = Store.open(board)
        task = store.add(title="x", status="queued", workspace_id="w1", agent_kind="pi")
        store.set_status(task.id, "doing")  # a real write, so a .bak exists
        bak_before = store.backup_path.read_text(encoding="utf-8")

        # ids are never reissued, even from a board file that lost its counter
        strangled = Path(tmp) / "no-seq-board.json"
        strangled.write_text(
            json.dumps({"version": 1, "tasks": [{"id": "K7", "title": "x"}]}),
            encoding="utf-8",
        )
        rescued = Store.open(strangled)
        check.check(
            "a board file without `seq` continues past its highest id",
            rescued.add(title="next").id == "K8",
            rescued.board.tasks[-1].id,
        )

        no_ops = {
            "set_status to the same column": lambda: store.set_status(task.id, "doing"),
            "update with no effective diff": lambda: store.update(task.id, title="x"),
            "set_title unchanged": lambda: store.set_title(task.id, "x"),
            "empty progress note": lambda: store.add_progress(task.id, "   "),
            "reorder out of range": lambda: store.reorder(task.id, 99),
            "step index out of range": lambda: store.set_step(task.id, 9, done=True),
        }
        wrote = []
        for label, call in no_ops.items():
            before = board.stat().st_mtime_ns
            time.sleep(0.01)
            call()
            if board.stat().st_mtime_ns != before:
                wrote.append(label)
        check.check(
            "no-op mutations do not rewrite the board",
            not wrote,
            ", ".join(wrote),
        )
        check.check(
            "and so they do not rotate the rollback copy",
            store.backup_path.read_text(encoding="utf-8") == bak_before,
        )
        before = board.stat().st_mtime_ns
        time.sleep(0.01)
        store.set_status(task.id, "review")
        check.check(
            "a real change still writes",
            board.stat().st_mtime_ns != before
            and store.by_id(task.id).status == "review",
        )

        # #3 a hand-edited board file must not take the board down ----------
        raw = json.loads(board.read_text(encoding="utf-8"))
        raw["tasks"][0].update(
            created_at=None,
            updated_at="yesterday",
            dispatched_at="soon",
            agent_model=7,
            created_by="someone",
        )
        raw["tasks"][0]["progress"] = [
            {"at": "ages ago", "text": "did it", "by": "agent"}
        ]
        raw["tasks"][0]["steps"] = [{"text": "s", "done": True, "at": "yesterday"}]
        board.write_text(json.dumps(raw), encoding="utf-8")
        try:
            poisoned = Store.open(board).by_id(task.id)
            loaded_ok = True
        except Exception as exc:  # pragma: no cover - the failure this guards
            poisoned, loaded_ok = None, f"{type(exc).__name__}: {exc}"
        check.check(
            "a board file with hand-edited timestamps still loads",
            loaded_ok is True,
            str(loaded_ok),
        )
        check.check(
            "nonsense timestamps become safe sentinels",
            poisoned is not None
            and poisoned.updated_at == 0.0
            and poisoned.created_at == 0.0
            and poisoned.dispatched_at is None
            and poisoned.progress[0]["at"] == 0.0
            and poisoned.steps[0]["at"] == 0.0,
            str(poisoned.updated_at) if poisoned else "",
        )
        check.check(
            "and a hand-edited model or origin is coerced, not trusted",
            poisoned is not None
            and poisoned.agent_model == ""
            and poisoned.created_by == "user",
            f"{poisoned.agent_model!r} {poisoned.created_by!r}" if poisoned else "-",
        )
        raw["tasks"][0]["updated_at"] = "1789000000.5"
        board.write_text(json.dumps(raw), encoding="utf-8")
        check.check(
            "a numeric string is still honoured",
            Store.open(board).by_id(task.id).updated_at == 1789000000.5,
        )
        fresh = Store.open(board)
        rendered = render_plain(
            build_view(
                load_config(),
                fresh.tasks,
                LiveState(),
                UiState(selected_id=task.id),
                width=100,
                height=20,
                icon_mode="unicode",
            )
        )
        check.check("and the board renders anyway", task.id in rendered)

        # #4/#8 cell widths -------------------------------------------------
        violations = [
            (text, width)
            for text in ("plain", "修正 flake 锁 🚀", "🇺🇸 flag", "👍🏽 ok", "a" * 40)
            for width in range(1, 20)
            if cell_len(chop(text, width)) > width
        ]
        check.check(
            "chop never exceeds its cell budget", not violations, str(violations[:3])
        )
        overflow = []
        for title in (
            "fix the flake lock",
            "修正 flake 锁 🚀 drift",
            "🚀🚀 emoji",
            "🇺🇸 flag day",
        ):
            for width in (14, 22, 34):
                card = CardView(
                    task=Task(
                        id="K1",
                        title=title,
                        workspace_label="日本プロジェクト",
                        agent_kind="pi",
                        updated_at=time.time(),
                    ),
                    status="working",
                )
                cells = {
                    cell_len(line.plain)
                    for line in render_card(card, width, False, "unicode")
                }
                if cells != {width}:
                    overflow.append((title, width, sorted(cells)))
        check.check(
            "cards with wide glyphs still fit their box exactly",
            not overflow,
            str(overflow[:3]),
        )

        # the mark tables themselves ----------------------------------------
        # Spelled out rather than derived, because the point of the check is the
        # opposite of the code: these are herdr-radar's tables
        # (lib/logos.js, tools/codepoints.toml), and a card whose mark disagrees
        # with the sidebar beside it makes you learn the same agent twice.
        radar_brand = {
            "claude": 0xE1A0,
            "codex": 0xE1A1,
            "opencode": 0xE1A2,
            "omp": 0xE1A3,
            "cline": 0xE1A4,
            "mastracode": 0xE1A5,
            "kimi": 0xE1A6,
            "kilo": 0xE1A7,
            "maki": 0xE1A8,
            "pi": 0xE1A9,
            "hermes": 0xE1AA,
            "cursor": 0xE1AB,
            "copilot": 0xE1AC,
            "deepseek": 0xE1AD,
            "gemini": 0xE1AE,
            "gpt": 0xE1AF,
            "qwen": 0xE1B0,
            "grok": 0xE1B1,
            "agy": 0xE1B2,
            "kiro": 0xE1B3,
            "amp": 0xE1B4,
            "devin": 0xE1B5,
            "qodercli": 0xE1B6,
            "glm": 0xE1B7,
        }
        radar_text = {
            "claude": "§",
            "codex": "Λ",
            "opencode": "◇",
            "omp": "Π",
            "cline": "∇",
            "mastracode": "∑",
            "kimi": "✨",
            "kilo": "♟",
            "maki": "✳",
            "pi": "π",
            "hermes": "☪",
            "cursor": "◆",
            "copilot": "⊙",
            "deepseek": "≋",
            "gemini": "✦",
            "gpt": "✺",
            "qwen": "Ϙ",
            "grok": "✖",
            "agy": "△",
            "kiro": "Ω",
            "amp": "Ʌ",
            "devin": "ꓓ",
            "qodercli": "Ǫ",
            "glm": "Ƶ",
        }
        drift = sorted(
            kind
            for kind, point in radar_brand.items()
            if icons.BRAND_GLYPHS.get(kind) != chr(point)
        ) + sorted(
            kind
            for kind, mark in radar_text.items()
            if icons.UNICODE_GLYPHS.get(kind) != mark
        )
        check.check(
            "both mark tables still match herdr-radar's",
            not drift,
            str(drift),
        )
        # A mark a terminal cannot size is worse than a plain one: every mark
        # the board draws by default must be one cell, and every kind herdr
        # starts must have both a brand and a text mark.
        over = sorted(
            kind for kind, mark in icons.UNICODE_GLYPHS.items() if cell_len(mark) != 1
        )
        missing = sorted(
            kind for kind, _ in icons.AGENT_KINDS if kind not in icons.UNICODE_GLYPHS
        )
        check.check(
            "every kind herdr starts has a text mark, and all but kimi's are one cell",
            over == ["kimi"] and not missing,
            f"wide={over} missing={missing}",
        )
        squashed = spread(Text("▎Backlog"), Text("9/9"), 14)
        check.check(
            "a narrow header keeps its label and its count",
            "Backlog" in squashed.plain and "9/9" in squashed.plain,
            squashed.plain,
        )

        # the id badge, and what off-screen cards look like ------------------
        from .render import ColumnView, id_badge_style, render_column_header
        from .store import Task as SelfTestTask

        def badge(status: str, age_days: float = 0.0, **kwargs: object) -> str:
            task = SelfTestTask(
                id="K9",
                title="badge probe",
                updated_at=time.time() - age_days * 86400,
            )
            card = CardView(task=task, status=status)
            options = {"selected": False, "show_age": True, "stale_after_days": 3.0}
            options.update(kwargs)
            return id_badge_style(card, **options)  # type: ignore[arg-type]

        check.check(
            "a running agent tints the id badge, so a column reads at a glance",
            badge("working") == f"bold {icons.status_color('working')}"
            and badge("idle") != "bold"
            and badge("exited") != "bold",
            f"{badge('working')} / {badge('idle')}",
        )
        check.check(
            "blocked and done leave the badge alone (the border already says it)",
            badge("blocked") == "bold" and badge("done") == "bold",
        )
        check.check(
            "staleness keeps a home when the age is hidden",
            badge("", age_days=30, show_age=False) == f"bold {icons.PALETTE['red']}"
            and badge("", age_days=4, show_age=False)
            == f"bold {icons.PALETTE['yellow']}"
            and badge("", age_days=30, show_age=True) == "bold"
            and badge("", age_days=0.1, show_age=False) == "bold",
            f"{badge('', age_days=30, show_age=False)} / {badge('', age_days=30)}",
        )

        def heading(count: int, scroll: int, visible: int = 3) -> str:
            column = ColumnView(
                column=Column("backlog", "Backlog"),
                cards=[CardView(task=SelfTestTask(id=f"K{i}")) for i in range(count)],
                scroll=scroll,
            )
            return render_column_header(column, 18, 0, False, visible).plain

        check.check(
            "a column with cards off screen says which way they are",
            "▾" in heading(9, 0) and "▴" not in heading(9, 0),
            heading(9, 0),
        )
        check.check(
            "scrolled into the middle, both arrows are there",
            "▴" in heading(9, 4) and "▾" in heading(9, 4),
            heading(9, 4),
        )
        check.check(
            "a column that fits has no arrows at all",
            "▴" not in heading(2, 0) and "▾" not in heading(2, 0),
            heading(2, 0),
        )

        # the models a card can ask for --------------------------------------
        from .dispatch import agent_args
        from .modals import model_options

        with_models = replace(
            load_config(),
            agent_args={
                "pi": ["--model", "deepseek-v4-flash", "--verbose"],
                "claude": ["--permission-mode=auto"],
                "codex": ["--model=gpt-5-codex"],
            },
        )
        check.check(
            "no model on the card leaves the kind's own flags alone",
            agent_args(with_models, "pi", "")
            == (
                "--model",
                "deepseek-v4-flash",
                "--verbose",
            ),
            str(agent_args(with_models, "pi", "")),
        )
        check.check(
            "a model on the card replaces the kind's --model, and keeps the rest",
            agent_args(with_models, "pi", "glm-5.3-flash")
            == ("--verbose", "--model", "glm-5.3-flash")
            and agent_args(with_models, "codex", "gpt-5") == ("--model", "gpt-5"),
            f"{agent_args(with_models, 'pi', 'glm-5.3-flash')} "
            f"{agent_args(with_models, 'codex', 'gpt-5')}",
        )
        check.check(
            "a kind with no --model of its own just gains one",
            agent_args(with_models, "claude", "opus")
            == ("--permission-mode=auto", "--model", "opus")
            and agent_args(with_models, "gemini", "x") == ("--model", "x"),
            str(agent_args(with_models, "claude", "opus")),
        )
        check.check(
            "the picker always offers default first, then the kind's names",
            model_options(with_models, "claude")[0] == ("·  default", "")
            and [value for _, value in model_options(with_models, "claude")]
            == ["", "sonnet", "opus"]
            and model_options(with_models, "gemini") == [("·  default", "")],
            str(model_options(with_models, "claude")),
        )
        check.check(
            "a model that is no longer in [models] is offered, not dropped",
            [value for _, value in model_options(with_models, "claude", "haiku")]
            == ["", "sonnet", "opus", "haiku"],
            str(model_options(with_models, "claude", "haiku")),
        )
        check.check(
            "[models] is read from the config file, per kind",
            load_config().models_for("claude") == ["sonnet", "opus"]
            and load_config().models_for("pi") == ["deepseek-v4-flash"]
            and load_config().models_for("gemini") == [],
            str(load_config().models),
        )

        # the `!` view ------------------------------------------------------
        from .model import UiState as SelfTestUiState
        from .model import visible_tasks

        live_state = LiveState()
        blocker = SelfTestTask(id="K1", title="blocked one", status="doing")
        quiet = SelfTestTask(id="K2", title="quiet one", status="doing")
        agent = herdr_module.Agent(
            name="k1",
            status="blocked",
            workspace_id="w1",
            pane_id="w1:p1",
            tab_id="w1:t1",
            cwd="",
            focused=False,
            title="",
            logo="",
        )
        live_state.agents_by_pane["w1:p1"] = agent
        blocker.pane_id = "w1:p1"
        shown, hidden, _ = visible_tasks(
            load_config(),
            [blocker, quiet],
            live_state,
            SelfTestUiState(only_blocked=True),
        )
        check.check(
            "the needs-you view keeps only the cards whose agents are blocked",
            [task.id for task in shown] == ["K1"] and hidden == 1,
            f"{[task.id for task in shown]} hidden={hidden}",
        )
        shown, hidden, _ = visible_tasks(
            load_config(), [blocker, quiet], live_state, SelfTestUiState()
        )
        check.check(
            "and it is a filter, not a mode: off means everything",
            len(shown) == 2 and hidden == 0,
            f"{len(shown)} shown",
        )

        # #9 hygiene --------------------------------------------------------
        bool_config = Path(tmp) / "bool-config.toml"
        bool_config.write_text(
            "[ui]\nwidth = true\nheight = false\nshow_agent_kind = true\n"
            "show_status_word = false\n"
            '[board]\nsort = "manual"\n'
            "[behavior]\nnotify_on_block = false\nnotify_system = false\n"
            "auto_delete_agent = false\nauto_archive_agent = true\n",
            encoding="utf-8",
        )
        # A sort value nothing recognises: it has to keep the default rather
        # than be honoured, because a typo silently read as a mode would leave
        # the columns in an order the key that edits them cannot explain.
        bogus_config = Path(tmp) / "bogus-sort.toml"
        bogus_config.write_text('[board]\nsort = "newest"\n', encoding="utf-8")
        saved_config = os.environ.get("KANBAN_CONFIG_FILE")
        os.environ["KANBAN_CONFIG_FILE"] = str(bool_config)
        try:
            loaded = load_config()
            check.check(
                'a boolean width does not become the string "True"',
                loaded.width == "95%" and loaded.height == "90%",
                f"{loaded.width}/{loaded.height}",
            )
            check.check(
                "the card-row toggles are read from [ui] independently",
                loaded.show_agent_kind and not loaded.show_status_word,
                f"{loaded.show_agent_kind}/{loaded.show_status_word}",
            )
            check.check(
                "and the blocked notification can be turned off",
                loaded.notify_on_block is False,
                str(loaded.notify_on_block),
            )
            check.check(
                "and the desktop banner has its own switch",
                loaded.notify_system is False,
                str(loaded.notify_system),
            )
            check.check(
                "and deleting a card can be told to keep its agent",
                loaded.auto_delete_agent is False,
                str(loaded.auto_delete_agent),
            )
            check.check(
                "and archiving a card can be told to stop its agent",
                loaded.auto_archive_agent is True,
                str(loaded.auto_archive_agent),
            )
            check.check(
                "the column order is read from [board]",
                loaded.sort == "manual",
                loaded.sort,
            )
            check.check(
                "an unreadable sort falls back to the default, not the typo",
                load_config(bogus_config).sort == "updated",
                load_config(bogus_config).sort,
            )

            # where a send lands --------------------------------------------
            sending = load_config()
            check.check(
                "a send lands in In Progress, wherever the card came from",
                sending.send_column("backlog") == "doing"
                and sending.send_column("queued") == "doing"
                and sending.send_column("todo") == "doing"
                and sending.send_column("blocked") == "doing"
                and sending.send_column("review") == "doing",
                " ".join(
                    sending.send_column(column)
                    for column in ("backlog", "queued", "todo", "blocked", "review")
                ),
            )
            check.check(
                "no column at all (the auto-move case) means In Progress",
                sending.send_column("") == "doing",
                sending.send_column(""),
            )
            renamed = replace(
                sending,
                columns=[
                    Column("later", "Later"),
                    Column("next", "Next"),
                    Column("started", "Started"),
                ],
            )
            check.check(
                "a board that names its columns differently still works",
                renamed.send_column("later") == "started"
                and renamed.send_column("next") == "started",
                f"{renamed.send_column('later')}/{renamed.send_column('next')}",
            )
            bare = replace(
                sending,
                columns=[Column("backlog", "Backlog"), Column("done", "Done")],
            )
            check.check(
                "a board with no In Progress column leaves the card where it is",
                bare.send_column("backlog") == "backlog",
                bare.send_column("backlog"),
            )
        finally:
            if saved_config is None:
                os.environ.pop("KANBAN_CONFIG_FILE", None)
            else:
                os.environ["KANBAN_CONFIG_FILE"] = saved_config

        fake = Path(tmp) / "fake-herdr-error"
        fake.write_text(
            '#!/usr/bin/env bash\nprintf \'{"id":"x","error":"boom"}\'\n',
            encoding="utf-8",
        )
        fake.chmod(0o755)
        result = herdr_module.Herdr(binary=str(fake)).workspaces()[1]
        check.check(
            "a non-dict error payload is still a failure",
            not result.ok and "boom" in result.error_text(),
            f"{result.ok} {result.error_text()}",
        )

        # #11 quoted phrases ------------------------------------------------
        phrase_task = Task(
            id="K7",
            title="Fix flake lock drift",
            notes="the drift is in\nthe llm-agents input pin",
            workspace_label="nixos-config-v2",
            agent_kind="pi",
        )
        check.check(
            "a quoted phrase is one term",
            query_terms('"flake lock"') == ["flake lock"]
            and task_matches(phrase_task, '"flake lock"', "nixos-config-v2")
            and not task_matches(phrase_task, '"lock flake"', "nixos-config-v2"),
            str(query_terms('"flake lock"')),
        )
        check.check(
            "a phrase can span a line break in the notes",
            task_matches(
                phrase_task, '"the drift is in the llm-agents input pin"', "w"
            ),
        )
        check.check(
            "unquoted words are still ANDed",
            query_terms("flake lock") == ["flake", "lock"]
            and task_matches(phrase_task, "flake nixos", "nixos-config-v2")
            and not task_matches(phrase_task, "flake nothing", "nixos-config-v2"),
        )

        # #13 the demo board exercises the detail sections -------------------
        demo = demo_tasks()
        check.check(
            "a demo card carries notes, updates and steps at once",
            any(card.notes and card.progress and card.steps for card in demo),
            str(
                [
                    (card.id, bool(card.notes), bool(card.progress), bool(card.steps))
                    for card in demo
                ]
            ),
        )
    finally:
        if saved is None:
            os.environ.pop("KANBAN_BOARD_FILE", None)
        else:
            os.environ["KANBAN_BOARD_FILE"] = saved


async def check_dialogs(check: Checker, tmp: str) -> None:
    """#10 and #12: the dialogs against a herdr that cannot answer."""
    import contextlib
    from dataclasses import replace

    from textual.widgets import Static

    from .app import KanbanApp
    from .config import load_config
    from .herdr import Herdr
    from .modals import TaskDetailModal
    from .store import Store

    board = Path(tmp) / "dialog-board.json"
    saved = os.environ.get("KANBAN_BOARD_FILE")
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    config = replace(load_config(), wip_limits={"doing": 1})
    try:
        store = Store.open(board)
        occupied = store.add(
            title="already in progress",
            status="doing",
            workspace_id="w1",
            agent_kind="pi",
        )
        target = store.add(
            title="about to start", status="queued", workspace_id="w1", agent_kind="pi"
        )
        app = KanbanApp(
            config=config, store=store, herdr=Herdr(binary="/nonexistent-herdr")
        )
        async with app.run_test(size=(120, 36)) as pilot:
            await pilot.pause()
            app.select_card(target.id)
            check.check(
                "dispatching into a full column says so",
                "limit" in app.wip_warning(app.task(target.id)),
                app.wip_warning(app.task(target.id)),
            )
            check.check(
                "and says nothing for a card already counted there",
                app.wip_warning(app.task(occupied.id)) == "",
            )

            # The dialog used to raise InvalidSelectValueError when the card's
            # workspace was missing from the (empty) live list.
            await pilot.press("s")
            await pilot.pause()
            modal = app.screen
            check.check(
                "the dispatch dialog survives a herdr that lists no workspaces",
                modal.__class__.__name__ == "DispatchModal",
                modal.__class__.__name__,
            )
            with contextlib.suppress(Exception):
                check.check(
                    "and shows the warning",
                    "limit" in str(modal.query_one("#dispatch-wip", Static).render()),
                )
            await pilot.press("escape")
            await pilot.pause()

            # #12 the detail view keeps itself current
            await pilot.press("enter")
            await pilot.pause()
            detail = app.screen
            await pilot.pause()
            store.update(target.id, notes="changed behind the modal")
            for _ in range(8):
                await pilot.pause(0.3)
            check.check(
                "the detail view refreshes itself while it is open",
                detail._polls > 0
                and detail.subject.notes == "changed behind the modal",
                f"polls={detail._polls} notes={detail.subject.notes!r}",
            )
            await pilot.press("escape")
            await pilot.pause()

            # a card filed from another one: the link reads both ways ---------
            parent = store.add(
                title="the run that found it", status="doing", workspace_id="w1"
            )
            child = store.add(
                title="what the run turned up",
                status="backlog",
                workspace_id="w1",
                parent_id=parent.id,
                created_by="agent",
            )
            parent_view = TaskDetailModal(
                task=Store.open(board).by_id(parent.id),
                config=app.config,
                herdr=app.herdr,
                icon_mode="unicode",
            )
            app.push_screen(parent_view)
            await pilot.pause()
            await pilot.pause()
            facts = parent_view._facts()
            check.check(
                "a card lists the follow-ups it produced",
                "spawned" in facts and child.id in facts,
                facts.replace(chr(10), " | ")[:110],
            )
            await pilot.press("escape")
            await pilot.pause()

            child_view = TaskDetailModal(
                task=Store.open(board).by_id(child.id),
                config=app.config,
                herdr=app.herdr,
                icon_mode="unicode",
            )
            app.push_screen(child_view)
            await pilot.pause()
            await pilot.pause()
            child_facts = child_view._facts()
            history = str(child_view.query_one("#detail-history", Static).render())
            check.check(
                "and a follow-up says which card it came out of",
                f"while working on {parent.id}" in child_facts
                and "created 0s ago by an agent" in child_facts,
                child_facts.replace(chr(10), " | ")[:110],
            )
            check.check(
                "the detail view shows the card's own record, not just its updates",
                "created in backlog by agent" in history,
                history[:70],
            )
            await pilot.press("escape")
            await pilot.pause()

            # the model picker follows the agent it belongs to ----------------
            from textual.widgets import Select as SelectWidget

            from .dispatch import plan_for
            from .modals import DispatchModal, TaskDraft, TaskFormModal

            picked: list[TaskDraft] = []
            form = TaskFormModal(config=app.config, workspaces=[], mode="unicode")
            app.push_screen(form, picked.append)
            await pilot.pause()
            await pilot.press(*"model probe")
            agent_select = form.query_one("#field-agent", SelectWidget)
            model_select = form.query_one("#field-model", SelectWidget)
            agent_select.value = "claude"
            await pilot.pause()
            agent_models_ok = True
            try:
                model_select.value = "opus"  # raises if it is not an option
            except Exception:  # pragma: no cover - only on a real regression
                agent_models_ok = False
            check.check(
                "the model list follows the agent it belongs to",
                agent_models_ok,
                str(model_select.value),
            )
            agent_select.value = "pi"  # a kind with no `opus`
            await pilot.pause()
            check.check(
                "and a model the new agent has no list for falls back to default",
                str(model_select.value) == "",
                str(model_select.value),
            )
            agent_select.value = "claude"
            await pilot.pause()
            model_select.value = "opus"
            form.action_save()
            await pilot.pause()
            check.check(
                "the form hands the chosen model to the card",
                bool(picked) and picked[0].agent_model == "opus",
                str(picked[0].agent_model if picked else "-"),
            )

            # the send form re-derives the flags when the kind changes --------
            args_config = replace(
                app.config,
                agent_args={
                    "pi": ["--model", "deepseek-v4-flash"],
                    "claude": ["--permission-mode=auto"],
                },
            )
            sendable = store.add(
                title="needs a model",
                status="queued",
                workspace_id="w1",
                agent_kind="pi",
                agent_model="deepseek-v4-flash",
            )
            send_plan = plan_for(
                Store.open(board).by_id(sendable.id),
                args_config,
                app.live,
            )
            check.check(
                "a card's model reaches the plan as a flag",
                send_plan.args == ("--model", "deepseek-v4-flash")
                and send_plan.model == "deepseek-v4-flash",
                str(send_plan.args),
            )
            send_form = DispatchModal(send_plan, args_config, [], "unicode")
            app.push_screen(send_form)
            await pilot.pause()
            send_form.query_one("#dispatch-agent", SelectWidget).value = "claude"
            await pilot.pause()
            flags = str(send_form.query_one("#dispatch-args", Static).render())
            check.check(
                "changing the agent in the send form re-derives its flags",
                "--permission-mode=auto" in flags and "deepseek-v4-flash" not in flags,
                flags,
            )
            await pilot.press("escape")
            await pilot.pause()
    finally:
        if saved is None:
            os.environ.pop("KANBAN_BOARD_FILE", None)
        else:
            os.environ["KANBAN_BOARD_FILE"] = saved


def _fake_herdr(tmp: str, name: str = "fake-herdr") -> Path:
    """A stand-in herdr that logs its argv and answers the calls the board makes.

    Behaviour is driven by env vars so a test can act out the failure modes a
    real agent only shows intermittently:
      FAKE_REACT=0        the agent never leaves idle (the stuck-prompt bug)
      FAKE_START_FAIL=... `agent start` refuses with this message
    """
    path = Path(tmp) / name
    logic = Path(tmp) / f"{name}.py"
    logic.write_text(
        """import json, os, sys

args = sys.argv[1:]
with open(os.environ["FAKE_LOG"], "a", encoding="utf-8") as handle:
    handle.write(" ".join(args) + "\\n")

def emit(payload):
    print(json.dumps({"id": "fake", "result": payload}))
    sys.exit(0)

def fail(code, message):
    print(json.dumps({"id": "fake", "error": {"code": code, "message": message}}))
    sys.exit(1)

reacted = os.environ.get("FAKE_REACT", "1") != "0"
prompted = os.path.exists(os.environ["FAKE_LOG"]) and any(
    line.startswith("agent prompt") for line in open(os.environ["FAKE_LOG"], encoding="utf-8")
)

def live_agent_name():
    # herdr reports the name `agent start` was given (`name`, unique among live
    # agents) separately from the kind (`agent`, what a screen-detected pane
    # has). The board matches a card's agent_name against the former, so the
    # fake has to report one: the last start it logged, or FAKE_AGENT_LIVE_NAME
    # for a check that acts out a live agent it never started.
    override = os.environ.get("FAKE_AGENT_LIVE_NAME")
    if override:
        return override
    try:
        with open(os.environ["FAKE_LOG"], encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except (KeyError, OSError):
        return ""
    for line in reversed(lines):
        parts = line.split()
        if len(parts) >= 3 and parts[0] == "agent" and parts[1] == "start":
            return parts[2]
    return ""

if args[:2] == ["workspace", "list"]:
    workspaces = [
        {"workspace_id": "w1", "label": "probe", "number": 1, "active_tab_id": "w1:t1",
         "agent_status": "idle"}]
    # A worktree workspace, once one has been forked (or reopened): set by the
    # checks that act out a card which already owns a checkout.
    if os.environ.get("FAKE_WORKTREE_OPEN") == "1":
        workspaces.append(
            {"workspace_id": "w9",
             "label": os.environ.get("FAKE_WORKTREE_LABEL", "probe-wt"),
             "number": 9, "active_tab_id": "w9:t1", "agent_status": "idle"})
    emit({"type": "workspace_list", "workspaces": workspaces})
if args[:2] == ["agent", "list"]:
    # A live agent, for the checks that need one to re-prompt — a review bounce
    # is only meaningful against the agent that did the work. The pane is the
    # one the card was dispatched to, and the name is what herdr reports for
    # the agent the board started (omitted, so the kind stands in, when there
    # never was a start).
    agents = []
    pane = os.environ.get("FAKE_AGENT_PANE")
    if pane:
        agent = {"agent": os.environ.get("FAKE_AGENT_NAME", "pi"),
                 "agent_status": os.environ.get("FAKE_AGENT_STATUS", "idle"),
                 "workspace_id": "w1",
                 "pane_id": pane,
                 "tab_id": "w1:t1",
                 "cwd": os.environ.get("FAKE_CWD", "/tmp"),
                 "terminal_title_stripped": "pi - probe"}
        name = live_agent_name()
        if name:
            agent["name"] = name
        agents.append(agent)
    emit({"type": "agent_list", "agents": agents})
if args[:2] == ["pane", "list"]:
    emit({"type": "pane_list", "panes": [{"pane_id": "w1:p1", "workspace_id": "w1",
                                          "tab_id": "w1:t1", "cwd": os.environ.get("FAKE_CWD", "/tmp")}]})
if args[:2] == ["tab", "get"]:
    label = os.environ.get("FAKE_TAB_LABEL", "")
    # A rename in an earlier call is a different process: the fake keeps the
    # label it was given in a file so a later `tab get` reports what a real
    # herdr would (`FAKE_TAB_FILE`).
    saved = os.environ.get("FAKE_TAB_FILE")
    if saved and os.path.exists(saved):
        label = open(saved, encoding="utf-8").read()
    if not label:
        fail("tab_not_found", "gone")
    emit({"tab": {"tab_id": args[2], "label": label}})
if args[:2] == ["tab", "rename"]:
    if os.environ.get("FAKE_RENAME_FAIL"):
        fail("tab_not_found", os.environ["FAKE_RENAME_FAIL"])
    saved = os.environ.get("FAKE_TAB_FILE")
    if saved:
        with open(saved, "w", encoding="utf-8") as handle:
            handle.write(args[3])
    emit({"tab": {"tab_id": args[2], "label": args[3]}})
if args[:2] == ["agent", "get"]:
    status = "working" if (reacted and prompted) else "idle"
    seq = 10 if status == "idle" else 11
    emit({"agent": {"agent": args[2], "agent_status": status, "state_change_seq": seq,
                    "pane_id": "w1:p2", "tab_id": "w1:t2"}})
if args[:2] == ["tab", "create"]:
    # The tab lands in whichever workspace it was asked for, so a worktree
    # dispatch is visible in the pane it started the agent in.
    ws = "w1"
    if "--workspace" in args:
        ws = args[args.index("--workspace") + 1]
    emit({"tab": {"tab_id": f"{ws}:t9"}, "root_pane": {"pane_id": f"{ws}:p9"}})
if args[:2] == ["agent", "read"]:
    # What a pane really hands back: a box, a status bar, stray blank lines.
    print("\u256d\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256e")
    print("\u2502 the agent \u2502")
    print("\u2570\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u256f")
    print("")
    print("")
    print(" DeepSeek V4 Flash  think:high  MCP: 2 servers enabled")
    print(" I finished the thing.")
    sys.exit(0)
if args[:2] == ["agent", "start"]:
    if os.environ.get("FAKE_START_FAIL"):
        fail("agent_name_taken", os.environ["FAKE_START_FAIL"])
    emit({})
if args[:2] in (["worktree", "create"], ["worktree", "open"]):
    if os.environ.get("FAKE_WORKTREE_FAIL"):
        fail("repository_not_trusted", os.environ["FAKE_WORKTREE_FAIL"])
    emit({"type": "worktree_created",
          "workspace": {"workspace_id": "w9",
                        "label": os.environ.get("FAKE_WORKTREE_LABEL", "probe-wt")},
          "worktree": {"path": os.environ.get("FAKE_WORKTREE_PATH", "/tmp/fake-worktree"),
                       "branch": os.environ.get("FAKE_WORKTREE_BRANCH", "worktree/fake"),
                       "open_workspace_id": "w9", "is_linked_worktree": True}})
if args[:2] == ["worktree", "remove"]:
    if os.environ.get("FAKE_WORKTREE_REMOVE_FAIL"):
        fail("workspace_not_found", os.environ["FAKE_WORKTREE_REMOVE_FAIL"])
    emit({"type": "worktree_removed",
          "workspace_id": args[args.index("--workspace") + 1],
          "path": os.environ.get("FAKE_WORKTREE_PATH", "/tmp/fake-worktree"),
          "forced": "--force" in args})
emit({"type": "ok"})
""",
        encoding="utf-8",
    )
    # Sh, not a `#!/usr/bin/env python3` shebang: the pre-commit hook runs this
    # in an environment where python3 is not on PATH, so reach the interpreter
    # the test itself is running under instead.
    path.write_text(
        f'#!/bin/sh\nexec {sys.executable!r} {str(logic)!r} "$@"\n',
        encoding="utf-8",
    )
    path.chmod(0o755)
    return path


async def check_send_now(check: Checker, tmp: str) -> None:
    """The add form's `^n`: write the card down and start its agent at once.

    Run against the fake herdr rather than demo data, because the point of the
    shortcut is the whole path — form, draft, store, plan, executor, and the
    column the card ends up in. A board that saved a card and quietly sent
    nothing would pass a weaker test.
    """
    import os
    from dataclasses import replace

    from .app import KanbanApp
    from .cli import run_agent_command
    from .config import load_config
    from .herdr import Herdr
    from .modals import TaskFormModal

    log = Path(tmp) / "send-now-calls.txt"
    board = Path(tmp) / "send-now-board.json"
    fake = _fake_herdr(tmp, "fake-herdr-send")
    env_keys = (
        "KANBAN_BOARD_FILE",
        "HERDR_WORKSPACE_ID",
        "HERDR_PLUGIN_CONTEXT_JSON",
        "HERDR_BIN_PATH",
        "FAKE_LOG",
        "FAKE_REACT",
        "FAKE_CWD",
    )
    saved = {key: os.environ.get(key) for key in env_keys}
    for key in env_keys:
        os.environ.pop(key, None)
    log.write_text("", encoding="utf-8")
    os.environ.update(
        {
            "KANBAN_BOARD_FILE": str(board),
            "HERDR_WORKSPACE_ID": "w1",
            # The CLI builds its own `Herdr`, which takes the binary from here.
            "HERDR_BIN_PATH": str(fake),
            "FAKE_LOG": str(log),
            "FAKE_REACT": "1",
            "FAKE_CWD": tmp,
        }
    )
    try:
        config = replace(load_config(), announce_protocol=True)
        add_form = TaskFormModal(config=config, workspaces=[], mode="unicode")
        edit_form = TaskFormModal(
            config=config,
            workspaces=[],
            mode="unicode",
            task=Task(id="K1", title="existing", workspace_id="w1"),
        )
        check.check(
            "the add form offers Send now and the edit form does not",
            "send-now" in [button.id for button in add_form.build_buttons()]
            and "send-now" not in [button.id for button in edit_form.build_buttons()],
        )

        app = KanbanApp(
            config=config,
            store=Store.open(board),
            herdr=Herdr(binary=str(fake)),
        )
        async with app.run_test(size=(120, 36)) as pilot:
            await pilot.pause()
            await pilot.press("a")
            await pilot.pause()
            opened = app.screen.__class__.__name__ == "TaskFormModal"
            await pilot.press(*"Start this one now")
            await pilot.press("ctrl+n")
            await pilot.pause()
            # let the dispatch worker finish before the app goes away
            for _ in range(60):
                await pilot.pause(0.05)
                if app.workers_running() == []:
                    break
            screen = app.screen.__class__.__name__

        stored = Store.open(board)
        card = stored.tasks[0] if stored.tasks else None
        check.check(
            "^n saves the card with no second dialog",
            opened
            and card is not None
            and card.title == "Start this one now"
            and screen != "DispatchModal",
            f"{card.title if card else '-'} / {screen}",
        )
        calls = [line.split() for line in log.read_text(encoding="utf-8").splitlines()]
        started = [call for call in calls if call[:2] == ["agent", "start"]]
        prompted = [call for call in calls if call[:2] == ["agent", "prompt"]]
        check.check(
            "and starts the agent for it straight away",
            bool(started) and bool(prompted),
            f"start={started[:1]} prompted={bool(prompted)}",
        )
        check.check(
            "a card sent out of the backlog lands in In Progress",
            card is not None and card.status == "doing",
            card.status if card else "-",
        )
        check.check(
            "and the card records the run, not just the save",
            card is not None
            and card.dispatched_at is not None
            and bool(card.pane_id)
            and bool(card.agent_name),
            str((card.dispatched_at, card.pane_id, card.agent_name)) if card else "-",
        )

        # the same dispatch, from a script ----------------------------------
        def cli(*argv: str) -> tuple[int, str]:
            import contextlib
            import io

            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = run_agent_command(list(argv))
            return code, (out.getvalue() + err.getvalue()).strip()

        assert card is not None
        # Put it back in the backlog so the dry run shows the rule a send
        # applies: it starts the agent, so it lands in In Progress, not Queued.
        Store.open(board).set_status(card.id, "backlog")
        log.write_text("", encoding="utf-8")
        code, out = cli("send", card.id, "--dry-run")
        check.check(
            "send --dry-run plans the dispatch the board would do, and stops",
            code == 0 and "would send" in out and "backlog -> doing" in out,
            out.replace(chr(10), " | ")[:90],
        )
        check.check(
            "and touches nothing",
            "agent start" not in log.read_text(encoding="utf-8"),
        )
        log.write_text("", encoding="utf-8")
        code, out = cli("send", card.id)
        sent = Store.open(board).by_id(card.id)
        check.check(
            "send dispatches for real: the card records the run and moves on",
            code == 0
            and sent is not None
            and sent.status == "doing"
            and sent.dispatched_at is not None
            and "agent start" in log.read_text(encoding="utf-8"),
            f"{code} {sent.status if sent else '-'} {sent.pane_id if sent else '-'}",
        )
        code, out = cli("send", "K99")
        check.check(
            "and sending a card that is not there is refused",
            code == 1 and "no task" in out,
            f"{code} {out[:50]}",
        )
        code, out = cli("send", card.id, "--model", "sonnet", "--dry-run")
        check.check(
            "send --model runs this send on that model",
            code == 0 and "--model sonnet" in out,
            out.replace(chr(10), " | ")[:100],
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


async def check_review_bounce(check: Checker, tmp: str) -> None:
    """The review bounce: `b` on the board, `herdr-kanban bounce` from a shell.

    The whole round is exercised — the record, the prompt, and the column the
    card ends up in — because a bounce is only different from `s` if the round
    is written down *and* the same agent picks the work up again. That second
    half is why the checks hold the pane to account: a bounce that started a
    fresh agent would pass a weaker test while breaking the one promise the key
    makes.
    """
    import contextlib
    import io
    import os
    import time
    from dataclasses import replace

    from .app import KanbanApp
    from .cli import run_agent_command
    from .config import load_config
    from .dispatch import review_prompt
    from .herdr import Herdr
    from .store import CHANGES_REQUESTED, Store

    log = Path(tmp) / "bounce-calls.txt"
    board = Path(tmp) / "bounce-board.json"
    app_board = Path(tmp) / "bounce-app-board.json"
    fake = _fake_herdr(tmp, "fake-herdr-bounce")
    env_keys = (
        "KANBAN_BOARD_FILE",
        "HERDR_PANE_ID",
        "HERDR_WORKSPACE_ID",
        "HERDR_BIN_PATH",
        "FAKE_LOG",
        "FAKE_REACT",
        "FAKE_CWD",
        "FAKE_AGENT_PANE",
        "FAKE_AGENT_NAME",
        "FAKE_AGENT_STATUS",
        "FAKE_AGENT_LIVE_NAME",
    )
    saved = {key: os.environ.get(key) for key in env_keys}
    for key in env_keys:
        os.environ.pop(key, None)

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        return code, (out.getvalue() + err.getvalue()).strip()

    try:
        config = replace(load_config(), announce_protocol=True)
        os.environ.update(
            {
                "KANBAN_BOARD_FILE": str(board),
                "HERDR_WORKSPACE_ID": "w1",
                # The CLI builds its own `Herdr`, which takes the binary from here.
                "HERDR_BIN_PATH": str(fake),
                "FAKE_LOG": str(log),
                "FAKE_REACT": "1",
                "FAKE_CWD": tmp,
            }
        )
        log.write_text("", encoding="utf-8")
        seed = Store.open(board)
        card = seed.add(
            title="Send this back",
            workspace_id="w1",
            workspace_label="nixos-config-v2",
            agent_kind="pi",
            status="review",
        )
        seed.hand_over(
            card.id,
            "review",
            pane_id="w1:p7",
            agent_name=f"{card.id}-pi",
            dispatched_at=time.time(),
        )

        def card_now():
            return Store.open(board).by_id(card.id)

        # -- the record -------------------------------------------------
        first, recorded = Store.open(board).request_changes(
            card.id, "the flake check still fails"
        )
        check.check(
            "a bounce records the round in History and the comment in Updates",
            first is not None
            and first.review_round == 1
            and first.history[-1]["what"] == f"{CHANGES_REQUESTED} (round 1)"
            and first.progress[-1]["text"] == "the flake check still fails"
            and first.progress[-1]["by"] == "user"
            and "round 1" in recorded,
            f"{recorded} / {first.history[-1]['what'] if first else '-'}",
        )
        check.check(
            "the record alone does not move the card",
            card_now().status == "review",
            card_now().status,
        )
        second, _ = Store.open(board).request_changes(card.id, "and the docs")
        check.check(
            "a second bounce is round two, and both rounds stay in History",
            second is not None
            and second.review_round == 2
            and second.history[-1]["what"] == f"{CHANGES_REQUESTED} (round 2)"
            and sum(
                1
                for entry in second.history
                if str(entry.get("what", "")).startswith(CHANGES_REQUESTED)
            )
            == 2,
            str(second.review_round if second else "-"),
        )
        _, ignored = Store.open(board).request_changes(card.id, "   ")
        check.check(
            "an empty comment is not a round",
            card_now().review_round == 2 and "empty comment" in ignored,
            ignored,
        )

        # -- the prompt -------------------------------------------------
        prompt = review_prompt(card_now(), "use the retry helper", config)
        check.check(
            "a bounce prompt names the round, quotes the comment, keeps the protocol",
            f"Changes requested on {card.id}" in prompt
            and prompt.index("use the retry helper") < prompt.index("herdr kanban:")
            and "The card is back in In Progress" in prompt
            and "herdr-kanban status review" in prompt,
            prompt.replace(chr(10), " | ")[:120],
        )
        quiet = review_prompt(card_now(), "x", replace(config, announce_protocol=False))
        check.check(
            "announce_protocol = false keeps the protocol out of a bounce too",
            "herdr-kanban" not in quiet
            and quiet.startswith(f"Changes requested on {card.id}"),
            repr(quiet[:60]),
        )

        # -- refusals ---------------------------------------------------
        os.environ["FAKE_AGENT_PANE"] = "w1:p7"
        # The agent the dispatch started: herdr answers to that name, which is
        # what the board verifies the pane against before re-prompting it.
        os.environ["FAKE_AGENT_LIVE_NAME"] = f"{card.id}-pi"
        code, out = cli("bounce", card.id)
        check.check(
            "bounce needs a comment: a lone card id is not sent as one",
            code == 2 and "usage" in out and card_now().review_round == 2,
            f"{code} {out[:60]}",
        )
        code, out = cli("bounce", "cfg-99")
        check.check(
            "an id the board does not know is not taken for a comment either",
            code == 2
            and "looks like a card id" in out
            and card_now().review_round == 2,
            f"{code} {out[:60]}",
        )
        code, out = cli("bounce")
        check.check(
            "bounce with nothing at all is a usage error",
            code == 2 and "usage" in out,
            f"{code} {out[:60]}",
        )
        code, out = cli("bounce", "the flake check still fails")
        check.check(
            "a bounce with no card to bounce is refused",
            code == 1 and "pass a task id" in out and card_now().review_round == 2,
            f"{code} {out[:60]}",
        )
        lonely = Store.open(board).add(
            title="Nobody is running this", workspace_id="w1", status="review"
        )
        Store.open(board).hand_over(
            lonely.id, "review", pane_id="w1:p404", dispatched_at=time.time()
        )
        code, out = cli("bounce", lonely.id, "pick this up again")
        sent = Store.open(board).by_id(lonely.id)
        check.check(
            "a card whose agent is gone is sent to `send`, not started here",
            code == 1
            and "no agent running" in out
            and sent is not None
            and sent.review_round == 0
            and sent.status == "review",
            f"{code} {out[:70]}",
        )

        # -- the send-back ----------------------------------------------
        log.write_text("", encoding="utf-8")
        code, out = cli("bounce", card.id, "use the retry helper")
        sent = Store.open(board).by_id(card.id)
        calls = log.read_text(encoding="utf-8")
        check.check(
            "a bounce re-prompts the agent in its own pane and lands In Progress",
            code == 0
            and sent is not None
            and sent.status == "doing"
            and "agent prompt w1:p7" in calls
            and "agent start" not in calls,
            f"{code} {sent.status if sent else '-'} {out[:50]}",
        )
        check.check(
            "and the round it recorded is the one the agent was given",
            sent is not None
            and sent.review_round == 3
            # The round is written before the prompt and the move after it, so
            # the round sits one entry above the dispatch's `-> doing`.
            and any(
                entry["what"] == f"{CHANGES_REQUESTED} (round 3)"
                for entry in sent.history
            )
            and sent.history[-1]["what"] == "review -> doing"
            and "use the retry helper" in calls,
            f"{sent.review_round if sent else '-'} {sent.history[-2:] if sent else '-'}",
        )

        # -- the board key, for real --------------------------------------
        # Not the demo board: a bounce is written by two different stores — the
        # board's own, then the dispatch worker's — and only a real run proves
        # the worker reads the round back before it moves the card.
        key_card = Store.open(board).add(
            title="Bounce me from the board",
            workspace_id="w1",
            workspace_label="nixos-config-v2",
            agent_kind="pi",
            status="review",
        )
        Store.open(board).hand_over(
            key_card.id,
            "review",
            pane_id="w1:p9",
            agent_name=f"{key_card.id}-pi",
            dispatched_at=time.time(),
        )
        os.environ["FAKE_AGENT_PANE"] = "w1:p9"
        os.environ["FAKE_AGENT_LIVE_NAME"] = f"{key_card.id}-pi"
        log.write_text("", encoding="utf-8")
        app = KanbanApp(
            config=config, store=Store.open(board), herdr=Herdr(binary=str(fake))
        )
        async with app.run_test(size=(120, 36)) as pilot:
            await pilot.pause()
            # The board's first live read has to land before `b` can see the
            # agent whose pane the card was dispatched to.
            for _ in range(20):
                await pilot.pause(0.05)
                if app.workers_running() == []:
                    break
            app.select_card(key_card.id)
            await pilot.press("b")
            await pilot.pause()
            real_key = app.screen.__class__.__name__ == "ReviewModal"
            if real_key:
                await pilot.press(*"use the retry helper")
                # `shift+enter` is a newline here the way it is in the notes
                # box: same widget, and the same hand trained on a chat box.
                # Driven through the real modal and onto the real record, so a
                # box that dropped the key would fail the round it wrote, not
                # just a binding table.
                await pilot.press("shift+enter")
                await pilot.press(*"and a test")
                await pilot.press("ctrl+s")
                for _ in range(60):
                    await pilot.pause(0.05)
                    if app.workers_running() == []:
                        break
        bounced = Store.open(board).by_id(key_card.id)
        calls = log.read_text(encoding="utf-8")
        comment = "use the retry helper\nand a test"
        check.check(
            "the board's b records the round and the dispatch keeps it",
            real_key
            and bounced is not None
            and bounced.status == "doing"
            and bounced.review_round == 1
            and bounced.history[-2]["what"] == f"{CHANGES_REQUESTED} (round 1)"
            and "agent prompt w1:p9" in calls
            and comment in calls,
            f"{bounced.status if bounced else '-'} / "
            f"{bounced.history[-2:] if bounced else '-'}",
        )
        check.check(
            "and shift+enter in the comment box is the newline the agent is given",
            bounced is not None
            and bounced.progress[-1]["text"] == comment
            and comment in calls,
            repr(
                bounced.progress[-1]["text"] if bounced and bounced.progress else None
            ),
        )

        # -- the key ----------------------------------------------------
        # The demo board's third column is the one holding its card with a live
        # agent (`cfg-3`, pane `w1:p9`): a bounce refuses a card whose run has
        # ended, which is the guard this check has to get past the honest way.
        os.environ["KANBAN_BOARD_FILE"] = str(app_board)
        app = KanbanApp(
            config=config,
            store=Store(Path(app_board)),
            herdr=Herdr(binary="/nonexistent-herdr"),
            demo=True,
        )
        async with app.run_test(size=(120, 36)) as pilot:
            await pilot.pause()
            # The demo board's first column holds a card with no live agent, and
            # its third the one with an agent (`cfg-3`, pane `w1:p9`): the guard
            # and the key, in the order a reviewer would meet them.
            await pilot.press("1")
            await pilot.pause()
            await pilot.press("b")
            await pilot.pause()
            refused = app.screen.__class__.__name__ != "ReviewModal"
            refusal = app.ui.notice
            await pilot.press("3")
            await pilot.pause()
            await pilot.press("b")
            await pilot.pause()
            board_key = app.screen.__class__.__name__ == "ReviewModal"
            empty_refused = False
            if board_key:
                await pilot.press("ctrl+s")
                await pilot.pause()
                empty_refused = app.screen.__class__.__name__ == "ReviewModal"
                await pilot.press("escape")
                await pilot.pause()
            await pilot.press("enter")
            await pilot.pause()
            await pilot.press("b")
            await pilot.pause()
            detail_key = app.screen.__class__.__name__ == "ReviewModal"
            if detail_key:
                await pilot.press(*"needs a test")
                await pilot.press("ctrl+s")
                await pilot.pause()
            notice = app.ui.notice
        check.check(
            "b refuses a card whose run has ended rather than starting one",
            refused and "no agent running" in refusal,
            f"{refused} {refusal!r}",
        )
        check.check(
            "b opens the comment box on the board and in the detail view",
            board_key and detail_key,
            f"board={board_key} detail={detail_key}",
        )
        check.check(
            "and an empty comment is refused, not sent as a round",
            empty_refused,
            str(empty_refused),
        )
        check.check(
            "and the demo board says what it would do without writing a board",
            "demo: would send" in notice and not app_board.exists(),
            f"{notice!r} written={app_board.exists()}",
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


async def check_worktree_dispatch(check: Checker, tmp: str) -> None:
    """A dispatch with the worktree option: fork a checkout and run the agent there.

    The whole path is exercised — plan, executor, herdr calls, and the fields
    the card ends up with — because the point of the option is that the agent
    runs in a workspace of its own rather than the card's.
    """
    import os
    from dataclasses import replace

    from .app import KanbanApp
    from .config import load_config
    from .dispatch import Executor, plan_for, tab_label_for
    from .herdr import Herdr, Workspace
    from .model import LiveState
    from .store import Store

    log = Path(tmp) / "worktree-calls.txt"
    board = Path(tmp) / "worktree-board.json"
    fake = _fake_herdr(tmp, "fake-herdr-worktree")
    worktree_path = str(Path(tmp) / "checkout")
    env_keys = (
        "KANBAN_BOARD_FILE",
        "HERDR_WORKSPACE_ID",
        "HERDR_PLUGIN_CONTEXT_JSON",
        "HERDR_BIN_PATH",
        "FAKE_LOG",
        "FAKE_REACT",
        "FAKE_CWD",
        "FAKE_WORKTREE_PATH",
        "FAKE_WORKTREE_BRANCH",
        "FAKE_WORKTREE_OPEN",
        "FAKE_WORKTREE_REMOVE_FAIL",
        "FAKE_TAB_LABEL",
    )
    saved = {key: os.environ.get(key) for key in env_keys}
    for key in env_keys:
        os.environ.pop(key, None)
    log.write_text("", encoding="utf-8")
    os.environ.update(
        {
            "KANBAN_BOARD_FILE": str(board),
            "HERDR_WORKSPACE_ID": "w1",
            "HERDR_BIN_PATH": str(fake),
            "FAKE_LOG": str(log),
            "FAKE_REACT": "1",
            "FAKE_CWD": tmp,
            "FAKE_WORKTREE_PATH": worktree_path,
            "FAKE_WORKTREE_BRANCH": "worktree/cfg-1",
        }
    )

    def space(workspace_id: str, label: str) -> Workspace:
        return Workspace(
            id=workspace_id,
            label=label,
            number=1,
            active_tab_id=f"{workspace_id}:t1",
            agent_status="idle",
        )

    def calls() -> list[list[str]]:
        return [line.split() for line in log.read_text(encoding="utf-8").splitlines()]

    try:
        config = replace(load_config(), announce_protocol=True)
        store = Store.open(board)
        task = store.add(
            title="Fork a checkout for this card",
            workspace_id="w1",
            workspace_label="probe",
            agent_kind="pi",
        )

        # The form offers the option — off by default for a card with no
        # checkout — and turning it on is what makes the dispatch fork one. The
        # press path is exercised rather than the widget in isolation, because
        # the checkbox only matters through the plan it produces and the run
        # that plan starts.
        app = KanbanApp(
            config=config, store=Store.open(board), herdr=Herdr(binary=str(fake))
        )
        async with app.run_test(size=(120, 36)) as pilot:
            await pilot.pause()
            app.ui.selected_id = task.id
            await pilot.press("s")
            await pilot.pause()
            box = app.screen.query_one("#dispatch-worktree")
            default_off = box.value is False
            box.value = True
            await pilot.press("ctrl+s")
            for _ in range(60):
                await pilot.pause(0.05)
                if app.workers_running() == []:
                    break
        check.check(
            "the send form offers a git worktree option, off by default",
            default_off,
        )
        updated = Store.open(board).by_id(task.id)
        recorded = calls()
        check.check(
            "turning it on forks a checkout and starts the agent in it",
            updated is not None
            and any(call[:2] == ["worktree", "create"] for call in recorded)
            and any(
                call[:2] == ["tab", "create"]
                and "--workspace" in call
                and call[call.index("--workspace") + 1] == "w9"
                for call in recorded
            )
            and any(
                call[:2] == ["agent", "start"]
                and "--pane" in call
                and call[call.index("--pane") + 1] == "w9:p9"
                for call in recorded
            ),
            " | ".join(" ".join(call) for call in recorded) or "no calls",
        )
        check.check(
            "the card records the checkout its run lives in",
            updated is not None
            and updated.worktree_path == worktree_path
            and updated.worktree_branch == "worktree/cfg-1"
            and updated.worktree_workspace_id == "w9",
            f"{updated.worktree_path if updated else '-'}"
            f" / {updated.worktree_workspace_id if updated else '-'}",
        )
        check.check(
            "and keeps the repo it forked from as the card's workspace",
            updated is not None and updated.workspace_id == "w1",
            updated.workspace_id if updated else "-",
        )

        # A re-dispatch reuses the checkout the card already owns instead of
        # forking another one for the same card.
        log.write_text("", encoding="utf-8")
        os.environ["FAKE_WORKTREE_OPEN"] = "1"
        live2 = LiveState(
            workspaces={"w1": space("w1", "probe"), "w9": space("w9", "probe-wt")}
        )
        again = replace(
            plan_for(updated, config, live2, fallback_workspace="w1"), worktree=True
        )
        outcome2 = Executor(Herdr(binary=str(fake))).run(again)
        recorded = calls()
        check.check(
            "a re-dispatch reuses the card's checkout rather than forking a second",
            outcome2.ok
            and not any(call[:2] == ["worktree", "create"] for call in recorded)
            and not any(call[:2] == ["worktree", "open"] for call in recorded)
            and any(
                call[:2] == ["tab", "create"]
                and call[call.index("--workspace") + 1] == "w9"
                for call in recorded
            ),
            outcome2.detail(),
        )

        # Deleting the card offers the checkout's removal; the board carries it
        # out while the workspace herdr opened for it is still there.
        os.environ["FAKE_TAB_LABEL"] = tab_label_for(updated)
        app = KanbanApp(
            config=config, store=Store.open(board), herdr=Herdr(binary=str(fake))
        )
        async with app.run_test(size=(110, 30)) as pilot:
            await pilot.pause()
            card = app.store.by_id(updated.id)
            offered = app.may_remove_worktree(card)
            app.delete_task(card, remove_worktree=True)
            await pilot.pause()
        recorded = log.read_text(encoding="utf-8").splitlines()
        check.check(
            "deleting the card offers and then removes its checkout",
            offered
            and any(
                call.startswith("worktree remove --workspace w9") for call in recorded
            ),
            " | ".join(recorded),
        )

        # A workspace closed by hand cannot be removed by herdr (`worktree
        # remove` takes only a workspace id): the board says so and names the
        # git command instead of pretending the checkout is gone.
        os.environ["FAKE_WORKTREE_REMOVE_FAIL"] = "workspace w9 not found"
        shell = Store.open(board)
        stranded = shell.add(
            title="a card whose worktree workspace closed",
            worktree_path=worktree_path,
            worktree_workspace_id="w9",
        )
        app2 = KanbanApp(config=config, store=shell, herdr=Herdr(binary=str(fake)))
        notice = app2.remove_worktree(shell.by_id(stranded.id))
        check.check(
            "a checkout whose workspace is gone is reported, not silently kept",
            "workspace w9 not found" in notice and "git worktree remove" in notice,
            notice,
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


async def check_live_loop(check: Checker, tmp: str) -> None:
    """The polling half: two clocks, and news only when there is news.

    Every herdr question is a subprocess, so the board asks the cheap one often
    and the expensive one on its own slower clock; and it says something the
    first time a card starts waiting on a human, and not once per tick after.
    """
    import os
    from dataclasses import replace

    from .app import KanbanApp
    from .config import load_config
    from .herdr import Agent, Herdr
    from .model import LiveState

    log = Path(tmp) / "live-calls.txt"
    board = Path(tmp) / "live-board.json"
    notify_log = Path(tmp) / "live-notify.txt"
    notifier = Path(tmp) / "fake-notifier"
    notifier.write_text(
        f'#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "{notify_log}"\n',
        encoding="utf-8",
    )
    notifier.chmod(0o755)
    env_keys = (
        "KANBAN_BOARD_FILE",
        "HERDR_WORKSPACE_ID",
        "HERDR_PANE_ID",
        "FAKE_LOG",
        "FAKE_REACT",
        "FAKE_CWD",
        "KANBAN_NOTIFY_CMD",
    )
    saved = {key: os.environ.get(key) for key in env_keys}
    for key in env_keys:
        os.environ.pop(key, None)
    log.write_text("", encoding="utf-8")
    os.environ.update(
        {
            "KANBAN_BOARD_FILE": str(board),
            "FAKE_LOG": str(log),
            "FAKE_REACT": "1",
            "FAKE_CWD": tmp,
            "KANBAN_NOTIFY_CMD": str(notifier),
        }
    )

    async def settled(pilot, app) -> None:  # type: ignore[no-untyped-def]
        """Wait for the app's workers, which is how a toast gets delivered."""
        for _ in range(20):
            await pilot.pause(0.05)
            if app.workers_running() == []:
                return

    def notified() -> list[str]:
        """The desktop banners the board asked for, in order."""
        if not notify_log.exists():
            return []
        return [
            line
            for line in notify_log.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    async def wait_for_notify(count: int) -> list[str]:
        """The notifier is started detached, so give it a moment to land."""
        for _ in range(40):
            lines = notified()
            if len(lines) >= count:
                return lines
            await asyncio.sleep(0.05)
        return notified()

    try:
        store = Store.open(board)
        card = store.add(
            title="the one that blocks",
            status="doing",
            workspace_id="w1",
            agent_kind="pi",
        )
        store.hand_over(
            card.id,
            "doing",
            pane_id="w1:p1",
            tab_id="w1:t1",
            dispatched_at=time.time(),
        )
        config = replace(load_config(), sync_seconds=30.0, workspace_sync_seconds=60.0)
        app = KanbanApp(
            config=config,
            store=Store.open(board),
            herdr=Herdr(binary=str(_fake_herdr(tmp, "fake-herdr-live"))),
        )
        async with app.run_test(size=(120, 36)) as pilot:
            await pilot.pause()
            # The board's own first refresh has to land before the log is used as
            # a measurement, or its two calls read as ours.
            await settled(pilot, app)
            log.write_text("", encoding="utf-8")
            quiet = app.read_live()
            app.read_live()
            calls = log.read_text(encoding="utf-8").splitlines()
            check.check(
                "a tick re-reads agent state and not workspaces it already has",
                calls.count("agent list") == 2 and calls.count("workspace list") == 0,
                str(calls),
            )
            # The slow clock comes round: workspaces are re-read on their turn.
            app.syncer._workspaces_read_at -= config.workspace_sync_seconds + 1
            app.read_live()
            calls = log.read_text(encoding="utf-8").splitlines()
            check.check(
                "until the workspace clock comes round",
                calls.count("workspace list") == 1 and calls.count("agent list") == 3,
                str(calls),
            )
            check.check(
                "and the card's workspace still resolves from the slow half",
                bool(quiet.workspaces) and quiet.workspace_label(card) == "probe",
                quiet.workspace_label(card),
            )

            blocked = Agent(
                name="k1",
                status="blocked",
                workspace_id="w1",
                pane_id=str(card.pane_id),
                tab_id="w1:t1",
                cwd="",
                focused=False,
                title="",
                logo="",
            )
            blocked_live = LiveState(
                workspaces=quiet.workspaces,
                agents={"k1": blocked},
                agents_by_pane={str(card.pane_id): blocked},
            )

            def toasts() -> list[str]:
                return [
                    line
                    for line in log.read_text(encoding="utf-8").splitlines()
                    if line.startswith("notification show")
                ]

            log.write_text("", encoding="utf-8")
            app.apply_live(quiet)  # first sight: baseline, not news
            await settled(pilot, app)
            check.check(
                "opening onto a board says nothing, however blocked it is",
                "notification" not in log.read_text(encoding="utf-8")
                and notified() == [],
                log.read_text(encoding="utf-8").strip()[:60],
            )
            app.apply_live(blocked_live)
            await settled(pilot, app)
            banners = await wait_for_notify(1)
            check.check(
                "a card that newly blocks raises a herdr notification",
                len(toasts()) == 1 and f"{card.id} needs you" in toasts()[0],
                str(toasts()),
            )
            check.check(
                "and asks the desktop too",
                len(banners) == 1 and f"{card.id} needs you" in banners[0],
                str(banners),
            )
            app.apply_live(blocked_live)
            await settled(pilot, app)
            check.check(
                "and neither repeats while the state stands",
                len(toasts()) == 1 and len(notified()) == 1,
            )
            app.config.notify_system = False
            app._live_status = {}
            app.apply_live(quiet)
            app.apply_live(blocked_live)
            await settled(pilot, app)
            check.check(
                "the desktop banner alone can be turned off",
                len(toasts()) == 2 and len(notified()) == 1,
                f"{len(notified())} banner(s)",
            )
            app.config.notify_on_block = False
            app.config.notify_system = True
            app._live_status = {}
            app.apply_live(quiet)
            app.apply_live(blocked_live)
            await settled(pilot, app)
            check.check(
                "and the whole thing can be turned off",
                len(toasts()) == 2 and len(notified()) == 1,
                log.read_text(encoding="utf-8").strip()[-60:],
            )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def check_sync_daemon(check: Checker, tmp: str) -> None:
    """The column rules and block announcements run with no board open.

    The daemon (`herdr-kanban --sync`) is the reconciler the startup hook
    starts; it must do on its own what the board's tick did, and while it holds
    the sync lock an open board must only draw — two reconcilers would announce
    every block twice.
    """
    from dataclasses import replace

    from .config import load_config
    from .herdr import Agent, Result, Workspace
    from .sync import SyncLock, daemon_pid, run_daemon

    board = Path(tmp) / "sync-board.json"
    store = Store.open(board)
    card = store.add(title="blocks with the board shut", status="doing",
                     workspace_id="w1", agent_kind="pi")
    store.hand_over(card.id, "doing", pane_id="w1:p1", tab_id="w1:t1",
                    dispatched_at=time.time())

    class StubHerdr(Herdr):
        def __init__(self) -> None:
            super().__init__(binary="/nonexistent-herdr")
            self.status = "working"
            self.down = False
            self.toasts: list[str] = []

        def workspaces(self):  # type: ignore[override]
            if self.down:
                return [], Result(ok=False, message="gone")
            return [Workspace(id="w1", label="probe", number=1, active_tab_id="w1:t1", agent_status="idle")], Result(ok=True)

        def agents(self):  # type: ignore[override]
            if self.down:
                return [], Result(ok=False, message="gone")
            agent = Agent(name="k1", status=self.status, workspace_id="w1",
                          pane_id="w1:p1", tab_id="w1:t1", cwd="",
                          focused=False, title="", logo="")
            return [agent], Result(ok=True)

        def notify(self, title: str, body: str = "") -> Result:
            self.toasts.append(title)
            return Result(ok=True)

    herdr = StubHerdr()
    config = replace(load_config(_pin_config(tmp, "sync-config.toml")),
                     notify_system=False)
    statuses = iter(["blocked", "blocked", "working"])

    def tick(_seconds: float) -> None:
        herdr.status = next(statuses, "working")

    run_daemon(config, Store.open(board), herdr, max_ticks=4, sleep=tick)
    after = Store.open(board)
    history = [entry["what"] for entry in after.by_id(card.id).history]
    check.check(
        "the daemon moves a card to Blocked with no board open, and back",
        "doing -> blocked" in history and after.by_id(card.id).status == "doing",
        str(history[-3:]),
    )
    check.check(
        "and announces the block once",
        herdr.toasts == [f"{card.id} needs you"],
        str(herdr.toasts),
    )
    check.check(
        "and leaves no lock or pid behind when it stops",
        daemon_pid(board) == 0,
    )

    held = SyncLock(board)
    held.acquire()
    try:
        check.check(
            "a second daemon finds the first and stops",
            run_daemon(config, Store.open(board), StubHerdr(), max_ticks=1,
                       sleep=lambda _s: None) == 0 and daemon_pid(board) != 0,
        )
        herdr.status = "blocked"
        app = KanbanApp(config=config, store=Store.open(board), herdr=herdr)
        herdr.toasts.clear()
        app.apply_live(app.read_live(force=True))
        check.check(
            "while it runs, an open board only draws",
            Store.open(board).by_id(card.id).status == "doing"
            and herdr.toasts == [],
        )
    finally:
        held.release()

    # A board mid-tick holds the lock with no daemon pid behind it; a daemon
    # starting then waits the tick out instead of leaving nothing watching.
    busy = SyncLock(board)
    busy.acquire()
    reads = StubHerdr()
    reads.status = "working"
    naps_taken: list[float] = []

    def board_tick_ends(seconds: float) -> None:
        naps_taken.append(seconds)
        if len(naps_taken) == 3:
            busy.release()

    run_daemon(config, Store.open(board), reads, max_ticks=1, sleep=board_tick_ends)
    busy.release()
    check.check(
        "a daemon started while an open board holds the lock for a tick waits for it",
        len(naps_taken) >= 3 and daemon_pid(board) == 0
        and Store.open(board).by_id(card.id).status == "doing",
        f"{len(naps_taken)} naps",
    )
    herdr.status = "blocked"
    app.apply_live(app.read_live())
    check.check(
        "and with it gone the board reconciles again",
        Store.open(board).by_id(card.id).status == "blocked",
    )

    herdr.down = True
    naps: list[float] = []
    clock = [0.0]
    real = time.monotonic
    time.monotonic = lambda: clock[0]  # type: ignore[assignment]

    def nap(seconds: float) -> None:
        naps.append(seconds)
        clock[0] += 30.0

    try:
        code = run_daemon(config, Store.open(board), herdr, max_ticks=10, sleep=nap)
    finally:
        time.monotonic = real  # type: ignore[assignment]
    check.check(
        "a daemon whose herdr has gone away exits instead of polling forever",
        code == 0 and len(naps) == 2,
        f"{len(naps)} naps",
    )


def check_settle_columns(check: Checker, tmp: str) -> None:
    """The column follows the agent, for the states that are never a judgement.

    A card whose agent has stopped to ask you something belongs in Blocked; a
    card whose agent is working belongs in In Progress, so one parked in a
    queued column — or answered out of Blocked — is carried on. A card blocked
    by hand, though, stays Blocked for as long as that working phase lasts, and
    `auto_move` must not be a second door back out. A card you have closed stays
    closed.
    """
    import contextlib
    import io
    import os
    from dataclasses import replace

    from .cli import run_agent_command
    from .config import load_config
    from .herdr import Agent
    from .model import LiveState

    board = Path(tmp) / "settle-board.json"
    saved = os.environ.get("KANBAN_BOARD_FILE")
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    try:
        store = Store.open(board)

        def card(title: str, status: str, pane: str = "") -> Task:
            task = store.add(
                title=title, status=status, workspace_id="w1", agent_kind="pi"
            )
            if pane:
                store.hand_over(
                    task.id, status, pane_id=pane, dispatched_at=time.time()
                )
            return task

        working = card("an agent is on it", "queued", "w1:p1")
        parked = card("an agent parked it", "doing", "w1:p2")
        waiting = card("waiting its turn", "queued")
        asking = card("asking you something", "doing", "w1:p3")
        answered = card("you answered it", "blocked", "w1:p4")
        closed = card("you closed it", "done", "w1:p5")

        def agent(status: str, pane: str) -> Agent:
            return Agent(
                name=pane.replace(":", "-"),
                status=status,
                workspace_id="w1",
                pane_id=pane,
                tab_id="w1:t9",
                cwd="",
                focused=False,
                title="",
                logo="",
            )

        def live_with(p2: str) -> LiveState:
            """The same world, with the parked card's agent in `p2`."""
            by_pane = {
                "w1:p1": agent("working", "w1:p1"),
                "w1:p3": agent("blocked", "w1:p3"),
                "w1:p4": agent("working", "w1:p4"),
                "w1:p5": agent("blocked", "w1:p5"),
                "w1:p6": agent("working", "w1:p6"),
            }
            if p2:
                by_pane["w1:p2"] = agent(p2, "w1:p2")
            return LiveState(
                workspaces={},
                agents={item.name: item for item in by_pane.values()},
                agents_by_pane=by_pane,
            )

        app = KanbanApp(
            config=replace(load_config(_pin_config(tmp)), notify_on_block=False),
            store=Store.open(board),
            herdr=Herdr(binary="/nonexistent-herdr"),
        )
        app.apply_live(live_with("working"))

        # The agent's `block` is a separate process writing the board file, and
        # the app only sees it on its next tick: that cross-process path is
        # exactly where the block used to be reverted.
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            run_agent_command(["block", parked.id, "need the DSN"])
        app.apply_live(live_with("working"))

        def status_of(task: Task) -> str:
            # A fresh read every time: the CLI and the app both write the file.
            found = Store.open(board).by_id(task.id)
            return found.status if found else "-"

        check.check(
            "a queued card whose agent is working moves to In Progress",
            status_of(working) == "doing",
            status_of(working),
        )
        check.check(
            "an explicitly blocked card stays Blocked while its agent works",
            status_of(parked) == "blocked",
            status_of(parked),
        )
        check.check(
            "and a queued card with no agent is left where it is",
            status_of(waiting) == "queued",
            status_of(waiting),
        )
        check.check(
            "a card whose agent asks a question moves to Blocked",
            status_of(asking) == "blocked",
            status_of(asking),
        )
        check.check(
            "and a blocked card whose agent is working again moves to In Progress",
            status_of(answered) == "doing",
            status_of(answered),
        )
        check.check(
            "but a card the human closed is not reopened by a live agent",
            status_of(closed) == "done",
            status_of(closed),
        )

        # The hold is spent the moment the agent leaves working, and the card
        # then follows it the way any answered block does.
        app.apply_live(live_with("idle"))
        check.check(
            "an idle agent does not lift a card that was blocked by hand",
            status_of(parked) == "blocked",
            status_of(parked),
        )
        app.apply_live(live_with("working"))
        check.check(
            "and a later working phase carries it to In Progress",
            status_of(parked) == "doing",
            status_of(parked),
        )

        # `auto_move` is a second door the live agent has into a card's column,
        # so it must honour the same hold: turning it on must not undo a block.
        auto = card("blocked with auto_move on", "doing", "w1:p6")
        app.config.auto_move = True
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            run_agent_command(["block", auto.id, "need a decision"])
        app.apply_live(live_with("working"))
        check.check(
            "auto_move does not undo a card blocked by hand",
            status_of(auto) == "blocked",
            status_of(auto),
        )
    finally:
        if saved is None:
            os.environ.pop("KANBAN_BOARD_FILE", None)
        else:
            os.environ["KANBAN_BOARD_FILE"] = saved


def check_pane_identity(check: Checker, tmp: str) -> None:
    """A pane is believed only when the agent in it is this card's agent.

    herdr never reuses a closed pane number inside one session, and carries the
    numbering across a normal restart — but a card's pane link lives in
    `board.json`, which outlives the session. A replaced session (a lost
    `session.json`, a legacy snapshot renumbered on restore) starts its counters
    at `w1`/`p1` again, so a recorded pane id can name a live stranger: the card
    would show that stranger's state and `settle_columns` would carry it into
    Blocked on it. The pane is therefore verified against the name the dispatch
    started the agent under, and that name — or the card's slug — heals a link
    that was cleared, without re-dispatching.
    """
    import os
    from dataclasses import replace

    from .config import load_config
    from .herdr import Agent
    from .model import LiveState
    from .store import Store
    from .sync import store_syncer

    board = Path(tmp) / "pane-identity-board.json"
    saved = os.environ.get("KANBAN_BOARD_FILE")
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    try:
        store = Store.open(board)
        config = replace(
            load_config(_pin_config(tmp, "pane-identity.toml")), notify_on_block=False
        )

        def card(title: str, status: str, pane: str, agent_name: str = "") -> Task:
            task = store.add(
                title=title, status=status, workspace_id="w1", agent_kind="pi"
            )
            fields: dict[str, object] = {
                "pane_id": pane,
                "dispatched_at": time.time(),
            }
            if agent_name:
                fields["agent_name"] = agent_name
            store.hand_over(task.id, status, **fields)
            return task

        def agent(name: str, pane: str, workspace: str = "w1") -> Agent:
            return Agent(
                name=name,
                status="blocked",
                workspace_id=workspace,
                pane_id=pane,
                tab_id="w1:t9",
                cwd="",
                focused=False,
                title="",
                logo="",
            )

        stranger = card("a card whose pane was taken", "doing", "w1:p4", "cfg-1-pi")
        ours = card("a card whose agent is there", "doing", "w1:p5", "cfg-2-pi")
        lost = card("a card whose pane link went", "doing", "w1:p404", "cfg-3-pi")
        by_slug = card("a card with no agent name", "doing", "w1:p404")
        detected = card(
            "a card whose pane holds a detected agent", "doing", "w1:p11", "cfg-7-pi"
        )
        # No recorded name, so the pane is the only link and the workspace is
        # the only thing left to check it with.
        stray = card(
            "a card whose pane is in a workspace it does not claim",
            "doing",
            "w9:p4",
        )
        worktree = store.add(
            title="a card running in a worktree",
            status="doing",
            workspace_id="w1",
            workspace_label="probe",
            agent_kind="pi",
        )
        store.hand_over(
            worktree.id,
            "doing",
            pane_id="w9:p3",
            agent_name="cfg-5-pi",
            worktree_path="/tmp/fake-worktree",
            worktree_workspace_id="w9",
            dispatched_at=time.time(),
        )

        by_pane = {
            "w1:p4": agent("cfg-9-pi", "w1:p4"),  # a stranger took the pane
            "w1:p5": agent("cfg-2-pi", "w1:p5"),  # ours, in the pane it recorded
            "w1:p7": agent("cfg-3-pi", "w1:p7"),  # ours, its pane link gone
            "w1:p8": agent(by_slug.slug, "w1:p8"),  # ours, found by slug
            "w1:p11": agent("", "w1:p11"),  # a detected stranger
            "w9:p3": agent("cfg-5-pi", "w9:p3", "w9"),  # ours, worktree
            "w9:p4": agent("cfg-6-pi", "w9:p4", "w9"),  # name right, place wrong
        }
        live = LiveState(
            workspaces={},
            agents={item.name: item for item in by_pane.values()},
            agents_by_pane=by_pane,
        )

        check.check(
            "a pane id whose agent is somebody else is not the card's agent",
            live.lookup(stranger) is None
            and live.for_task(stranger) == ("exited", False),
            str(live.for_task(stranger)),
        )
        check.check(
            "nor is a pane holding an agent herdr only detected",
            live.lookup(detected) is None,
            str(live.lookup(detected)),
        )
        check.check(
            "and one in a workspace the card does not claim",
            live.lookup(stray) is None,
            str(live.lookup(stray)),
        )
        check.check(
            "the card's own agent in its own pane is still found",
            live.lookup(ours) is not None
            and live.lookup(ours).name == "cfg-2-pi"  # type: ignore[union-attr]
            and live.for_task(ours) == ("blocked", True),
            str(live.for_task(ours)),
        )
        check.check(
            "a worktree run is still the card's, in the workspace it opened",
            live.lookup(worktree) is not None
            and live.lookup(worktree).workspace_id == "w9"  # type: ignore[union-attr]
            and live.for_task(worktree) == ("blocked", True),
            str(live.for_task(worktree)),
        )
        check.check(
            "a card whose pane link went is found by the agent name it recorded",
            live.lookup(lost) is not None
            and live.lookup(lost).pane_id == "w1:p7"  # type: ignore[union-attr]
            and live.for_task(lost) == ("blocked", True),
            str(live.for_task(lost)),
        )
        check.check(
            "and a card with no recorded name is found by its slug",
            live.lookup(by_slug) is not None
            and live.lookup(by_slug).pane_id == "w1:p8"  # type: ignore[union-attr]
            and live.for_task(by_slug) == ("blocked", True),
            str(live.for_task(by_slug)),
        )

        # The column rule runs on the same snapshot, so it must reach the same
        # verdict: a stranger's Blocked is not this card's news. More than one
        # pass because moving a card rewrites the stored list order while the
        # reconciler iterates it, so a card it moves can be skipped for a tick
        # (`kanban: settle_columns iterates the list it mutates`). The daemon's
        # next tick does this for free; a check that wants one verdict asks
        # again.
        syncer = store_syncer(config, store, Herdr(binary="/nonexistent-herdr"))
        syncer.live = live
        for _ in range(3):
            syncer.settle_columns()

        def status_of(task: Task) -> str:
            found = Store.open(board).by_id(task.id)
            return found.status if found else "-"

        check.check(
            "a stranger's blocked state does not move the card to Blocked",
            status_of(stranger) == "doing"
            and status_of(detected) == "doing"
            and status_of(stray) == "doing",
            f"{status_of(stranger)}/{status_of(detected)}/{status_of(stray)}",
        )
        check.check(
            "while a healed link follows the agent it found",
            status_of(lost) == "blocked"
            and status_of(by_slug) == "blocked"
            and status_of(ours) == "blocked",
            f"{status_of(lost)}/{status_of(by_slug)}/{status_of(ours)}",
        )
    finally:
        if saved is None:
            os.environ.pop("KANBAN_BOARD_FILE", None)
        else:
            os.environ["KANBAN_BOARD_FILE"] = saved


def check_live_staleness(check: Checker, tmp: str) -> None:
    """The board times the live states it watches, and the view spends that clock.

    herdr reports no timestamp for a status change — `agent list` carries
    `state_change_seq`, a counter, not a clock — so `Syncer.read_live` times the
    transitions it observes, and the view turns that into the two card states
    the raw snapshot cannot express: an idle agent that has sat in In Progress
    past `idle_stale_minutes` is flagged, and a card whose agent is gone stops
    saying `no agent` after `exited_decay_minutes`. These checks pin the clock
    (start, hold, restamp, carry-forward on a failed read) and what the view
    does with it; a state that never carried a clock keeps the old behaviour.
    """
    from dataclasses import replace

    from .config import load_config
    from .herdr import Agent, Result, Workspace
    from .model import LiveState, UiState, build_view
    from .render import CardView, _card_rule, format_duration
    from .sync import store_syncer

    def make_agent(name: str, status: str, pane: str) -> Agent:
        return Agent(
            name=name,
            status=status,
            workspace_id="w1",
            pane_id=pane,
            tab_id="w1:t1",
            cwd="",
            focused=False,
            title="",
            logo="",
        )

    class StubHerdr(Herdr):
        def __init__(self) -> None:
            super().__init__(binary="/nonexistent-herdr")
            self.status = "idle"
            self.agents_ok = True

        def workspaces(self):  # type: ignore[override]
            return [
                Workspace(
                    id="w1",
                    label="probe",
                    number=1,
                    active_tab_id="w1:t1",
                    agent_status="idle",
                )
            ], Result(ok=True)

        def agents(self):  # type: ignore[override]
            if not self.agents_ok:
                return [], Result(ok=False, message="agent list failed")
            return [make_agent(idle_card.slug, self.status, "w1:p1")], Result(ok=True)

    board = Path(tmp) / "staleness-board.json"
    store = Store.open(board)
    idle_card = store.add(
        title="agent went idle", status="doing", workspace_id="w1", agent_kind="pi"
    )
    gone_card = store.add(
        title="agent is gone", status="review", workspace_id="w1", agent_kind="pi"
    )
    store.hand_over(
        idle_card.id,
        "doing",
        pane_id="w1:p1",
        tab_id="w1:t1",
        agent_name=idle_card.slug,
        dispatched_at=time.time(),
    )
    store.hand_over(
        gone_card.id,
        "review",
        pane_id="w1:p2",
        tab_id="w1:t1",
        agent_name=gone_card.slug,
        dispatched_at=time.time(),
    )

    herdr = StubHerdr()
    config = replace(
        load_config(_pin_config(tmp, "staleness-config.toml")),
        idle_stale_minutes=15.0,
        exited_decay_minutes=60.0,
    )
    syncer = store_syncer(config, store, herdr)

    # -- the clock the Syncer keeps across ticks -------------------------
    clock = [1000.0]
    real = time.monotonic
    time.monotonic = lambda: clock[0]  # type: ignore[assignment]
    try:
        first = syncer.read_live(force=True)
        check.check(
            "the first sighting of a status starts its clock",
            first.status_since.get(idle_card.id) == 1000.0
            and first.status_since.get(gone_card.id) == 1000.0,
            str(first.status_since),
        )
        clock[0] += 30
        held = syncer.read_live()
        check.check(
            "an unchanged status keeps its clock",
            held.status_since.get(idle_card.id) == 1000.0,
            str(held.status_since),
        )
        herdr.status = "working"
        clock[0] += 5
        flipped = syncer.read_live()
        check.check(
            "a status change restamps the clock",
            flipped.status_since.get(idle_card.id) == 1035.0,
            str(flipped.status_since),
        )
        herdr.agents_ok = False
        clock[0] += 600
        unread = syncer.read_live()
        check.check(
            "a failed agent read carries the clocks forward, not to now",
            unread.status_since.get(idle_card.id) == 1035.0
            and unread.status_since.get(gone_card.id) == 1000.0,
            str(unread.status_since),
        )
    finally:
        time.monotonic = real  # type: ignore[assignment]

    # -- what the view spends the clock on --------------------------------
    def shown(task: Task, live: LiveState) -> CardView | None:
        view = build_view(
            config,
            store.tasks,
            live,
            UiState(),
            width=160,
            height=20,
            icon_mode="unicode",
        )
        return view.card(task.id)

    idle_agent = make_agent(idle_card.slug, "idle", "w1:p1")
    review_agent = make_agent(gone_card.slug, "idle", "w1:p2")
    watched = LiveState(
        agents={idle_agent.name: idle_agent, review_agent.name: review_agent},
        agents_by_pane={
            idle_agent.pane_id: idle_agent,
            review_agent.pane_id: review_agent,
        },
        status_since={
            idle_card.id: time.monotonic() - 1000,
            gone_card.id: time.monotonic() - 1000,
        },
    )
    idle_view = shown(idle_card, watched)
    assert idle_view is not None
    check.check(
        "an idle agent in In Progress past the window is flagged",
        idle_view.idle_stale and idle_view.status == "idle",
        f"{idle_view.status}/{idle_view.idle_stale}",
    )
    rule = _card_rule(idle_view, 30, "unicode", "x", True).plain
    check.check(
        "and its rule says how long the agent has been idle",
        "idle" in rule and format_duration(idle_view.status_age) in rule,
        rule,
    )
    review_view = shown(gone_card, watched)
    check.check(
        "but an idle agent is only stale in In Progress, not in Review",
        review_view is not None and not review_view.idle_stale,
        str(review_view and review_view.idle_stale),
    )
    fresh_view = shown(
        idle_card,
        LiveState(
            agents={idle_agent.name: idle_agent},
            agents_by_pane={idle_agent.pane_id: idle_agent},
            status_since={idle_card.id: time.monotonic()},
        ),
    )
    check.check(
        "and a recently idle agent is not flagged",
        fresh_view is not None
        and fresh_view.status == "idle"
        and not fresh_view.idle_stale,
        str(fresh_view and (fresh_view.status, fresh_view.idle_stale)),
    )
    decayed = shown(
        gone_card, LiveState(status_since={gone_card.id: time.monotonic() - 3700})
    )
    check.check(
        "a gone agent past the decay window stops saying no agent",
        decayed is not None and decayed.status == "",
        str(decayed and decayed.status),
    )
    inside = shown(
        gone_card, LiveState(status_since={gone_card.id: time.monotonic() - 60})
    )
    untimed = shown(gone_card, LiveState())
    check.check(
        "a gone agent inside the window still says it, as untimed state does",
        inside is not None
        and inside.status == "exited"
        and untimed is not None
        and untimed.status == "exited",
        str(inside and inside.status),
    )

    # -- the two keys ----------------------------------------------------
    parsed = Path(tmp) / "staleness-keys.toml"
    parsed.write_text(
        "[board]\nidle_stale_minutes = 5\nexited_decay_minutes = 0\n",
        encoding="utf-8",
    )
    keys = load_config(parsed)
    check.check(
        "the staleness keys parse, and 0 turns one off",
        keys.idle_stale_minutes == 5.0 and keys.exited_decay_minutes == 0.0,
        f"{keys.idle_stale_minutes}/{keys.exited_decay_minutes}",
    )
    bad = Path(tmp) / "staleness-bad.toml"
    bad.write_text(
        '[board]\nidle_stale_minutes = "soon"\nexited_decay_minutes = -5\n',
        encoding="utf-8",
    )
    fallback = load_config(bad)
    check.check(
        "a bad value falls back, a negative one clamps to off",
        fallback.idle_stale_minutes == 15.0
        and fallback.exited_decay_minutes == 0.0,
        f"{fallback.idle_stale_minutes}/{fallback.exited_decay_minutes}",
    )


def check_prompt_delivery(check: Checker, tmp: str) -> None:
    """A prompt that lands in the composer but starts nothing must not pass.

    This is the failure pi reproduces intermittently: `agent prompt` reports the
    text and the Enter as written, the agent stays idle, and a board that trusts
    the call marks the card as running while nothing happens. The turn is not
    success — but the agent that was started is real, so the run is recorded at
    the moment it exists rather than only after a confirmation that may never
    come.
    """
    import os
    from dataclasses import replace

    from . import dispatch
    from .config import load_config
    from .dispatch import Executor, Plan
    from .herdr import Herdr

    log = Path(tmp) / "calls.txt"

    def drive(react: bool, start_fail: str = "") -> tuple[bool, list[str], str, list]:
        log.write_text("", encoding="utf-8")
        os.environ["FAKE_LOG"] = str(log)
        os.environ["FAKE_REACT"] = "1" if react else "0"
        os.environ["FAKE_CWD"] = tmp
        if start_fail:
            os.environ["FAKE_START_FAIL"] = start_fail
        else:
            os.environ.pop("FAKE_START_FAIL", None)
        steps = []
        records = []
        plan = Plan(
            task_id="K1",
            workspace_id="w1",
            workspace_label="probe",
            kind="pi",
            name="k1",
            prompt="do the thing",
            tab_label="K1 do the thing",
        )
        outcome = Executor(Herdr(binary=str(_fake_herdr(tmp)))).run(
            plan, on_step=steps.append, on_record=records.append
        )
        return (
            outcome.ok,
            [f"{s.label}: {s.detail}" for s in steps],
            outcome.error,
            records,
        )

    saved = {
        k: os.environ.get(k)
        for k in ("FAKE_LOG", "FAKE_REACT", "FAKE_CWD", "FAKE_START_FAIL")
    }
    # The unconfirmed path polls for the whole production window, twice; these
    # checks only care *that* it waited, not for how long.
    saved_confirm = dispatch.PROMPT_CONFIRM_SECONDS
    dispatch.PROMPT_CONFIRM_SECONDS = 0.05
    try:
        ok, steps, error, records = drive(react=True)
        check.check(
            "a prompt the agent acts on is reported as submitted",
            ok and any("task submitted" in step for step in steps) and not error,
            " | ".join(steps),
        )
        check.check(
            "and the run is recorded the moment the agent starts",
            len(records) == 1
            and records[0].agent_name == "k1"
            and records[0].pane_id == "w1:p9"
            and records[0].tab_id == "w1:t9"
            and not records[0].ok,
            str([(r.agent_name, r.pane_id, r.ok) for r in records]),
        )

        ok, steps, error, records = drive(react=False)
        check.check(
            "a prompt the agent ignores is not reported as success",
            not ok and "never started" in error,
            f"{ok} {error[:60]}",
        )
        check.check(
            "and the text already in the composer is submitted with Enter",
            any("pressing Enter" in step for step in steps),
            " | ".join(steps),
        )
        check.check(
            "but the agent it started is recorded anyway, before the failed wait",
            len(records) == 1
            and records[0].agent_name == "k1"
            and records[0].pane_id == "w1:p9"
            and not records[0].ok,
            str([(r.agent_name, r.pane_id) for r in records]),
        )

        ok, steps, error, records = drive(react=True, start_fail="already used")
        check.check(
            "a refused agent name is reported, not swallowed",
            not ok and "already used" in error,
            error[:60],
        )
        check.check(
            "and nothing is recorded when no agent was ever started",
            records == [],
            str([(r.agent_name, r.pane_id) for r in records]),
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        dispatch.PROMPT_CONFIRM_SECONDS = saved_confirm
        del replace, load_config


def check_send_records_unconfirmed(check: Checker, tmp: str) -> None:
    """`send` records the run even when the turn never confirms.

    The CLI's door into the same invariant: `agent prompt` can report success
    with the text still in the composer, and the caller is right to call that
    "not sent" — but the agent is running, and a card with no pane and no name
    is an orphan herdr will not let a re-send replace (duplicate name). So the
    fields are written whatever the confirmation said, and written before the
    wait rather than after it; only the column move and the exit code still wait
    on the turn.
    """
    import contextlib
    import io
    import os
    import threading
    import time

    from . import dispatch
    from .cli import run_agent_command
    from .store import Store

    board = Path(tmp) / "unconfirmed-board.json"
    log = Path(tmp) / "unconfirmed-calls.txt"
    env_keys = (
        "KANBAN_BOARD_FILE",
        "HERDR_WORKSPACE_ID",
        "HERDR_PLUGIN_CONTEXT_JSON",
        "HERDR_BIN_PATH",
        "FAKE_LOG",
        "FAKE_REACT",
        "FAKE_CWD",
    )
    saved = {key: os.environ.get(key) for key in env_keys}
    saved_confirm = dispatch.PROMPT_CONFIRM_SECONDS
    for key in env_keys:
        os.environ.pop(key, None)
    log.write_text("", encoding="utf-8")
    os.environ.update(
        {
            "KANBAN_BOARD_FILE": str(board),
            "HERDR_WORKSPACE_ID": "w1",
            "HERDR_BIN_PATH": str(_fake_herdr(tmp, "fake-herdr-unconfirmed")),
            "FAKE_LOG": str(log),
            "FAKE_REACT": "0",  # the prompt lands; the turn never starts
            "FAKE_CWD": tmp,
        }
    )
    dispatch.PROMPT_CONFIRM_SECONDS = 0.05
    try:
        card = Store.open(board).add(
            title="delivered but never confirmed", workspace_id="w1"
        )
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(["send", card.id])
        stored = Store.open(board).by_id(card.id)
        check.check(
            "send reports an unconfirmed turn as not sent",
            code == 1 and "not sent" in err.getvalue(),
            f"{code} {err.getvalue().strip()[:70]}",
        )
        check.check(
            "but records the pane, tab and agent it did start",
            stored is not None
            and bool(stored.pane_id)
            and bool(stored.tab_id)
            and bool(stored.agent_name)
            and stored.dispatched_at is not None,
            str(
                (stored.pane_id, stored.tab_id, stored.agent_name, stored.dispatched_at)
                if stored
                else None
            ),
        )
        check.check(
            "and leaves the card where it was, not claiming it is in progress",
            stored is not None and stored.status == "backlog",
            stored.status if stored else "-",
        )

        # The CLI is a dispatching process too: the link has to be on disk while
        # `send` is still inside the confirmation wait, not only once it
        # returns, or a script killed in that window loses it the way the board
        # used to. Run the send on its own thread so the wait can be watched
        # from outside it.
        second = Store.open(board).add(
            title="killed mid-confirmation", workspace_id="w1"
        )
        log.write_text("", encoding="utf-8")
        dispatch.PROMPT_CONFIRM_SECONDS = 0.5
        codes: list[int] = []

        def run_send() -> None:
            quiet_out, quiet_err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(quiet_out), contextlib.redirect_stderr(
                quiet_err
            ):
                codes.append(run_agent_command(["send", second.id]))

        sender = threading.Thread(target=run_send)
        sender.start()
        linked_mid_wait = False
        observe_until = time.monotonic() + 1.0
        while time.monotonic() < observe_until:
            current = Store.open(board).by_id(second.id)
            if current is not None and current.pane_id:
                linked_mid_wait = sender.is_alive()
                break
            time.sleep(0.01)
        sender.join(timeout=5)
        check.check(
            "and the link is written while send is still confirming the turn",
            linked_mid_wait,
            f"alive={sender.is_alive()} code={codes}",
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        dispatch.PROMPT_CONFIRM_SECONDS = saved_confirm


async def check_dispatch_record_survives_close(check: Checker, tmp: str) -> None:
    """A board closed mid-dispatch still leaves the card linked to its agent.

    The write must not ride on the board's event loop: the dispatch worker
    starts the agent, and the record has to be on disk before the worker waits
    on the prompt — because the board (or the quick-add popup that launched it)
    can be gone by the time that wait ends. This closes the app inside the wait
    and checks the link survived it.
    """
    import asyncio
    import os

    from . import dispatch
    from .app import KanbanApp
    from .config import load_config
    from .herdr import Herdr
    from .store import Store

    board = Path(tmp) / "dispatch-record-board.json"
    log = Path(tmp) / "dispatch-record-calls.txt"
    env_keys = (
        "KANBAN_BOARD_FILE",
        "HERDR_WORKSPACE_ID",
        "HERDR_PLUGIN_CONTEXT_JSON",
        "HERDR_BIN_PATH",
        "FAKE_LOG",
        "FAKE_REACT",
        "FAKE_CWD",
    )
    saved = {key: os.environ.get(key) for key in env_keys}
    saved_confirm = dispatch.PROMPT_CONFIRM_SECONDS
    for key in env_keys:
        os.environ.pop(key, None)
    log.write_text("", encoding="utf-8")
    os.environ.update(
        {
            "KANBAN_BOARD_FILE": str(board),
            "HERDR_WORKSPACE_ID": "w1",
            "HERDR_BIN_PATH": str(_fake_herdr(tmp, "fake-herdr-record")),
            "FAKE_LOG": str(log),
            "FAKE_REACT": "0",  # the turn never confirms
            "FAKE_CWD": tmp,
        }
    )
    # Wide enough to close the board inside the confirmation wait on purpose.
    dispatch.PROMPT_CONFIRM_SECONDS = 1.0
    try:
        app = KanbanApp(
            config=load_config(),
            store=Store.open(board),
            herdr=Herdr(binary=os.environ["HERDR_BIN_PATH"]),
        )
        linked_while_busy = False
        async with app.run_test(size=(120, 36)) as pilot:
            await pilot.pause()
            await pilot.press("a")
            await pilot.pause()
            await pilot.press(*"Keep the link")
            await pilot.press("ctrl+n")
            for _ in range(150):
                await pilot.pause(0.02)
                current = Store.open(board).tasks
                card = current[0] if current else None
                if card is not None and card.pane_id:
                    linked_while_busy = any(
                        worker.group == "dispatch" and not worker.is_finished
                        for worker in app.workers
                    )
                    break
            check.check(
                "the card is linked while the dispatch is still confirming",
                linked_while_busy,
                str([(w.group, w.is_finished) for w in app.workers]),
            )
        # The board is gone; the worker was inside the confirmation wait.
        after = Store.open(board)
        card = after.tasks[0] if after.tasks else None
        check.check(
            "and the link survives the board closing on it",
            card is not None
            and bool(card.pane_id)
            and bool(card.agent_name)
            and bool(card.dispatched_at),
            str((card.pane_id, card.agent_name) if card else None),
        )
        check.check(
            "with the card left where it was, since the turn never confirmed",
            card is not None and card.status == "backlog",
            card.status if card else "-",
        )
        # The orphaned worker is still finishing its second wait; let it go
        # before the env it is using is restored under it.
        await asyncio.sleep(2.5)
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        dispatch.PROMPT_CONFIRM_SECONDS = saved_confirm


async def check_delete_stops_agent(check: Checker, tmp: str) -> None:
    """Deleting a card stops its agent; a repurposed tab is left alone."""
    import os
    from dataclasses import replace

    from .app import KanbanApp
    from .config import load_config
    from .dispatch import tab_label_for
    from .herdr import Herdr
    from .store import Store

    log = Path(tmp) / "delete-calls.txt"
    os.environ["FAKE_LOG"] = str(log)
    os.environ["FAKE_CWD"] = tmp
    os.environ["FAKE_REACT"] = "1"
    board = Path(tmp) / "delete-board.json"
    saved = {
        k: os.environ.get(k)
        for k in (
            "KANBAN_BOARD_FILE",
            "FAKE_LOG",
            "FAKE_REACT",
            "FAKE_CWD",
            "FAKE_TAB_LABEL",
        )
    }
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    fake = _fake_herdr(tmp)

    def app_for(store: Store, config: object = None) -> KanbanApp:
        return KanbanApp(
            config=config or load_config(),
            store=store,
            herdr=Herdr(binary=str(fake)),
        )

    try:
        store = Store.open(board)
        task = store.add(
            title="a card with an agent",
            agent_kind="pi",
            workspace_id="w1",
            status="doing",
            pane_id="w1:p9",
            tab_id="w1:t9",
            agent_name="k1",
        )
        log.write_text("", encoding="utf-8")
        os.environ["FAKE_TAB_LABEL"] = tab_label_for(task)
        app = app_for(store)
        async with app.run_test(size=(110, 30)) as pilot:
            await pilot.pause()
            app.live = app.live.__class__(
                workspaces=app.live.workspaces,
                agents={
                    "pi": __import__("kanban.herdr", fromlist=["Agent"]).Agent(
                        name="pi",
                        status="idle",
                        workspace_id="w1",
                        pane_id="w1:p9",
                        tab_id="w1:t9",
                        cwd=tmp,
                        focused=False,
                        title="π - probe",
                        logo="",
                    )
                },
                agents_by_pane={},
            )
            app.delete_task(task)
            await pilot.pause()
        calls = log.read_text(encoding="utf-8").splitlines()
        check.check(
            "deleting a card closes the tab its dispatch opened",
            any(call.startswith("tab close w1:t9") for call in calls),
            " | ".join(calls),
        )
        check.check("and the card is gone", Store.open(board).by_id(task.id) is None)

        # a tab the user has since repurposed is not ours to close
        store2 = Store.open(board)
        other = store2.add(
            title="a card whose tab moved on",
            agent_kind="pi",
            workspace_id="w1",
            status="doing",
            pane_id="w1:p9",
            tab_id="w1:t9",
            agent_name="k2",
        )
        log.write_text("", encoding="utf-8")
        os.environ["FAKE_TAB_LABEL"] = "something else entirely"
        app2 = app_for(store2)
        async with app2.run_test(size=(110, 30)) as pilot:
            await pilot.pause()
            app2.live = app2.live.__class__(
                workspaces=app2.live.workspaces,
                agents={
                    "pi": __import__("kanban.herdr", fromlist=["Agent"]).Agent(
                        name="pi",
                        status="idle",
                        workspace_id="w1",
                        pane_id="w1:p9",
                        tab_id="w1:t9",
                        cwd=tmp,
                        focused=False,
                        title="π - probe",
                        logo="",
                    )
                },
                agents_by_pane={},
            )
            app2.delete_task(other)
            await pilot.pause()
        calls = log.read_text(encoding="utf-8").splitlines()
        check.check(
            "a repurposed tab is left alone when the card is deleted",
            not any(call.startswith("tab close") for call in calls),
            " | ".join(calls),
        )

        # a board that opts out (`auto_delete_agent = false`) keeps the agent
        store3 = Store.open(board)
        kept = store3.add(
            title="a card whose agent the board should keep",
            agent_kind="pi",
            workspace_id="w1",
            status="doing",
            pane_id="w1:p9",
            tab_id="w1:t9",
            agent_name="k3",
        )
        log.write_text("", encoding="utf-8")
        os.environ["FAKE_TAB_LABEL"] = tab_label_for(kept)
        app3 = app_for(store3, replace(load_config(), auto_delete_agent=False))
        async with app3.run_test(size=(110, 30)) as pilot:
            await pilot.pause()
            app3.delete_task(kept)
            await pilot.pause()
        calls = log.read_text(encoding="utf-8").splitlines()
        check.check(
            "auto_delete_agent = false deletes the card and leaves its tab alone",
            not any(call.startswith("tab close") for call in calls)
            and Store.open(board).by_id(kept.id) is None,
            " | ".join(calls),
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


async def check_archive_stops_agent(check: Checker, tmp: str) -> None:
    """`auto_archive_agent`: the card's agent goes with the card — both doors.

    Archiving is about the board, and by default it leaves the run alone. With
    the flag on the tab closes exactly as `d` closes it — the label check
    included, so a repurposed pane is still not ours — and `herdr-kanban
    archive` does the same thing from a script, because a keypress and a script
    must not mean two different things. Either way the card's pointer at the tab
    goes with it; flag off, the pane and tab the card was dispatched with
    survive, which is what lets `unarchive` put a card whose agent is still
    running back on the board.
    """
    import contextlib
    import io
    import os
    from dataclasses import replace

    from .app import KanbanApp
    from .cli import run_agent_command
    from .config import load_config
    from .dispatch import tab_label_for
    from .herdr import Herdr
    from .store import Store

    log = Path(tmp) / "archive-agent-calls.txt"
    fake = _fake_herdr(tmp, "archive-herdr")
    board = Path(tmp) / "archive-agent-board.json"
    saved = {
        key: os.environ.get(key)
        for key in (
            "KANBAN_BOARD_FILE",
            "KANBAN_CONFIG_FILE",
            "HERDR_BIN_PATH",
            "HERDR_PANE_ID",
            "FAKE_LOG",
            "FAKE_TAB_LABEL",
        )
    }
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    os.environ["FAKE_LOG"] = str(log)
    # The CLI builds its own `Herdr`, so the fake reaches it through the
    # variable herdr injects rather than through a constructor argument.
    os.environ["HERDR_BIN_PATH"] = str(fake)
    # Not from a pane: these calls are the human's, so no `_from_agent` refusal.
    os.environ.pop("HERDR_PANE_ID", None)
    os.environ["KANBAN_CONFIG_FILE"] = str(
        _pin_config(tmp, "archive-agent-config.toml", auto_archive_agent=True)
    )

    def calls() -> list[str]:
        return log.read_text(encoding="utf-8").splitlines()

    def cli(*argv: str) -> tuple[int, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = run_agent_command(list(argv))
        return code, (out.getvalue() + err.getvalue()).strip()

    def dispatched_card(store: Store, title: str):
        """A card mid-run: a pane, the tab its dispatch opened, an agent name."""
        return store.add(
            title=title,
            agent_kind="pi",
            workspace_id="w1",
            status="doing",
            pane_id="w1:p9",
            tab_id="w1:t9",
            agent_name="k1",
        )

    def board_app(store: Store, config: object) -> KanbanApp:
        return KanbanApp(config=config, store=store, herdr=Herdr(binary=str(fake)))

    try:
        # The `A` key, flag on: the tab goes with the card.
        store = Store.open(board)
        card = dispatched_card(store, "a card whose agent should stop")
        log.write_text("", encoding="utf-8")
        os.environ["FAKE_TAB_LABEL"] = tab_label_for(card)
        app = board_app(store, load_config())
        async with app.run_test(size=(110, 30)) as pilot:
            await pilot.pause()
            app.archive_task(card)
            await pilot.pause()
            notice = app.ui.notice
        check.check(
            "auto_archive_agent closes the tab when the board archives a card",
            any(call.startswith("tab close w1:t9") for call in calls()),
            " | ".join(calls()),
        )
        archived = Store.open(board).archived_by_id(card.id)
        check.check(
            "and the archived card forgets the pane and tab it was sent to",
            archived is not None
            and archived.tab_id == ""
            and archived.pane_id == ""
            and archived.agent_name == "",
            f"{archived.tab_id!r}/{archived.pane_id!r}" if archived else "gone",
        )
        check.check(
            "and the notice reports the stop rather than a running agent",
            "closed w1:t9" in notice and "still running" not in notice,
            notice,
        )

        # Flag off: the run outlives its place on the board.
        store2 = Store.open(board)
        kept = dispatched_card(store2, "a card whose agent should keep going")
        log.write_text("", encoding="utf-8")
        os.environ["FAKE_TAB_LABEL"] = tab_label_for(kept)
        app2 = board_app(store2, replace(load_config(), auto_archive_agent=False))
        async with app2.run_test(size=(110, 30)) as pilot:
            await pilot.pause()
            app2.archive_task(kept)
            await pilot.pause()
            notice_off = app2.ui.notice
        left = Store.open(board).archived_by_id(kept.id)
        check.check(
            "flag off, archiving leaves the tab and the card's pointer alone",
            not any(call.startswith("tab close") for call in calls())
            and left is not None
            and left.tab_id == "w1:t9"
            and left.agent_name == "k1",
            " | ".join(calls()) or "no calls",
        )
        check.check(
            "and the notice says the agent is still running",
            "still running" in notice_off,
            notice_off,
        )

        # A tab the user has taken for something else is not ours to close,
        # whichever door archives the card (the dead pointer goes either way).
        store3 = Store.open(board)
        repurposed = dispatched_card(store3, "a card whose tab moved on")
        log.write_text("", encoding="utf-8")
        os.environ["FAKE_TAB_LABEL"] = "something else entirely"
        app3 = board_app(store3, load_config())
        async with app3.run_test(size=(110, 30)) as pilot:
            await pilot.pause()
            app3.archive_task(repurposed)
            await pilot.pause()
        moved_on = Store.open(board).archived_by_id(repurposed.id)
        check.check(
            "a repurposed tab is left alone when a card is archived",
            not any(call.startswith("tab close") for call in calls())
            and moved_on is not None
            and moved_on.tab_id == "",
            " | ".join(calls()) or "no calls",
        )

        # ...and the CLI says the same thing, which is the whole point of a
        # flag: `herdr-kanban archive` from a script stops the agent too.
        scripted = dispatched_card(Store.open(board), "a card archived from a script")
        log.write_text("", encoding="utf-8")
        os.environ["FAKE_TAB_LABEL"] = tab_label_for(scripted)
        code, out = cli("archive", scripted.id)
        check.check(
            "the CLI's archive stops the agent too, and says so",
            code == 0
            and out.splitlines()[0] == f"{scripted.id} archived from doing"
            and "closed w1:t9" in out
            and any(call.startswith("tab close w1:t9") for call in calls()),
            out,
        )
        gone = Store.open(board).archived_by_id(scripted.id)
        check.check(
            "and the card the CLI archived has no pane left on it",
            gone is not None and gone.tab_id == "" and gone.pane_id == "",
            f"{gone.tab_id!r}" if gone else "gone",
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


async def check_tab_follows_title(check: Checker, tmp: str) -> None:
    """A card's name reaches its tab, and the board still knows the tab is its.

    The tab a dispatch opens is labelled `<id> <title>` (`dispatch.tab_label_for`),
    and that label is also how the board tells its own tab from one that was
    repurposed — `KanbanApp.agent_tab`, which is what closes the agent when the
    card is deleted. So a rename has to reach herdr (or the card and its tab
    disagree about what the work is called), and the label the board matches
    against has to be the one it actually wrote rather than one recomputed from
    the title it has since changed: a rename that only reached the card would
    make the board disown the tab it opened.
    """
    import contextlib
    import io
    import os
    from dataclasses import replace

    from .app import KanbanApp
    from .cli import run_agent_command
    from .config import load_config
    from .dispatch import Outcome, Plan, dispatch_fields, retitle_tab, tab_label_for
    from .herdr import Herdr
    from .store import Store

    board = Path(tmp) / "tab-title-board.json"
    log = Path(tmp) / "tab-title-calls.txt"
    label_file = Path(tmp) / "tab-title-label.txt"
    keys = (
        "KANBAN_BOARD_FILE",
        "HERDR_BIN_PATH",
        "HERDR_PANE_ID",
        "HERDR_ENV",
        "FAKE_LOG",
        "FAKE_CWD",
        "FAKE_TAB_LABEL",
        "FAKE_TAB_FILE",
        "FAKE_RENAME_FAIL",
    )
    saved = {key: os.environ.get(key) for key in keys}
    fake = _fake_herdr(tmp, "fake-herdr-tab-title")
    os.environ.pop("FAKE_RENAME_FAIL", None)
    os.environ.update(
        {
            "KANBAN_BOARD_FILE": str(board),
            "HERDR_BIN_PATH": str(fake),
            "HERDR_ENV": "1",
            "HERDR_PANE_ID": "w1:p9",
            "FAKE_LOG": str(log),
            "FAKE_CWD": tmp,
            "FAKE_TAB_FILE": str(label_file),
        }
    )
    try:
        store = Store.open(board)
        task = store.add(
            title="do the thing",
            agent_kind="pi",
            workspace_id="w1",
            workspace_label="nixos-config-v2",
            status="doing",
        )
        first_label = tab_label_for(task)
        os.environ["FAKE_TAB_LABEL"] = first_label  # what `tab create` left
        store.hand_over(
            task.id,
            "doing",
            pane_id="w1:p9",
            tab_id="w1:t9",
            tab_label=first_label,
            agent_name="pi",
            dispatched_at=time.time(),
        )

        # The label a dispatch writes is recorded on the card; a re-prompt of a
        # running agent writes no label, so it must not claim one.
        plan = Plan(
            task_id=task.id,
            workspace_id="w1",
            workspace_label="probe",
            kind="pi",
            name=task.slug,
            prompt="do the thing",
            tab_label=first_label,
        )
        fresh = dispatch_fields(plan, Outcome(True, tab_id="w1:t9", agent_name="pi"))
        reused = dispatch_fields(
            replace(plan, reuse_target="pi"),
            Outcome(True, tab_id="w1:t9", agent_name="pi"),
        )
        check.check(
            "a dispatch records the tab label it wrote, and a re-prompt does not",
            fresh.get("tab_label") == first_label and "tab_label" not in reused,
            f"{fresh.get('tab_label')!r} / {sorted(reused)}",
        )

        # The path an agent takes: `herdr-kanban title` renames the tab with the
        # card, because the label is the card's title too.
        log.write_text("", encoding="utf-8")
        stream = io.StringIO()
        with contextlib.redirect_stdout(stream), contextlib.redirect_stderr(stream):
            code = run_agent_command(["title", "A better name for the work"])
        renamed = Store.open(board).by_id(task.id)
        second_label = tab_label_for(renamed)
        calls = log.read_text(encoding="utf-8")
        check.check(
            "an agent's rename reaches the tab as well as the card",
            code == 0
            and renamed.title == "A better name for the work"
            and renamed.tab_label == second_label
            and f"tab rename w1:t9 {second_label}" in calls,
            f"{calls!r} {renamed.tab_label!r}",
        )

        app = KanbanApp(
            config=load_config(),
            store=Store.open(board),
            herdr=Herdr(binary=str(fake)),
        )
        async with app.run_test(size=(110, 30)) as pilot:
            await pilot.pause()
            check.check(
                "the board still calls the renamed tab its own",
                app.agent_tab(Store.open(board).by_id(task.id))[0] == "w1:t9",
                app.agent_tab(Store.open(board).by_id(task.id))[0],
            )

            # A rename herdr never accepted leaves the tab holding the label the
            # board last wrote, so the board keeps recognising it. Matching on a
            # label recomputed from the title would have lost it here.
            os.environ["FAKE_RENAME_FAIL"] = "herdr is not answering"
            log.write_text("", encoding="utf-8")
            stream = io.StringIO()
            with contextlib.redirect_stdout(stream), contextlib.redirect_stderr(stream):
                code = run_agent_command(["title", "Another name entirely"])
            failed = Store.open(board).by_id(task.id)
            check.check(
                "a tab rename herdr refused is reported, and the card is renamed",
                code == 0
                and failed.title == "Another name entirely"
                and "could not rename its tab" in stream.getvalue(),
                stream.getvalue()[:120],
            )
            check.check(
                "and the board still owns the tab it could not reach",
                failed.tab_label == second_label
                and app.agent_tab(failed)[0] == "w1:t9",
                f"{failed.tab_label!r} / {app.agent_tab(failed)[0]!r}",
            )

        # The helper on its own: nothing to do for a card with no tab.
        lonely = Store.open(board).add(title="never dispatched", workspace_id="w1")
        check.check(
            "a card with no tab needs no relabelling",
            retitle_tab(Store.open(board), lonely) == "",
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


async def check_detail_tail(check: Checker, tmp: str) -> None:
    """The agent's output is hidden until asked for, and tidied when shown."""
    import os

    from textual.widgets import Static

    from .app import KanbanApp
    from .config import load_config
    from .herdr import Agent, Herdr
    from .model import LiveState
    from .store import Store

    log = Path(tmp) / "tail-calls.txt"
    board = Path(tmp) / "tail-board.json"
    saved = {
        k: os.environ.get(k)
        for k in ("KANBAN_BOARD_FILE", "FAKE_LOG", "FAKE_REACT", "FAKE_CWD")
    }
    os.environ.update(
        {
            "KANBAN_BOARD_FILE": str(board),
            "FAKE_LOG": str(log),
            "FAKE_REACT": "1",
            "FAKE_CWD": tmp,
        }
    )
    fake = _fake_herdr(tmp, "tail-herdr")
    try:
        store = Store.open(board)
        task = store.add(
            title="a card with an agent",
            agent_kind="pi",
            workspace_id="w1",
            status="doing",
            pane_id="w1:p9",
            tab_id="w1:t9",
            agent_name="k1",
        )
        log.write_text("", encoding="utf-8")
        app = KanbanApp(
            config=load_config(), store=store, herdr=Herdr(binary=str(fake))
        )
        async with app.run_test(size=(110, 40)) as pilot:
            await pilot.pause()
            agent = Agent(
                name="k1",
                status="working",
                workspace_id="w1",
                pane_id="w1:p9",
                tab_id="w1:t9",
                cwd=tmp,
                focused=False,
                title="π - probe",
                logo="",
            )
            app.live = LiveState(
                workspaces=app.live.workspaces,
                agents={agent.name: agent},
                agents_by_pane={agent.pane_id: agent},
            )
            app.select_card(task.id)
            await pilot.press("enter")
            await pilot.pause()
            detail = app.screen
            shown = str(detail.query_one("#detail-tail", Static).render())
            calls = log.read_text(encoding="utf-8").splitlines()
            check.check(
                "the agent's output is hidden when the detail view opens",
                "hidden" in shown
                and not any(c.startswith("agent read") for c in calls),
                f"{shown!r} | {[c for c in calls if c.startswith('agent read')]}",
            )

            await pilot.press("r")
            await pilot.pause()
            for _ in range(20):
                await pilot.pause(0.05)
                if app.workers_running() == []:
                    break
            await pilot.pause()
            shown = str(detail.query_one("#detail-tail", Static).render())
            calls = log.read_text(encoding="utf-8").splitlines()
            check.check(
                "r reads the agent's output on demand",
                any(c.startswith("agent read") for c in calls),
                " | ".join(calls),
            )
            check.check(
                "and the terminal chrome is stripped out of it",
                "I finished the thing." in shown
                and "\u256d" not in shown
                and "\u2502" not in shown
                and "\u2570" not in shown,
                repr(shown),
            )

            await pilot.press("r")
            await pilot.pause()
            check.check(
                "r again hides it",
                "hidden" in str(detail.query_one("#detail-tail", Static).render()),
            )
            await pilot.press("escape")
            await pilot.pause()
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


async def check_markup(check: Checker, tmp: str) -> None:
    """Card text is shown, not parsed: markup-shaped text must not crash a dialog.

    `Static` parses its content as Textual markup unless told otherwise, and the
    board hands card text to it in a lot of places: the detail view's title,
    facts, notes, steps, updates and history, the confirm dialog's message, the
    review and dispatch notes. A card whose title or notes contain `[/tmp/x]`
    used to take its own detail view down with MarkupError. A toast parses its
    message too (`App.notify`), so the capture confirmation is driven here as
    well.
    """
    import os

    from textual.widgets import Input, Static

    from .app import KanbanApp
    from .config import load_config
    from .dispatch import Plan
    from .herdr import Herdr
    from .modals import ConfirmModal, DispatchModal, ReviewModal
    from .store import Store

    board = Path(tmp) / "markup-board.json"
    saved = os.environ.get("KANBAN_BOARD_FILE")
    os.environ["KANBAN_BOARD_FILE"] = str(board)
    try:
        store = Store.open(board)
        task = store.add(
            title="removed [/tmp/x] earlier",
            notes="see [b]this[/b] note, then [/tmp/x]",
            status="queued",
            workspace_id="w1",
            workspace_label="a[b]space",
            agent_kind="pi",
            labels=["br[ack]et"],
            title_source="agent",
            original_title="captured [/tmp/x] title",
        )
        store.add_step(task.id, "dropped [/tmp/x]")
        store.add_progress(task.id, "cleaned [/tmp/x] up")
        app = KanbanApp(
            config=load_config(), store=store, herdr=Herdr(binary="/nonexistent-herdr")
        )
        async with app.run_test(size=(110, 40)) as pilot:
            await pilot.pause()
            app.select_card(task.id)
            await pilot.press("enter")
            await pilot.pause()
            detail = app.screen
            check.check(
                "a card whose text looks like markup still opens its detail view",
                detail.__class__.__name__ == "TaskDetailModal",
                detail.__class__.__name__,
            )
            shown = {
                widget_id: str(detail.query_one(widget_id, Static).render())
                for widget_id in (
                    "#dialog-title",
                    "#detail-facts",
                    "#detail-notes",
                    "#detail-steps",
                    "#detail-updates",
                    "#detail-history",
                )
            }
            check.check(
                "and shows its title, facts, notes, steps and updates literally",
                "removed [/tmp/x] earlier" in shown["#dialog-title"]
                and "br[ack]et" in shown["#detail-facts"]
                and "[b]this[/b]" in shown["#detail-notes"]
                and "dropped [/tmp/x]" in shown["#detail-steps"]
                and "cleaned [/tmp/x] up" in shown["#detail-updates"]
                and "[/tmp/x]" in shown["#detail-history"],
                " | ".join(f"{key}={value!r}" for key, value in shown.items()),
            )
            await pilot.press("escape")
            await pilot.pause()

            # The confirm dialog puts the same title in its message.
            confirmed = ConfirmModal(
                "Delete task",
                f"Delete {task.id} — {task.title}?\n\n{task.notes}",
                confirm_label="Delete",
                danger=True,
            )
            app.push_screen(confirmed)
            await pilot.pause()
            message = str(confirmed.query_one("#confirm-message", Static).render())
            check.check(
                "the confirm dialog shows a markup-shaped message literally",
                "removed [/tmp/x] earlier" in message,
                repr(message),
            )
            await pilot.press("escape")
            await pilot.pause()

            # The review and dispatch notes carry the same text.
            review = ReviewModal(task, workspace_label="a[b]space")
            app.push_screen(review)
            await pilot.pause()
            review_note = str(review.query_one(".field-note", Static).render())
            check.check(
                "the review dialog shows a markup-shaped title literally",
                "removed [/tmp/x] earlier" in review_note,
                repr(review_note),
            )
            await pilot.press("escape")
            await pilot.pause()

            dispatch = DispatchModal(
                Plan(
                    task_id=task.id,
                    workspace_id="w1",
                    workspace_label="a[b]space",
                    kind="pi",
                    name="pi",
                    prompt="do it",
                    args=("--model", "m[1]"),
                    reuse_target="w1:p9",
                    reuse_name="agent [x]",
                    reuse_pane="w1:p9",
                ),
                app.config,
                workspaces=[],
                icon_mode="unicode",
            )
            app.push_screen(dispatch)
            await pilot.pause()
            reuse = str(dispatch.query_one("#dispatch-reuse", Static).render())
            check.check(
                "the dispatch dialog shows a markup-shaped agent name literally",
                "agent [x]" in reuse,
                repr(reuse),
            )
            await pilot.press("escape")
            await pilot.pause()

            # And the capture confirmation, which goes out as a toast.
            await pilot.press("a")
            await pilot.pause()
            form = app.screen
            form.query_one("#field-title", Input).value = "typed [/tmp/x] title"
            form.action_save()
            await pilot.pause()
            check.check(
                "a markup-shaped title still saves and confirms",
                any(
                    other.title == "typed [/tmp/x] title"
                    for other in Store.open(board).tasks
                ),
                str([other.title for other in Store.open(board).tasks]),
            )
    finally:
        if saved is None:
            os.environ.pop("KANBAN_BOARD_FILE", None)
        else:
            os.environ["KANBAN_BOARD_FILE"] = saved


async def check_edit_title(check: Checker, tmp: str) -> None:
    """Saving the edit form must not write back a title the human never typed.

    The form is built from the card as it looked when it opened. An agent can
    rename the card while the dialog is up — that is the point of the protocol —
    and the draft still carries the old title. Sending it unconditionally
    reverts the rename, silently, and leaves `✎` on a title the agent never
    chose, which is indistinguishable from the naming step never running.
    """
    from dataclasses import replace

    from .app import KanbanApp
    from .config import load_config
    from .dispatch import tab_label_for
    from .herdr import Herdr
    from .modals import TaskDraft

    board = Path(tmp) / "edit-title-board.json"
    log = Path(tmp) / "edit-title-calls.txt"
    label_file = Path(tmp) / "edit-title-label.txt"
    env_keys = (
        "KANBAN_BOARD_FILE",
        "HERDR_WORKSPACE_ID",
        "HERDR_PANE_ID",
        "FAKE_LOG",
        "FAKE_REACT",
        "FAKE_CWD",
        "FAKE_TAB_FILE",
    )
    saved_env = {key: os.environ.get(key) for key in env_keys}
    for key in env_keys:
        os.environ.pop(key, None)
    log.write_text("", encoding="utf-8")
    os.environ.update(
        {
            "KANBAN_BOARD_FILE": str(board),
            "HERDR_WORKSPACE_ID": "w1",
            "FAKE_LOG": str(log),
            "FAKE_REACT": "1",
            "FAKE_CWD": tmp,
            "FAKE_TAB_FILE": str(label_file),
        }
    )
    fake = _fake_herdr(tmp, "fake-herdr-edit")

    def draft_of(task: Task, **overrides: object) -> TaskDraft:
        """The draft `TaskFormModal` would hand back for `task`."""
        fields: dict[str, object] = {
            "title": task.title,
            "notes": task.notes,
            "status": task.status,
            "workspace_id": task.workspace_id,
            "workspace_label": task.workspace_label,
            "agent_kind": task.agent_kind,
            "agent_model": task.agent_model,
            "priority": task.priority,
            "labels": list(task.labels),
        }
        fields.update(overrides)
        return TaskDraft(**fields)

    async def save(draft: TaskDraft, task: Task) -> None:
        app = KanbanApp(
            config=replace(load_config(), announce_protocol=True),
            store=Store.open(board),
            herdr=Herdr(binary=str(fake)),
        )
        async with app.run_test(size=(120, 36)) as pilot:
            await pilot.pause()
            app.on_edit(draft, task)
            await pilot.pause()

    try:
        seeded = Store.open(board)
        card = seeded.add(
            title="ctrl+c in herdr kanban plugin should exit",
            workspace_id="w1",
            workspace_label="nixos-config-v2",
        )

        # The form opens on the capture title, the agent names the card while it
        # is up, and the human saves a different field.
        stale = Store.open(board).by_id(card.id)
        opened = Store.open(board)
        opened.set_title(card.id, "Bind ctrl+c to quit the board", source="agent")
        await save(draft_of(stale, priority="high"), stale)

        kept = Store.open(board).by_id(card.id)
        check.check(
            "saving the edit form does not revert an agent's rename",
            kept.title == "Bind ctrl+c to quit the board"
            and kept.priority == "high"
            and not kept.title_edited,
            f"{kept.title!r} {kept.priority!r} edited={kept.title_edited}",
        )

        # A title the human actually typed still claims the card.
        human = Store.open(board).by_id(card.id)
        await save(draft_of(human, title="Quit the board with ctrl+c"), human)
        claimed = Store.open(board).by_id(card.id)
        check.check(
            "a title the human typed in the form still claims the card",
            claimed.title == "Quit the board with ctrl+c"
            and claimed.title_edited
            and claimed.title_source == "user",
            f"{claimed.title!r} {claimed.title_source} {claimed.title_edited}",
        )

        # A rename typed in the form reaches the tab too: the tab carries the
        # card's name, and the board recognises its own tab by that label, so a
        # card renamed in the board while its tab kept the old name would leave
        # the board unable to close the agent it started.
        tabbed = Store.open(board)
        tabbed.update(
            card.id,
            pane_id="w1:p9",
            tab_id="w1:t9",
            tab_label=tab_label_for(tabbed.by_id(card.id)),
        )
        log.write_text("", encoding="utf-8")
        stale = Store.open(board).by_id(card.id)
        await save(draft_of(stale, title="The board owns the tab name"), stale)
        renamed = Store.open(board).by_id(card.id)
        calls = log.read_text(encoding="utf-8")
        check.check(
            "a rename typed in the form renames the card's tab with it",
            renamed.title == "The board owns the tab name"
            and renamed.tab_label == tab_label_for(renamed)
            and f"tab rename w1:t9 {tab_label_for(renamed)}" in calls,
            f"{calls!r} {renamed.tab_label!r}",
        )
    finally:
        for key, value in saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


async def check_quit(check: Checker, tmp: str) -> None:
    """Ctrl+C has to quit — from the board and from a dialog.

    Textual binds ctrl+c to a "press q to quit" toast of its own, which inside a
    herdr overlay is a key that appears to do nothing, and `q` is not the reflex
    key. A dialog is the case worth pinning: its focused Input is the widget
    Textual keeps ctrl+c for.
    """

    async def quitting(press: list[str], label: str, stem: str) -> None:
        app = KanbanApp(
            config=load_config(_pin_config(tmp)),
            store=Store.open(Path(tmp) / f"{stem}.json"),
            herdr=Herdr(binary="/nonexistent-herdr"),
            demo=True,
        )
        async with app.run_test(size=(120, 36)) as pilot:
            await pilot.pause()
            for key in press[:-1]:
                await pilot.press(key)
                await pilot.pause()
            opened = app.screen.__class__.__name__
            focused = app.focused.__class__.__name__ if app.focused else "-"
            await pilot.press(press[-1])
            await pilot.pause()
            check.check(
                f"ctrl+c quits {label}",
                app._exit,
                f"{opened} / {focused}",
            )

    await quitting(["ctrl+c"], "the board", "quit-board")
    await quitting(["a", "ctrl+c"], "a dialog", "quit-dialog")


async def _run(check: Checker) -> None:
    with TemporaryDirectory() as tmp:
        # A check must not inherit the pane it was run from. `herdr-kanban add`
        # reads HERDR_PANE_ID (who filed the card), HERDR_WORKSPACE_ID (where —
        # which now decides the card's id code) and HERDR_BIN_PATH (which binary
        # to ask about workspaces), and this selftest runs inside a herdr pane
        # often enough — as a pre-commit hook — that inheriting them would make
        # the answer depend on the terminal. Checks that need herdr set what
        # they need themselves; the pin is a binary that cannot answer, so a
        # workspace lookup fails the same way everywhere.
        pane_env = {
            key: value for key, value in os.environ.items() if key.startswith("HERDR_")
        }
        for key in pane_env:
            os.environ.pop(key, None)
        os.environ["HERDR_BIN_PATH"] = str(Path(tmp) / "no-such-herdr")

        saved = os.environ.get("KANBAN_CONFIG_FILE")
        saved_notify = os.environ.get("KANBAN_NOTIFY_CMD")
        os.environ["KANBAN_CONFIG_FILE"] = str(_pin_config(tmp))
        # A real desktop banner must never fire during the checks; the one check
        # that wants to see a banner points this at a script that logs instead.
        os.environ["KANBAN_NOTIFY_CMD"] = "true"
        try:
            check_store(check, tmp)
            check_list_order(check, tmp)
            check_pane_args(check, tmp)
            check_ids(check, tmp)
            check_counters(check, tmp)
            check_archive(check, tmp)
            check_rename(check, tmp)
            check_assign(check, tmp)
            check_agent_protocol(check, tmp)
            check_add_notification(check, tmp)
            check_status_rights(check, tmp)
            await check_quick_capture(check, tmp)
            await check_multiline_notes(check, tmp)
            await check_extras(check, tmp)
            check_hardening(check, tmp)
            await check_dialogs(check, tmp)
            await check_send_now(check, tmp)
            await check_review_bounce(check, tmp)
            await check_worktree_dispatch(check, tmp)
            await check_edit_title(check, tmp)
            await check_live_loop(check, tmp)
            check_settle_columns(check, tmp)
            check_pane_identity(check, tmp)
            check_live_staleness(check, tmp)
            check_sync_daemon(check, tmp)
            check_prompt_delivery(check, tmp)
            check_send_records_unconfirmed(check, tmp)
            await check_dispatch_record_survives_close(check, tmp)
            check_dispatch_env(check, tmp)
            await check_delete_stops_agent(check, tmp)
            await check_archive_stops_agent(check, tmp)
            await check_tab_follows_title(check, tmp)
            await check_detail_tail(check, tmp)
            await check_markup(check, tmp)
            await check_quit(check, tmp)
        finally:
            if saved is None:
                os.environ.pop("KANBAN_CONFIG_FILE", None)
            else:
                os.environ["KANBAN_CONFIG_FILE"] = saved
            if saved_notify is None:
                os.environ.pop("KANBAN_NOTIFY_CMD", None)
            else:
                os.environ["KANBAN_NOTIFY_CMD"] = saved_notify
        store = Store(Path(tmp) / "board.json")
        store.load()
        app = KanbanApp(
            # Pinned explicitly, not through the environment: this block sits
            # outside the `finally` that restores KANBAN_CONFIG_FILE, so a bare
            # `load_config()` here read whatever config the machine happens to
            # have deployed — and a check whose answer depends on that is not a
            # check. (It failed exactly once: when the demo board's columns moved
            # ahead of the deployed config's.)
            config=load_config(_pin_config(tmp)),
            store=store,
            herdr=Herdr(binary="/nonexistent-herdr"),
            demo=True,
        )
        async with app.run_test(size=(140, 40)) as pilot:
            await pilot.pause()

            view = app.current_view()
            check.check(
                "the board draws one column per configured column",
                len(view.columns) == len(app.config.columns),
                f"{len(view.columns)} columns for {len(app.config.columns)}",
            )
            check.check(
                "demo cards are placed",
                sum(column.count for column in view.columns) == 8,
                str([column.count for column in view.columns]),
            )
            check.check("a card is selected on open", bool(app.ui.selected_id))

            # A card follows the agent its dispatch started: the pane it
            # recorded, confirmed against the name herdr reports for it (the
            # kind label, `pi`, is what a pane without a name falls back to).
            k3 = app.task("cfg-3")
            status, online = app.live.for_task(k3) if k3 else ("", False)
            check.check(
                "a card follows the agent its dispatch started, by pane and name",
                k3 is not None and online and status == "working",
                f"{k3.agent_name if k3 else '-'} -> {status}",
            )
            blocked = [c for c in app.current_view().cards() if c.status == "blocked"]
            check.check(
                "a blocked agent is reflected on its card",
                any(c.task.id == "work-1" for c in blocked),
                str([c.task.id for c in blocked]),
            )

            # cursor ------------------------------------------------------
            start = app.ui.selected_id
            await pilot.press("j")
            check.check("j moves down a card", app.ui.selected_id != start)
            await pilot.press("k")
            check.check("k moves back up", app.ui.selected_id == start)
            column_before = app.ui.selected_column
            await pilot.press("l")
            check.check(
                "l moves right a column", app.ui.selected_column != column_before
            )
            await pilot.press("h")
            check.check("h moves back left", app.ui.selected_column == column_before)
            await pilot.press("5")
            check.check("digits jump to a column", app.ui.selected_column == 4)
            await pilot.press("1")
            check.check("back to the first column", app.ui.selected_column == 0)
            await pilot.press("G")
            check.check(
                "G selects the last card in the column", bool(app.ui.selected_id)
            )

            # moving between columns --------------------------------------
            task = app.selected_task()
            assert task is not None
            origin = task.status
            await pilot.press("L")
            check.check(
                "L moves the card to the next column",
                task.status != origin,
                f"{origin} -> {task.status}",
            )
            check.check(
                "the move says where it came from and where it went",
                app.ui.notice
                == (
                    f"{task.id} · {app.config.label_for(origin)}"
                    f" → {app.config.label_for(task.status)}"
                ),
                app.ui.notice,
            )
            await pilot.press("H")
            check.check("H moves it back", task.status == origin)

            # reordering --------------------------------------------------
            column_cards = [
                card.task.id
                for card in app.current_view().columns[app.ui.selected_column].cards
            ]
            if len(column_cards) > 1:
                app.select_card(column_cards[0])
                await pilot.press("J")
                after = [
                    card.task.id
                    for card in app.current_view().columns[app.ui.selected_column].cards
                ]
                check.check("J reorders inside the column", after != column_cards)
            else:
                check.check("J reorders inside the column", True, "single-card column")

            # ...and the default sort, where there is no manual order to edit --
            if app.selected_task() is not None:
                app.config.sort = "updated"
                sorted_before = [
                    card.task.id
                    for card in app.current_view().columns[app.ui.selected_column].cards
                ]
                await pilot.press("J")
                await pilot.pause()
                sorted_after = [
                    card.task.id
                    for card in app.current_view().columns[app.ui.selected_column].cards
                ]
                check.check(
                    "J refuses while the column is sorted, and names the way back",
                    sorted_after == sorted_before
                    and 'sort = "manual"' in app.ui.notice
                    and "config.toml" in app.ui.notice,
                    app.ui.notice,
                )
                app.config.sort = "manual"
                app.refresh_board()
                await pilot.pause()

            # filter ------------------------------------------------------
            await pilot.press("slash")
            await pilot.press(*"flake")
            await pilot.press("enter")
            await pilot.pause()
            check.check("filter text is applied", app.ui.filter_text == "flake")
            check.check(
                "filter hides non-matching cards",
                app.current_view().hidden_total > 0,
                str(app.current_view().hidden_total),
            )
            app.action_clear_filters()
            await pilot.pause()
            check.check(
                "clearing the filter restores every card",
                app.current_view().hidden_total == 0,
            )

            # add a task --------------------------------------------------
            before = len(app.tasks())
            await pilot.press("a")
            await pilot.pause()
            await pilot.press(*"Write selftest coverage")
            await pilot.press("enter")
            await pilot.pause()
            created = app.tasks()[-1] if len(app.tasks()) > before else None
            check.check("a adds a task", len(app.tasks()) == before + 1)
            check.check(
                "the new task carries a workspace and an agent",
                created is not None
                and bool(created.workspace_id)
                and bool(created.agent_kind),
                f"{created.workspace_id if created else '-'} / {created.agent_kind if created else '-'}",
            )
            check.check(
                "the new task lands in the default column",
                created is not None and created.status == app.config.default_column,
            )
            if created is not None:
                check.check(
                    "the add form trimmed the title to what was typed",
                    created.title == "Write selftest coverage",
                    repr(created.title),
                )

            # dialogs -----------------------------------------------------
            app.select_card(created.id if created else app.tasks()[0].id)
            await pilot.press("s")
            await pilot.pause()
            check.check(
                "s opens the dispatch form",
                app.screen.__class__.__name__ == "DispatchModal",
            )
            await pilot.press("escape")
            await pilot.pause()

            await pilot.press("enter")
            await pilot.pause()
            check.check(
                "⏎ opens the detail view",
                app.screen.__class__.__name__ == "TaskDetailModal",
            )
            await pilot.press("escape")
            await pilot.pause()

            await pilot.press("question_mark")
            await pilot.pause()
            check.check("? opens help", app.screen.__class__.__name__ == "HelpModal")
            await pilot.press("escape")
            await pilot.pause()

            count_before = len(app.tasks())
            await pilot.press("d")
            await pilot.pause()
            check.check(
                "d asks before deleting",
                app.screen.__class__.__name__ == "ConfirmModal",
            )
            await pilot.press("escape")
            await pilot.pause()
            check.check(
                "cancelling delete keeps the task", len(app.tasks()) == count_before
            )

            # archive -----------------------------------------------------
            target = app.selected_task()
            tasks_before = len(app.tasks())
            archived_before = len(app._demo_archived)
            await pilot.press("A")
            await pilot.pause()
            check.check(
                "A archives the selected card instead of deleting it",
                target is not None
                and len(app.tasks()) == tasks_before - 1
                and len(app._demo_archived) == archived_before + 1
                and app._demo_archived[-1].id == target.id,
                app.ui.notice,
            )
            check.check(
                "archiving names the command that brings the card back",
                "unarchive" in app.ui.notice,
                app.ui.notice,
            )

            # the archived column (`v`) -----------------------------------
            check.check(
                "the archived column is hidden by default",
                all(c.column.id != "archived" for c in app.current_view().columns),
            )
            await pilot.press("v")
            await pilot.pause()
            shown = [c for c in app.current_view().columns if c.column.id == "archived"]
            check.check(
                "v shows the archived column with the archived card in it",
                len(shown) == 1 and [c.task.id for c in shown[0].cards] == [target.id],
                app.ui.notice,
            )
            app.select_card(target.id)
            await pilot.pause()
            check.check(
                "an archived card can be selected in its column",
                app.selected_task() is not None and app.selected_task().id == target.id,
            )
            status_before = target.status
            await pilot.press("L")
            await pilot.pause()
            check.check(
                "moving an archived card is refused",
                target.status == status_before and "archived" in app.ui.notice,
                app.ui.notice,
            )
            await pilot.press("u")
            await pilot.pause()
            check.check(
                "u unarchives the selected card",
                target.id not in [t.id for t in app._demo_archived]
                and target.id in [t.id for t in app.tasks()],
                app.ui.notice,
            )
            check.check(
                "unarchiving says which column it went back to",
                "restored to" in app.ui.notice,
                app.ui.notice,
            )
            await pilot.press("v")
            await pilot.pause()
            check.check(
                "v hides the archived column again",
                all(c.column.id != "archived" for c in app.current_view().columns),
            )

            # a card with notes AND updates mounts two detail Statics — they
            # used to share one id and the modal died on MountError.
            from .modals import TaskDetailModal

            noted = TaskDetailModal(
                task=Task(
                    id="KZ",
                    title="notes and updates",
                    notes="why this exists",
                    status="queued",
                    created_at=time.time(),
                    updated_at=time.time(),
                    progress=[
                        {"at": time.time(), "by": "agent", "text": "did a thing"}
                    ],
                ),
                config=app.config,
                herdr=app.herdr,
                icon_mode="unicode",
            )
            app.push_screen(noted)
            await pilot.pause()
            await pilot.pause()
            check.check(
                "⏎ opens the detail view on a card with notes and updates",
                app.screen.__class__.__name__ == "TaskDetailModal",
            )
            await pilot.press("escape")
            await pilot.pause()

            # rendering ---------------------------------------------------
            snapshot, _ = render_board(app.current_view())
            check.check(
                "the board fills the screen exactly",
                len(snapshot) == app.current_view().height,
                f"{len(snapshot)} lines for {app.current_view().height} rows",
            )
            await pilot.resize_terminal(48, 12)
            await pilot.pause()
            small = app.current_view()
            check.check("survives a tiny pane", small.width >= 40 and small.height >= 6)


def check_dispatch_env(check: Checker, tmp: str) -> None:
    """A dispatch tab carries the marker that tells a shell to skip direnv.

    The board's tab is a vehicle for the agent, not a dev session: without the
    marker a repo with a dev shell — this one — pays `nix print-dev-env` and
    prints the dev-shell banner into the pane while `agent start` is still
    waiting for a prompt (modules/home/zsh.nix, docs/kanban.md).
    """
    import os

    from .dispatch import Executor, Plan
    from .herdr import Herdr

    log = Path(tmp) / "tab-create-calls.txt"
    saved = {k: os.environ.get(k) for k in ("FAKE_LOG", "FAKE_REACT", "FAKE_CWD")}
    os.environ["FAKE_LOG"] = str(log)
    os.environ["FAKE_REACT"] = "1"
    os.environ["FAKE_CWD"] = tmp
    try:
        herdr = Herdr(binary=str(_fake_herdr(tmp, "fake-herdr-tab")))
        log.write_text("", encoding="utf-8")
        plan = Plan(
            task_id="K1",
            workspace_id="w1",
            workspace_label="probe",
            kind="pi",
            name="k1",
            prompt="do the thing",
            tab_label="K1 do the thing",
        )
        outcome = Executor(herdr).run(plan)
        creates = [
            line
            for line in log.read_text(encoding="utf-8").splitlines()
            if line.startswith("tab create")
        ]
        check.check(
            "a dispatched tab is created with the direnv-skipping marker",
            outcome.ok
            and any("--env HERDR_KANBAN_DISPATCH=1" in line for line in creates),
            " | ".join(creates),
        )

        log.write_text("", encoding="utf-8")
        herdr.create_tab("w1", label="mine", cwd=tmp)
        check.check(
            "a tab created without env markers gets no --env argument",
            "--env" not in log.read_text(encoding="utf-8"),
        )
    finally:
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def run_selftest(args: argparse.Namespace | None = None) -> int:
    del args
    check = Checker()
    print("herdr-kanban selftest")
    asyncio.run(_run(check))
    print()
    if check.failures:
        print(f"{len(check.failures)} check(s) failed: {', '.join(check.failures)}")
        return 1
    print(f"all {check.passed} checks passed")
    return 0
