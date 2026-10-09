"""Your own GitHub workload, through the GitHub CLI's stored login (no token handling here)."""
import json
import os
from datetime import datetime, timezone

from statusbadges import process
from statusbadges.model import Item, ProviderError, Result, Section, State
from statusbadges.providers.base import Field, Provider, registry

QUERY = """{
  viewer {
    login
    pullRequests(states: OPEN, first: 20, orderBy: {field: UPDATED_AT, direction: DESC}) {
      totalCount
      nodes { title url number isDraft repository { nameWithOwner }
              commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }
    }
    repositories(first: 8, orderBy: {field: PUSHED_AT, direction: DESC},
                 ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER]) {
      nodes { nameWithOwner url pushedAt defaultBranchRef { target { ... on Commit { statusCheckRollup { state } } } } }
    }
  }
  reviews: search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 20) {
    issueCount
    nodes { ... on PullRequest { title url number repository { nameWithOwner } author { login } } }
  }
}"""
CI_STATE = {"SUCCESS": "ci_passing", "FAILURE": "ci_failing", "ERROR": "ci_failing",
            "PENDING": "ci_running", "EXPECTED": "ci_running"}


def ago(iso: str) -> str:
    minutes = int((datetime.now(timezone.utc) - datetime.fromisoformat(iso.replace("Z", "+00:00"))).total_seconds() // 60)
    if minutes < 60:
        return f"{max(minutes, 1)} min ago"
    if minutes < 24 * 60:
        return f"{minutes // 60} h ago"
    return f"{minutes // (24 * 60)} d ago"


def html_url(notification: dict) -> str:
    subject = notification["subject"]
    if subject.get("type") == "Release":
        return notification["repository"]["html_url"] + "/releases"
    if not subject.get("url"):
        return "https://github.com/notifications"
    return (subject["url"].replace("https://api.github.com/repos/", "https://github.com/")
            .replace("/pulls/", "/pull/").replace("/commits/", "/commit/"))


@registry.add
class GitHubAccount(Provider):
    kind = "githubaccount"
    name = "GitHub Account"
    description = "Review requests, notifications, your pull requests and CI, through the GitHub CLI (gh)."
    default_interval = 180
    states = [
        State("reviews", "Review requests", "eye", "#0969da", 1),
        State("notifications", "Unread notifications", "bell", "#6e7781", 1),
        State("prs", "Open pull requests", "merge", "#1a7f37", 0),
        State("ci_failing", "CI failing", "cross", "#cf222e", 3),
        State("ci_running", "CI running", "restart", "#bf8700", 1),
        State("ci_passing", "CI passing", "check", "#1a7f37", 0),
    ]
    fields = [Field("account", "GitHub account", "choice", "",
                    "Accounts come from \"gh auth login\". Empty uses gh's active account.")]

    @classmethod
    def choices(cls, key: str) -> list[str]:
        try:
            out = process.run(["gh", "auth", "status", "--json", "hosts", "--jq", ".hosts[][] | .login"])
        except ProviderError:
            return []
        return [line for line in out.splitlines() if line.strip()]

    @classmethod
    def problem_states(cls) -> set[str]:
        return {"ci_failing", "reviews", "notifications"}

    def _gh(self, *args: str) -> str:
        env = dict(os.environ)
        account = str(self.setting("account")).strip()
        if account:
            env["GH_TOKEN"] = process.run(["gh", "auth", "token", "--hostname", "github.com", "--user", account]).strip()
        return process.run(["gh", *args], env=env)

    def fetch(self) -> Result:
        notifications = json.loads(self._gh("api", "notifications", "-X", "GET", "-f", "per_page=30"))
        data = json.loads(self._gh("api", "graphql", "-f", f"query={QUERY}"))["data"]
        viewer = data["viewer"]

        prs = []
        for pr in viewer["pullRequests"]["nodes"]:
            commits = pr["commits"]["nodes"]
            rollup = commits[0]["commit"]["statusCheckRollup"] if commits else None
            prs.append((pr, CI_STATE.get(rollup["state"]) if rollup else None))
        repos = []
        for r in viewer["repositories"]["nodes"]:
            target = (r.get("defaultBranchRef") or {}).get("target") or {}
            rollup = target.get("statusCheckRollup")
            repos.append((r, CI_STATE.get(rollup["state"]) if rollup else None))

        unread = [n for n in notifications if n.get("unread")]
        ci = [s for _, s in prs + repos if s]
        counts = {"reviews": data["reviews"]["issueCount"], "notifications": len(unread),
                  "prs": viewer["pullRequests"]["totalCount"],
                  "ci_failing": ci.count("ci_failing"), "ci_running": ci.count("ci_running"),
                  "ci_passing": ci.count("ci_passing")}
        ci_label = {"ci_passing": "checks passed", "ci_failing": "checks failed", "ci_running": "checks running", None: "no checks"}

        sections = []
        reviews = [r for r in data["reviews"]["nodes"] if r.get("url")]
        if reviews:
            sections.append(Section("Review requested", [
                Item(r["url"], r["title"], f'{r["repository"]["nameWithOwner"]} #{r["number"]} by '
                     f'{(r.get("author") or {}).get("login", "unknown")}', "reviews", r["url"], bold=True)
                for r in reviews]))
        if notifications:
            sections.append(Section(f"Notifications ({len(unread)} unread)", [
                Item("n" + n["id"], n["subject"]["title"],
                     f'{n["repository"]["full_name"]} · {n["reason"].replace("_", " ")} · {ago(n["updated_at"])}',
                     "notifications" if n.get("unread") else "", html_url(n), bold=bool(n.get("unread")))
                for n in notifications]))
        if prs:
            sections.append(Section("Your open pull requests", [
                Item(pr["url"], ("[Draft] " if pr["isDraft"] else "") + pr["title"],
                     f'{pr["repository"]["nameWithOwner"]} #{pr["number"]} · {ci_label[state]}', state or "", pr["url"])
                for pr, state in prs]))
        if repos:
            sections.append(Section("Recently pushed repositories", [
                Item(r["url"], r["nameWithOwner"], f'{ci_label[state]} · pushed {ago(r["pushedAt"])}',
                     state or "", r["url"] + "/actions")
                for r, state in repos]))
        return Result(counts, sections, "@" + viewer["login"])
