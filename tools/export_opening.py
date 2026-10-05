"""Export all fixed opening branches from a clean game, without save data."""
import argparse
import re
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from voice_mod.common import atomic_json, line_id, speaker_id, speech_text
from voice_mod.pck import read_pack


def opening_lines(pack):
    rows = {}
    pattern = re.compile(r'^"?(?P<speaker>[A-Za-z_][A-Za-z_0-9 ]*)"?(?:\s*\([^)]*\))?\s*:\s*(?P<text>.+)$')
    source = '\n'.join(pack.files[name].decode('utf-8') for name in (
        'dialogic/timelines/everfree_intro.dtl', 'dialogic/timelines/library_scene.dtl'))
    for raw in source.splitlines():
        text = raw.strip()
        if not text or text.startswith(('#', '[background', '[wait', '- ', 'if ', 'elif ', 'else:', 'set ', 'join ', 'leave ', 'update ', 'audio ', 'do ', 'label ', 'jump ', 'return', 'signal ', 'call ')):
            continue
        match = pattern.match(text)
        speaker = speaker_id(match['speaker'] if match else 'narrator')
        text = speech_text(match['text'] if match else text)
        if '{' in text or '}' in text:
            raise ValueError('Opening contains variable text; do not publish resolved player data.')
        key = line_id('en', speaker, text)
        rows[key] = dict(id=key, language='en', speaker=speaker, text=text)
    text = "Hello! My name is Twilight Sparkle, and I'm so happy to meet you!"
    key = line_id('en', 'twilight', text)
    rows[key] = dict(id=key, language='en', speaker='twilight', text=text)
    return list(rows.values())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    backup = args.game / 'PonyPonyParadise.pck.voice-mod-original'
    pack = read_pack(backup if backup.exists() else args.game / 'PonyPonyParadise.pck')
    rows = opening_lines(pack)
    atomic_json(args.output, {'schema_version': 1, 'description': 'Fixed Everfree and Golden Oak Library scenes, every choice branch, and the Twilight voice test.', 'lines': rows})
    print(f'Exported {len(rows)} fixed lines.')
