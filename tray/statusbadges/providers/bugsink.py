"""Issues from a Bugsink server (canonical API), with resolve and mute."""
from datetime import datetime, timezone

from statusbadges import httpjson, keystore
from statusbadges.model import Action, Item, ProviderError, Result, Section, State
from statusbadges.providers.base import Field, Provider, registry

NEW_WITHIN_HOURS = 24


def hours_since(iso: str) -> float:
    return (datetime.now(timezone.utc) - datetime.fromisoformat(iso.replace("Z", "+00:00"))).total_seconds() / 3600


def ago(iso: str) -> str:
    hours = hours_since(iso)
    if hours < 1:
        return f"{max(int(hours * 60), 1)} min ago"
    return f"{int(hours)} h ago" if hours < 24 else f"{int(hours // 24)} d ago"


@registry.add
class BugsinkStatus(Provider):
    kind = "bugsink"
    name = "Bugsink Status"
    description = "New, open, muted and resolved issues from a Bugsink server, with resolve and mute."
    default_interval = 120
    states = [
        State("new", "New", "plus", "#d71920", 2),
        State("open", "Open", "exclamation", "#ff9800", 1),
        State("muted", "Muted", "muted", "#8a8a8a", 0, shown=False),
        State("resolved", "Resolved", "check", "#7ba700", 0, shown=False),
    ]
    fields = [
        Field("server", "Bugsink server", "text", "", placeholder="https://bugsink.example.com"),
        Field("token", "API token", "secret", "", "Create one in Bugsink under Tokens. Stored in your system keyring."),
        Field("max_pages", "Pages of issues per project", "int", 10,
              "Issues are read most recently seen first; older muted and resolved ones beyond this aren't counted.",
              minimum=1, maximum=100),
    ]

    def _get(self, path_or_url: str, token: str, method: str | None = None):
        url = path_or_url if path_or_url.startswith("http") else self.server + path_or_url
        return httpjson.request(url, headers={"Authorization": f"Bearer {token}"}, method=method,
                                body={} if method == "POST" else None, auth_name="Bugsink")

    def _paged(self, path: str, token: str, max_pages: int) -> tuple[list, bool]:
        url, pages, results = path, 0, []
        while url and pages < max_pages:
            page = self._get(url, token)
            results += page["results"]
            url, pages = page.get("next"), pages + 1
        return results, bool(url)

    def _token(self) -> str:
        if not self.server:
            raise ProviderError("No Bugsink server set. Open the settings to add one.")
        token = keystore.get(self.kind, self.server)
        if not token:
            raise ProviderError("No API token stored for this server. Add it in the settings.")
        return token

    def fetch(self) -> Result:
        token = self._token()
        projects, _ = self._paged("/api/canonical/0/projects/", token, 20)
        counts = {"new": 0, "open": 0, "muted": 0, "resolved": 0}
        sections = []
        for project in projects:
            issues, _ = self._paged(f"/api/canonical/0/issues/?project={project['id']}&sort=last_seen&order=desc",
                                    token, int(self.setting("max_pages")))
            items = []
            for i in issues:
                if i.get("is_resolved"):
                    counts["resolved"] += 1
                elif i.get("is_muted"):
                    counts["muted"] += 1
                else:
                    state = "new" if hours_since(i["first_seen"]) < NEW_WITHIN_HOURS else "open"
                    counts[state] += 1
                    title = ": ".join(t for t in (i.get("calculated_type"), i.get("calculated_value")) if t) or "(no message)"
                    events = i.get("digested_event_count") or 0
                    items.append(Item(i["id"], title,
                                      " · ".join(t for t in (i.get("transaction"), f"{events} events",
                                                             f"last seen {ago(i['last_seen'])}") if t),
                                      state, f"{self.server}/issues/issue/{i['id']}/event/last/", bold=state == "new",
                                      actions=[Action("resolve", "Resolve", "check"), Action("mute", "Mute", "muted")]))
            if items:
                sections.append(Section(f"{project['name']} ({len(items)} open)", items))
        return Result(counts, sections, self.server.split("://", 1)[-1])

    def run_action(self, item_id: str, action: str) -> None:
        if action not in ("resolve", "mute"):
            raise ProviderError(f"Unknown action {action}")
        self._get(f"/api/canonical/0/issues/{item_id}/{action}/", self._token(), method="POST")
