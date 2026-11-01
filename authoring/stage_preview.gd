## Native editor stage preview. Reuses the game clock, judgment and audio in one persistent instance.
extends Control
const Stage = preload("../music_game.gd")
const STAGE_SCENE: PackedScene = preload("../music_game.tscn")
var song: AudioStream = preload("../charts/hold_test/hold_test.wav")
var audio_id: String = "hold_test/hold_test.wav"
var game: Stage
var current_chart: Dictionary = {}
var chart_revision: int = -1
var range_start: float = 0.0
var range_end: float = 16.0
var loop_enabled: bool = true
var playing: bool = false
var cycles: int = 0
var updates: int = 0
var _segment_start: float = 0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Run the range boundary before the stage's existing Auto and miss sweep.
	get_tree().process_frame.connect(_before_frame)
	game = STAGE_SCENE.instantiate() as Stage
	game.editor_preview = true
	add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.set_auto_play(true)
	game.set_process_input(false)
	game.backend.set_process_input(false)
	_force_stream_players(game)
	_show_stage()
	game.mode = "stopped"

## Match the game audio player path used by the native editor.
func _force_stream_players(node: Node) -> void:
	if node is AudioStreamPlayer:
		(node as AudioStreamPlayer).playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	for child: Node in node.get_children():
		_force_stream_players(child)

func _show_stage() -> void:
	game.get_node("Modal").hide()
	game.get_node("HUD").show()
	game.get_node("HUD/PauseButton").hide()
	game.get_node("HUD/Countdown").set("text", "")
	game._auto_active = true

## Resolve packaged chart audio safely; data updates keep the same stage instance.
func update_chart(data: Dictionary, revision: int, next_audio_id: String = "hold_test/hold_test.wav") -> Dictionary:
	if revision < chart_revision:
		return {"ok": false, "error": "忽略过期的谱面修改"}
	if next_audio_id.is_absolute_path() or next_audio_id.contains("..") or next_audio_id.contains(":") or next_audio_id.contains("\\") or next_audio_id.get_file() != str(data.get("audio_file", "")):
		return {"ok": false, "error": "预览音源路径无效"}
	var next_song: AudioStream = song
	if next_audio_id != audio_id:
		var path: String = Stage.Backend.Paths.resolve("charts/" + next_audio_id)
		next_song = Stage.Backend.Chart.load_audio(path)
		if next_song == null:
			return {"ok": false, "error": "预览音源无法加载"}
	var report: Dictionary = Stage.Backend.Chart.validate(data)
	if data.get("notes_ms", null) is Array and data.notes_ms.is_empty():
		var probe: Dictionary = data.duplicate(true)
		probe.notes_ms = [0.0]
		probe.lanes = [0]
		probe.durations_ms = [0.0]
		probe.subs_ms = [[]]
		report = Stage.Backend.Chart.validate(probe)
		if report.ok and data.get("lanes") == [] and data.get("durations_ms") == [] and data.get("subs_ms") == []:
			report = {"ok": true, "notes": [], "lanes": [], "ends": [], "subs": [], "sounds": {}}
		else:
			return {"ok": false, "error": "空谱面数组不一致"}
	if not report.ok:
		return report
	if not report.ends.is_empty() and float(report.ends.max()) + 0.15 >= next_song.get_length():
		return {"ok": false, "error": "音符超出音乐范围"}
	var now: float = game.backend._clock()
	if next_audio_id != audio_id:
		stop_preview()
		song = next_song
		audio_id = next_audio_id
		game.backend._audio.stream = song
		now = 0.0
		range_start = 0.0
		range_end = minf(16.0, song.get_length())
	if int(data.key_count) != game.backend.key_count:
		_stop_hit_sounds()
		game.backend.configure_lanes(int(data.key_count))
		game.configure_lane_feedback()
	current_chart = data.duplicate(true)
	chart_revision = revision
	updates += 1
	game.backend._notes.assign(report.notes)
	game.backend._note_lanes.assign(report.lanes)
	game.backend._note_ends.assign(report.ends)
	game.backend._note_subs.assign(report.subs)
	game.backend.chart_sounds = report.sounds
	game.backend._duration = song.get_length()
	if game.backend._audio.stream == null:
		game.backend._audio.stream = song
	_rebuild_at(now)
	game.get_node("HUD/TrackTitle").set("text", "%s / %s" % [data.title, data.difficulty])
	return {"ok": true}

