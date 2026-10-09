"""Applications, compose stacks and databases on a Dokploy server, with deploy, start and stop.
Only names and statuses are read; database passwords and environment variables are never kept."""
from statusbadges import httpjson, keystore
from statusbadges.model import Action, Item, ProviderError, Result, Section, State
from statusbadges.providers.base import Field, Provider, registry

DATABASE_TYPES = ("postgres", "mysql", "mariadb", "mongo", "redis")
TYPE_LABELS = {"application": "Application", "compose": "Compose", "postgres": "PostgreSQL", "mysql": "MySQL",
               "mariadb": "MariaDB", "mongo": "MongoDB", "redis": "Redis"}


@registry.add
class DokployStatus(Provider):
    kind = "dokploy"
    name = "Dokploy Status"
    description = "Deployments on a Dokploy server, with deploy, start and stop."
    default_interval = 60
    states = [
        State("error", "Failed", "cross", "#d71920", 3),
        State("running", "Deploying", "restart", "#ff9800", 1),
        State("done", "Deployed", "check", "#7ba700", 0),
        State("idle", "Idle", "stop", "#8a8a8a", 0),
    ]
    fields = [
        Field("server", "Dokploy server", "text", "", placeholder="https://dokploy.example.com"),
        Field("apikey", "API key", "secret", "",
              "Generate one in Dokploy under Settings → Profile → API/CLI. Stored in your system keyring."),
    ]

    def _call(self, endpoint: str, params: dict | None = None, body: dict | None = None):
        if not self.server:
            raise ProviderError("No Dokploy server set. Open the settings to add one.")
        key = keystore.get(self.kind, self.server)
        if not key:
            raise ProviderError("No API key stored for this server. Add it in the settings.")
        return httpjson.request(f"{self.server}/api/{endpoint}", headers={"x-api-key": key}, params=params,
                                body=body, auth_name="Dokploy")

    def fetch(self) -> Result:
        counts, sections = {}, []
        order = [s.key for s in self.states]
        for project in self._call("project.all"):
            environments = project.get("environments", [])
            for env in environments:
                services = []
                for app in env.get("applications") or []:
                    services.append(("application", app["applicationId"], app["name"], app.get("applicationStatus")))
                for compose in env.get("compose") or []:
                    services.append(("compose", compose["composeId"], compose["name"], compose.get("composeStatus")))
                for db_type in DATABASE_TYPES:
                    for db in env.get(db_type) or []:
                        db_id = db[f"{db_type}Id"]
                        detail = self._call(f"{db_type}.one", {f"{db_type}Id": db_id}) or {}
                        services.append((db_type, db_id, detail.get("name", db_type), detail.get("applicationStatus")))
                if not services:
                    continue
                items = []
                for kind, sid, name, status in services:
                    state = status if status in order else "idle"
                    counts[state] = counts.get(state, 0) + 1
                    actions = [] if state == "running" else [Action("deploy", "Deploy", "upload")]
                    if state == "idle":
                        actions.append(Action("start", "Start", "play"))
                    elif state in ("done", "error"):
                        actions.append(Action("stop", "Stop", "stop"))
                    items.append(Item(f"{kind}:{sid}", name, f"{TYPE_LABELS.get(kind, kind)} · "
                                      f"{next(s.label for s in self.states if s.key == state)}", state,
                                      f"{self.server}/dashboard/project/{project['projectId']}/environment/"
                                      f"{env['environmentId']}/services/{kind}/{sid}",
                                      bold=state == "error", actions=actions))
                title = f"{project['name']} · {env['name']}" if len(environments) > 1 else project["name"]
                sections.append(Section(title, sorted(items, key=lambda i: (order.index(i.state), i.title))))
        return Result(counts, sections, self.server.split("://", 1)[-1])

    def run_action(self, item_id: str, action: str) -> None:
        kind, sid = item_id.split(":", 1)
        if action not in ("deploy", "start", "stop") or kind not in TYPE_LABELS:
            raise ProviderError(f"Unknown action {action} for {kind}")
        self._call(f"{kind}.{action}", body={f"{kind}Id": sid})

    def fast_poll(self, result: Result) -> bool:
        """While something is deploying, check every few seconds."""
        return result.counts.get("running", 0) > 0
