## Standalone single-player test menu. The child game owns playback and judgment.
extends Control
const Game = preload("music_game.gd")
const Backend = Game.Backend
const KeySettings = preload("ui/rhythm_key_settings.gd")
@export var game: Game
@onready var backend: Backend = game.backend
var difficulty: int = 0
var track_choice: OptionButton
var skip_intro: CheckBox
var auto_choice: CheckBox
var _key_settings: KeySettings
var _sound_dialog: ConfirmationDialog
var _sound_sliders: Dictionary[String, HSlider] = {}
var _sound_snapshot: Dictionary = {}
var _sound_choices: Dictionary[String, OptionButton] = {}
var _sound_status: Label
var _preview_bgm: AudioStreamPlayer

func _ready() -> void:
	assert(game != null, "Missing rhythm game scene")
	if not backend.last_error.is_empty():
		set_process(false)
		return
	theme = game.theme.duplicate() as Theme
	theme.default_font_size = 24
	$Menu/Begin.pressed.connect(start_game)
	game.return_requested.connect(show_menu)
	game.playback_failed.connect(func(message: String) -> void:
		show_menu()
		$Menu/Duration.text = message)
	track_choice = OptionButton.new()
	track_choice.get_popup().max_size = Vector2i(1920, 280)
	track_choice.position = Vector2(802, 767)
	track_choice.size = Vector2(568, 60)
	track_choice.item_selected.connect(set_difficulty)
	$Menu.add_child(track_choice)
	var refresh: Button = Button.new()
	refresh.text = "刷新"
	refresh.tooltip_text = "重新读取谱面库，保留当前选择"
	refresh.position = Vector2(1376, 767)
	refresh.size = Vector2(72, 60)
	refresh.pressed.connect(refresh_chart_library)
	$Menu.add_child(refresh)
	var options: VBoxContainer = VBoxContainer.new()
	options.position = Vector2(1450, 580)
	options.custom_minimum_size = Vector2(370, 0)
	options.add_theme_constant_override("separation", 12)
	$Menu.add_child(options)
	skip_intro = CheckBox.new()
	skip_intro.text = "从首音前 3 秒开始"
	options.add_child(skip_intro)
	auto_choice = CheckBox.new()
	auto_choice.text = "AUTO 自动演奏（测试）"
	auto_choice.tooltip_text = "本局自动敲击和长按，使用当前音效与输入补偿；不会写入设置。"
	auto_choice.set_pressed_no_signal(game.auto_play)
	auto_choice.toggled.connect(game.set_auto_play)
	options.add_child(auto_choice)
	$Menu/Duration.position = Vector2(1450, 900)
	$Menu/Duration.size = Vector2(370, 80)
	var calibrate: Button = Button.new()
	calibrate.text = "音画校准"
	calibrate.pressed.connect(open_calibration)
	options.add_child(calibrate)
	var sound_button: Button = Button.new()
	sound_button.text = "音效与按键"
	sound_button.pressed.connect(show_sound_settings)
	options.add_child(sound_button)
	_build_sound_settings()
	$Menu/Begin.theme_type_variation = &"RhythmPrimary"
	$Menu/Eyebrow.add_theme_color_override("font_color", Game.ACCENT)
	$Menu/SelectHint.add_theme_color_override("font_color", Game.ACCENT)
	$Header/Edition.hide()
	$Header/Rule.hide()
	resized.connect(_layout_screen)
	_layout_screen()
	show_menu()

func _layout_screen() -> void:
	var center_offset: Vector2 = (size - Vector2(1920, 1080)) * 0.5
	for node: Control in [$Header, $Menu]:
		node.position = center_offset
	$Footer.position = Vector2(72, size.y - 73)

func show_menu() -> void:
	game.stop_playback()
	$Header.show()
	$Menu.show()
	$Footer.show()
	refresh_chart_library()

func start_game() -> void:
	game.chart_path = str(track_choice.get_item_metadata(difficulty))
	game.skip_intro = skip_intro.button_pressed
	$Header.hide()
	$Menu.hide()
	$Footer.hide()
	game.start_game()

func open_calibration() -> void:
	game.stop_playback()
	var error: Error = get_tree().change_scene_to_file(Backend.Paths.resolve("calibration_test.tscn"))
	if error != OK:
		push_error("无法打开音画校准：" + error_string(error))

