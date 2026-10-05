"""Keep reference transcription/verification fast without crowding the TTS GPU."""
from __future__ import annotations
import logging

MIN_FREE_GPU_BYTES = 4 * 1024 ** 3

def select_device(torch, tts_device: str) -> str:
    if str(tts_device).startswith("cuda") and torch.cuda.is_available():
        try:
            free, _ = torch.cuda.mem_get_info(torch.device(tts_device))
            if free >= MIN_FREE_GPU_BYTES:
                return str(tts_device)
        except (RuntimeError, ValueError):
            pass
    return "cpu"

def load_asr(model, persistent_prompts: bool, tts_device: str):
    import torch
    device = select_device(torch, tts_device)
    def load(selected):
        if selected == "cpu":
            torch.set_num_threads(min(4, torch.get_num_threads()))
        if persistent_prompts:
            model.load_asr_model(device=selected)
        else:
            from transformers import pipeline
            model._asr_pipe = pipeline("automatic-speech-recognition", model="openai/whisper-small",
                device=selected, dtype=torch.float32 if selected == "cpu" else torch.float16)
    try:
        load(device)
    except torch.OutOfMemoryError:
        if device == "cpu":
            raise
        # The driver may lose spare VRAM to another application during loading.
        model._asr_pipe = None
        torch.cuda.empty_cache()
        device = "cpu"
        load(device)
    logging.info("Whisper-small transcription/verification device: %s", device)
    return device
