## Neon chart-driven stage driven exclusively by the shared audio and calibration backend.
extends Control
## Only the embedded authoring preview may continue when its canvas loses focus.
var editor_preview: bool = false
var preview_end: float = INF
const Backend = preload("rhythm_backend.gd")
const ACCENT: Color = Color("73f5eb")
var backend: Backend
@onready var skin: Control = $Backdrop/NeonStage
## Preparation is presentation time only; song playback starts after it completes.
@export_range(0.0, 15.0, 1.0) var preparation_seconds: float = 5.0
var preparation_remaining: float = 0.0
var mode: String = "idle"
var ambient: float = 0.0
var effects: Array[Dictionary] = []
var press_ages: Array[float] = [1.0, 1.0]
var _tap_players: Array[AudioStreamPlayer] = []
var _chart_players: Array[Array] = [[], [], [], []]
var _chart_voice_next: Array[int] = [0, 0, 0, 0]
var _tap_buses: Array[StringName] = []
const TAP_PAN: float = 0.15
var judgment_age: float = 0.0
@onready var timing_error: Label = $HUD/TimingError
var _calibration_mode: bool = false
## Test playback only. The menu/API choice is captured at the start of each round.
@export var auto_play: bool = false
@onready var auto_status: Label = $HUD/AutoStatus
var _auto_active: bool = false
var _auto_next: int = 0
var _auto_release_at: Array[float] = [-INF, -INF]
var view_notes: Array[Dictionary] = []
var mouse_lane: int = -1
var _tap_streams: Dictionary[String, AudioStream] = {}
var _hold_players: Array[Dictionary] = [{}, {}, {}, {}]
var _tap_preview: AudioStreamPlayer
@onready var _leaderboard: CenterContainer = $HUD/Leaderboard
@onready var _leaderboard_accuracy: Label = $HUD/Leaderboard/Panel/Rows/Self/Accuracy

@export var auto_start: bool = true
@export_file("*.json") var chart_path: String = Backend.DEFAULT_CHART
@export var show_return_button: bool = false
var skip_intro: bool = false
var listen_calibration: bool = false
signal return_requested
signal playback_stopped
signal playback_finished
signal playback_failed(message: String)

func _ready() -> void:
	# SceneTree emits this before node processing, so due inputs precede miss checks.
	get_tree().process_frame.connect(_auto_frame)
	backend = Backend.new()
	backend.editor_preview = editor_preview
	backend.name = "AudioBackend"
	add_child(backend)
	if not backend.last_error.is_empty():
		push_error(backend.last_error)
		set_process(false)
		set_process_input(false)
		return
	backend.set_process_input(false)
	backend.note_judged.connect(_on_judged)
	backend.hit_feedback.connect(_on_hit_feedback)
	backend.press_feedback.connect(_on_press_feedback)
	var tap: AudioStreamWAV = Backend.Synth.build_tap()
	_tap_streams["synth"] = tap
	for id: String in Backend.Synth.TAP_FILES:
		if id != "synth":
			_tap_streams[id] = load(Backend.Paths.resolve(Backend.Synth.TAP_ROOT + Backend.Synth.TAP_FILES[id])) as AudioStream
	_tap_preview = AudioStreamPlayer.new()
	_tap_preview.name = "TapPreview"
	add_child(_tap_preview)
	for lane: int in range(4):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "TapLane%d" % lane
		player.bus = _create_tap_bus(lane)
		player.stream = tap
		player.max_polyphony = 4
		add_child(player)
		_tap_players.append(player)
		for voice_index: int in range(8):
			var voice: AudioStreamPlayer = AudioStreamPlayer.new()
			voice.name = "ChartSound%d_%d" % [lane, voice_index]
			voice.bus = player.bus
			add_child(voice)
			_chart_players[lane].append(voice)
		for kind: String in ["hold_start", "hold_sub", "hold_end"]:
			var hold_player: AudioStreamPlayer = AudioStreamPlayer.new()
			hold_player.name = kind + str(lane)
			hold_player.bus = player.bus
			hold_player.max_polyphony = 8
			add_child(hold_player)
			_hold_players[lane][kind] = hold_player
	$HUD/PauseButton.pressed.connect(pause_game)
	$Modal/Pause/Resume.pressed.connect(start_game)
	$Modal/Pause/Back.pressed.connect(_request_return)
	$Modal/Results/Again.pressed.connect(start_game)
	$Modal/Results/Home.pressed.connect(_request_return)
	$Modal/Pause/Back.visible = show_return_button
	$Modal/Results/Home.visible = show_return_button
	configure_lane_feedback()
	stop_playback()
	if auto_start and not editor_preview:
		start_game()


