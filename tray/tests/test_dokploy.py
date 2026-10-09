import pytest

from statusbadges.model import ProviderError, Result
from statusbadges.providers.dokploy import DokployStatus

SERVER = "https://dokploy.example.com"
API = SERVER + "/api/"


def env(eid, name, applications=(), compose=(), postgres=()):
    return {"environmentId": eid, "name": name, "applications": list(applications), "compose": list(compose),
            "postgres": list(postgres)}


@pytest.fixture
def dokploy(http, secrets):
    secrets[("dokploy", SERVER)] = "k"
    http.add(API + "project.all", [
        {"projectId": "p1", "name": "Shop", "environments": [
            env("e1", "production",
                applications=[{"applicationId": "a1", "name": "web", "applicationStatus": "done"},
                              {"applicationId": "a2", "name": "worker", "applicationStatus": "error"}],
                compose=[{"composeId": "c1", "name": "stack", "composeStatus": "running"}],
                postgres=[{"postgresId": "db1"}]),
            env("e2", "staging"),                       # empty: no section
        ]},
        {"projectId": "p2", "name": "Blog", "environments": [
            env("e3", "production", applications=[{"applicationId": "a3", "name": "site", "applicationStatus": None}]),
        ]},
    ])
    http.add(API + "postgres.one", {"name": "shop-db", "applicationStatus": "done", "databasePassword": "secret"})
    return DokployStatus({"server": SERVER})


def test_counts_applications_compose_stacks_and_databases(dokploy):
    result = dokploy.fetch()
    assert result.counts == {"done": 2, "error": 1, "running": 1, "idle": 1}
    assert result.summary == "dokploy.example.com"


def test_sections_and_actions(dokploy):
    shop, blog = dokploy.fetch().sections
    assert shop.title == "Shop · production"            # project has more than one environment
    assert blog.title == "Blog"
    items = {i.title: i for i in shop.items}
    assert [i.title for i in shop.items] == ["worker", "stack", "shop-db", "web"]   # worst first
    assert items["worker"].bold and items["worker"].subtitle == "Application · Failed"
    assert [a.id for a in items["worker"].actions] == ["deploy", "stop"]
    assert items["stack"].actions == []                 # deploying: wait for it
    assert items["shop-db"].id == "postgres:db1" and items["shop-db"].subtitle == "PostgreSQL · Deployed"
    assert items["web"].url == SERVER + "/dashboard/project/p1/environment/e1/services/application/a1"
    site = blog.items[0]
    assert site.state == "idle" and [a.id for a in site.actions] == ["deploy", "start"]


def test_never_keeps_database_secrets(dokploy):
    result = dokploy.fetch()
    assert "secret" not in repr(result)


def test_run_action(dokploy, http):
    http.add(API + "compose.deploy", None)
    dokploy.run_action("compose:c1", "deploy")
    assert http.calls[-1]["url"] == API + "compose.deploy"
    assert http.calls[-1]["body"] == {"composeId": "c1"}
    assert http.calls[-1]["headers"] == {"x-api-key": "k"}
    with pytest.raises(ProviderError):
        dokploy.run_action("compose:c1", "delete")
    with pytest.raises(ProviderError):
        dokploy.run_action("server:s1", "deploy")


def test_fast_poll_while_deploying():
    assert DokployStatus({}).fast_poll(Result({"running": 1, "done": 3}))
    assert not DokployStatus({}).fast_poll(Result({"done": 3}))


def test_needs_a_server(secrets):
    with pytest.raises(ProviderError, match="No Dokploy server"):
        DokployStatus({}).fetch()
