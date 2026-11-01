"""Offline FluidR3 one-shots; Python + NumPy + GCC, no runtime MIDI dependency.

The supplied SF2 and TinySoundFont header stay outside the shipped assets.
Write a candidate rhythm_audio.gd separately so an editor can apply it safely.
See assets/audio_candidates/fluid_r3/SOURCES.md for source URLs and licensing.
"""
import argparse
import json
import math
import re
import subprocess
import wave
from pathlib import Path

import numpy as np

RATE = 44100
GAME = Path(__file__).resolve().parent.parent
FAMILIES = ['键盘', '音高打击', '风琴', '吉他', '贝斯', '弦乐', '合奏人声', '铜管',
            '簧管', '笛管', '合成主音', '合成铺底', '合成效果', '民族弹拨', '打击乐']
NAMES = [
    '三角钢琴', '明亮钢琴', '电钢琴', '酒吧钢琴', '电钢琴一', '电钢琴二', '羽管键琴', '击弦古钢琴',
    '钢片琴', '钟琴', '八音盒', '颤音琴', '马林巴', '木琴', '管钟', '扬琴',
    '拉杆风琴', '打击风琴', '摇滚风琴', '教堂管风琴', '簧风琴', '手风琴', '口琴', '探戈手风琴',
    '尼龙弦吉他', '钢弦吉他', '爵士电吉他', '清音电吉他', '闷音电吉他', '过载电吉他', '失真电吉他', '吉他泛音',
    '原声贝斯', '指弹贝斯', '拨片贝斯', '无品贝斯', '击弦贝斯一', '击弦贝斯二', '合成贝斯一', '合成贝斯二',
    '小提琴', '中提琴', '大提琴', '低音提琴', '颤弓弦乐', '拨奏弦乐', '竖琴', '定音鼓',
    '弦乐合奏一', '弦乐合奏二', '合成弦乐一', '合成弦乐二', '合唱啊声', '人声呜声', '合成人声', '管弦齐奏',
    '小号', '长号', '大号', '弱音小号', '圆号', '铜管合奏', '合成铜管一', '合成铜管二',
    '高音萨克斯', '中音萨克斯', '次中音萨克斯', '上低音萨克斯', '双簧管', '英国管', '巴松', '单簧管',
    '短笛', '长笛', '竖笛', '排箫', '吹瓶', '尺八', '哨笛', '陶笛',
    '方波主音', '锯齿主音', '汽笛风琴主音', '吹管主音', '查朗主音', '人声主音', '五度主音', '贝斯加主音',
    '新世纪铺底', '温暖铺底', '复音合成铺底', '合唱铺底', '弓弦铺底', '金属铺底', '光环铺底', '扫频铺底',
    '雨滴', '电影氛围', '水晶', '大气', '明亮', '精灵', '回声', '科幻',
    '西塔琴', '班卓琴', '三味线', '筝', '卡林巴', '风笛', '民谣提琴', '唢呐',
    '叮当铃', '阿戈戈钟', '钢鼓', '木块', '太鼓', '旋律通鼓', '合成鼓', '反向镲',
]
# A second register only where it provides a useful contrasting one-shot.
EXTRA = {0, 1, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 24, 25, 26, 27, 28, 31,
         32, 33, 34, 35, 36, 37, 38, 39, 45, 46, 47, 55, 80, 81, 82, 87,
         98, 104, 105, 106, 107, 108, 112, 113, 114, 115, 116, 117, 118}
PERCUSSION = {
    39: '拍手', 54: '铃鼓', 56: '牛铃', 58: '振击器', 60: '高音邦戈', 61: '低音邦戈',
    62: '闷音康加', 63: '开放康加', 64: '低音康加', 65: '高音天巴鼓', 66: '低音天巴鼓',
    67: '高音阿戈戈', 68: '低音阿戈戈', 69: '卡巴萨', 70: '沙锤', 73: '短刮瓜',
    74: '长刮瓜', 75: '响棒', 76: '高音木块', 77: '低音木块', 80: '闷三角铁', 81: '开放三角铁',
}


