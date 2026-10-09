import json
from urllib.parse import urlencode

import pytest

from conftest import secret_tool

ORG = "acme"
ISSUES = f"/api/0/organizations/{ORG}/issues/"


def issues_route(query, **params):
    return f"GET {ISSUES}?" + urlencode({"project": -1, "statsPeriod": "90d", "query": query, **params})


def issue(iid, project="shop", **kw):
    return {"id": iid, "shortId": f"SHOP-{iid}", "title": "KeyError: 'x'", "culprit": "app.views", "level": "error",
            "firstSeen": "2026-10-01T00:00:00Z", "lastSeen": "2026-10-09T00:00:00Z", "count": "3", "userCount": 1,
            "permalink": f"https://acme.sentry.io/issues/{iid}/", "project": {"slug": project, "name": project},
            "metadata": {"secret": "internals"}, **kw}


@pytest.fixture
def sentry(server, stubs):
    secret_tool(stubs, "plasma-sentry", server.url, "tok")
    page2 = f"{server.url}{ISSUES}?cursor=2"
    server.add(issues_route("is:unresolved", sort="date", limit=100), [issue("1"), issue("2", project="blog")],
               headers={"X-Hits": "3", "Link": f'<{page2}>; rel="next"; results="true"; cursor="2"'})
    server.add(f"GET {ISSUES}?cursor=2", [issue("3")],
               headers={"Link": f'<{server.url}{ISSUES}?cursor=3>; rel="next"; results="false"; cursor="3"'})
    server.add(issues_route("is:unresolved firstSeen:-24h", limit=1), [issue("1")], headers={"X-Hits": "1"})
    server.add(issues_route("is:ignored", limit=1), [issue("9")], headers={"X-Hits": "4"})
    # No X-Hits: the issues on a full page are counted instead.
    server.add(issues_route("is:resolved", limit=1), [issue("7")])
    server.add(issues_route("is:resolved", limit=100), [issue("7"), issue("8")])
    return server


def test_fetch(sentry, run):
    result = run("sentrystatus", "sentry.py", "fetch", sentry.url + "/", ORG, "5")
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert [i["id"] for i in data["issues"]] == ["1", "2", "3"]
    assert [i["project"] for i in data["issues"]] == ["shop", "blog", "shop"]
    assert "metadata" not in data["issues"][0]                    # only the fields the widget shows
    assert data["counts"] == {"new": 1, "unresolved": 3, "archived": 4, "resolved": 2}
    assert data["truncated"] is False
    assert {r["headers"]["authorization"] for r in sentry.requests} == {"Bearer tok"}


def test_fetch_stops_after_max_pages(sentry, run):
    result = run("sentrystatus", "sentry.py", "fetch", sentry.url, ORG)
    data = json.loads(result.stdout)
    assert [i["id"] for i in data["issues"]] == ["1", "2"]
    assert data["truncated"] is True


@pytest.mark.parametrize("action, status", [("resolve", "resolved"), ("archive", "ignored")])
def test_actions_put(sentry, run, action, status):
    sentry.add(f"PUT {ISSUES}?id=42", None, status=204)
    result = run("sentrystatus", "sentry.py", action, sentry.url, ORG, "42")
    assert result.returncode == 0, result.stderr
    assert sentry.requests[-1]["method"] == "PUT"
    assert sentry.requests[-1]["body"] == {"status": status}


@pytest.mark.parametrize("args", [("delete", "42"), ("resolve", "42&id=43"), ("resolve",)])
def test_bad_actions(sentry, run, args):
    assert run("sentrystatus", "sentry.py", args[0], sentry.url, ORG, *args[1:]).returncode == 2


@pytest.mark.parametrize("status, code, message", [
    (401, 4, "rejected the auth token (401)"), (404, 5, "Check the organization slug"), (500, 5, "HTTP 500"),
])
def test_http_errors(server, stubs, run, status, code, message):
    secret_tool(stubs, "plasma-sentry", server.url, "tok")
    server.add(f"GET {ISSUES}", {"detail": "nope"}, status)
    result = run("sentrystatus", "sentry.py", "fetch", server.url, ORG)
    assert result.returncode == code
    assert message in result.stderr


def test_no_token(server, stubs, run):
    secret_tool(stubs, "plasma-sentry", "https://other.example.com", "tok")
    result = run("sentrystatus", "sentry.py", "fetch", server.url, ORG)
    assert result.returncode == 3 and "No auth token" in result.stderr


def test_unreachable(stubs, run):
    secret_tool(stubs, "plasma-sentry", "http://127.0.0.1:9", "tok")
    result = run("sentrystatus", "sentry.py", "fetch", "http://127.0.0.1:9", ORG)
    assert result.returncode == 6 and "Could not reach" in result.stderr


def test_usage(run):
    assert run("sentrystatus", "sentry.py").returncode == 2
    assert run("sentrystatus", "sentry.py", "fetch", "https://sentry.io").returncode == 2
