"""File-based worker; Godot never waits for this process to finish."""
from __future__ import annotations

import argparse
import json
import logging
import os
import re
import time
from pathlib import Path

from .common import atomic_json, language_code, line_id, speaker_id, speech_text
from .generate import VoiceGenerator

KEY_RE = re.compile(r"^[a-f0-9]{64}$")

def ordered_jobs(session: Path, preferred_speaker: str = "") -> list[Path]:
    """Keep background prompts together; the currently visible line takes priority."""
    records = []
    for path in session.glob("job_*.json"):
        try:
            row = json.loads(path.read_text(encoding="utf-8"))
            records.append((path, int(row.get("priority", 0)), path.stat().st_mtime_ns,
                            speaker_id(row.get("speaker", "narrator"))))
        except FileNotFoundError:
            continue # Cancellation can remove a job during this scan.
        except (ValueError, TypeError, AttributeError):
            records.append((path, 0, 0, "")) # process_job reports malformed jobs.
    records.sort(key=lambda item: item[2])
    groups = {preferred_speaker: 0} if preferred_speaker else {}
    for _, _, _, speaker in records:
        if speaker not in groups:
            groups[speaker] = len(groups)
    records.sort(key=lambda item: (-item[1], groups[item[3]], item[2]))
    return [item[0] for item in records]


def process_job(path: Path, runtime: dict, generator: VoiceGenerator) -> None:
    key = path.stem.removeprefix("job_")
    if not KEY_RE.fullmatch(key):
        logging.warning("Ignoring malformed job filename: %s", path.name)
        return
    active = path.with_name("active_" + key + ".json")
    try:
        os.replace(path, active)
    except FileNotFoundError:
        return
    result = {"ok": False, "id": key, "error": ""}
    try:
        row = json.loads(active.read_text(encoding="utf-8"))
        language = language_code(row.get("language", "en"))
        speaker = speaker_id(row.get("speaker", "narrator"))
        text = speech_text(row.get("text", ""))
        if line_id(language, speaker, text) != key:
            raise ValueError("Job identity mismatch.")
        if time.time() > float(row.get("deadline", 0)):
            raise TimeoutError("Job expired before generation.")
        # Derive the destination locally; do not accept arbitrary job output paths.
        output = Path(runtime["voices_path"]) / language / (key + ".mp3")
        if output.is_file() and output.stat().st_size > 0:
            result["ok"] = True
        elif key in runtime.get("protected_ids", set()):
            raise FileNotFoundError("Base voice clip missing. Apply voices again to restore it.")
        else:
            if generator.model is None:
                atomic_json(path.with_name("worker_state.json"), {"phase": "loading", "started": time.time()})
                generator.load_model()
                atomic_json(path.with_name("worker_state.json"), {"phase": "ready"})
            result["ok"] = generator.generate(language, speaker, text, output)
        if not result["ok"]:
            result["error"] = "No reference audio for this character/language."
    except Exception as error:
        result["error"] = str(error)
        logging.exception("Voice job %s failed", key)
    finally:
        active.unlink(missing_ok=True)
        atomic_json(path.with_name("done_" + key + ".json"), result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--session", type=Path, required=True)
    args = parser.parse_args()
    session = args.session.resolve()
    session.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(filename=session / "worker.log", level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")
    # Library progress and tracebacks must not create a console for the game.
    import sys
    with (session / "output.log").open("a", encoding="utf-8", buffering=1) as log:
        sys.stdout = sys.stderr = log
        runtime = json.loads(args.config.read_text(encoding="utf-8"))
        for field in ("references_path", "voices_path"):
            runtime[field] = str((args.config.resolve().parent / runtime[field]).resolve())
        for field in ("default_voice",):
            if runtime["omnivoice"].get(field):
                runtime["omnivoice"][field] = str((args.config.resolve().parent / runtime["omnivoice"][field]).resolve())
        runtime["omnivoice"]["character_voices"] = {
            speaker_id(key): str((args.config.resolve().parent / value).resolve())
            for key, value in runtime["omnivoice"].get("character_voices", {}).items() if value
        }
        index = Path(runtime["voices_path"]) / "opening_manifest.json"
        runtime["protected_ids"] = {row["id"] for row in json.loads(index.read_text(encoding="utf-8"))["lines"]} if index.is_file() else set()
        runtime["omnivoice"]["num_step"] = 64
        runtime["omnivoice"]["prompt_cache"] = str(session.parent / "prompts")
        runtime["omnivoice"]["temp_directory"] = str(session)
        generator = VoiceGenerator(Path(runtime["references_path"]), runtime["omnivoice"])
        heartbeat = session / "heartbeat"
        preferred_speaker = ""
        try:
            while heartbeat.exists() and time.time() - heartbeat.stat().st_mtime < 60:
                jobs = ordered_jobs(session, preferred_speaker)
                if jobs:
                    job = jobs[0]
                    if not heartbeat.exists() or time.time() - heartbeat.stat().st_mtime >= 60:
                        break
                    try:
                        preferred_speaker = speaker_id(json.loads(job.read_text(encoding="utf-8")).get("speaker", "narrator"))
                    except (OSError, ValueError, AttributeError):
                        pass
                    process_job(job, runtime, generator)
                else:
                    time.sleep(0.1)
        finally:
            generator.close()


if __name__ == "__main__":
    main()