def make_plan():
    result = []
    assert len(NAMES) == 120
    for program, name in enumerate(NAMES):
        family = FAMILIES[program // 8]
        key = 48 if 32 <= program < 40 or program in (43, 47, 58, 70, 116) else 60
        if program in (8, 9, 10, 13, 72, 76, 78, 112):
            key = 72
        soft = 88 <= program < 104 or program in (44, 48, 49, 50, 51, 52, 53, 54, 119)
        hold = 0.65 if soft else 0.28
        for variant_key in ([key, key + 12] if program in EXTRA else [key]):
            pitch = f'C{variant_key // 12 - 1}'
            suffix = ' · 慢起音' if soft else ''
            result.append(dict(id=f'gm_{program + 1:03d}_{pitch.lower()}', name=f'{family} · {name} · {pitch}{suffix}',
                               bank=0, program=program, key=variant_key, velocity=100, hold=hold, total=3.0))
    for key, name in PERCUSSION.items():
        result.append(dict(id=f'gm_perc_{key}', name=f'小打击 · {name}', bank=128, program=0,
                           key=key, velocity=100, hold=0.10, total=3.0))
    return result


def finish_pcm(raw):
    """Trim only near-silence, preserve attack, and match the existing 50 ms RMS target.

    No compressor: transient shape is retained and a -1 dBFS peak ceiling wins
    over the RMS target. Tail truncation uses a 20 ms fade to avoid clicks.
    """
    if not np.isfinite(raw).all():
        raise ValueError('Non-finite renderer output')
    peak = float(np.max(np.abs(raw)))
    if peak < 1e-7:
        raise ValueError('Silent sample')
    active = np.flatnonzero(np.abs(raw) > peak * 10 ** (-70 / 20))
    start = max(0, int(active[0]) - 22)
    end = min(len(raw), int(active[-1]) + 1 + 220)
    pcm = raw[start:end].astype(np.float64).copy()
    pcm[:22] *= np.linspace(0, 1, 22)
    fade = min(882, len(pcm))
    pcm[-fade:] *= np.linspace(1, 0, fade)
    window = min(round(RATE * .05), len(pcm))
    energy = np.concatenate(([0.0], np.cumsum(pcm * pcm)))
    rms = math.sqrt(float(np.max(energy[window:] - energy[:-window])) / window)
    gain = min(10 ** (-16 / 20) / rms, 10 ** (-1 / 20) / float(np.max(np.abs(pcm))))
    pcm *= gain
    packed = np.rint(pcm * 32767).astype('<i2')
    return packed, dict(trim_start_ms=round(start * 1000 / RATE, 3), frames=len(packed),
                        duration_s=round(len(packed) / RATE, 4), applied_gain_db=round(20 * math.log10(gain), 3),
                        peak_dbfs=round(20 * math.log10(float(np.max(np.abs(pcm)))), 3),
                        max_50ms_rms_dbfs=round(20 * math.log10(rms * gain), 3))


def catalog_candidate(samples, target):
    source = (GAME / 'rhythm_audio.gd').read_text(encoding='utf-8')
    for field, value in [('TAP_FILES', lambda s: json.dumps('fluid_r3/' + s['id'] + '.wav')),
                         ('TAP_NAMES', lambda s: json.dumps(s['name'], ensure_ascii=False)),
                         ('TAP_GAIN_DB', lambda s: '0.0')]:
        pattern = rf'(const {field}: Dictionary\[[^\n]+ = \{{)(.*?)(\n\}})'
        match = re.search(pattern, source, re.S)
        if not match:
            raise ValueError(f'Missing catalog {field}')
        old = re.sub(r'\n\s*# BEGIN FLUID_R3.*?# END FLUID_R3', '', match[2], flags=re.S).rstrip().rstrip(',')
        entries = ',\n'.join('\t' + json.dumps(s['id']) + ': ' + value(s) for s in samples)
        body = old + ',\n\t# BEGIN FLUID_R3 (generated by authoring/render_instruments.py)\n' + entries + '\n\t# END FLUID_R3'
        source = source[:match.start(2)] + body + source[match.end(2):]
    target.write_text(source, encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--soundfont', required=True, type=Path)
    parser.add_argument('--tsf-header', required=True, type=Path)
    parser.add_argument('--work', required=True, type=Path)
    parser.add_argument('--catalog-output', required=True, type=Path)
    parser.add_argument('--compiler', default='gcc')
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    output = GAME / 'assets/audio_candidates/fluid_r3'
    output.mkdir(parents=True, exist_ok=True)
    samples = make_plan()
    plan = work / 'render_plan.txt'
    plan.write_text(''.join(f"{s['id']} {s['bank']} {s['program']} {s['key']} {s['velocity']} {s['hold']} {s['total']}\n" for s in samples), encoding='ascii')
    executable = work / 'render_instrument_sample.exe'
    subprocess.run([args.compiler, '-O2', '-I', str(args.tsf_header.resolve().parent),
                    str(Path(__file__).with_name('render_instrument_sample.c')), '-o', str(executable), '-lm'], check=True)
    subprocess.run([str(executable), str(args.soundfont.resolve()), str(plan), str(work)], check=True)
    for sample in samples:
        raw = np.fromfile(work / (sample['id'] + '.f32'), dtype='<f4')
        pcm, measurement = finish_pcm(raw)
        sample.update(measurement)
        with wave.open(str(output / (sample['id'] + '.wav')), 'wb') as wav:
            wav.setparams((1, 2, RATE, len(pcm), 'NONE', 'not compressed'))
            wav.writeframes(pcm.tobytes())
    metadata = dict(source='FluidR3 GM v3.1', renderer='TinySoundFont v0.9', sample_rate=RATE,
                    channels=1, bits=16, velocity=100, samples=samples)
    (output / 'samples.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    catalog_candidate(samples, args.catalog_output)
    rows = ['| 音效 | GM Program（1 起）/ 打击键号 | 音高 | 时长 |', '| --- | --- | --- | ---: |']
    for s in samples:
        preset = str(s['program'] + 1) if s['bank'] == 0 else f"鼓组 / {s['key']}"
        rows.append(f"| [{s['name']}]({s['id']}.wav) | {preset} | {s['key']} | {s['duration_s']:.3f} s |")
    (output / 'CATALOG.md').write_text('# FluidR3 代表音色目录\n\n' + '\n'.join(rows) + '\n', encoding='utf-8')
    print(f'{len(samples)} WAVs; {sum((output / (s["id"] + ".wav")).stat().st_size for s in samples) / 1048576:.2f} MiB')


if __name__ == '__main__':
    main()