func refresh_chart_library() -> void:
	var chosen: String = str(track_choice.get_item_metadata(difficulty)) if track_choice.item_count > difficulty else Backend.Paths.resolve(Backend.DEFAULT_CHART)
	backend.refresh_chart_library()
	track_choice.clear()
	# Keep the familiar three originals at the front when present; all files are discovered.
	for path: String in backend.chart_paths.slice(0, mini(3, backend.chart_paths.size())):
		_add_chart_choice(path)
	track_choice.add_item("双轨合成测试（含长按）")
	track_choice.set_item_metadata(track_choice.item_count - 1, "")
	for path: String in backend.chart_paths.slice(mini(3, backend.chart_paths.size())):
		_add_chart_choice(path)
	var selection: int = 0
	for index: int in range(track_choice.item_count):
		if str(track_choice.get_item_metadata(index)) == chosen:
			selection = index
	set_difficulty(selection)

func _add_chart_choice(path: String) -> void:
	var index: int = backend.chart_paths.find(path)
	track_choice.add_item(backend.chart_names[index])
	track_choice.set_item_metadata(track_choice.item_count - 1, path)

func _selected_backend_track() -> int:
	var path: String = str(track_choice.get_item_metadata(difficulty))
	return 0 if path.is_empty() else backend.chart_paths.find(path) + 1

func set_difficulty(value: int) -> void:
	difficulty = clampi(value, 0, track_choice.item_count - 1)
	backend._select_track(_selected_backend_track())
	track_choice.select(difficulty)
	$Header/Tag.text = "单机测试 / %d KEY RHYTHM" % backend.key_count
	$Menu/Eyebrow.text = "%d KEYS. ONE MOMENT." % backend.key_count
	$Menu/Subtitle.text = "%d 条轨道，一次心跳。\n跟随节拍，进入霓虹舞台。" % backend.key_count
	game.configure_lane_feedback()
	_update_binding_text()
	var path: String = str(track_choice.get_item_metadata(difficulty))
	if path.is_empty():
		$Menu/Duration.text = "双轨练习 · 含长按\n计分 ×1.00"
	else:
		var chart: Dictionary = Backend.Chart.read_chart(path)
		$Menu/Duration.text = "%d 起点 · %s\n计分 ×%.2f" % [chart.notes.size(), chart.data.difficulty, Backend.Scoring.difficulty_multiplier(str(chart.data.difficulty))] if chart.ok else chart.error

func _update_binding_text() -> void:
	var labels: PackedStringArray = []
	for lane: int in range(backend.key_count):
		labels.append(backend.lane_key_text(lane, backend.key_count))
	var binding: String = "左轨 %s · 右轨 %s" % [labels[0], labels[1]] if backend.key_count == 2 else "四轨 " + " · ".join(labels)
	$Footer.text = binding + " · ESC 停止本轮"
	$Menu/Instruction.text = binding + "\n短音符轻按；长条音符按住至尾部。"

