## Standalone calibration backend and F6 lab: local audio/visual/input calibration, no PartyAPI.
## The audio playback position is the sole timeline; input samples it on key events.
extends Control

const Timing = preload("res://rhythm_timing.gd")
const Synth = preload("res://rhythm_audio.gd")
const Lane = preload("res://rhythm_lane.gd")
const Chart = preload("res://rhythm_chart.gd")
const BAD_APPLE: String = "res://charts/bad_apple/chart.json"
const SETTINGS_PATH: String = "user://party/prototypes/rhythm_1k.cfg"
const CHART_PATHS: Array[String] = [BAD_APPLE,
	"res://charts/bad_apple/normal.json",
	"res://charts/bad_apple/hard.json"]
const CHART_NAMES: Array[String] = ["Easy", "Normal", "Hard"]
const DEFAULTS: Dictionary = {"visual_ms": 0.0, "input_ms": 0.0, "approach": 1.6, "bpm": 120.0, "volume": 0.65}
## seconds_until captures the consumed note against the visual clock at the input edge.
signal note_judged(lane: int, grade: String, error_ms: float, seconds_until: float)

enum State { IDLE, PLAYING, FINISHED }

var state: State = State.IDLE
var settings: Dictionary = DEFAULTS.duplicate()
var _audio: AudioStreamPlayer
var _lane: Lane
var _notes: Array[float] = []
var _judged: Array[bool] = []
var _raw_errors: Array[float] = []
var _counts: Dictionary = {"PERFECT": 0, "GOOD": 0, "OK": 0, "MISS": 0}
var _combo: int = 0
var _best_combo: int = 0
var _latency: float = 0.0
var _last_time: float = 0.0
var _held: bool = false
var _held_right: bool = false
var _note_lanes: Array[int] = []
var _calibration_checkbox: CheckBox
var _key_sources: Array[Dictionary] = [{}, {}]
var _calibration: bool = false
var _status: Label
var _stats: Label
var _telemetry: Label
var _suggestion: Label
var _progress: ProgressBar
var _bpm: SpinBox
var _controls: Dictionary[String, SpinBox] = {}
var _hint: Label
var _track_selector: OptionButton
var _track_info: Label
var _selected_track: int = 1
var _duration: float = 1.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_settings()
	_build_ui()
	_audio = AudioStreamPlayer.new()
	_audio.name = "TestTrack"
	add_child(_audio)
	_audio.finished.connect(_on_audio_finished)
	_apply_volume()
	_select_track(_selected_track)

func _build_ui() -> void:
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color("#080f1e")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var page: VBoxContainer = VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)
	var title: Label = _label(page, "2K  /  节奏同步实验室", 32)
	title.add_theme_color_override("font_color", Color("#65e2df"))
	_label(page, "GodotParty 原版小游戏 · 独立原型    /    先对齐声音、画面与按键，再扩展谱面", 18)
	var body: HBoxContainer = HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	_lane = Lane.new()
	_lane.name = "Lane"
	_lane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lane.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lane.custom_minimum_size = Vector2(620, 540)
	body.add_child(_lane)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size.x = 540
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var panel: VBoxContainer = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 12)
	scroll.add_child(panel)
	_label(panel, "歌曲与校准", 25)
	_track_selector = OptionButton.new()
	_track_selector.add_item("合成测试节拍")
	for difficulty: String in CHART_NAMES:
		_track_selector.add_item("Bad Apple!! / " + difficulty + " · 双轨")
	_track_selector.select(_selected_track)
	_track_selector.focus_mode = Control.FOCUS_NONE
	_track_selector.item_selected.connect(_select_track)
	panel.add_child(_track_selector)
	_track_info = _label(panel, "", 17)
	_track_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint = _label(panel, "听到短音时，按下空格。前 4 拍为预备拍。", 18)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var actions: HBoxContainer = HBoxContainer.new()
	panel.add_child(actions)
	_button(actions, "开始 / 重来", _start)
	_button(actions, "停止", _stop)
	_button(panel, "从首音前 3 秒测试", _start.bind(true))
	_label(panel, "左轨 A / ←    右轨 D / →", 18)
	var check: CheckBox = CheckBox.new()
	_calibration_checkbox = check
	check.text = "听音校准：隐藏音符，每拍敲一次"
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(_set_calibration)
	panel.add_child(check)
	_bpm = _setting(panel, "bpm", "合成测试 BPM（歌曲保持原速）", 60.0, 180.0, 5.0)
	_setting(panel, "visual_ms", "画面提前量 ms：正值让音符更早到线", -250.0, 250.0, 1.0)
	_setting(panel, "input_ms", "按压延迟补偿 ms：正值补偿偏晚敲击", -250.0, 250.0, 1.0)
	_setting(panel, "approach", "下落时间 s：越大越慢，不影响判定", 0.5, 3.0, 0.1)
	_setting(panel, "volume", "测试音量（不修改系统 Master）", 0.0, 1.0, 0.05)
	_suggestion = _label(panel, "校准建议：至少完成 16 次有效敲击", 18)
	_suggestion.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(panel, "采用听音校准建议（尚不保存）", _use_suggestion)
	var persistence: HBoxContainer = HBoxContainer.new()
	panel.add_child(persistence)
	_button(persistence, "应用并保存", _save_settings)
	_button(persistence, "恢复默认（尚不保存）", _reset_settings)
	_stats = _label(panel, "", 20)
	_telemetry = _label(panel, "", 16)
	_telemetry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var help: Label = _label(panel, "调节顺序：\n1. 听音校准，保持自然节拍；建议值含设备与个人反应偏差。\n2. 关闭听音校准，调画面提前量，让到线与听到短音一致。\n3. 调下落速度，再开始一轮验证。\n\n显示误差：负值 EARLY / 正值 LATE\nPERFECT ±40 · GOOD ±90 · OK ±150 ms\n切换窗口会停止本轮，返回后重新开始。", 17)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 8
	page.add_child(_progress)
	_status = _label(page, "就绪 · 所有调整仅在本机生效，点击“应用并保存”才写入磁盘", 18)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_update_binding()
	_bpm.editable = false

