"""OmniVoice backend for local play."""
from __future__ import annotations

import os
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

from .common import language_code, speaker_id, speech_text
from .settings import state_directory
from .narration import (REFERENCE_PREPARATION_VERSION, NARRATOR_MAX_ATTEMPTS,
                        has_onset_burst, pad_narration, verify_words)


def ffmpeg_binary() -> str:
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def convert_audio(source: Path, target: Path, max_seconds: float | None = None) -> None:
    command = [ffmpeg_binary(), "-hide_banner", "-loglevel", "error", "-y", "-i", str(source)]
    if max_seconds is not None:
        command += ["-t", str(max_seconds)]
    command += ["-ac", "1", "-ar", "24000"]
    if target.suffix == ".mp3":
        command += ["-codec:a", "libmp3lame", "-b:a", "128k"]
    subprocess.run(command + [str(target)], check=True, timeout=120,
                   creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))


class VoiceGenerator:
    def __init__(self, references: Path, options: dict):
        self.references = references
        self.options = {**options, "num_step": 64}
        self.model = None
        self.prompts = {}
        self._identities = {}
        self.persistent_prompts = True
        self.narrator_options = {"postprocess_output": False}
        self.last_verification = {}
        self.temp = tempfile.TemporaryDirectory(prefix="synthesis_", dir=options.get("temp_directory"))

    def close(self):
        self.temp.cleanup()

    def reference(self, language: str, speaker: str) -> Path | None:
        language, speaker = language_code(language), speaker_id(speaker)
        override = self.options.get("character_voices", {}).get(speaker, "")
        if override and Path(override).is_file():
            return Path(override)
        for suffix in (".mp3", ".wav", ".ogg", ".flac"):
            path = self.references / language / (speaker + suffix)
            if path.is_file():
                return path
        default = self.options.get("default_voice", "") or str(self.references / language / "twilight.mp3")
        return Path(default) if speaker not in ("narrator", "celestia") and default and Path(default).is_file() else None

    def load_model(self):
        if self.model is not None:
            return
        import torch
        from omnivoice import OmniVoice
        from omnivoice.models.omnivoice import VoiceClonePrompt
        device = self.options.get("device", "cuda:0")
        if device.startswith("cuda") and not torch.cuda.is_available():
            raise RuntimeError("CUDA GPU unavailable. Check the NVIDIA driver and selected OmniVoice environment.")
        dtype = torch.float16 if device.startswith(("cuda", "mps", "xpu")) else torch.float32
        # Earlier OmniVoice releases have no prompt save/load and do not accept
        # asr_device. They can still synthesize through their supported API.
        self.persistent_prompts = hasattr(VoiceClonePrompt, "load") and hasattr(VoiceClonePrompt, "save")
        arguments = {"device_map": device, "dtype": dtype, "asr_model_name": "openai/whisper-small"}
        if self.persistent_prompts:
            arguments["asr_device"] = "cpu"
        self.model = OmniVoice.from_pretrained(self.options.get("model", "k2-fsa/OmniVoice"), **arguments)
        from dataclasses import fields
        from omnivoice import OmniVoiceGenerationConfig
        supported = {field.name for field in fields(OmniVoiceGenerationConfig)}
        # Older engines do not expose fade/padding controls. Our narrator
        # padding below supplies the same behavior for both API generations.
        self.narrator_options.update({key: 0.0 for key in ("fade_duration", "pad_duration") if key in supported})

    def prompt_identity(self, reference: Path) -> str:
        transcript = reference.with_suffix(".txt")
        def fingerprint(path):
            try:
                stat = path.stat()
                return (stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns)
            except FileNotFoundError:
                return None
        stamp = (fingerprint(reference), fingerprint(transcript),
                 self.options.get("reference_max_seconds", 10),
                 self.options.get("model", "k2-fsa/OmniVoice"), REFERENCE_PREPARATION_VERSION)
        previous = self._identities.get(reference)
        if previous and previous[0] == stamp:
            return previous[1]
        value = {"reference": hashlib.sha256(reference.read_bytes()).hexdigest(),
                 "transcript": hashlib.sha256(transcript.read_bytes()).hexdigest() if transcript.exists() else "asr",
                 "seconds": self.options.get("reference_max_seconds", 10),
                 "model": self.options.get("model", "k2-fsa/OmniVoice"),
                 "preparation": REFERENCE_PREPARATION_VERSION}
        identity = hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
        self._identities[reference] = (stamp, identity)
        return identity

    def _ensure_asr(self):
        if getattr(self.model, "_asr_pipe", None) is None:
            from .asr import load_asr
            load_asr(self.model, self.persistent_prompts, self.options.get("device", "cuda:0"))

    def _transcribe_narration(self, audio, sample_rate: int, language: str) -> str:
        self._ensure_asr()
        import numpy as np
        from scipy.signal import resample_poly
        from math import gcd
        divisor = gcd(sample_rate, 16000)
        waveform = resample_poly(np.asarray(audio, dtype=np.float32).reshape(-1), 16000 // divisor, sample_rate // divisor)
        return self.model._asr_pipe({"array": waveform, "sampling_rate": 16000},
                  generate_kwargs={"language": language, "task": "transcribe"})["text"].strip()

    def generate(self, language: str, speaker: str, text: str, output: Path) -> bool:
        import soundfile as sf
        language, speaker, text = language_code(language), speaker_id(speaker), speech_text(text)
        reference = self.reference(language, speaker)
        if reference is None or not text:
            return False
        self.load_model()
        self.last_verification = {}
        identity = self.prompt_identity(reference)
        if identity not in self.prompts:
            from omnivoice.models.omnivoice import VoiceClonePrompt
            cache = Path(self.options.get("prompt_cache", state_directory() / "cache/prompts"))
            cache.mkdir(parents=True, exist_ok=True)
            cached = cache / (identity + ".pt")
            if self.persistent_prompts and cached.is_file():
                self.prompts[identity] = VoiceClonePrompt.load(str(cached))
        if identity not in self.prompts:
            trimmed = Path(self.temp.name) / f"{language}-{speaker}.wav"
            full_reference = Path(self.temp.name) / "full-reference.wav"
            convert_audio(reference, full_reference)
            maximum = float(self.options.get("reference_max_seconds", 10))
            waveform, sample_rate = sf.read(full_reference)
            was_trimmed = len(waveform) / sample_rate > maximum + .01
            # Decode/resample once; cropping PCM does not require a second FFmpeg.
            sf.write(trimmed, waveform[:int(maximum * sample_rate)], sample_rate)
            # Transcribe only the trimmed reference, with a separate VRAM budget.
            transcript_path = reference.with_suffix(".txt")
            transcript = transcript_path.read_text(encoding="utf-8").strip() if transcript_path.exists() else None
            # A transcript for the full recording must never accompany a crop.
            if was_trimmed:
                transcript = None
            if not transcript:
                self._ensure_asr()
            self.prompts[identity] = self.model.create_voice_clone_prompt(str(trimmed), ref_text=transcript)
            staged_prompt = cached.with_name(identity + f".{os.getpid()}.tmp.pt")
            if self.persistent_prompts:
                try:
                    self.prompts[identity].save(str(staged_prompt))
                    os.replace(staged_prompt, cached)
                finally:
                    staged_prompt.unlink(missing_ok=True)
        import torch
        narrator = speaker == "narrator"
        attempts = NARRATOR_MAX_ATTEMPTS if narrator else 1
        for attempt in range(1, attempts + 1):
            with torch.inference_mode():
                audio = self.model.generate(
                    text=text, language=language, voice_clone_prompt=self.prompts[identity],
                    num_step=64, speed=1.0,
                    **(self.narrator_options if narrator else {}),
                )[0]
            if not narrator:
                break
            recognized = self._transcribe_narration(audio, self.model.sampling_rate, language)
            verification = verify_words(text, recognized)
            verification.update(attempts=attempt, asr_model="openai/whisper-small",
                                onset_burst=bool(has_onset_burst(audio, self.model.sampling_rate)))
            self.last_verification = verification
            if verification["ok"] and not verification["onset_burst"]:
                audio = pad_narration(audio, self.model.sampling_rate)
                break
        else:
            raise RuntimeError("Narrator speech failed its opening-word/content check after three 64-step attempts. No faulty clip was cached.")
        output.parent.mkdir(parents=True, exist_ok=True)
        wav = Path(self.temp.name) / "generated.wav"
        sf.write(wav, audio, self.model.sampling_rate)
        temp_mp3 = output.with_name(output.stem + f".{os.getpid()}.tmp.mp3")
        try:
            convert_audio(wav, temp_mp3)
            os.replace(temp_mp3, output)
        finally:
            temp_mp3.unlink(missing_ok=True)
        return True
