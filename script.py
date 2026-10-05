#!/usr/bin/env python3
"""Portable local OmniVoice setup and asset sync.

The setup manager requires only Python 3.10+ standard library. Heavy inference
packages are installed only in the selected OmniVoice virtual environment.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

from voice_mod.common import atomic_json, language_code, line_id, manifest_lines, speaker_id, speech_text
from voice_mod.pck import read_pack, write_pack
from voice_mod.settings import preferences_path, state_directory

ROOT = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
if getattr(sys, "frozen", False):
    ROOT = ROOT / "payload"
OMNIVOICE_URL = "https://github.com/k2-fsa/OmniVoice.git"
SUPPORTED_REFERENCE_SUFFIXES = {".mp3", ".wav", ".ogg", ".flac", ".txt"}
DEFAULTS = {
    "schema_version": 1, "game_path": "../PonyPonyParadise", "github_repository": "novusluke/ponyponyparadise-voice-mod",
    "github_branch": "main", "enabled": True, "execution_mode": "local", "language": "en",
    "volume_db": 0.0, "request_timeout_seconds": 120,
    "text_display_mode": "wait",
    "setup_music": {"muted": False, "volume": 25},
    "omnivoice": {"install_path": "", "python_path": "",
                  "revision": "08be0b4ccbac3e13e374e86fbfead4b4cac343e2",
                  "model": "k2-fsa/OmniVoice", "device": "cuda:0", "num_step": 64,
                  "speed": 1.0, "torch_index": "https://download.pytorch.org/whl/cu128",
                  "reference_max_seconds": 10, "default_voice": "", "character_voices": {}},
}


def resolve_path(value: str, base: Path = ROOT) -> Path:
    return (base / Path(value).expanduser()).resolve()


def stored_path(path: Path, base: Path = ROOT) -> str:
    # Relative when possible; a user-selected folder on another drive must be absolute.
    try:
        return Path(os.path.relpath(path.resolve(), base.resolve())).as_posix()
    except ValueError:
        return str(path.resolve())


def load_config(path: Path) -> dict:
    config = copy.deepcopy(DEFAULTS)
    if path.exists():
        value = json.loads(path.read_text(encoding="utf-8-sig"))
        if not isinstance(value, dict) or value.get("schema_version", 1) != 1:
            raise ValueError("Unsupported config.json schema.")
        options = value.pop("omnivoice", {})
        config.update(value)
        config["omnivoice"].update(options)
    language_code(config["language"])
    config["language"] = "en"
    config["omnivoice"]["num_step"] = 64
    config["omnivoice"]["speed"] = max(0.5, min(2.0, float(config["omnivoice"]["speed"])))
    # Earlier execution preferences migrate to the sole supported engine.
    config["execution_mode"] = "local"
    config.pop("cloud_provider", None)
    config.pop("cache_cleanup_days", None)
    music = config.get("setup_music", {})
    config["setup_music"] = {"muted": bool(music.get("muted", False)),
        "volume": max(0, min(100, int(music.get("volume", 25))))}
    if config["text_display_mode"] not in ("wait", "instant"):
        raise ValueError("text_display_mode must be wait or instant.")
    return config


def repository_name(value: str) -> str:
    value = value.strip().rstrip("/")
    value = re.sub(r"^(https://github\.com/|git@github\.com:)", "", value)
    value = value.removesuffix(".git")
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ValueError("Enter a GitHub owner/repository or GitHub repository URL.")
    return value


def infer_repository(config: dict) -> str:
    if config.get("github_repository"):
        return repository_name(config["github_repository"])
    try:
        result = subprocess.run(["git", "-C", str(ROOT), "remote", "get-url", "origin"],
                                capture_output=True, text=True, timeout=10, check=True,
                                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        return repository_name(result.stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        return ""


def download(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "ponyponyparadise-voice-mod", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def sync_references(config: dict, destination: Path | None = None, remote: bool = True) -> int:
    destination = destination or ROOT / "reference_audios"
    destination.mkdir(parents=True, exist_ok=True)
    bundled = ROOT / "reference_audios"
    if bundled.resolve() != destination.resolve():
        receipt_path = destination / "_bundled_sources.json"
        try:
            previous = json.loads(receipt_path.read_text(encoding="utf-8")) if receipt_path.is_file() else {}
        except (OSError, ValueError):
            previous = {}
        if not isinstance(previous, dict):
            previous = {}
        supplied = {}
        for source in bundled.rglob("*"):
            if source.is_file() and source.relative_to(bundled).parts[0] == "en" and source.suffix in SUPPORTED_REFERENCE_SUFFIXES:
                target = destination / source.relative_to(bundled)
                relative = source.relative_to(bundled).as_posix()
                checksum = hashlib.sha256(source.read_bytes()).hexdigest()
                supplied[relative] = checksum
                if not target.exists() or previous.get(relative) != checksum:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, target)
                    if source.suffix != ".txt" and not source.with_suffix(".txt").exists():
                        target.with_suffix(".txt").unlink(missing_ok=True)
        if supplied:
            atomic_json(receipt_path, supplied)
    repository = infer_repository(config)
    count = 0
    if remote and repository:
        branch = urllib.parse.quote(config.get("github_branch", "main"), safe="")
        prefix = f"https://api.github.com/repos/{repository}/contents/reference_audios"
        try:
            languages = json.loads(download(prefix + f"?ref={branch}"))
            for directory in languages:
                if directory.get("type") != "dir" or directory.get("name") != "en":
                    continue
                language = language_code(directory["name"])
                entries = json.loads(download(prefix + "/" + language + f"?ref={branch}"))
                available = {entry.get("name", "") for entry in entries if entry.get("type") == "file"}
                for entry in entries:
                    name = entry["name"]
                    if entry.get("type") != "file" or not re.fullmatch(r"[a-z0-9]+\.(mp3|wav|ogg|flac|txt)", name):
                        continue
                    target = destination / language / name
                    sha = entry.get("sha", "")
                    if target.is_file() and git_blob_sha(target.read_bytes()) == sha:
                        continue
                    url = entry.get("download_url", "")
                    if urllib.parse.urlparse(url).hostname != "raw.githubusercontent.com":
                        raise ValueError("Unexpected reference download host.")
                    content = download(url)
                    if git_blob_sha(content) != sha:
                        raise ValueError(f"Reference checksum mismatch: {name}")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    tmp = target.with_suffix(target.suffix + ".tmp")
                    tmp.write_bytes(content)
                    os.replace(tmp, target)
                    if target.suffix != ".txt" and target.with_suffix(".txt").name not in available:
                        target.with_suffix(".txt").unlink(missing_ok=True)
                    count += 1
            print(f"Reference sync: {count} new/updated files from {repository}.")
        except (urllib.error.URLError, json.JSONDecodeError) as error:
            print(f"Reference sync unavailable ({error}); using bundled clips.")
    elif remote:
        print("Using bundled reference clips. After publishing, set --repo OWNER/REPO or configure the Git origin.")
    return count


def git_blob_sha(content: bytes) -> str:
    return hashlib.sha1(f"blob {len(content)}\0".encode() + content).hexdigest()


def python_candidates(folder: Path) -> list[Path]:
    candidates = [folder] if folder.is_file() else []
    for base in (folder, folder / ".venv", folder / "venv", folder / "env"):
        candidates += [base / "Scripts/python.exe", base / "bin/python"]
    return [p for p in candidates if p.is_file()]


def probe_python(python: Path) -> bool:
    try:
        probe = subprocess.run([str(python), "-c", "import importlib.util; raise SystemExit(0 if importlib.util.find_spec('omnivoice') else 1)"],
                               capture_output=True, timeout=20,
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        return probe.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def find_omnivoice(config: dict) -> Path | None:
    options = config["omnivoice"]
    candidates = []
    if options.get("python_path"):
        candidates.append(resolve_path(options["python_path"]))
    if os.environ.get("OMNIVOICE_HOME"):
        candidates.extend(python_candidates(Path(os.environ["OMNIVOICE_HOME"])))
    if options.get("install_path"):
        candidates.extend(python_candidates(resolve_path(options["install_path"])))
    if not getattr(sys, "frozen", False):
        candidates.append(Path(sys.executable))
    return next((p for p in dict.fromkeys(candidates) if probe_python(p)), None)


def run(command: list[str], **kwargs) -> None:
    subprocess.run(command, check=True, **kwargs)


def install_omnivoice(folder: Path, options: dict) -> Path:
    folder = folder.resolve()
    revision = options["revision"]
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("OmniVoice revision must be a pinned 40-character commit SHA.")
    if not (folder / "pyproject.toml").exists():
        if folder.exists() and any(folder.iterdir()):
            raise ValueError("Choose an empty installation folder or an existing OmniVoice checkout.")
        folder.parent.mkdir(parents=True, exist_ok=True)
        if shutil.which("git"):
            run(["git", "clone", OMNIVOICE_URL, str(folder)])
            run(["git", "-C", str(folder), "checkout", revision])
        else:
            print("Git unavailable; downloading the pinned OmniVoice source archive.")
            archive = download(f"https://github.com/k2-fsa/OmniVoice/archive/{revision}.zip")
            import io
            with zipfile.ZipFile(io.BytesIO(archive)) as z:
                prefix = z.namelist()[0].split("/")[0] + "/"
                for item in z.infolist():
                    relative = Path(item.filename.removeprefix(prefix))
                    if not relative.parts or ".." in relative.parts or relative.is_absolute():
                        continue
                    target = folder / relative
                    if item.is_dir():
                        target.mkdir(parents=True, exist_ok=True)
                    else:
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(z.read(item))
    venv = folder / ".venv"
    python = venv / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    if not python.exists():
        run([sys.executable, "-m", "venv", str(venv)])
    run([str(python), "-m", "pip", "install", "--upgrade", "pip"])
    run([str(python), "-m", "pip", "install", "torch==2.8.0", "torchaudio==2.8.0",
         "--index-url", options["torch_index"]])
    run([str(python), "-m", "pip", "install", "-e", str(folder), "-r", str(ROOT / "requirements.txt")])
    return python


def configure_local(config: dict, args) -> None:
    options = config["omnivoice"]
    python = None
    if args.python:
        python = resolve_path(args.python)
        if not probe_python(python):
            raise ValueError("Selected Python does not have OmniVoice installed.")
    elif args.omnivoice_folder:
        selected = resolve_path(args.omnivoice_folder)
        python = next((p for p in python_candidates(selected) if probe_python(p)), None)
        if python is None:
            raise ValueError("No installed OmniVoice Python environment found in that folder.")
        options["install_path"] = stored_path(selected)
    elif args.install_omnivoice:
        selected = resolve_path(args.install_omnivoice)
        python = install_omnivoice(selected, options)
        options["install_path"] = stored_path(selected)
    else:
        python = find_omnivoice(config)
        if python:
            print(f"Found OmniVoice: {python}")
        elif not sys.stdin.isatty():
            raise ValueError("OmniVoice not found. Use --omnivoice-folder, --python or --install-omnivoice PATH.")
        else:
            choice = input("OmniVoice not found. [1] Select existing folder [2] Download/install: ").strip()
            selected = resolve_path(input("OmniVoice folder path: ").strip().strip('"'))
            if choice == "1":
                python = next((p for p in python_candidates(selected) if probe_python(p)), None)
                if python is None:
                    raise ValueError("OmniVoice is not installed in the selected folder.")
            elif choice == "2":
                python = install_omnivoice(selected, options)
            else:
                raise ValueError("Choose 1 or 2.")
            options["install_path"] = stored_path(selected)
    # This helper is also needed by an existing environment.
    run([str(python), "-m", "pip", "install", "-r", str(ROOT / "requirements.txt")])
    run([str(python), "-c", "from omnivoice import OmniVoice; import torch, imageio_ffmpeg; print('CUDA available:', torch.cuda.is_available())"])
    options["python_path"] = stored_path(python)


def install_game(game: Path, config: dict, references: Path | None = None) -> None:
    config = copy.deepcopy(config)
    config["language"] = "en"
    state = {}
    pack_path = game / "PonyPonyParadise.pck"
    if not pack_path.is_file():
        raise FileNotFoundError(f"Game PCK not found: {pack_path}")
    backup = game / "PonyPonyParadise.pck.voice-mod-original"
    state_path = game / "data/voice_mod/install_state.json"
    if backup.exists():
        if not state_path.exists():
            raise ValueError("An original backup exists without install metadata. Preserve it and inspect the game first.")
        state = json.loads(state_path.read_text())
        if hashlib.sha256(backup.read_bytes()).hexdigest() != state["original_sha256"]:
            raise ValueError("Original backup checksum changed; refusing to overwrite the game.")
        if hashlib.sha256(pack_path.read_bytes()).hexdigest() != state["installed_sha256"]:
            raise ValueError("Game changed since installation. Restore/update it before reinstalling this mod.")
    original = backup if backup.exists() else pack_path
    pack = read_pack(original)
    compatibility = json.loads((ROOT / "game_patch/compatibility.json").read_text())
    for relative, digest in compatibility["base_scripts"].items():
        bytecode = relative.removesuffix(".gd") + ".gdc"
        if hashlib.sha256(pack.files.get(bytecode, b"")).hexdigest() != digest:
            raise ValueError(f"Unsupported game build: {relative} differs from the clean supported version.")
    # Refuse old experiments, even if somebody reused matching files from this build.
    if any("omnivoice" in p.lower() or "codex" in p.lower() for p in pack.files):
        raise ValueError("Install on a clean game copy; an old experimental mod is present.")
    for source in (ROOT / "game_patch").rglob("*.gd"):
        relative = source.relative_to(ROOT / "game_patch").as_posix()
        pack.files[relative] = source.read_bytes()
        pack.files.pop(relative + ".remap", None)
        pack.files.pop(relative.removesuffix(".gd") + ".gdc", None)
    staged = pack_path.with_suffix(".pck.voice-mod-staged")
    write_pack(staged, pack)
    read_pack(staged)  # Verify every checksum before replacing the exported pack.
    if not backup.exists():
        shutil.copy2(pack_path, backup)
    mod = game / "data/voice_mod"
    from voice_mod.uninstall import preserve_original_files, digest
    from voice_mod.characters import installation_sources
    resources = set()
    characters = installation_sources(game, ROOT)
    sources = ((ROOT / "voice_mod", "data/voice_mod/voice_mod"),
               (references or ROOT / "reference_audios", "data/voice_mod/reference_audios"),
               (ROOT / "data/voices", "data/voices"), *characters)
    for folder, prefix in sources:
        for path in folder.rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc":
                relative = path.relative_to(folder)
                if prefix == "data/voice_mod/reference_audios" and (len(relative.parts) < 2 or relative.parts[0] != "en"):
                    continue
                if prefix == "data/voices" and len(relative.parts) > 1 and relative.parts[0] != "en":
                    continue
                resources.add(prefix + "/" + path.relative_to(folder).as_posix())
    resources.update(("data/voice_mod/config.json", "data/voice_mod/worker_bootstrap.py"))
    receipt = preserve_original_files(game.resolve(), resources, state, ROOT)
    mod.mkdir(parents=True, exist_ok=True)
    for source, relative in characters:
        shutil.copytree(source, game / relative)
    shutil.copytree(ROOT / "voice_mod", mod / "voice_mod", dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    (mod / "worker_bootstrap.py").write_text("from voice_mod.worker import main\nif __name__ == '__main__':\n    main()\n", encoding="utf-8")
    if references is None:
        sync_references(config, mod / "reference_audios", remote=False)
    elif references.resolve() != (mod / "reference_audios").resolve():
        if (references / "en").is_dir():
            shutil.copytree(references / "en", mod / "reference_audios/en", dirs_exist_ok=True)
    # A replaced reference must not inherit the previous sample's transcript.
    reference_source = references or ROOT / "reference_audios"
    for audio in reference_source.rglob("*"):
        if audio.is_file() and audio.relative_to(reference_source).parts[0] == "en" and audio.suffix in SUPPORTED_REFERENCE_SUFFIXES - {".txt"} and not audio.with_suffix(".txt").is_file():
            (mod / "reference_audios" / audio.relative_to(reference_source)).with_suffix(".txt").unlink(missing_ok=True)
    bundled = ROOT / "data/voices"
    if bundled.is_dir():
        if (bundled / "en").is_dir():
            shutil.copytree(bundled / "en", game / "data/voices/en", dirs_exist_ok=True)
        if (bundled / "opening_manifest.json").is_file():
            shutil.copyfile(bundled / "opening_manifest.json", game / "data/voices/opening_manifest.json")
    runtime = {key: config[key] for key in ("schema_version", "enabled", "execution_mode", "language", "volume_db", "request_timeout_seconds", "github_branch", "text_display_mode")}
    runtime.update({"github_repository": infer_repository(config), "references_path": "reference_audios", "voices_path": "../voices", "omnivoice": copy.deepcopy(config["omnivoice"]), "python_path": ""})
    runtime["omnivoice"]["num_step"] = 64
    if config["omnivoice"].get("python_path"):
        runtime["python_path"] = stored_path(resolve_path(config["omnivoice"]["python_path"]), mod)
    atomic_json(mod / "config.json", runtime)
    state = {"schema_version": 1, "original_sha256": hashlib.sha256(original.read_bytes()).hexdigest(),
             "installed_sha256": hashlib.sha256(staged.read_bytes()).hexdigest(), "engine": pack.engine}
    from voice_mod.installer_service import patch_fingerprint, release_metadata
    state.update({"mod_version": release_metadata()["version"], "patch_fingerprint": patch_fingerprint()})
    receipt["owned_files"].update({relative: digest(game / relative) for relative in resources if (game / relative).is_file()})
    state.update(receipt, status="installed")
    os.replace(staged, pack_path)
    atomic_json(state_path, state)
    print(f"Voice mod installed: {game}\nOriginal backup: {backup.name}")


def export_dialogue(game: Path, output: Path, language: str, include_captured: bool = True) -> int:
    backup = game / "PonyPonyParadise.pck.voice-mod-original"
    pack = read_pack(backup if backup.exists() else game / "PonyPonyParadise.pck")
    rows = {}
    speaker_pattern = re.compile(r'^"?(?P<speaker>[A-Za-z_][A-Za-z_0-9 ]*)"?(?:\s*\([^)]*\))?\s*:\s*(?P<text>.+)$')
    for name, content in pack.files.items():
        if not name.endswith(".dtl"):
            continue
        for raw in content.decode("utf-8").splitlines():
            text = raw.strip()
            if not text or text.startswith(("#", "[background", "[wait", "- ", "if ", "elif ", "else:", "set ", "join ", "leave ", "update ", "audio ", "signal ", "jump ", "return", "wait ", "do ", "label ", "call ")):
                continue
            match = speaker_pattern.match(text)
            speaker = speaker_id(match["speaker"] if match else "narrator")
            text = speech_text(match["text"] if match else text)
            # Variable-dependent lines need their resolved text captured during play.
            if not text or "{" in text or "}" in text:
                continue
            key = line_id(language, speaker, text)
            rows[key] = {"id": key, "language": language, "speaker": speaker, "text": text}
    capture = game / "data/voice_mod/dialogue_manifest.json"
    if include_captured and capture.exists():
        captured = json.loads(capture.read_text(encoding="utf-8")).get("lines", [])
        # Recompute identities when upgrading an earlier narrator mapping.
        for row in captured:
            lang = language_code(row.get("language", "en"))
            speaker = speaker_id(row.get("speaker", "narrator"))
            text = speech_text(row.get("text", ""))
            key = line_id(lang, speaker, text)
            rows[key] = {"id": key, "language": lang, "speaker": speaker, "text": text}
    atomic_json(output, {"schema_version": 1, "lines": list(rows.values())})
    print(f"Exported {len(rows)} lines: {output}")
    return len(rows)


def main(argv=None) -> int:
    if sys.version_info < (3, 10):
        raise SystemExit("Python 3.10 or newer is required.")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", default="setup", choices=("setup", "sync", "doctor", "uninstall"))
    parser.add_argument("--config", type=Path, default=preferences_path(), help="Private settings file (outside the repository by default).")
    parser.add_argument("--game", help="Game folder; paths are resolved from script.py, never the shell working directory.")
    parser.add_argument("--repo", help="GitHub owner/repository (auto-detected from origin when possible).")
    parser.add_argument("--branch", help="GitHub branch containing reference_audios (default: config.json).")
    parser.add_argument("--omnivoice-folder", help="Existing OmniVoice checkout or virtual environment.")
    parser.add_argument("--install-omnivoice", metavar="PATH", help="Download/install OmniVoice in this folder.")
    parser.add_argument("--python", help="Existing Python executable with OmniVoice installed.")
    parser.add_argument("--skip-sync", action="store_true", help="Use bundled references without checking GitHub.")
    args = parser.parse_args(argv)
    try:
        config = load_config(args.config)
        if args.game:
            config["game_path"] = stored_path(resolve_path(args.game))
        if args.repo:
            config["github_repository"] = repository_name(args.repo)
        if args.branch:
            config["github_branch"] = args.branch
        game = resolve_path(config["game_path"])
        if args.command == "setup":
            configure_local(config, args)
            sync_references(config, remote=not args.skip_sync)
            install_game(game, config)
            atomic_json(args.config, config)
        elif args.command == "sync":
            sync_references(config, remote=not args.skip_sync)
            if (game / "data/voice_mod").is_dir():
                sync_references(config, game / "data/voice_mod/reference_audios", remote=False)
            atomic_json(args.config, config)
        elif args.command == "doctor":
            print(f"Mod folder: {ROOT}\nGame folder: {game}\nMode: {config['execution_mode']}\nGitHub repository: {infer_repository(config) or '(not published yet)'}")
            print(f"Reference audio files: {len(list((ROOT / 'reference_audios').rglob('*.mp3')))}")
            print(f"OmniVoice Python: {find_omnivoice(config) or '(not configured)'}")
            read_pack(game / "PonyPonyParadise.pck")
            print("Game PCK checksums: OK")
        elif args.command == "uninstall":
            from voice_mod.installer_service import uninstall_voices
            uninstall_voices(game, print)
        return 0
    except (ValueError, OSError, subprocess.SubprocessError, zipfile.BadZipFile) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
