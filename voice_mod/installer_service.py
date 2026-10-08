"""Installer operations without a GUI dependency; suitable for offline tests."""
from __future__ import annotations

import copy
import hashlib
import io
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import uuid
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

import script as backend
from .common import atomic_json
from .settings import application_directory, preferences_path, state_directory

UV_VERSION = "0.12.21"
UV_SHA256 = "5d223efa0bf00208c3853246af09420419dfbd352536aa6bb8163d6170e23890"
PROBE_CODE = """import importlib.util,json,sys
info = {'python':sys.version.split()[0], 'omnivoice':bool(importlib.util.find_spec('omnivoice')), 'encoder':bool(importlib.util.find_spec('imageio_ffmpeg'))}
if info['omnivoice']:
    try:
        from omnivoice import OmniVoice, OmniVoiceGenerationConfig
        from omnivoice.models.omnivoice import VoiceClonePrompt
        import torch
        info['loaded'] = callable(getattr(OmniVoice, 'from_pretrained', None))
        info['cuda'] = torch.cuda.is_available()
        info['torch'] = torch.__version__
    except Exception:
        info['loaded'] = False
print(json.dumps(info))
"""


def release_metadata() -> dict:
    path = backend.ROOT / "release.json"
    return json.loads(path.read_text()) if path.exists() else {"version": "1.0.2", "github_repository": "", "github_branch": "main"}


def patch_fingerprint() -> str:
    digest = hashlib.sha256()
    for path in sorted((backend.ROOT / "game_patch").rglob("*.gd")):
        digest.update(path.relative_to(backend.ROOT).as_posix().encode("utf-8"))
        digest.update(path.read_bytes())
    return digest.hexdigest()


def load_preferences() -> dict:
    config = backend.load_config(preferences_path())
    game = Path(config["game_path"]) if Path(config["game_path"]).is_absolute() else default_game_folder()
    runtime = game / "data/voice_mod/config.json"
    if runtime.is_file():
        current = json.loads(runtime.read_text(encoding="utf-8"))
        for field in ("text_display_mode", "cache_cleanup_days"):
            if field in current:
                config[field] = current[field]
    if runtime.is_file() and not config["omnivoice"].get("python_path"):
        value = json.loads(runtime.read_text(encoding="utf-8"))
        for field in ("enabled", "execution_mode", "language", "volume_db", "omnivoice", "text_display_mode", "cache_cleanup_days"):
            if field in value:
                if field == "omnivoice":
                    config[field].update(value[field])
                else:
                    config[field] = value[field]
        python = value.get("python_path", "")
        if python:
            config["omnivoice"]["python_path"] = str((runtime.parent / python).resolve())
    if not config["omnivoice"].get("install_path"):
        config["omnivoice"]["install_path"] = str(state_directory() / "OmniVoice")
    from .common import quality_steps
    config["omnivoice"]["num_step"] = quality_steps(config["omnivoice"].get("num_step", 64))
    config["execution_mode"] = "local"
    config["language"] = "en"
    config["github_repository"] = release_metadata().get("github_repository", "") or backend.DEFAULTS["github_repository"]
    config.pop("cloud_provider", None)
    return config


def save_preferences(config: dict) -> None:
    from .common import quality_steps
    config["omnivoice"]["num_step"] = quality_steps(config["omnivoice"].get("num_step", 64))
    atomic_json(preferences_path(), config)


def default_game_folder() -> Path:
    base = application_directory()
    for candidate in (base, base.parent, base.parent / "PonyPonyParadise", base / "PonyPonyParadise"):
        if (candidate / "PonyPonyParadise.pck").is_file():
            return candidate
    return base.parent / "PonyPonyParadise"


def public_repository_directory() -> Path | None:
    base = application_directory().resolve()
    # A manually packaged source ZIP may be extracted beside the game's PCK.
    # The frozen setup still reads templates from its embedded payload and
    # stores preferences privately; that installed game is an allowed target.
    if getattr(sys, "frozen", False) and (base / "PonyPonyParadise.pck").is_file():
        return None
    if (base / "script.py").is_file() and (base / "game_patch").is_dir():
        return base
    return None


def require_private_destination(path: Path) -> None:
    repo = public_repository_directory()
    path = path.resolve()
    if repo is not None and (path == repo or repo in path.parents):
        raise ValueError("Choose a folder outside the public mod repository. Personal environments and game data must stay separate.")


def clean_subprocess_environment() -> dict:
    environment = os.environ.copy()
    # A frozen installer must not inject its extraction DLLs into a real Python.
    for name in ("PYTHONHOME", "PYTHONPATH", "QT_PLUGIN_PATH", "QT_QPA_PLATFORM_PLUGIN_PATH"):
        environment.pop(name, None)
    return environment


