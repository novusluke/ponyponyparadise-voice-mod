"""Restore the verified game pack and remove only resources owned by this mod."""
from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import stat
import uuid
from pathlib import Path, PurePosixPath

from .common import atomic_json, line_id
from .pck import read_pack
from .settings import state_directory


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def checked_path(game: Path, relative: str) -> Path:
    name = PurePosixPath(relative)
    if "\\" in relative or name.is_absolute() or ".." in name.parts or not name.parts or ":" in relative:
        raise ValueError("Invalid resource path in installation metadata.")
    if name.parts[:2] not in (("data", "voice_mod"), ("data", "voices")) and name.parts[:4] != ("data", "characters", "custom", "buttonmash"):
        raise ValueError("Installation resource is outside this mod's data folders.")
    path = game
    for part in name.parts:
        path /= part
        if path.exists() or path.is_symlink():
            info = path.lstat()
            if path.is_symlink() or getattr(info, "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT:
                raise ValueError("Linked mod folders cannot be modified automatically.")
    if not path.resolve().is_relative_to(game):
        raise ValueError("Installation resource escaped the selected game folder.")
    return path


def legacy_files(game: Path, source: Path) -> set[str]:
    result = {"data/voice_mod/config.json", "data/voice_mod/worker_bootstrap.py"}
    for folder, prefix in ((source / "voice_mod", "data/voice_mod/voice_mod"),
                           (source / "reference_audios", "data/voice_mod/reference_audios")):
        for path in folder.rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc":
                result.add(prefix + "/" + path.relative_to(folder).as_posix())
    index = checked_path(game, "data/voices/opening_manifest.json")
    if index.is_file():
        manifest = json.loads(index.read_text(encoding="utf-8"))
        for row in manifest.get("lines", []):
            if row.get("id") != line_id(row.get("language", "en"), row.get("speaker", "narrator"), row.get("text", "")):
                raise ValueError("Base voice manifest has an invalid identity.")
            expected = row.get("language", "en") + "/" + row["id"] + ".mp3"
            if row.get("file") != expected:
                raise ValueError("Base voice manifest has an invalid file path.")
            result.add("data/voices/" + expected)
        result.add("data/voices/opening_manifest.json")
    return result


def preserve_original_files(game: Path, paths: set[str], previous: dict, source: Path) -> dict:
    owned = dict(previous.get("owned_files", {}))
    originals = dict(previous.get("original_files", {}))
    known = set(owned)
    if previous and "owned_files" not in previous:
        known |= legacy_files(game, source)
    for relative in paths:
        target = checked_path(game, relative)
        if relative not in known and relative not in originals and target.is_file():
            # A publisher ZIP may already have placed the bundled MP3s in
            # data/voices before Apply. Those exact bundled files are mod assets.
            bundled = source / relative
            if relative.startswith("data/voices/") and bundled.is_file() and digest(target) == digest(bundled):
                continue
            backup = checked_path(game, "data/voice_mod/install_originals/" + relative)
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, backup)
            originals[relative] = digest(backup)
    return {"owned_files": owned, "original_files": originals}


