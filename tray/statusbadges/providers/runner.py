"""Self-hosted GitHub Actions runners, from a runner dashboard's /api/status."""
import re
import time

from statusbadges import httpjson
from statusbadges.model import Item, ProviderError, Result, Section, State
from statusbadges.providers.base import Field, Provider, registry


def runner_state(runner: dict) -> str:
    """The dashboard reports idle, busy or offline. Anything else (e.g. a runner whose service
    isn't loaded) counts as offline, so it still gets a red badge."""
    return runner.get("status") if runner.get("status") in ("busy", "idle") else "offline"


def title(runner: dict) -> str:
    """Several runners can share a name (one per repository), so the repository is the title."""
    return runner.get("repo") or runner.get("name") or ""


def last_job(runner: dict) -> dict | None:
    return max(runner.get("history") or [], key=lambda j: j.get("finished") or 0, default=None)


def job_failed(job: dict | None) -> bool:
    return bool(job) and job.get("result") not in ("Succeeded", "Canceled", "Skipped")


def actions_url(runner: dict) -> str:
    """The running job's page on GitHub, or the repository's Actions page. The URL comes from the
    dashboard (over plain http), so only http(s) links are used, never file: or other schemes."""
    repo_url = runner.get("repo_url") or ""
    if not re.fullmatch(r"https?://\S+", repo_url, re.I):
        return ""
    job = runner.get("job") or {}
    return f"{repo_url}/actions/runs/{job['run_id']}" if job.get("run_id") else f"{repo_url}/actions"


def duration(seconds) -> str:
    """Seconds as "45s", "3m 12s", "2h 5m" or "4d 3h"."""
    if seconds is None:
        return "–"
    s = max(0, round(seconds))
    d, h, m = s // 86400, s % 86400 // 3600, s % 3600 // 60
    return f"{d}d {h}h" if d else f"{h}h {m}m" if h else f"{m}m {s % 60}s" if m else f"{s}s"


@registry.add
class RunnerStatus(Provider):
    kind = "runner"
    name = "Runner Status"
    description = "Self-hosted GitHub Actions runners (idle, busy, offline) from a runner dashboard."
    default_interval = 15
    notify_on_return = True
    states = [
        State("offline", "Offline", "cross", "#cf222e", 3),
        State("busy", "Busy", "play", "#bf8700", 1),
        State("idle", "Idle", "check", "#1a7f37", 0),
    ]
    fields = [
        Field("server", "Runner dashboard", "text", "", "Its /api/status is read. No key needed.",
              placeholder="http://192.168.1.10:8089"),
    ]

    def fetch(self) -> Result:
        if not self.server:
            raise ProviderError("No runner dashboard set. Open the settings to add its address.")
        data = httpjson.request(self.server + "/api/status", auth_name="The runner dashboard")
        if not isinstance(data, dict) or not isinstance(data.get("runners"), list):
            raise ProviderError("The runner dashboard sent an unexpected response")
        now = data.get("now") or time.time()   # the server's clock, so durations don't depend on ours
        order = [s.key for s in self.states]
        runners = sorted(data["runners"], key=lambda r: (order.index(runner_state(r)), title(r)))
        counts: dict[str, int] = {}
        items = []
        for r in runners:
            state = runner_state(r)
            counts[state] = counts.get(state, 0) + 1
            job, last = r.get("job"), last_job(r)
            if job:
                detail = (f"{job.get('job') or 'job'} in {job.get('workflow') or 'workflow'}"
                          f" · running {duration(now - job['started']) if job.get('started') else '–'}")
            elif last:
                detail = (f"{last.get('name') or 'job'} {(last.get('result') or '').lower()}"
                          f" {duration(now - last['finished']) + ' ago' if last.get('finished') else ''}").strip()
            else:
                detail = "no jobs yet"
            parts = [r.get("name") if r.get("name") != title(r) else "", detail,
                     f"up {duration(r.get('uptime'))}" if state != "offline" and r.get("uptime") else ""]
            items.append(Item(r.get("dir") or title(r), title(r), " · ".join(p for p in parts if p), state,
                              actions_url(r), bold=state == "offline" or (not job and job_failed(last))))
        host = data.get("host") or {}
        summary = " · ".join(p for p in (host.get("hostname"), f"load {' / '.join(map(str, host['load']))}"
                                         if host.get("load") else "") if p)
        return Result(counts, [Section("Runners", items)] if items else [], summary)
