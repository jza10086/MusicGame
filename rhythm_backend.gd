## Shared rhythm playback, judgment and local settings. All presentation belongs to music_game.
## A silent lead-in advances into the audio playback timeline; input samples it on key events.
extends Node
## Only the embedded authoring preview may continue when its canvas loses focus.
var editor_preview: bool = false

const Paths = preload("rhythm_paths.gd")
const Preferences = preload("settings.gd")
var party_config: PartyConfig
const Timing = preload("rhythm_timing.gd")
const Scoring = preload("rhythm_scoring.gd")
var scoring: Scoring = Scoring.new()
const Synth = preload("rhythm_audio.gd")
const Chart = preload("rhythm_chart.gd")
const DEFAULT_CHART: String = "charts/hold_test/chart.json"
const BGM_GAIN: float = 0.4
const DEFAULT_CHART_ORDER: Array[String] = [DEFAULT_CHART,
	"charts/bad_apple/Bad_Apple_4K_Normal.json",
	"charts/bad_apple/chart.json",
	"charts/bad_apple/normal.json",
	"charts/bad_apple/hard.json",
	"charts/bad_apple/authored.json",
	"charts/bad_apple/authored_easy.json"]
var chart_paths: Array[String] = []
var chart_names: Array[String] = []
const DEFAULTS: Dictionary = Preferences.DEFAULTS
## seconds_until captures the consumed note against the visual clock at the input edge.
signal press_feedback(lane: int, hit: bool)
signal hold_feedback(lane: int, kind: String)
signal hit_feedback(lane: int, kind: String, chart_time: float)
var chart_sounds: Dictionary = {}
signal note_judged(lane: int, grade: String, error_ms: float, seconds_until: float)

enum State { IDLE, PLAYING, FINISHED }

var state: State = State.IDLE
var settings: Dictionary = DEFAULTS.duplicate(true)
var _audio: AudioStreamPlayer
var _notes: Array[float] = []
var _judged: Array[bool] = []
var _note_ends: Array[float] = []
var _active_holds: Array[int] = [-1, -1]
var _hold_errors: Array[float] = [0.0, 0.0]
var _note_subs: Array = []
var _sub_next: Array[int] = []
var _total_units: int = 0
var _raw_errors: Array[float] = []
var _counts: Dictionary = {"PERFECT": 0, "GOOD": 0, "OK": 0, "MISS": 0}
var _combo: int = 0
var _best_combo: int = 0
var _latency: float = 0.0
var _preparation_end: float = 0.0
var _last_time: float = 0.0
var _playback_start: float = 0.0
var _lead_in_active: bool = false
var _lead_in_from: float = 0.0
var _lead_in_origin_usec: int = 0
var _audio_clock_pending: bool = false
var _audio_queued_usec: int = 0
var key_count: int = 2
var held_lanes: Array[bool] = [false, false]
var _note_lanes: Array[int] = []
var _key_sources: Array[Dictionary] = [{}, {}]
## Each finger owns its initial lane until release, even if it drifts across a boundary.
var _touch_sources: Dictionary[int, int] = {}
var _calibration: bool = false
var _selected_track: int = 1
var _duration: float = 1.0

var last_error: String = ""


func _ready() -> void:
	_audio = $Track
	_audio.finished.connect(_on_audio_finished)
	if not editor_preview and _load_settings() != OK:
		return
	_apply_volume()
	configure_lanes(2)

func refresh_chart_library() -> void:
	var found: Array[String] = Chart.discover_paths()
	chart_paths.clear()
	for relative_path: String in DEFAULT_CHART_ORDER:
		var path: String = Paths.resolve(relative_path)
		if found.has(path):
			chart_paths.append(path)
	for path: String in found:
		if not chart_paths.has(path):
			chart_paths.append(path)
	chart_names.clear()
	for path: String in chart_paths:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var project_name: String = str(data.get("project_name", "")).strip_edges()
		chart_names.append(project_name if not project_name.is_empty() else path.get_file().get_basename())

func _select_track(index: int) -> void:
	_stop()
	_selected_track = clampi(index, 0, chart_paths.size())
	_notes.clear()
	_note_ends.clear()
	_note_subs.clear()
	_note_lanes.clear()
	_judged.clear()
	_combo = 0
	_best_combo = 0
	_counts = {"PERFECT": 0, "GOOD": 0, "OK": 0, "MISS": 0}
	last_error = ""
	if _selected_track == 0:
		configure_lanes(2)
	else:
		var chart: Dictionary = Chart.read_chart(chart_paths[_selected_track - 1])
		if not chart.ok:
			last_error = chart.error
			return
		configure_lanes(int(chart.data.key_count))

