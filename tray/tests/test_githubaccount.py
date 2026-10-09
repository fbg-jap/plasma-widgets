import pytest

from conftest import iso_ago
from statusbadges.model import ProviderError
from statusbadges.providers.githubaccount import GitHubAccount, html_url


def notification(nid, title, unread=True, kind="PullRequest", url="https://api.github.com/repos/o/r/pulls/7"):
    return {"id": nid, "unread": unread, "reason": "review_requested", "updated_at": iso_ago(hours=3),
            "subject": {"title": title, "type": kind, "url": url},
            "repository": {"full_name": "o/r", "html_url": "https://github.com/o/r"}}


def pr(number, title, rollup, draft=False):
    commits = [{"commit": {"statusCheckRollup": {"state": rollup} if rollup else None}}]
    return {"title": title, "url": f"https://github.com/o/r/pull/{number}", "number": number, "isDraft": draft,
            "repository": {"nameWithOwner": "o/r"}, "commits": {"nodes": commits}}


def repo(name, rollup):
    target = {"statusCheckRollup": {"state": rollup}} if rollup else {}
    return {"nameWithOwner": name, "url": f"https://github.com/{name}", "pushedAt": iso_ago(days=2),
            "defaultBranchRef": {"target": target}}


GRAPHQL = {"data": {
    "viewer": {
        "login": "octo",
        "pullRequests": {"totalCount": 25, "nodes": [pr(1, "Fix bug", "FAILURE"), pr(2, "WIP", "PENDING", True),
                                                       pr(3, "Docs", None)]},
        "repositories": {"nodes": [repo("o/r", "SUCCESS"), repo("o/empty", None)]},
    },
    "reviews": {"issueCount": 1, "nodes": [{"title": "Add feature", "url": "https://github.com/o/r/pull/9",
                                            "number": 9, "repository": {"nameWithOwner": "o/r"},
                                            "author": {"login": "mona"}}, {}]},
}}


@pytest.fixture
def gh(cli):
    cli.add(["gh", "api", "notifications"], [notification("1", "Please review"),
                                             notification("2", "Old news", unread=False)])
    cli.add(["gh", "api", "graphql"], GRAPHQL)
    return cli


def test_counts(gh):
    result = GitHubAccount({}).fetch()
    assert result.counts == {"reviews": 1, "notifications": 1, "prs": 25,
                             "ci_failing": 1, "ci_running": 1, "ci_passing": 1}
    assert result.summary == "@octo"


def test_sections(gh):
    reviews, notifications, prs, repos = GitHubAccount({}).fetch().sections
    assert reviews.items[0].subtitle == "o/r #9 by mona"
    assert len(reviews.items) == 1                       # entries without a URL (e.g. issues) are skipped
    assert notifications.title == "Notifications (1 unread)"
    assert [(i.bold, i.state) for i in notifications.items] == [(True, "notifications"), (False, "")]
    assert notifications.items[0].subtitle == "o/r · review requested · 3 h ago"
    assert notifications.items[0].url == "https://github.com/o/r/pull/7"
    assert [(i.title, i.state) for i in prs.items] == [
        ("Fix bug", "ci_failing"), ("[Draft] WIP", "ci_running"), ("Docs", "")]
    assert prs.items[2].subtitle == "o/r #3 · no checks"
    assert repos.items[0].subtitle == "checks passed · pushed 2 d ago"
    assert repos.items[0].url == "https://github.com/o/r/actions"


def test_uses_the_chosen_accounts_token(gh):
    gh.add(["gh", "auth", "token"], "gho_secret\n")
    GitHubAccount({"account": "work-account"}).fetch()
    token_call = gh.calls[0]["args"]
    assert token_call[-2:] == ["--user", "work-account"]
    assert all(c["env"]["GH_TOKEN"] == "gho_secret" for c in gh.calls if c["args"][1] == "api")


def test_reports_gh_errors(cli):
    cli.add(["gh"], ProviderError("gh is not installed or not on PATH"))
    with pytest.raises(ProviderError, match="gh is not installed"):
        GitHubAccount({}).fetch()


@pytest.mark.parametrize("subject, expected", [
    ({"type": "PullRequest", "url": "https://api.github.com/repos/o/r/pulls/7"}, "https://github.com/o/r/pull/7"),
    ({"type": "Issue", "url": "https://api.github.com/repos/o/r/issues/3"}, "https://github.com/o/r/issues/3"),
    ({"type": "Commit", "url": "https://api.github.com/repos/o/r/commits/abc"}, "https://github.com/o/r/commit/abc"),
    ({"type": "Release", "url": "https://api.github.com/repos/o/r/releases/1"}, "https://github.com/o/r/releases"),
    ({"type": "CheckSuite", "url": None}, "https://github.com/notifications"),
])
def test_html_url(subject, expected):
    assert html_url({"subject": subject, "repository": {"html_url": "https://github.com/o/r"}}) == expected
