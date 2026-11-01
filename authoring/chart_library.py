"""Offline chart library for generation tools. Audio stays beside charts; deletion moves to recovery.

Only current v3 2K/4K charts are editable. Empty charts are valid editor drafts, but
the game only discovers playable charts. Revisions use file metadata, not hashes.
"""
import json
import math
import re
import struct
import threading
import uuid
from datetime import datetime
from pathlib import Path

from author import GAME, read, write, validate
from project_paths import find_project_root


def audio_duration(path):
    """Read WAV/Vorbis timing headers without a decoder or file checksums."""
    with path.open('rb') as source:
        if path.suffix.lower() == '.wav':
            header = source.read(12)
            if header[:4] != b'RIFF' or header[8:] != b'WAVE':
                raise ValueError('不支持此 WAV 容器')
            rate = 0
            data_size = 0
            while chunk := source.read(8):
                if len(chunk) != 8:
                    raise ValueError('WAV 块不完整')
                length = struct.unpack('<I', chunk[4:])[0]
                if chunk[:4] == b'fmt ':
                    fmt = source.read(length)
                    if len(fmt) < 16:
                        raise ValueError('WAV 格式头不完整')
                    rate = struct.unpack_from('<I', fmt, 8)[0]
                else:
                    if chunk[:4] == b'data':
                        data_size += length
                    source.seek(length, 1)
                if length % 2:
                    source.seek(1, 1)
            if rate and data_size:
                return data_size / rate
        else:
            rate = 0
            serial = None
            granule = 0
            while header := source.read(27):
                if len(header) != 27 or header[:4] != b'OggS':
                    raise ValueError('OGG 页面不完整')
                segments = source.read(header[26])
                body = source.read(sum(segments))
                page_serial = header[14:18]
                if body.startswith(b'\x01vorbis') and len(body) >= 16:
                    serial = page_serial
                    rate = struct.unpack_from('<I', body, 12)[0]
                position = struct.unpack_from('<Q', header, 6)[0]
                if page_serial == serial and position != 0xffffffffffffffff:
                    granule = max(granule, position)
            if rate and granule:
                return granule / rate
    raise ValueError('无法读取音源时长；支持 WAV 和 Vorbis OGG')


class Conflict(ValueError):
    pass


