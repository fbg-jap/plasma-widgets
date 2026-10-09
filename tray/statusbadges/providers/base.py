"""The interface every service (GitHub, PRTG, Docker, ...) implements."""
from dataclasses import dataclass, field

from statusbadges.model import Result, State


@dataclass
class Field:
    """One provider-specific setting, shown in the settings window."""
    key: str
    label: str
    type: str = "text"       # text | secret | int | choice
    default: object = ""
    help: str = ""
    placeholder: str = ""
    minimum: int = 1
    maximum: int = 100


class Provider:
    """Fetches one service. Subclasses set the class attributes and implement fetch()."""

    kind = ""                # stable id, used in the settings file and the keyring
    name = ""                # shown to the user, e.g. "PRTG Status"
    description = ""
    default_interval = 120   # seconds between checks
    states: list[State] = []
    fields: list[Field] = []
    # Notify again when an item comes back to a problem state after leaving it, e.g. a runner that
    # goes offline twice. Off for issues, which shouldn't count as new when they reopen.
    notify_on_return = False

    def __init__(self, settings: dict):
        self.settings = settings

    def setting(self, key: str):
        value = self.settings.get(key)
        if value in (None, ""):
            default = next((f.default for f in self.fields if f.key == key), "")
            return default
        return value

    @property
    def server(self) -> str:
        return str(self.setting("server")).strip().rstrip("/")

    def fetch(self) -> Result:
        raise NotImplementedError

    def run_action(self, item_id: str, action: str) -> None:
        """Performs an item's action, e.g. ("<container id>", "restart")."""
        raise NotImplementedError

    @classmethod
    def choices(cls, key: str) -> list[str]:
        """Values to offer for a "choice" field, e.g. the logged-in gh accounts."""
        return []

    @classmethod
    def problem_states(cls) -> set[str]:
        """States that trigger a notification when an item newly enters them."""
        return {s.key for s in cls.states if s.severity >= 2}


@dataclass
class Registry:
    providers: dict[str, type[Provider]] = field(default_factory=dict)

    def add(self, provider: type[Provider]) -> type[Provider]:
        self.providers[provider.kind] = provider
        return provider


registry = Registry()
