extends Control
const Session = preload("res://core/rhythm_session.gd")
const SKIN_PATHS := ["res://skins/neon.tscn","res://skins/pixel.tscn","res://skins/aurora.tscn"]
const TITLES := ["霓虹回响", "午夜电台", "浮光之间"]
const SUBTITLES := ["LUMINOUS  /  未来舞台", "AFTER HOURS  /  像素心跳", "AETHER  /  光影诗篇"]
const ACCENTS := [Color("73f5eb"),Color("ffd18a"),Color("cdebbb")]
const SECONDARY := [Color("fa85d6"),Color("fa8e76"),Color("8ac9cd")]
var session := Session.new()
var skin:Control
var selected := 0
var difficulty := 0
var mode := "menu"
var ambient := 0.0
var effects:Array[Dictionary] = []
var judgment_age := 0.0
var key_sources := [{},{}]
var touch_lanes:Dictionary = {}
var resume_countdown := 0.0
var reduced_motion := false

func _ready() -> void:
	call_deferred("_set_clean_window_title")
	var chinese := load("res://assets/Chinese.ttc") as Font
	var display := load("res://assets/Display.ttf") as Font
	theme = Theme.new()
	theme.default_font = chinese
	theme.default_font_size = 24
	for path in ["Header/Brand","HUD/Score","HUD/Combo","Modal/Results/Grade","Modal/Results/FinalScore"]:
		get_node(path).add_theme_font_override("font",display)
	for i in range(3):
		get_node("Menu/Style"+str(i)).pressed.connect(select_style.bind(i))
	$Menu/Easy.pressed.connect(set_difficulty.bind(0))
	$Menu/Hard.pressed.connect(set_difficulty.bind(1))
	$Menu/Begin.pressed.connect(start_game)
	$Menu/Motion.pressed.connect(toggle_motion)
	$HUD/PauseButton.pressed.connect(pause_game)
	$Modal/Pause/Resume.pressed.connect(resume_game)
	$Modal/Pause/Restart.pressed.connect(start_game)
	$Modal/Pause/Back.pressed.connect(show_menu)
	$Modal/Results/Again.pressed.connect(start_game)
	$Modal/Results/Home.pressed.connect(show_menu)
	$HUD/Countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$HUD/Progress.show_percentage = false
	select_style(0)
	show_menu()
	resized.connect(_layout_screen)
	_layout_screen()

func _set_clean_window_title() -> void:
	get_window().title = "DUET / 双生节拍"
	DisplayServer.window_set_title("DUET / 双生节拍")

func select_style(index:int) -> void:
	selected = clampi(index,0,2)
	if is_instance_valid(skin):
		$Backdrop.remove_child(skin)
		skin.queue_free()
	if ResourceLoader.exists(SKIN_PATHS[selected]):
		skin = load(SKIN_PATHS[selected]).instantiate()
		$Backdrop.add_child(skin)
		_update_skin()
	_apply_theme()
	_layout_screen()

func _apply_theme() -> void:
	var accent:Color = ACCENTS[selected]
	for node in find_children("*","Button",true,false):
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.045,0.065,0.105,0.90)
		normal.border_color = Color(accent,0.32)
		normal.set_border_width_all(1)
		normal.set_corner_radius_all(12 if selected != 1 else 0)
		normal.content_margin_left = 26
		normal.content_margin_right = 26
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(accent,0.20)
		hover.border_color = accent
		var focus := normal.duplicate() as StyleBoxFlat
		focus.bg_color = Color.TRANSPARENT
		focus.border_color = Color.WHITE
		focus.set_border_width_all(3)
		node.add_theme_stylebox_override("normal",normal)
		node.add_theme_stylebox_override("hover",hover)
		node.add_theme_stylebox_override("pressed",hover)
		node.add_theme_stylebox_override("focus",focus)
		node.add_theme_color_override("font_color",Color("e9f1f5"))
		node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for i in range(3):
		var button:Button = get_node("Menu/Style"+str(i))
		button.text = "0%d     %s\n          %s" % [i+1,TITLES[i],SUBTITLES[i]]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if i == selected:
			var active:StyleBoxFlat = button.get_theme_stylebox("normal").duplicate()
			active.bg_color = Color(accent,0.17)
			active.border_color = accent
			active.border_width_left = 5
			button.add_theme_stylebox_override("normal",active)
			button.add_theme_color_override("font_color",accent)
	for path in ["Menu/Begin","Modal/Pause/Resume","Modal/Results/Again"]:
		var button:Button = get_node(path)
		var filled:StyleBoxFlat = button.get_theme_stylebox("normal").duplicate()
		filled.bg_color = accent
		button.add_theme_stylebox_override("normal",filled)
		var filled_hover := filled.duplicate() as StyleBoxFlat
		filled_hover.bg_color = accent.lightened(0.15)
		var filled_pressed := filled.duplicate() as StyleBoxFlat
		filled_pressed.bg_color = accent.darkened(0.10)
		button.add_theme_stylebox_override("hover",filled_hover)
		button.add_theme_stylebox_override("pressed",filled_pressed)
		for color_name in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			button.add_theme_color_override(color_name,Color("142330"))
	for path in ["Menu/Eyebrow","Menu/SelectHint","HUD/Score","HUD/Combo","HUD/Judgment","Modal/Results/Grade","Modal/Results/FinalScore"]:
		get_node(path).add_theme_color_override("font_color",accent)
	set_difficulty(difficulty)
	$HUD/TrackTitle.text = TITLES[selected]
	$HUD/TrackEyebrow.text = "%02d  /  %s" % [selected+1,SUBTITLES[selected].split("  /")[0]]

