import copy
import hashlib
import json
import os
import tempfile
import stat
from types import SimpleNamespace
import unittest
from pathlib import Path
from unittest.mock import patch

import script
from voice_mod.common import atomic_json, line_id
from voice_mod.pck import Pack, write_pack
from voice_mod.uninstall import uninstall_game


class UninstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.private_state = patch.dict(os.environ, {"PONY_VOICE_STATE_DIR": str(self.root / "private")})
        self.private_state.start()
        self.source = self.root / "source"
        self.game = self.root / "selected game"
        (self.source / "game_patch/scripts").mkdir(parents=True)
        (self.source / "voice_mod").mkdir()
        (self.source / "voice_mod/__init__.py").write_text("")
        (self.source / "voice_mod/worker.py").write_text("# worker fixture\n")
        (self.source / "game_patch/scripts/example.gd").write_text("extends Node\n")
        atomic_json(self.source / "game_patch/compatibility.json", {"base_scripts": {
            "scripts/example.gd": hashlib.sha256(b"compiled fixture").hexdigest()}})
        self.game.mkdir()
        self.pack = self.game / "PonyPonyParadise.pck"
        write_pack(self.pack, Pack(4, (4, 8, 0), {"scripts/example.gdc": b"compiled fixture", "project.binary": b"project"}))
        self.original_pack = self.pack.read_bytes()
        self.key = line_id("en", "celestia", "Hello.")
        asset = self.source / "data/voices/en" / (self.key + ".mp3")
        asset.parent.mkdir(parents=True)
        asset.write_bytes(b"ID3 mod fixture")
        atomic_json(self.source / "data/voices/opening_manifest.json", {"lines": [{
            "id": self.key, "speaker": "celestia", "language": "en", "text": "Hello.",
            "file": "en/" + asset.name, "sha256": hashlib.sha256(asset.read_bytes()).hexdigest()}]})
        self.preexisting = self.game / "data/voices/en" / asset.name
        self.preexisting.parent.mkdir(parents=True)
        self.preexisting.write_bytes(b"preexisting recording")
        self.save = self.game / "saves/slot.json"
        self.save.parent.mkdir()
        self.save.write_bytes(b"player save")
        self.unknown = self.game / "data/voice_mod/notes.txt"
        self.unknown.parent.mkdir()
        self.unknown.write_bytes(b"keep these notes")
        self.config = copy.deepcopy(script.DEFAULTS)
        with patch.object(script, "ROOT", self.source):
            script.install_game(self.game, self.config)

    def tearDown(self):
        self.private_state.stop()
        self.temporary.cleanup()

    def state(self):
        return self.game / "data/voice_mod/install_state.json"

    def uninstall(self):
        return uninstall_game(self.game, self.source)

    def test_restores_original_assets_removes_owned_cache_and_can_reinstall(self):
        generated = line_id("en", "celestia", "A generated reply.")
        cached = self.game / "data/voices/en" / (generated + ".mp3")
        cached.write_bytes(b"generated cache")
        atomic_json(self.game / "data/voice_mod/dialogue_manifest.json", {"lines": [{
            "id": generated, "language": "en", "speaker": "celestia", "text": "A generated reply."}]})
        runtime = self.game / "data/voice_mod/runtime/session_123_456"
        runtime.mkdir(parents=True)
        (runtime / "heartbeat").touch()
        (runtime / ("job_" + generated + ".json")).write_text("{}")
        (runtime / "important.txt").write_text("keep this")
        result = self.uninstall()
        self.assertEqual(self.pack.read_bytes(), self.original_pack)
        self.assertEqual(self.preexisting.read_bytes(), b"preexisting recording")
        self.assertFalse(cached.exists())
        self.assertFalse((runtime / "heartbeat").exists())
        preserved = Path(result["recovery_directory"]) / "data/voice_mod"
        self.assertTrue((preserved / "runtime/session_123_456/important.txt").is_file())
        self.assertEqual(self.save.read_bytes(), b"player save")
        self.assertEqual((preserved / "notes.txt").read_bytes(), b"keep these notes")
        self.assertGreater(result["removed"], 0)
        self.assertFalse((self.game / "data/voice_mod").exists())
        self.assertFalse((self.game / "PonyPonyParadise.pck.voice-mod-original").exists())
        with patch.object(script, "ROOT", self.source):
            script.install_game(self.game, self.config)
        self.assertNotEqual(self.pack.read_bytes(), self.original_pack)
        self.assertEqual(self.uninstall()["restored"], 1)

    def test_modified_game_backup_or_resource_metadata_refused_before_changes(self):
        for failure in ("game", "backup", "path", "original resource"):
            with self.subTest(failure=failure):
                pack = self.pack.read_bytes()
                backup = self.game / "PonyPonyParadise.pck.voice-mod-original"
                backup_bytes = backup.read_bytes()
                state_bytes = self.state().read_bytes()
                state = json.loads(state_bytes)
                if failure == "game":
                    self.pack.write_bytes(pack + b"changed")
                elif failure == "backup":
                    backup.write_bytes(backup_bytes + b"changed")
                elif failure == "path":
                    state["owned_files"]["data/voices/../../saves/slot.json"] = hashlib.sha256(self.save.read_bytes()).hexdigest()
                    atomic_json(self.state(), state)
                else:
                    state["original_files"]["data/voices/en/" + self.preexisting.name] = "0" * 64
                    atomic_json(self.state(), state)
                before = {str(path): path.read_bytes() for path in self.game.rglob("*") if path.is_file()}
                with self.assertRaises(ValueError):
                    self.uninstall()
                self.assertEqual(before, {str(path): path.read_bytes() for path in self.game.rglob("*") if path.is_file()})
                self.pack.write_bytes(pack)
                backup.write_bytes(backup_bytes)
                self.state().write_bytes(state_bytes)

    def test_user_edits_and_unknown_audio_are_preserved(self):
        worker = self.game / "data/voice_mod/voice_mod/worker.py"
        worker.write_text("# user changes\n")
        audio = self.game / "data/voices/en/personal-recording.wav"
        audio.write_bytes(b"unrelated audio")
        result = self.uninstall()
        self.assertGreater(result["retained"], 0)
        self.assertEqual((Path(result["recovery_directory"]) / "data/voice_mod/voice_mod/worker.py").read_text(), "# user changes\n")
        self.assertEqual(audio.read_bytes(), b"unrelated audio")

    def test_locked_file_cleanup_can_be_retried_with_original_resources_intact(self):
        worker = self.game / "data/voice_mod/voice_mod/worker.py"
        original_unlink = Path.unlink
        def locked(path, *args, **kwargs):
            if path == worker:
                raise PermissionError("File locked by another program")
            return original_unlink(path, *args, **kwargs)
        with patch.object(Path, "unlink", locked):
            with self.assertRaisesRegex(RuntimeError, "click Uninstall voice mod again"):
                self.uninstall()
        state = json.loads(self.state().read_text())
        self.assertEqual(state["status"], "cleanup_pending")
        self.assertEqual(self.pack.read_bytes(), self.original_pack)
        self.assertTrue(state["original_files"])
        self.uninstall()
        self.assertFalse(worker.exists())
        self.assertEqual(self.preexisting.read_bytes(), b"preexisting recording")
        self.assertEqual(self.save.read_bytes(), b"player save")
        self.assertFalse((self.game / "data/voice_mod").exists())
        self.assertFalse((self.game / "PonyPonyParadise.pck.voice-mod-original").exists())

    def test_legacy_installation_without_resource_receipt_can_be_removed(self):
        state = json.loads(self.state().read_text())
        # Original-assets recovery was added with receipts; legacy installs have
        # only the verified PCK and the mod's base-asset index.
        state.pop("owned_files")
        state.pop("original_files")
        atomic_json(self.state(), state)
        result = self.uninstall()
        self.assertEqual(self.pack.read_bytes(), self.original_pack)
        self.assertFalse((self.game / "data/voice_mod/voice_mod/worker.py").exists())
        self.assertTrue((Path(result["recovery_directory"]) / "data/voice_mod/notes.txt").exists())

    def test_clean_uninstall_removes_backup_and_entire_mod_folder(self):
        self.unknown.unlink()
        self.uninstall()
        self.assertFalse((self.game / "data/voice_mod").exists())
        self.assertFalse((self.game / "PonyPonyParadise.pck.voice-mod-original").exists())
        self.assertEqual(self.pack.read_bytes(), self.original_pack)
        self.assertEqual(self.save.read_bytes(), b"player save")

    def test_old_inactive_receipt_and_backup_are_cleaned(self):
        state = json.loads(self.state().read_text())
        self.pack.write_bytes(self.original_pack)
        state.update(status="uninstalled", installed_sha256=state["original_sha256"], owned_files={}, original_files={})
        atomic_json(self.state(), state)
        self.uninstall()
        self.assertFalse((self.game / "data/voice_mod").exists())
        self.assertFalse((self.game / "PonyPonyParadise.pck.voice-mod-original").exists())

    def test_locked_backup_keeps_cleanup_retryable(self):
        backup = self.game / "PonyPonyParadise.pck.voice-mod-original"
        original_unlink = Path.unlink
        def locked(path, *args, **kwargs):
            if path == backup:
                raise PermissionError("Backup locked")
            return original_unlink(path, *args, **kwargs)
        with patch.object(Path, "unlink", locked):
            with self.assertRaisesRegex(RuntimeError, "click Uninstall voice mod again"):
                self.uninstall()
        self.assertEqual(json.loads(self.state().read_text())["status"], "cleanup_pending")
        self.uninstall()
        self.assertFalse(backup.exists())
        self.assertFalse((self.game / "data/voice_mod").exists())
        self.assertEqual(self.preexisting.read_bytes(), b"preexisting recording")

    def test_locked_receipt_can_be_retried_after_backup_is_removed(self):
        original_unlink = Path.unlink
        def locked(path, *args, **kwargs):
            if path == self.state():
                raise PermissionError("Receipt locked")
            return original_unlink(path, *args, **kwargs)
        with patch.object(Path, "unlink", locked):
            with self.assertRaisesRegex(RuntimeError, "click Uninstall voice mod again"):
                self.uninstall()
        self.assertFalse((self.game / "PonyPonyParadise.pck.voice-mod-original").exists())
        self.uninstall()
        self.assertFalse((self.game / "data/voice_mod").exists())
        self.assertEqual(self.preexisting.read_bytes(), b"preexisting recording")

    def test_linked_mod_folder_is_refused(self):
        outside = self.root / "external"
        outside.mkdir()
        link = self.game / "data/voice_mod/runtime"
        try:
            link.symlink_to(outside, target_is_directory=True)
        except OSError:
            self.skipTest("OS does not allow unprivileged directory symlinks")
        before = self.pack.read_bytes()
        with self.assertRaisesRegex(ValueError, "Linked"):
            self.uninstall()
        self.assertEqual(self.pack.read_bytes(), before)

    def test_windows_reparse_attribute_is_refused_before_any_write(self):
        runtime = self.game / "data/voice_mod/runtime"
        runtime.mkdir()
        original = Path.lstat
        def metadata(path, *args, **kwargs):
            info = original(path, *args, **kwargs)
            if path == runtime:
                return SimpleNamespace(st_mode=info.st_mode, st_file_attributes=stat.FILE_ATTRIBUTE_REPARSE_POINT)
            return info
        before = self.pack.read_bytes()
        with patch.object(Path, "lstat", metadata):
            with self.assertRaisesRegex(ValueError, "Linked"):
                self.uninstall()
        self.assertEqual(self.pack.read_bytes(), before)

    def test_zip_assets_already_matching_bundle_are_removed_on_uninstall(self):
        self.uninstall()
        self.preexisting.write_bytes((self.source / "data/voices/en" / self.preexisting.name).read_bytes())
        with patch.object(script, "ROOT", self.source):
            script.install_game(self.game, self.config)
        self.uninstall()
        self.assertFalse(self.preexisting.exists())

    def bundled_character(self):
        root = self.source / "character_assets/buttonmash"
        (root / "sprites").mkdir(parents=True)
        atomic_json(root / "character.json", {"tag": "buttonmash", "name": "Button Mash"})
        (root / "sprites/neutral.png").write_bytes(b"PNG character fixture")
        return root

    def test_button_mash_is_installed_once_and_owned_files_can_be_uninstalled(self):
        source = self.bundled_character()
        with patch.object(script, "ROOT", self.source):
            script.install_game(self.game, self.config)
        target = self.game / "data/characters/custom/buttonmash"
        self.assertEqual((target / "character.json").read_bytes(), (source / "character.json").read_bytes())
        with patch.object(script, "ROOT", self.source):
            script.install_game(self.game, self.config)
        self.assertEqual((target / "sprites/neutral.png").read_bytes(), b"PNG character fixture")
        self.uninstall()
        self.assertFalse(target.exists())
        self.assertEqual(self.save.read_bytes(), b"player save")

    def test_existing_button_mash_under_another_folder_is_never_overwritten(self):
        self.bundled_character()
        existing = self.game / "data/characters/custom/my_button_mash"
        existing.mkdir(parents=True)
        atomic_json(existing / "character.json", {"tag": "buttonmash", "name": "My Button Mash"})
        before = (existing / "character.json").read_bytes()
        with patch.object(script, "ROOT", self.source):
            script.install_game(self.game, self.config)
        self.assertFalse((self.game / "data/characters/custom/buttonmash").exists())
        self.assertEqual((existing / "character.json").read_bytes(), before)
        self.uninstall()
        self.assertEqual((existing / "character.json").read_bytes(), before)

    def test_editing_bundled_button_mash_preserves_the_complete_character_on_uninstall(self):
        self.bundled_character()
        with patch.object(script, "ROOT", self.source):
            script.install_game(self.game, self.config)
        target = self.game / "data/characters/custom/buttonmash"
        atomic_json(target / "character.json", {"tag": "buttonmash", "name": "My edited Button Mash"})
        self.uninstall()
        self.assertTrue((target / "sprites/neutral.png").is_file())
        self.assertEqual(json.loads((target / "character.json").read_text())["name"], "My edited Button Mash")