func _select_track(index: int) -> void:
	_stop()
	_selected_track = clampi(index, 0, CHART_PATHS.size())
	_track_selector.select(_selected_track)
	_update_binding()
	_bpm.editable = _calibration or _selected_track == 0
	_notes.clear()
	_note_lanes.clear()
	_judged.clear()
	_lane.notes = _notes
	_lane.judged = _judged
	_lane.errors.clear()
	_combo = 0
	_best_combo = 0
	_lane.combo = 0
	_counts = {"PERFECT": 0, "GOOD": 0, "OK": 0, "MISS": 0}
	_refresh_stats()
	if _selected_track == 0:
		_track_info.text = "原创合成节拍 · 4 拍预备 · 64 拍练习"
	else:
		var chart: Dictionary = Chart.read_chart(CHART_PATHS[_selected_track - 1])
		if not chart.ok:
			_track_info.text = chart.error
			return
		_track_info.text = "%s · %s\n%s / 原谱 Gpop %s · %d 单击 · 首音 %.3f s" % [chart.data.title, chart.data.artist, CHART_NAMES[_selected_track - 1], chart.data.source.difficulty, chart.notes.size(), chart.notes[0]]

func _label(parent: Node, value: String, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("#dce6f8"))
	parent.add_child(label)
	return label

