"""Running command-line tools (gh, docker) without flashing a console window on Windows."""
import subprocess
import sys

from statusbadges.model import ProviderError

NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0) if sys.platform == "win32" else 0


def run(args: list[str], env: dict | None = None, timeout: int = 60) -> str:
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=env,
                                creationflags=NO_WINDOW)
    except FileNotFoundError:
        raise ProviderError(f"{args[0]} is not installed or not on PATH")
    except subprocess.TimeoutExpired:
        raise ProviderError(f"{args[0]} did not answer within {timeout} seconds")
    if result.returncode != 0:
        raise ProviderError(result.stderr.strip() or f"{args[0]} exited with code {result.returncode}")
    return result.stdout