func _start(chart: Dictionary, skip_intro: bool = false, lead_in_seconds: float = 0.0, calibration_track: bool = false) -> void:
	_stop()
	last_error = ""
	_note_subs.clear()
	var stream: AudioStream
	var chart_start: float = 0.0
	var base_score: int = RhythmSongChart.DEFAULT_BASE_SCORE
	_note_lanes.clear()
	_note_ends.clear()
	chart_sounds.clear()
	if not chart.is_empty() and not _calibration:
		if not chart.ok:
			last_error = chart.error
			return
		base_score = chart.base_score
		configure_lanes(int(chart.data.key_count))
		_notes = chart.notes
		_note_lanes = chart.lanes
		_note_ends = chart.ends
		_note_subs = chart.subs
		chart_sounds = chart.sounds
		stream = chart.audio
		chart_start = minf(0.0, float(chart.notes[0]))
		var editor: Variant = chart.data.get("editor", {})
		if editor is Dictionary:
			var offset: float = float(editor.get("offset_ms", 0.0)) / 1000.0
			if is_finite(offset):
				chart_start = minf(chart_start, offset)
	else:
		configure_lanes(2)
		_notes = Timing.note_times(float(settings.bpm), _calibration or calibration_track)
		stream = Synth.build(_notes, float(settings.bpm))
		for index: int in range(_notes.size()):
			_note_lanes.append(index % 2 if not _calibration else 0)
	if _note_ends.is_empty():
		var original_notes: Array[float] = _notes.duplicate()
		var original_lanes: Array[int] = _note_lanes.duplicate()
		var busy_until: Array[float] = [-1.0, -1.0]
		_notes.clear()
		_note_lanes.clear()
		for index: int in range(original_notes.size()):
			var lane: int = original_lanes[index]
			var time: float = original_notes[index]
			if time <= busy_until[lane]:
				continue
			var hold_length: float = 90.0 / float(settings.bpm) if not _calibration and not calibration_track and index >= 8 and index % 16 in [8, 1] else 0.0
			_notes.append(time)
			_note_lanes.append(lane)
			_note_ends.append(time + hold_length)
			busy_until[lane] = time + hold_length
		stream = Synth.build(_notes, float(settings.bpm))
	if _note_subs.is_empty():
		for index: int in range(_notes.size()):
			_note_subs.append([])
	_sub_next.clear()
	_sub_next.resize(_notes.size())
	_sub_next.fill(0)
	scoring.reset(_notes, _note_ends, base_score)
	_total_units = _notes.size()
	for index: int in range(_notes.size()):
		if _note_ends[index] > _notes[index]:
			_total_units += 1 + _note_subs[index].size()
	_duration = stream.get_length()
	_judged.clear()
	_judged.resize(_notes.size())
	_judged.fill(false)
	_raw_errors.clear()
	_counts = {"PERFECT": 0, "GOOD": 0, "OK": 0, "MISS": 0}
	_combo = 0
	_best_combo = 0
	_audio.stream = stream
	_latency = AudioServer.get_output_latency()
	_playback_start = maxf(0.0, _notes[0] - 3.0) if skip_intro else 0.0
	# Negative chart time is silence before BGM; preparation remains a separate 5-second interval.
	_preparation_end = chart_start if chart_start < 0.0 else _playback_start
	_lead_in_from = _preparation_end - maxf(0.0, lead_in_seconds)
	_lead_in_active = _lead_in_from < _playback_start
	_lead_in_origin_usec = Time.get_ticks_usec()
	_last_time = _lead_in_from
	if not _lead_in_active:
		_audio.play(_playback_start)
	state = State.PLAYING

func _stop() -> void:
	_lead_in_active = false
	_audio_clock_pending = false
	_audio.stop()
	state = State.IDLE
	reset_lane_state()

