"""Shared identity and manifest rules for the game and local worker."""
from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path


def quality_steps(value=64) -> int:
    """Public assets use 64; players may trade quality for shorter generation."""
    try:
        return max(8, min(64, int(value)))
    except (ValueError, TypeError, OverflowError):
        return 64

ALIASES = {
    "player": "narrator",
    "narrator": "narrator", "narration": "narrator",
    "princesscelestia": "celestia", "cel": "celestia", "princessluna": "luna",
    "twilightsparkle": "twilight", "twi": "twilight",
    "sweetiebelle": "sweetiebelle", "buttonmash": "buttonmash",
    "aj": "applejack", "chrys": "chrysalis", "queenchrysalis": "chrysalis",
    "shy": "fluttershy", "pinkie": "pinkiepie", "dash": "rainbowdash", "rainbow": "rainbowdash",
    "trixielulamoon": "trixie", "berry": "berrypunch",
    "bigmac": "bigmcintosh", "bigmacintosh": "bigmcintosh",
    "princeblueblood": "blueblood", "derpy": "derpyhooves", "diamond": "diamondtiara",
    "fleet": "fleetfoot", "fleur": "fleurdelys", "granny": "grannysmith",
    "lightning": "lightningdust", "lyra": "lyraheartstrings", "mayor": "mayormare",
    "redheart": "nurseredheart", "nursehedheart": "nurseredheart",
    "octavia": "octaviamelody", "spitf": "spitfire",
}
LANGUAGE_RE = re.compile(r"^[a-z]{2,3}(?:-[a-z0-9]{2,8})*$")


def language_code(value: str) -> str:
    value = str(value).strip().lower()
    if not LANGUAGE_RE.fullmatch(value):
        raise ValueError(f"Invalid language code: {value!r}")
    return value


def speaker_id(value: str) -> str:
    value = re.sub(r"[^a-z0-9]", "", str(value).lower()) or "narrator"
    return ALIASES.get(value, value)


def speech_text(value: str) -> str:
    # Match the Godot implementation exactly; hash the displayed, resolved text.
    value = re.sub(r"\[[^\]]*\]", "", str(value)).replace("\\:", ":").replace("\ufffd", "...")
    return re.sub(r"\s+", " ", value).strip()


def line_id(language: str, speaker: str, text: str) -> str:
    canonical = f"{language_code(language)}\n{speaker_id(speaker)}\n{speech_text(text)}"
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def atomic_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, path)


def manifest_lines(path: Path) -> list[dict]:
    raw = json.loads(path.read_text(encoding="utf-8-sig"))
    rows = raw.get("lines", []) if isinstance(raw, dict) else raw
    if not isinstance(rows, list):
        raise ValueError("Manifest must be a list or an object containing 'lines'.")
    found = {}
    for row in rows:
        language = language_code(row.get("language", "en"))
        speaker = speaker_id(row.get("speaker", "narrator"))
        text = speech_text(row.get("text", ""))
        if not text:
            continue
        key = line_id(language, speaker, text)
        if row.get("id", key) != key:
            raise ValueError(f"Manifest identity mismatch for {text[:50]!r}")
        found[key] = {"id": key, "language": language, "speaker": speaker, "text": text}
    return list(found.values())
