import pytest

from conftest import iso_ago
from statusbadges.model import ProviderError
from statusbadges.providers.bugsink import BugsinkStatus, ago

SERVER = "https://bugsink.example.com"
API = SERVER + "/api/canonical/0"


def issue(iid, first_seen, last_seen=None, resolved=False, muted=False, **extra):
    return {"id": iid, "first_seen": first_seen, "last_seen": last_seen or first_seen,
            "is_resolved": resolved, "is_muted": muted, **extra}


@pytest.fixture
def bugsink(http, secrets):
    secrets[("bugsink", SERVER)] = "tok"
    http.add(API + "/projects/", {"results": [{"id": 1, "name": "Shop"}, {"id": 2, "name": "Quiet"}],
                                  "next": None})
    http.add(API + "/issues/?project=1", {"results": [
        issue("n1", iso_ago(hours=2), calculated_type="KeyError", calculated_value="'user'",
              transaction="/checkout", digested_event_count=3),
        issue("o1", iso_ago(days=3), iso_ago(minutes=5)),
        issue("m1", iso_ago(days=3), muted=True),
    ], "next": API + "/issues/page2"})
    http.add(API + "/issues/page2", {"results": [issue("r1", iso_ago(days=9), resolved=True)], "next": None})
    http.add(API + "/issues/?project=2", {"results": [issue("r2", iso_ago(days=1), resolved=True)], "next": None})
    return BugsinkStatus({"server": SERVER})


def test_counts_issues_across_projects_and_pages(bugsink):
    result = bugsink.fetch()
    assert result.counts == {"new": 1, "open": 1, "muted": 1, "resolved": 2}
    assert result.summary == "bugsink.example.com"


def test_lists_open_issues_per_project(bugsink):
    [shop] = bugsink.fetch().sections                   # "Quiet" has nothing open
    assert shop.title == "Shop (2 open)"
    new, old = shop.items
    assert (new.title, new.state, new.bold) == ("KeyError: 'user'", "new", True)
    assert new.subtitle == "/checkout · 3 events · last seen 2 h ago"
    assert new.url == SERVER + "/issues/issue/n1/event/last/"
    assert [a.id for a in new.actions] == ["resolve", "mute"]
    assert (old.title, old.state, old.subtitle) == ("(no message)", "open", "0 events · last seen 5 min ago")


def test_stops_after_max_pages(bugsink, http):
    bugsink.settings["max_pages"] = 1
    assert bugsink.fetch().counts["resolved"] == 1      # page 2 of Shop not read
    assert not any(c["url"].endswith("page2") for c in http.calls)


def test_sends_the_token(bugsink, http):
    bugsink.fetch()
    assert {c["headers"]["Authorization"] for c in http.calls} == {"Bearer tok"}


def test_run_action_posts(bugsink, http):
    http.add(API + "/issues/o1/mute/", None)
    bugsink.run_action("o1", "mute")
    assert http.calls[-1]["url"] == API + "/issues/o1/mute/"
    assert http.calls[-1]["method"] == "POST"
    with pytest.raises(ProviderError, match="Unknown action"):
        bugsink.run_action("o1", "delete")


def test_needs_a_token(secrets):
    with pytest.raises(ProviderError, match="No API token"):
        BugsinkStatus({"server": SERVER}).fetch()


@pytest.mark.parametrize("delta, expected", [
    ({"seconds": 10}, "1 min ago"), ({"minutes": 42}, "42 min ago"), ({"hours": 5}, "5 h ago"),
    ({"days": 3, "hours": 1}, "3 d ago"),
])
def test_ago(delta, expected):
    assert ago(iso_ago(**delta)) == expected