class ChartLibrary:
    def __init__(self, root=None, recovery=None):
        self.root = Path(root or GAME / 'charts').resolve()
        self.recovery = Path(recovery or find_project_root() / 'tmp/rhythm_chart_trash').resolve()
        self.lock = threading.RLock()

    def project_name(self, name):
        if not isinstance(name, str) or not name or name != name.strip() or len(name) > 80:
            raise ValueError('工程名须为 1–80 个字符，首尾不能为空格')
        if re.search(r'[<>:"/\\|?*\x00-\x1f]', name) or name.startswith('.') or name.endswith('.'):
            raise ValueError('工程名不能包含路径符号、控制字符或首尾句点')
        if name.lower().endswith('.json'):
            raise ValueError('工程名不需要填写 .json 后缀')
        if name.split('.')[0].lower() in {'con', 'prn', 'aux', 'nul', *[f'com{i}' for i in range(10)], *[f'lpt{i}' for i in range(10)]}:
            raise ValueError('此工程名为系统保留名称，请换一个名称')
        return name

    def document(self, chart, name):
        """One filename identity and six author-facing fields; preserve runtime/provenance data."""
        result = dict(chart, project_name=self.project_name(name))
        for key, limit in [('title', 200), ('artist', 200), ('mapper', 200), ('difficulty', 80), ('remarks', 4000)]:
            value = result.get(key, '')
            if not isinstance(value, str) or len(value) > limit:
                raise ValueError(f'{key} 须为不超过 {limit} 字符的文本')
            result[key] = value.strip()
        return result

    def path(self, identifier, suffixes=('.json',), must_exist=True):
        if not isinstance(identifier, str) or not identifier or '\\' in identifier or ':' in identifier:
            raise ValueError('库内路径无效')
        parts = identifier.split('/')
        if any(not p or p.startswith('.') for p in parts):
            raise ValueError('不可访问谱面库以外的路径')
        path = (self.root / identifier).resolve()
        if not path.is_relative_to(self.root) or path.suffix.lower() not in suffixes:
            raise ValueError('路径或文件类型无效')
        if must_exist and not path.is_file():
            raise ValueError('文件不存在，请刷新谱面库')
        return path

    def revision(self, path):
        stat = path.stat()
        return f'{stat.st_mtime_ns}:{stat.st_size}'

    def audio_path(self, chart_path, chart):
        # Validate the basename before joining it to an otherwise trusted folder.
        if not isinstance(chart, dict):
            raise ValueError('谱面必须是 JSON 对象')
        name = chart.get('audio_file')
        if not isinstance(name, str) or not name or any(c in name for c in ('/', '\\', ':', '..')):
            raise ValueError('音源须放在谱面同目录')
        identifier = (chart_path.parent / name).relative_to(self.root).as_posix()
        return self.path(identifier, ('.wav', '.ogg'))

    def chart(self, identifier):
        path = self.path(identifier)
        stored = read(path)
        if not isinstance(stored, dict):
            raise ValueError('谱面必须是 JSON 对象')
        chart = self.document(stored, stored.get('project_name', path.stem))
        audio = self.audio_path(path, chart)
        duration = audio_duration(audio)
        validate(chart, duration, allow_empty=True)
        metadata = chart.get('editor', {})
        if not metadata:
            # Existing analysis/provenance is only an initial grid suggestion.
            source = path.with_name(path.stem + '_source.json')
            analysis = path.parent / 'authoring_analysis.json'
            candidate = read(source) if source.exists() else (read(analysis) if analysis.exists() else {})
            metadata = {k: candidate.get(k, default) for k, default in [('bpm', 120), ('offset_ms', 0)]}
        analysis = {'waveform': [], 'onset_times_ms': [], 'duration': duration}
        reference_analysis = path.parent / 'authoring_analysis.json'
        if reference_analysis.exists() and chart['audio_file'] == 'bad_apple.ogg':
            analysis.update(read(reference_analysis))
        return dict(id=identifier, chart=chart, metadata=self.metadata(metadata, chart['key_count']), analysis=analysis,
                    audio_id=audio.relative_to(self.root).as_posix(), revision=self.revision(path))

    def list(self):
        charts, audios = [], []
        for path in sorted(self.root.rglob('*')):
            identifier = path.relative_to(self.root).as_posix()
            if any(part.startswith('.') for part in path.relative_to(self.root).parts) or not path.is_file():
                continue
            if path.suffix.lower() in ('.ogg', '.wav'):
                try:
                    self.path(identifier, ('.ogg', '.wav'))
                    audios.append(dict(id=identifier, name=identifier))
                except ValueError:
                    continue
            elif path.suffix.lower() == '.json':
                try:
                    self.path(identifier)
                    data = read(path)
                    if not isinstance(data, dict) or data.get('format_version') != 3 or data.get('key_count') not in (2, 4):
                        continue
                    charts.append(dict(id=identifier, project_name=data.get('project_name', path.stem), title=str(data.get('title', '')), artist=str(data.get('artist', '')),
                                       difficulty=str(data.get('difficulty', '')), heads=len(data.get('notes_ms', [])),
                                       audio_id=(path.parent / data.get('audio_file', '')).relative_to(self.root).as_posix()))
                except (ValueError, TypeError, OSError):
                    continue
        return dict(charts=charts, audios=audios)

    def project(self, identifier):
        with self.lock:
            result = self.chart(identifier)
            references = {}
            for entry in self.list()['charts']:
                if entry['id'] != identifier and entry['audio_id'] == result['audio_id']:
                    try:
                        references[entry['id']] = self.chart(entry['id'])['chart']
                    except (ValueError, OSError):
                        continue
            result['references'] = references
            return result

    def metadata(self, meta, key_count=2):
        if type(key_count) is not int or key_count not in (2, 4):
            raise ValueError('键数只能为 2 或 4')
        bpm, offset = float(meta['bpm']), float(meta['offset_ms'])
        if not math.isfinite(bpm) or not 30 <= bpm <= 400 or not math.isfinite(offset):
            raise ValueError('BPM 必须为 30–400，网格起点必须为有限数值')
        result = dict(bpm=bpm, offset_ms=offset)
        if 'beat_notes' in meta:
            notes = meta['beat_notes']
            if not isinstance(notes, list) or len(notes) > 100000:
                raise ValueError('拍数音符数组无效')
            clean = []
            for note in notes:
                if not isinstance(note, dict) or not all(k in note for k in ('t', 'l', 'd', 's')):
                    raise ValueError('拍数音符字段不完整')
                if not isinstance(note['s'], list) or len(note['s']) > 4096:
                    raise ValueError('拍数 sub 数组无效')
                if any(type(v) not in (int, float) or not math.isfinite(v) for v in [note['t'], note['l'], note['d'], *note['s']]):
                    raise ValueError('拍数必须为有限数值')
                if note['l'] not in range(key_count) or note['d'] < 0:
                    raise ValueError('音符轨道或长度无效')
                normalized = dict(t=note['t'], l=int(note['l']), d=note['d'], s=list(note['s']))
                for key in ('sound', 'end_sound'):
                    if note.get(key):
                        normalized[key] = self.sound_id(note[key])
                if 'sub_sounds' in note:
                    if not isinstance(note['sub_sounds'], list) or len(note['sub_sounds']) != len(note['s']):
                        raise ValueError('Sub 音效数量不一致')
                    normalized['sub_sounds'] = [self.sound_id(s) for s in note['sub_sounds']]
                clean.append(normalized)
            result['beat_notes'] = clean
        if 'note_points' in meta:
            points = meta['note_points']
            if not isinstance(points, list) or len(points) > 300000:
                raise ValueError('编辑点数组无效')
            clean = []
            for point in points:
                if (not isinstance(point, dict) or type(point.get('t')) not in (int, float)
                        or not math.isfinite(point['t']) or type(point.get('l')) is not int
                        or point['l'] not in range(key_count) or point.get('k') not in ('tap', 'hold')):
                    raise ValueError('编辑点字段无效')
                normalized = dict(t=point['t'], l=point['l'], k=point['k'])
                if point.get('sound'):
                    normalized['sound'] = self.sound_id(point['sound'])
                clean.append(normalized)
            previous = [-math.inf] * key_count
            for point in sorted(clean, key=lambda p: p['t']):
                if point['t'] - previous[point['l']] < 1e-5:
                    raise ValueError('同轨同拍只能有一个编辑点')
                previous[point['l']] = point['t']
            result['note_points'] = clean
            result['beat_notes'] = self.pair_points(clean)
        return result

    @staticmethod
    def sound_id(value):
        if not isinstance(value, str) or len(value) > 64 or value and not value.isidentifier():
            raise ValueError('音效 ID 无效')
        return value

    @staticmethod
    def pair_points(points):
        """Pair chronological endpoints per lane; retain raw points separately from playable notes."""
        notes = []
        for lane in sorted({p['l'] for p in points}):
            holds = sorted((p for p in points if p['l'] == lane and p['k'] == 'hold'), key=lambda p: p['t'])
            pairs = []
            for a, b in zip(holds[::2], holds[1::2]):
                note = dict(t=a['t'], l=lane, d=b['t']-a['t'], s=[])
                if a.get('sound'): note['sound'] = a['sound']
                if b.get('sound'): note['end_sound'] = b['sound']
                pairs.append(note)
            notes.extend(pairs)
            index = 0
            for point in sorted((p for p in points if p['l'] == lane and p['k'] == 'tap'), key=lambda p: p['t']):
                tap = point['t']
                while index < len(pairs) and tap > pairs[index]['t'] + pairs[index]['d'] + 1e-8:
                    index += 1
                note = pairs[index] if index < len(pairs) else None
                if note is None or tap < note['t'] - 1e-8:
                    note = dict(t=tap, l=lane, d=0, s=[])
                    if point.get('sound'): note['sound'] = point['sound']
                    notes.append(note)
                elif note['t'] + 1e-8 < tap < note['t'] + note['d'] - 1e-8:
                    if point.get('sound') or 'sub_sounds' in note:
                        note.setdefault('sub_sounds', [''] * len(note['s'])).append(point.get('sound', ''))
                    note['s'].append(tap)
        return sorted(notes, key=lambda n: (n['t'], n['l']))

    def compile_beats(self, chart, metadata):
        """Persist exact editor beats and derive the game's unchanged millisecond schema."""
        if 'beat_notes' not in metadata:
            return chart
        result = dict(chart, notes_ms=[], lanes=[], durations_ms=[], subs_ms=[])
        result.pop('hit_sounds', None)
        sounds = []
        unit = 60000 / metadata['bpm']
        def ms(beat):
            return round(metadata['offset_ms'] + beat * unit, 3)
        for note in sorted(metadata['beat_notes'], key=lambda n: (n['t'], n['l'])):
            result['notes_ms'].append(ms(note['t']))
            result['lanes'].append(note['l'])
            result['durations_ms'].append(round(note['d'] * unit, 3))
            result['subs_ms'].append([ms(b) for b in note['s']])
            points = [(note['t'], note.get('sound', ''))]
            if note['d']:
                points.append((note['t'] + note['d'], note.get('end_sound', '')))
            points.extend(zip(note['s'], note.get('sub_sounds', [])))
            sounds.extend(dict(time_ms=ms(t), lane=note['l'], sound=s) for t, s in points if s)
        if sounds:
            result['hit_sounds'] = sorted(sounds, key=lambda s: (s['time_ms'], s['lane']))
        return result

    def save(self, identifier, chart, metadata, revision=None, create=False):
        with self.lock:
            path = self.path(identifier, must_exist=not create)
            if create and path.exists():
                raise Conflict('文件名已存在，请换一个名称；另存为不会覆盖已有谱面')
            if not create and self.revision(path) != revision:
                raise Conflict('谱面已被其他窗口或程序修改，请重新打开或另存为')
            if not create:
                self.chart(identifier)  # Never overwrite an analysis/provenance JSON.
            audio = self.audio_path(path, chart)
            metadata = self.metadata(metadata, chart.get('key_count'))
            chart = self.compile_beats(chart, metadata)
            duration = audio_duration(audio)
            for point in metadata.get('note_points', []):
                seconds = metadata['offset_ms'] / 1000 + point['t'] * 60 / metadata['bpm']
                if seconds + .15 >= duration:
                    raise ValueError('编辑点超出音源范围')
            validate(chart, duration, allow_empty=True)
            name = self.project_name(chart['project_name'])
            target_id = self.new_path(audio.relative_to(self.root).as_posix(), name)
            target = self.path(target_id, must_exist=False)
            if create and target_id != identifier:
                raise ValueError('工程名与目标文件名不一致')
            if target != path and target.exists():
                raise Conflict('工程名已存在，请换一个名称；保存不会覆盖其他谱面')
            result = dict(self.document(chart, name), editor=metadata)
            if target_id == identifier:
                write(path, result)
            else:
                # Prepare all new bytes first; keep the original recoverable if renaming fails.
                temporary = target.with_name('.' + uuid.uuid4().hex + '.json')
                write(temporary, result)
                recovery = self.recovery / (datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8]) / identifier
                recovery.parent.mkdir(parents=True, exist_ok=True)
                path.rename(recovery)
                try:
                    temporary.rename(target)
                except OSError:
                    recovery.rename(path)
                    raise
            return self.project(target_id)

    def new_path(self, audio_id, project_name):
        audio = self.path(audio_id, ('.wav', '.ogg'))
        filename = re.sub(r'\s+', '_', self.project_name(project_name)) + '.json'
        return (audio.parent / filename).relative_to(self.root).as_posix()

    def delete(self, identifier, revision):
        with self.lock:
            self.chart(identifier)
            path = self.path(identifier)
            if self.revision(path) != revision:
                raise Conflict('谱面已变化，请重新打开后再删除')
            folder = self.recovery / (datetime.now().strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:8])
            target = folder / identifier
            target.parent.mkdir(parents=True, exist_ok=True)
            path.rename(target)
            return dict(ok=True, recovery=str(target))
