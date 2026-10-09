"""Unresolved issues across a Sentry organization (sentry.io or self-hosted), with resolve and archive."""
import re
import urllib.parse

from statusbadges import httpjson, keystore
from statusbadges.model import Action, Item, ProviderError, Result, Section, State
from statusbadges.providers.base import Field, Provider, registry
from statusbadges.providers.bugsink import NEW_WITHIN_HOURS, ago, hours_since

PERIOD = "90d"   # Sentry's usual retention; the counts cover issues seen in this window
STATUS_FOR_ACTION = {"resolve": "resolved", "archive": "ignored"}


def next_page(headers) -> str | None:
    """The next page's URL from Sentry's Link header, or None."""
    for part in (headers.get("Link") or "").split(","):
        match = re.search(r'<([^>]+)>;\s*rel="next";\s*results="(true|false)"', part)
        if match and match.group(2) == "true":
            return match.group(1)
    return None


@registry.add
class SentryStatus(Provider):
    kind = "sentry"
    name = "Sentry Status"
    description = "New, open, archived and resolved issues across a Sentry organization, with resolve and archive."
    default_interval = 120
    states = [
        State("new", "New", "plus", "#e1567c", 2),
        State("open", "Open", "exclamation", "#f2b712", 1),
        State("archived", "Archived", "muted", "#8a8a8a", 0, shown=False),
        State("resolved", "Resolved", "check", "#2ba185", 0, shown=False),
    ]
    fields = [
        Field("server", "Sentry server", "text", "https://sentry.io",
              "https://sentry.io, https://de.sentry.io for EU organizations, or your own.",
              placeholder="https://sentry.io"),
        Field("organization", "Organization slug", "text", "", "As in the Sentry address.", placeholder="my-org"),
        Field("token", "Auth token", "secret", "",
              "A personal token with the event:read and event:write scopes. Stored in your system keyring."),
        Field("max_pages", "Pages of 100 unresolved issues to list", "int", 1,
              "Most recently seen first. The badge counts cover every issue regardless.", minimum=1, maximum=20),
    ]

    @property
    def organization(self) -> str:
        return str(self.setting("organization")).strip()

    def _issues_url(self, query: str, **params) -> str:
        # project=-1: every project the token can see, not only the user's own ones.
        query_string = urllib.parse.urlencode({"project": -1, "statsPeriod": PERIOD, "query": query, **params})
        return f"{self.server}/api/0/organizations/{urllib.parse.quote(self.organization)}/issues/?{query_string}"

    def _get(self, url: str, token: str, method: str | None = None, body=None):
        return httpjson.request(url, headers={"Authorization": f"Bearer {token}"}, method=method, body=body,
                                auth_name="Sentry", with_headers=True)

    def _hits(self, token: str, query: str) -> int:
        """How many issues match: Sentry's X-Hits header, read from a one-issue page. Without that
        header, the issues on a full page are counted instead (so at most 100)."""
        _, headers = self._get(self._issues_url(query, limit=1), token)
        try:
            return int(headers.get("X-Hits"))
        except (TypeError, ValueError):
            results, _ = self._get(self._issues_url(query, limit=100), token)
            return len(results or [])

    def _same_server(self, url: str | None) -> str | None:
        """A next-page URL, only when it's on our server, so the token is never sent elsewhere."""
        if url and urllib.parse.urlsplit(url)[:2] == urllib.parse.urlsplit(self.server)[:2]:
            return url
        return None

    def _token(self) -> str:
        if not self.server:
            raise ProviderError("No Sentry server set. Open the settings to add one.")
        if not self.organization:
            raise ProviderError("No organization set. Open the settings to add its slug.")
        token = keystore.get(self.kind, self.server)
        if not token:
            raise ProviderError("No auth token stored for this server. Add it in the settings.")
        return token

    def _issue_url(self, issue: dict) -> str:
        if re.fullmatch(r"https?://\S+", issue.get("permalink") or "", re.I):
            return issue["permalink"]
        return f"{self.server}/organizations/{urllib.parse.quote(self.organization)}/issues/{issue['id']}/"

    def fetch(self) -> Result:
        token = self._token()
        issues, url, pages, unresolved = [], self._issues_url("is:unresolved", sort="date", limit=100), 0, None
        while url and pages < int(self.setting("max_pages")):
            results, headers = self._get(url, token)
            if unresolved is None and headers.get("X-Hits"):
                unresolved = int(headers.get("X-Hits"))
            issues += results or []
            url, pages = self._same_server(next_page(headers)), pages + 1
        new = self._hits(token, "is:unresolved firstSeen:-24h")
        unresolved = unresolved if unresolved is not None else len(issues)
        counts = {"new": new, "open": max(unresolved - new, 0),
                  "archived": self._hits(token, "is:ignored"), "resolved": self._hits(token, "is:resolved")}

        new_ids = {i["id"] for i in issues if i.get("firstSeen") and hours_since(i["firstSeen"]) < NEW_WITHIN_HOURS}
        by_project: dict[str, list[dict]] = {}
        for i in issues:   # most recently seen first, so projects come out most recently active first
            project = i.get("project") or {}
            by_project.setdefault(project.get("name") or project.get("slug") or "", []).append(i)
        sections = []
        for project, project_issues in by_project.items():
            items = []
            for i in project_issues:
                state = "new" if i["id"] in new_ids else "open"
                events = i.get("count") or 0
                items.append(Item(i["id"], i.get("title") or "(no message)",
                                  " · ".join(t for t in (i.get("culprit"), f"{events} events",
                                                         f"last seen {ago(i['lastSeen'])}" if i.get("lastSeen") else "")
                                             if t),
                                  state, self._issue_url(i), bold=state == "new",
                                  actions=[Action("resolve", "Resolve", "check"), Action("archive", "Archive", "muted")]))
            sections.append(Section(f"{project or 'Issues'} ({len(items)})", items))
        return Result(counts, sections, f"{self.organization} · {self.server.split('://', 1)[-1]}")

    def run_action(self, item_id: str, action: str) -> None:
        if action not in STATUS_FOR_ACTION or not re.fullmatch(r"[0-9]+", item_id):
            raise ProviderError(f"Unknown action {action}")
        self._get(f"{self.server}/api/0/organizations/{urllib.parse.quote(self.organization)}/issues/?id={item_id}",
                  self._token(), method="PUT", body={"status": STATUS_FOR_ACTION[action]})

