"""What a provider hands back after a check: per-state counts and the items to list."""
from dataclasses import dataclass, field


@dataclass
class State:
    """One kind of badge, e.g. "down" or "running", in panel order (worst first)."""
    key: str
    label: str
    glyph: str           # a key of the vector symbols in qml/Glyph.qml
    color: str
    severity: int = 0    # 3 critical, 2 warning, 1 attention, 0 fine; drives the tray icon colour
    shown: bool = True   # default for the "show this badge" setting


@dataclass
class Action:
    id: str              # passed back to Provider.run_action
    label: str
    glyph: str


@dataclass
class Item:
    id: str
    title: str
    subtitle: str = ""
    state: str = ""      # a State.key; colours the item's dot
    url: str = ""
    bold: bool = False
    actions: list[Action] = field(default_factory=list)


@dataclass
class Section:
    title: str
    items: list[Item]


@dataclass
class Result:
    counts: dict[str, int]
    sections: list[Section] = field(default_factory=list)
    summary: str = ""    # one line under the widget's name, e.g. "All Systems Operational"


class ProviderError(Exception):
    """A failure to show the user as is, e.g. "PRTG rejected the API key (401)"."""
