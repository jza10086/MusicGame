"""Offline chart validation, analysis and draft generation helpers."""
import argparse
import json
import math
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
GAME = ROOT.parent
SONG = GAME / 'charts/bad_apple'
CHART = SONG / 'authored.json'
ANALYSIS = SONG / 'authoring_analysis.json'
META = SONG / 'authoring_meta.json'
REFERENCES = {'Easy': 'chart.json', 'Normal': 'normal.json', 'Hard': 'hard.json'}


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
    temporary.replace(path)


def validate(chart, duration, allow_empty=False):
    if not isinstance(chart, dict):
        raise ValueError('谱面必须是 JSON 对象')
    if chart.get('format_version') != 3 or type(chart.get('key_count')) is not int or chart['key_count'] not in (2, 4) or chart.get('note_type') != 'tap_hold':
        raise ValueError('仅支持版本 3 的 2K / 4K tap_hold')
    audio = chart.get('audio_file')
    if not isinstance(audio, str) or not audio or any(c in audio for c in ('/', '\\', ':', '..')) or Path(audio).suffix.lower() not in ('.ogg', '.wav'):
        raise ValueError('音源必须是谱面目录内的 OGG / WAV 文件名')
    for key in ('title', 'artist', 'difficulty'):
        if not isinstance(chart.get(key), str) or not chart[key].strip():
            raise ValueError('缺少 ' + key)
    arrays = [chart.get(k) for k in ('notes_ms', 'lanes', 'durations_ms', 'subs_ms')]
    if any(not isinstance(a, list) for a in arrays) or not (0 if allow_empty else 1) <= len(arrays[0]) <= 100000 or any(len(a) != len(arrays[0]) for a in arrays):
        raise ValueError('音符数组长度不一致或为空')
    end = [-math.inf] * chart['key_count']
    previous = (-math.inf, -1)
    for t, lane, length, subs in zip(*arrays):
        if any(type(v) not in (int, float) or not math.isfinite(v) for v in (t, lane, length)):
            raise ValueError('时间和轨道必须为有限数值')
        if lane not in range(chart['key_count']) or length < 0 or (t, lane) <= previous:
            raise ValueError('音符必须按时间、轨道排序且不可重复')
        lane = int(lane)
        if t <= end[lane] or (t + length) / 1000 + .15 >= duration:
            raise ValueError('同轨重叠、共用长按尾部，或超过音源范围')
        if not isinstance(subs, list) or len(subs) > 4096:
            raise ValueError('sub 数组无效')
        last = t
        for sub in subs:
            if type(sub) not in (int, float) or not math.isfinite(sub) or not last < sub < t + length:
                raise ValueError('sub 必须严格递增且在头尾之间')
            last = sub
        previous = (t, lane)
        end[lane] = t + length

    sounds = chart.get('hit_sounds', [])
    if not isinstance(sounds, list) or len(sounds) > 300000:
        raise ValueError('谱面音效数组无效')
    points = {(round(at * 1000), lane) for t, lane, length, subs in zip(*arrays)
              for at in [t, t + length, *subs]}
    seen = set()
    for sound in sounds:
        if (not isinstance(sound, dict) or type(sound.get('time_ms')) not in (int, float)
                or not math.isfinite(sound['time_ms']) or type(sound.get('lane')) is not int
                or not isinstance(sound.get('sound'), str) or not sound['sound'].isidentifier()
                or len(sound['sound']) > 64):
            raise ValueError('谱面音效字段无效')
        key = (round(sound['time_ms'] * 1000), sound['lane'])
        if key not in points or key in seen:
            raise ValueError('谱面音效必须对应唯一音符节点')
        seen.add(key)


def metrics(chart):
    times = chart['notes_ms']
    lengths = chart['durations_ms']
    subs = sum(map(len, chart['subs_ms']))
    holds = sum(d > 0 for d in lengths)
    by_lane = [[t for t, lane in zip(times, chart['lanes']) if lane == k] for k in (0, 1)]
    peak = 0
    left = 0
    for right, t in enumerate(times):
        while times[left] <= t - 1000:
            left += 1
        peak = max(peak, right - left + 1)
    gaps = [b - a for lane in by_lane for a, b in zip(lane, lane[1:])]
    return dict(heads=len(times), taps=len(times)-holds, holds=holds, subs=subs,
                units=len(times)+holds+subs, left=len(by_lane[0]), right=len(by_lane[1]),
                chords=sum(a == b for a, b in zip(times, times[1:])), peak_heads_per_second=peak,
                minimum_same_lane_head_gap_ms=round(min(gaps), 1) if gaps else None,
                first_ms=times[0], last_ms=max(t+d for t, d in zip(times, lengths)))


def comparison(chart):
    result = {'draft': metrics(chart), 'references': {}}
    times = chart['notes_ms']
    for name, filename in REFERENCES.items():
        ref = read(SONG / filename)
        distances = [min(abs(t-r) for r in ref['notes_ms']) for t in times]
        result['references'][name] = dict(metrics=metrics(ref),
            draft_heads_near_reference_25ms=sum(d <= 25 for d in distances),
            median_nearest_head_distance_ms=round(statistics.median(distances), 2))
    result['bins'] = [dict(start_s=s, draft=sum(s*1000 <= t < (s+8)*1000 for t in times),
                          **{name: sum(s*1000 <= t < (s+8)*1000 for t in read(SONG/f)['notes_ms'])
                             for name, f in REFERENCES.items()}) for s in range(0, 224, 8)]
    return result


