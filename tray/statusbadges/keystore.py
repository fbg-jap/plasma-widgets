"""API keys in the operating system's credential store (Windows Credential Manager, macOS
Keychain, Secret Service on Linux), never in the settings file."""
import shutil
import subprocess
import sys

import keyring

SERVICE = "status-badges"


def _username(kind: str, server: str) -> str:
    return f"{kind}:{server.rstrip('/')}"


def get(kind: str, server: str) -> str | None:
    key = keyring.get_password(SERVICE, _username(kind, server))
    if key:
        return key
    # On Linux, reuse a key already stored by the KDE Plasma widget of the same kind.
    if sys.platform.startswith("linux") and shutil.which("secret-tool"):
        result = subprocess.run(["secret-tool", "lookup", "service", f"plasma-{kind}", "server", server.rstrip("/")],
                                capture_output=True, text=True)
        return result.stdout.strip() or None
    return None


def set(kind: str, server: str, value: str) -> None:
    keyring.set_password(SERVICE, _username(kind, server), value.strip())


def has(kind: str, server: str) -> bool:
    return bool(server) and get(kind, server) is not None