func _clock() -> float:
	if state != State.PLAYING:
		return _last_time
	if _lead_in_active:
		var time: float = _lead_in_from + float(Time.get_ticks_usec() - _lead_in_origin_usec) / 1000000.0
		# Queue music ahead of its audible start, accounting for the next mix and output latency.
		# A late frame seeks past only the elapsed portion; it never restarts the countdown.
		var audio_delay: float = maxf(0.0, AudioServer.get_time_to_next_mix()) + _latency
		var until_start: float = _playback_start - time
		_last_time = maxf(_last_time, time)
		if until_start > audio_delay:
			return _last_time
		_audio_queued_usec = Time.get_ticks_usec()
		_audio.play(_playback_start + maxf(0.0, audio_delay - until_start))
		_lead_in_active = false
		_audio_clock_pending = true
	if _audio_clock_pending:
		# Until the first new mix, playback position/mix age may still describe the stopped player.
		var since_queue: float = float(Time.get_ticks_usec() - _audio_queued_usec) / 1000000.0
		if AudioServer.get_time_since_last_mix() > since_queue:
			_last_time = maxf(_last_time, _lead_in_from + float(Time.get_ticks_usec() - _lead_in_origin_usec) / 1000000.0)
			return _last_time
		_audio_clock_pending = false
	_last_time = Timing.playback_time(_audio.get_playback_position(), AudioServer.get_time_since_last_mix(), _latency, _last_time)
	return _last_time

func _process(_delta: float) -> void:
	var time: float = _clock()
	if state != State.PLAYING:
		return
	var judged_time: float = time if _calibration else time - float(settings.input_ms) / 1000.0
	_update_holds(judged_time)
	var window: float = 0.24 if _calibration else Timing.HIT_MS / 1000.0
	for index: int in range(_notes.size()):
		if not _judged[index] and not _active_holds.has(index) and judged_time > _notes[index] + window:
			_judged[index] = true
			_miss_note(index)
	if time >= _duration:
		_finish()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	var lane: int = key_lane(key.physical_keycode)
	if lane < 0 or key.echo:
		return
	if key.pressed and get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if key.pressed:
		if state != State.PLAYING or _key_sources[lane].has(key.physical_keycode):
			return
		_key_sources[lane][key.physical_keycode] = true
	else:
		_key_sources[lane].erase(key.physical_keycode)
	press_lane(lane, _lane_has_input(lane), key.pressed)
	if state == State.PLAYING:
		get_viewport().set_input_as_handled()

## Touch begins only in the stage's playable area; release uses the original finger ID.
func begin_touch(index: int, lane: int) -> void:
	if state != State.PLAYING or _touch_sources.has(index):
		return
	_touch_sources[index] = lane
	press_lane(lane, true, true)

## Release outside the runway and OS cancellation must still end the captured touch.
func end_touch(index: int) -> bool:
	if not _touch_sources.has(index):
		return false
	var lane: int = _touch_sources[index]
	_touch_sources.erase(index)
	press_lane(lane, _lane_has_input(lane), false)
	return true

func _lane_has_input(lane: int) -> bool:
	return not _key_sources[lane].is_empty() or _touch_sources.values().has(lane)

## Each physical press may strike, even while its same-lane partner remains held.
## The lane stays held until all sources release; OS key repeat is filtered at input.

func press_lane(lane: int, down: bool, new_press: bool) -> void:
	if lane < 0 or lane >= key_count:
		return
	var was_held: bool = held_lanes[lane]
	held_lanes[lane] = down and state == State.PLAYING
	if not down and was_held and state == State.PLAYING:
		_release_hold(_clock(), lane)
	if down and new_press and state == State.PLAYING:
		var time: float = _clock()
		_update_holds(time - float(settings.input_ms) / 1000.0)
		var hit: bool = false
		if _active_holds[lane] < 0:
			hit = _hit(time, lane)
		press_feedback.emit(lane, hit)

## Consume at most one nearest unjudged note. Stray keys never consume future notes.

