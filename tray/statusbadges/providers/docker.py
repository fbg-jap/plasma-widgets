"""Docker containers through the docker CLI, for any docker context (local, Podman, remote)."""
import json
import re

from statusbadges import process
from statusbadges.model import Action, Item, ProviderError, Result, Section, State
from statusbadges.providers.base import Field, Provider, registry

# Exit codes that mean "stopped on purpose": clean exit, Ctrl+C, docker stop's SIGTERM or SIGKILL.
STOPPED_EXIT_CODES = {0, 130, 137, 143}


def label(labels: str, key: str) -> str:
    match = re.search(r"(?:^|,)" + re.escape(key) + r"=([^,]*)", labels or "")
    return match.group(1) if match else ""


def classify(c: dict) -> str:
    state, status = c.get("State", ""), c.get("Status", "")
    if state == "restarting":
        return "restarting"
    if state == "paused":
        return "paused"
    if state == "running":
        return "unhealthy" if c.get("HealthStatus") == "unhealthy" or "(unhealthy)" in status else "running"
    if state == "dead":
        return "failed"
    if state == "exited":
        exit_code = re.search(r"Exited \((\d+)\)", status)
        return "failed" if exit_code and int(exit_code.group(1)) not in STOPPED_EXIT_CODES else "stopped"
    return "stopped"


def short_ports(ports: str) -> str:
    seen = []
    for host, container in re.findall(r":(\d+)->(\d+)", ports or ""):
        if f"{host}→{container}" not in seen:
            seen.append(f"{host}→{container}")
    return ", ".join(seen)


@registry.add
class DockerStatus(Provider):
    kind = "docker"
    name = "Docker Status"
    description = "Your Docker containers, with start, stop and restart. Needs the docker CLI."
    default_interval = 15
    states = [
        State("failed", "Failed", "cross", "#d71920", 3),
        State("unhealthy", "Unhealthy", "exclamation", "#e5534b", 3),
        State("restarting", "Restarting", "restart", "#ff9800", 2),
        State("paused", "Paused", "pause", "#2a72d6", 1),
        State("stopped", "Stopped", "stop", "#8a8a8a", 0),
        State("running", "Running", "play", "#7ba700", 0),
    ]
    fields = [Field("context", "Docker context", "choice", "",
                    "From \"docker context ls\", e.g. a Podman machine or remote host. Empty uses the current context.")]

    @classmethod
    def choices(cls, key: str) -> list[str]:
        try:
            out = process.run(["docker", "context", "ls", "--format", "{{.Name}}"])
        except ProviderError:
            return []
        return [line for line in out.splitlines() if line.strip()]

    def _docker(self, *args: str) -> str:
        context = str(self.setting("context")).strip()
        return process.run(["docker", *(["--context", context] if context else []), *args])

    def fetch(self) -> Result:
        out = self._docker("ps", "--all", "--no-trunc", "--format", "{{json .}}")
        containers = [json.loads(line) for line in out.splitlines() if line.strip()]
        order = [s.key for s in self.states]
        counts, groups = {}, {}
        for c in containers:
            state = classify(c)
            counts[state] = counts.get(state, 0) + 1
            project = label(c.get("Labels", ""), "com.docker.compose.project")
            name = label(c.get("Labels", ""), "com.docker.compose.service") or c["Names"]
            image = c["Image"][7:19] if c["Image"].startswith("sha256:") else c["Image"]
            active = state in ("running", "unhealthy", "restarting")
            actions = ([Action("restart", "Restart", "restart"), Action("stop", "Stop", "stop")] if active
                       else [] if state == "paused" else [Action("start", "Start", "play")])
            item = Item(c["ID"], name, " · ".join(t for t in (image, c["Status"], short_ports(c.get("Ports", ""))) if t),
                        state, bold=state in ("failed", "unhealthy"), actions=actions)
            groups.setdefault(project, []).append(item)
        sections = [Section(project or "Standalone containers",
                            sorted(items, key=lambda i: (order.index(i.state), i.title)))
                    for project, items in sorted(groups.items(), key=lambda kv: (kv[0] == "", kv[0]))]
        context = str(self.setting("context")).strip()
        return Result(counts, sections, context or "current context")

    def run_action(self, item_id: str, action: str) -> None:
        if action not in ("start", "stop", "restart"):
            raise ProviderError(f"Unknown action {action}")
        self._docker(action, item_id)