def generate():
    import numpy as np
    import soundfile as sf
    audio, sr = sf.read(SONG / 'bad_apple.ogg', always_2d=True)
    mono = audio.mean(axis=1)[::4]
    rate = sr / 4
    hop, frame = 128, 1024
    windows = np.lib.stride_tricks.sliding_window_view(mono, frame)[::hop]
    spectrum = abs(np.fft.rfft(windows * np.hanning(frame), axis=1))
    flux = np.maximum(0, np.diff(np.log1p(spectrum), axis=0)).sum(axis=1)
    flux = np.concatenate(([0], flux))
    flux /= max(float(np.percentile(flux, 95)), .0001)
    times = (np.arange(len(flux))*hop + frame/2) / rate
    # Tempo is an explicit musical prior. Offset is fitted against audio onset flux.
    bpm = 138.0
    beat = 60 / bpm
    mask = (times > 14) & (times < 200)
    phases = np.arange(0, beat, .001)
    strength = [float(np.sum(flux[mask] * np.exp(-.5 * (((times[mask]-p+beat/2) % beat-beat/2)/.018)**2))) for p in phases]
    phase = float(phases[int(np.argmax(strength))])
    # Spectral windows localize onsets late; retain raw estimate visibly, no player calibration baked in.
    first = phase + math.ceil((13.8-phase)/beat)*beat
    def energy(t):
        return float(np.max(flux[np.abs(times-t) < .045], initial=0))
    notes = []
    occupied = [-1., -1.]
    for bar in range(math.ceil((209-first)/(beat*4))):
        start = first + bar*4*beat
        phrase = bar // 8
        # Repeat a rhythmic motif across a phrase; use audio strength to admit offbeats.
        for slot in range(8):
            t = start + slot*beat/2
            if t > 209:
                continue
            e = energy(t)
            if slot % 2 and e < (.72 if phrase % 3 == 1 else 1.05):
                continue
            if slot % 2 == 0 and e < .25:
                continue
            lane = (slot//2 + bar%2 + phrase) % 2 if slot%2 == 0 else (slot//2 + bar%2 + phrase + 1)%2
            if t < occupied[lane] + .17:
                lane = 1-lane
            if t < occupied[lane] + .17:
                continue
            duration = 0.
            sub = []
            # Explicit authored phrase motif, not a claim of automatic sustain transcription.
            if bar % 8 in (2, 6) and slot == 0:
                duration = beat * (3 if bar % 8 == 2 else 2)
                sub = [t + k*beat/2 for k in range(1, round(duration/beat*2)) if energy(t+k*beat/2) > .3]
            notes.append((round(t*1000, 3), lane, round(duration*1000, 3), [round(s*1000, 3) for s in sub]))
            occupied[lane] = t + duration
            other = 1-lane
            if bar % 8 == 7 and slot == 6 and e > .8 and t > occupied[other] + .25:
                notes.append((round(t*1000, 3), other, 0., []))
                occupied[other] = t
    notes.sort()
    chart = dict(format_version=3, key_count=2, note_type='tap_hold', title='Bad Apple!!',
                 artist='Alstroemeria Records', difficulty='Author Draft / Normal', audio_file='bad_apple.ogg',
                 mapper='Codex assisted audio-feature draft; human refinement pending',
                 notes_ms=[n[0] for n in notes], lanes=[n[1] for n in notes], durations_ms=[n[2] for n in notes], subs_ms=[n[3] for n in notes])
    duration = len(audio)/sr
    validate(chart, duration)
    # Small peak envelope for editor rendering; no full PCM stored in source control.
    stride = max(1, len(mono)//5000)
    wave = [round(float(np.max(abs(mono[i:i+stride]))), 4) for i in range(0,len(mono),stride)]
    analysis = dict(duration=duration, bpm=bpm, offset_ms=round(phase*1000, 3), waveform=wave,
                    onset_times_ms=[round(float(t)*1000, 2) for i,t in enumerate(times[1:-1],1)
                                    if flux[i] > .65 and flux[i] > flux[i-1] and flux[i] >= flux[i+1]],
                    method='Log spectral flux; 138 BPM prior; audio-only phase fit; phrase-based two-key arrangement. No reference notes used.')
    write(CHART, chart)
    write(ANALYSIS, analysis)
    write(META, dict(bpm=bpm, offset_ms=analysis['offset_ms']))
    report = comparison(chart)
    write(SONG / 'authoring_comparison.json', report)
    print(json.dumps(dict(analysis={k:v for k,v in analysis.items() if k not in ('waveform','onset_times_ms')}, comparison=report), ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Generate an offline Bad Apple draft')
    parser.add_argument('--force', action='store_true', help='Explicitly replace manually edited draft')
    args = parser.parse_args()
    if CHART.exists() and not args.force:
        sys.exit('已有初稿；为保护人工修改，重新生成须显式指定 --force')
    generate()
