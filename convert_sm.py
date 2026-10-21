"""Convert one dance-single SM difficulty into the prototype's tap-only 2K JSON (left/down to left, up/right to right).

Timing is absolute audio time: integrate BPMs, add stops strictly before the
note beat, subtract SM OFFSET. Unsupported timing extensions are rejected.
"""
import argparse
import json
import math
import re
from pathlib import Path


def pairs(value):
    result = sorted(tuple(map(float, item.strip().split('=')))
                    for item in value.split(',') if item.strip())
    if any(len(item) != 2 or not all(map(math.isfinite, item)) for item in result):
        raise ValueError('Invalid timing values')
    if len({item[0] for item in result}) != len(result):
        raise ValueError('Duplicate timing beats')
    return result


def beat_seconds(beat, bpms, stops, offset):
    result = -offset
    for index, (start, bpm) in enumerate(bpms):
        end = bpms[index + 1][0] if index + 1 < len(bpms) else beat
        if beat <= start:
            break
        result += (min(beat, end) - start) * 60.0 / bpm
    # A note ON a stop is hit before freezing; later notes include its duration.
    return result + sum(duration for start, duration in stops if start < beat)


def convert(text, difficulty='Easy'):
    text = re.sub(r'//[^\r\n]*', '', text)
    tags = re.findall(r'#([^:;]+):(.*?);', text, flags=re.S)
    header = {key.strip().upper(): value.strip() for key, value in tags if key.strip().upper() != 'NOTES'}
    for unsupported in ('WARPS', 'DELAYS', 'FAKES'):
        if header.get(unsupported):
            raise ValueError(f'Unsupported timing tag: {unsupported}')
    bpms = pairs(header['BPMS'])
    stops = pairs(header.get('STOPS', ''))
    offset = float(header.get('OFFSET', '0'))
    if not math.isfinite(offset) or not bpms or bpms[0][0] != 0 or any(bpm <= 0 or beat < 0 for beat, bpm in bpms):
        raise ValueError('Expected positive BPMs starting at beat zero')
    if any(beat < 0 or duration < 0 for beat, duration in stops):
        raise ValueError('Negative stops are not supported')
    charts = [value.split(':', 5) for key, value in tags if key.strip().upper() == 'NOTES']
    matches = [parts for parts in charts if len(parts) == 6 and parts[0].strip() == 'dance-single' and parts[2].strip() == difficulty]
    if len(matches) != 1:
        raise ValueError('Expected exactly one matching dance-single difficulty')
    chart = matches[0]
    times = []
    lanes = []
    stats = dict(source_heads=0, simultaneous_heads_merged=0, hold_heads_to_taps=0, ignored_tails=0, ignored_mines=0)
    for measure, data in enumerate(chart[5].split(',')):
        rows = [line.strip() for line in data.splitlines() if line.strip()]
        if not rows:
            raise ValueError('Empty measure')
        for index, row in enumerate(rows):
            if len(row) != 4 or any(char not in '01234MLF' for char in row):
                raise ValueError(f'Unsupported note row: {row}')
            heads = sum(char in '124' for char in row)
            stats['source_heads'] += heads
            stats['hold_heads_to_taps'] += sum(char in '24' for char in row)
            stats['ignored_tails'] += row.count('3')
            stats['ignored_mines'] += row.count('M')
            if heads:
                target_lanes = sorted({column // 2 for column, char in enumerate(row) if char in '124'})
                stats['simultaneous_heads_merged'] += heads - len(target_lanes)
                beat = measure * 4 + index * 4 / len(rows)
                timestamp = round(beat_seconds(beat, bpms, stops, offset) * 1000, 3)
                if timestamp < 0 or (times and timestamp <= times[-1]):
                    raise ValueError('Negative or non-increasing converted note time')
                times.extend([timestamp] * len(target_lanes))
                lanes.extend(target_lanes)
    if not times:
        raise ValueError('Empty chart')
    return {
        'format_version': 2, 'key_count': 2, 'note_type': 'tap',
        'title': header['TITLE'], 'artist': header['ARTIST'],
        'audio_file': 'bad_apple.ogg', 'difficulty': f'{difficulty} / 2K',
        'notes_ms': times, 'lanes': lanes,
        'source': {'format': 'StepMania SM', 'difficulty': difficulty,
                   'meter': chart[3].strip(), 'offset_seconds': offset,
                   'bpms': bpms, 'stops': stops},
        'conversion': stats,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--difficulty', default='Easy')
    parser.add_argument('--mapper', required=True)
    parser.add_argument('--source-url', required=True)
    args = parser.parse_args()
    raw = args.source.read_bytes()
    chart = convert(raw.decode('utf-8-sig'), args.difficulty)
    chart['source'].update(mapper=args.mapper, url=args.source_url)
    args.output.write_text(json.dumps(chart, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'notes': len(chart['notes_ms']), 'first_ms': chart['notes_ms'][0],
                      'last_ms': chart['notes_ms'][-1], **chart['conversion']}))
