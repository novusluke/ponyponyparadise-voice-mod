"""Conservative checks for narrator speech before accepting it into the cache."""
from __future__ import annotations

import difflib
import re

REFERENCE_PREPARATION_VERSION = 2
NARRATOR_MAX_ATTEMPTS = 3


def words(text: str) -> list[str]:
    # These homophones cannot be distinguished reliably by an audio recognizer.
    aliases = {"weight": "wait", "their": "there", "they're": "there", "it's": "its", "russell": "rustle"}
    tokens = re.findall(r"[^\W_]+(?:'[^\W_]+)?", text.lower().replace("’", "'"))
    return [aliases.get(token, token) for token in tokens]


def verify_words(expected: str, recognized: str) -> dict:
    wanted, heard = words(expected), words(recognized)
    if not wanted or not heard:
        return {"ok": False, "first_word_verified": False, "word_coverage": 0.0}
    # Permit minor ASR spelling differences, but never accept the next word as
    # a substitute for a missing first word or allow an extra vocal prefix.
    first = wanted[0] == heard[0] or (min(len(wanted[0]), len(heard[0])) >= 5 and
             difflib.SequenceMatcher(None, wanted[0], heard[0]).ratio() >= .86)
    matcher = difflib.SequenceMatcher(None, wanted, heard, autojunk=False)
    coverage = sum(block.size for block in matcher.get_matching_blocks()) / len(wanted)
    extra = len(heard) > len(wanted) + max(1, len(wanted) // 5)
    return {"ok": first and coverage >= .88 and not extra,
            "first_word_verified": first, "word_coverage": round(coverage, 4)}


def has_onset_burst(audio, sample_rate: int) -> bool:
    import numpy as np
    audio = np.asarray(audio).reshape(-1)
    frame = max(1, int(sample_rate * .025))
    if len(audio) < sample_rate * 1.2:
        return False
    rms = np.sqrt(np.mean(audio[:len(audio) // frame * frame].reshape(-1, frame) ** 2, axis=1))
    active = np.flatnonzero(rms > max(.008, float(np.max(rms)) * .06))
    if len(active) < 12:
        return False
    start = int(active[0])
    onset = float(np.max(rms[start:start + 8]))
    rest = rms[start + 12:]
    rest = rest[rest > .008]
    # A single stressed word has a loud vowel followed by a quiet tail. Require
    # one second of later voiced audio before using it as a comparison baseline.
    return len(rest) >= 40 and onset > .08 and onset > float(np.median(rest)) * 5


def pad_narration(audio, sample_rate: int):
    import numpy as np
    audio = np.asarray(audio, dtype=np.float32).reshape(-1).copy()
    if not len(audio) or not np.isfinite(audio).all() or np.max(np.abs(audio)) < 1e-4:
        raise ValueError("Narrator output is empty, silent or invalid.")
    peak = float(np.max(np.abs(audio)))
    if peak > .92:
        audio *= .92 / peak
    # Five milliseconds prevents a click without fading away the first syllable.
    length = min(int(sample_rate * .005), len(audio) // 2)
    if length:
        ramp = np.linspace(0, 1, length, dtype=np.float32)
        audio[:length] *= ramp
        audio[-length:] *= ramp[::-1]
    return np.pad(audio, (int(sample_rate * .12), int(sample_rate * .15)))
