"""Desktop notifications, for the moments the board is not in front of you.

Two of them: a card whose agent has stopped to ask you something, and a card an
agent filed while working on another one. herdr's own `notification show` is an
in-session toast: only someone already looking at herdr sees it, and both of
these happen precisely when you are not. So the board also asks the desktop —
macOS Notification Center through `terminal-notifier` (what this repo's other
scripts use) or `osascript`, and `notify-send` elsewhere.

Everything here is best-effort. A machine with no notifier, or one whose
notifier fails, must never break a board tick, so the command is started
detached and its failure is swallowed. `KANBAN_NOTIFY_CMD` overrides the command
(the title and body are appended as two arguments), which is also how the
selftest keeps a real banner from firing.
"""

from __future__ import annotations

import os
import shlex
import shutil
import subprocess
import sys

OVERRIDE_ENV = "KANBAN_NOTIFY_CMD"

# `osascript` takes the title and body as argv rather than interpolating them
# into the script, so a title with a quote in it cannot break out of it.
_OSASCRIPT = (
    "on run argv\n"
    "display notification (item 2 of argv) with title (item 1 of argv)\n"
    "end run"
)


def command(title: str, body: str = "") -> list[str]:
    """The desktop-notification command for this machine, or [] for none."""
    override = os.environ.get(OVERRIDE_ENV, "").strip()
    if override:
        return [*shlex.split(override), title, body]
    if sys.platform == "darwin":
        if shutil.which("terminal-notifier"):
            return ["terminal-notifier", "-title", title, "-message", body]
        if shutil.which("osascript"):
            return ["osascript", "-e", _OSASCRIPT, title, body]
    if shutil.which("notify-send"):
        return ["notify-send", title, body]
    return []


def system(title: str, body: str = "") -> bool:
    """Fire a desktop notification. True when a command was started."""
    args = command(title, body)
    if not args:
        return False
    try:
        subprocess.Popen(
            args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    except OSError:
        return False
    return True


__all__ = ["OVERRIDE_ENV", "command", "system"]
