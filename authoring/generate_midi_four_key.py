"""Offline MIDI-to-4K arrangement with representative WAV hitsounds.

Uses mido only during authoring. MIDI tempo is integrated before mapping to the
recording; playback still consumes ordinary millisecond chart events.
"""
from collections import defaultdict, deque, Counter
from pathlib import Path
import argparse
import itertools
import json
import math


def read_midi(path):
    import mido
    midi = mido.MidiFile(path)
    rows = []
    for track, messages in enumerate(midi.tracks):
        tick = 0
        for order, message in enumerate(messages):
            tick += message.time
            rows.append((tick, track, order, message))
    rows.sort(key=lambda row: row[:3])
    programs, volumes = [0] * 16, [127] * 16
    active = defaultdict(deque)
    notes, tempos = [], []
    tick, seconds, tempo = 0, 0.0, 500000
    for next_tick, track, order, msg in rows:
        seconds += mido.tick2second(next_tick - tick, midi.ticks_per_beat, tempo)
        tick = next_tick
        if msg.type == 'set_tempo':
            tempo = msg.tempo
            if not tempos or tempos[-1]['tempo'] != tempo:
                tempos.append(dict(tick=tick, time=seconds, tempo=tempo))
        elif msg.type == 'program_change':
            programs[msg.channel] = msg.program
        elif msg.type == 'control_change' and msg.control == 7:
            volumes[msg.channel] = msg.value
        elif msg.type == 'note_on' and msg.velocity:
            note = dict(tick=tick, time=seconds, end=seconds, track=track,
                        channel=msg.channel, program=programs[msg.channel], pitch=msg.note,
                        velocity=msg.velocity, volume=volumes[msg.channel])
            notes.append(note)
            active[(msg.channel, msg.note)].append(note)
        elif msg.type in ('note_off', 'note_on'):
            queue = active[(msg.channel, msg.note)]
            if queue:
                queue.popleft()['end'] = seconds
    for queue in active.values():
        for note in queue:
            note['end'] = seconds
    return dict(ppq=midi.ticks_per_beat, duration=seconds, tempos=tempos, notes=notes)


def arrange(data, catalog, repeat_at=480, repeat_length=32):
    """Quantize to the editor's 1/64 grid; cap only simultaneous voices, not density.

    The album has an extra eight-bar repeated phrase before MIDI beat 480.
    Copy the preceding phrase and shift subsequent source events, never stretch audio.
    """
    by_program = defaultdict(list)
    for sample in catalog['samples']:
        if sample['bank'] == 0:
            by_program[sample['program']].append(sample)
    drums = {35:'kick',36:'kick',37:'cross_stick',38:'snare',40:'snare',
             41:'low_tom',43:'low_tom',45:'low_tom',47:'high_tom',48:'high_tom',50:'high_tom',
             42:'closed_hat',44:'pedal_hat',46:'open_hat',49:'crash',52:'crash',55:'crash',57:'crash',
             51:'ride',59:'ride',53:'ride_bell'}
    groups = defaultdict(list)
    stats = Counter()
    for note in data['notes']:
        if note['volume'] == 0:
            stats['muted_source_events'] += 1
            continue
        source_beat = note['tick'] / data['ppq']
        destinations = [source_beat + (repeat_length if source_beat >= repeat_at else 0)]
        if repeat_at-repeat_length <= source_beat < repeat_at:
            destinations.append(source_beat+repeat_length)
            stats['inserted_repeat_source_events'] += 1
        if note['channel'] == 9:
            pitch = note['pitch']
            sound = 'drum_' + drums[pitch] if pitch in drums else f'gm_perc_{pitch}'
            if pitch not in drums and not any(s['id']==sound for s in catalog['samples']):
                stats['unsupported_percussion'] += 1
                continue
            priority = 115 if pitch in (35,36) else 110 if pitch in (37,38,39,40) else 94 if pitch in (49,52,55,57) else 85
            role = 0 if pitch in (35,36,41,43,45) else 1
        else:
            variants = by_program[note['program']]
            if not variants:
                stats['unsupported_program'] += 1
                continue
            sample = min(variants, key=lambda s: (abs(s['key']-note['pitch']), s['key']))
            sound = sample['id']
            program = note['program']
            priority = 102 if program<8 else 89 if 64<=program<80 else 80 if 32<=program<40 else 76 if 24<=program<32 else 48
            role = (2 if note['pitch']<67 else 3) if program<8 else 0 if 32<=program<40 else 3
        score = priority + 5 * note['velocity']/127 + note['volume']/127
        for beat in destinations:
            snapped = round(beat*16)/16
            groups[snapped].append(dict(sound=sound, priority=score, role=role, pitch=note['pitch'], track=note['track']))
    points = []
    last_time = [-math.inf]*4
    last_sound = ['']*4
    selected_sounds = Counter()
    source_tracks = Counter()
    for beat, events in sorted(groups.items()):
        unique = {}
        for event in events:
            if event['sound'] not in unique or event['priority'] > unique[event['sound']]['priority']:
                unique[event['sound']] = event
        stats['duplicate_representative_sounds'] += len(events)-len(unique)
        chosen = sorted(unique.values(), key=lambda e: (-e['priority'], e['sound']))[:4]
        stats['over_capacity_sounds'] += max(0,len(unique)-4)
        stats['over_capacity_positions'] += len(unique)>4
        def cost(lanes):
            total=0
            for event,lane in zip(chosen,lanes):
                gap=beat-last_time[lane]
                total += abs(lane-event['role'])*.6 + (8 if gap<.125 else 2 if gap<.25 else 0)
                total -= .25 if last_sound[lane]==event['sound'] else 0
            return total,lanes
        lanes=min(itertools.permutations(range(4),len(chosen)),key=cost)
        for event,lane in zip(chosen,lanes):
            points.append(dict(t=beat,l=lane,k='tap',sound=event['sound']))
            last_time[lane]=beat;last_sound[lane]=event['sound']
            selected_sounds[event['sound']]+=1;source_tracks[event['track']]+=1
    points.sort(key=lambda n:(n['t'],n['l']))
    return points,dict(stats,source_events=len(data['notes']),selected_sounds=dict(selected_sounds),selected_source_tracks=dict(source_tracks))


