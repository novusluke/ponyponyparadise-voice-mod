"""Build the Windows release with all intermediate files in private app data."""
from __future__ import annotations

import os
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from voice_mod.settings import state_directory


def main():
    debug = "--debug" in sys.argv
    name = "PonyVoiceDebug" if debug else "PonyPonyParadiseVoiceSetup"
    if sys.platform != "win32":
        raise SystemExit("Build this Windows installer on Windows.")
    work = state_directory() / "development/release-build"
    work.mkdir(parents=True, exist_ok=True)
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    # Render a code-native vector icon; all raster intermediates stay private.
    from PySide6.QtCore import QRectF
    from PySide6.QtGui import QImage, QPainter
    from PySide6.QtSvg import QSvgRenderer
    from PIL import Image
    art = QImage(256, 256, QImage.Format.Format_ARGB32)
    art.fill(0)
    painter = QPainter(art)
    QSvgRenderer(str(ROOT / "assets/installer-icon.svg")).render(painter, QRectF(0, 0, 256, 256))
    painter.end()
    art.save(str(work / "icon.png"))
    Image.open(work / "icon.png").save(work / "icon.ico", sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    metadata = json.loads((ROOT / "release.json").read_text(encoding="utf-8"))
    version = metadata["version"]
    version_parts = tuple(int(part) for part in version.split(".")) + (0,)
    version_info = work / "version-info.txt"
    version_info.write_text(f"""VSVersionInfo(
  ffi=FixedFileInfo(filevers={version_parts!r}, prodvers={version_parts!r}, mask=0x3f,
                    flags=0x0, OS=0x40004, fileType=0x1, subtype=0x0, date=(0,0)),
  kids=[StringFileInfo([StringTable('040904B0', [
    StringStruct('FileDescription', 'PonyPonyParadise Voice Setup'),
    StringStruct('FileVersion', '{version}'),
    StringStruct('ProductName', 'PonyPonyParadise Voice Mod'),
    StringStruct('ProductVersion', '{version}'),
    StringStruct('OriginalFilename', '{name}.exe')
  ])]), VarFileInfo([VarStruct('Translation', [1033,1200])])]
)\n""", encoding="utf-8")
    command = [sys.executable, "-B", "-m", "PyInstaller", "--noconfirm", "--clean", "--onefile", "--console" if debug else "--windowed", "--noupx",
               "--name", name, "--icon", str(work / "icon.ico"), "--version-file", str(version_info),
               "--specpath", str(work / "spec"), "--workpath", str(work / "work"), "--distpath", str(work / "dist")]
    # Build from an explicit, filtered resource list. Never bundle Python caches,
    # a developer's preferences or their machine-specific build paths.
    with tempfile.TemporaryDirectory(prefix="payload-", dir=work) as directory:
        staging = Path(directory)
        for item in ("assets", "config.json", "config.schema.json", "release.json", "requirements.txt",
                     "dialogue", "reference_audios", "character_assets", "data", "game_patch", "voice_mod", "THIRD_PARTY_NOTICES.md", "LICENSE"):
            source = ROOT / item
            if source.is_dir():
                shutil.copytree(source, staging / item, ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "*.log"))
            elif source.is_file():
                shutil.copyfile(source, staging / item)
        metadata = json.loads((staging / "release.json").read_text())
        for folder in (staging / "reference_audios", staging / "data/voices"):
            for language in folder.iterdir():
                if language.is_dir() and language.name != "en":
                    if not language.resolve().is_relative_to(staging.resolve()):
                        raise ValueError("Language payload escaped the build folder.")
                    shutil.rmtree(language)
        repository = os.environ.get("GITHUB_REPOSITORY", "")
        if repository:
            import script
            metadata["github_repository"] = script.repository_name(repository)
            (staging / "release.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
        shutil.copyfile(ROOT / "installer.py", staging / "installer.py")
        shutil.copyfile(ROOT / "script.py", staging / "script.py")
        command.extend(["--paths", str(staging), "--add-data", f"{staging}:payload", str(staging / "installer.py")])
        # DLL collection must not pick up unrelated image/video tools from a
        # developer's PATH. In particular, their ICU can break Qt at startup.
        environment = os.environ.copy()
        windows = Path(os.environ["WINDIR"])
        environment["PATH"] = os.pathsep.join(map(str, (Path(sys.executable).parent, Path(sys.base_prefix),
                                                        windows / "System32", windows)))
        subprocess.run(command, cwd=work, env=environment, check=True)
    output = (work / "PonyVoiceDebug.exe") if debug else ROOT / "PonyPonyParadiseVoiceSetup.exe"
    shutil.copyfile(work / "dist" / (name + ".exe"), output)
    print(f"Built {output.name} ({output.stat().st_size // 1_000_000} MB).")


if __name__ == "__main__":
    main()
