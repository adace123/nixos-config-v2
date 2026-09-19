"""Herdr's CLI is the plugin API — this is the thin, non-raising wrapper.

Every call goes through `HERDR_BIN_PATH` (injected by herdr) so the plugin stays
portable across the Unix socket and Windows named pipes, and every failure comes
back as a `Result` instead of an exception: a board refresh must never take the
UI down because a workspace was closed mid-poll.
"""

from __future__ import annotations

import json
import os
import subprocess
from collections.abc import Sequence
from dataclasses import dataclass, field
from typing import Any

DEFAULT_TIMEOUT = 8.0
START_TIMEOUT = 45.0

AGENT_STATUSES = ("working", "blocked", "idle", "done", "unknown")


@dataclass(frozen=True)
class Result:
    ok: bool
    payload: dict[str, Any] | None = None
    code: str = ""
    message: str = ""
    text: str = ""

    @property
    def data(self) -> dict[str, Any]:
        """The `result` object of a successful call (or the payload itself)."""
        payload = self.payload or {}
        result = payload.get("result")
        return result if isinstance(result, dict) else payload

    def error_text(self) -> str:
        if self.code and self.message:
            return f"{self.code}: {self.message}"
        return self.message or self.code or "herdr call failed"


@dataclass(frozen=True)
class Workspace:
    id: str
    label: str
    number: int
    active_tab_id: str
    agent_status: str
    tokens: dict[str, str] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Workspace:
        tokens = data.get("tokens")
        return cls(
            id=str(data.get("workspace_id") or ""),
            label=str(data.get("label") or data.get("workspace_id") or ""),
            number=int(data.get("number") or 0),
            active_tab_id=str(data.get("active_tab_id") or ""),
            agent_status=str(data.get("agent_status") or "unknown"),
            tokens=tokens if isinstance(tokens, dict) else {},
        )


@dataclass(frozen=True)
class Agent:
    """A live agent in a pane. `name` is herdr's unique live agent name."""

    name: str
    status: str
    workspace_id: str
    pane_id: str
    tab_id: str
    cwd: str
    focused: bool
    title: str
    logo: str

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Agent:
        tokens = data.get("tokens")
        tokens = tokens if isinstance(tokens, dict) else {}
        logo = str(
            data.get("harness_logo")
            or tokens.get("harness_logo")
            or tokens.get("logo")
            or ""
        )
        return cls(
            name=str(data.get("agent") or ""),
            status=str(data.get("agent_status") or "unknown"),
            workspace_id=str(data.get("workspace_id") or ""),
            pane_id=str(data.get("pane_id") or ""),
            tab_id=str(data.get("tab_id") or ""),
            cwd=str(data.get("cwd") or ""),
            focused=bool(data.get("focused")),
            title=str(
                data.get("terminal_title_stripped") or data.get("terminal_title") or ""
            ),
            logo=logo,
        )


@dataclass(frozen=True)
class Pane:
    id: str
    workspace_id: str
    tab_id: str
    cwd: str
    agent_name: str
    focused: bool

    @property
    def has_agent(self) -> bool:
        return bool(self.agent_name)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Pane:
        return cls(
            id=str(data.get("pane_id") or ""),
            workspace_id=str(data.get("workspace_id") or ""),
            tab_id=str(data.get("tab_id") or ""),
            cwd=str(data.get("cwd") or ""),
            agent_name=str(data.get("agent") or ""),
            focused=bool(data.get("focused")),
        )


def _parse_json(text: str) -> dict[str, Any] | None:
    text = text.strip()
    if not text.startswith("{"):
        return None
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return None
    return parsed if isinstance(parsed, dict) else None


def _tail(text: str, limit: int = 200) -> str:
    collapsed = " ".join(text.split())
    return collapsed[-limit:] if len(collapsed) > limit else collapsed


