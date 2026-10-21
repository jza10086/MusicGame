## Focused clock-offset, judgement, generated audio and prototype lifecycle checks.
## Does not establish physical speaker/display/input latency or human timing feel.
extends Node
const Timing = preload("res://rhythm_timing.gd")
const Synth = preload("res://rhythm_audio.gd")
const Prototype = preload("res://rhythm_prototype.gd")
var failures: int = 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	check(Timing.grade(-40.0) == "PERFECT" and Timing.grade(40.0) == "PERFECT", "perfect includes both boundaries")
	check(Timing.grade(40.01) == "GOOD" and Timing.grade(-90.0) == "GOOD", "good boundaries")
	check(Timing.grade(-150.0) == "OK" and Timing.grade(150.01) == "MISS", "outer boundaries")
	check(absf(Timing.error_ms(2.08, 2.0, 80.0)) < 0.001, "positive compensation corrects late input")
	check(Timing.visual_time(2.0, 100.0) == 2.1, "positive visual offset advances notes")
	var values: Array[float] = [80.0, 90.0, 500.0, 70.0]
	check(Timing.median(values) == 85.0 and values[0] == 80.0, "robust median does not mutate observations")
	var notes: Array[float] = Timing.note_times(120.0, false)
	check(notes[0] == 2.0 and notes.size() == 72, "four beat count-in and mixed pattern")
	var calibration: Array[float] = Timing.note_times(120.0, true)
	check(calibration.size() == 64 and calibration[1] - calibration[0] == 0.5, "calibration regular beats")
	var stream: AudioStreamWAV = Synth.build(calibration, 120.0)
	var onset: int = int(calibration[0] * Synth.RATE)
	check(stream.mix_rate == 44100 and stream.format == AudioStreamWAV.FORMAT_16_BITS, "PCM audio configuration")
	check(stream.data.decode_s16((onset - 1) * 2) == 0, "no cue ahead of chart sample")
	var peak: int = 0
	for index: int in range(onset, onset + 128):
		peak = maxi(peak, absi(stream.data.decode_s16(index * 2)))
	check(peak > 100, "audible cue begins at scheduled sample")
	var game: Control = Prototype.new()
	add_child(game)
	game._select_track(0)
	game.settings.input_ms = 0.0
	game.settings.visual_ms = 0.0
	game._start()
	var first: float = game._notes[0]
	game._hit(first - 0.4)
	check(game._counts.PERFECT == 0 and not game._judged[0], "stray press cannot consume future note")
	game._hit(first + 0.02)
	check(game._counts.PERFECT == 1 and game._combo == 1, "valid press consumes one note")
	game._hit(first + 0.021)
	check(game._counts.PERFECT == 1, "duplicate cannot score same note")
	var echo: InputEventKey = InputEventKey.new()
	echo.physical_keycode = KEY_A
	echo.pressed = true
	echo.echo = true
	game._input(echo)
	check(game._counts.PERFECT == 1, "keyboard autorepeat ignored")
	game._last_time = game._notes.back() + 0.6
	game._process(0.0)
	check(game._counts.MISS == game._notes.size() - 1, "frame stall expires all overdue notes")
	game._start()
	check(game._counts.MISS == 0 and game._combo == 0 and game._last_time == 0.0, "restart clears score and monotonic clock")
	game._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(game.state == 0 and not game._audio.playing and not game._held, "focus loss stops audio and resets hold")
	game._set_calibration(true)
	game._start()
	for index: int in range(16):
		game._hit(game._notes[index] + 0.08)
	game._use_suggestion()
	check(absf(float(game.settings.input_ms) - 80.0) < 0.01, "calibration proposes raw median, not compensated residual")
	game._stop()
	var chart_script: Script = load("res://rhythm_chart.gd")
	var chart: Dictionary = chart_script.read_chart(game.BAD_APPLE)
	check(chart.ok, "downloaded song and converted chart load")
	if chart.ok:
		check(chart.notes.size() == 287 and absf(chart.notes[0] - 13.991782) < 0.00001, "converted chart note count and absolute offset")
		check(chart.duration > chart.notes.back() + 0.15, "audio covers final hit window")
		var invalid: Dictionary = chart.data.duplicate(true)
		invalid.notes_ms = [1000, 1000]
		invalid.lanes = [0, 0]
		check(not chart_script.validate(invalid).ok, "duplicate note times rejected")
		invalid.lanes = [0]
		invalid.notes_ms = [-10]
		check(not chart_script.validate(invalid).ok, "negative note times rejected")
		invalid.notes_ms = [1000]
		invalid.audio_file = "../outside.ogg"
		check(not chart_script.validate(invalid).ok, "audio traversal rejected")
		game._set_calibration(false)
		game.settings.input_ms = 65.0
		game.settings.visual_ms = -25.0
		var expected_counts: Array[int] = [287, 532, 704]
		for index: int in range(1, 4):
			game._select_track(index)
			check(game.state == 0 and not game._audio.playing and game._notes.is_empty(), "difficulty switch stops playback and removes old notes")
			check(game._counts.PERFECT == 0 and game._counts.MISS == 0 and game._combo == 0, "difficulty switch clears score")
			check(game.settings.input_ms == 65.0 and game.settings.visual_ms == -25.0, "difficulty switch preserves calibration")
			check(game._track_selector.selected == index and game._track_info.text.contains(game.CHART_NAMES[index - 1]), "selector and chart metadata agree")
			game._start(true)
			check(game._audio.playing and game._notes.size() == expected_counts[index - 1], "song playback uses selected difficulty")
			check(game._note_lanes.has(0) and game._note_lanes.has(1), "Bad Apple includes both lanes")
			game._hit(game._notes[0] + 0.065, 1 - game._note_lanes[0])
			check(not game._judged[0], "right key cannot consume a left chart note")
			check(game._audio.stream.resource_path == chart.audio.resource_path, "difficulties share the matching song")
			check(absf(game._last_time - (chart.notes[0] - 3.0)) < 0.001, "intro skip preserves absolute song time")
			game._finish()
			check(game._counts.MISS == expected_counts[index - 1] and game.state == 2, "song end resolves pending notes and terminates")
			game._start(true)
			game._hit(game._notes[0] + 0.065, game._note_lanes[0])
			check(game._counts.PERFECT == 1, "selected difficulty supports compensated input")
		game._select_track(0)
		check(game.state == 0 and not game._audio.playing and game._counts.PERFECT == 0, "returning to synth clears active song")
	game._stop()
	game.free()
	print("RHYTHM_1K: PASS" if failures == 0 else "RHYTHM_1K: FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
