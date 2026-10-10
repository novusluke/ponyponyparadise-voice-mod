# PonyPonyParadise Voice Mod

English voices for PonyPonyParadise, powered by local [OmniVoice](https://github.com/k2-fsa/OmniVoice). Includes 49 character voices and a narrator.

Download the ZIP from [Releases](https://github.com/novusluke/ponyponyparadise-voice-mod/releases/latest), extract it, and open **PonyPonyParadiseVoiceSetup.exe**.

1. Select your PonyPonyParadise game folder.
2. Use an existing OmniVoice installation, or click **Download & install OmniVoice** and choose a location. Setup downloads Python and OmniVoice into its own folder.
3. Click **Apply voices**, then **Launch PonyPonyParadise**.

Generating new speech requires an NVIDIA CUDA GPU. The first engine setup and model download require an internet connection.

Setup v1.0.3 supports the previously supported Windows game export and the official October 2026 Windows download checked on 10 October. It selects patches for the detected build, preserving its newer history, save and language features. Unrecognized or modified builds are refused before game files change; include your game version/download link when reporting a compatibility error.

Voice settings and **Clean Cache** are available in the game's Character Voices menu. Setup includes **Check for updates**, **Release page**, and **Uninstall voice mod**. Uninstall restores the original game and keeps your saves.

New Game and Quick Start include ready-to-play speech at 64 steps. **Wait for Audio (Recommended)** prepares the whole response before showing it; progress appears at the bottom right. After 30 seconds, **Too slow?** offers fewer steps with a quality warning. Preparation continues through settings and stops when you return to the main menu.

Click to advance, drag to select text, and use **Ctrl+C** to copy. **Space** and **Enter** also advance dialogue.

To build the Windows setup from source:

```powershell
python -m pip install -r requirements-installer.txt
python -B tools/build_installer.py
python -B tools/build_release_zip.py
```

Source uses [PolyForm Noncommercial 1.0.0](LICENSE). Dialogic uses [MIT](game_patch/addons/dialogic/LICENSE). Audio, artwork, and music retain their respective owners' rights. See [third-party notices](THIRD_PARTY_NOTICES.md).

[Original setup music](https://www.youtube.com/watch?v=For4GGkxALQ).

You can also try the web version that also includes voices: https://ponyponyparadise.bond/
