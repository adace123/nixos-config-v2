"""Sample data for `--demo` and `--snapshot`.

Lets the board be looked at (and screenshotted) without touching the real board
file or requiring a running herdr server — including the states that are hard to
reproduce on demand: a blocked agent, a closed workspace, an agent that exited.
"""

from __future__ import annotations

import time

from .herdr import Agent, Workspace
from .model import LiveState
from .store import Task

_NOW = time.time()


def _task(
    task_id: str,
    title: str,
    status: str,
    workspace_id: str,
    workspace_label: str,
    kind: str = "pi",
    **extra: object,
) -> Task:
    task = Task(
        id=task_id,
        title=title,
        status=status,
        workspace_id=workspace_id,
        workspace_label=workspace_label,
        agent_kind=kind,
        agent_name=extra.pop("agent_name", f"{task_id.lower()}-{kind}"),  # type: ignore[arg-type]
        created_at=_NOW - 3600 * 4,
        updated_at=_NOW - 600,
        **extra,  # type: ignore[arg-type]
    )
    return task


def demo_tasks() -> list[Task]:
    return [
        _task(
            "K1",
            "Fix flake lock drift after nixpkgs bump",
            "backlog",
            "w1",
            "nixos-config-v2",
            notes="The llm-agents input pins a different nixpkgs than the lock.",
            priority="high",
        ),
        _task(
            "K2",
            "Tidy the nixvim treesitter grammar exclusions",
            "backlog",
            "w1",
            "nixos-config-v2",
            kind="claude",
        ),
        _task(
            "K3",
            "Add herdr kanban board plugin",
            "doing",
            "w1",
            "nixos-config-v2",
            dispatched_at=_NOW - 900,
            pane_id="w1:p9",
            tab_id="w1:t4",
            # Named by the agent after it started, and keeping its own card
            # current — what the protocol is for. This is also the only demo
            # card carrying notes, updates *and* steps at once, so every
            # `--screen detail` snapshot exercises all three sections.
            title_source="agent",
            original_title="kanban board",
            notes="Board, dispatch and the agent protocol. Keep the pane honest.",
            steps=[
                {
                    "text": "renderer and store",
                    "done": True,
                    "at": _NOW - 800,
                    "by": "agent",
                },
                {
                    "text": "dispatch + protocol",
                    "done": True,
                    "at": _NOW - 600,
                    "by": "agent",
                },
                {"text": "document the verbs", "done": False, "at": 0.0, "by": ""},
            ],
            progress=[
                {
                    "at": _NOW - 800,
                    "by": "agent",
                    "text": "renderer and store are in; wiring dispatch",
                },
                {
                    "at": _NOW - 240,
                    "by": "agent",
                    "text": "pane-first agent lookup: herdr reports the kind, not the name",
                },
            ],
            # The board's own record of the card, as opposed to the agent's
            # narrative above — this is what the detail view's History section
            # shows, so the demo card carries one of each kind of entry.
            history=[
                {"at": _NOW - 3600, "what": "created in backlog by agent"},
                {"at": _NOW - 3500, "what": "backlog -> todo"},
                {"at": _NOW - 900, "what": "todo -> doing"},
                {
                    "at": _NOW - 880,
                    "what": "title set by agent: Add herdr kanban board plugin",
                },
            ],
        ),
        _task(
            "K4",
            "Review the tsk board integration",
            "review",
            "w8",
            "argo",
            kind="codex",
            agent_name="k4-codex",
            dispatched_at=_NOW - 7200,
            pane_id="w8:p3",
        ),
        _task(
            "K5",
            "Bump the pi package pins",
            "queued",
            "wB",
            "personal",
            kind="amp",
            notes="Some git/npm versions intentionally differ — check before bumping.",
        ),
        _task(
            "K6",
            "Ship the sidebars and the theme",
            "queued",
            "w4",
            "work",
            kind="claude",
            priority="urgent",
            agent_name="reviewer",
            dispatched_at=_NOW - 600,
            pane_id="w4:p1",
            progress=[
                {
                    "at": _NOW - 120,
                    "by": "agent",
                    "text": "blocked: needs the production client id",
                },
            ],
        ),
        _task(
            "K7",
            "Write release notes for the SD image workflow",
            "done",
            "w6",
            "snowflake-reporting",
            kind="gemini",
            dispatched_at=_NOW - 86400,
        ),
        _task(
            "K8",
            "Investigate flaky worktree trust prompt",
            "doing",
            "w9",
            "jupyter",
            kind="opencode",
            priority="urgent",
            agent_name="k8-opencode",
            dispatched_at=_NOW - 5400,
            pane_id="w9:p2",
        ),
    ]


def demo_live() -> LiveState:
    """Sample herdr state.

    Agent labels are what herdr actually reports for an agent that was started
    without a name — the kind ("pi"), not the name we passed to
    `agent start`. The board must therefore match cards to agents by pane ID;
    this data is what keeps that honest in `--demo` and the selftest.
    """
    workspaces = [
        Workspace("w1", "nixos-config-v2", 1, "w1:t4", "working"),
        Workspace("w4", "work", 2, "w4:t1", "blocked"),
        Workspace("w6", "snowflake-reporting", 3, "w6:t1", "unknown"),
        Workspace("w8", "argo", 4, "w8:t1", "idle"),
        Workspace("wB", "personal", 5, "wB:t1", "unknown"),
        Workspace("w9", "jupyter", 6, "w9:t1", "working"),
    ]
    agents = [
        Agent(
            "pi",
            "working",
            "w1",
            "w1:p9",
            "w1:t4",
            "/Users/aaron/Projects/personal/nixos-config-v2",
            True,
            "π - nixos-config-v2",
            "",
        ),
        Agent(
            "codex",
            "idle",
            "w8",
            "w8:p3",
            "w8:t1",
            "/Users/aaron/Projects/work/argo",
            False,
            "codex - argo",
            "",
        ),
        Agent(
            "opencode",
            "working",
            "w9",
            "w9:p2",
            "w9:t1",
            "/Users/aaron/Projects/work/jupyter",
            False,
            "opencode - jupyter",
            "",
        ),
        Agent(
            "claude",
            "blocked",
            "w4",
            "w4:p1",
            "w4:t1",
            "/Users/aaron/Projects/work",
            False,
            "claude - work",
            "",
        ),
    ]
    return LiveState(
        workspaces={workspace.id: workspace for workspace in workspaces},
        agents={agent.name: agent for agent in agents},
        agents_by_pane={agent.pane_id: agent for agent in agents},
    )
