import json

import pytest

from conftest import secret_tool


@pytest.fixture
def dokploy(server, stubs):
    secret_tool(stubs, "plasma-dokploy", server.url, "key")
    server.add("GET /api/project.all", [{
        "projectId": "p1", "name": "Shop", "env": {"SECRET": "x"},
        "environments": [{
            "environmentId": "e1", "name": "production",
            "applications": [{"applicationId": "a1", "name": "web", "applicationStatus": "done", "env": "TOKEN=1"}],
            "compose": [{"composeId": "c1", "name": "stack", "composeStatus": "running"}],
            "postgres": [{"postgresId": "d1"}],
            "mysql": None,
        }],
    }])
    server.add("GET /api/postgres.one?postgresId=d1",
               {"name": "shop-db", "applicationStatus": "error", "databasePassword": "hunter2"})
    return server


def test_fetch(dokploy, run):
    result = run("dokploystatus", "dokploy.py", "fetch", dokploy.url + "/")
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == {"projects": [{"id": "p1", "name": "Shop", "environments": [{
        "id": "e1", "name": "production", "services": [
            {"type": "application", "id": "a1", "name": "web", "status": "done"},
            {"type": "compose", "id": "c1", "name": "stack", "status": "running"},
            {"type": "postgres", "id": "d1", "name": "shop-db", "status": "error"},
        ]}]}]}
    for secret in ("hunter2", "TOKEN", "SECRET"):
        assert secret not in result.stdout
    assert {r["headers"]["x-api-key"] for r in dokploy.requests} == {"key"}


def test_actions(dokploy, run):
    dokploy.add("POST /api/compose.deploy", None)
    result = run("dokploystatus", "dokploy.py", "deploy", dokploy.url, "compose", "c1")
    assert result.returncode == 0, result.stderr
    assert dokploy.requests[-1]["body"] == {"composeId": "c1"}


@pytest.mark.parametrize("args", [("delete", "compose", "c1"), ("deploy", "server", "s1"), ("deploy", "compose")])
def test_rejects_unknown_actions_and_types(dokploy, run, args):
    action, *rest = args
    assert run("dokploystatus", "dokploy.py", action, dokploy.url, *rest).returncode == 2
    assert not dokploy.requests


def test_http_error_shows_dokploys_message(server, stubs, run):
    secret_tool(stubs, "plasma-dokploy", server.url, "key")
    server.add("GET /api/project.all", {"message": "Database is down"}, 500)
    result = run("dokploystatus", "dokploy.py", "fetch", server.url)
    assert result.returncode == 5
    assert "HTTP 500 for project.all: Database is down" in result.stderr


def test_rejected_key(server, stubs, run):
    secret_tool(stubs, "plasma-dokploy", server.url, "key")
    server.add("GET /api/project.all", {}, 401)
    result = run("dokploystatus", "dokploy.py", "fetch", server.url)
    assert result.returncode == 4 and "rejected the API key" in result.stderr


def test_no_key(server, stubs, run):
    secret_tool(stubs, "plasma-dokploy", "https://other.example.com", "key")
    assert run("dokploystatus", "dokploy.py", "fetch", server.url).returncode == 3
