"""Generate an auditable, complete 64-step base pack in a private staging folder.

Run with an OmniVoice GPU environment. Publication is a separate operation;
this tool never patches the game or overwrites the repository's current audio.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from voice_mod.common import atomic_json, manifest_lines, speaker_id
from voice_mod.generate import VoiceGenerator
from voice_mod.installer_service import require_private_destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--speaker", help="Regenerate only this character; preserve other base clips.")
    parser.add_argument("--resume", action="store_true", help="Resume only verified results from the same preparation recipe.")
    args = parser.parse_args()
    output = args.output.resolve()
    require_private_destination(output)
    if output.exists() and any(output.iterdir()) and not args.resume:
        parser.error("Choose a new empty staging folder; cached clips cannot establish generation provenance.")
    output.mkdir(parents=True, exist_ok=True)
    rows = {}
    for filename in ("opening.json", "system.json"):
        for row in manifest_lines(ROOT / "dialogue" / filename):
            rows[row["id"]] = row
    selected = {key: row for key, row in rows.items() if not args.speaker or row["speaker"] == speaker_id(args.speaker)}
    if not selected:
        parser.error("The requested character has no base dialogue.")
    existing = {}
    if args.speaker:
        old = json.loads((ROOT / "data/voices/opening_manifest.json").read_text(encoding="utf-8"))
        existing = {row["id"]: row for row in old["lines"]}
        for key, row in rows.items():
            if key not in selected:
                record = existing[key]
                if hashlib.sha256((ROOT / "data/voices" / record["file"]).read_bytes()).hexdigest() != record["sha256"]:
                    parser.error("An unselected base clip does not match its recorded checksum.")
    recipe = hashlib.sha256()
    for source in (ROOT / "voice_mod/generate.py", ROOT / "voice_mod/narration.py", ROOT / "voice_mod/common.py"):
        recipe.update(source.read_bytes())
    # Other characters' reference updates cannot affect this speaker's resume.
    for language, speaker in sorted({(row["language"], row["speaker"]) for row in selected.values()}):
        reference = ROOT / "reference_audios" / language / (speaker + ".mp3")
        recipe.update(reference.read_bytes())
        if reference.with_suffix(".txt").is_file():
            recipe.update(reference.with_suffix(".txt").read_bytes())
    recipe.update(json.dumps(selected, sort_keys=True).encode())
    recipe = recipe.hexdigest()
    options = json.loads((ROOT / "config.json").read_text(encoding="utf-8"))["omnivoice"]
    options.update(num_step=64, speed=1.0, prompt_cache=str(output / "runtime/prompts"),
                   temp_directory=str(output / "runtime"))
    (output / "runtime").mkdir(exist_ok=True)
    generator = VoiceGenerator(ROOT / "reference_audios", options)
    calls = []
    index = []
    if args.resume:
        previous = json.loads((output / "progress.json").read_text(encoding="utf-8"))
        if previous.get("recipe_sha256") != recipe:
            parser.error("Generation preparation changed; use a new staging folder.")
        index = previous["lines"]
        for record in index:
            if record["id"] not in selected or record["num_step"] != 64 or hashlib.sha256((output / "voices" / record["file"]).read_bytes()).hexdigest() != record["sha256"]:
                parser.error("A staged clip failed its provenance check.")
    completed = {row["id"] for row in index}
    try:
        generator.load_model()
        original_generate = generator.model.generate
        def checked_generate(*positional, **named):
            if named.get("num_step") != 64:
                raise ValueError("Refusing to publish a clip generated at a quality other than 64 steps.")
            calls.append({"num_step": named["num_step"], "text_sha256": hashlib.sha256(named["text"].encode()).hexdigest()})
            return original_generate(*positional, **named)
        generator.model.generate = checked_generate
        for number, row in enumerate(selected.values(), 1):
            if row["id"] in completed:
                continue
            relative = row["language"] + "/" + row["id"] + ".mp3"
            target = output / "voices" / relative
            before = len(calls)
            print(f"GENERATING {number}/{len(selected)} {row['speaker']} {row['id']}", flush=True)
            try:
                generated = generator.generate(row["language"], row["speaker"], row["text"], target)
            except Exception:
                print("VERIFICATION_FAILED " + json.dumps(generator.last_verification), flush=True)
                raise
            if not generated or len(calls) <= before:
                raise ValueError("Every replacement clip must have a verified 64-step generation call.")
            import soundfile
            import subprocess
            from voice_mod.generate import ffmpeg_binary
            wav = output / "runtime/validation.wav"
            subprocess.run([ffmpeg_binary(), "-hide_banner", "-loglevel", "error", "-y", "-i", str(target), str(wav)],
                           check=True, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            if soundfile.info(wav).duration <= 0.2:
                raise ValueError("Generated MP3 is too short or invalid.")
            record = {**row, "file": relative, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                      "num_step": calls[-1]["num_step"], "generation_text_sha256": calls[-1]["text_sha256"],
                      "generation_attempts": len(calls) - before}
            if row["speaker"] == "narrator":
                record["narrator_verification"] = generator.last_verification
                record["reference_sha256"] = hashlib.sha256(generator.reference(row["language"], row["speaker"]).read_bytes()).hexdigest()
            index.append(record)
            atomic_json(output / "progress.json", {"complete": len(index), "total": len(selected), "recipe_sha256": recipe, "lines": index})
            print(f"READY {number}/{len(selected)} steps=64 attempts={len(calls)-before} sha256={record['sha256']}", flush=True)
    finally:
        generator.close()
    manifest = {"schema_version":1, "num_step":64, "speed":1.0, "model":options["model"],
                "omnivoice_version":importlib.metadata.version("omnivoice"),
                "quality_verification":"Each clip records the actual model.generate num_step argument and MP3 checksum.",
                "lines":[{**existing, **{row["id"]: row for row in index}}[key] for key in rows]}
    atomic_json(output / "voices/opening_manifest.json", manifest)
    print(f"BASE_PACK_COMPLETE {len(index)} replacements actual-generation-calls=64", flush=True)


if __name__ == "__main__":
    main()
