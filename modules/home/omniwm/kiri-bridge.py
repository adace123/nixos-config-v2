#!/usr/bin/env python3
"""Loopback action bridge for the OmniShell `kiri` widget.

A widget cannot run a process and cannot POST to a unix socket, so the Stop
button in each container row cannot talk to Kiri's daemon directly. This
process is the one thing a widget can reach: an HTTP endpoint on 127.0.0.1 that
does the call itself.

    POST /stop  container=<name>   -> {"ok": true}

It speaks the Docker Engine API over Kiri's own socket
(`~/.kiri/run/docker.sock`), which is the same endpoint `docker stop` uses, so
the result is indistinguishable from stopping the container by hand. The
daemon is asleep only when nothing is running, so stopping an already-stopped
container is a no-op rather than a VM wake.

Loopback only, and the name is validated: any local process can already reach
the socket, but this must not become a path-smuggling hole into
`/containers/...`.
"""

import json
import os
import re
import socket
import sys
from http.client import HTTPConnection
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

SOCKET = os.path.expanduser("~/.kiri/run/docker.sock")
PORT = 47833
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,254}$")


class UnixConnection(HTTPConnection):
    """HTTP over the daemon's unix socket."""

    def __init__(self, path, timeout):
        super().__init__("localhost", timeout=timeout)
        self._path = path

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        sock.connect(self._path)
        self.sock = sock


def docker(method, path, timeout=20):
    conn = UnixConnection(SOCKET, timeout)
    try:
        conn.request(method, path, headers={"Host": "localhost"})
        response = conn.getresponse()
        return response.status, response.read()
    finally:
        conn.close()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        # Launchd already keeps stderr; one line per action is enough.
        sys.stderr.write("kiri-bridge: " + (fmt % args) + "\n")

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        form = parse_qs(self.rfile.read(length).decode("utf-8", "replace")) if length else {}
        if self.path != "/stop":
            return self.reply(404, {"error": "unknown path"})
        name = (form.get("container") or [""])[0].strip().lstrip("/")
        if not NAME.match(name):
            return self.reply(400, {"error": "bad container name"})
        try:
            status, body = docker("POST", "/containers/%s/stop?t=10" % name)
        except OSError as error:
            return self.reply(502, {"error": "kiri daemon unreachable: %s" % error})
        if status in (204, 304):
            return self.reply(200, {"ok": True, "container": name})
        return self.reply(502, {"error": body.decode("utf-8", "replace")[:200], "status": status})


def main():
    if not os.path.exists(SOCKET):
        sys.stderr.write("kiri-bridge: no %s; waiting for the daemon\n" % SOCKET)
        while not os.path.exists(SOCKET):
            import time

            time.sleep(5)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    sys.stderr.write("kiri-bridge: listening on 127.0.0.1:%d\n" % PORT)
    server.serve_forever()


if __name__ == "__main__":
    main()
