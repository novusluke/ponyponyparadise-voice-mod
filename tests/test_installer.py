"""Installer regressions: broken venvs, native browsing and private state."""
import copy
import io
import json
import os
import ssl
import subprocess
import tempfile
import time
import unittest
import urllib.error
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

import script
from voice_mod import installer_service as service
from voice_mod.settings import preferences_path


class DownloadTests(unittest.TestCase):
    def test_verified_download_does_not_create_a_fallback_context(self):
        with patch.object(script.urllib.request, "urlopen", return_value=io.BytesIO(b"download")) as open_url, \
             patch.object(script.ssl, "_create_unverified_context") as fallback:
            self.assertEqual(script.download("https://example.com/download"), b"download")
        self.assertEqual(open_url.call_count, 1)
        self.assertNotIn("context", open_url.call_args.kwargs)
        fallback.assert_not_called()

    def test_certificate_failure_retries_the_same_request_once(self):
        error = urllib.error.URLError(ssl.SSLCertVerificationError(1, "CERTIFICATE_VERIFY_FAILED"))
        log = Mock()
        default_context = ssl._create_default_https_context
        with patch.object(script.urllib.request, "urlopen", side_effect=[error, io.BytesIO(b"download")]) as open_url:
            self.assertEqual(script.download("https://example.com/download", log=log), b"download")
        first, retry = open_url.call_args_list
        self.assertIs(first.args[0], retry.args[0])
        self.assertEqual(first.kwargs, {"timeout": 60})
        self.assertEqual(retry.kwargs["timeout"], 60)
        self.assertEqual(retry.kwargs["context"].verify_mode, ssl.CERT_REQUIRED)
        self.assertTrue(retry.kwargs["context"].check_hostname)
        self.assertIs(ssl._create_default_https_context, default_context)
        log.assert_called_once()

    def test_direct_and_wrapped_ssl_verification_errors_retry(self):
        generic = ssl.SSLError(1, "certificate failure")
        generic.reason = "CERTIFICATE_VERIFY_FAILED"
        for error in (ssl.SSLCertVerificationError(1, "certificate failure"), urllib.error.URLError(generic)):
            with self.subTest(error=error), \
                 patch.object(script.urllib.request, "urlopen", side_effect=[error, io.BytesIO(b"download")]) as open_url:
                self.assertEqual(script.download("https://example.com/download", log=Mock()), b"download")
                self.assertEqual(open_url.call_count, 2)

    def test_other_network_errors_are_not_retried(self):
        errors = (urllib.error.URLError("CERTIFICATE_VERIFY_FAILED"), urllib.error.URLError("DNS lookup failed"),
                  urllib.error.HTTPError("https://example.com", 404, "Not found", {}, None),
                  ssl.SSLError(1, "TLS protocol failure"), TimeoutError("download timed out"))
        for error in errors:
            with self.subTest(error=error), \
                 patch.object(script.urllib.request, "urlopen", side_effect=error) as open_url, \
                 patch.object(script.ssl, "_create_unverified_context") as fallback:
                with self.assertRaises(type(error)) as caught:
                    script.download("https://example.com/download")
                self.assertIs(caught.exception, error)
                self.assertEqual(open_url.call_count, 1)
                fallback.assert_not_called()

    def test_failed_fallback_propagates_without_another_retry(self):
        certificate = urllib.error.URLError(ssl.SSLCertVerificationError(1, "certificate failure"))
        failure = urllib.error.URLError("connection refused")
        with patch.object(script.urllib.request, "urlopen", side_effect=[certificate, failure]) as open_url:
            with self.assertRaises(urllib.error.URLError) as caught:
                script.download("https://example.com/download", log=Mock())
        self.assertIs(caught.exception, failure)
        self.assertEqual(open_url.call_count, 2)

    def test_untrusted_certificate_is_never_accepted(self):
        error = urllib.error.URLError(ssl.SSLCertVerificationError(1, "untrusted certificate"))
        with patch.object(script.urllib.request, "urlopen", side_effect=error) as open_url, \
             patch.object(script.ssl, "_create_unverified_context") as unsafe:
            with self.assertRaises(urllib.error.URLError):
                script.download("https://example.com/download", log=Mock())
        self.assertEqual(open_url.call_count, 2)
        unsafe.assert_not_called()

    def test_plain_http_download_is_refused(self):
        with patch.object(script.urllib.request, "urlopen") as open_url:
            with self.assertRaises(ValueError):
                script.download("http://example.com/download")
        open_url.assert_not_called()


class InstallerServiceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name).resolve()
        self.state = patch.dict(os.environ, {"PONY_VOICE_STATE_DIR": str(self.root / "private")})
        self.state.start()
        self.folder = self.root / "folder with spaces/venv"
        (self.folder / "Scripts").mkdir(parents=True)
        self.python = self.folder / "Scripts/python.exe"
        self.python.touch()

    def tearDown(self):
        self.state.stop()
        self.temporary.cleanup()

    def test_broken_moved_venv_gives_recovery_message(self):
        result = subprocess.CompletedProcess([], 103, "", 'No Python at missing-base-interpreter')
        with patch.object(service, "command_result", return_value=result):
            detected = service.inspect_environment(self.folder)
        self.assertFalse(detected["ok"])
        self.assertEqual(detected["kind"], "broken")
        self.assertIn("Repair", detected["message"])
        self.assertNotIn("missing-base-interpreter", detected["message"])

    def test_select_venv_or_parent_folder_with_spaces(self):
        info = {"python": "3.11.8", "omnivoice": True, "loaded": True, "cuda": True, "encoder": True}
        with patch.object(service, "command_result", return_value=subprocess.CompletedProcess([], 0, json.dumps(info), "")) as probe:
            for folder in (self.folder, self.folder.parent, self.python, self.python.parent):
                self.assertTrue(service.inspect_environment(folder)["ok"])
                self.assertEqual(probe.call_args.args[0][0], str(self.python))
                self.assertIn("-I", probe.call_args.args[0])

    def test_package_presence_without_loadable_dependencies_is_not_ready(self):
        info = {"python": "3.11.8", "omnivoice": True, "loaded": False, "encoder": True}
        with patch.object(service, "command_result", return_value=subprocess.CompletedProcess([], 0, json.dumps(info), "")):
            detected = service.inspect_environment(self.folder)
        self.assertFalse(detected["ok"])
        self.assertIn("dependencies cannot load", detected["message"])

    def test_arbitrary_selected_file_is_not_executed(self):
        selected = self.root / "unrelated.exe"
        selected.write_bytes(b"fixture")
        with patch.object(service, "command_result") as probe:
            self.assertFalse(service.inspect_environment(selected)["ok"])
        probe.assert_not_called()

    def test_timeout_and_missing_package_do_not_crash(self):
        with patch.object(service, "command_result", side_effect=subprocess.TimeoutExpired("python", 20)):
            self.assertFalse(service.inspect_environment(self.folder)["ok"])
        with patch.object(service, "command_result", return_value=subprocess.CompletedProcess([], 0, '{"python":"3.11","omnivoice":false}', "")):
            self.assertIn("not installed", service.inspect_environment(self.folder)["message"])

    def test_repair_requires_matching_version_and_restores_original_on_failure(self):
        cfg = self.folder / "pyvenv.cfg"
        original = b"home = missing-runtime\nversion = 3.11.8\n"
        cfg.write_bytes(original)
        ready = {"ok": True, "python": "3.11.16", "encoder": True, "python_path": str(self.python)}
        broken = {"ok": False, "repairable": True}
        base = self.root / "managed/python.exe"
        found = subprocess.CompletedProcess([], 0, str(base), "")
        info = subprocess.CompletedProcess([], 0, '{"minor":"3.11","version":"3.11.16"}', "")
        with patch.object(service, "inspect_environment", side_effect=[broken, ready]), \
             patch.object(service, "ensure_uv", return_value=Path("uv.exe")), \
             patch.object(service.subprocess, "run", return_value=found), \
             patch.object(service, "command_result", return_value=info), \
             patch.object(service, "windows_architecture", return_value=0x8664), \
             patch.object(service, "prepare_existing", side_effect=ValueError("dependency failed")):
            with self.assertRaisesRegex(ValueError, "dependency failed"):
                service.repair_environment(self.folder, lambda _: None)
        self.assertEqual(cfg.read_bytes(), original)
        self.assertEqual(self.python.read_bytes(), b"")
        self.assertEqual(len(list((self.root / "private/environment-repairs").rglob("*.original"))), 1)

    def test_repair_refuses_incompatible_architecture_without_writing_config(self):
        cfg = self.folder / "pyvenv.cfg"
        original = b"home = missing-runtime\nversion = 3.11.8\n"
        cfg.write_bytes(original)
        with patch.object(service, "inspect_environment", return_value={"ok":False,"repairable":True}), \
             patch.object(service, "ensure_uv", return_value=Path("uv.exe")), \
             patch.object(service.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "managed/python.exe", "")), \
             patch.object(service, "command_result", return_value=subprocess.CompletedProcess([], 0, '{"minor":"3.11","version":"3.11.16"}', "")), \
             patch.object(service, "windows_architecture", side_effect=[0x8664, 0x14c]):
            with self.assertRaisesRegex(ValueError, "architecture differs"):
                service.repair_environment(self.folder, lambda _: None)
        self.assertEqual(cfg.read_bytes(), original)

    def test_matching_python_repair_keeps_packages_and_private_backup(self):
        cfg = self.folder / "pyvenv.cfg"
        original = b"home = missing-runtime\nversion = 3.11.8\n"
        cfg.write_bytes(original)
        ready = {"ok":True,"python":"3.11.16","encoder":True,"python_path":str(self.python)}
        with patch.object(service, "inspect_environment", side_effect=[{"ok":False,"repairable":True},ready.copy(),ready.copy()]), \
             patch.object(service, "ensure_uv", return_value=Path("uv.exe")), \
             patch.object(service.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "managed/python.exe", "")), \
             patch.object(service, "command_result", return_value=subprocess.CompletedProcess([], 0, '{"minor":"3.11","version":"3.11.16"}', "")), \
             patch.object(service, "windows_architecture", return_value=0x8664), \
             patch.object(service, "prepare_existing") as verify:
            result = service.repair_environment(self.folder, lambda _: None)
        self.assertTrue(result["ok"])
        verify.assert_called_once_with(self.python, unittest.mock.ANY)
        self.assertEqual(service.venv_version(cfg), "3.11")
        self.assertNotIn("missing-runtime", cfg.read_text())
        self.assertEqual(self.python.read_bytes(), b"")
        backup = next((self.root / "private/environment-repairs").rglob("*.original"))
        self.assertEqual(backup.read_bytes(), original)

    def test_preferences_never_change_public_template(self):
        template = script.ROOT / "config.json"
        before = template.read_bytes()
        config = copy.deepcopy(script.DEFAULTS)
        config["omnivoice"]["python_path"] = str(self.python)
        service.save_preferences(config)
        self.assertEqual(template.read_bytes(), before)
        self.assertEqual(service.load_preferences()["omnivoice"]["python_path"], str(self.python))
        self.assertTrue(preferences_path().is_relative_to(self.root))

    def test_fresh_install_preserves_existing_folder(self):
        before = self.python.read_bytes()
        with patch.object(script, "download") as download:
            with self.assertRaisesRegex(ValueError, "empty folder"):
                service.install_local(self.folder, script.DEFAULTS["omnivoice"], lambda _: None)
            download.assert_not_called()
        self.assertEqual(self.python.read_bytes(), before)

    def test_download_location_preserves_existing_files_and_installations(self):
        downloads = self.root / "Downloads"
        downloads.mkdir()
        (downloads / "personal.txt").write_text("keep")
        existing = downloads / "OmniVoice"
        existing.mkdir()
        (existing / "important.txt").write_text("keep existing engine")
        target = service.new_installation_folder(downloads)
        self.assertEqual(target, downloads / "OmniVoice-2")
        self.assertEqual((downloads / "personal.txt").read_text(), "keep")
        self.assertEqual((existing / "important.txt").read_text(), "keep existing engine")

    def test_fresh_install_downloads_source_and_creates_managed_python(self):
        import io
        import zipfile
        content = io.BytesIO()
        with zipfile.ZipFile(content, "w") as archive:
            archive.writestr("OmniVoice-source/pyproject.toml", "[project]\nname='omnivoice'\n")
        target = service.new_installation_folder(self.root)
        ready = {"ok": True, "python_path": str(target / ".venv/Scripts/python.exe"), "message": "OmniVoice ready"}
        with patch.object(script, "download", return_value=content.getvalue()) as download, \
             patch.object(service, "ensure_uv", return_value=self.root / "uv.exe"), \
             patch.object(service, "run_logged") as run, \
             patch.object(service, "inspect_environment", return_value=ready):
            self.assertEqual(service.install_local(target, script.DEFAULTS["omnivoice"], lambda _: None), ready)
        self.assertTrue((target / "pyproject.toml").is_file())
        self.assertIn(script.DEFAULTS["omnivoice"]["revision"], download.call_args.args[0])
        self.assertIn("--managed-python", run.call_args_list[0].args[0])
        self.assertEqual(len(run.call_args_list), 3)

    def test_environment_manager_checksum_is_required_after_ssl_fallback(self):
        error = urllib.error.URLError(ssl.SSLCertVerificationError(1, "certificate failure"))
        with patch.object(script.urllib.request, "urlopen", side_effect=[error, io.BytesIO(b"invalid archive")]) as open_url:
            with self.assertRaisesRegex(ValueError, "checksum"):
                service.ensure_uv(Mock())
        self.assertEqual(open_url.call_count, 2)
        self.assertFalse((self.root / "private/tools/uv.exe").exists())

    def test_releases_new_current_and_unpublished(self):
        response = {"tag_name": "v1.2.0", "assets": [{"name": "PonyPonyParadiseVoiceSetup.exe",
                     "browser_download_url": "https://github.com/owner/repo/releases/download/v1.2.0/PonyPonyParadiseVoiceSetup.exe"}]}
        with patch.object(script, "download", return_value=json.dumps(response).encode()):
            self.assertEqual(service.check_updates("owner/repo", "1.1.0")["kind"], "available")
            self.assertEqual(service.check_updates("owner/repo", "1.2.0")["kind"], "current")
            self.assertTrue(service.check_updates("owner/repo", "1.1.0")["download"])
        error = urllib.error.HTTPError("https://api.github.com", 404, "Not found", {}, None)
        with patch.object(script, "download", side_effect=error):
            self.assertEqual(service.check_updates("owner/repo", "1.1.0")["kind"], "unpublished")

    def test_private_data_cannot_be_written_inside_public_repo(self):
        with self.assertRaisesRegex(ValueError, "outside the public"):
            service.require_private_destination(script.ROOT / "personal-environment")
        with patch.object(service, "public_repository_directory", return_value=None):
            service.require_private_destination(self.root)

    def test_uninstall_requires_game_to_be_closed_before_modification(self):
        with patch.object(service, "os", SimpleNamespace(name="nt")), \
             patch.object(service, "command_result", return_value=subprocess.CompletedProcess([], 0, '"PonyPonyParadise.exe","1234"\n', "")), \
             patch("voice_mod.uninstall.uninstall_game") as remove:
            with self.assertRaisesRegex(ValueError, "Close PonyPonyParadise"):
                service.uninstall_voices(self.root / "game", lambda _: None)
            remove.assert_not_called()

    def test_frozen_setup_allows_full_repository_zip_extracted_into_game(self):
        game = self.root / "game"
        game.mkdir()
        (game / "PonyPonyParadise.pck").write_bytes(b"game fixture")
        (game / "script.py").write_text("# public source", encoding="utf-8")
        (game / "game_patch").mkdir()
        with patch.object(service, "application_directory", return_value=game), \
             patch.object(service.sys, "frozen", True, create=True):
            service.require_private_destination(game)

    def test_remote_assets_override_older_bundled_voice(self):
        root = self.root / "bundle"
        (root / "reference_audios/en").mkdir(parents=True)
        (root / "reference_audios/en/spike.mp3").write_bytes(b"old bundled voice")
        content = b"updated voice"
        entry = [{"type": "file", "name": "spike.mp3", "sha": script.git_blob_sha(content),
                  "download_url": "https://raw.githubusercontent.com/owner/repo/main/reference_audios/en/spike.mp3"}]
        def download(url):
            if "raw.githubusercontent" in url:
                return content
            return json.dumps(entry if "/en?" in url else [{"type": "dir", "name": "en"}]).encode()
        config = copy.deepcopy(script.DEFAULTS)
        config["github_repository"] = "owner/repo"
        with patch.object(script, "ROOT", root), patch.object(script, "download", side_effect=download):
            script.sync_references(config, self.root / "cache")
        self.assertEqual((self.root / "cache/en/spike.mp3").read_bytes(), content)
        self.assertEqual((root / "reference_audios/en/spike.mp3").read_bytes(), b"old bundled voice")