func start_game() -> void:
	_begin_playback(false)

func _begin_playback(calibration: bool = false) -> void:
	_calibration_mode = calibration
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	stop_hit_sounds()
	_auto_active = auto_play and not calibration
	_auto_next = 0
	_auto_release_at.fill(-INF)
	backend.set_process_input(false)
	backend._set_calibration(calibration and listen_calibration)
	var track: int = 0
	if not calibration and not chart_path.is_empty():
		var resolved: String = chart_path if chart_path.begins_with("res://") else Backend.Paths.resolve(chart_path)
		track = backend.chart_paths.find(resolved) + 1
		if track == 0:
			stop_playback()
			var message: String = "谱面不在当前谱面库中：" + chart_path
			push_error(message)
			playback_failed.emit(message)
			return
	backend._select_track(track)
	backend._start(false if calibration else skip_intro, preparation_seconds, calibration)
	configure_lane_feedback()
	if backend.state != Backend.State.PLAYING:
		var message: String = backend.last_error
		stop_playback()
		push_error(message)
		playback_failed.emit(message)
		return
	view_notes.clear()
	for index: int in range(backend._notes.size()):
		view_notes.append({"time": backend._notes[index], "end": backend._note_ends[index], "subs": backend._note_subs[index], "sub_next": 0, "holding": false, "lane": backend._note_lanes[index], "hit": false, "missed": false})
	effects.clear()
	press_ages.fill(1.0)
	mouse_lane = -1
	mode = "playing"
	$HUD.show()
	$Modal.hide()
	$HUD/Judgment.text = "READY"
	timing_error.text = ""
	$HUD/TrackTitle.text = "音画校准" if calibration else ("双轨合成测试" if track == 0 else backend.chart_names[track - 1])
	judgment_age = 0.0
	_update_hud()
	_update_skin()

## Stop on focus loss without introducing a second pause clock.

func pause_game() -> void:
	if mode != "playing":
		return
	preparation_remaining = 0.0
	$HUD/Countdown.text = ""
	backend._stop()
	stop_hit_sounds()
	mouse_lane = -1
	mode = "stopped"
	press_ages.fill(1.0)
	if _calibration_mode:
		playback_stopped.emit()
		return
	$Modal.show()
	$Modal/Pause.show()
	$Modal/Results.hide()

func finish_game() -> void:
	if _calibration_mode:
		mode = "stopped"
		playback_finished.emit()
		return
	mode = "results"
	$HUD.hide()
	$Modal.show()
	$Modal/Pause.hide()
	$Modal/Results.show()
	var accuracy: float = _accuracy()
	$Modal/Results/Grade.text = "SS" if accuracy >= 100.0 else ("S" if accuracy >= 95.0 else ("A" if accuracy >= 85.0 else ("B" if accuracy >= 70.0 else "C")))
	$Modal/Results/FinalScore.text = "%.2f%%" % accuracy
	$Modal/Results/FinalAccuracy.text = "准确率  /  ACCURACY"
	$Modal/Results/Stats.text = "PERFECT %d   GOOD %d   OK %d   MISS %d\n最长连击 %d / %d" % [backend._counts.PERFECT, backend._counts.GOOD, backend._counts.OK, backend._counts.MISS, backend._best_combo, backend._total_units]
	if _auto_active:
		$Modal/Results/Stats.text += "\nAUTO 自动演奏测试"

## Configure the next round without mixing automatic and human inputs mid-song.

func set_auto_play(enabled: bool) -> void:
	auto_play = enabled


func _presentation_time(audio_time: float) -> float:
	if editor_preview and mode == "playing":
		return minf(audio_time, preview_end - 0.00001)
	return audio_time

func _auto_frame() -> void:
	if _auto_active and mode == "playing" and backend != null and backend.state == Backend.State.PLAYING:
		_advance_auto(_presentation_time(backend._clock()))

## Feed scheduled input timestamps into the unchanged judge before its miss sweep.
## Advance holds chronologically between heads, including after a stalled frame.
## Sounds still use the same players/levels as manual play; no separate song clock.

func _advance_auto(audio_time: float) -> void:
	if not _auto_active or mode != "playing" or backend.state != Backend.State.PLAYING:
		return
	var compensation: float = float(backend.settings.input_ms) / 1000.0
	var judged_time: float = audio_time - compensation
	while _auto_next < backend._notes.size() and backend._notes[_auto_next] <= judged_time:
		var index: int = _auto_next
		var note_time: float = backend._notes[index]
		var lane: int = backend._note_lanes[index]
		backend._update_holds(note_time)
		if not backend._judged[index] and not backend._active_holds.has(index):
			backend._hit(note_time + compensation, lane)
			press_ages[lane] = 0.0
			if backend._note_ends[index] > note_time:
				_auto_release_at[lane] = backend._note_ends[index]
			else:
				_auto_release_at[lane] = note_time + 0.06
		_auto_next += 1
	backend._update_holds(judged_time)
	for lane: int in range(backend.key_count):
		backend.held_lanes[lane] = judged_time < _auto_release_at[lane]

