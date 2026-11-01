"""Generate an editable 2K experiment from the supplied MIDI-event JSON.

This is an offline arrangement pass, not a music transcriber. All timing is in
quarter-note beats; the existing library compiles points to unchanged game data.
Creation refuses overwrite so regenerating cannot erase a hand-edited project.
"""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

from author import metrics, validate
from chart_library import ChartLibrary, audio_duration


def arrange(source, bpm, offset_ms, origin, duration):
    ppq = source['ticks_per_quarter']
    if not isinstance(ppq, (int, float)) or ppq <= 0:
        raise ValueError('ticks_per_quarter must be positive')
    maximum = (duration - .151 - offset_ms / 1000) * bpm / 60
    events = []
    rejected = Counter()
    for raw in source['notes']:
        beat = raw['tick'] / ppq - origin
        snapped = round(beat * 4) / 4
        if abs(beat - snapped) > .08:
            rejected['off_grid'] += 1
            continue
        if snapped < 0 or snapped > maximum:
            rejected['outside_audio'] += 1
            continue
        if raw['velocity'] < 10:
            rejected['quiet'] += 1
            continue
        events.append(dict(raw, beat=snapped))
    drums = [n for n in events if n['part'] == 'percussion']
    hats = {n['beat'] for n in drums if n['pitch'] == 42 and n['velocity'] >= 40}
    # A three-hit sixteenth burst is not a triplet. The missing fourth slot is
    # part of this motif, preventing an uninterrupted roll from being absorbed.
    motifs = sorted(int(b) for b in hats if b == int(b)
                    and {b, b + .25, b + .5} <= hats and b + .75 not in hats)
    holds, covered = [], set()
    index = 0
    def kick_lane(beat):
        return (int(beat) // 32 + 1) % 2
    while index < len(motifs):
        start = last = motifs[index]
        index += 1
        while (index < len(motifs) and motifs[index] == last + 1
               and motifs[index] - start < 8
               and motifs[index] // 32 == start // 32):
            last = motifs[index]
            index += 1
        end = last + .5
        hits = sorted(b for b in hats if start <= b <= end)
        holds.append(dict(t=start, end=end, lane=1-kick_lane(start),
                          subs=hits[1:-1], reason='closed_hat_burst'))
        covered.update(hits)

    # The final sustained accompaniment can supply hold endpoints, whereas the
    # labelled vocal track's short, overlapping notes cannot establish a sung sustain.
    last_drum = max((n['beat'] for n in drums), default=-1)
    sustain = defaultdict(list)
    for n in events:
        if n['part'] != 'percussion' and n['track'] in (3, 4, 9) and n['velocity'] >= 70 and n['beat'] > last_drum:
            length = int(n['duration'] * bpm / 60 * 4) / 4
            if length >= 1:
                sustain[n['beat']].append(min(length, 8))
    sustain_onsets = sorted(sustain)
    for i, start in enumerate(sustain_onsets):
        end = min(start + max(sustain[start]), maximum)
        if i + 1 < len(sustain_onsets):
            end = min(end, sustain_onsets[i + 1] - .25)
        end = int(end * 4) / 4
        lane = 1-kick_lane(start)
        if end-start >= 1 and not any(h['lane'] == lane and start <= h['end'] and end >= h['t'] for h in holds):
            holds.append(dict(t=start, end=end, lane=lane, subs=[], reason='outro_sustain'))

    points = {}
    reasons = Counter()
    def put(beat, lane, kind, reason):
        key = (beat, lane)
        if key in points:
            return False
        points[key] = dict(t=beat, l=lane, k=kind)
        reasons[reason] += 1
        return True
    for hold in holds:
        put(hold['t'], hold['lane'], 'hold', hold['reason'])
        for beat in hold['subs']:
            put(beat, hold['lane'], 'tap', 'closed_hat_sub')
        put(hold['end'], hold['lane'], 'hold', hold['reason'])

    def occupied(beat, lane):
        return any(h['lane'] == lane and h['t'] <= beat <= h['end'] for h in holds)
    def tap(beat, lane, reason, move=False):
        if occupied(beat, lane):
            if not move or occupied(beat, 1-lane):
                return
            lane = 1-lane
        put(beat, lane, 'tap', reason)

    # Stable roles within an eight-bar phrase; simultaneous instruments collapse
    # to one point per lane. No random distribution or difficulty-dependent time shifts.
    for n in drums:
        if n['pitch'] in (35, 36):
            tap(n['beat'], kick_lane(n['beat']), 'kick', True)
    for n in drums:
        b, p = n['beat'], n['pitch']
        lane = kick_lane(b)
        if p in (37, 38, 39, 40):
            tap(b, lane, 'rim_clap', True)
        elif p == 42 and b not in covered and b * 2 == int(b * 2) and n['velocity'] >= 60:
            tap(b, 1-lane, 'closed_hat_single')
        elif p in (44, 46) and b not in hats and b * 2 == int(b * 2) and n['velocity'] >= 50:
            tap(b, 1-lane, 'open_hat')
        elif p in (49, 51, 52, 55, 57, 59) and b not in hats and n['velocity'] >= 85:
            tap(b, 1-lane, 'cymbal', True)
        elif p in (41, 43, 45, 47, 48, 50) and n['velocity'] >= 65:
            tap(b, lane ^ (int(b * 4) % 2), 'tom_fill', True)

    # In drum rests, take only strong vocal onsets on eighth-note positions.
    # Collapse chord doublings and discard faint echoes; never infer vocal holds.
    drum_bars = {int(n['beat']) // 4 for n in drums if n['velocity'] >= 40}
    melody = sorted({n['beat'] for n in events if n['part'] == 'vocal'
                     and n['velocity'] >= 110 and n['beat'] * 2 == int(n['beat'] * 2)
                     and int(n['beat']) // 4 not in drum_bars})
    for beat in melody:
        tap(beat, kick_lane(beat) ^ (int(beat * 2) % 2), 'rest_melody', True)
    return sorted(points.values(), key=lambda n: (n['t'], n['l'])), dict(
        holds=holds, point_reasons=dict(reasons), rejected=dict(rejected),
        source_events=len(source['notes']), eligible_drum_events=len(drums))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--name', default='baddapple_MIDI规则试验')
    parser.add_argument('--bpm', type=float, default=138)
    parser.add_argument('--offset-ms', type=float, default=79.13)
    parser.add_argument('--midi-origin-beat', type=float, default=4)
    parser.add_argument('--audio-id', default='bad_apple/bad_apple.ogg')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    library = ChartLibrary()
    identifier = library.new_path(args.audio_id, args.name)
    if library.path(identifier, must_exist=False).exists():
        raise SystemExit('工程已存在；请使用 --name 创建新工程，保留人工修改。')
    source = json.loads(args.source.read_text(encoding='utf-8-sig'))
    duration = audio_duration(library.path(args.audio_id, ('.ogg', '.wav')))
    points, report = arrange(source, args.bpm, args.offset_ms, args.midi_origin_beat, duration)
    metadata = library.metadata(dict(bpm=args.bpm, offset_ms=args.offset_ms, note_points=points))
    chart = dict(format_version=3, key_count=2, note_type='tap_hold',
                 project_name=args.name, title=source['title'], artist='Alstroemeria Records / nomico',
                 mapper='Codex（MIDI 规则生成）', difficulty='Normal / 规则试验',
                 audio_file=Path(args.audio_id).name,
                 remarks=f'底鼓与镲分层；闭镲三连合并长按＋Sub；8 小节换手。MIDI 第 {args.midi_origin_beat:g} 拍 → 编辑器第 0 拍，音频 {args.offset_ms:g} ms。来源：{source.get("source_midi", args.source.name)}。末尾长按来自伴奏持续音，非人声识别。')
    compiled = library.compile_beats(chart, metadata)
    validate(compiled, duration)
    result = library.save(identifier, chart, metadata, create=True)
    report.update(project_id=identifier, bpm=args.bpm, offset_ms=args.offset_ms,
                  midi_origin_beat=args.midi_origin_beat, metrics=metrics(result['chart']),
                  source_midi=source.get('source_midi'), source_json=str(args.source))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps(dict(project_id=identifier, metrics=report['metrics'], point_reasons=report['point_reasons']), ensure_ascii=False))


if __name__ == '__main__':
    main()
