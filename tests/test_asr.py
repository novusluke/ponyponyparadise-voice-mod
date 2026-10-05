import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch
from voice_mod.asr import load_asr, select_device, MIN_FREE_GPU_BYTES

class MemoryErrorFixture(RuntimeError):
    pass

class ASRTests(unittest.TestCase):
    def torch(self, free):
        return SimpleNamespace(cuda=SimpleNamespace(is_available=lambda: True,
            mem_get_info=Mock(return_value=(free, 12 * 1024**3)), empty_cache=Mock()),
            device=lambda value: value, OutOfMemoryError=MemoryErrorFixture,
            set_num_threads=Mock(), get_num_threads=lambda: 16,
            float16="float16", float32="float32")

    def test_gpu_requires_memory_margin_and_tts_cuda(self):
        torch = self.torch(MIN_FREE_GPU_BYTES - 1)
        self.assertEqual(select_device(torch, "cuda:0"), "cpu")
        torch.cuda.mem_get_info.return_value = (MIN_FREE_GPU_BYTES, 12 * 1024**3)
        self.assertEqual(select_device(torch, "cuda:0"), "cuda:0")
        self.assertEqual(select_device(torch, "cpu"), "cpu")
        torch.cuda.mem_get_info.side_effect = RuntimeError("Unavailable memory query")
        self.assertEqual(select_device(torch, "cuda:0"), "cpu")

    def test_supported_engine_loads_gpu_verifier_once(self):
        torch = self.torch(8 * 1024**3)
        model = SimpleNamespace(load_asr_model=Mock())
        with patch.dict("sys.modules", {"torch": torch}):
            self.assertEqual(load_asr(model, True, "cuda:0"), "cuda:0")
        model.load_asr_model.assert_called_once_with(device="cuda:0")
        torch.set_num_threads.assert_not_called()

    def test_gpu_load_oom_falls_back_to_cpu(self):
        torch = self.torch(8 * 1024**3)
        model = SimpleNamespace(load_asr_model=Mock(side_effect=[MemoryErrorFixture(), None]))
        with patch.dict("sys.modules", {"torch": torch}):
            self.assertEqual(load_asr(model, True, "cuda:0"), "cpu")
        self.assertEqual(model.load_asr_model.call_args_list[1].kwargs, {"device": "cpu"})
        torch.cuda.empty_cache.assert_called_once()
        torch.set_num_threads.assert_called_once_with(4)

    def test_legacy_engine_preserves_whisper_model_on_both_devices(self):
        for free, device, dtype in ((0, "cpu", "float32"), (8 * 1024**3, "cuda:0", "float16")):
            torch = self.torch(free)
            model = SimpleNamespace(_asr_pipe=None)
            pipe = Mock(return_value=object())
            with patch.dict("sys.modules", {"torch": torch, "transformers": SimpleNamespace(pipeline=pipe)}):
                self.assertEqual(load_asr(model, False, "cuda:0"), device)
            self.assertEqual(pipe.call_args.kwargs, {"model": "openai/whisper-small", "device": device, "dtype": dtype})
            self.assertIsNotNone(model._asr_pipe)
