## Neon two-key stage driven exclusively by the shared audio and calibration backend.
extends Control
const Backend = preload("res://rhythm_prototype.gd")
const STAGE: PackedScene = preload("res://skins/neon.tscn")
const ACCENT: Color = Color("73f5eb")
var backend: Backend
var skin: Control
var difficulty: int = 0
var mode: String = "menu"
var ambient: float = 0.0
var effects: Array[Dictionary] = []
var judgment_age: float = 0.0
var timing_error: Label
var reduced_motion: bool = false
var track_choice: OptionButton
var calibration_close: Button
var skip_intro: CheckBox
var view_notes: Array[Dictionary] = []
var mouse_lane: int = -1

func _ready() -> void:
	theme = Theme.new()
	theme.default_font = preload("res://assets/Chinese.ttc")
	theme.default_font_size = 24
	for path: String in ["Header/Brand", "HUD/Score", "HUD/Combo", "Modal/Results/Grade", "Modal/Results/FinalScore"]:
		get_node(path).add_theme_font_override("font", preload("res://assets/Display.ttf"))
	timing_error = Label.new()
	timing_error.name = "TimingError"
	timing_error.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timing_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$HUD.add_child(timing_error)
	backend = Backend.new()
	backend.name = "AudioBackend"
	add_child(backend)
	backend.hide()
	backend.set_process_input(false)
	backend.note_judged.connect(_on_judged)
	$Menu/Begin.pressed.connect(start_game)
	$Menu/Motion.pressed.connect(toggle_motion)
	$HUD/PauseButton.pressed.connect(pause_game)
	$Modal/Pause/Resume.pressed.connect(start_game)
	$Modal/Pause/Restart.pressed.connect(show_calibration)
	$Modal/Pause/Back.pressed.connect(show_menu)
	$Modal/Results/Again.pressed.connect(start_game)
	$Modal/Results/Home.pressed.connect(show_menu)
	$Menu/Easy.hide()
	$Menu/Hard.hide()
	track_choice = OptionButton.new()
	for title: String in ["Bad Apple!! / Easy", "Bad Apple!! / Normal", "Bad Apple!! / Hard", "双轨合成测试"]:
		track_choice.add_item(title)
	track_choice.position = Vector2(802, 767)
	track_choice.size = Vector2(568, 60)
	track_choice.item_selected.connect(set_difficulty)
	$Menu.add_child(track_choice)
	var options: VBoxContainer = VBoxContainer.new()
	options.position = Vector2(1450, 680)
	options.custom_minimum_size = Vector2(370, 0)
	options.add_theme_constant_override("separation", 18)
	$Menu.add_child(options)
	$Menu/Motion.position = Vector2(1450, 580)
	$Menu/Motion.size = Vector2(370, 60)
	skip_intro = CheckBox.new()
	skip_intro.text = "从首音前 3 秒开始"
	options.add_child(skip_intro)
	var calibrate: Button = Button.new()
	calibrate.text = "音画校准"
	calibrate.pressed.connect(show_calibration)
	options.add_child(calibrate)
	calibration_close = Button.new()
	calibration_close.text = "返回双键舞台"
	calibration_close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	calibration_close.position = Vector2(size.x - 300, 20)
	calibration_close.size = Vector2(270, 50)
	calibration_close.pressed.connect(show_menu)
	add_child(calibration_close)
	calibration_close.hide()
	$Modal/Pause/PauseTitle.text = "本轮已停止"
	$Modal/Pause/PauseText.text = "重新开始会重置音频时钟与成绩。"
	$Modal/Pause/Resume.text = "重新演奏   →"
	$Modal/Pause/Restart.text = "音画校准"
	$HUD/Countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$HUD/Progress.show_percentage = false
	skin = STAGE.instantiate()
	$Backdrop.add_child(skin)
	_update_skin()
	_apply_theme()
	show_menu()
	resized.connect(_layout_screen)
	_layout_screen()

func set_difficulty(value: int) -> void:
	difficulty = clampi(value, 0, 3)
	if backend == null:
		return
	backend._select_track(0 if difficulty == 3 else difficulty + 1)
	track_choice.select(difficulty)
	$Menu/Duration.text = "双轨练习\n左右交替" if difficulty == 3 else "%d NOTES\nBad Apple!! · 双轨" % [287, 532, 704][difficulty]

func show_menu() -> void:
	backend._stop()
	backend.hide()
	backend.set_process_input(false)
	calibration_close.hide()
	effects.clear()
	view_notes.clear()
	mouse_lane = -1
	mode = "menu"
	$Header.show()
	$Footer.show()
	$Menu.show()
	$HUD.hide()
	$Modal.hide()
	set_difficulty(difficulty)
	$Footer.text = "左轨 A / ←   ·   右轨 D / →   ·   双押同时按左右键   ·   ESC 停止本轮"
	$Menu/Instruction.text = "左轨 A / ←   右轨 D / →\n音符抵达光线时，轻按对应按键。"
	_update_skin()

