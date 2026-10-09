"""Fakes for the outside world (HTTP, the gh/docker CLIs, the keyring) so providers can be tested offline."""
import json
from datetime import datetime, timedelta, timezone

import pytest

from statusbadges import httpjson, keystore, process
from statusbadges.model import ProviderError


def iso_ago(**delta) -> str:
    """A UTC timestamp the given time ago, in the "...Z" form the APIs use."""
    return (datetime.now(timezone.utc) - timedelta(**delta)).strftime("%Y-%m-%dT%H:%M:%SZ")


class FakeHTTP:
    """Answers httpjson.request from canned responses, matched by the longest URL prefix."""

    def __init__(self):
        self.routes = {}
        self.calls = []

    def add(self, url_prefix: str, response):
        self.routes[url_prefix] = response

    def __call__(self, url, headers=None, params=None, body=None, method=None, auth_name="the server"):
        self.calls.append({"url": url, "headers": headers or {}, "params": params, "body": body, "method": method})
        matches = [p for p in self.routes if url.startswith(p)]
        if not matches:
            raise ProviderError(f"no fake response for {url}")
        response = self.routes[max(matches, key=len)]
        return response(url, params) if callable(response) else response


class FakeProcess:
    """Answers process.run from canned output, matched by the longest leading run of arguments."""

    def __init__(self):
        self.routes = {}
        self.calls = []

    def add(self, args: list[str], output):
        self.routes[tuple(args)] = output

    def __call__(self, args, env=None, timeout=60):
        self.calls.append({"args": list(args), "env": env})
        matches = [r for r in self.routes if tuple(args[:len(r)]) == r]
        if not matches:
            raise ProviderError(f"no fake output for {args}")
        output = self.routes[max(matches, key=len)]
        if isinstance(output, Exception):
            raise output
        return output if isinstance(output, str) else json.dumps(output)


@pytest.fixture
def http(monkeypatch):
    fake = FakeHTTP()
    monkeypatch.setattr(httpjson, "request", fake)
    return fake


@pytest.fixture
def cli(monkeypatch):
    fake = FakeProcess()
    monkeypatch.setattr(process, "run", fake)
    return fake


@pytest.fixture
def secrets(monkeypatch):
    """The keyring, as a dict of (kind, server) -> key."""
    store = {}
    monkeypatch.setattr(keystore, "get", lambda kind, server: store.get((kind, server.rstrip("/"))))
    return store
