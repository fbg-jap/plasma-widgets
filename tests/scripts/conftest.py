"""Runs the widgets' helper scripts (contents/code/*.py, *.sh) as real processes, against a local
HTTP server and stub `secret-tool`, `docker` and `gh` commands on PATH."""
import json
import os
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]


class FakeServer:
    """Answers requests from canned (status, body) responses keyed by "METHOD /path?query" or "METHOD /path"."""

    def __init__(self):
        self.routes = {}
        self.requests = []
        handler = self._handler()
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def add(self, route: str, body, status: int = 200):
        self.routes[route] = (status, body)

    def _handler(self):
        server = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _answer(self):
                length = int(self.headers.get("Content-Length") or 0)
                body = self.rfile.read(length) if length else b""
                server.requests.append({"method": self.command, "path": self.path, "headers": {k.lower(): v for k, v in self.headers.items()},
                                        "body": json.loads(body) if body else None})
                path_only = self.path.split("?")[0]
                status, payload = server.routes.get(f"{self.command} {self.path}") \
                    or server.routes.get(f"{self.command} {path_only}") or (404, {"message": "no route"})
                data = b"" if payload is None else json.dumps(payload).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            do_GET = do_POST = do_PUT = _answer

        return Handler


@pytest.fixture
def server():
    fake = FakeServer()
    yield fake
    fake.httpd.shutdown()


class Stubs:
    """Executable stand-ins for CLI tools. Each logs its arguments (one call per line, as JSON) and
    the environment variables it was asked to record."""

    def __init__(self, directory: Path):
        self.dir = directory
        self.log = directory / "calls.jsonl"

    def add(self, name: str, body: str, record_env: tuple = ()):
        path = self.dir / name
        path.write_text(f"""#!/bin/sh
python3 -c 'import json, os, sys; print(json.dumps({{"tool": "{name}", "args": sys.argv[1:],
    "env": {{v: os.environ.get(v, "") for v in {json.dumps(list(record_env))}}}}}))' "$@" >> "{self.log}"
{body}
""")
        path.chmod(0o755)

    def calls(self, tool: str | None = None) -> list[dict]:
        if not self.log.exists():
            return []
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return [c for c in calls if tool is None or c["tool"] == tool]


@pytest.fixture
def stubs(tmp_path):
    directory = tmp_path / "bin"
    directory.mkdir()
    return Stubs(directory)


@pytest.fixture
def run(stubs):
    """Runs a widget script with the stubs first on PATH. Returns the CompletedProcess."""
    def run_script(widget: str, script: str, *args: str, env: dict | None = None):
        path = REPO / widget / "contents" / "code" / script
        command = [sys.executable, "-I", str(path)] if script.endswith(".py") else ["sh", str(path)]
        full_env = {**os.environ, "PATH": f"{stubs.dir}{os.pathsep}{os.environ['PATH']}", **(env or {})}
        return subprocess.run(command + list(args), capture_output=True, text=True, env=full_env, timeout=30)
    return run_script


def secret_tool(stubs, service: str, server: str, secret: str):
    """A secret-tool that knows one secret: the one for `service` on `server`."""
    stubs.add("secret-tool", f"""
[ "$1 $2 $3 $4 $5" = "lookup service {service} server {server}" ] && printf '%s' '{secret}'
exit 0""")
