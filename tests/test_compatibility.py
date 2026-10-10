import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import script
from voice_mod.common import atomic_json
from voice_mod.compatibility import patch_sources, profiles, select_build, source_digest
from voice_mod.pck import Pack, read_pack, write_pack


class CompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.old = {"scripts/chat.gdc": b"old chat", "scripts/menu.gdc": b"old menu"}
        self.new = {"scripts/chat.gdc": b"new chat", "scripts/menu.gdc": b"new menu"}
        self.sources = {"scripts/chat.gd": b"extends Node\nfunc run():\n\tpass\n"}
        self.manifest = {"engine": [4, 8, 0], "base_scripts": self.hashes(self.old),
                         "base_sources": {name: [source_digest(data)] for name, data in self.sources.items()},
                         "builds": [{"id": "windows-october-2026", "label": "current official export",
                                     "engine": [4, 8, 0], "base_scripts": self.hashes(self.new)}]}

    @staticmethod
    def hashes(files):
        return {name.removesuffix(".gdc") + ".gd": hashlib.sha256(data).hexdigest() for name, data in files.items()}

    def select(self, files, engine=(4, 8, 0)):
        return select_build(Pack(4, engine, files), self.manifest)

    def test_recognizes_whole_old_and_new_official_builds(self):
        self.assertEqual(self.select(self.old)["id"], "original-windows")
        self.assertEqual(self.select(self.new)["id"], "windows-october-2026")

    def test_refuses_mixed_builds(self):
        with self.assertRaisesRegex(ValueError, "not supported.*1/2 scripts"):
            self.select({"scripts/chat.gdc": self.new["scripts/chat.gdc"], "scripts/menu.gdc": self.old["scripts/menu.gdc"]})

    def test_refuses_missing_or_changed_scripts_with_recovery_details(self):
        for files in ({}, {**self.new, "scripts/chat.gdc": b"changed logic"}):
            with self.assertRaises(ValueError) as error:
                self.select(files)
            message = str(error.exception)
            self.assertIn("scripts/chat.gd", message)
            self.assertIn("No game files were changed", message)
            self.assertIn("download/version", message)
            self.assertNotIn(str(Path.home()), message)

    def test_checks_engine_even_when_scripts_match(self):
        with self.assertRaisesRegex(ValueError, "Godot 4.9.0"):
            self.select(self.new, (4, 9, 0))

    def test_accepts_reviewed_source_with_crlf_and_bom(self):
        files = {**self.old, **self.sources}
        files["scripts/chat.gd"] = b"\xef\xbb\xbf" + files["scripts/chat.gd"].replace(b"\n", b"\r\n")
        del files["scripts/chat.gdc"]
        self.assertEqual(self.select(files)["id"], "original-windows")

    def test_source_changes_are_not_hidden_by_unused_recognized_bytecode(self):
        with self.assertRaises(ValueError):
            self.select({**self.old, "scripts/chat.gd": b"extends Node\nfunc run():\n\tquit()\n"})

    def test_checks_remap_target_and_active_bytecode(self):
        files = {**self.old, "scripts/chat.gd": b"unused source",
                 "scripts/chat.gd.remap": b'[remap]\npath="res://scripts/chat.gdc"\n'}
        self.assertEqual(self.select(files)["id"], "original-windows")
        for remap in (b'path="res://scripts/unknown.gdc"\n', b"invalid", b"\xff",
                      b'[remap]\npath="res://scripts/chat.gdc"\npath="res://scripts/unknown.gdc"\n',
                      b'[other]\npath="res://scripts/chat.gdc"\n'):
            with self.assertRaises(ValueError):
                self.select({**files, "scripts/chat.gd.remap": remap})

    def test_applies_selected_override_and_uninstall_restores_that_build(self):
        from voice_mod.uninstall import uninstall_game
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "mod"
            game = root / "game"
            game.mkdir()
            for folder in (source / "game_patch/scripts", source / "voice_mod", source / "game_builds/windows-october-2026/scripts"):
                folder.mkdir(parents=True)
            (source / "game_patch/scripts/chat.gd").write_bytes(b"legacy patch")
            (source / "game_patch/scripts/menu.gd").write_bytes(b"common patch")
            (source / "game_builds/windows-october-2026/scripts/chat.gd").write_bytes(b"current patch")
            atomic_json(source / "game_patch/compatibility.json", self.manifest)
            pack = game / "PonyPonyParadise.pck"
            write_pack(pack, Pack(4, (4, 8, 0), self.new))
            original = pack.read_bytes()
            with patch.object(script, "ROOT", source):
                script.install_game(game, copy.deepcopy(script.DEFAULTS))
                patched = read_pack(pack)
                self.assertEqual(patched.files["scripts/chat.gd"], b"current patch")
                self.assertEqual(patched.files["scripts/menu.gd"], b"common patch")
                self.assertNotIn("scripts/chat.gdc", patched.files)
                self.assertFalse(any("game_builds" in name for name in patched.files))
                state = json.loads((game / "data/voice_mod/install_state.json").read_text())
                self.assertEqual(state["game_build"], "windows-october-2026")
                script.install_game(game, copy.deepcopy(script.DEFAULTS))
                uninstall_game(game, source)
            self.assertEqual(pack.read_bytes(), original)

    def test_unknown_build_does_not_create_backup_or_change_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, game = root / "mod", root / "game"
            (source / "game_patch").mkdir(parents=True)
            game.mkdir()
            atomic_json(source / "game_patch/compatibility.json", self.manifest)
            pack = game / "PonyPonyParadise.pck"
            write_pack(pack, Pack(4, (4, 8, 0), {**self.new, "scripts/chat.gdc": b"other mod"}))
            original = pack.read_bytes()
            with patch.object(script, "ROOT", source), self.assertRaises(ValueError):
                script.install_game(game, copy.deepcopy(script.DEFAULTS))
            self.assertEqual(pack.read_bytes(), original)
            self.assertEqual({path.name for path in game.iterdir()}, {pack.name})

    def test_missing_build_payload_does_not_stage_or_change_pack(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, game = root / "mod", root / "game"
            (source / "game_patch").mkdir(parents=True)
            game.mkdir()
            atomic_json(source / "game_patch/compatibility.json", self.manifest)
            pack = game / "PonyPonyParadise.pck"
            write_pack(pack, Pack(4, (4, 8, 0), self.new))
            original = pack.read_bytes()
            with patch.object(script, "ROOT", source), self.assertRaisesRegex(ValueError, "patches are missing"):
                script.install_game(game, copy.deepcopy(script.DEFAULTS))
            self.assertEqual(pack.read_bytes(), original)
            self.assertEqual({path.name for path in game.iterdir()}, {pack.name})

    def test_variant_id_cannot_escape_payload(self):
        self.manifest["builds"][0]["id"] = "../../elsewhere"
        with self.assertRaisesRegex(ValueError, "Invalid game compatibility profile"):
            self.select(self.new)

    def test_every_shipped_override_has_a_verified_original(self):
        root = script.ROOT
        manifest = json.loads((root / "game_patch/compatibility.json").read_text(encoding="utf-8"))
        for profile in profiles(manifest):
            for name, digest in profile["base_scripts"].items():
                self.assertRegex(digest, r"^[a-f0-9]{64}$")
                self.assertEqual(len(profile["base_sources"][name]), 1)
            patches = patch_sources(root, profile)
            self.assertIn("scripts/voice_mod/voice_controller.gd", patches)
            if profile["id"] != "original-windows":
                for path in (root / "game_builds" / profile["id"]).rglob("*.gd"):
                    self.assertIn(path.relative_to(root / "game_builds" / profile["id"]).as_posix(), profile["base_scripts"])
                    self.assertNotIn(b"<<<<<<<", path.read_bytes())


if __name__ == "__main__":
    unittest.main()