class Herdr:
    """Subset of the herdr CLI the board needs."""

    def __init__(
        self, binary: str | None = None, timeout: float = DEFAULT_TIMEOUT
    ) -> None:
        self.binary = binary or os.environ.get("HERDR_BIN_PATH") or "herdr"
        self.timeout = timeout
        self.available = True
        self.last_error = ""

    # -- plumbing --------------------------------------------------------

    def _run(self, *args: str, timeout: float | None = None) -> Result:
        try:
            proc = subprocess.run(
                [self.binary, *args],
                capture_output=True,
                text=True,
                timeout=timeout or self.timeout,
                check=False,
            )
        except FileNotFoundError:
            self.available = False
            return Result(
                False, code="herdr_missing", message=f"{self.binary} not found"
            )
        except subprocess.TimeoutExpired:
            return Result(
                False, code="timeout", message=f"herdr {' '.join(args)} timed out"
            )
        except OSError as exc:  # pragma: no cover - exotic exec failures
            return Result(False, code="exec_failed", message=str(exc))

        payload = _parse_json(proc.stdout) or _parse_json(proc.stderr)
        if payload is None:
            message = _tail(proc.stdout or proc.stderr or "no output")
            return Result(
                False, code="unexpected_output", message=message, text=proc.stdout
            )
        error = payload.get("error")
        if error is not None:
            if isinstance(error, dict):
                return Result(
                    False,
                    payload=payload,
                    code=str(error.get("code") or "error"),
                    message=str(error.get("message") or ""),
                )
            # A present-but-odd error shape is still a failure, never a success.
            return Result(False, payload=payload, code="error", message=str(error))
        if proc.returncode != 0:
            return Result(
                False,
                payload=payload,
                code="exit_status",
                message=f"herdr {' '.join(args)} exited {proc.returncode}",
            )
        return Result(True, payload=payload, text=proc.stdout)

    def _read(self, *args: str, timeout: float | None = None) -> Result:
        """For commands that print text rather than JSON (`agent read`)."""
        try:
            proc = subprocess.run(
                [self.binary, *args],
                capture_output=True,
                text=True,
                timeout=timeout or self.timeout,
                check=False,
            )
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError) as exc:
            return Result(False, code="read_failed", message=str(exc))
        if proc.returncode != 0:
            # Failures come back as JSON on stderr, like every other command.
            payload = _parse_json(proc.stderr)
            error = payload.get("error") if payload else None
            if isinstance(error, dict):
                return Result(
                    False,
                    payload=payload,
                    code=str(error.get("code") or "read_failed"),
                    message=str(error.get("message") or ""),
                )
            if error is not None:
                return Result(False, payload=payload, code="error", message=str(error))
            return Result(
                False,
                code="read_failed",
                message=_tail(proc.stderr or proc.stdout),
                text="",
            )
        return Result(True, text=proc.stdout)

    # -- reads -----------------------------------------------------------

    def workspaces(self) -> tuple[list[Workspace], Result]:
        result = self._run("workspace", "list")
        if not result.ok:
            return [], result
        raw = result.data.get("workspaces")
        items = raw if isinstance(raw, list) else []
        return [
            Workspace.from_dict(item) for item in items if isinstance(item, dict)
        ], result

    def agents(self) -> tuple[list[Agent], Result]:
        result = self._run("agent", "list")
        if not result.ok:
            return [], result
        raw = result.data.get("agents")
        items = raw if isinstance(raw, list) else []
        return [
            Agent.from_dict(item) for item in items if isinstance(item, dict)
        ], result

    def panes(self, workspace_id: str | None = None) -> tuple[list[Pane], Result]:
        args = ["pane", "list"]
        if workspace_id:
            args += ["--workspace", workspace_id]
        result = self._run(*args)
        if not result.ok:
            return [], result
        raw = result.data.get("panes")
        items = raw if isinstance(raw, list) else []
        return [
            Pane.from_dict(item) for item in items if isinstance(item, dict)
        ], result

    def read_agent(self, target: str, lines: int = 40) -> Result:
        return self._read(
            "agent",
            "read",
            target,
            "--source",
            "recent-unwrapped",
            "--lines",
            str(lines),
        )

    @staticmethod
    def agent_target(pane_id: str = "", agent_name: str = "") -> str:
        """What to hand to an `agent` subcommand.

        herdr accepts a live agent name or the pane hosting it, but the `agent`
        field of `agent list` is a kind label (an unnamed agent reports "pi"),
        so the pane ID is the only target that is reliably unique.
        """
        return pane_id or agent_name

    def context(self) -> dict[str, Any]:
        """The invocation context herdr injected for the action that opened us."""
        raw = os.environ.get("HERDR_PLUGIN_CONTEXT_JSON") or ""
        parsed = _parse_json(raw) if raw else None
        return parsed or {}

    def current_workspace(self) -> str:
        """The workspace the board was launched from, if herdr told us."""
        for key in ("workspace_id", "workspace", "focused_workspace_id"):
            value = self.context().get(key)
            if isinstance(value, str) and value:
                return value
        return os.environ.get("HERDR_WORKSPACE_ID", "")

    def current_cwd(self) -> str:
        context = self.context()
        for key in ("focused_pane_cwd", "workspace_cwd", "cwd"):
            value = context.get(key)
            if isinstance(value, str) and value:
                return value
        return ""

    # -- mutations -------------------------------------------------------

    def focus_workspace(self, workspace_id: str) -> Result:
        return self._run("workspace", "focus", workspace_id)

    def focus_agent(self, target: str) -> Result:
        return self._run("agent", "focus", target)

    def focus_pane(self, pane_id: str) -> Result:
        return self._run("pane", "focus", pane_id)

    def create_tab(
        self, workspace_id: str, label: str = "", cwd: str = "", focus: bool = False
    ) -> Result:
        args = ["tab", "create"]
        if workspace_id:
            args += ["--workspace", workspace_id]
        if label:
            args += ["--label", label]
        if cwd:
            args += ["--cwd", cwd]
        args.append("--focus" if focus else "--no-focus")
        return self._run(*args)

    def split_pane(
        self,
        pane_id: str,
        direction: str = "right",
        cwd: str = "",
        focus: bool = False,
    ) -> Result:
        args = ["pane", "split", "--pane", pane_id, "--direction", direction]
        if cwd:
            args += ["--cwd", cwd]
        args.append("--focus" if focus else "--no-focus")
        return self._run(*args)

    def start_agent(
        self,
        name: str,
        kind: str,
        pane_id: str,
        args: Sequence[str] = (),
        timeout: float = START_TIMEOUT,
    ) -> Result:
        argv = [
            "agent",
            "start",
            name,
            "--kind",
            kind,
            "--pane",
            pane_id,
            "--timeout",
            str(int(timeout * 1000)),
        ]
        if args:
            # Everything after `--` is the agent's own command line.
            argv += ["--", *args]
        return self._run(*argv, timeout=timeout + 5.0)

    def prompt_agent(self, target: str, text: str) -> Result:
        return self._run("agent", "prompt", target, text, timeout=30.0)

    def agent_state(self, target: str) -> tuple[str, int]:
        """(status, state_change_seq) for a live agent, or ("", 0).

        `state_change_seq` only moves when the agent's *lifecycle* state
        changes, which is what distinguishes "the text landed and it started
        working" from "the text is sitting in its input box".
        """
        result = self._run("agent", "get", target)
        if not result.ok:
            return "", 0
        agent = result.data.get("agent") or {}
        try:
            seq = int(agent.get("state_change_seq") or 0)
        except (TypeError, ValueError):
            seq = 0
        return str(agent.get("agent_status") or ""), seq

    def notify(self, title: str, body: str = "") -> Result:
        """A toast in the running herdr session — how a capture confirms itself."""
        args = ["notification", "show", title]
        if body:
            args += ["--body", body]
        return self._run(*args)

    def send_keys(self, target: str, *keys: str) -> Result:
        return self._run("agent", "send-keys", target, *keys)

    def close_pane(self, pane_id: str) -> Result:
        return self._run("pane", "close", pane_id)

    def close_tab(self, tab_id: str) -> Result:
        return self._run("tab", "close", tab_id)

    def tab_label(self, tab_id: str) -> str:
        """The label of a live tab, or "" when it no longer exists."""
        result = self._run("tab", "get", tab_id)
        if not result.ok:
            return ""
        return str(result.data.get("tab", {}).get("label") or "")

    def reload_config(self) -> Result:
        return self._run("server", "reload-config")
