import copy
import hashlib
import importlib.util
import json
import tempfile
import unittest
from contextlib import nullcontext
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import Mock, patch

import script
from voice_mod.common import atomic_json, line_id, manifest_lines, speaker_id, speech_text
from voice_mod.generate import VoiceGenerator
from voice_mod.pck import Pack, read_pack, write_pack
from voice_mod.worker import process_job, ordered_jobs
from voice_mod.narration import verify_words


class FakeGenerator:
    def __init__(self, references, options):
        self.references = references
        self.calls = 0
        self.model = None

    def load_model(self):
        self.model = object()

    def reference(self, language, speaker):
        path = self.references / language / (speaker + ".mp3")
        return path if path.exists() else None

    def generate(self, language, speaker, text, output):
        if text == "FAIL":
            raise RuntimeError("Simulated GPU failure")
        if self.reference(language, speaker) is None:
            return False
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_bytes(b"ID3test-fixture")
        self.calls += 1
        return True

    def close(self):
        pass


class VoiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.refs = self.root / "references"
        (self.refs / "en").mkdir(parents=True)
        (self.refs / "en/spike.mp3").write_bytes(b"reference fixture")

    def tearDown(self):
        self.temp.cleanup()

    def test_quality_is_always_64_even_for_legacy_preferences(self):
        preferences = self.root / "config.json"
        for previous in (4, 16, 128, "invalid"):
            atomic_json(preferences, {"omnivoice": {"num_step": previous}})
            self.assertEqual(script.load_config(preferences)["omnivoice"]["num_step"], 64)
            generator = VoiceGenerator(self.refs, {"num_step": previous})
            try:
                self.assertEqual(generator.options["num_step"], 64)
            finally:
                generator.close()

    def test_in_game_version_matches_installer_release(self):
        release = json.loads((script.ROOT / "release.json").read_text(encoding="utf-8"))
        version = (script.ROOT / "game_patch/scripts/voice_mod/voice_version.gd").read_text(encoding="utf-8")
        self.assertIn('VERSION := "' + release["version"] + '"', version)

    def test_all_base_clips_have_verified_64_step_provenance(self):
        root = script.ROOT / "data/voices"
        manifest = json.loads((root / "opening_manifest.json").read_text(encoding="utf-8"))
        expected = {}
        for filename in ("opening.json", "system.json"):
            expected.update({row["id"]: row for row in manifest_lines(script.ROOT / "dialogue" / filename)})
        self.assertEqual(len(expected), 151)
        self.assertEqual({row["id"] for row in manifest["lines"]}, set(expected))
        self.assertEqual({p.stem for p in (root / "en").glob("*.mp3")}, set(expected))
        narrator_count = 0
        reference_sha256 = hashlib.sha256((script.ROOT / "reference_audios/en/narrator.mp3").read_bytes()).hexdigest()
        for row in manifest["lines"]:
            self.assertEqual(row["num_step"], 64, row["id"])
            self.assertEqual(row["generation_text_sha256"], hashlib.sha256(speech_text(expected[row["id"]]["text"]).encode()).hexdigest())
            self.assertEqual(row["sha256"], hashlib.sha256((root / row["file"]).read_bytes()).hexdigest())
            if row["speaker"] == "narrator":
                narrator_count += 1
                verification = row["narrator_verification"]
                self.assertTrue(verification["ok"])
                self.assertTrue(verification["first_word_verified"])
                self.assertFalse(verification["onset_burst"])
                self.assertGreaterEqual(verification["word_coverage"], .88)
                self.assertIn(row["generation_attempts"], (1, 2, 3))
                self.assertEqual(row["reference_sha256"], reference_sha256)
        self.assertEqual(narrator_count, 84)

    def test_reference_loudness_receipt_matches_all_bundled_clips(self):
        report = json.loads((script.ROOT / "reference_audios/loudness.json").read_text(encoding="utf-8"))
        self.assertEqual(len(report["files"]), 50)
        for record in report["files"]:
            self.assertLessEqual(abs(record["after_lufs"] - report["target_lufs"]), .3)
            self.assertLessEqual(record["true_peak_dbtp"], 0)
            self.assertEqual(record["sha256"], hashlib.sha256((script.ROOT / "reference_audios" / record["file"]).read_bytes()).hexdigest())
        for filename in ("bonbon.mp3", "daisy.mp3"):
            record = next(row for row in report["files"] if row["file"] == "en/" + filename)
            self.assertGreater(record["after_lufs"] - record["before_lufs"], 10)

    def test_player_identity_uses_narrator(self):
        self.assertEqual(speaker_id("player"), "narrator")
        self.assertEqual(speaker_id("???"), "narrator")
        rows = manifest_lines(script.ROOT / "dialogue/opening.json")
        for text in ('"I... I can\'t..."', '"Why can\'t I remember anything?"'):
            self.assertTrue(any(row["speaker"] == "narrator" and row["text"] == text for row in rows))

    def test_background_jobs_stay_with_speaker_but_visible_line_has_priority(self):
        import os
        for number, speaker in enumerate(("twi", "narrator", "twilight", "narrator")):
            path = self.root / f"job_{number}.json"
            atomic_json(path, {"speaker": speaker, "priority": 0})
            os.utime(path, ns=(number + 1, number + 1))
        self.assertEqual([path.stem for path in ordered_jobs(self.root)], ["job_0", "job_2", "job_1", "job_3"])
        self.assertEqual([path.stem for path in ordered_jobs(self.root, "narrator")], ["job_1", "job_3", "job_0", "job_2"])
        atomic_json(self.root / "job_2.json", {"speaker": "twilight", "priority": 1})
        self.assertEqual(ordered_jobs(self.root, "narrator")[0].stem, "job_2")

    def test_unchanged_reference_is_hashed_once_per_worker(self):
        generator = VoiceGenerator(self.refs, {})
        reference = self.refs / "en/spike.mp3"
        original = Path.read_bytes
        reads = []
        def read(path):
            reads.append(path)
            return original(path)
        try:
            with patch.object(Path, "read_bytes", read):
                expected = generator.prompt_identity(reference)
                for _ in range(40):
                    self.assertEqual(generator.prompt_identity(reference), expected)
            self.assertEqual(reads, [reference])
        finally:
            generator.close()

    def test_inference_receives_64_even_if_options_are_mutated(self):
        generator = VoiceGenerator(self.refs, {"num_step": 4})
        model = SimpleNamespace(sampling_rate=24000, generate=Mock(return_value=[[0.0]]))
        generator.model = model
        generator.options["num_step"] = 16
        identity = generator.prompt_identity(self.refs / "en/spike.mp3")
        generator.prompts[identity] = object()
        try:
            with patch.dict("sys.modules", {"torch": SimpleNamespace(inference_mode=nullcontext),
                                            "soundfile": SimpleNamespace(write=Mock())}), \
                 patch("voice_mod.generate.convert_audio", side_effect=lambda _, target: target.write_bytes(b"ID3fixture")):
                self.assertTrue(generator.generate("en", "spike", "Hello.", self.root / "output.mp3"))
            self.assertEqual(model.generate.call_args.kwargs["num_step"], 64)
        finally:
            generator.close()

    def test_identity_matches_godot_fixture(self):
        self.assertEqual(line_id("en", "cel", "[i]Hello[/i]   world!"),
                         "804dfb0ffeeb6dcca883b26f792076440bfea1ea753563154382eb9dd7fe9fe1")
        self.assertEqual(speaker_id("Twilight Sparkle"), speaker_id("twi"))
        self.assertEqual(speaker_id("Sweetie_Belle"), "sweetiebelle")
        self.assertEqual(speaker_id("narrator"), "narrator")
        self.assertNotEqual(line_id("en", "narrator", "Darkness."), line_id("en", "celestia", "Darkness."))
        self.assertEqual(speech_text("[color=red]Hello[/color]\nworld"), "Hello world")
        self.assertNotEqual(line_id("en", "spike", "Hello"), line_id("it", "spike", "Hello"))

    def test_narrator_rejects_missing_first_word_and_unwanted_prefix(self):
        self.assertFalse(verify_words("The library is warm and welcoming.", "Library is warm and welcoming.")["ok"])
        self.assertFalse(verify_words("The library is warm and welcoming.", "Ah! The library is warm and welcoming.")["ok"])
        self.assertFalse(verify_words("You can now ask questions or continue the conversation.", "You can now ask.")["ok"])
        self.assertTrue(verify_words("Weight.", "Wait.")["ok"])
        self.assertTrue(verify_words("Leaves rustle nearby, something is moving out there.", "Leaves Russell nearby. Something is moving out there.")["ok"])
        self.assertTrue(verify_words("Доброе утро.", "Доброе утро.")["ok"])
        self.assertTrue(verify_words("The library is warm and welcoming.", "The library is warm and welcoming.")["ok"])

    def test_prompt_cache_changes_when_transcript_or_preparation_changes(self):
        generator = VoiceGenerator(self.refs, {})
        try:
            reference = self.refs / "en/spike.mp3"
            first = generator.prompt_identity(reference)
            reference.with_suffix(".txt").write_text("Matching words.")
            second = generator.prompt_identity(reference)
            reference.with_suffix(".txt").write_text("Corrected words.")
            self.assertNotEqual(first, second)
            self.assertNotEqual(second, generator.prompt_identity(reference))
            before = generator.prompt_identity(reference)
            with patch("voice_mod.generate.REFERENCE_PREPARATION_VERSION", 999):
                self.assertNotEqual(before, generator.prompt_identity(reference))
        finally:
            generator.close()

    def test_narrator_retries_bad_audio_and_caches_only_verified_speech(self):
        reference = self.refs / "en/narrator.mp3"
        reference.write_bytes(b"narrator fixture")
        for succeeds in (True, False):
            with self.subTest(succeeds=succeeds):
                generator = VoiceGenerator(self.refs, {})
                generator.model = SimpleNamespace(sampling_rate=24000, generate=Mock(return_value=[[0.1]]))
                generator.prompts[generator.prompt_identity(reference)] = object()
                output = self.root / ("verified.mp3" if succeeds else "rejected.mp3")
                transcripts = ["Library is warm.", "The library is warm."] if succeeds else ["Library is warm."] * 3
                try:
                    with patch.dict("sys.modules", {"torch": SimpleNamespace(inference_mode=nullcontext),
                                                    "soundfile": SimpleNamespace(write=Mock())}), \
                         patch.object(generator, "_transcribe_narration", side_effect=transcripts), \
                         patch("voice_mod.generate.has_onset_burst", return_value=False), \
                         patch("voice_mod.generate.pad_narration", side_effect=lambda audio, _: audio), \
                         patch("voice_mod.generate.convert_audio", side_effect=lambda _, target: target.write_bytes(b"ID3verified")):
                        if succeeds:
                            self.assertTrue(generator.generate("en", "narrator", "The library is warm.", output))
                            self.assertTrue(output.is_file())
                            self.assertEqual(generator.last_verification["attempts"], 2)
                        else:
                            with self.assertRaisesRegex(RuntimeError, "No faulty clip was cached"):
                                generator.generate("en", "narrator", "The library is warm.", output)
                            self.assertFalse(output.exists())
                    for call in generator.model.generate.call_args_list:
                        self.assertEqual(call.kwargs["num_step"], 64)
                        self.assertFalse(call.kwargs["postprocess_output"])
                finally:
                    generator.close()

    def test_cropped_reference_does_not_use_full_recording_transcript(self):
        reference = self.refs / "en/spike.mp3"
        reference.with_suffix(".txt").write_text("Words from the full recording.")
        generator = VoiceGenerator(self.refs, {"prompt_cache": str(self.root / "prompts")})
        generator.model = SimpleNamespace(sampling_rate=24000, generate=Mock(return_value=[[0.1]]),
                            create_voice_clone_prompt=Mock(return_value=object()), _asr_pipe=object())
        generator.persistent_prompts = False
        try:
            with patch.dict("sys.modules", {"torch": SimpleNamespace(inference_mode=nullcontext),
                   "soundfile": SimpleNamespace(write=Mock(), read=Mock(return_value=([0.1] * 300000, 24000))),
                   "omnivoice.models.omnivoice": SimpleNamespace(VoiceClonePrompt=object)}), \
                 patch("voice_mod.generate.convert_audio", side_effect=lambda _, target, *args: target.write_bytes(b"fixture")):
                generator.generate("en", "spike", "Hello.", self.root / "output.mp3")
            self.assertIsNone(generator.model.create_voice_clone_prompt.call_args.kwargs["ref_text"])
        finally:
            generator.close()

    def test_manifest_rejects_mismatched_hash(self):
        path = self.root / "manifest.json"
        atomic_json(path, [{"id": "wrong", "text": "Hello", "speaker": "spike"}])
        with self.assertRaises(ValueError):
            manifest_lines(path)

    def test_manifest_deduplicates_equivalent_speakers(self):
        path = self.root / "manifest.json"
        atomic_json(path, [{"text": "Hello", "speaker": "twi"}, {"text": "Hello", "speaker": "twilight"}])
        self.assertEqual(len(manifest_lines(path)), 1)

    def test_pack_roundtrip_all_supported_versions(self):
        for version in (2, 3, 4):
            path = self.root / f"{version}.pck"
            pack = Pack(version, (4, 8, 0), {"project.binary": b"fixture", "folder/script.gd": b"extends Node\n"})
            write_pack(path, pack)
            result = read_pack(path)
            self.assertEqual(result, pack)

    def test_pack_corruption_refused(self):
        path = self.root / "game.pck"
        write_pack(path, Pack(4, (4, 8, 0), {"data.bin": b"hello"}))
        blob = bytearray(path.read_bytes())
        blob[112] ^= 1
        path.write_bytes(blob)
        with self.assertRaisesRegex(ValueError, "checksum"):
            read_pack(path)

    def test_pack_path_traversal_refused(self):
        with self.assertRaises(ValueError):
            write_pack(self.root / "game.pck", Pack(4, (4, 8, 0), {"../outside": b"oops"}))

    def test_expired_worker_job_returns_failure(self):
        self.worker_case("Hello", deadline=0, expected=False)

    def test_gpu_failure_returns_marker(self):
        self.worker_case("FAIL", deadline=10**12, expected=False)

    def test_successful_worker_uses_derived_output(self):
        self.worker_case("Hello", deadline=10**12, expected=True)

    def test_worker_cache_skips_model_loading_and_generation(self):
        key = line_id("en", "spike", "Cached sentence")
        output = self.root / "voices/en" / (key + ".mp3")
        output.parent.mkdir(parents=True)
        output.write_bytes(b"ID3existing")
        job = self.root / ("job_" + key + ".json")
        atomic_json(job, {"language": "en", "speaker": "spike", "text": "Cached sentence", "deadline": 10**12})
        generator = FakeGenerator(self.refs, {})
        with patch.object(generator, "load_model", side_effect=AssertionError("Model must stay unloaded")):
            process_job(job, {"voices_path": str(self.root / "voices")}, generator)
        self.assertEqual(generator.calls, 0)
        self.assertEqual(output.read_bytes(), b"ID3existing")
        self.assertTrue(json.loads((self.root / ("done_" + key + ".json")).read_text())["ok"])

    def test_worker_missing_protected_clip_never_synthesizes(self):
        key = line_id("en", "spike", "Fixed system sentence")
        job = self.root / ("job_" + key + ".json")
        atomic_json(job, {"language": "en", "speaker": "spike", "text": "Fixed system sentence", "deadline": 10**12})
        generator = FakeGenerator(self.refs, {})
        with self.assertLogs(level="ERROR"), patch.object(generator, "load_model", side_effect=AssertionError("Must not synthesize base clips")):
            process_job(job, {"voices_path": str(self.root / "voices"), "protected_ids": {key}}, generator)
        self.assertEqual(generator.calls, 0)
        self.assertFalse(json.loads((self.root / ("done_" + key + ".json")).read_text())["ok"])

    def test_text_mode_default_and_removed_cache_interval_migration(self):
        config = self.root / "config.json"
        atomic_json(config, {"text_display_mode": "invalid"})
        with self.assertRaises(ValueError):
            script.load_config(config)
        for days in (1, 7, 30, -1):
            atomic_json(config, {"cache_cleanup_days": days})
            migrated = script.load_config(config)
            self.assertNotIn("cache_cleanup_days", migrated)
            self.assertEqual(migrated["text_display_mode"], "wait")

    def test_every_english_character_tag_and_name_has_its_own_reference(self):
        roster = json.loads((script.ROOT / "dialogue/voice_roster.json").read_text(encoding="utf-8"))
        self.assertEqual(len(roster["characters"]), 49)
        for row in roster["characters"]:
            self.assertEqual(speaker_id(row["tag"]), row["voice"])
            self.assertEqual(speaker_id(row["name"]), row["voice"])
            self.assertTrue((script.ROOT / "reference_audios" / row["file"]).is_file(), row["name"])
        self.assertTrue((script.ROOT / "reference_audios" / roster["narrator"]).is_file())

    def worker_case(self, text, deadline, expected):
        key = line_id("en", "spike", text)
        path = self.root / ("job_" + key + ".json")
        atomic_json(path, {"language": "en", "speaker": "spike", "text": text, "deadline": deadline,
                           "output_path": str(self.root / "should-never-be-written.mp3")})
        process_job(path, {"voices_path": str(self.root / "voices")}, FakeGenerator(self.refs, {}))
        done = json.loads((self.root / ("done_" + key + ".json")).read_text())
        self.assertEqual(done["ok"], expected)
        self.assertFalse(path.exists())
        self.assertFalse((self.root / "should-never-be-written.mp3").exists())
        self.assertEqual((self.root / "voices/en" / (key + ".mp3")).exists(), expected)

    def test_local_path_resolution_ignores_shell_directory(self):
        self.assertEqual(script.resolve_path("reference_audios"), script.ROOT / "reference_audios")

    def test_git_origin_url_formats(self):
        for value in ("owner/repo", "https://github.com/owner/repo.git", "git@github.com:owner/repo.git"):
            self.assertEqual(script.repository_name(value), "owner/repo")
        with self.assertRaises(ValueError):
            script.repository_name("https://example.com/owner/repo")

    def test_new_reference_sync_and_checksum(self):
        content = b"new character voice"
        directory = [{"type": "dir", "name": "en"}]
        entries = [{"type": "file", "name": "newpony.mp3", "sha": script.git_blob_sha(content),
                    "download_url": "https://raw.githubusercontent.com/owner/repo/main/reference_audios/en/newpony.mp3"}]
        def fake_download(url):
            if "raw.githubusercontent" in url:
                return content
            return json.dumps(directory if "/en?" not in url else entries).encode()
        config = copy.deepcopy(script.DEFAULTS)
        config["github_repository"] = "owner/repo"
        with patch.object(script, "download", side_effect=fake_download):
            destination = script.ROOT / "reference_audios"  # mock copy origin to avoid mixing bundled fixtures
            with patch.object(script, "ROOT", self.root):
                self.assertEqual(script.sync_references(config, self.root / "reference_audios"), 1)
                self.assertEqual(script.sync_references(config, self.root / "reference_audios"), 0)
        self.assertEqual((self.root / "reference_audios/en/newpony.mp3").read_bytes(), content)

    def test_reference_sync_downloads_only_english(self):
        source = self.root / "source/reference_audios"
        for code in ("en", "it"):
            (source / code).mkdir(parents=True)
            (source / code / "spike.mp3").write_bytes(code.encode())
        requested = []
        def remote(url):
            requested.append(url)
            return json.dumps([{"type": "dir", "name": "en"}, {"type": "dir", "name": "it"}]
                              if "/en?" not in url else []).encode()
        with patch.object(script, "ROOT", self.root / "source"), patch.object(script, "download", side_effect=remote):
            script.sync_references(copy.deepcopy(script.DEFAULTS), self.root / "cache")
        self.assertTrue((self.root / "cache/en/spike.mp3").is_file())
        self.assertFalse((self.root / "cache/it").exists())
        self.assertFalse(any("/it?" in url for url in requested))

    def test_changed_bundled_reference_replaces_old_cache_and_discards_stale_transcript(self):
        source = self.root / "source/reference_audios/en"
        source.mkdir(parents=True)
        (source / "spike.mp3").write_bytes(b"updated bundled sample")
        cache = self.root / "cached-references/en"
        cache.mkdir(parents=True)
        (cache / "spike.mp3").write_bytes(b"old sample")
        (cache / "spike.txt").write_text("Transcript from the old sample.")
        with patch.object(script, "ROOT", self.root / "source"):
            script.sync_references(copy.deepcopy(script.DEFAULTS), cache.parent, remote=False)
            self.assertEqual((cache / "spike.mp3").read_bytes(), b"updated bundled sample")
            self.assertFalse((cache / "spike.txt").exists())
            (cache / "spike.mp3").write_bytes(b"newer remote sample")
            script.sync_references(copy.deepcopy(script.DEFAULTS), cache.parent, remote=False)
            self.assertEqual((cache / "spike.mp3").read_bytes(), b"newer remote sample")
            (source / "spike.mp3").write_bytes(b"next release sample")
            script.sync_references(copy.deepcopy(script.DEFAULTS), cache.parent, remote=False)
            self.assertEqual((cache / "spike.mp3").read_bytes(), b"next release sample")

    def test_installer_backup_reinstall_and_modified_game_protection(self):
        source = self.root / "mod-source"
        (source / "game_patch/scripts").mkdir(parents=True)
        (source / "voice_mod").mkdir()
        (source / "voice_mod/__init__.py").write_text("")
        original_script = b"compiled game fixture"
        (source / "game_patch/scripts/example.gd").write_text("extends Node\n")
        atomic_json(source / "game_patch/compatibility.json",
                    {"engine": [4, 8, 0], "base_scripts": {"scripts/example.gd": hashlib.sha256(original_script).hexdigest()}})
        game = self.root / "game"
        game.mkdir()
        target = game / "PonyPonyParadise.pck"
        write_pack(target, Pack(4, (4, 8, 0), {"scripts/example.gdc": original_script,
                                             "scripts/example.gd.remap": b"remap", "project.binary": b"project fixture"}))
        original_hash = hashlib.sha256(target.read_bytes()).hexdigest()
        with patch.object(script, "ROOT", source):
            config = copy.deepcopy(script.DEFAULTS)
            script.install_game(game, config)
            installed = read_pack(target)
            self.assertIn("scripts/example.gd", installed.files)
            self.assertNotIn("scripts/example.gdc", installed.files)
            self.assertNotIn("scripts/example.gd.remap", installed.files)
            script.install_game(game, config)
            backup = game / "PonyPonyParadise.pck.voice-mod-original"
            self.assertEqual(hashlib.sha256(backup.read_bytes()).hexdigest(), original_hash)
            target.write_bytes(target.read_bytes() + b"other modification")
            with self.assertRaisesRegex(ValueError, "changed since installation"):
                script.install_game(game, config)
            self.assertEqual(hashlib.sha256(backup.read_bytes()).hexdigest(), original_hash)


if __name__ == "__main__":
    unittest.main()