func show_calibration() -> void:
	backend._stop()
	mode = "calibration"
	backend.show()
	backend.set_process_input(true)
	calibration_close.show()

func start_game() -> void:
	backend.hide()
	backend.set_process_input(false)
	backend._set_calibration(false)
	backend._select_track(0 if difficulty == 3 else difficulty + 1)
	backend._start(skip_intro.button_pressed)
	if backend.state != Backend.State.PLAYING:
		$Menu/Duration.text = backend._status.text
		return
	view_notes.clear()
	for index: int in range(backend._notes.size()):
		view_notes.append({"time": backend._notes[index], "lane": backend._note_lanes[index], "hit": false, "missed": false})
	effects.clear()
	mouse_lane = -1
	mode = "playing"
	$Header.hide()
	$Footer.hide()
	$Menu.hide()
	$HUD.show()
	$Modal.hide()
	calibration_close.hide()
	$HUD/Judgment.text = "READY"
	timing_error.text = ""
	$HUD/TrackTitle.text = "双轨合成测试" if difficulty == 3 else "Bad Apple!! / " + backend.CHART_NAMES[difficulty]
	judgment_age = 0.0
	_update_hud()
	_update_skin()

## Preserve the prototype's stop-on-focus-loss policy; no second pause clock.
func pause_game() -> void:
	if mode != "playing":
		return
	backend._stop()
	mouse_lane = -1
	mode = "stopped"
	$Modal.show()
	$Modal/Pause.show()
	$Modal/Results.hide()

func finish_game() -> void:
	mode = "results"
	$HUD.hide()
	$Modal.show()
	$Modal/Pause.hide()
	$Modal/Results.show()
	var accuracy: float = _accuracy()
	$Modal/Results/Grade.text = "SS" if accuracy >= 100.0 else ("S" if accuracy >= 95.0 else ("A" if accuracy >= 85.0 else ("B" if accuracy >= 70.0 else "C")))
	$Modal/Results/FinalScore.text = "%07d" % _score()
	$Modal/Results/FinalAccuracy.text = "%.2f%%  ACCURACY" % accuracy
	$Modal/Results/Stats.text = "PERFECT %d   GOOD %d   OK %d   MISS %d\n最长连击 %d / %d" % [backend._counts.PERFECT, backend._counts.GOOD, backend._counts.OK, backend._counts.MISS, backend._best_combo, backend._notes.size()]

func _score() -> int:
	return roundi((backend._counts.PERFECT + backend._counts.GOOD * 0.65 + backend._counts.OK * 0.3) / maxf(1.0, backend._notes.size()) * 1000000.0)

func _accuracy() -> float:
	var count: int = backend._counts.PERFECT + backend._counts.GOOD + backend._counts.OK + backend._counts.MISS
	return 100.0 if count == 0 else (backend._counts.PERFECT + backend._counts.GOOD * 0.65 + backend._counts.OK * 0.3) / count * 100.0

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
	$HUD/Score.text = "%07d" % _score()
	$HUD/Combo.text = str(backend._combo)
	$HUD/Accuracy.text = "%.2f%%  ACCURACY" % _accuracy()
	$HUD/Progress.value = clampf(backend._last_time / backend._duration * 100.0, 0, 100)
	var remaining: int = ceili(maxf(0.0, backend._duration - backend._last_time))
	$HUD/Remaining.text = "%02d:%02d" % [remaining / 60, remaining % 60]
	$HUD/Judgment.modulate.a = clampf(1.4 - judgment_age, 0.25, 1.0)
	timing_error.modulate.a = $HUD/Judgment.modulate.a
	$HUD/Countdown.text = ""

func _update_skin() -> void:
	if not is_instance_valid(skin) or backend == null:
		return
	for index: int in range(mini(view_notes.size(), backend._judged.size())):
		view_notes[index].hit = backend._judged[index]
	skin.set_state({"mode": "playing" if mode in ["playing", "stopped"] else "menu", "time": 0.0 if reduced_motion else ambient, "song_time": backend.Timing.visual_time(backend._clock(), float(backend.settings.visual_ms)), "approach": backend.settings.approach, "notes": view_notes, "effects": [] if reduced_motion else effects, "pressed": [backend._held, backend._held_right], "combo": backend._combo})

func _input(event: InputEvent) -> void:
	if mode == "calibration":
		return
	if event is InputEventKey:
		if event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			pause_game()
			get_viewport().set_input_as_handled()
		elif mode == "playing":
			backend._input(event)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready():
		pause_game()

