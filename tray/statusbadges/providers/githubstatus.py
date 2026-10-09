"""GitHub's service health from the public status feed at githubstatus.com."""
from statusbadges import httpjson
from statusbadges.model import Item, Result, Section, State
from statusbadges.providers.base import Provider, registry

PAGE = "https://www.githubstatus.com"
IMPACT_STATE = {"critical": "major_outage", "major": "partial_outage", "minor": "degraded_performance",
                "maintenance": "under_maintenance", "none": "under_maintenance"}


@registry.add
class GitHubStatus(Provider):
    kind = "githubstatus"
    name = "GitHub Status"
    description = "GitHub's service health from githubstatus.com. No account needed."
    default_interval = 300
    states = [
        State("major_outage", "Major outage", "cross", "#cb2431", 3),
        State("partial_outage", "Partial outage", "exclamation", "#e36209", 2),
        State("degraded_performance", "Degraded performance", "wave", "#dbab09", 2),
        State("under_maintenance", "Under maintenance", "gear", "#0366d6", 1),
        State("operational", "Operational", "check", "#28a745", 0),
    ]

    def fetch(self) -> Result:
        data = httpjson.request(PAGE + "/api/v2/summary.json", auth_name="githubstatus.com")
        components = [c for c in data["components"] if not c.get("group") and not c["name"].startswith("Visit ")]
        counts = {}
        for c in components:
            counts[c["status"]] = counts.get(c["status"], 0) + 1
        labels = {s.key: s.label for s in self.states}
        sections = []
        incidents = data.get("incidents", []) + [m for m in data.get("scheduled_maintenances", [])
                                                   if m.get("status") == "in_progress"]
        if incidents:
            sections.append(Section("Active incidents", [
                Item(i["id"], i["name"], f'{i["status"].replace("_", " ")} · {i.get("impact", "")} impact',
                     IMPACT_STATE.get(i.get("impact"), "under_maintenance"), i.get("shortlink", PAGE), bold=True)
                for i in incidents]))
        sections.append(Section("Components", [
            Item(c["id"], c["name"], labels.get(c["status"], c["status"]), c["status"], PAGE)
            for c in components]))
        return Result(counts, sections, data["status"]["description"])
