"""Prepare a separate game and save namespace for Godot regression checks."""
import argparse
import copy
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import script
from voice_mod.pck import read_pack, write_pack
from voice_mod.installer_service import require_private_destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-game", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    source, output = args.source_game.resolve(), args.output.resolve()
    require_private_destination(output)
    if output == source or output.is_relative_to(source) or (output.exists() and any(output.iterdir())):
        parser.error("Choose a new empty QA folder outside the source game.")
    original = source / "PonyPonyParadise.pck.voice-mod-original"
    pack = read_pack(original if original.is_file() else source / "PonyPonyParadise.pck")
    name = b"PonyPonyParadise"
    if name not in pack.files.get("project.binary", b""):
        parser.error("Unsupported project configuration; QA namespace cannot be isolated.")
    # Equal byte lengths preserve Godot's binary string serialization. The
    # separate name is a fallback if an editor ignores project overrides.
    pack.files["project.binary"] = pack.files["project.binary"].replace(name, b"PonyVoiceModQA__")
    pack.files["override.cfg"] = b'[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="PonyVoiceModQA__/tests"\n'
    output.mkdir(parents=True, exist_ok=True)
    write_pack(output / "PonyPonyParadise.pck", pack)
    shutil.copytree(source / "data", output / "data", dirs_exist_ok=True,
                    ignore=shutil.ignore_patterns("voice_mod", "voices"))
    script.install_game(output, copy.deepcopy(script.DEFAULTS))
    print("QA game prepared. Source game and save files were not modified.")


if __name__ == "__main__":
    main()
