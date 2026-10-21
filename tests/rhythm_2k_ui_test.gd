## Covers two-lane isolation and the MusicGame-to-audio-clock integration.
extends Node
const Game = preload("res://music_game.tscn")
const Chart = preload("res://rhythm_chart.gd")
var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var ui: Control = Game.instantiate()
	add_child(ui)
	var game: Control = ui.backend
	game.settings.input_ms = 0.0
	game.settings.visual_ms = 45.0
	game.settings.approach = 2.4
	ui.set_difficulty(3)
	ui.start_game()
	check(game._note_lanes.has(0) and game._note_lanes.has(1), "synthetic test exercises both lanes")
	game._hit(game._notes[1], 0)
	check(not game._judged[1], "left press cannot consume right note")
	game._hit(game._notes[1], 1)
	check(game._judged[1] and game._counts.PERFECT == 1, "right lane judges using unchanged timing")
	# Simultaneous lane notes are two independent press edges.
	game._start()
	game._notes[1] = game._notes[0]
	game._hit(game._notes[0], 0)
	game._hit(game._notes[0], 1)
	check(game._counts.PERFECT == 2, "chord scores one note per lane")
	game._hit(game._notes[0], 1)
	check(game._counts.PERFECT == 2, "duplicate right press cannot rescore")
	game._start()
	game._last_time = game._notes[0]
	key_event(game, KEY_A, true)
	key_event(game, KEY_LEFT, true)
	check(game._counts.PERFECT == 1, "left aliases do not double score")
	key_event(game, KEY_A, false)
	check(game._held, "left arrow keeps lane held after A release")
	key_event(game, KEY_LEFT, false)
	check(not game._held, "last left source releases lane")
	game._last_time = game._notes[1]
	key_event(game, KEY_RIGHT, true)
	key_event(game, KEY_D, true)
	check(game._counts.PERFECT == 2, "D and right arrow judge right lane once")
	key_event(game, KEY_RIGHT, false)
	check(game._held_right, "D keeps right lane held")
	key_event(game, KEY_D, false)
	check(not game._held_right, "last right source releases lane")
	game._held = true
	game._held_right = true
	game._stop()
	check(not game._held and not game._held_right, "stop releases both keys")
	ui.set_difficulty(2)
	ui.skip_intro.button_pressed = true
	ui.start_game()
	var stream: AudioStream = game._audio.stream
	var note_times: Array = game._notes.duplicate()
	var before: float = game._clock()
	ui._update_skin()
	check(game.state == 1 and game._audio.stream == stream, "stage update keeps playback")
	check(game._notes == note_times and game._last_time >= before, "stage update keeps absolute note timestamps and monotonic clock")
	check(ui.skin.state.notes.size() == 704, "stage receives Hard chart")
	check(ui.skin.state.notes.any(func(note: Dictionary) -> bool: return note.lane == 0) and ui.skin.state.notes.any(func(note: Dictionary) -> bool: return note.lane == 1), "stage displays both Bad Apple lanes")
	check(absf(ui.skin.state.song_time - game._last_time - 0.045) < 0.001, "stage use existing visual compensation")
	check(ui.skin.travel == 2.4, "stage honor approach duration")
	ui._on_judged(0, "PERFECT", -12.5, 0.0125)
	check(ui.timing_error.text == "-12.5 ms", "early timing is signed below judgement")
	ui._on_judged(1, "GOOD", 58.2, -0.0582)
	check(ui.timing_error.text == "+58.2 ms", "late timing is signed below judgement")
	check(ui.get_node("HUD/Judgment").position.y > ui.size.y * 0.55 and ui.timing_error.position.y > ui.get_node("HUD/Judgment").position.y, "stage place judgement and timing in lower center")
	check(ui.get_node("HUD/Combo").position.x > ui.size.x * 0.6, "combo is at top right")
	ui._on_judged(0, "MISS", 0.0, INF)
	check(ui.timing_error.text == "— ms", "miss does not fabricate a timing offset")
	var neon: Control = ui.skin
	for progress: float in [0.0, 0.3, 0.7, 1.0]:
		check(neon._lane_point(0, 1.0, progress).is_equal_approx(neon._lane_point(1, -1.0, progress)), "neon lane halves share one edge throughout the perspective runway")
	var mapping: Transform2D = neon.playfield_transform()
	check(neon.lane_at_position(mapping * neon._lane_point(0, -0.95, 1.0), true) == 0, "widened left receptor stays inside the visual hit area")
	check(neon.lane_at_position(mapping * neon._lane_point(1, 0.95, 1.0), true) == 1, "widened right receptor stays inside the visual hit area")
	check(neon.lane_at_position(mapping * neon._lane_point(1, 1.2, 1.0), true) == -1, "outside the runway remains outside the hit area")
	var step_a: Vector2 = neon.note_position(0, 0.4) - neon.note_position(0, 0.8)
	var step_b: Vector2 = neon.note_position(0, 0.0) - neon.note_position(0, 0.4)
	var step_c: Vector2 = neon.note_position(0, -0.4) - neon.note_position(0, 0.0)
	check(step_a.y < step_b.y and step_b.y < step_c.y, "neon perspective accelerates on screen toward near edge")
	var depths: Array[float] = []
	for until: float in [0.8, 0.4, 0.0]:
		var position: Vector2 = neon.note_position(0, until)
		var projected: float = (position.y - neon.TOP_Y) / (neon.HIT_Y - neon.TOP_Y)
		depths.append(neon.DEPTH_RATIO * projected / (1.0 + (neon.DEPTH_RATIO - 1.0) * projected))
	check(is_equal_approx(depths[1] - depths[0], depths[2] - depths[1]), "inverse projection recovers constant world-depth speed")
	check(is_equal_approx(neon.note_position(0, neon.travel).y, neon.TOP_Y), "perspective starts at far edge")
	check(neon.note_position(0, 0.0).x < 960.0 and neon.note_position(1, 0.0).x > 960.0, "both lanes retain their sides")
	check(is_equal_approx(neon.note_position(0, 0.0).y, neon.HIT_Y), "neon reaches judgement line at exact note time")
	# Hit afterimages must preserve the consumed note's visual position, not judgement error.
	ui.set_difficulty(3)
	ui.start_game()
	game.settings.input_ms = 25.0
	game._hit(game._notes[0] - 0.06, 0)
	game._hit(game._notes[1] + 0.09, 1)
	check(game._judged[0] and game._judged[1] and game._counts.GOOD == 2, "visual afterimages never delay consumption or score")
	check(ui.effects.size() == 2, "one afterimage per consumed note")
	var left_effect: Dictionary = ui.effects[0]
	var right_effect: Dictionary = ui.effects[1]
	check(is_equal_approx(float(left_effect.seconds_until), 0.015) and is_equal_approx(float(right_effect.seconds_until), -0.135), "input-edge snapshots include visual offset but do not substitute input compensation")
	var left_geometry: Dictionary = neon.hit_note_geometry(left_effect)
	var right_geometry: Dictionary = neon.hit_note_geometry(right_effect)
	check(left_geometry.position.is_equal_approx(neon.note_position(0, 0.015)), "early hit starts at the actual left note")
	check(right_geometry.position.is_equal_approx(neon.note_position(1, -0.135)), "late hit starts at the actual right note")
	neon.travel = 1.0
	check(neon.hit_note_geometry(left_effect).position.is_equal_approx(left_geometry.position), "approach changes cannot move an existing afterimage")
	ui._update_skin()
	check(ui.view_notes[0].hit and ui.view_notes[1].hit, "live note sprites hide while independent afterimages animate")
	ui._on_judged(0, "MISS", 0.0, INF)
	check(neon.hit_note_geometry(ui.effects.back()).is_empty(), "miss does not create a consumed note")
	ui._process(0.7)
	check(ui.effects.is_empty(), "afterimages clear without lingering into subsequent beats")
	ui._on_judged(0, "PERFECT", 0.0, 0.0)
	ui.start_game()
	check(ui.effects.is_empty(), "restart clears previous hit effects")
	# Render the whole effect lifetime, including fade boundaries, to catch degenerate polygons.
	ui.set_process(false)
	game.set_process(false)
	game._audio.stop()
	ui._on_judged(0, "PERFECT", 0.0, 0.0)
	ui._on_judged(1, "GOOD", 60.0, -0.06)
	for frame: int in range(73):
		for effect: Dictionary in ui.effects:
			effect.age = float(frame) / 240.0
		ui._update_skin()
		await RenderingServer.frame_post_draw
	ui.set_process(true)
	game.set_process(true)
	game._finish()
	ui._process(0.0)
	check(ui.mode == "results" and ui.get_node("Modal/Results").visible, "audio completion opens results")
	ui.show_calibration()
	check(game.visible and game.is_processing_input(), "calibration panel retains keyboard input")
	ui.show_menu()
	check(not game.visible and not game.is_processing_input(), "menu disables hidden calibration input")
	ui.start_game()
	ui._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(ui.mode == "stopped" and not game._audio.playing, "focus loss retains stop policy")
	var data: Dictionary = Chart.read_chart(game.BAD_APPLE).data.duplicate(true)
	data.notes_ms = [1000, 1000]
	data.lanes = [0, 1]
	check(Chart.validate(data).ok, "two-lane simultaneous notes accepted")
	data.lanes = [0, 0]
	check(not Chart.validate(data).ok, "duplicate lane-time rejected")
	data.lanes = [0, 2]
	check(not Chart.validate(data).ok, "invalid lane rejected")
	data.lanes = [0]
	check(not Chart.validate(data).ok, "missing lane rejected")
	ui.free()
	print("RHYTHM_2K_UI: PASS" if failures == 0 else "RHYTHM_2K_UI: FAIL %d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func key_event(game: Control, code: Key, down: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	game._input(event)
