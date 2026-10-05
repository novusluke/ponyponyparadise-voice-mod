"""Read and patch unencrypted standalone Godot 4 PCK v2/v3/v4 files.

The writer preserves the input format and engine version. Unknown formats and
encrypted/sparse entries are refused before making any game changes.
"""
from __future__ import annotations

import hashlib
import struct
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

MAGIC = 0x43504447


@dataclass
class Pack:
    version: int
    engine: tuple[int, int, int]
    files: dict[str, bytes]


def safe_name(name: str) -> str:
    name = name.removeprefix("res://")
    path = PurePosixPath(name)
    if not name or path.is_absolute() or ".." in path.parts or "\\" in name or ":" in name:
        raise ValueError(f"Unsafe PCK path: {name}")
    return name


def read_pack(path: Path) -> Pack:
    blob = path.read_bytes()
    if len(blob) < 100:
        raise ValueError("PCK is truncated.")
    magic, version, major, minor, patch, flags = struct.unpack_from("<6I", blob)
    if magic != MAGIC or version not in (2, 3, 4):
        raise ValueError("Expected an unencrypted standalone Godot 4 PCK (v2/v3/v4).")
    if flags & ~2:
        raise ValueError("Encrypted or sparse PCK archives are unsupported.")
    base = struct.unpack_from("<Q", blob, 24)[0]
    directory = struct.unpack_from("<Q", blob, 32)[0] if version >= 3 else 96
    pos = directory
    count = struct.unpack_from("<I", blob, pos)[0]
    pos += 4
    if count > 100_000:
        raise ValueError("Invalid PCK entry count.")
    files = {}
    for _ in range(count):
        length = struct.unpack_from("<I", blob, pos)[0]
        pos += 4
        if length > 16384 or pos + length + 36 > len(blob):
            raise ValueError("Invalid PCK directory entry.")
        name = safe_name(blob[pos:pos + length].rstrip(b"\0").decode("utf-8"))
        pos += length
        offset, size = struct.unpack_from("<QQ", blob, pos)
        digest = blob[pos + 16:pos + 32]
        file_flags = struct.unpack_from("<I", blob, pos + 32)[0]
        pos += 36
        if file_flags:
            raise ValueError(f"Unsupported encrypted/removal/delta PCK entry: {name}")
        start = base + offset
        if start + size > len(blob):
            raise ValueError(f"Truncated PCK entry: {name}")
        data = blob[start:start + size]
        if hashlib.md5(data).digest() != digest:
            raise ValueError(f"PCK checksum mismatch: {name}")
        if name in files:
            raise ValueError(f"Duplicate PCK entry: {name}")
        files[name] = data
    return Pack(version, (major, minor, patch), files)


def write_pack(path: Path, pack: Pack) -> None:
    records = []
    if pack.version >= 3:
        header = struct.pack("<6IQQ16I", MAGIC, pack.version, *pack.engine, 2, 112, 0, *([0] * 16))
        output = bytearray(header.ljust(112, b"\0"))
        base = 112
    else:
        # v2 places the directory before file data.
        directory_size = 4 + sum(4 + ((len(safe_name(n).encode()) + 3) // 4 * 4) + 36 for n in pack.files)
        base = (96 + directory_size + 15) // 16 * 16
        header = struct.pack("<6IQ16I", MAGIC, 2, *pack.engine, 2, base, *([0] * 16))
        output = bytearray(header.ljust(base, b"\0"))
    for name, data in sorted(pack.files.items()):
        name_bytes = safe_name(name).encode("utf-8")
        name_bytes += b"\0" * (-len(name_bytes) % 4)
        records.append(struct.pack("<I", len(name_bytes)) + name_bytes + struct.pack("<QQ", len(output) - base, len(data)) + hashlib.md5(data).digest() + struct.pack("<I", 0))
        output.extend(data)
        output.extend(b"\0" * (-len(output) % 16))
    directory_blob = struct.pack("<I", len(records)) + b"".join(records)
    if pack.version >= 3:
        struct.pack_into("<Q", output, 32, len(output))
        output.extend(directory_blob)
    else:
        output[96:96 + len(directory_blob)] = directory_blob
    path.write_bytes(output)