func _hit(time: float, lane: int = 0) -> bool:
	var target: int = -1
	var distance: float = INF
	var compensated: float = time if _calibration else time - float(settings.input_ms) / 1000.0
	for index: int in range(_notes.size()):
		if _judged[index] or _active_holds.has(index) or _note_lanes[index] != lane:
			continue
		var candidate: float = absf(compensated - _notes[index])
		if candidate < distance:
			distance = candidate
			target = index
	var window: float = 0.24 if _calibration else Timing.HIT_MS / 1000.0
	if target < 0 or distance > window:
		return false
	_judged[target] = _note_ends[target] <= _notes[target]
	var raw: float = (time - _notes[target]) * 1000.0
	var error: float = Timing.error_ms(time, _notes[target], float(settings.input_ms))
	scoring.record_head(target, Timing.grade(error))
	if not _judged[target]:
		_active_holds[lane] = target
		_hold_errors[lane] = error
		_record(Timing.grade(error), error, lane, _notes[target] - Timing.visual_time(time, float(settings.visual_ms)))
		hold_feedback.emit(lane, "hold_start")
		hit_feedback.emit(lane, "hold_start", _notes[target])
		return true
	if _calibration:
		_raw_errors.append(raw)
		if _raw_errors.size() > 32:
			_raw_errors.pop_front()

	_record(Timing.grade(error), error, lane, _notes[target] - Timing.visual_time(time, float(settings.visual_ms)))
	if not _calibration:
		hit_feedback.emit(lane, "success", _notes[target])
	return true

func _record(grade: String, error: float, lane: int = 0, seconds_until: float = INF) -> void:
	note_judged.emit(lane, grade, error, seconds_until)
	_counts[grade] += 1
	_combo = 0 if grade == "MISS" else _combo + 1
	_best_combo = maxi(_best_combo, _combo)

func _finish() -> void:
	_update_holds(_duration - float(settings.input_ms) / 1000.0)
	_audio.stop()
	for index: int in range(_notes.size()):
		if not _judged[index]:
			_judged[index] = true
			if _active_holds.has(index):
				_complete_hold(_note_lanes[index], true)
			else:
				_miss_note(index)
	_last_time = _duration
	state = State.FINISHED
	reset_lane_state()

func _on_audio_finished() -> void:
	if state == State.PLAYING:
		_finish()

func _set_calibration(value: bool) -> void:
	_stop()
	_calibration = value
	if value:
		configure_lanes(2)
	_raw_errors.clear()

func configure_lanes(count: int) -> void:
	assert(count in [2, 4])
	key_count = count
	reset_lane_state()

func reset_lane_state() -> void:
	_touch_sources.clear()
	held_lanes.resize(key_count)
	held_lanes.fill(false)
	_active_holds.resize(key_count)
	_active_holds.fill(-1)
	_hold_errors.resize(key_count)
	_hold_errors.fill(0.0)
	_key_sources.clear()
	for lane: int in range(key_count):
		_key_sources.append({})

func key_lane(code: Key) -> int:
	var keys: Array = settings["keys_%dk" % key_count]
	var slot: int = keys.find(int(code))
	return slot / 2 if key_count == 2 and slot >= 0 else slot

func lane_key_text(lane: int, count: int) -> String:
	var keys: Array = settings["keys_%dk" % count]
	if count == 2:
		return "%s / %s" % [OS.get_keycode_string(int(keys[lane * 2])), OS.get_keycode_string(int(keys[lane * 2 + 1]))]
	return OS.get_keycode_string(int(keys[lane]))

static func valid_play_key(code: int) -> bool:
	return code > 0 and code not in [KEY_ESCAPE, KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK] and not OS.get_keycode_string(code).is_empty()

## Validate saved bindings once at the JSON boundary, before replacing settings.
static func validate_play_keys(value: Variant) -> bool:
	if not value is Array or value.size() != 4:
		return false
	var seen: Array[int] = []
	for code: Variant in value:
		if not code is int or not valid_play_key(code) or seen.has(code):
			return false
		seen.append(code)
	return true

func _apply_volume() -> void:
	_audio.volume_linear = float(settings.volume) * BGM_GAIN

## Formal values are supplied by the active scope; authoring persistence is opt-in and separate.
func _load_settings() -> Error:
	if party_config != null:
		return apply_preferences(party_config.snapshot_effective().own)
	var path: String = preview_settings_path()
	if not FileAccess.file_exists(path):
		return OK
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		var open_error: Error = FileAccess.get_open_error()
		last_error = "无法读取作者工具设置：%s (%s)" % [path, error_string(open_error)]
		return open_error
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	if error != OK or not parser.data is Dictionary or not parser.data.get("local") is Dictionary:
		last_error = "作者工具设置无效：" + path
		return ERR_INVALID_DATA
	return apply_preferences(parser.data.local)

static func preview_settings_path() -> String:
	return PartyInput.installation_directory().path_join("minigame/gp_rhythm_game/config/authoring.json")

