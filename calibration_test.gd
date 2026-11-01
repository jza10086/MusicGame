## Standalone audio/visual calibration UI; playback stays in the shared game scene.
extends Control
const Game = preload("music_game.gd")
const Backend = Game.Backend
@export var game: Game
@onready var backend: Backend = game.backend
var _calibration_panel: MarginContainer
var _calibration_controls: Dictionary[String, SpinBox] = {}
var _calibration_listen: CheckBox
var _calibration_samples: Label
var _calibration_telemetry: Label
var _calibration_status: Label
var _calibration_apply: Button

func _ready() -> void:
	assert(game != null, "Missing rhythm game scene")
	if not backend.last_error.is_empty():
		set_process(false)
		return
	theme = game.theme.duplicate() as Theme
	theme.default_font_size = 24
	_build_calibration_panel()
	game.playback_stopped.connect(func() -> void: _calibration_status.text = "本轮已停止。点击开始 / 重来继续测试。")
	game.playback_finished.connect(func() -> void: _calibration_status.text = "本轮完成。可采用建议或调整参数后重测。")
	game.playback_failed.connect(func(message: String) -> void: _calibration_status.text = message)
	start_test()

func start_test() -> void:
	_calibration_status.text = "听到短音时按左轨 %s。" % backend.lane_key_text(0, 2) if _calibration_listen.button_pressed else "跟随音符敲击，调整画面与声音的对应位置。"
	game.start_calibration(_calibration_listen.button_pressed)

func _process(_delta: float) -> void:
	_update_calibration_panel()

func return_to_single_player() -> void:
	game.stop_playback()
	var error: Error = get_tree().change_scene_to_file(Backend.Paths.resolve("single_player_test.tscn"))
	if error != OK:
		push_error("无法打开单机测试：" + error_string(error))

func _build_calibration_panel() -> void:
	_calibration_panel = MarginContainer.new()
	_calibration_panel.name = "CalibrationPanel"
	add_child(_calibration_panel)
	_calibration_panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_calibration_panel.offset_left = -474.0
	_calibration_panel.offset_right = -24.0
	_calibration_panel.offset_top = 140.0
	_calibration_panel.offset_bottom = -24.0
	var panel: PanelContainer = PanelContainer.new()
	_calibration_panel.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	_calibration_label(box, "音画校准", 28)
	_calibration_label(box, "负值 EARLY · 正值 LATE", 18)
	_calibration_listen = CheckBox.new()
	_calibration_listen.text = "听音采样（隐藏音符）"
	_calibration_listen.focus_mode = Control.FOCUS_NONE
	_calibration_listen.toggled.connect(func(_enabled: bool) -> void: start_test())
	box.add_child(_calibration_listen)
	for item: Array in [["bpm", "测试 BPM", 60.0, 180.0, 5.0], ["visual_ms", "画面提前量 ms", -250.0, 250.0, 1.0], ["input_ms", "按压补偿 ms", -250.0, 250.0, 1.0], ["approach", "下落时间 s", 0.5, 3.0, 0.1], ["volume", "节拍音量（0–2）", 0.0, 2.0, 0.05]]:
		var key: String = item[0]
		var row: HBoxContainer = HBoxContainer.new()
		box.add_child(row)
		var caption: Label = _calibration_label(row, item[1], 20)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var spin: SpinBox = SpinBox.new()
		spin.custom_minimum_size.x = 140.0
		spin.min_value = item[2]
		spin.max_value = item[3]
		spin.step = item[4]
		spin.value = float(backend.settings[key])
		spin.value_changed.connect(func(value: float) -> void:
			backend.settings[key] = value
			if key == "volume":
				backend._apply_volume()
			_calibration_status.text = "已预览，尚未保存。BPM 下轮生效；修改补偿后请重测。"
		)
		row.add_child(spin)
		_calibration_controls[key] = spin
	var actions: HBoxContainer = HBoxContainer.new()
	box.add_child(actions)
	_calibration_button(actions, "开始 / 重来", start_test)
	_calibration_button(actions, "停止", game.pause_game)
	_calibration_samples = _calibration_label(box, "", 20)
	_calibration_apply = _calibration_button(box, "采用听音建议", _use_calibration_suggestion)
	_calibration_telemetry = _calibration_label(box, "", 18)
	_calibration_status = _calibration_label(box, "", 18)
	_calibration_button(box, "应用并保存", _save_calibration)
	_calibration_button(box, "恢复校准默认值", _reset_calibration)
	_calibration_button(box, "返回单机测试", return_to_single_player)


func _calibration_label(parent: Node, caption: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = caption
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _calibration_button(parent: Node, caption: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _update_calibration_panel() -> void:
	var count: int = backend._raw_errors.size()
	_calibration_apply.disabled = count < 16
	if count == 0:
		_calibration_samples.text = "听音采样：至少完成 16 次敲击。"
	else:
		var estimate: float = Backend.Timing.median(backend._raw_errors)
		var deviations: Array[float] = []
		for value: float in backend._raw_errors:
			deviations.append(absf(value - estimate))
		_calibration_samples.text = "%d 次采样 · 建议 %+.1f ms\n中位绝对偏差 %.1f ms" % [count, estimate, Backend.Timing.median(deviations)]
	_calibration_telemetry.text = "音频时钟 %.3f s · 输出延迟估计 %.1f ms\n画面 %+.0f ms · 按压 %+.0f ms" % [backend._last_time, backend._latency * 1000.0, backend.settings.visual_ms, backend.settings.input_ms]

func _use_calibration_suggestion() -> void:
	if backend._raw_errors.size() < 16:
		return
	_calibration_controls["input_ms"].value = clampf(Backend.Timing.median(backend._raw_errors), -250.0, 250.0)
	_calibration_status.text = "已采用建议，尚未保存。请重开一轮复测。"

func _save_calibration() -> void:
	var result: Error = backend._save_settings()
	_calibration_status.text = "校准与音效设置已保存。" if result == OK else "保存失败：" + error_string(result)

func _reset_calibration() -> void:
	for key: String in _calibration_controls:
		_calibration_controls[key].value = float(Backend.DEFAULTS[key])
	_calibration_status.text = "已恢复校准默认值，尚未保存。"

