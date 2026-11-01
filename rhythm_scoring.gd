## Accuracy-based single-player scoring. Sub judgments and combo never add weight.
## Live accuracy counts only judged heads/tails; the internal score retains the full-chart denominator.
extends RefCounted

const BASE_SCORE: float = 1000000.0
const HOLD_BONUS: float = 0.5
const QUALITY: Dictionary[String, float] = {"PERFECT": 1.0, "GOOD": 0.65, "OK": 0.30, "MISS": 0.0}

var multiplier: float = 1.0
var maximum_weight: float = 0.0
var earned_weight: float = 0.0
var judged_weight: float = 0.0
var _included: Array[bool] = []
var _holds: Array[bool] = []
var _heads: Array[bool] = []
var _tails: Array[bool] = []
var _quality: Array[float] = []

## Preview counts only heads in its selected interval; crossing holds remain visual/audio only.
func reset(notes: Array[float], ends: Array[float], difficulty: String, from_time: float = -INF, to_time: float = INF) -> void:
	multiplier = difficulty_multiplier(difficulty)
	maximum_weight = 0.0
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
		if _included[index]:
			maximum_weight += 1.0 + (HOLD_BONUS if _holds[index] else 0.0)

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
	var full_chart_accuracy: float = earned_weight / maximum_weight if maximum_weight > 0.0 else 0.0
	return roundi(BASE_SCORE * multiplier * pow(clampf(full_chart_accuracy, 0.0, 1.0), 2.0))

func maximum_score() -> int:
	return roundi(BASE_SCORE * multiplier)

## Only canonical difficulty labels carry a bonus. Custom/test labels stay neutral.
static func difficulty_multiplier(difficulty: String) -> float:
	match difficulty.strip_edges().to_lower():
		"easy":
			return 0.90
		"hard":
			return 1.10
	return 1.0
