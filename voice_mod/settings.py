"""Private per-user state. Public repository templates are never overwritten."""
import os
import sys
from pathlib import Path


def state_directory() -> Path:
    override = os.environ.get("PONY_VOICE_STATE_DIR")
    if override:
        return Path(override).expanduser().resolve()
    if os.name == "nt":
        base = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData/Local"))
    else:
        base = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return base / "PonyPonyParadiseVoiceMod"


def preferences_path() -> Path:
    return state_directory() / "preferences.json"


def application_directory() -> Path:
    return Path(sys.executable).resolve().parent if getattr(sys, "frozen", False) else Path(__file__).resolve().parent.parent