func _build_sound_settings() -> void:
	_preview_bgm = AudioStreamPlayer.new()
	_preview_bgm.name = "BgmPreview"
	_preview_bgm.stream = preload("charts/hold_test/hold_test.wav")
	add_child(_preview_bgm)
	_sound_dialog = ConfirmationDialog.new()
	_sound_dialog.transparent_bg = true
	_sound_dialog.title = "音效与演奏按键"
	_sound_dialog.min_size = Vector2i(850, 680)
	_sound_dialog.ok_button_text = "应用并保存"
	_sound_dialog.cancel_button_text = "取消"
	_sound_dialog.dialog_hide_on_ok = false
	_sound_dialog.confirmed.connect(_save_sound_settings)
	_sound_dialog.canceled.connect(_cancel_sound_settings)
	add_child(_sound_dialog)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(810, 540)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sound_dialog.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 18)
	scroll.add_child(box)
	_key_settings = KeySettings.new()
	_key_settings.backend = backend
	box.add_child(_key_settings)
	var captions: Dictionary = {"volume": "BGM / 校准（基准 ×0.4）", "success_volume": "成功敲击", "empty_volume": "空敲击", "hold_start_volume": "长按开始", "hold_sub_volume": "长按 Sub", "hold_end_volume": "长按结束"}
	for key: String in captions:
		var row: HBoxContainer = HBoxContainer.new()
		box.add_child(row)
		var label: Label = Label.new()
		label.text = str(captions[key])
		label.custom_minimum_size.x = 230
		row.add_child(label)
		var slider: HSlider = HSlider.new()
		slider.min_value = 0
		slider.max_value = 200
		slider.step = 1
		slider.custom_minimum_size.x = 260
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		var amount: Label = Label.new()
		amount.custom_minimum_size.x = 70
		row.add_child(amount)
		slider.value_changed.connect(func(value: float) -> void:
			backend.settings[key] = value / 100.0
			amount.text = "%d%%" % roundi(value)
			if key == "volume":
				_preview_bgm.volume_linear = value / 100.0 * Backend.BGM_GAIN
				backend._apply_volume()
		)
		_sound_sliders[key] = slider
		if key != "volume":
			var preview: Button = Button.new()
			preview.text = "试听"
			preview.pressed.connect(func() -> void:
				game._play_sound(game._tap_preview, key.trim_suffix("_volume"))
			)
			row.add_child(preview)
			var sound_key: String = key.trim_suffix("_volume") + "_sound"
			var choice: OptionButton = OptionButton.new()
			choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# PopupMenu provides its own scrollbar when the list exceeds this height.
			choice.get_popup().max_size = Vector2i(1920, 320)
			for id: String in Backend.Synth.TAP_NAMES:
				choice.add_item(Backend.Synth.TAP_NAMES[id])
				choice.set_item_metadata(choice.item_count - 1, id)
			choice.item_selected.connect(func(index: int) -> void:
				backend.settings[sound_key] = str(choice.get_item_metadata(index))
				game._tap_preview.stop()
			)
			box.add_child(choice)
			_sound_choices[sound_key] = choice
		else:
			var preview: Button = Button.new()
			preview.text = "试听 / 停止"
			preview.pressed.connect(func() -> void:
				if _preview_bgm.playing:
					_preview_bgm.stop()
				else:
					_preview_bgm.play(14.0)
			)
			row.add_child(preview)
	var chart_sounds_choice: CheckBox = CheckBox.new()
	chart_sounds_choice.name = "ChartSoundsChoice"
	chart_sounds_choice.text = "使用谱面指定音效（未指定时使用以上设置）"
	chart_sounds_choice.button_pressed = bool(backend.settings.use_chart_sounds)
	chart_sounds_choice.toggled.connect(func(enabled: bool) -> void: backend.settings.use_chart_sounds = enabled)
	box.add_child(chart_sounds_choice)
	_sound_status = Label.new()
	_sound_status.text = "0% 为静音；调节即时预览，应用后保存。"
	box.add_child(_sound_status)

func show_sound_settings() -> void:
	_sound_snapshot = backend.settings.duplicate(true)
	_key_settings.refresh()
	(find_child("ChartSoundsChoice", true, false) as CheckBox).set_pressed_no_signal(bool(backend.settings.use_chart_sounds))
	for key: String in _sound_choices:
		var choice: OptionButton = _sound_choices[key]
		for index: int in range(choice.item_count):
			if str(choice.get_item_metadata(index)) == str(backend.settings[key]):
				choice.select(index)
				break
	for key: String in _sound_sliders:
		_sound_sliders[key].value = float(backend.settings[key]) * 100.0
		_sound_sliders[key].value_changed.emit(_sound_sliders[key].value)
	_sound_status.text = "0% 为静音；调节即时预览，应用后保存。"
	_sound_dialog.popup_centered()

func _cancel_sound_settings() -> void:
	backend.settings = _sound_snapshot.duplicate(true)
	_update_binding_text()
	_preview_bgm.stop()
	game._tap_preview.stop()
	backend._apply_volume()
	for player: AudioStreamPlayer in game._tap_players:
		player.stop()

func _save_sound_settings() -> void:
	_update_binding_text()
	var result: Error = backend._save_settings()
	if result == OK:
		game._tap_preview.stop()
		_preview_bgm.stop()
		_sound_dialog.hide()
	else:
		_sound_status.text = "保存失败：" + error_string(result)




