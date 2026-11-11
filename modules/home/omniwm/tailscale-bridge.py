#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Tailscale profile bridge for the OmniShell bar.

Pushes the current login profile to the bar as OmniShell runtime values and
serves a loopback HTTP endpoint that switches profiles. A bar widget cannot
launch a process, so this is the one action it cannot run itself: the widget
POSTs a profile id, this process validates it against `tailscale switch
--list` and runs the switch.

Values pushed (one `omniwmctl shell set` each, re-pushed every tick because
they only live as long as OmniWM):

  tailscale.label     short name of the current tailnet, e.g. "rexforddrive"
  tailscale.state     BackendState, e.g. "Running"
  tailscale.profiles  one "id<TAB>label<TAB>current" line per login profile

Loopback only: the HTTP server binds 127.0.0.1 and never leaves the machine.
"""

import json
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 47832
POLL_SECONDS = 15
TAILSCALE = shutil.which("tailscale")
OMNIWMCTL = shutil.which("omniwmctl")

ROW = re.compile(r"^([0-9a-fA-F]{4,16})\s+(\S+)\s+(\S+)\s*$")
switch_lock = threading.Lock()


def run(args, timeout):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except Exception as error:  # noqa: BLE001 - a missing CLI must not kill the daemon
        print(f"tailscale-profiles: {args[0]} failed: {error}", file=sys.stderr)
        return None


def profiles():
    result = run([TAILSCALE, "switch", "--list"], 15)
    if not result or result.returncode != 0:
        return []
    rows = []
    for line in result.stdout.splitlines():
        match = ROW.match(line.strip())
        if not match:
            continue
        profile, tailnet, account = match.groups()
        current = account.endswith("*")
        rows.append(
            {
                "id": profile,
                "tailnet": tailnet,
                "account": account.rstrip("*"),
                "current": current,
            }
        )
    return rows


def state():
    result = run([TAILSCALE, "status", "--json"], 15)
    if not result or result.returncode != 0:
        return "Unavailable"
    try:
        return json.loads(result.stdout).get("BackendState", "Unknown")
    except Exception:  # noqa: BLE001 - an odd payload is not a crash
        return "Unknown"


def short(row):
    name = row["tailnet"].split("@")[0].split(".")[0]
    return name or row["id"]


def push(rows):
    current = next((row for row in rows if row["current"]), None)
    # One line: OmniShell runtime values round-trip most predictably without
    # embedded newlines, so entries are `id|label|current` joined by `;`.
    table = ";".join(
        f'{row["id"]}|{short(row)}|{1 if row["current"] else 0}' for row in rows
    )
    values = {
        "tailscale.label": short(current) if current else "Tailscale",
        "tailscale.state": state(),
        "tailscale.profiles": table,
    }
    for key, value in values.items():
        # OmniWM may be restarting; the next tick retries.
        run([OMNIWMCTL, "shell", "set", key, value], 10)


def poll():
    while True:
        try:
            push(profiles())
        except Exception as error:  # noqa: BLE001 - keep polling
            print(f"tailscale-profiles: poll failed: {error}", file=sys.stderr)
        time.sleep(POLL_SECONDS)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"tailscale-profiles: {fmt % args}", file=sys.stderr)

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.path.startswith("/status"):
            return self.reply(404, {"ok": False, "error": "not_found"})
        rows = profiles()
        self.reply(200, {"ok": True, "state": state(), "profiles": rows})

    def do_POST(self):
        if not self.path.startswith("/switch"):
            return self.reply(404, {"ok": False, "error": "not_found"})
        try:
            length = min(int(self.headers.get("Content-Length") or 0), 4096)
        except ValueError:
            length = 0
        raw = self.rfile.read(length).decode("utf-8", "replace")
        try:
            profile_id = (urllib.parse.parse_qs(raw).get("id") or [""])[0]
        except Exception:  # noqa: BLE001 - malformed body is a client error
            profile_id = ""
        if not re.fullmatch(r"[0-9a-fA-F]{4,16}", profile_id):
            print(f"tailscale-profiles: bad switch body {raw!r}", file=sys.stderr)
            return self.reply(400, {"ok": False, "error": "invalid_profile"})

        with switch_lock:
            rows = profiles()
            match = next((row for row in rows if row["id"] == profile_id), None)
            if match is None:
                return self.reply(400, {"ok": False, "error": "unknown_profile"})
            if not match["current"]:
                result = run([TAILSCALE, "switch", profile_id], 30)
                if not result or result.returncode != 0:
                    detail = (result.stderr or result.stdout or "").strip()[-400:] if result else ""
                    return self.reply(
                        500, {"ok": False, "error": detail or "tailscale_unavailable"}
                    )
            push(profiles())
        self.reply(200, {"ok": True, "id": profile_id})


def main():
    if TAILSCALE is None or OMNIWMCTL is None:
        print("tailscale-profiles: tailscale or omniwmctl missing from PATH", file=sys.stderr)
        return 1
    threading.Thread(target=poll, daemon=True).start()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"tailscale-profiles: bridge on http://127.0.0.1:{PORT}", file=sys.stderr)
    server.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
