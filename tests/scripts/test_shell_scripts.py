"""fetch.sh / action.sh for PRTG, Docker and GitHub Account."""
import json
import shutil
from urllib.parse import parse_qs, urlsplit

import pytest

from conftest import secret_tool


# PRTG: secret-tool for the key, the real curl against the fake server.

@pytest.mark.skipif(not shutil.which("curl"), reason="needs curl")
def test_prtg_fetch(server, stubs, run):
    secret_tool(stubs, "plasma-prtg", server.url, "k3y")
    server.add("GET /api/table.json", {"sensors": [{"objid": 1, "status_raw": 5}]})
    result = run("prtgstatus", "fetch.sh", server.url)
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == {"problems": {"sensors": [{"objid": 1, "status_raw": 5}]},
                                         "all": {"sensors": [{"objid": 1, "status_raw": 5}]}}
    problems, everything = (parse_qs(urlsplit(r["path"]).query) for r in server.requests)
    assert problems["filter_status"] == ["4", "5", "10", "13", "14"]
    assert problems["apitoken"] == everything["apitoken"] == ["k3y"]
    assert "filter_status" not in everything


@pytest.mark.skipif(not shutil.which("curl"), reason="needs curl")
def test_prtg_http_error(server, stubs, run):
    secret_tool(stubs, "plasma-prtg", server.url, "k3y")
    server.add("GET /api/table.json", {}, 401)
    result = run("prtgstatus", "fetch.sh", server.url)
    assert result.returncode != 0 and result.stdout == ""


def test_prtg_needs_server_and_key(stubs, run):
    secret_tool(stubs, "plasma-prtg", "https://prtg.example.com", "k3y")
    assert run("prtgstatus", "fetch.sh", "").returncode == 2
    result = run("prtgstatus", "fetch.sh", "https://other.example.com")
    assert result.returncode == 3 and "No API key" in result.stderr


# Docker: a stub docker CLI.

@pytest.fixture
def docker(stubs):
    stubs.add("docker", 'echo \'{"ID":"a1"}\'')
    return stubs


def test_docker_fetch(docker, run):
    assert run("dockerstatus", "fetch.sh", "").stdout == '{"ID":"a1"}\n'
    assert docker.calls("docker")[-1]["args"] == ["ps", "--all", "--no-trunc", "--format", "{{json .}}"]
    run("dockerstatus", "fetch.sh", "colima")
    assert docker.calls("docker")[-1]["args"][:3] == ["--context", "colima", "ps"]


@pytest.mark.parametrize("context, expected", [("", ["restart", "a1"]), ("colima", ["--context", "colima", "restart", "a1"])])
def test_docker_action(docker, run, context, expected):
    assert run("dockerstatus", "action.sh", context, "restart", "a1").returncode == 0
    assert docker.calls("docker")[-1]["args"] == expected


def test_docker_action_rejects_other_commands(docker, run):
    result = run("dockerstatus", "action.sh", "", "rm", "a1")
    assert result.returncode == 2 and "Unknown action" in result.stderr
    assert docker.calls("docker") == []


# GitHub Account: a stub gh CLI.

@pytest.fixture
def gh(stubs):
    stubs.add("gh", """
case "$1 $2" in
  "auth token") [ "$6" = "work" ] && echo gho_work && exit 0; exit 1 ;;
  "api notifications") echo '[{"id":"1"}]' ;;
  "api graphql") echo '{"data":{"viewer":{"login":"octo"}}}' ;;
esac""", record_env=("GH_TOKEN",))
    return stubs


def test_github_fetch(gh, run):
    result = run("githubaccount", "fetch.sh", "", env={"GH_TOKEN": ""})
    assert result.returncode == 0, result.stderr
    assert json.loads(result.stdout) == {"notifications": [{"id": "1"}], "graphql": {"data": {"viewer": {"login": "octo"}}}}
    calls = gh.calls("gh")
    assert [c["args"][:2] for c in calls] == [["api", "notifications"], ["api", "graphql"]]
    assert all(c["env"]["GH_TOKEN"] == "" for c in calls)      # gh's active account


def test_github_fetch_as_another_account(gh, run):
    result = run("githubaccount", "fetch.sh", "work", env={"GH_TOKEN": ""})
    assert result.returncode == 0, result.stderr
    api_calls = [c for c in gh.calls("gh") if c["args"][0] == "api"]
    assert api_calls and all(c["env"]["GH_TOKEN"] == "gho_work" for c in api_calls)
    assert not any("gho_work" in " ".join(c["args"]) for c in gh.calls("gh"))   # never on a command line


def test_github_fetch_unknown_account(gh, run):
    result = run("githubaccount", "fetch.sh", "nobody")
    assert result.returncode == 4 and "not logged in as nobody" in result.stderr


def test_github_mark_read(gh, run):
    assert run("githubaccount", "fetch.sh", "", "mark-read").returncode == 0
    assert gh.calls("gh")[0]["args"] == ["api", "-X", "PUT", "notifications", "--silent"]
