"""Stage reference clips at Button Mash's perceived loudness; never patch a game."""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from voice_mod.generate import ffmpeg_binary
from voice_mod.common import atomic_json
from voice_mod.installer_service import require_private_destination

def run(arguments):
    return subprocess.run([ffmpeg_binary(), "-hide_banner", "-nostdin", *arguments],
        capture_output=True, text=True, check=True, timeout=120,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))

def measure(path):
    result = run(["-i", str(path), "-af",
        "aformat=channel_layouts=mono,loudnorm=I=-20:TP=-1:LRA=50:print_format=json", "-f", "null", "-"])
    return json.JSONDecoder().raw_decode(result.stderr[result.stderr.rfind("{"):])[0]

def normalize(source, target, loudness):
    measured = measure(source)
    assert math.isfinite(float(measured["input_i"])), "Silent/invalid reference"
    gain = loudness - float(measured["input_i"])
    for attempt in range(16):
        # Constant gain preserves dynamics; the oversampled limiter catches peaks
        # only when needed. Always render from the original, never a prior MP3.
        filters = (f"aformat=channel_layouts=mono,aresample=192000,volume={gain:.4f}dB,"
                   "alimiter=limit=0.841395:level=false:latency=true")
        run(["-y", "-i", str(source), "-af", filters,
             "-map_metadata", "-1", "-id3v2_version", "0", "-write_id3v1", "0",
             "-ar", "24000", "-ac", "1", "-codec:a", "libmp3lame", "-b:a", "192k", str(target)])
        actual = measure(target)
        error = loudness - float(actual["input_i"])
        if abs(error) <= .3 and float(actual["input_tp"]) <= 0:
            return measured, actual
        gain += error
    raise ValueError(f"{source.name} cannot meet loudness/peak limits; staged file was not approved.")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    require_private_destination(output)
    if output.exists() and any(output.iterdir()):
        parser.error("Choose a new empty private staging directory.")
    output.mkdir(parents=True, exist_ok=True)
    references = ROOT / "reference_audios/en"
    button = measure(references / "buttonmash.mp3")
    loudness = float(button["input_i"])
    records = []
    for source in sorted(references.glob("*.mp3")):
        target = output / source.name
        before, after = normalize(source, target, loudness)
        records.append({"file": "en/" + source.name,
            "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
            "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
            "before_lufs": float(before["input_i"]), "after_lufs": float(after["input_i"]),
            "true_peak_dbtp": float(after["input_tp"])})
        print(f"{source.stem}: {before['input_i']} -> {after['input_i']} LUFS", flush=True)
    atomic_json(output / "loudness.json", {"schema_version": 1,
        "method": "FFmpeg EBU R128 integrated loudness, mono, verified after MP3 encoding",
        "reference": "en/buttonmash.mp3", "target_lufs": loudness,
        "tolerance_lu": .3, "peak_limit_dbtp": 0, "files": records})

if __name__ == "__main__":
    main()