def cache_files(game: Path) -> set[str]:
    result = set()
    receipt = checked_path(game, "data/voice_mod/reference_audios/_bundled_sources.json")
    if receipt.is_file():
        result.add("data/voice_mod/reference_audios/_bundled_sources.json")
    capture = checked_path(game, "data/voice_mod/dialogue_manifest.json")
    if capture.is_file():
        try:
            value = json.loads(capture.read_text(encoding="utf-8"))
            for row in value.get("lines", []):
                if row.get("id") == line_id(row.get("language", "en"), row.get("speaker", "narrator"), row.get("text", "")):
                    result.add("data/voices/" + row.get("language", "en") + "/" + row["id"] + ".mp3")
            result.add("data/voice_mod/dialogue_manifest.json")
        except (ValueError, TypeError):
            pass  # Unrecognized history is preserved, never treated as a cache.
    root = checked_path(game, "data/voice_mod/runtime")
    for directory, folders, files in os.walk(root, followlinks=False):
        # Do not traverse reparse points, including Windows directory junctions.
        folders[:] = [name for name in folders if not (Path(directory) / name).is_symlink()
                      and not getattr((Path(directory) / name).lstat(), "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT]
        for name in files:
            relative = (Path(directory) / name).relative_to(game).as_posix()
            inside = PurePosixPath(relative).parts[3:-1]
            session = any(re.fullmatch(r"session_\d+_\d+", part) for part in inside)
            scratch = session and any(part.startswith("synthesis_") for part in inside)
            if (session and (re.fullmatch(r"(?:job|active|done)_[a-f0-9]{64}\.json", name)
                             or name in ("heartbeat", "worker.log", "worker_state.json"))) or (
                    scratch and (name in ("generated.wav", "full-reference.wav") or re.fullmatch(r"[a-z0-9-]+\.wav", name))) or (
                    inside == ("prompts",) and re.fullmatch(r"[a-f0-9]{64}(?:\.\d+\.tmp)?\.pt", name)):
                checked_path(game, relative)
                result.add(relative)
    return result


def uninstall_game(game: Path, source: Path, log=lambda message: None) -> dict:
    game = game.resolve()
    target, backup = game / "PonyPonyParadise.pck", game / "PonyPonyParadise.pck.voice-mod-original"
    state_path = checked_path(game, "data/voice_mod/install_state.json")
    if not state_path.is_file() or not target.is_file():
        raise ValueError("A verified voice-mod installation and original PCK backup are required.")
    state = json.loads(state_path.read_text(encoding="utf-8"))
    cleanup = state.get("status") in ("cleanup_pending", "uninstalled")
    if not backup.is_file() and not (cleanup and digest(target) == state.get("original_sha256")):
        raise ValueError("A verified voice-mod installation and original PCK backup are required.")
    if target.is_symlink() or backup.is_symlink() or (backup.is_file() and digest(backup) != state.get("original_sha256")) or digest(target) != state.get("installed_sha256"):
        raise ValueError("Game or original backup changed; uninstall refused before modifying any files.")
    read_pack(backup if backup.is_file() else target)
    owned = state.get("owned_files")
    if owned is not None and not isinstance(owned, dict):
        raise ValueError("Invalid installation resource receipt.")
    paths = set(owned) if owned is not None else legacy_files(game, source)
    cache = cache_files(game)
    originals = state.get("original_files", {})
    # Validate the entire operation before restoring the PCK or deleting assets.
    for relative in paths | cache | set(originals):
        checked_path(game, relative)
    for relative, checksum in originals.items():
        original = checked_path(game, "data/voice_mod/install_originals/" + relative)
        already_restored = cleanup and checked_path(game, relative).is_file() and digest(checked_path(game, relative)) == checksum
        if not already_restored and (not original.is_file() or digest(original) != checksum):
            raise ValueError("An original resource backup is missing or changed; uninstall cannot safely proceed.")
    mod = checked_path(game, "data/voice_mod")
    mod_directories = {mod}
    # Validate all remaining folders before touching the game, including files
    # that will be preserved outside the installation rather than deleted.
    for directory, folders, files in os.walk(mod, followlinks=False):
        for name in folders + files:
            path = checked_path(game, (Path(directory) / name).relative_to(game).as_posix())
            if path.is_dir():
                mod_directories.add(path)
    log("Restoring the verified original game…")
    staged = target.with_suffix(".pck.voice-mod-uninstall")
    try:
        if backup.is_file():
            shutil.copy2(backup, staged)
            if digest(target) != state["installed_sha256"]:
                raise ValueError("Game changed during uninstall; no files were removed.")
            os.replace(staged, target)
    finally:
        staged.unlink(missing_ok=True)
    state = {**state, "status": "cleanup_pending", "installed_sha256": state["original_sha256"]}
    atomic_json(state_path, state)
    removed = restored = retained = 0
    directories = set()
    mutable = {"data/voice_mod/config.json", "data/voice_mod/dialogue_manifest.json"}
    character_prefix = "data/characters/custom/buttonmash/"
    character_files = {name for name in paths if name.startswith(character_prefix)}
    keep_character = False
    if character_files and owned is not None:
        character_root = checked_path(game, character_prefix.rstrip("/"))
        keep_character = any(checked_path(game, name).is_file() and digest(checked_path(game, name)) != owned[name]
                             for name in character_files)
        # Preserve the complete character if the user edited it or added assets.
        keep_character |= any(path.is_file() and path.relative_to(game).as_posix() not in character_files
                              for path in character_root.rglob("*"))
    try:
        for relative in sorted(paths | cache | set(originals)):
            path = checked_path(game, relative)
            if keep_character and relative.startswith(character_prefix):
                retained += int(path.is_file())
                continue
            if relative in originals:
                original = checked_path(game, "data/voice_mod/install_originals/" + relative)
                path.parent.mkdir(parents=True, exist_ok=True)
                if original.is_file():
                    shutil.copy2(original, path)
                # Keep recovery copies until cleanup succeeds, so a locked file
                # or interrupted cleanup can be retried with the same receipt.
                restored += 1
            elif path.is_file():
                if owned is not None and relative in owned and relative not in mutable and digest(path) != owned[relative]:
                    retained += 1  # Keep user edits to installed resources.
                    continue
                path.unlink()
                removed += 1
            directories.add(path.parent)
        for relative in originals:
            original = checked_path(game, "data/voice_mod/install_originals/" + relative)
            original.unlink(missing_ok=True)
            directories.add(original.parent)
        remaining = []
        for directory, folders, files in os.walk(mod, followlinks=False):
            for name in folders:
                checked_path(game, (Path(directory) / name).relative_to(game).as_posix())
            for name in files:
                path = checked_path(game, (Path(directory) / name).relative_to(game).as_posix())
                if path != state_path:
                    remaining.append(path)
        recovery = None
        if remaining:
            identifier = state.get("recovery_id", uuid.uuid4().hex)
            if not re.fullmatch(r"[a-f0-9]{32}", identifier):
                raise ValueError("Invalid uninstall recovery identifier.")
            recovery_root = (state_directory() / "uninstall-recovery").resolve()
            recovery = (recovery_root / identifier).resolve()
            if not recovery.is_relative_to(recovery_root) or recovery.is_relative_to(game):
                raise ValueError("Uninstall recovery must be outside the game folder.")
            state["recovery_id"] = identifier
            atomic_json(state_path, state)
            # Preserve user edits and unrelated files before removing the mod
            # directory. Verify every copy before deleting its source.
            for path in remaining:
                saved = recovery / path.relative_to(game)
                saved.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, saved)
                if digest(path) != digest(saved):
                    raise OSError("Uninstall recovery checksum mismatch.")
            for path in remaining:
                path.unlink()
                retained += 1
            log(f"Additional files preserved in {recovery}")
        backup.unlink(missing_ok=True)
        state_path.unlink()
    except OSError as error:
        raise RuntimeError("Original game restored, but file cleanup was interrupted. Close programs using the game folder and click Uninstall voice mod again.") from error
    # Empty directories only; unrelated files are never recursively deleted.
    for directory in sorted(directories | mod_directories, key=lambda path: len(path.parts), reverse=True):
        while directory != game / "data" and directory.is_relative_to(game / "data"):
            try:
                directory.rmdir()
            except OSError:
                break
            directory = directory.parent
    log(f"Voice mod uninstalled. Removed {removed} files; restored {restored} original resources.")
    return {"removed": removed, "restored": restored, "retained": retained,
            "recovery_directory": str(recovery) if recovery else ""}
