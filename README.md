# PonyPonyParadise Voice Mod

English voices for PonyPonyParadise, powered by local [OmniVoice](https://github.com/k2-fsa/OmniVoice). Includes 49 character voices and a narrator.

Download the ZIP from [Releases](https://github.com/novusluke/ponyponyparadise-voice-mod/releases/latest), extract it, and open **PonyPonyParadiseVoiceSetup.exe**.

1. Select your PonyPonyParadise game folder.
2. Select an existing OmniVoice installation or choose **Install OmniVoice**.
3. Click **Apply voices**, then **Launch PonyPonyParadise**.

Generating new speech requires an NVIDIA CUDA GPU. The first engine setup and model download require an internet connection.

Voice settings and **Clean Cache** are available in the game's Character Voices menu. Setup includes **Check for updates**, **Release page**, and **Uninstall voice mod**. Uninstall restores the original game and keeps your saves.

To build the Windows setup from source:

```powershell
python -m pip install -r requirements-installer.txt
python -B tools/build_installer.py
python -B tools/build_release_zip.py
```

Source uses [PolyForm Noncommercial 1.0.0](LICENSE). Dialogic uses [MIT](game_patch/addons/dialogic/LICENSE). Audio, artwork, and music retain their respective owners' rights. See [third-party notices](THIRD_PARTY_NOTICES.md).