func _apply_theme() -> void:
	var accent:Color = ACCENT
	for node: Button in find_children("*","Button",true,false):
		if node is CheckBox or backend.is_ancestor_of(node):
			continue
		var normal: StyleBoxFlat = StyleBoxFlat.new()
		normal.bg_color = Color(0.045,0.065,0.105,0.90)
		normal.border_color = Color(accent,0.32)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(12)
		normal.content_margin_left = 26
		normal.content_margin_right = 26
		var hover: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(accent,0.20)
		hover.border_color = accent
		var focus: StyleBoxFlat = normal.duplicate() as StyleBoxFlat
		focus.bg_color = Color.TRANSPARENT
		focus.border_color = Color.WHITE
		focus.set_border_width_all(3)
		node.add_theme_stylebox_override("normal",normal)
		node.add_theme_stylebox_override("hover",hover)
		node.add_theme_stylebox_override("pressed",hover)
		node.add_theme_stylebox_override("focus",focus)
		node.add_theme_color_override("font_color",Color("e9f1f5"))
		node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for path: String in ["Menu/Begin","Modal/Pause/Resume","Modal/Results/Again"]:
		var button:Button = get_node(path)
		var filled:StyleBoxFlat = button.get_theme_stylebox("normal").duplicate()
		filled.bg_color = accent
		button.add_theme_stylebox_override("normal",filled)
		var filled_hover: StyleBoxFlat = filled.duplicate() as StyleBoxFlat
		filled_hover.bg_color = accent.lightened(0.15)
		var filled_pressed: StyleBoxFlat = filled.duplicate() as StyleBoxFlat
		filled_pressed.bg_color = accent.darkened(0.10)
		button.add_theme_stylebox_override("hover",filled_hover)
		button.add_theme_stylebox_override("pressed",filled_pressed)
		for color_name: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			button.add_theme_color_override(color_name,Color("142330"))
	for path: String in ["Menu/Eyebrow","Menu/SelectHint","HUD/Score","HUD/Combo","HUD/Judgment","HUD/TimingError","Modal/Results/Grade","Modal/Results/FinalScore"]:
		get_node(path).add_theme_color_override("font_color",accent)
	if mode == "menu":
		$HUD/TrackTitle.text = "霓虹回响"
	$HUD/TrackEyebrow.text = "LUMINOUS / TWO KEY RHYTHM"


func toggle_motion() -> void:
	reduced_motion = not reduced_motion
	$Menu/Motion.text = "动态效果：" + ("舒缓" if reduced_motion else "完整")
	_update_skin()


func _place(path: String, rect: Rect2, font_size: int = 0) -> void:
	var control: Control = get_node(path)
	if font_size > 0: control.add_theme_font_size_override("font_size", font_size)
	control.position = rect.position
	control.size = rect.size


func _layout_screen() -> void:
	if not is_node_ready(): return
	$Backdrop.size = size
	$HUD.size = size
	$Modal.size = size
	$Modal/Shade.size = size
	var center_offset: Vector2 = (size - Vector2(1920,1080)) * 0.5
	for node: Control in [$Header, $Menu, $Modal/Pause, $Modal/Results]:
		node.position = center_offset
	$Footer.position = Vector2(72, size.y - 73)
	# Only live game information belongs on stage. Descriptions stay in selection.
	for path: String in ["HUD/TrackEyebrow", "HUD/TrackSub", "HUD/ScoreLabel", "HUD/Best", "HUD/Accuracy", "Header/Edition", "Header/Rule"]:
		get_node(path).hide()
	_place("HUD/TrackTitle", Rect2(48, 32, 380, 56), 32)
	_place("HUD/Score", Rect2(size.x - 418, 28, 270, 58), 42)
	$HUD/Score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place("HUD/PauseButton", Rect2(size.x - 108, 30, 62, 62), 25)
	$HUD/PauseButton.text = "■"
	for style_name: String in ["normal", "hover", "pressed", "focus"]:
		var box: StyleBoxFlat = $HUD/PauseButton.get_theme_stylebox(style_name).duplicate() as StyleBoxFlat
		box.content_margin_left = 0
		box.content_margin_right = 0
		$HUD/PauseButton.add_theme_stylebox_override(style_name, box)
	$HUD/PauseButton.tooltip_text = ""
	$HUD/PauseButton.add_theme_constant_override("outline_size", 0)
	_place("HUD/Combo", Rect2(size.x - 700, 19, 150, 62), 48)
	$HUD/Combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place("HUD/ComboLabel", Rect2(size.x - 535, 42, 110, 24), 16)
	$HUD/ComboLabel.text = "COMBO"
	_place("HUD/Judgment", Rect2(size.x * 0.5 - 200, size.y * 0.60, 400, 56), 42)
	$HUD/Judgment.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place("HUD/TimingError", Rect2(size.x * 0.5 - 200, size.y * 0.60 + 58, 400, 36), 26)
	_place("HUD/Progress", Rect2(0, 0, size.x, 4))
	_place("HUD/Remaining", Rect2(size.x - 262, 86, 112, 30), 17)
	$HUD/Remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place("HUD/Countdown", Rect2(size.x * 0.5 - 235, size.y * 0.5 - 100, 470, 160), 92)
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color(1,1,1,0.08)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = ACCENT
	$HUD/Progress.add_theme_stylebox_override("background",track)
	$HUD/Progress.add_theme_stylebox_override("fill",fill)
	if calibration_close != null:
		calibration_close.position = Vector2(size.x - 300, 20)
