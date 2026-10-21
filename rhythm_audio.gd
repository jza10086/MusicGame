## Original synthesized test track: all cues are placed at chart sample indices.
## No frame timers or live beat scheduling; playback is a single uncompressed stream.
extends RefCounted

const RATE: int = 44100

static func build(notes: Array[float], bpm: float) -> AudioStreamWAV:
	var duration: float = notes.back() + 2.0
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(int(ceil(duration * float(RATE))))
	var beat: float = 60.0 / bpm
	for index: int in range(4):
		_tone(samples, float(index) * beat, 660.0 if index < 3 else 990.0, 0.07, 0.30)
	for index: int in range(notes.size()):
		_tone(samples, notes[index], 1100.0, 0.055, 0.33)
		_tone(samples, notes[index], 110.0 if index % 4 == 0 else 165.0, 0.13, 0.20)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for index: int in range(samples.size()):
		bytes.encode_s16(index * 2, int(clampf(samples[index], -0.95, 0.95) * 32767.0))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream

static func _tone(samples: PackedFloat32Array, time: float, frequency: float, length: float, gain: float) -> void:
	var start: int = int(round(time * float(RATE)))
	var count: int = int(length * float(RATE))
	for index: int in range(count):
		var sample_index: int = start + index
		if sample_index >= samples.size():
			break
		var phase: float = float(index) / float(RATE)
		var envelope: float = minf(phase / 0.001, 1.0) * exp(-phase * 45.0)
		samples[sample_index] += sin(TAU * frequency * phase) * envelope * gain
