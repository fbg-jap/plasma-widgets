import pytest

from statusbadges.model import ProviderError
from statusbadges.providers.runner import RunnerStatus, actions_url, duration, runner_state

SERVER = "http://runners.local:8089"
NOW = 1_000_000.0


def runner(repo, status, **extra):
    return {"repo": repo, "name": "build", "dir": f"/runners/{repo}", "status": status,
            "repo_url": f"https://github.com/{repo}", **extra}


@pytest.fixture
def runners(http):
    http.add(SERVER + "/api/status", {"now": NOW, "host": {"hostname": "mac", "load": [1.5, 1.2, 0.9]}, "runners": [
        runner("me/web", "idle", uptime=7500, history=[
            {"name": "test", "result": "Succeeded", "finished": NOW - 3600},
            {"name": "lint", "result": "Failed", "finished": NOW - 120}]),
        runner("me/api", "busy", uptime=60, job={"job": "build", "workflow": "CI", "run_id": 42, "started": NOW - 192}),
        runner("me/old", "stopped"),
    ]})
    return RunnerStatus({"server": SERVER + "/"})


def test_counts_and_sorts_worst_first(runners):
    result = runners.fetch()
    assert result.counts == {"offline": 1, "busy": 1, "idle": 1}
    assert result.summary == "mac · load 1.5 / 1.2 / 0.9"
    assert [(i.title, i.state) for i in result.sections[0].items] == [
        ("me/old", "offline"), ("me/api", "busy"), ("me/web", "idle")]


def test_describes_each_runner(runners):
    old, api, web = runners.fetch().sections[0].items
    assert (old.subtitle, old.bold, old.id) == ("build · no jobs yet", True, "/runners/me/old")
    assert api.subtitle == "build · build in CI · running 3m 12s · up 1m 0s"
    assert api.url == "https://github.com/me/api/actions/runs/42"
    assert (web.subtitle, web.bold) == ("build · lint failed 2m 0s ago · up 2h 5m", True)   # the last job failed
    assert web.url == "https://github.com/me/web/actions"


def test_needs_a_server():
    with pytest.raises(ProviderError, match="No runner dashboard"):
        RunnerStatus({}).fetch()


def test_rejects_an_unexpected_response(http):
    http.add(SERVER, {"error": "nope"})
    with pytest.raises(ProviderError, match="unexpected"):
        RunnerStatus({"server": SERVER}).fetch()


def test_only_offline_is_a_problem():
    assert RunnerStatus.problem_states() == {"offline"}


@pytest.mark.parametrize("status, expected", [("idle", "idle"), ("busy", "busy"), ("stopped", "offline"), (None, "offline")])
def test_runner_state(status, expected):
    assert runner_state({"status": status}) == expected


def test_actions_url_only_allows_http():
    assert actions_url({"repo_url": "file:///etc/passwd"}) == ""
    assert actions_url({"repo_url": "https://github.com/me/x", "job": {"run_id": 7}}) == "https://github.com/me/x/actions/runs/7"


@pytest.mark.parametrize("seconds, expected", [(None, "–"), (45, "45s"), (192, "3m 12s"), (7500, "2h 5m"),
                                               (4 * 86400 + 3 * 3600, "4d 3h"), (-5, "0s")])
def test_duration(seconds, expected):
    assert duration(seconds) == expected
