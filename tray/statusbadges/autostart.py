"""Start at login on Windows (Run registry key), macOS (LaunchAgent) and Linux (XDG autostart)."""
import os
import plistlib
import sys
from pathlib import Path

NAME = "StatusBadges"


def command() -> list[str]:
    if getattr(sys, "frozen", False):        # packaged with PyInstaller
        return [sys.executable]
    python = sys.executable
    if sys.platform == "win32" and python.endswith("python.exe"):
        python = python[:-len("python.exe")] + "pythonw.exe"   # no console window
    return [python, "-m", "statusbadges"]


def _linux_file() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "autostart" / "statusbadges.desktop"


def _mac_file() -> Path:
    return Path.home() / "Library" / "LaunchAgents" / "dk.madebypless.statusbadges.plist"


def is_enabled() -> bool:
    if sys.platform == "win32":
        import winreg
        try:
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run") as key:
                winreg.QueryValueEx(key, NAME)
                return True
        except OSError:
            return False
    return (_mac_file() if sys.platform == "darwin" else _linux_file()).exists()


def set_enabled(enabled: bool) -> None:
    cmd = command()
    if sys.platform == "win32":
        import subprocess
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", 0,
                            winreg.KEY_SET_VALUE) as key:
            if enabled:
                winreg.SetValueEx(key, NAME, 0, winreg.REG_SZ, subprocess.list2cmdline(cmd))
            else:
                try:
                    winreg.DeleteValue(key, NAME)
                except OSError:
                    pass
        return
    path = _mac_file() if sys.platform == "darwin" else _linux_file()
    if not enabled:
        path.unlink(missing_ok=True)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    if sys.platform == "darwin":
        path.write_bytes(plistlib.dumps({"Label": "dk.madebypless.statusbadges", "ProgramArguments": cmd,
                                         "RunAtLoad": True}))
    else:
        import shlex
        path.write_text("[Desktop Entry]\nType=Application\nName=Status Badges\n"
                        f"Exec={' '.join(shlex.quote(c) for c in cmd)}\nX-GNOME-Autostart-enabled=true\n")