def command_result(command: list[str], timeout=30) -> subprocess.CompletedProcess:
    return subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace",
                          timeout=timeout, env=clean_subprocess_environment(),
                          creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


def inspect_environment(folder: Path) -> dict:
    candidates = backend.python_candidates(folder)
    if not candidates:
        return {"ok": False, "kind": "missing", "message": "No OmniVoice environment found. Click Download & install OmniVoice, or Use existing to select an installation."}
    errors = []
    repairable = False
    for python in candidates:
        try:
            result = command_result([str(python), "-I", "-c", PROBE_CODE], timeout=60)
            if result.returncode != 0:
                reason = (result.stderr or result.stdout).strip()
                if "No Python at" in reason or "Unable to create process" in reason:
                    cfg = python.parent.parent / "pyvenv.cfg"
                    repairable = repairable or (os.name == "nt" and cfg.is_file() and bool(venv_version(cfg)))
                    errors.append("The environment’s base Python was removed or moved. Use Repair environment to restore a compatible Python, or Install OmniVoice in a new empty folder.")
                else:
                    errors.append("This Python environment cannot start. Install a fresh environment or choose another folder.")
                continue
            info = json.loads(result.stdout.strip().splitlines()[-1])
            if not info["omnivoice"]:
                errors.append("Python works, but OmniVoice is not installed in this environment.")
                continue
            if not info.get("loaded"):
                errors.append("OmniVoice is installed, but its dependencies cannot load. Repair the environment or install OmniVoice in a new folder.")
                continue
            return {"ok": True, "kind": "ready", "python_path": str(python.resolve()), **info,
                    "message": "OmniVoice detected · Python " + info["python"] + (" · CUDA ready" if info.get("cuda") else " · CUDA unavailable; check your NVIDIA driver")}
        except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError, IndexError):
            errors.append("Could not inspect this Python environment. Choose another folder or install a fresh environment.")
    return {"ok": False, "kind": "broken", "repairable": repairable,
            "message": errors[0] if errors else "OmniVoice is unavailable."}


def venv_version(cfg: Path) -> str:
    values = dict(line.split("=", 1) for line in cfg.read_text(encoding="utf-8-sig").splitlines() if "=" in line)
    values = {key.strip(): value.strip() for key, value in values.items()}
    match = re.match(r"^(3\.\d+)(?:\.|$)", values.get("version", values.get("version_info", "")))
    return match[1] if match else ""


def windows_architecture(python: Path) -> int:
    with python.open("rb") as stream:
        if stream.read(2) != b"MZ":
            raise ValueError("The selected Python executable is invalid.")
        stream.seek(0x3c)
        offset = struct.unpack("<I", stream.read(4))[0]
        stream.seek(offset)
        if stream.read(4) != b"PE\x00\x00":
            raise ValueError("The selected Python executable is invalid.")
        return struct.unpack("<H", stream.read(2))[0]