def main():
    from chart_library import ChartLibrary, audio_duration
    from author import validate
    game=Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--inspect', type=Path)
    parser.add_argument('--audio-id', default='bad_apple_full/bad_apple_full.ogg')
    parser.add_argument('--name', default='BadApple_完整版_MIDI_4K')
    parser.add_argument('--offset-ms', type=float, default=1308.0)
    parser.add_argument('--repeat-at', type=float, default=480)
    parser.add_argument('--repeat-length', type=float, default=32)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    data = read_midi(args.source)
    if args.inspect:
        args.inspect.write_text(json.dumps(data, ensure_ascii=False), encoding='utf-8')
        print(json.dumps({k:v for k,v in data.items() if k!='notes'}))
        return
    if len(data['tempos'])!=1 or abs(60000000/data['tempos'][0]['tempo']-138)>.01:
        raise ValueError('This arrangement expects the supplied constant-138-BPM MIDI')
    catalog=json.loads((game/'assets/audio_candidates/fluid_r3/samples.json').read_text(encoding='utf8'))
    points,report=arrange(data,catalog,args.repeat_at,args.repeat_length)
    library=ChartLibrary()
    identifier=library.new_path(args.audio_id,args.name)
    if library.path(identifier,must_exist=False).exists():
        raise ValueError('工程已存在；请换一个 --name，保留人工修改')
    metadata=library.metadata(dict(bpm=138,offset_ms=args.offset_ms,note_points=points),4)
    chart=dict(format_version=3,key_count=4,note_type='tap_hold',project_name=args.name,
               title='Bad Apple!! feat. nomico（完整版）',artist='Alstroemeria Records / nomico',
               mapper='Codex（用户提供 MIDI 编排）',difficulty='Unlimited',
               audio_file=Path(args.audio_id).name,
               remarks=f'全单击，无密度上限。同刻最多四种代表音效，鼓与钢琴优先；1/64 网格。BPM 138，起点 {args.offset_ms:g} ms。原 MIDI 第 {args.repeat_at:g} 拍前补入之前 {args.repeat_length:g} 拍的重复乐句以匹配专辑完整版，之后顺延。每个音符保留器乐音效 ID，非完整音高还原。')
    compiled=library.compile_beats(chart,metadata)
    duration=audio_duration(library.path(args.audio_id,('.ogg','.wav')))
    validate(compiled,duration)
    library.save(identifier,chart,metadata,create=True)
    times=compiled['notes_ms'];counts=Counter(compiled['lanes']);chords=Counter(Counter(times).values())
    left=0;peak=0
    for right,t in enumerate(times):
        while times[left]<=t-1000:left+=1
        peak=max(peak,right-left+1)
    report.update(project=identifier,bpm=138,offset_ms=args.offset_ms,audio_duration=duration,
                  repeat_at=args.repeat_at,repeat_length=args.repeat_length,taps=len(times),holds=0,
                  lanes=dict(counts),chord_sizes=dict(chords),peak_notes_per_second=peak,first_ms=times[0],last_ms=times[-1])
    if args.report:args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
