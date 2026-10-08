import io
import stat
import tempfile
import unittest
import zipfile
from pathlib import Path

import script
from voice_mod.archive import extract_source


class ArchiveSecurityTests(unittest.TestCase):
    def test_unsafe_archive_is_rejected_before_any_file_is_written(self):
        for name in ("source/../escape.py", "source//absolute/../../escape", "source/drive:C", "source\\escape", "/absolute", "other/escape.py"):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                data = io.BytesIO()
                with zipfile.ZipFile(data, "w") as archive:
                    archive.writestr("source/valid.py", "fixture")
                    item = zipfile.ZipInfo("placeholder")
                    item.filename = name
                    archive.writestr(item, "unsafe fixture")
                folder = Path(temporary) / "engine"
                with zipfile.ZipFile(data) as archive, self.assertRaises(ValueError):
                    extract_source(archive, folder)
                self.assertFalse(folder.exists())

    def test_symlink_archive_entry_is_refused(self):
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as archive:
            item = zipfile.ZipInfo("source/link")
            item.create_system = 3
            item.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(item, "../outside")
        with tempfile.TemporaryDirectory() as temporary, zipfile.ZipFile(data) as archive:
            with self.assertRaises(ValueError):
                extract_source(archive, Path(temporary) / "engine")

    def test_linked_game_pack_is_refused_before_reading_or_writing(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = root / "original.pck"
            original.write_bytes(b"preserve this")
            game = root / "game"
            game.mkdir()
            try:
                (game / "PonyPonyParadise.pck").symlink_to(original)
            except OSError:
                self.skipTest("Creating a file symlink is unavailable")
            with self.assertRaisesRegex(ValueError, "Linked game packs"):
                script.install_game(game, script.DEFAULTS)
            self.assertEqual(original.read_bytes(), b"preserve this")
            self.assertFalse((game / "PonyPonyParadise.pck.voice-mod-original").exists())
