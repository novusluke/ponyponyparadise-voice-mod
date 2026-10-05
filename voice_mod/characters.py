"""Install bundled characters only when the selected game lacks their tag."""
from __future__ import annotations

import json
import stat
from pathlib import Path


def linked(path: Path) -> bool:
    return path.is_symlink() or bool(getattr(path.lstat(), "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT)


def has_button_mash(game: Path) -> bool:
    root = game / "data/characters"
    if not root.is_dir() or linked(root):
        return False
    for tier in ("core", "custom"):
        directory = root / tier
        if not directory.is_dir() or linked(directory):
            continue
        for folder in directory.iterdir():
            if not folder.is_dir() or linked(folder):
                continue
            if folder.name.lower().replace("_", "").replace(" ", "") == "buttonmash":
                return True
            config = folder / "character.json"
            if not config.is_file() or linked(config):
                continue
            try:
                value = json.loads(config.read_text(encoding="utf-8-sig"))
                if str(value.get("tag", "")).lower().replace("_", "") == "buttonmash":
                    return True
            except (OSError, ValueError, AttributeError):
                continue
    return False


def installation_sources(game: Path, source: Path) -> list[tuple[Path, str]]:
    character = source / "character_assets/buttonmash"
    if character.is_dir() and not has_button_mash(game):
        return [(character, "data/characters/custom/buttonmash")]
    return []
