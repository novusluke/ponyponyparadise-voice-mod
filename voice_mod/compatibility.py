"""Select a verified game export and its patches before changing any files.

Each profile describes a whole build. Mixing individually recognized scripts
from different builds must never select a patch set with incompatible APIs.
"""
from __future__ import annotations

import configparser
import hashlib
import re
from pathlib import Path

from .pck import Pack, safe_name


def source_digest(content: bytes) -> str:
    """Allow the same reviewed source with Windows or Unix line endings."""
    return hashlib.sha256(content.removeprefix(b"\xef\xbb\xbf").replace(b"\r\n", b"\n")).hexdigest()


def profiles(manifest: dict) -> list[dict]:
    legacy = {key: manifest[key] for key in ("engine", "base_scripts", "base_sources") if key in manifest}
    legacy.update(id="original-windows", label="previously supported Windows export")
    return [legacy, *manifest.get("builds", [])]


def _matches(pack: Pack, relative: str, compiled: str, sources: list[str]) -> bool:
    relative = safe_name(relative)
    bytecode = relative.removesuffix(".gd") + ".gdc"
    remap = pack.files.get(relative + ".remap")
    if remap is not None:
        # Verify the resource actually loads the bytecode we checked. An extra
        # recognized .gdc must not disguise a remap to a different script.
        try:
            mapping = configparser.ConfigParser(interpolation=None)
            mapping.optionxform = str
            mapping.read_string(remap.decode("utf-8-sig"))
        except (UnicodeError, configparser.Error):
            return False
        if (mapping.defaults() or mapping.sections() != ["remap"]
                or list(mapping["remap"]) != ["path"]
                or mapping["remap"]["path"] != '"res://' + bytecode + '"'):
            return False
    elif relative in pack.files:
        # Without a remap, Godot loads the source, even if bytecode also exists.
        return source_digest(pack.files[relative]) in sources
    return bytecode in pack.files and hashlib.sha256(pack.files[bytecode]).hexdigest() == compiled


def select_build(pack: Pack, manifest: dict) -> dict:
    candidates = profiles(manifest)
    results = []
    for profile in candidates:
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", profile["id"]):
            raise ValueError("Invalid game compatibility profile.")
        scripts = profile["base_scripts"]
        if not scripts:
            raise ValueError("Game compatibility profile has no verified scripts.")
        mismatch = [name for name, expected in scripts.items()
                    if not _matches(pack, name, expected, profile.get("base_sources", {}).get(name, []))]
        engine_ok = "engine" not in profile or tuple(profile["engine"]) == pack.engine
        if engine_ok and not mismatch:
            return profile
        results.append((len(mismatch) + (0 if engine_ok else len(scripts)), profile, mismatch))
    _, nearest, mismatch = min(results, key=lambda result: result[0])
    different = ", ".join(mismatch[:3]) or "engine version"
    if len(mismatch) > 3:
        different += f", and {len(mismatch) - 3} more"
    raise ValueError(
        f"This game export is not supported by this setup yet (Godot {'.'.join(map(str, pack.engine))}; "
        f"{len(nearest['base_scripts']) - len(mismatch)}/{len(nearest['base_scripts'])} scripts match "
        f"the {nearest['label']}). Different or missing: {different}. "
        "Use a clean supported game build, or report your game download/version so support can be added. "
        "No game files were changed."
    )


def patch_sources(root: Path, profile: dict) -> dict[str, Path]:
    """Common patches plus only the selected build's reviewed overrides."""
    patches = {safe_name(path.relative_to(root / "game_patch").as_posix()): path
               for path in (root / "game_patch").rglob("*.gd")}
    if profile["id"] != "original-windows":
        folder = root / "game_builds" / profile["id"]
        if not folder.is_dir() or folder.is_symlink() or not folder.resolve().is_relative_to(root.resolve()):
            raise ValueError("The selected game build's patches are missing or linked. Download a complete setup.")
        overrides = {safe_name(path.relative_to(folder).as_posix()): path for path in folder.rglob("*.gd")}
        if not overrides:
            raise ValueError("The selected game build's patch set is empty.")
        patches.update(overrides)
    if any(path.is_symlink() or not path.resolve().is_relative_to(root.resolve()) for path in patches.values()):
        raise ValueError("Linked or external game patches cannot be applied. Download a complete setup.")
    return patches
