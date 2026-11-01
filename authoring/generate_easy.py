"""Bad Apple drum-focused Easy draft with authored outro sustain anchors.

Requires numpy and soundfile. Do not regenerate over manual edits without --force.
The 138 BPM / 73 ms grid is shared with the audio-analyzed Normal draft.
Uses audio features and arrangement rules, never reference-chart note input.
"""
import argparse
import math
import numpy as np
import soundfile as sf
from author import SONG, read, write, validate, comparison


def generate(force=False):
    path = SONG / 'authored_easy.json'
    if path.exists() and not force:
        raise SystemExit('Easy 已存在；为保护人工编辑，仅 --force 可重新生成')
    audio, sr = sf.read(SONG / 'bad_apple.ogg', always_2d=True)
    mono = audio.mean(axis=1)[::2]
    rate = sr / 2
    frame, hop = 1024, 128
    windows = np.lib.stride_tricks.sliding_window_view(mono, frame)[::hop]
    spectrum = abs(np.fft.rfft(windows * np.hanning(frame), axis=1))
    frequencies = np.fft.rfftfreq(frame, 1/rate)
    times = (np.arange(len(windows))*hop + frame/2) / rate

    def band(lo, hi):
        # Positive energy changes suppress sustained melody; frequency bands are
        # drum proxies, not instrument transcription or source separation.
        power = np.sqrt((spectrum[:, (frequencies >= lo) & (frequencies < hi)]**2).mean(axis=1))
        flux = np.maximum(0, np.diff(power, prepend=power[0]))
        return flux / max(float(np.percentile(flux, 97)), 1e-8)

    low, high = band(35, 180), band(1800, 9000)
    analysis = read(SONG / 'authoring_analysis.json')
    beat = 60 / 138
    phase = analysis['offset_ms']/1000
    candidates = []
    for i in range(math.ceil((209-phase)/beat)):
        t = phase + i*beat
        if t < 2.0:
            continue  # Audio starts at zero; allow readable travel for the first note.
        mask = abs(times-t) < .045
        kick = float(np.max(low[mask], initial=0))
        snare = float(np.max(high[mask], initial=0))
        strength = max(kick, snare*.75)
        # Easy skeleton: half-note pulse, with isolated quarter notes for accents.
        # Include the intro from its first detected beat, not a fixed 14 s cutoff.
        if i % 2 == 0:
            keep = strength >= .32
        else:
            keep = strength >= 1.0 and i % 8 in (3, 7)
        if keep:
            candidates.append(dict(time_ms=round(t*1000, 3), beat=i,
                                   low=round(kick,3), high=round(snare,3)))
    # Add isolated high-frequency accents omitted by the half-note skeleton.
    used = {n['beat'] for n in candidates}
    for i in range(math.ceil((209-phase)/beat)):
        t = phase+i*beat
        if t < 2 or i in used or i % 4 != 1:
            continue
        mask = abs(times-t) < .045
        strength = float(np.max(high[mask], initial=0))
        if strength > 1.15:
            candidates.append(dict(time_ms=round(t*1000,3),beat=i,low=0,high=strength))
    candidates.sort(key=lambda n:n['time_ms'])
    # Stable musical roles instead of index-based left/right alternation.
    for n in candidates:
        n['lane'] = 1 if n['high']*.6 > n['low'] else 0
        n['duration'] = 0
    # Local eighth-note bursts, not continuous alternating streams. Pick one
    # strong offbeat per four-bar phrase and retain the ordinary drum roles.
    by_beat = {n['beat']: n for n in candidates}
    bursts = []
    for phrase in range(32, 432, 16):
        choices = []
        for i in range(phrase, phrase+14):
            if i not in by_beat or i+1 not in by_beat:
                continue
            t = phase+(i+.5)*beat
            mask = abs(times-t) < .035
            strength = max(float(np.max(low[mask], initial=0)),
                           float(np.max(high[mask], initial=0))*.75)
            if strength >= .5:
                choices.append((strength, i))
        if not choices:
            continue
        _, i = max(choices)
        lane = by_beat[i]['lane']
        by_beat[i]['burst'] = by_beat[i+1]['burst'] = True
        by_beat[i+1]['lane'] = lane
        candidates.append(dict(time_ms=round((phase+(i+.5)*beat)*1000,3),
                               beat=i+.5, low=0, high=0, lane=1-lane,
                               duration=0, burst=True))
        bursts.append(dict(start_ms=by_beat[i]['time_ms'],lanes=[lane,1-lane,lane]))
    candidates.sort(key=lambda n:n['time_ms'])
    # Sustained high-band energy suggests cymbal decay, not an instrument guarantee.
    high_power = np.sqrt((spectrum[:,frequencies>=3500]**2).mean(axis=1))
    last_hold = -10
    for index,n in enumerate(candidates):
        t=n['time_ms']/1000
        tail_power=float(np.mean(high_power[(times>t+.1)&(times<t+.4)]))
        if n.get('burst') or n['lane'] != 1 or n['high'] < .9 or t-last_hold < 8 or tail_power < np.percentile(high_power,55):
            continue
        next_same=next((v['time_ms']/1000 for v in candidates[index+1:] if v['lane']==1),999)
        length=2*beat if next_same-t>=3*beat else beat
        if next_same-t < length+.3:
            continue
        n['duration']=round(length*1000,3)
        last_hold=t
    # Authored outro phrase anchors on the shared audio grid. These represent
    # sustained melody/vocals rather than a claim of automatic vocal isolation.
    # The final held sound remains after the drums stop near 209 s and fades
    # around 215.5 s; the old 209 s candidate cutoff omitted it entirely.
    outro_holds = [(432,2,0), (440,2,1), (448,3,0), (456,2,1),
                   (464,2,0), (472,2,1), (476,2,0), (480,15.5,1)]
    for start, length, lane in outro_holds:
        head = round((phase+start*beat)*1000,3)
        duration = round(length*beat*1000,3)
        tail = head+duration
        # Replace the same-lane taps with a hold, with recovery on both sides;
        # avoid accidental chords at its head and keep the other hand playable.
        candidates = [n for n in candidates if
                      abs(n['time_ms']-head) > .01 and not
                      (n['lane']==lane and n['time_ms'] < tail+300 and
                       n['time_ms']+n['duration'] > head-300)]
        candidates.append(dict(time_ms=head,beat=start,lane=lane,duration=duration,outro=True))
    # Intro onset inspection: the fills at beats 3, 11, 19, 27 have four
    # sixteenth intervals (five attacks including the landing beat). Interleaved
    # fills use eighths. Preserve the sounding phrase, not an arbitrary NPS cap.
    # Begin at the first fill, leaving 1.377 s to read it after audio starts.
    intro_roles = {n['beat']:n['lane'] for n in candidates}
    intro_notes = {float(i): dict(time_ms=round((phase+i*beat)*1000,3),
                   beat=i,lane=intro_roles.get(i,0),duration=0) for i in range(3,33)}
    intro_runs = []
    for group, start in enumerate(range(3,32,4)):
        count = 5 if group%2 == 0 else 3
        step = 1/(count-1)
        first_lane = (group//2)%2
        for j in range(count):
            position = start+j*step
            intro_notes[position] = dict(time_ms=round((phase+position*beat)*1000,3),
                                        beat=position,lane=(first_lane+j)%2,duration=0)
        intro_runs.append(dict(start_ms=round((phase+start*beat)*1000,3),
                               count=count,interval_ms=round(step*beat*1000,3),
                               lanes=[(first_lane+j)%2 for j in range(count)]))
    intro_end = round((phase+32*beat)*1000,3)
    candidates = [n for n in candidates if n['time_ms'] > intro_end]
    candidates.extend(intro_notes.values())
    candidates.sort(key=lambda n:n['time_ms'])
    for n in candidates:
        # One automatic sub per beat; short one-beat holds get a midpoint.
        # Keep a half-beat margin at both ends, avoiding a tail/sub double hit.
        length = n['duration']
        offsets = np.arange(beat*1000, length-beat*500+.01, beat*1000)
        if length and not len(offsets):
            offsets = [length/2]
        n['subs'] = [round(n['time_ms']+float(v),3) for v in offsets]
    chart = dict(format_version=3,key_count=2,note_type='tap_hold',title='Bad Apple!!',
                 artist='Alstroemeria Records',difficulty='Author Easy / Drums + Intro',
                 audio_file='bad_apple.ogg',mapper='Codex assisted drum-band Easy arrangement',
                 notes_ms=[n['time_ms'] for n in candidates],lanes=[n['lane'] for n in candidates],
                 durations_ms=[n['duration'] for n in candidates],subs_ms=[n['subs'] for n in candidates])
    validate(chart,len(audio)/sr)
    write(path,chart)
    write(SONG/'authoring_easy_meta.json',dict(bpm=138,offset_ms=analysis['offset_ms']))
    report = comparison(chart)
    report['previous_draft'] = comparison(read(SONG/'authored.json'))['draft']
    report['intro_heads_before_14s'] = sum(t<14000 for t in chart['notes_ms'])
    report['method'] = 'Intro onset-aligned five-hit sixteenth runs and three-hit eighth runs without an NPS cap; later drum/cymbal roles, automatic hold subs and sustained outro phrases. Holds reserve 300ms same-lane recovery.'
    report['bursts'] = bursts
    report['intro_runs'] = intro_runs
    report['outro_holds'] = [dict(start_ms=n['time_ms'],end_ms=round(n['time_ms']+n['duration'],3),lane=n['lane']) for n in candidates if n.get('outro')]
    write(SONG/'authoring_easy_comparison.json',report)
    print({'metrics':report['draft'],'intro_heads':report['intro_heads_before_14s'],
           'intro_times_ms':[t for t in chart['notes_ms'] if t<14000]})


if __name__ == '__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--force',action='store_true')
    generate(parser.parse_args().force)
