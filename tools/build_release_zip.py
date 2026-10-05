"""Build the release ZIP that extracts directly into the game folder."""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def build_release_zip(root=ROOT):
    manifest = json.loads((root / "data/voices/opening_manifest.json").read_text(encoding="utf-8"))
    files = [root / "PonyPonyParadiseVoiceSetup.exe",
             root / "INSTALL.txt", root / "LICENSE", root / "THIRD_PARTY_NOTICES.md",
             root / "data/voices/opening_manifest.json"]
    for row in manifest["lines"]:
        path = root / "data/voices" / row["file"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != row["sha256"]:
            raise ValueError("Opening voice checksum mismatch: " + row["file"])
        files.append(path)
    destination = root / "ponyponyparadise-voice-mod.zip"
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in files:
            info = zipfile.ZipInfo(path.relative_to(root).as_posix(), (2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, path.read_bytes())
    print(f"Built {destination.name}: {len(manifest['lines'])} protected base clips, {destination.stat().st_size // 1_000_000} MB.")
    return destination


if __name__ == '__main__':
    build_release_zip()
