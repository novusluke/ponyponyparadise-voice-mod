"""Launch the real standalone EXE and check its GUI report outside the repo."""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from voice_mod.settings import state_directory


def main():
    work = state_directory() / "development"
    work.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment["QT_QPA_PLATFORM"] = "offscreen"
    with tempfile.TemporaryDirectory(prefix="exe-smoke-", dir=work) as temporary:
        report = Path(temporary) / "report.json"
        subprocess.run([str(ROOT / "PonyPonyParadiseVoiceSetup.exe"), "--preview", "--report", str(report)],
                       cwd=temporary, env=environment, timeout=45, check=True,
                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        result = json.loads(report.read_text())
        assert result["visible"] and result["single_view"] and result["apply_buttons"] == 1
        assert result["bundled_references"] >= 5
        assert result["version"] == json.loads((ROOT / "release.json").read_text())["version"]
    print("Standalone EXE smoke check passed: GUI opens from another directory with bundled assets.")


if __name__ == "__main__":
    main()