func _score() -> int:
	return backend.scoring.score()

func _accuracy() -> float:
	return backend.scoring.accuracy() * 100.0

func _on_judged(lane: int, quality: String, error_ms: float, seconds_until: float) -> void:
	# Freeze the actual consumed note, including visual calibration; the effect never resamples the clock.
	effects.append({"lane": lane, "quality": quality, "age": 0.0, "seconds_until": seconds_until, "approach": float(backend.settings.approach)})
	$HUD/Judgment.text = quality
	timing_error.text = "— ms" if quality == "MISS" else "%+.1f ms" % error_ms
	judgment_age = 0.0

func _process(delta: float) -> void:
	if backend == null:
		return
	ambient += delta
	judgment_age += delta
	for lane: int in range(backend.key_count):
		press_ages[lane] = minf(1.0, press_ages[lane] + delta)
	for effect: Dictionary in effects:
		effect.age += delta
	effects = effects.filter(func(effect: Dictionary) -> bool: return float(effect.age) < 0.65)
	if mode == "playing":
		_update_hud()
		if backend.state == Backend.State.FINISHED:
			finish_game()
		elif backend.state == Backend.State.IDLE:
			pause_game()
	_update_skin()

func _update_hud() -> void:
	preparation_remaining = maxf(0.0, backend._preparation_end - backend._clock())
	$HUD/Score.text = "%.2f%%" % _accuracy()
	_leaderboard_accuracy.text = $HUD/Score.text
	$HUD/Combo.text = str(backend._combo)
	$HUD/Progress.value = clampf(backend._last_time / backend._duration * 100.0, 0, 100)
	var remaining: int = ceili(maxf(0.0, backend._duration - backend._last_time))
	$HUD/Remaining.text = "%02d:%02d" % [remaining / 60, remaining % 60]
	$HUD/Judgment.modulate.a = clampf(1.4 - judgment_age, 0.25, 1.0)
	timing_error.modulate.a = $HUD/Judgment.modulate.a
	$HUD/Countdown.text = str(ceili(preparation_remaining)) if preparation_remaining > 0.0 else ""

func _update_skin() -> void:
	if not is_instance_valid(skin) or backend == null:
		return
	# Sorted chart times bound rendering work to the visible approach window.
	# Active holds remain visible even when their heads precede that window.
	var song_time: float = backend.Timing.visual_time(_presentation_time(backend._clock()), float(backend.settings.visual_ms))
	var first: int = backend._notes.bsearch(song_time - 0.16)
	var last: int = backend._notes.bsearch(song_time + float(backend.settings.approach), false)
	var indices: Array[int] = []
	for active: int in backend._active_holds:
		if active >= 0 and active < first:
			indices.append(active)
	for index: int in range(first, mini(last, view_notes.size())):
		indices.append(index)
	indices.sort()
	var visible_notes: Array[Dictionary] = []
	for index: int in indices:
		view_notes[index].hit = backend._judged[index]
		view_notes[index].holding = backend._active_holds.has(index)
		view_notes[index].sub_next = backend._sub_next[index]
		visible_notes.append(view_notes[index])
	_leaderboard.visible = not _calibration_mode
	auto_status.visible = _auto_active and mode in ["playing", "stopped"]
	skin.set_state({"key_count": backend.key_count, "mode": "playing" if mode in ["playing", "stopped"] else "menu", "time": ambient, "song_time": song_time, "approach": backend.settings.approach, "notes": [] if _calibration_mode and backend._calibration else visible_notes, "effects": effects, "press_ages": press_ages.duplicate(), "pressed": backend.held_lanes.duplicate(), "combo": backend._combo})

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			pause_game()
			get_viewport().set_input_as_handled()
		elif mode == "playing" and not _auto_active:
			backend._input(event)
			_update_skin()

func _on_press_feedback(lane: int, hit: bool) -> void:
	press_ages[lane] = 0.0
	if not hit and not backend._calibration and backend._active_holds[lane] < 0:
		_play_tap(_tap_players[lane], false)

func _notification(what: int) -> void:
	if not editor_preview and what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		pause_game()