def repair_environment(folder: Path, log) -> dict:
    """Restore a missing Windows base interpreter, with ABI checks and rollback.

    Repoint only the redirector's configuration, never an unrelated interpreter
    or the user's packages. Installation scripts are not invoked via stale
    activation/entry-point paths. Unsupported environments get a fresh-install
    recovery message; browsing and detection themselves remain read-only.
    """
    require_private_destination(folder)
    current = inspect_environment(folder)
    if current["ok"]:
        return current
    if not current.get("repairable"):
        raise ValueError("This environment cannot be repaired automatically. Install OmniVoice in a new empty folder.")
    python = next((path for path in backend.python_candidates(folder)
                   if (path.parent.parent / "pyvenv.cfg").is_file()), None)
    if python is None:
        raise ValueError("No virtual environment configuration was found.")
    cfg = python.parent.parent / "pyvenv.cfg"
    version = venv_version(cfg)
    uv = ensure_uv(log)
    environment = clean_subprocess_environment()
    environment.update({"UV_PYTHON_INSTALL_DIR": str(state_directory() / "python"),
                        "UV_CACHE_DIR": str(state_directory() / "cache/uv")})
    command = [str(uv), "python", "find", "--managed-python", version]
    def find_python():
        return subprocess.run(command, env=environment, capture_output=True, text=True, timeout=30,
                              creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    found = find_python()
    if found.returncode:
        log("Downloading the environment’s matching Python version…")
        run_logged([str(uv), "python", "install", version], log, environment=environment)
        found = find_python()
    if found.returncode:
        raise ValueError("A compatible Python could not be located. Install a fresh OmniVoice environment.")
    base = Path(found.stdout.strip()).resolve()
    check = command_result([str(base), "-c", "import json,sys;print(json.dumps({'minor':'.'.join(map(str,sys.version_info[:2])),'version':sys.version.split()[0]}))"])
    info = json.loads(check.stdout.strip()) if check.returncode == 0 else {}
    if info.get("minor") != version or windows_architecture(base) != windows_architecture(python):
        raise ValueError("Python version or architecture differs. Install OmniVoice in a new empty folder.")
    original = cfg.read_bytes()
    backup = state_directory() / "environment-repairs" / uuid.uuid4().hex / "pyvenv.cfg.original"
    backup.parent.mkdir(parents=True, exist_ok=True)
    backup.write_bytes(original)
    text = original.decode("utf-8-sig")
    changes = {"home": str(base.parent), "executable": str(base), "version": info["version"],
               "command": f'"{base}" -m venv "{python.parent.parent}"'}
    for key, value in changes.items():
        text, count = re.subn(rf"(?m)^{key}\s*=.*$", lambda _: f"{key} = {value}", text)
        if not count:
            text = text.rstrip() + f"\n{key} = {value}\n"
    staged = cfg.with_name("pyvenv.cfg.voice-mod-repair.tmp")
    try:
        staged.write_text(text, encoding="utf-8")
        os.replace(staged, cfg)
        result = inspect_environment(python)
        if not result["ok"]:
            raise ValueError(result["message"])
        prepare_existing(python, log)
        result = inspect_environment(python)
        result["message"] = "OmniVoice repaired · Python " + result["python"]
        log("Compatible Python restored. Original environment configuration backed up privately.")
        return result
    except Exception:
        cfg.write_bytes(original)
        raise
    finally:
        staged.unlink(missing_ok=True)


def detect_environment(config: dict, extra: Path | None = None) -> dict:
    folders = []
    if extra:
        folders.append(extra)
    options = config["omnivoice"]
    for value in (options.get("python_path"), options.get("install_path"), os.environ.get("OMNIVOICE_HOME"), os.environ.get("VIRTUAL_ENV"), os.environ.get("CONDA_PREFIX")):
        if value:
            folders.append(backend.resolve_path(value))
    base = application_directory()
    folders += [base / "OmniVoice", base.parent / "OmniVoice", Path.home() / "OmniVoice", state_directory() / "OmniVoice"]
    if not getattr(sys, "frozen", False):
        folders.append(Path(sys.executable))
    last = None
    for folder in dict.fromkeys(folders):
        result = inspect_environment(folder)
        if result["ok"]:
            return result
        if result["kind"] == "broken" and last is None:
            last = result
    return last or {"ok": False, "kind": "missing", "message": "No existing OmniVoice found. Browse to its folder or install a fresh environment."}


def run_logged(command: list[str], log, *, environment: dict | None = None) -> None:
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               text=True, encoding="utf-8", errors="replace",
                               env=environment or clean_subprocess_environment(),
                               creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
    for line in process.stdout:
        log(line.rstrip())
    if process.wait() != 0:
        raise RuntimeError("Installation command failed. Details are available in the installer log.")


def ensure_uv(log) -> Path:
    target = state_directory() / "tools/uv.exe"
    if target.is_file():
        return target
    log("Downloading the private Python environment manager…")
    content = backend.download(f"https://github.com/astral-sh/uv/releases/download/{UV_VERSION}/uv-x86_64-pc-windows-msvc.zip", log=log)
    if hashlib.sha256(content).hexdigest() != UV_SHA256:
        raise ValueError("The environment-manager download failed its checksum check.")
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        member = next((n for n in archive.namelist() if Path(n).name == "uv.exe"), None)
        if member is None:
            raise ValueError("The environment-manager archive contains no executable.")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(archive.read(member))
    return target


def new_installation_folder(parent: Path) -> Path:
    parent = parent.expanduser().resolve()
    if not parent.is_dir():
        raise ValueError("Choose a folder where OmniVoice should be installed.")
    folder = parent / "OmniVoice"
    number = 2
    while folder.exists() and (not folder.is_dir() or any(folder.iterdir())):
        folder = parent / f"OmniVoice-{number}"
        number += 1
    require_private_destination(folder)
    return folder


def install_local(folder: Path, options: dict, log) -> dict:
    folder = folder.resolve()
    require_private_destination(folder)
    # Never repoint or overwrite a broken copied venv; Python ABI versions may differ.
    if folder.exists() and any(folder.iterdir()):
        raise ValueError("Choose a new empty folder. The existing environment will be preserved.")
    revision = options["revision"]
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise ValueError("Invalid pinned OmniVoice revision.")
    log("Downloading OmniVoice source…")
    content = backend.download(f"https://github.com/k2-fsa/OmniVoice/archive/{revision}.zip", log=log)
    from .archive import extract_source
    with zipfile.ZipFile(io.BytesIO(content)) as archive:
        extract_source(archive, folder)
    uv = ensure_uv(log)
    environment = clean_subprocess_environment()
    environment.update({"UV_PYTHON_INSTALL_DIR": str(state_directory() / "python"),
                        "UV_CACHE_DIR": str(state_directory() / "cache/uv")})
    venv = folder / ".venv"
    log("Creating a compatible Python environment…")
    run_logged([str(uv), "venv", "--python", "3.11", "--managed-python", "--seed", str(venv)], log, environment=environment)
    python = venv / "Scripts/python.exe"
    log("Installing CUDA PyTorch. This download can take several minutes…")
    run_logged([str(uv), "pip", "install", "--python", str(python), "torch==" + backend.TORCH_VERSION, "torchaudio==" + backend.TORCH_VERSION, "--index-url", options["torch_index"]], log, environment=environment)
    log("Installing OmniVoice and the MP3 encoder…")
    run_logged([str(uv), "pip", "install", "--python", str(python), "-e", str(folder), "-r", str(backend.ROOT / "requirements.txt")], log, environment=environment)
    result = inspect_environment(folder)
    if not result["ok"]:
        raise RuntimeError(result["message"])
    return result


def prepare_existing(python: Path, log) -> None:
    result = inspect_environment(python)
    if not result["ok"]:
        raise ValueError(result["message"])
    if not result.get("encoder"):
        log("Installing the MP3 encoder in the selected environment…")
        run_logged([str(python), "-m", "pip", "install", "-r", str(backend.ROOT / "requirements.txt")], log)
    result = command_result([str(python), "-c", "from omnivoice import OmniVoice; import torch; print('CUDA available:',torch.cuda.is_available())"], timeout=60)
    if result.returncode:
        raise ValueError("OmniVoice cannot load its dependencies. Install a fresh environment or inspect the private log.")
    log(result.stdout.strip())


def apply_voices(game: Path, config: dict, log, save_config: bool = True) -> dict:
    game = game.resolve()
    require_private_destination(game)
    if config["execution_mode"] == "local":
        python = config["omnivoice"].get("python_path", "")
        if not python:
            raise ValueError("Browse or detect a working OmniVoice environment first.")
        prepare_existing(Path(python), log)
    cache = state_directory() / "cache/reference_audios"
    log("Syncing reference voices…")
    backend.sync_references(config, cache, remote=True)
    log("Applying the voice mod and preserving the original game pack…")
    backend.install_game(game, config, references=cache)
    config["game_path"] = str(game)
    if save_config:
        save_preferences(config)
    return {"message": "Voices applied successfully. You can launch the game.",
            "references": len([p for p in cache.rglob("*") if p.suffix.lower() in (".mp3", ".wav", ".ogg", ".flac")])}


def uninstall_voices(game: Path, log) -> dict:
    game = game.resolve()
    require_private_destination(game)
    if os.name == "nt":
        running = command_result(["tasklist", "/FI", "IMAGENAME eq PonyPonyParadise.exe", "/FO", "CSV", "/NH"], timeout=15)
        if running.returncode:
            raise ValueError("Unable to check running games. Close PonyPonyParadise and try again.")
        if any(line.lower().startswith('"ponyponyparadise.exe",') for line in running.stdout.splitlines()):
            raise ValueError("Close PonyPonyParadise before uninstalling its voice mod.")
    from .uninstall import uninstall_game
    return uninstall_game(game, backend.ROOT, log)


def version_tuple(value: str) -> tuple:
    match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)(?:[-+].*)?", value)
    if not match:
        raise ValueError("The release tag is not a supported version number.")
    return tuple(int(x) for x in match.groups())


def check_updates(repository: str, current: str) -> dict:
    repository = backend.repository_name(repository)
    try:
        release = json.loads(backend.download(f"https://api.github.com/repos/{repository}/releases/latest"))
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return {"kind": "unpublished", "message": "No public release has been published yet.", "url": f"https://github.com/{repository}/releases"}
        raise ValueError("GitHub could not check releases. Try again later.") from error
    latest = str(release["tag_name"])
    newer = version_tuple(latest) > version_tuple(current)
    result = {"kind": "available" if newer else "current", "latest": latest,
              "message": f"Version {latest} is available." if newer else f"You have the latest release ({current}).",
              "url": f"https://github.com/{repository}/releases/latest", "download": ""}
    for asset in release.get("assets", []):
        url = str(asset.get("browser_download_url", ""))
        if asset.get("name") in ("ponyponyparadise-voice-mod.zip", "PonyPonyParadiseVoiceSetup.exe") and url.startswith(f"https://github.com/{repository}/releases/download/"):
            if result["download"].endswith(".zip"):
                continue
            result["download"] = url
    return result