try:
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6.QtWidgets import QApplication, QFileDialog
    from installer import Installer
    HAVE_QT = True
except ImportError:
    HAVE_QT = False


@unittest.skipUnless(HAVE_QT, "GUI checks require requirements-installer.txt")
class InstallerGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self):
        self.window = Installer(preview=True)
        self.window.show()
        self.app.processEvents()

    def tearDown(self):
        if self.window.job:
            self.window.job.wait(3000)
            self.app.processEvents()
        self.window.close()
        self.window.deleteLater()
        self.app.processEvents()

    def finish(self):
        deadline = time.monotonic() + 4
        while self.window.job and self.window.job.isRunning() and time.monotonic() < deadline:
            self.app.processEvents()
            time.sleep(.01)
        self.app.processEvents()
        self.assertFalse(self.window.job.isRunning())

    def test_native_browse_keeps_window_open_for_broken_venv(self):
        broken = {"ok": False, "kind": "broken", "message": "The base Python is missing. Choose a new folder."}
        with patch.object(QFileDialog, "getExistingDirectory", return_value="chosen folder/venv") as dialog, \
             patch.object(service, "inspect_environment", return_value=broken):
            self.window.browse_omni.click()
            self.finish()
        dialog.assert_called_once()
        self.assertEqual(len(dialog.call_args.args), 3)  # native default, no DontUseNativeDialog
        self.assertTrue(self.window.isVisible())
        self.assertIn("base Python", self.window.status.text())
        self.assertTrue(self.window.controls.isEnabled())

    def test_detect_searches_when_default_install_folder_is_missing(self):
        detected = {"ok": True, "kind": "ready", "python_path": str(Path("detected/.venv/Scripts/python.exe").resolve()),
                    "message": "OmniVoice detected"}
        self.window.omni_folder.setText("uninstalled-default-folder")
        with patch.object(service, "detect_environment", return_value=detected) as discover:
            self.window.detect_button.click()
            self.finish()
        discover.assert_called_once()
        self.assertTrue(self.window.environment["ok"])
        self.assertNotEqual(self.window.config["omnivoice"]["install_path"], "uninstalled-default-folder")

    def test_download_button_installs_into_child_of_selected_location(self):
        with tempfile.TemporaryDirectory() as temporary:
            parent = Path(temporary).resolve()
            (parent / "existing-download.txt").write_text("keep")
            target = parent / "OmniVoice"
            ready = {"ok": True, "python_path": str(target / ".venv/Scripts/python.exe"), "message": "OmniVoice ready"}
            def installed(folder, options, log):
                folder.mkdir()
                return ready
            with patch.object(QFileDialog, "getExistingDirectory", return_value=str(parent)), \
                 patch.object(service, "install_local", side_effect=installed) as install, \
                 patch.object(service, "inspect_environment") as detect:
                self.window.install_button.click()
                self.finish()
            self.assertEqual(install.call_args.args[0], target)
            detect.assert_not_called()
            self.assertEqual(self.window.omni_folder.text(), str(target))
            self.assertEqual(self.window.config["omnivoice"]["python_path"], ready["python_path"])
            self.assertTrue(self.window.environment["ok"])
            self.assertTrue(self.window.log.isVisible())
            self.assertEqual((parent / "existing-download.txt").read_text(), "keep")

    def test_cancelling_download_location_starts_no_installation(self):
        with patch.object(QFileDialog, "getExistingDirectory", return_value=""), \
             patch.object(service, "install_local") as install:
            self.window.install_button.click()
        install.assert_not_called()
        self.assertIsNone(self.window.job)

    def test_local_mode_needs_a_working_environment(self):
        self.window.game_folder.setText(str(Path(__file__).parent))
        self.window.apply()
        self.assertFalse(hasattr(self.window, "pages"))
        self.assertIn("game folder", self.window.status.text())

    def test_detection_finishes_without_an_idle_progress_line(self):
        result = {"ok": True, "python_path": "python.exe", "message": "OmniVoice detected Python 3.11"}
        with patch.object(service, "detect_environment", return_value=result):
            self.window.detect()
            self.finish()
        self.assertFalse(self.window.progress.isVisible())
        from PySide6.QtWidgets import QPushButton
        texts = [item.text() for item in self.window.findChildren(QPushButton)]
        self.assertNotIn("Continue to apply voices  →", texts)
        self.assertIn("Apply voices", texts)

    def test_release_buttons_use_embedded_repository(self):
        self.window.config["github_repository"] = "old-owner/old-repository"
        with patch.object(service, "check_updates", return_value={"kind": "current", "message": "Up to date."}) as check:
            self.window.check_button.click()
            self.finish()
        check.assert_called_once_with("novusluke/ponyponyparadise-voice-mod", self.window.metadata["version"])
        self.assertFalse(hasattr(self.window, "repository"))
        self.assertEqual(self.window.language.count(), 1)
        self.assertEqual(self.window.language.currentData(), "en")

    def test_single_view_has_one_apply_and_no_numbered_tabs(self):
        from PySide6.QtWidgets import QPushButton, QStackedWidget
        texts = [item.text() for item in self.window.findChildren(QPushButton)]
        self.assertEqual(texts.count("Apply voices"), 1)
        self.assertIn("Launch PonyPonyParadise", texts)
        self.assertIn("Check for updates", texts)
        self.assertIn("Release page", texts)
        self.assertFalse(self.window.findChildren(QStackedWidget))
        self.assertFalse(any(text.startswith(("01", "02", "03", "Continue to")) for text in texts))

    def test_local_only_controls_and_prominent_launch(self):
        from PySide6.QtWidgets import QPushButton, QLabel
        texts = [item.text().lower() for item in self.window.findChildren(QPushButton)]
        self.assertFalse(any(any(token in text for token in ("colab","kaggle","notebook","export dialogue","import")) for text in texts))
        self.assertFalse(any("Made for a little more wonder" in item.text() for item in self.window.findChildren(QLabel)))
        self.assertEqual(self.window.config["execution_mode"], "local")
        self.assertEqual(self.window.config["text_display_mode"], "wait")
        self.assertEqual(self.window.launch_button.objectName(), "launch")
        self.assertGreaterEqual(self.window.launch_button.minimumHeight(), 58)

    def test_music_mute_and_volume_use_private_preferences(self):
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {"PONY_VOICE_STATE_DIR": temporary}):
            self.window.preview = False
            template = (script.ROOT / "config.json").read_bytes()
            self.window.music_muted.setChecked(True)
            self.window.music_volume.setValue(12)
            self.assertTrue(self.window.music_output.isMuted())
            self.assertAlmostEqual(self.window.music_output.volume(), .12, places=4)
            self.assertEqual(json.loads(preferences_path().read_text())["setup_music"], {"muted":True,"volume":12})
            self.assertEqual((script.ROOT / "config.json").read_bytes(), template)
            self.window.preview = True

    def test_music_asset_decodes_and_closing_stops_playback(self):
        from PySide6.QtMultimedia import QMediaPlayer
        self.window.music_output.setMuted(True)
        self.window.music_player.play()
        deadline = time.monotonic() + 4
        while self.window.music_player.duration() == 0 and time.monotonic() < deadline:
            self.app.processEvents()
            time.sleep(.01)
        self.assertEqual(self.window.music_player.error(), QMediaPlayer.Error.NoError)
        self.assertGreater(self.window.music_player.duration(), 1000)
        self.window.close()
        self.assertEqual(self.window.music_player.playbackState(), QMediaPlayer.PlaybackState.StoppedState)

    def test_successful_launch_closes_setup_and_stops_music(self):
        from PySide6.QtMultimedia import QMediaPlayer
        with tempfile.TemporaryDirectory() as temporary:
            game = Path(temporary).resolve()
            (game / "PonyPonyParadise.pck").touch()
            (game / "PonyPonyParadise.exe").touch()
            self.window.game_folder.setText(str(game))
            self.window.music_output.setMuted(True)
            self.window.music_player.play()
            with patch.object(service.subprocess, "Popen") as launch:
                self.window.launch_button.click()
            launch.assert_called_once()
            self.assertEqual(launch.call_args.args[0], [str(game / "PonyPonyParadise.exe")])
            self.assertFalse(self.window.isVisible())
            self.assertEqual(self.window.music_player.playbackState(), QMediaPlayer.PlaybackState.StoppedState)

    def test_failed_launch_keeps_setup_open(self):
        with tempfile.TemporaryDirectory() as temporary:
            game = Path(temporary).resolve()
            (game / "PonyPonyParadise.pck").touch()
            (game / "PonyPonyParadise.exe").touch()
            self.window.game_folder.setText(str(game))
            with patch.object(service.subprocess, "Popen", side_effect=OSError("Launch failed")):
                self.window.launch_button.click()
            self.assertTrue(self.window.isVisible())
            self.assertIn("Launch failed", self.window.status.text())

    def test_uninstall_uses_selected_game_and_refreshes_install_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            game = Path(temporary).resolve() / "selected game"
            game.mkdir()
            (game / "PonyPonyParadise.pck").touch()
            (game / "PonyPonyParadise.pck.voice-mod-original").touch()
            state = game / "data/voice_mod/install_state.json"
            state.parent.mkdir(parents=True)
            state.write_text('{"mod_version":"1.6.1"}')
            self.window.game_folder.setText(str(game))
            self.assertTrue(self.window.uninstall_button.isEnabled())
            from PySide6.QtWidgets import QMessageBox
            def removed(selected, log):
                self.assertEqual(selected, game)
                state.unlink()
                state.parent.rmdir()
                (game / "PonyPonyParadise.pck.voice-mod-original").unlink()
                return {"removed": 5, "restored": 0, "retained": 0}
            with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.Yes) as question, \
                 patch.object(service, "uninstall_voices", side_effect=removed) as uninstall:
                self.window.uninstall_button.click()
                self.finish()
            uninstall.assert_called_once()
            self.assertIn(str(game), question.call_args.args[2])
            self.assertFalse(self.window.uninstall_button.isEnabled())
            self.assertIn("ready to install", self.window.game_version.text())
            self.assertIn("Original game restored", self.window.status.text())

    def test_cancelling_uninstall_changes_nothing(self):
        with tempfile.TemporaryDirectory() as temporary:
            game = Path(temporary).resolve()
            (game / "PonyPonyParadise.pck").write_bytes(b"unchanged")
            self.window.game_folder.setText(str(game))
            from PySide6.QtWidgets import QMessageBox
            with patch.object(QMessageBox, "question", return_value=QMessageBox.StandardButton.No), \
                 patch.object(service, "uninstall_voices") as remove:
                self.window.uninstall_mod()
            remove.assert_not_called()
            self.assertEqual((game / "PonyPonyParadise.pck").read_bytes(), b"unchanged")

    def test_older_game_update_is_read_only_until_clicked(self):
        with tempfile.TemporaryDirectory() as temporary:
            game = Path(temporary).resolve()
            pack = game / "PonyPonyParadise.pck"
            pack.write_bytes(b"existing game fixture")
            state = game / "data/voice_mod/install_state.json"
            state.parent.mkdir(parents=True)
            state.write_text('{"mod_version":"0.9.0"}', encoding="utf-8")
            before = pack.read_bytes()
            with patch.object(service, "apply_voices") as apply:
                self.window.game_folder.setText(str(game))
                self.window.detect_game_button.click()
                self.window.launch_game()
                self.assertTrue(self.window.update_button.isVisible())
                self.assertEqual(self.window.update_button.objectName(), "update")
                apply.assert_not_called()
                self.assertEqual(pack.read_bytes(), before)
            with patch.object(self.window, "apply_from_engine") as explicit:
                self.window.update_button.click()
                explicit.assert_called_once()

    def test_remote_update_check_never_applies_a_game_patch(self):
        with patch.object(service, "apply_voices") as apply:
            self.window.checked_update({"kind": "available", "message": "New version available",
                                       "url": "https://github.com/owner/repo/releases/latest", "download": ""})
            self.assertTrue(self.window.update_button.isVisible())
            apply.assert_not_called()


if __name__ == "__main__":
    unittest.main()
