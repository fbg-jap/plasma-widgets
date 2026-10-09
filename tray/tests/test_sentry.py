from urllib.parse import parse_qs, urlsplit

import pytest

from conftest import iso_ago
from statusbadges.model import ProviderError
from statusbadges.providers.sentry import SentryStatus, next_page

SERVER = "https://sentry.example.com"
ISSUES = SERVER + "/api/0/organizations/acme/issues/"


def issue(iid, project, first_seen, last_seen=None, **extra):
    return {"id": iid, "project": {"name": project, "slug": project.lower()}, "firstSeen": first_seen,
            "lastSeen": last_seen or first_seen, **extra}


def link(url=None):
    return f'<{url or ISSUES}>; rel="previous"; results="false", <{url or ISSUES}>; rel="next"; results="{"true" if url else "false"}"'


def hits(n):
    return ([], {"X-Hits": str(n)})


@pytest.fixture
def sentry(http, secrets):
    secrets[("sentry", SERVER)] = "tok"

    def issues(url, params):
        query = parse_qs(urlsplit(url).query)
        if query.get("limit") == ["1"]:
            return hits({"is:unresolved firstSeen:-24h": 1, "is:ignored": 4, "is:resolved": 7}[query["query"][0]])
        if "cursor=2" in url:
            return ([issue("3", "Api", iso_ago(days=5), iso_ago(days=2))], {"X-Hits": "3", "Link": link()})
        return ([issue("1", "Shop", iso_ago(hours=2), title="KeyError: 'user'", culprit="checkout.views", count="12",
                       permalink="https://acme.sentry.io/issues/1/"),
                 issue("2", "Api", iso_ago(days=3), iso_ago(minutes=5), permalink="javascript:alert(1)")],
                {"X-Hits": "3", "Link": link(ISSUES + "?cursor=2")})
    http.add(ISSUES, issues)
    return SentryStatus({"server": SERVER + "/", "organization": "acme"})


def test_counts_from_x_hits(sentry):
    result = sentry.fetch()
    assert result.counts == {"new": 1, "open": 2, "archived": 4, "resolved": 7}
    assert result.summary == "acme · sentry.example.com"


def test_lists_unresolved_issues_per_project(sentry):
    shop, api = sentry.fetch().sections                 # first page only by default
    assert (shop.title, api.title) == ("Shop (1)", "Api (1)")
    [new] = shop.items
    assert (new.title, new.state, new.bold, new.url) == ("KeyError: 'user'", "new", True, "https://acme.sentry.io/issues/1/")
    assert new.subtitle == "checkout.views · 12 events · last seen 2 h ago"
    assert [a.id for a in new.actions] == ["resolve", "archive"]
    [old] = api.items
    assert (old.title, old.state, old.subtitle) == ("(no message)", "open", "0 events · last seen 5 min ago")
    assert old.url == SERVER + "/organizations/acme/issues/2/"   # a non-http permalink isn't used


def test_follows_pages_up_to_max_pages(sentry, http):
    sentry.settings["max_pages"] = 3
    [shop, api] = sentry.fetch().sections
    assert [i.id for i in api.items] == ["2", "3"]
    assert sum("cursor=2" in c["url"] for c in http.calls) == 1


def test_does_not_send_the_token_to_another_host(http, secrets):
    secrets[("sentry", SERVER)] = "tok"
    http.add(ISSUES, ([issue("1", "Shop", iso_ago(days=2))], {"X-Hits": "1", "Link": link("https://evil.example/?cursor=2")}))
    http.add("https://evil.example/", ([], {}))
    SentryStatus({"server": SERVER, "organization": "acme", "max_pages": 3}).fetch()
    assert not any(c["url"].startswith("https://evil.example") for c in http.calls)


def test_asks_every_project_and_sends_the_token(sentry, http):
    sentry.fetch()
    assert all("project=-1" in c["url"] for c in http.calls)
    assert {c["headers"]["Authorization"] for c in http.calls} == {"Bearer tok"}


def test_counts_a_page_without_x_hits(http, secrets):
    secrets[("sentry", SERVER)] = "tok"
    http.add(ISSUES, ([issue("1", "Shop", iso_ago(days=2))], {}))
    assert SentryStatus({"server": SERVER, "organization": "acme"}).fetch().counts == {
        "new": 1, "open": 0, "archived": 1, "resolved": 1}   # each query counts the one-issue fake page


def test_run_action_puts_the_status(sentry, http):
    sentry.run_action("2", "archive")
    assert http.calls[-1]["url"] == ISSUES + "?id=2"
    assert (http.calls[-1]["method"], http.calls[-1]["body"]) == ("PUT", {"status": "ignored"})
    with pytest.raises(ProviderError, match="Unknown action"):
        sentry.run_action("2", "delete")
    with pytest.raises(ProviderError, match="Unknown action"):
        sentry.run_action("2&status=resolved", "resolve")


@pytest.mark.parametrize("settings, message", [
    ({"server": SERVER, "organization": ""}, "No organization"),
    ({"server": SERVER, "organization": "acme"}, "No auth token"),
])
def test_needs_an_organization_and_a_token(secrets, settings, message):
    with pytest.raises(ProviderError, match=message):
        SentryStatus(settings).fetch()


def test_server_defaults_to_sentry_io():
    assert SentryStatus({"organization": "acme"}).server == "https://sentry.io"


def test_next_page():
    assert next_page({"Link": link(ISSUES + "?cursor=2")}) == ISSUES + "?cursor=2"
    assert next_page({"Link": link()}) is None
    assert next_page({}) is None