func toggle_motion() -> void:
	reduced_motion = not reduced_motion
	$Menu/Motion.text = "动态效果：" + ("舒缓" if reduced_motion else "完整")
	_update_skin()

func set_difficulty(value:int) -> void:
	difficulty = value
	$Menu/Easy.modulate = Color.WHITE if difficulty==0 else Color(0.6,0.65,0.7)
	$Menu/Hard.modulate = Color.WHITE if difficulty==1 else Color(0.6,0.65,0.7)

func show_menu() -> void:
	session.cancel()
	_clear_input()
	effects.clear()
	resume_countdown = 0.0
	mode = "menu"
	$Header.show()
	$Footer.show()
	$Menu.show()
	$HUD.hide()
	$Modal.hide()
	$Footer.text = "D / K  ·  F / J  ·  ← / →   双键演奏           ESC   暂停           触屏：轻点左右轨道"
	_update_skin()

func start_game() -> void:
	_clear_input()
	effects.clear()
	resume_countdown = 0.0
	session.start(difficulty)
	mode = "playing"
	$Header.hide()
	$Footer.hide()
	$Menu.hide()
	$HUD.show()
	$Modal.hide()
	$HUD/Judgment.text = "READY"
	judgment_age = 0.0
	$HUD/TrackSub.text = "双键下落   /   " + ("漫步" if difficulty==0 else "跃动")
	_update_hud()
	_update_skin()

func pause_game() -> void:
	if mode != "playing": return
	session.set_paused(true)
	_clear_input()
	resume_countdown = 0.0
	mode = "paused"
	$Modal.show()
	$Modal/Pause.show()
	$Modal/Results.hide()
	$Modal/Pause/Resume.grab_focus()

func resume_game() -> void:
	if mode != "paused": return
	mode = "playing"
	$Modal.hide()
	resume_countdown = 2.0
	_clear_input()

func finish_game() -> void:
	mode = "results"
	_clear_input()
	effects.clear()
	$HUD.hide()
	$Modal.show()
	$Modal/Pause.hide()
	$Modal/Results.show()
	$Modal/Results/Grade.text = session.grade()
	$Modal/Results/FinalScore.text = "%07d" % session.score
	$Modal/Results/FinalAccuracy.text = "%.2f%%  ACCURACY" % session.accuracy()
	$Modal/Results/Stats.text = "PERFECT   %d       GOOD   %d       MISS   %d\n最长连击  %d  /  %d" % [session.perfect,session.good,session.misses,session.max_combo,session.notes.size()]
	$Modal/Results/Again.grab_focus()

func _process(delta:float) -> void:
	ambient += delta
	if mode == "playing":
		if resume_countdown > 0.0:
			resume_countdown = maxf(0.0,resume_countdown-delta)
			if resume_countdown <= 0.0: session.set_paused(false)
		else: session.advance(delta)
		judgment_age += delta
		for fx in effects: fx.age += delta
		effects = effects.filter(func(fx:Dictionary)->bool:return float(fx.age)<0.65)
		for event in session.events:
			effects.append({"lane":event.lane,"quality":event.quality,"age":0.0})
			$HUD/Judgment.text = event.quality
			judgment_age = 0.0
		session.events.clear()
		_update_hud()
		if session.finished: finish_game()
	_update_skin()

func _update_hud() -> void:
	$HUD/Score.text = "%07d" % session.score
	$HUD/Combo.text = str(session.combo)
	$HUD/Accuracy.text = "%.2f%%  ACCURACY" % session.accuracy()
	$HUD/Best.text = "BEST CHAIN   %03d" % session.max_combo
	$HUD/Progress.value = clampf(session.time/session.DURATION*100.0,0,100)
	$HUD/Remaining.text = "00:%02d" % ceili(maxf(0,session.DURATION-maxf(0.0,session.time)))
	$HUD/Judgment.modulate.a = clampf(1.4-judgment_age,0.25,1.0)
	if resume_countdown>0: $HUD/Countdown.text = str(ceili(resume_countdown))
	elif session.time<0: $HUD/Countdown.text = str(ceili(-session.time))
	elif session.time<0.6: $HUD/Countdown.text = "GO"
	else: $HUD/Countdown.text = ""

