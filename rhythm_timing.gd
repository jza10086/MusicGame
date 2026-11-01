## Pure timing and judgement rules for the standalone 1K calibration prototype.
extends RefCounted

const PERFECT_MS: float = 50.0
const GOOD_MS: float = 100.0
const HIT_MS: float = 150.0

static func note_times(bpm: float, calibration: bool) -> Array[float]:
	var notes: Array[float] = []
	var beat: float = 60.0 / bpm
	for index: int in range(64):
		notes.append((4.0 + float(index)) * beat)
		if not calibration and index >= 16 and index < 48 and index % 4 == 3:
			notes.append((4.5 + float(index)) * beat)
	return notes

## Positive input compensation subtracts a consistent late response from judgement.
static func error_ms(audio_time: float, note_time: float, input_ms: float) -> float:
	return (audio_time - note_time) * 1000.0 - input_ms

## Positive visual offset advances the falling notes without changing judgement.
static func visual_time(audio_time: float, visual_ms: float) -> float:
	return audio_time + visual_ms / 1000.0

static func grade(error: float) -> String:
	var distance: float = absf(error)
	if distance <= PERFECT_MS:
		return "PERFECT"
	if distance <= GOOD_MS:
		return "GOOD"
	if distance <= HIT_MS:
		return "OK"
	return "MISS"

static func median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var middle: int = sorted.size() / 2
	return sorted[middle] if sorted.size() % 2 else (sorted[middle - 1] + sorted[middle]) * 0.5


## Keep the last valid audio time while the mixer is suspended or reports an invalid age.
## Web occasionally reports ~2^64 microseconds instead of a small mix interval.
## Normal samples retain playback position + mix age - output latency exactly.
static func playback_time(position: float, mix_age: float, latency: float, previous: float) -> float:
	if not is_finite(position) or not is_finite(mix_age) or not is_finite(latency) or mix_age < 0.0 or mix_age > 1.0:
		return previous
	return maxf(previous, position + mix_age - latency)
