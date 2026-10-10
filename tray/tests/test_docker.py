import json

import pytest

from statusbadges.model import Item, ProviderError
from statusbadges.providers.docker import DockerStatus, classify, label, short_ports, stack_actions


@pytest.mark.parametrize("state, status, health, expected", [
    ("running", "Up 2 hours", "", "running"),
    ("running", "Up 2 hours (healthy)", "healthy", "running"),
    ("running", "Up 2 hours (unhealthy)", "", "unhealthy"),
    ("running", "Up 2 hours", "unhealthy", "unhealthy"),
    ("restarting", "Restarting (1) 5 seconds ago", "", "restarting"),
    ("paused", "Up 2 hours (Paused)", "", "paused"),
    ("dead", "Dead", "", "failed"),
    ("exited", "Exited (1) 3 minutes ago", "", "failed"),
    ("exited", "Exited (255) 3 minutes ago", "", "failed"),
    ("exited", "Exited (0) 3 minutes ago", "", "stopped"),       # finished normally
    ("exited", "Exited (137) 3 minutes ago", "", "stopped"),     # docker stop / kill
    ("exited", "Exited (143) 3 minutes ago", "", "stopped"),
    ("exited", "Exited (130) 3 minutes ago", "", "stopped"),     # Ctrl+C
    ("created", "Created", "", "stopped"),
])
def test_classify(state, status, health, expected):
    assert classify({"State": state, "Status": status, "HealthStatus": health}) == expected


def test_label():
    labels = "com.docker.compose.project=shop,com.docker.compose.service=web,other=x"
    assert label(labels, "com.docker.compose.project") == "shop"
    assert label(labels, "com.docker.compose.service") == "web"
    assert label(labels, "missing") == ""
    assert label("", "anything") == ""
    assert label("xcom.docker.compose.project=nope", "com.docker.compose.project") == ""


def test_short_ports_drops_ipv6_duplicates():
    ports = "0.0.0.0:8080->80/tcp, [::]:8080->80/tcp, 0.0.0.0:5432->5432/tcp, 6379/tcp"
    assert short_ports(ports) == "8080→80, 5432→5432"
    assert short_ports("") == ""


def container(cid, name, state, status, project="", service="", image="nginx:1.27", ports=""):
    labels = ",".join(f"com.docker.compose.{k}={v}" for k, v in (("project", project), ("service", service)) if v)
    return {"ID": cid, "Names": name, "State": state, "Status": status, "Image": image, "Labels": labels,
            "Ports": ports}


@pytest.fixture
def docker(cli):
    rows = [
        container("a1", "shop-web-1", "running", "Up 1 hour", "shop", "web", ports="0.0.0.0:8080->80/tcp"),
        container("a2", "shop-db-1", "exited", "Exited (1) 2 minutes ago", "shop", "db", image="postgres:17"),
        container("a3", "shop-cache-1", "paused", "Up 1 hour (Paused)", "shop", "cache"),
        container("b1", "scratch", "exited", "Exited (0) 1 day ago", image="sha256:0123456789abcdef0123"),
    ]
    cli.add(["docker", "ps"], "\n".join(json.dumps(r) for r in rows) + "\n")
    cli.add(["docker", "--context"], "\n".join(json.dumps(r) for r in rows[:1]))
    return cli


def test_fetch_counts_and_groups_by_compose_project(docker):
    result = DockerStatus({}).fetch()
    assert result.counts == {"running": 1, "failed": 1, "paused": 1, "stopped": 1}
    assert result.summary == "current context"
    shop, standalone = result.sections
    assert shop.title == "shop" and standalone.title == "Standalone containers"
    # Worst state first, named after the compose service.
    assert [(i.title, i.state, i.bold) for i in shop.items] == [
        ("db", "failed", True), ("cache", "paused", False), ("web", "running", False)]
    web = shop.items[2]
    assert web.subtitle == "nginx:1.27 · Up 1 hour · 8080→80"
    assert [a.id for a in web.actions] == ["restart", "stop"]
    assert shop.items[1].actions == []                           # paused: nothing to offer
    assert [a.id for a in shop.items[0].actions] == ["start"]
    assert standalone.items[0].subtitle.startswith("0123456789ab · ")   # image id shortened
    # The stack is half up, so it can be started, restarted and stopped as a whole.
    assert shop.id == "project:shop"
    assert [a.id for a in shop.actions] == ["start", "restart", "stop"]
    assert standalone.id == "" and standalone.actions == []


@pytest.mark.parametrize("states, expected", [
    (["running", "unhealthy"], ["restart", "stop"]),
    (["stopped", "failed"], ["start"]),
    (["restarting"], ["restart", "stop"]),
    (["paused"], []),                                            # unpause isn't offered
])
def test_stack_actions(states, expected):
    assert [a.id for a in stack_actions([Item(str(n), "c", state=s) for n, s in enumerate(states)])] == expected


def test_fetch_uses_the_chosen_context(docker):
    result = DockerStatus({"context": "colima"}).fetch()
    assert docker.calls[0]["args"][:3] == ["docker", "--context", "colima"]
    assert result.summary == "colima"


def test_run_action(docker):
    docker.add(["docker", "restart"], "")
    DockerStatus({}).run_action("a1", "restart")
    assert docker.calls[-1]["args"] == ["docker", "restart", "a1"]
    with pytest.raises(ProviderError, match="Unknown action"):
        DockerStatus({}).run_action("a1", "rm")


def test_run_stack_action(docker):
    docker.add(["docker", "compose"], "")
    DockerStatus({}).run_action("project:shop", "stop")
    assert docker.calls[-1]["args"] == ["docker", "compose", "--project-name", "shop", "stop"]
    DockerStatus({"context": "colima"}).run_action("project:shop", "start")
    assert docker.calls[-1]["args"] == ["docker", "--context", "colima", "compose", "--project-name", "shop", "start"]
    with pytest.raises(ProviderError, match="Unknown action"):
        DockerStatus({}).run_action("project:shop", "down")


def test_choices_lists_contexts_and_survives_a_missing_cli(cli):
    cli.add(["docker", "context", "ls"], "default\ncolima\n\n")
    assert DockerStatus.choices("context") == ["default", "colima"]
    cli.add(["docker", "context", "ls"], ProviderError("docker is not installed or not on PATH"))
    assert DockerStatus.choices("context") == []
