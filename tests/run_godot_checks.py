"""Run the real menu, MP3 and dialogue regression against an installed game.

Requires the matching portable Godot editor binary (the release game executable
ignores --script). The checked game needs the mod installed first.
"""
import argparse
import os
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--game", type=Path, required=True)
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from voice_mod.settings import state_directory
    parser.add_argument("--log", type=Path, default=state_directory() / "development/godot-checks.log")
    parser.add_argument("--live-gpu-python", type=Path)
    args = parser.parse_args()
    # Never let QA autoloads write the player's real user:// preferences/saves.
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from voice_mod.pck import read_pack
    pack = read_pack(args.game / "PonyPonyParadise.pck")
    if b'PonyVoiceModQA__' not in pack.files.get("project.binary", b""):
        parser.error("Prepare an isolated game with tests/prepare_godot_checks.py first.")
    environment = os.environ.copy()
    environment["PONY_TEST_PYTHON"] = sys.executable
    environment["PONY_VOICE_ROSTER"] = str(Path(__file__).resolve().parents[1] / "dialogue/voice_roster.json")
    if args.live_gpu_python:
        environment["PONY_TEST_GPU_PYTHON"] = str(args.live_gpu_python.resolve())
    from voice_mod.installer_service import require_private_destination
    require_private_destination(args.log)
    args.log.parent.mkdir(parents=True, exist_ok=True)
    passed = True
    output = []
    for scene, marker, timeout in [("godot_regression", "VOICE_MOD_REGRESSION_OK", 180 if args.live_gpu_python else 25),
                                   ("godot_batch_regression", "BATCH_AUDIO_REGRESSION_OK", 30),
                                   ("godot_story_regression", "STORY_SAVE_REGRESSION_OK", 45),
                                   ("godot_lifecycle_regression", "AUDIO_SCENE_EXIT_OK", 15),
                                   ("godot_restart_regression", "LOAD_TITLE_NEW_GAME_OK", 35)]:
        try:
            result = subprocess.run([str(args.godot.resolve()), "--headless", "--path", str(args.game.resolve()), "--main-pack",
                                     str((args.game / "PonyPonyParadise.pck").resolve()),
                                     str(Path(__file__).with_name(scene + ".tscn").resolve())],
                                    cwd=args.game.resolve(), env=environment, capture_output=True,
                                    text=True, timeout=timeout, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            output.append(result.stdout + "\n" + result.stderr)
            ok = result.returncode == 0 and marker in result.stdout and "ERROR:" not in result.stderr
        except subprocess.TimeoutExpired as error:
            partial = (error.stdout or b"") + (error.stderr or b"")
            output.append(partial.decode("utf-8", errors="replace") if isinstance(partial, bytes) else partial)
            ok = False
        print(scene + ":", "PASS" if ok else "FAIL")
        passed = passed and ok
        if not ok:
            break
    args.log.write_text("\n".join(output), encoding="utf-8")
    print("Godot regressions:", "PASS" if passed else "FAIL", "| Log:", args.log.resolve())
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