func apply_preferences(values: Dictionary) -> Error:
	var next: Dictionary = DEFAULTS.duplicate(true)
	var fields: Dictionary = Preferences.schema().fields
	for key: String in values:
		if not fields.has(key):
			last_error = "未知音游设置：" + key
			return ERR_INVALID_DATA
		var value: Variant = values[key]
		var field: Dictionary = fields[key]
		var valid: bool
		if field.type == "array":
			# JSON numbers are floats; convert only exact integer key codes at this boundary.
			if value is Array:
				value = value.duplicate()
				for index: int in range(value.size()):
					if value[index] is float and is_finite(value[index]) and value[index] == floor(value[index]):
						value[index] = int(value[index])
			valid = validate_play_keys(value)
		elif field.type == "bool":
			valid = value is bool
		elif field.type == "string":
			valid = value is String and Synth.TAP_FILES.has(value)
		else:
			valid = (value is float or value is int) and is_finite(float(value)) and value >= field.min and value <= field.max
		if not valid:
			last_error = "音游设置值无效：" + key
			return ERR_INVALID_DATA
		next[key] = value
	settings = next
	last_error = ""
	return OK

func _save_settings() -> Error:
	if party_config != null:
		return ERR_UNAVAILABLE
	var validation: Error = apply_preferences(settings)
	if validation != OK:
		return validation
	var path: String = preview_settings_path()
	var error: Error = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		return error
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"local": settings}, "\t") + "\n")
	return file.get_error()

## Release physical sources and score an interrupted hold using the current audio time.
func release_inputs() -> void:
	_touch_sources.clear()
	for lane: int in range(key_count):
		_key_sources[lane].clear()
		press_lane(lane, false, false)

func performance() -> Dictionary:
	return {"accuracy": roundi(scoring.accuracy() * 10000.0), "combo": _best_combo}

## Audio-clock milestones catch up after frame stalls; no timers or release are required.

func _update_holds(judged_time: float) -> void:
	for lane: int in range(key_count):
		var index: int = _active_holds[lane]
		if index < 0:
			continue
		while _sub_next[index] < _note_subs[index].size() and float(_note_subs[index][_sub_next[index]]) <= judged_time:
			_sub_next[index] += 1
			_record("PERFECT", 0.0, lane, 0.0)
			hold_feedback.emit(lane, "hold_sub")
			hit_feedback.emit(lane, "hold_sub", _note_subs[index][_sub_next[index] - 1])
		if judged_time >= _note_ends[index]:
			_complete_hold(lane, false)

func _release_hold(audio_time: float, lane: int) -> void:
	var judged_time: float = audio_time - float(settings.input_ms) / 1000.0
	_update_holds(judged_time)
	if _active_holds[lane] >= 0:
		_complete_hold(lane, true)

func _complete_hold(lane: int, broken: bool) -> void:
	var index: int = _active_holds[lane]
	if index < 0:
		return
	scoring.complete_hold(index, broken)
	_active_holds[lane] = -1
	_judged[index] = true
	while _sub_next[index] < _note_subs[index].size():
		_sub_next[index] += 1
		_record("MISS", 0.0, lane)
	_record("MISS" if broken else "PERFECT", 0.0, lane, INF if broken else 0.0)
	if not broken:
		hold_feedback.emit(lane, "hold_end")
		hit_feedback.emit(lane, "hold_end", _note_ends[index])

func _miss_note(index: int) -> void:
	scoring.record_head(index, "MISS")
	scoring.complete_hold(index, true)
	_record("MISS", 0.0, _note_lanes[index])
	if _note_ends[index] > _notes[index]:
		for sub: Variant in _note_subs[index]:
			_record("MISS", 0.0, _note_lanes[index])
		_record("MISS", 0.0, _note_lanes[index])
		_sub_next[index] = _note_subs[index].size()

## Called once immediately after _start by the party entry. Later judgment uses only the audio clock.
## A late arrival seeks forward once; never rescale playback speed or repeatedly reset song time.
func schedule_audio_zero(delay_seconds: float) -> void:
	_audio.stop()
	_lead_in_from = -delay_seconds
	_lead_in_origin_usec = Time.get_ticks_usec()
	_last_time = _lead_in_from
	_playback_start = maxf(0.0, _lead_in_from)
	_lead_in_active = true
	_audio_clock_pending = false