func _play_tap(player: AudioStreamPlayer, success: bool) -> void:
	_play_sound(player, "success" if success else "empty")

func _play_sound(player: AudioStreamPlayer, kind: String, chart_sound: String = "") -> void:
	var id: String = str(backend.settings[kind + "_sound"])
	if bool(backend.settings.use_chart_sounds) and _tap_streams.has(chart_sound):
		id = chart_sound
	var stream: AudioStream = _tap_streams.get(id, _tap_streams["synth"])
	if player.stream != stream:
		player.stream = stream
	player.volume_linear = float(backend.settings[kind + "_volume"]) * db_to_linear(Backend.Synth.TAP_GAIN_DB.get(id, Backend.Synth.TAP_GAIN_DB["synth"]))
	player.play()

func _on_hit_feedback(lane: int, kind: String, chart_time: float) -> void:
	var player: AudioStreamPlayer = _tap_players[lane] if kind == "success" else _hold_players[lane][kind]
	var id: String = str(backend.chart_sounds.get(Backend.Chart.sound_key(chart_time, lane), ""))
	if bool(backend.settings.use_chart_sounds) and _tap_streams.has(id):
		# A fixed voice pool preserves tails when adjacent notes use different streams.
		var slot: int = _chart_voice_next[lane]
		for offset: int in range(_chart_players[lane].size()):
			var candidate: int = (slot + offset) % _chart_players[lane].size()
			if not (_chart_players[lane][candidate] as AudioStreamPlayer).playing:
				slot = candidate
				break
		player = _chart_players[lane][slot]
		player.stop()
		_chart_voice_next[lane] = (slot + 1) % _chart_players[lane].size()
	_play_sound(player, kind, id)
	press_ages[lane] = 0.0





## Scope-owned lane buses keep feedback panning independent from BGM and centered preview.

func _create_tap_bus(lane: int) -> StringName:
	var bus_name: StringName = StringName("RhythmTap_%s_%s" % [get_instance_id(), lane])
	var index: int = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, &"Master")
	var panner: AudioEffectPanner = AudioEffectPanner.new()
	panner.pan = lerpf(-TAP_PAN, TAP_PAN, float(lane) / 3.0)
	AudioServer.add_bus_effect(index, panner)
	_tap_buses.append(bus_name)
	return bus_name

## Stop every feedback voice when seeking, looping, switching charts or leaving play.

func stop_hit_sounds() -> void:
	for player: AudioStreamPlayer in _tap_players:
		player.stop()
	for lane: Dictionary in _hold_players:
		for player: AudioStreamPlayer in lane.values():
			player.stop()
	for lane: Array in _chart_players:
		for player: AudioStreamPlayer in lane:
			player.stop()

func _exit_tree() -> void:
	stop_hit_sounds()
	for lane_players: Dictionary in _hold_players:
		for player: AudioStreamPlayer in lane_players.values():
			player.stop()
	for player: AudioStreamPlayer in _tap_players:
		player.stop()
	for bus_name: StringName in _tap_buses:
		var index: int = AudioServer.get_bus_index(bus_name)
		if index >= 0:
			AudioServer.remove_bus(index)
	_tap_buses.clear()

## Reuse four sound players; reset only lane presentation on chart switches.

func configure_lane_feedback() -> void:
	press_ages.resize(backend.key_count)
	press_ages.fill(1.0)
	_auto_release_at.resize(backend.key_count)
	_auto_release_at.fill(-INF)
	effects.clear()
	stop_hit_sounds()
	for lane: int in range(_tap_players.size()):
		_tap_players[lane].stop()
		for player: AudioStreamPlayer in _hold_players[lane].values():
			player.stop()
		var index: int = AudioServer.get_bus_index(_tap_players[lane].bus)
		var panner: AudioEffectPanner = AudioServer.get_bus_effect(index, 0) as AudioEffectPanner
		panner.pan = lerpf(-TAP_PAN, TAP_PAN, float(lane) / float(backend.key_count - 1)) if lane < backend.key_count else 0.0


## Clear presentation and stop audio when returning to the owning screen.
func stop_playback() -> void:
	_auto_active = false
	preparation_remaining = 0.0
	$HUD/Countdown.text = ""
	backend._stop()
	stop_hit_sounds()
	effects.clear()
	press_ages.fill(1.0)
	view_notes.clear()
	mode = "idle"
	$HUD.hide()
	$Modal.hide()
	_update_skin()

func _request_return() -> void:
	stop_playback()
	return_requested.emit()

## The test scene owns calibration controls; this scene supplies the same stage and clock.
func start_calibration(listen: bool) -> void:
	listen_calibration = listen
	_begin_playback(true)
