"""Sensors from a PRTG Network Monitor server, like PRTG's own status bar."""
from statusbadges import httpjson, keystore
from statusbadges.model import Item, ProviderError, Result, Section, State
from statusbadges.providers.base import Field, Provider, registry

STATE_CODES = {"down": [5, 14], "acknowledged": [13], "warning": [4], "unusual": [10],
               "unknown": [1, 2, 6], "paused": [7, 8, 9, 11, 12], "up": [3]}


@registry.add
class PRTGStatus(Provider):
    kind = "prtg"
    name = "PRTG Status"
    description = "Down, warning, unusual, paused and up sensors from a PRTG server."
    default_interval = 120
    states = [
        State("down", "Down", "cross", "#d71920", 3),
        State("acknowledged", "Down (acknowledged)", "cross", "#e77579", 1),
        State("warning", "Warning", "exclamation", "#ffcb05", 2),
        State("unusual", "Unusual", "wave", "#ff9800", 2),
        State("unknown", "Unknown", "dash", "#8a8a8a", 1),
        State("paused", "Paused", "pause", "#2a72d6", 0),
        State("up", "Up", "check", "#7ba700", 0),
    ]
    fields = [
        Field("server", "PRTG server", "text", "", placeholder="https://prtg.example.com"),
        Field("apikey", "API key", "secret", "",
              "A read-only key from PRTG: Setup → Account Settings → API Keys. Stored in your system keyring."),
    ]

    def _table(self, key: str, **params) -> dict:
        query = {"content": "sensors", "apitoken": key, **params}
        return httpjson.request(f"{self.server}/api/table.json", params=query, auth_name="PRTG")

    def fetch(self) -> Result:
        if not self.server:
            raise ProviderError("No PRTG server set. Open the settings to add one.")
        key = keystore.get(self.kind, self.server)
        if not key:
            raise ProviderError("No API key stored for this server. Add it in the settings.")
        problems = self._table(key, count=500, columns="objid,device,sensor,status_raw,message_raw,lastvalue",
                               filter_status=[4, 5, 10, 13, 14])["sensors"]
        everything = self._table(key, count=50000, columns="objid,status_raw")["sensors"]

        def state_of(raw):
            return next((k for k, codes in STATE_CODES.items() if raw in codes), "unknown")

        counts = {}
        for s in everything:
            key_ = state_of(s["status_raw"])
            counts[key_] = counts.get(key_, 0) + 1
        sections = []
        for state, title in (("down", "Down"), ("warning", "Warning"), ("unusual", "Unusual"), ("acknowledged", "Acknowledged")):
            sensors = [s for s in problems if state_of(s["status_raw"]) == state]
            if sensors:
                sections.append(Section(title, [
                    Item(str(s["objid"]), f'{s["device"]} – {s["sensor"]}',
                         " · ".join(t for t in (s.get("lastvalue"), s.get("message_raw")) if t and t != "-"),
                         state, f'{self.server}/sensor.htm?id={s["objid"]}', bold=state == "down")
                    for s in sensors]))
        host = self.server.split("://", 1)[-1]
        return Result(counts, sections, host)
