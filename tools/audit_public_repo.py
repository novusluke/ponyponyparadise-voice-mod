"""Check the physical public folder, including ignored files and EXE resources."""
from __future__ import annotations

import json
import os
import re
import sys
import types
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN_DIRECTORIES = {"__pycache__", ".runtime", ".venv", "venv", "build", "dist", ".pytest_cache", ".ipynb_checkpoints", "generated"}
FORBIDDEN_FILES = {"preferences.json", "config.local.json", "install_state.json", "voice_pack.zip", "pyvenv.cfg", ".env"}
LOCAL_PATH = re.compile(rb"[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s\"']+", re.I)
SECRET = re.compile(rb"(?:\bgh[pousr]_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{30,}|\bAKIA[A-Z0-9]{16}\b|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----\r?\n[A-Za-z0-9+/=\r\n]{64,})")


def main():
    errors = []
    markers = []
    for value in (os.environ.get("USERPROFILE"), os.environ.get("LOCALAPPDATA"), str(ROOT)):
        if value and len(value) > 8:
            for variant in (value, value.replace("\\", "/"), value.replace("\\", "\\\\")):
                markers += [variant.encode(), variant.encode("utf-16le")]

    def check_content(name, content):
        if SECRET.search(content):
            errors.append(f"Credential or private key in {name}")
        paths = [match.group().decode(errors="replace").replace("\\", "/").lower() for match in LOCAL_PATH.finditer(content)]
        # These are verified strings in the official dependency wheels: Qt's
        # publisher build account and Python's standard-library path examples.
        # Do not mistake them for the mod author's own computer information.
        allowed = {"c:" + "/users/qt"} if name.startswith("PySide6") else set()
        if name in ("python312.dll", "base_library.zip"):
            allowed.add("c:" + "/users/barney")
        if any(path not in allowed for path in paths) or any(marker in content for marker in markers):
            errors.append(f"Local machine path embedded in {name}")

    def check_code(name, code):
        if isinstance(code, types.CodeType):
            check_content(name + " filename", code.co_filename.encode())
            for constant in code.co_consts:
                if isinstance(constant, types.CodeType):
                    check_code(name, constant)
                elif isinstance(constant, str):
                    check_content(name + " string", constant.encode())

    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT).as_posix()
        if ".git" in path.relative_to(ROOT).parts:
            continue
        if any(part in FORBIDDEN_DIRECTORIES for part in path.relative_to(ROOT).parts):
            errors.append(f"Private/generated artifact in {relative}")
            continue
        if path.is_file():
            if path.name in FORBIDDEN_FILES or path.name.startswith(".env.") or path.suffix.lower() in (".pyc", ".pyo", ".log", ".spec", ".pem", ".key"):
                errors.append(f"Private/generated file in {relative}")
            content = path.read_bytes()
            check_content(relative, content)
            if path.suffix == ".ipynb":
                notebook = json.loads(content)
                for cell in notebook["cells"]:
                    if cell.get("outputs") or cell.get("execution_count") is not None:
                        errors.append(f"Executed notebook output in {relative}")
            if path.name == "ponyponyparadise-voice-mod.zip":
                allowed_names = {"PonyPonyParadiseVoiceSetup.exe", "INSTALL.txt", "LICENSE", "THIRD_PARTY_NOTICES.md", "data/voices/opening_manifest.json"}
                with zipfile.ZipFile(path) as release:
                    for entry in release.infolist():
                        if entry.filename not in allowed_names and not re.fullmatch(r"data/voices/en/[a-f0-9]{64}\.mp3", entry.filename):
                            errors.append("Unexpected file in release ZIP: " + entry.filename)
                        data = release.read(entry)
                        if entry.filename == "PonyPonyParadiseVoiceSetup.exe":
                            if data != (ROOT / entry.filename).read_bytes():
                                errors.append("Release ZIP contains a different installer")
                        else:
                            check_content(entry.filename, data)
            if path.name == "PonyPonyParadiseVoiceSetup.exe":
                try:
                    from PyInstaller.archive.readers import CArchiveReader
                except ImportError:
                    print("EXE archive audit requires requirements-installer.txt.")
                    errors.append("Unable to audit the EXE archive")
                    continue
                import marshal
                archive = CArchiveReader(path)
                for name, record in archive.toc.items():
                    if "__pycache__" in name or name.endswith(".pyc"):
                        errors.append(f"Python cache bundled in {name}")
                    if record[-1] == "z":
                        pyz = archive.open_embedded_archive(name)
                        for module in pyz.toc:
                            if module == "script" or module.startswith("voice_mod"):
                                check_code(module, pyz.extract(module))
                    elif record[-1] == "s":
                        check_code(name, marshal.loads(archive.extract(name)))
                    else:
                        check_content(name, archive.extract(name))
    template = json.loads((ROOT / "config.json").read_text())
    if template["omnivoice"]["python_path"] or template["omnivoice"]["install_path"]:
        errors.append("Public configuration contains a selected interpreter or install folder")
    if Path(template["game_path"]).is_absolute():
        errors.append("Public configuration contains an absolute game path")
    if errors:
        print("\n".join(sorted(set(errors))))
        return 1
    print("Public folder audit passed: no personal machine paths, private settings, logs, caches or notebook outputs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