func _button(parent: Node, caption: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 42
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _setting(parent: Node, key: String, caption: String, low: float, high: float, step: float) -> SpinBox:
	_label(parent, caption, 17)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = float(settings[key])
	spin.custom_minimum_size.y = 38
	spin.value_changed.connect(func(value: float) -> void:
		settings[key] = value
		if key == "volume" and _audio != null:
			_apply_volume()
		if _status != null:
			_status.text = "调整已预览，尚未保存；修改补偿后建议重开一轮比较。"
	)
	parent.add_child(spin)
	_controls[key] = spin
	return spin

## Rebuild audio and notes from the exact same times, then reset all timing state.
func _start(skip_intro: bool = false) -> void:
	_stop()
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus != null:
		focus.release_focus()
	var stream: AudioStream
	_note_lanes.clear()
	if _selected_track > 0 and not _calibration:
		var chart: Dictionary = Chart.read_chart(CHART_PATHS[_selected_track - 1])
		if not chart.ok:
			_status.text = chart.error
			return
		_notes = chart.notes
		_note_lanes = chart.lanes
		stream = chart.audio
	else:
		_notes = Timing.note_times(float(settings.bpm), _calibration)
		stream = Synth.build(_notes, float(settings.bpm))
		for index: int in range(_notes.size()):
			_note_lanes.append(index % 2 if not _calibration else 0)
	_lane.note_lanes = _note_lanes
	_duration = stream.get_length()
	_judged.clear()
	_judged.resize(_notes.size())
	_judged.fill(false)
	_raw_errors.clear()
	_counts = {"PERFECT": 0, "GOOD": 0, "OK": 0, "MISS": 0}
	_combo = 0
	_best_combo = 0
	_lane.notes = _notes
	_lane.judged = _judged
	_lane.errors.clear()
	_lane.combo = 0
	_lane.judgement = "LISTEN" if _calibration else "READY"
	_lane.hide_notes = _calibration
	_lane.running = true
	_audio.stream = stream
	_latency = AudioServer.get_output_latency()
	_last_time = maxf(0.0, _notes[0] - 3.0) if skip_intro else 0.0
	_audio.play(_last_time)
	state = State.PLAYING
	_status.text = "听音校准中 · 每个短音敲一次" if _calibration else "练习中 · 音符中心到达青色判定线时敲击"
	_suggestion.text = "校准建议：至少完成 16 次有效敲击"
	_update_binding()
	_refresh_stats()

func _stop() -> void:
	if _audio != null:
		_audio.stop()
	state = State.IDLE
	_held = false
	_held_right = false
	_key_sources = [{}, {}]
	if _lane != null:
		_lane.running = false
		_lane.pressed = false
		_lane.pressed_right = false
		_lane.judgement = "READY"
	if _status != null:
		_status.text = "已停止 · 点击开始 / 重来"

## Sample on both draw frames and key events. Clamp backward audio-thread jitter.
## Output latency is cached once per playback; manual offsets are independent.
func _clock() -> float:
	if state != State.PLAYING:
		return _last_time
	var raw: float = _audio.get_playback_position() + AudioServer.get_time_since_last_mix() - _latency
	_last_time = maxf(_last_time, raw)
	return _last_time

func _process(_delta: float) -> void:
	if _lane == null:
		return
	var time: float = _clock()
	_lane.song_time = time
	_lane.visual_time = Timing.visual_time(time, float(settings.visual_ms))
	_lane.approach = float(settings.approach)
	_lane.pressed = _held
	_lane.pressed_right = _held_right
	if state != State.PLAYING:
		return
	var judged_time: float = time if _calibration else time - float(settings.input_ms) / 1000.0
	var window: float = 0.24 if _calibration else Timing.HIT_MS / 1000.0
	for index: int in range(_notes.size()):
		if not _judged[index] and judged_time > _notes[index] + window:
			_judged[index] = true
			_record("MISS", 0.0, _note_lanes[index])
	_progress.value = time / _duration * 100.0
	_telemetry.text = "音频时钟 %.3f s  /  设备延迟估计 %.1f ms\n画面 %+.0f ms  ·  输入 %+.0f ms" % [time, _latency * 1000.0, settings.visual_ms, settings.input_ms]
	if time >= _duration:
		_finish()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key: InputEventKey = event as InputEventKey
	var lane: int = 0 if key.physical_keycode in [KEY_A, KEY_LEFT] else (1 if key.physical_keycode in [KEY_D, KEY_RIGHT] else -1)
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
	press_lane(lane, not _key_sources[lane].is_empty())
	if state == State.PLAYING:
		get_viewport().set_input_as_handled()

## All input sources judge against the original audio clock, once per press edge.
func press_lane(lane: int, down: bool) -> void:
	if lane < 0 or lane > 1:
		return
	var was_held: bool = _held if lane == 0 else _held_right
	if lane == 0:
		_held = down and state == State.PLAYING
	else:
		_held_right = down and state == State.PLAYING
	if down and not was_held and state == State.PLAYING:
		_hit(_clock(), lane)

## Consume at most one nearest unjudged note. Stray keys never consume future notes.
func _hit(time: float, lane: int = 0) -> void:
	var target: int = -1
	var distance: float = INF
	var compensated: float = time if _calibration else time - float(settings.input_ms) / 1000.0
	for index: int in range(_notes.size()):
		if _judged[index] or _note_lanes[index] != lane:
			continue
		var candidate: float = absf(compensated - _notes[index])
		if candidate < distance:
			distance = candidate
			target = index
	var window: float = 0.24 if _calibration else Timing.HIT_MS / 1000.0
	if target < 0 or distance > window:
		_lane.judgement = "EMPTY"
		_lane.flash = 1.0
		return
	_judged[target] = true
	var raw: float = (time - _notes[target]) * 1000.0
	var error: float = Timing.error_ms(time, _notes[target], float(settings.input_ms))
	if _calibration:
		_raw_errors.append(raw)
		if _raw_errors.size() > 32:
			_raw_errors.pop_front()
		var estimate: float = Timing.median(_raw_errors)
		var deviations: Array[float] = []
		for value: float in _raw_errors:
			deviations.append(absf(value - estimate))
		_suggestion.text = "%d 次采样 · 建议补偿 %+.1f ms\n中位绝对偏差 %.1f ms（越小越稳定）" % [_raw_errors.size(), estimate, Timing.median(deviations)]
	_record(Timing.grade(error), error, lane, _notes[target] - Timing.visual_time(time, float(settings.visual_ms)))

func _record(grade: String, error: float, lane: int = 0, seconds_until: float = INF) -> void:
	note_judged.emit(lane, grade, error, seconds_until)
	_counts[grade] += 1
	_combo = 0 if grade == "MISS" else _combo + 1
	_best_combo = maxi(_best_combo, _combo)
	_lane.combo = _combo
	_lane.judgement = grade
	_lane.last_error = error
	_lane.flash = 1.0
	if grade != "MISS":
		_lane.errors.append(error)
		if _lane.errors.size() > 32:
			_lane.errors.pop_front()
	_refresh_stats()

func _refresh_stats() -> void:
	_stats.text = "PERFECT %d    GOOD %d\nOK %d    MISS %d    MAX COMBO %d" % [_counts.PERFECT, _counts.GOOD, _counts.OK, _counts.MISS, _best_combo]

func _finish() -> void:
	_audio.stop()
	for index: int in range(_notes.size()):
		if not _judged[index]:
			_judged[index] = true
			_record("MISS", 0.0, _note_lanes[index])
	_last_time = _duration
	state = State.FINISHED
	_lane.running = false
	_held = false
	_held_right = false
	_key_sources = [{}, {}]
	_lane.pressed = false
	_status.text = "本轮完成 · 查看误差分布，调整后点击开始 / 重来"
	_progress.value = 100.0

func _on_audio_finished() -> void:
	if state == State.PLAYING:
		_finish()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == State.PLAYING:
		_stop()
		_status.text = "窗口失去焦点，本轮已停止；回来后重新开始，避免时钟跳跃。"

func _set_calibration(value: bool) -> void:
	_stop()
	_calibration = value
	_calibration_checkbox.set_pressed_no_signal(value)
	_bpm.editable = value or _selected_track == 0
	_update_binding()
	_lane.hide_notes = value
	_raw_errors.clear()
	_suggestion.text = "校准建议：至少完成 16 次有效敲击"

func _update_binding() -> void:
	_lane.binding = "A / ←"
	_lane.right_binding = "D / →"
	_hint.text = "听到短音时按左键 A / ←。前 4 拍预备；长按不连击。" if _calibration else "左轨 A / ←，右轨 D / →。左右同时音符需双押，长按不连击。"

func _use_suggestion() -> void:
	if _raw_errors.size() < 16:
		_status.text = "请先开启听音校准，完成至少 16 次有效敲击。"
		return
	_controls["input_ms"].value = clampf(Timing.median(_raw_errors), -250.0, 250.0)
	_status.text = "已采用建议；重开一轮复测，满意后点击应用并保存。"

func _apply_volume() -> void:
	_audio.volume_db = linear_to_db(maxf(0.0001, float(settings.volume)))

func _reset_settings() -> void:
	for key: String in _controls:
		_controls[key].value = float(DEFAULTS[key])
	_update_binding()
	_status.text = "已恢复默认预览，尚未保存"

func _load_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for key: String in ["visual_ms", "input_ms", "approach", "bpm", "volume"]:
		var value: Variant = config.get_value("local", key, DEFAULTS[key])
		if (value is float or value is int) and is_finite(float(value)):
			settings[key] = float(value)
	settings.visual_ms = clampf(settings.visual_ms, -250.0, 250.0)
	settings.input_ms = clampf(settings.input_ms, -250.0, 250.0)
	settings.approach = clampf(settings.approach, 0.5, 3.0)
	settings.bpm = clampf(settings.bpm, 60.0, 180.0)
	settings.volume = clampf(settings.volume, 0.0, 1.0)

func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	for key: String in settings:
		config.set_value("local", key, settings[key])
	var result: Error = DirAccess.make_dir_recursive_absolute(SETTINGS_PATH.get_base_dir())
	if result == OK:
		result = config.save(SETTINGS_PATH)
	_status.text = "已应用并保存本机校准参数" if result == OK else "保存失败：%s" % error_string(result)
