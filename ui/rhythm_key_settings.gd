## Shared play-key controls for the game and native editor settings.
## The containing dialog owns Apply/Cancel and persistence.
extends VBoxContainer
const Backend = preload("../rhythm_backend.gd")
var backend: Backend
var _buttons: Dictionary[String, Array] = {}
var _capture: AcceptDialog
var _mode: String = ""
var _slot: int = -1

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	for mode: String in ["keys_2k", "keys_4k"]:
		var title: Label = Label.new()
		title.text = "2K 演奏按键（每轨两个）" if mode == "keys_2k" else "4K 演奏按键（从左到右）"
		add_child(title)
		var row: HBoxContainer = HBoxContainer.new()
		add_child(row)
		_buttons[mode] = []
		for slot: int in range(4):
			var button: Button = Button.new()
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(func() -> void: begin_capture(mode, slot))
			row.add_child(button)
			_buttons[mode].append(button)
	var reset: Button = Button.new()
	reset.text = "恢复默认演奏按键"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func() -> void:
		for mode: String in _buttons:
			backend.settings[mode] = Backend.DEFAULTS[mode].duplicate()
		refresh()
	)
	add_child(reset)
	_capture = AcceptDialog.new()
	_capture.title = "修改演奏按键"
	_capture.ok_button_text = "取消"
	_capture.min_size = Vector2i(460, 150)
	add_child(_capture)
	_capture.window_input.connect(_capture_input)
	refresh()

func refresh() -> void:
	for mode: String in _buttons:
		for slot: int in range(4):
			var lane: String = ("左轨" if slot < 2 else "右轨") if mode == "keys_2k" else "轨道 %d" % (slot + 1)
			_buttons[mode][slot].text = "%s · %s" % [lane, OS.get_keycode_string(int(backend.settings[mode][slot]))]

func begin_capture(mode: String, slot: int) -> void:
	_mode = mode
	_slot = slot
	_capture.dialog_text = "请按新的演奏按键，Esc 取消。"
	_capture.popup_centered()

func _capture_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var key: InputEventKey = event
	if key.physical_keycode == KEY_ESCAPE:
		_capture.hide()
	elif key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed or not Backend.valid_play_key(key.physical_keycode):
		_capture.dialog_text = "请选择单个按键；Esc 和修饰键不能用作演奏按键。"
	else:
		var keys: Array = backend.settings[_mode]
		var other: int = keys.find(int(key.physical_keycode))
		if other >= 0 and other != _slot:
			_capture.dialog_text = "该按键已在此模式中使用，请选择其他按键。"
		else:
			keys[_slot] = int(key.physical_keycode)
			refresh()
			_capture.hide()
	_capture.get_viewport().set_input_as_handled()
