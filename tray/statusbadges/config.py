"""Settings in a JSON file in the platform's config directory. Keys live in the keyring, not here."""
import json
import os
import uuid
from pathlib import Path

from platformdirs import user_config_dir

APP_NAME = "StatusBadges"
PATH = Path(os.environ.get("STATUS_BADGES_CONFIG") or Path(user_config_dir(APP_NAME, appauthor=False)) / "config.json")
DEFAULTS = {"widgets": [], "badgeStyle": "square", "startAtLogin": False}


def load() -> dict:
    try:
        data = json.loads(PATH.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        data = {}
    return {**DEFAULTS, **data}


def save(data: dict) -> None:
    PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2), encoding="utf-8")
    tmp.replace(PATH)


def new_widget(kind: str, name: str, interval: int) -> dict:
    return {"id": uuid.uuid4().hex[:12], "kind": kind, "name": name, "interval": interval,
            "hiddenStates": [], "showZero": False, "showTotal": False, "notify": True}
