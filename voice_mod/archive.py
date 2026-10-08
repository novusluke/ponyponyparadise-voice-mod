"""Validate the entire pinned source archive before writing any files."""
from __future__ import annotations

import stat
from pathlib import Path, PurePosixPath


def extract_source(archive, folder: Path) -> None:
    root = folder.resolve()
    entries = []
    names = set()
    prefix = None
    size = 0
    for item in archive.infolist():
        name = PurePosixPath(item.filename)
        if name.is_absolute() or ".." in name.parts or "\\" in item.orig_filename or ":" in item.filename or not name.parts:
            raise ValueError("Unsafe path in OmniVoice source archive.")
        if stat.S_ISLNK(item.external_attr >> 16):
            raise ValueError("Linked source archive entries are unsupported.")
        prefix = prefix or name.parts[0]
        if name.parts[0] != prefix:
            raise ValueError("Unexpected source archive root.")
        relative = name.parts[1:]
        if not relative:
            if not item.is_dir():
                raise ValueError("Source archive has no enclosing folder.")
            continue
        target = root.joinpath(*relative)
        if target in names or not target.resolve().is_relative_to(root):
            raise ValueError("Duplicate or escaping source archive entry.")
        for parent in (target, *target.parents):
            if parent == root:
                break
            if parent.is_symlink() or (parent.exists() and getattr(parent.lstat(), "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0)):
                raise ValueError("Source destination contains a linked folder.")
        names.add(target)
        size += item.file_size
        if size > 512 * 1024 * 1024 or len(names) > 10000:
            raise ValueError("Source archive exceeds the supported size.")
        entries.append((item, target))
    if not entries:
        raise ValueError("Source archive is empty.")
    for item, target in entries:
        if item.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(item))
