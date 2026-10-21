"""Timing regression tests independent of the downloaded song's note count."""
import importlib.util
import json
import unittest
import sys
sys.dont_write_bytecode = True
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT
spec = importlib.util.spec_from_file_location('convert_sm', GAME / 'convert_sm.py')
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)


class ConversionTest(unittest.TestCase):
    def test_bpm_stop_and_offset(self):
        bpms = [(0, 120), (4, 60)]
        stops = [(4, 0.25)]
        self.assertAlmostEqual(converter.beat_seconds(4, bpms, stops, 0.1), 1.9)
        self.assertAlmostEqual(converter.beat_seconds(5, bpms, stops, 0.1), 3.15)
        self.assertAlmostEqual(converter.beat_seconds(3, bpms, stops, 0.1), 1.4)

    def test_chords_and_hold_heads(self):
        chart = converter.convert('''#TITLE:Fixture;#ARTIST:Test;#OFFSET:0;#BPMS:0=120;
        #NOTES:dance-single::Easy:1:0,0,0,0,0:
        1100
        0200
        0300
        0001;''')
        self.assertEqual(chart['notes_ms'], [0, 500, 1500])
        self.assertEqual(chart['lanes'], [0, 0, 1])
        chord = converter.convert('#TITLE:Fixture;#ARTIST:Test;#BPMS:0=120;#NOTES:dance-single::Easy:1:0:1111;')
        self.assertEqual(chord['notes_ms'], [0, 0])
        self.assertEqual(chord['lanes'], [0, 1])
        self.assertEqual(chart['conversion']['simultaneous_heads_merged'], 1)
        self.assertEqual(chart['conversion']['hold_heads_to_taps'], 1)

    def test_real_chart_reproduces_all_timestamps(self):
        # Beat 36 includes beat 35's doubled BPM and its 217 ms stop.
        expected = (35 * 60 / 138 + 60 / 276.001 + 0.217 - 1.660) * 1000
        source = (GAME / 'charts/bad_apple/source.sm').read_text()
        for difficulty, filename, count in [('Easy', 'chart.json', 287),
                                            ('Medium', 'normal.json', 532),
                                            ('Hard', 'hard.json', 704)]:
            with self.subTest(difficulty=difficulty):
                converted = converter.convert(source, difficulty=difficulty)
                stored = json.loads((GAME / 'charts/bad_apple' / filename).read_text())
                self.assertEqual(converted['notes_ms'], stored['notes_ms'])
                self.assertEqual(converted['conversion'], stored['conversion'])
                self.assertEqual(len(stored['notes_ms']), count)
                self.assertEqual(stored['format_version'], 2)
                self.assertEqual(stored['key_count'], 2)
                self.assertEqual(set(stored['lanes']), {0, 1})
                self.assertEqual(list(zip(stored['notes_ms'], stored['lanes'])), sorted(set(zip(stored['notes_ms'], stored['lanes']))))
                self.assertEqual(converted['lanes'], stored['lanes'])
                self.assertEqual(stored['source']['difficulty'], difficulty)
                self.assertAlmostEqual(stored['notes_ms'][0], expected, places=3)

    def test_invalid_timing_is_rejected(self):
        source = (GAME / 'charts/bad_apple/source.sm').read_text()
        with self.assertRaises(ValueError):
            converter.convert(source.replace('#BPMS:0.000=138.000', '#BPMS:0.000=0'))
        with self.assertRaises(ValueError):
            converter.convert('#WARPS:4=2;' + source)


if __name__ == '__main__':
    unittest.main()