func _update_skin() -> void:
	if is_instance_valid(skin) and skin.has_method("set_state"):
		skin.set_state({"mode":mode,"time":0.0 if reduced_motion else ambient,"song_time":session.time,"notes":session.notes,"effects":[] if reduced_motion else effects,"pressed":session.held,"combo":session.combo})

func _clear_input() -> void:
	key_sources = [{},{}]
	touch_lanes.clear()
	session.release(0)
	session.release(1)

func _input(event:InputEvent) -> void:
	if event is InputEventKey:
		if event.echo: return
		if event.pressed and event.physical_keycode == KEY_ESCAPE:
			if mode=="playing": pause_game()
			elif mode=="paused": resume_game()
			get_viewport().set_input_as_handled()
			return
		var lane := -1
		if event.physical_keycode in [KEY_D, KEY_F, KEY_LEFT]: lane = 0
		elif event.physical_keycode in [KEY_K, KEY_J, KEY_RIGHT]: lane = 1
		if lane>=0:
			_input_lane(lane,"key"+str(event.physical_keycode),event.pressed)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		var hit_lane: int = skin.lane_at_position(event.position) if is_instance_valid(skin) else -1
		if event.pressed and mode=="playing" and hit_lane >= 0:
			var lane: int = hit_lane
			touch_lanes[event.index] = lane
			_input_lane(lane,"touch"+str(event.index),true)
		elif not event.pressed and touch_lanes.has(event.index):
			_input_lane(int(touch_lanes[event.index]),"touch"+str(event.index),false)
			touch_lanes.erase(event.index)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		var hit_lane: int = skin.lane_at_position(event.position, true) if is_instance_valid(skin) else -1
		if event.pressed and mode=="playing" and hit_lane >= 0:
			var lane: int = hit_lane
			touch_lanes[-1] = lane
			_input_lane(lane,"mouse",true)
		elif not event.pressed and touch_lanes.has(-1):
			_input_lane(int(touch_lanes[-1]),"mouse",false)
			touch_lanes.erase(-1)

func _input_lane(lane:int,source:String,down:bool) -> void:
	if mode != "playing" or resume_countdown>0: return
	if down:
		if key_sources[lane].has(source): return
		var was_empty:bool = key_sources[lane].is_empty()
		key_sources[lane][source] = true
		if was_empty: session.press(lane)
	else:
		key_sources[lane].erase(source)
		if key_sources[lane].is_empty(): session.release(lane)

func _notification(what:int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and is_node_ready() and mode=="playing": pause_game()

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
	var center_offset := (size - Vector2(1920,1080)) * 0.5
	for node in [$Header, $Menu, $Modal/Pause, $Modal/Results]:
		node.position = center_offset
	$Footer.position = Vector2(72, size.y - 73)
	# Only live game information belongs on stage. Descriptions stay in selection.
	for path in ["HUD/TrackEyebrow", "HUD/TrackSub", "HUD/ScoreLabel", "HUD/Best", "HUD/Accuracy", "Header/Edition", "Header/Rule"]:
		get_node(path).hide()
	_place("HUD/TrackTitle", Rect2(48, 32, 380, 56), 32)
	_place("HUD/Score", Rect2(size.x - 418, 28, 270, 58), 42)
	$HUD/Score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place("HUD/PauseButton", Rect2(size.x - 108, 30, 62, 62), 25)
	$HUD/PauseButton.text = "Ⅱ"
	for style_name in ["normal", "hover", "pressed", "focus"]:
		var box := $HUD/PauseButton.get_theme_stylebox(style_name).duplicate() as StyleBoxFlat
		box.content_margin_left = 0
		box.content_margin_right = 0
		$HUD/PauseButton.add_theme_stylebox_override(style_name, box)
	$HUD/PauseButton.tooltip_text = ""
	$HUD/PauseButton.add_theme_constant_override("outline_size", 0)
	_place("HUD/Combo", Rect2(size.x * 0.5 - 135, 19, 130, 62), 48)
	$HUD/Combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place("HUD/ComboLabel", Rect2(size.x * 0.5 + 10, 31, 120, 24), 16)
	$HUD/ComboLabel.text = "COMBO"
	_place("HUD/Judgment", Rect2(size.x * 0.5 + 10, 55, 190, 32), 22)
	_place("HUD/Progress", Rect2(0, 0, size.x, 4))
	_place("HUD/Remaining", Rect2(size.x - 262, 86, 112, 30), 17)
	$HUD/Remaining.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place("HUD/Countdown", Rect2(size.x * 0.5 - 235, size.y * 0.5 - 100, 470, 160), 92)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(1,1,1,0.08)
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENTS[selected]
	$HUD/Progress.add_theme_stylebox_override("background",track)
	$HUD/Progress.add_theme_stylebox_override("fill",fill)