## Reconstruct a seek/edit point silently. Heads before it never replay sounds or earn score.
func _rebuild_at(audio_time: float, seeking: bool = false) -> void:
	var backend: Stage.Backend = game.backend
	# A seek boundary is chart time, not calibrated input time. Keep a head exactly
	# at the cursor, including negative input offsets; hot edits cannot resurrect the pre-roll.
	# Compiled milliseconds are rounded; include a grid head within ten microseconds.
	var judged_time: float = audio_time - 0.00001 if seeking else maxf(_segment_start - 0.00001, audio_time - float(backend.settings.input_ms) / 1000.0)
	var count: int = backend._notes.size()
	backend._judged.resize(count)
	backend._judged.fill(false)
	backend._sub_next.resize(count)
	backend._sub_next.fill(0)
	backend.reset_lane_state()
	backend._counts = {"PERFECT": 0, "GOOD": 0, "OK": 0, "MISS": 0}
	backend._combo = 0
	backend._best_combo = 0
	backend._total_units = 0
	backend.scoring.reset(backend._notes, backend._note_ends, str(current_chart.get("difficulty", "Normal")), judged_time, range_end)
	backend._raw_errors.clear()
	game._auto_next = count
	game._auto_release_at.fill(-INF)
	game.view_notes.clear()
	for index: int in range(count):
		var head: float = backend._notes[index]
		var tail: float = backend._note_ends[index]
		var lane: int = backend._note_lanes[index]
		if head >= judged_time:
			game._auto_next = mini(game._auto_next, index)
			backend._total_units += 1
		elif tail <= judged_time:
			backend._judged[index] = true
		else:
			backend._active_holds[lane] = index
			game._auto_release_at[lane] = tail
		while backend._sub_next[index] < backend._note_subs[index].size() and float(backend._note_subs[index][backend._sub_next[index]]) < judged_time:
			backend._sub_next[index] += 1
		if tail > head and tail >= judged_time:
			backend._total_units += 1 + backend._note_subs[index].size() - backend._sub_next[index]
		game.view_notes.append({"time": head, "end": tail, "subs": backend._note_subs[index], "sub_next": backend._sub_next[index], "holding": backend._active_holds.has(index), "lane": lane, "hit": backend._judged[index], "missed": false})
	for lane: int in range(backend.key_count):
		backend.held_lanes[lane] = backend._active_holds[lane] >= 0
	game.effects.clear()
	game.press_ages.fill(1.0)
	game.timing_error.text = ""
	game.get_node("HUD/Judgment").set("text", "AUTO PREVIEW")
	game._update_hud()
	game._update_skin()

func set_range(start: float, end: float, looping: bool) -> Dictionary:
	var duration: float = song.get_length()
	# Decoders and editor metadata can differ slightly in duration precision.
	# Tolerate at most 1 ms of decoder rounding; genuinely out-of-range intervals still fail.
	if not is_finite(start) or not is_finite(end) or end <= start or start >= duration or end > duration + 0.001:
		return {"ok": false, "error": "区间须满足 起点 < 终点 ≤ 音乐长度（负时间为静音）"}
	range_start = start
	range_end = minf(end, duration)
	game.preview_end = range_end
	loop_enabled = looping
	return {"ok": true}

## Reuse the same scene/player/stream. Reset the original monotonic audio-clock baseline on seeks.
func seek_to(seconds: float, resume: bool, prepare: bool = false) -> void:
	if not is_finite(seconds):
		return
	var target: float = minf(seconds, song.get_length())
	var backend: Stage.Backend = game.backend
	_stop_hit_sounds()
	backend.state = Stage.Backend.State.IDLE
	backend._audio.stop()
	backend._lead_in_active = false
	backend._audio_clock_pending = false
	backend._playback_start = maxf(0.0, target)
	backend._preparation_end = target
	backend._last_time = target
	backend._latency = AudioServer.get_output_latency()
	backend._audio.stream = song
	_segment_start = target
	_rebuild_at(target, true)
	playing = resume
	game.mode = "playing" if resume else "stopped"
	backend.state = Stage.Backend.State.PLAYING if resume else Stage.Backend.State.IDLE
	game._auto_active = true
	_show_stage()
	if resume:
		var lead_in: float = game.preparation_seconds if prepare else 0.0
		if lead_in > 0.0 or target < 0.0:
			backend._lead_in_active = true
			backend._lead_in_from = target - lead_in
			backend._lead_in_origin_usec = Time.get_ticks_usec()
			backend._last_time = backend._lead_in_from
		else:
			backend._audio.play(target)

func _stop_hit_sounds() -> void:
	game.stop_hit_sounds()
	for player: AudioStreamPlayer in game._tap_players:
		player.stop()
	for lane: Dictionary in game._hold_players:
		for value: Variant in lane.values():
			(value as AudioStreamPlayer).stop()

func stop_preview() -> void:
	var seconds: float = game.backend._clock()
	playing = false
	game.backend._stop()
	game.backend._last_time = seconds
	game.mode = "stopped"
	_stop_hit_sounds()

func _before_frame() -> void:
	if not playing or game == null:
		return
	var seconds: float = game.backend._clock()
	if seconds >= range_end:
		# End is exclusive. Do not let Auto consume notes after a stalled range boundary.
		game._advance_auto(range_end - 0.00001)
		if loop_enabled:
			cycles += 1
			seek_to(range_start, true)
		else:
			seek_to(range_end, false)

func status() -> Dictionary:
	var time: float = game.backend._clock()
	return {"type": "status", "ready": true, "playing": playing, "time": time, "cursor_time": maxf(_segment_start, time), "preparing": playing and time < _segment_start, "revision": chart_revision, "updates": updates, "cycles": cycles, "scene_loads": 1, "instance": str(game.get_instance_id()), "notes": game.backend._notes.size(), "combo": game.backend._combo, "miss": game.backend._counts.MISS, "latency_ms": game.backend._latency * 1000.0, "bgm_gain": game.backend._audio.volume_linear}
