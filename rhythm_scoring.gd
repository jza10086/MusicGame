## Accuracy-based single-player scoring. Sub judgments and combo never add weight.
## Live accuracy counts only judged heads/tails; chart resources supply the full-accuracy score.
extends RefCounted

const HOLD_BONUS: float = 0.5
const QUALITY: Dictionary[String, float] = {"PERFECT": 1.0, "GOOD": 0.65, "OK": 0.30, "MISS": 0.0}

var base_score: int = RhythmSongChart.DEFAULT_BASE_SCORE
var earned_weight: float = 0.0
var judged_weight: float = 0.0
var _included: Array[bool] = []
var _holds: Array[bool] = []
var _heads: Array[bool] = []
var _tails: Array[bool] = []
var _quality: Array[float] = []

## Preview counts only heads in its selected interval; crossing holds remain visual/audio only.
func reset(notes: Array[float], ends: Array[float], full_score: int, from_time: float = -INF, to_time: float = INF) -> void:
	base_score = full_score
	earned_weight = 0.0
	judged_weight = 0.0
	_included.resize(notes.size())
	_holds.resize(notes.size())
	_heads.resize(notes.size())
	_heads.fill(false)
	_tails.resize(notes.size())
	_tails.fill(false)
	_quality.resize(notes.size())
	_quality.fill(0.0)
	for index: int in range(notes.size()):
		_included[index] = notes[index] >= from_time and notes[index] < to_time
		_holds[index] = ends[index] > notes[index]

## A hold's head quality also caps its completion bonus; no automatic PERFECT inflation.
func record_head(index: int, grade: String) -> void:
	if index < 0 or index >= _heads.size() or not _included[index] or _heads[index]:
		return
	_heads[index] = true
	judged_weight += 1.0
	_quality[index] = QUALITY.get(grade, 0.0)
	earned_weight += _quality[index]

func complete_hold(index: int, broken: bool) -> void:
	if index < 0 or index >= _tails.size() or not _included[index] or not _holds[index] or not _heads[index] or _tails[index]:
		return
	_tails[index] = true
	judged_weight += HOLD_BONUS
	if not broken:
		earned_weight += _quality[index] * HOLD_BONUS

## Misses count in the denominator; unjudged notes do not. A fresh round starts at 100%.
func accuracy() -> float:
	return clampf(earned_weight / judged_weight, 0.0, 1.0) if judged_weight > 0.0 else 1.0

func score() -> int:
	# Match the two-decimal percentage displayed locally and reported to the host.
	return score_for_accuracy(base_score, float(roundi(accuracy() * 10000.0)) / 10000.0)

func maximum_score() -> int:
	return base_score

## Accuracy is a fraction (0..1), not a percentage (0..100).
static func score_for_accuracy(full_score: int, accuracy_value: float) -> int:
	return roundi(float(full_score) * accuracy_value)
