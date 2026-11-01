## Standalone runtime authoring scene. Uses the real game preview, clock, judge, sounds and preferences.
extends Control
const Document = preload("chart_document.gd")
const Library = preload("native_library.gd")
const Timeline = preload("chart_timeline.gd")
const Waveform = preload("waveform_cache.gd")
const Preview = preload("stage_preview.gd")
const KeySettings = preload("../ui/rhythm_key_settings.gd")
@export var ui_theme: Theme = preload("../ui/rhythm_theme.tres")
@export var preview_scene: PackedScene = preload("stage_preview.tscn")
var document: Document
var library: Library = Library.new()
var preview: Preview
var waveform: Waveform
var timeline: Timeline
var overview: Timeline
var path: String = ""
var audio_path: String = ""
var file_revision: String = ""
var cursor: float = 0.0
var view_start: float = 0.0
var view_span: float = 16.0
var snap_division: int = 8
var hidden_divisions: Dictionary = {}
var range_start: float = 0.0
var range_end: float = 0.0
var reference_chart: Variant = null
var analysis: Dictionary = {}
var show_onsets: bool = false
var visible_points: Array[int] = []
var hold_notes: Array = []
var density: Array[int] = []
var _sorted_points: Array[int] = []
var _preview_revision: int = 0
var _file_dialog: FileDialog
var _metadata_dialog: ConfirmationDialog
var _metadata_fields: Dictionary = {}
var _metadata_audio: OptionButton
var _metadata_keys: OptionButton
var _metadata_mode: String = ""
var _pending: Callable
var _confirm: ConfirmationDialog
var _library_picker: OptionButton
var _reference_picker: OptionButton
var _play_picker: OptionButton
var _snap_picker: OptionButton
var _loop: CheckBox
var _audition: CheckBox
var _stage_visible: CheckBox
var _title: Label
var _status: Label
var _clock: Label
var _bpm: SpinBox
var _offset: SpinBox
var _range_start: SpinBox
var _range_end: SpinBox
var _seek_slider: HSlider
var _viewport_container: SubViewportContainer
var _settings_dialog: ConfirmationDialog
var _settings_snapshot: Dictionary = {}
var _audition_player: AudioStreamPlayer
var _audition_serial: int = 0
var _audition_tween: Tween
var _last_audition: int = 0
var _paused: bool = false
var _status_until: int = 0
var _sync_controls: bool = false
var _view_interaction_until: int = 0
var _settings_controls: Dictionary = {}
var _split: HSplitContainer

func _ready() -> void:
	assert(preview_scene!=null,"Missing native preview scene")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_make_theme()
	_build_ui()
	waveform = Waveform.new()
	add_child(waveform)
	waveform.updated.connect(func() -> void: timeline.queue_redraw(); overview.queue_redraw())
	_audition_player = AudioStreamPlayer.new()
	add_child(_audition_player)
	_build_dialogs()
	get_tree().auto_accept_quit = false
	get_window().min_size = Vector2i(1100,650)
	var settings_error: Error = preview.game.backend._load_settings()
	if settings_error != OK:
		push_error(preview.game.backend.last_error)
		status(preview.game.backend.last_error, true)
		set_process(false)
		set_process_input(false)
		return
	preview.game.backend._apply_volume()
	refresh_library()
	if not library.charts.is_empty():
		_open(str(library.charts[0].path))
	timeline.grab_focus()

func _make_theme() -> void:
	assert(ui_theme!=null,"Missing rhythm UI theme")
	theme = ui_theme

func _row(parent: Node) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	return row

func _label(parent: Node, text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _option(parent: Node, items: Array[String], callback: Callable) -> OptionButton:
	var option: OptionButton = OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.get_popup().max_size.y = 420
	for item: String in items:
		option.add_item(item)
	option.item_selected.connect(callback)
	parent.add_child(option)
	return option

func _check(parent: Node, text: String, checked: bool, callback: Callable) -> CheckBox:
	var box: CheckBox = CheckBox.new()
	box.text = text
	box.focus_mode = Control.FOCUS_NONE
	box.button_pressed = checked
	box.toggled.connect(callback)
	parent.add_child(box)
	return box

func _number(parent: Node, low: float, high: float, step: float, value: float, callback: Callable) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 100
	spin.value_changed.connect(callback)
	spin.get_line_edit().text_submitted.connect(func(_text: String) -> void: spin.apply(); timeline.grab_focus())
	parent.add_child(spin)
	return spin

func _panel(parent: Node) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	panel.add_child(box)
	return box

func _build_ui() -> void:
	var background: ColorRect = ColorRect.new()
	background.color = Color("#090e20")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin: MarginContainer = MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,12)
	var layout: VBoxContainer = VBoxContainer.new()
	margin.add_child(layout)
	var header: HBoxContainer = _row(layout)
	var brand: Label = _label(header,"DUET")
	brand.add_theme_font_size_override("font_size",28)
	_title = _label(header,"原生制谱工作台")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(header,"工程信息",func() -> void: show_metadata("edit"))
	_button(header,"音效与同步",show_settings)
	_button(header,"快捷键 F1",show_help)
	var files: HBoxContainer = _row(layout)
	_library_picker = _option(files,[],func(index: int) -> void: _guard(func() -> void: _open(str(_library_picker.get_item_metadata(index)))))
	_library_picker.custom_minimum_size.x = 320
	_library_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(files,"刷新库",refresh_library)
	_button(files,"新建",func() -> void: _guard(func() -> void: show_metadata("new")))
	_button(files,"另存为",func() -> void: show_metadata("save_as"))
	_button(files,"更换音乐",func() -> void: show_metadata("audio"))
	_button(files,"导入音乐",func() -> void: _file_dialog.popup_centered_ratio(0.75))
	_button(files,"删除工程",delete_chart)
	_button(files,"导出",export_chart)
	_split = HSplitContainer.new()
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(_split)
	var left: VBoxContainer = _panel(_split)
	left.get_parent().custom_minimum_size.x = 420
	var edit_row: HBoxContainer = _row(left)
	_label(edit_row,"吸附")
	_snap_picker = _option(edit_row,["1/1","1/2","1/4","1/8","1/16","1/32","1/64"],func(index: int) -> void:
		snap_division = int(pow(2,index)); seek_beat(cursor,false))
	_snap_picker.select(3)
	_label(edit_row,"BPM")
	_bpm = _number(edit_row,30,400,0.01,120,func(value: float) -> void: change_timing(value,true))
	_label(edit_row,"起点 ms")
	_offset = _number(edit_row,-3600000,3600000,0.1,0,func(value: float) -> void: change_timing(value,false))
	timeline = Timeline.new()
	timeline.name = "Timeline"
	timeline.editor = self
	timeline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	timeline.custom_minimum_size.y = 330
	left.add_child(timeline)
	var right: VBoxContainer = VBoxContainer.new()
	right.custom_minimum_size.x = 480
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_split.add_child(right)
	var overview_box: VBoxContainer = _panel(right)
	overview = Timeline.new()
	overview.name = "Overview"
	overview.overview = true
	overview.editor = self
	overview.custom_minimum_size.y = 105
	overview_box.add_child(overview)
	_seek_slider = HSlider.new()
	_seek_slider.focus_mode = Control.FOCUS_NONE
	_seek_slider.step = 0.0001
	_seek_slider.value_changed.connect(func(value: float) -> void:
		if not _sync_controls: pause(); seek_beat(value,true))
	overview_box.add_child(_seek_slider)
	_clock = _label(overview_box,"")
	var preview_box: VBoxContainer = _panel(right)
	preview_box.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	var transport: HBoxContainer = _row(preview_box)
	_play_picker = _option(transport,["从光标","起止区间","从头（5s）"],func(_index: int) -> void: pause(); _paused=false)
	_loop = _check(transport,"循环",false,func(_value: bool) -> void: _update_range())
	_label(transport,"起")
	_range_start = _number(transport,0,100000,0.25,0,func(value: float) -> void: set_marker(false,value))
	_label(transport,"止")
	_range_end = _number(transport,0,100000,0.25,0,func(value: float) -> void: set_marker(true,value))
	var options: HBoxContainer = _row(preview_box)
	_audition = _check(options,"光标试听",true,func(value: bool) -> void:
		if not value: _stop_audition())
	_stage_visible = _check(options,"舞台",true,func(value: bool) -> void: _viewport_container.visible=value)
	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "StageViewport"
	_viewport_container.stretch = true
	_viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport_container.custom_minimum_size = Vector2(420,260)
	preview_box.add_child(_viewport_container)
	var viewport: SubViewport = SubViewport.new()
	viewport.name = "Neon"
	viewport.size = Vector2i(960,540)
	viewport.size_2d_override = Vector2i(1920,1080)
	viewport.size_2d_override_stretch = true
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport_container.add_child(viewport)
	preview = preview_scene.instantiate() as Preview
	preview.name = "Preview"
	viewport.add_child(preview)
	var footer: HBoxContainer = _row(layout)
	_reference_picker = _option(footer,["无参考"],_select_reference)
	_reference_picker.custom_minimum_size.x = 230
	_check(footer,"起音候选",false,func(value: bool) -> void: show_onsets=value; timeline.queue_redraw())
	_button(footer,"网格显示",show_grid_settings)
	_button(footer,"统计对比",show_statistics)
	_status = _label(layout,"")
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_split.split_offset = 0

func _build_dialogs() -> void:
	_confirm = ConfirmationDialog.new()
	_confirm.transparent_bg = true
	_confirm.cancel_button_text = "取消"
	add_child(_confirm)
	_confirm.confirmed.connect(func() -> void:
		if _pending.is_valid(): _pending.call())
	_metadata_dialog = ConfirmationDialog.new()
	_metadata_dialog.transparent_bg = true
	_metadata_dialog.title = "工程信息"
	_metadata_dialog.ok_button_text = "确定"
	_metadata_dialog.cancel_button_text = "取消"
	_metadata_dialog.min_size = Vector2i(620,540)
	_metadata_dialog.dialog_hide_on_ok = false
	add_child(_metadata_dialog)
	var box: VBoxContainer = VBoxContainer.new()
	_metadata_dialog.add_child(box)
	_metadata_audio = _option(box,[],func(_index: int) -> void: pass)
	_metadata_keys = _option(box,["2K","4K"],func(_index: int) -> void: pass)
	for pair: Array in [["project_name","工程名"],["title","音乐名"],["artist","音乐作者"],["mapper","谱面作者"],["difficulty","难度"],["remarks","额外备注"]]:
		_label(box,pair[1])
		var field: LineEdit = LineEdit.new()
		field.max_length = 4000 if pair[0]=="remarks" else 200
		box.add_child(field)
		_metadata_fields[pair[0]] = field
	_metadata_dialog.confirmed.connect(_apply_metadata)
	_file_dialog = FileDialog.new()
	_file_dialog.transparent_bg = true
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = PackedStringArray(["*.wav, *.ogg ; 音乐 WAV / OGG"])
	add_child(_file_dialog)
	_file_dialog.file_selected.connect(func(source: String) -> void:
		var result: Dictionary = library.import_audio(source)
		if result.ok: refresh_library(); status("音乐已导入："+result.path)
		else: status(result.error,true))

func status(message: String, error: bool = false) -> void:
	_status.text = message
	_status.modulate = Color("#ff8e9c") if error else Color("#a6cfdb")
	if error: _status_until=Time.get_ticks_msec()+3500

func _guard(action: Callable) -> void:
	if document!=null and document.dirty:
		_pending = action
		_confirm.title = "未保存修改"
		_confirm.dialog_text = "当前工程有未保存修改。继续将放弃修改。"
		_confirm.ok_button_text = "放弃并继续"
		_confirm.popup_centered()
	else:
		action.call()

func refresh_library() -> void:
	library.scan()
	_library_picker.clear()
	for entry: Dictionary in library.charts:
		_library_picker.add_item(str(entry.name))
		_library_picker.set_item_metadata(_library_picker.item_count-1,entry.path)
		if entry.path==path:
			_library_picker.select(_library_picker.item_count-1)
	_refresh_references()

func _open(next_path: String) -> void:
	var result: Dictionary = library.open_chart(next_path)
	if not result.ok:
		status(result.error,true)
		return
	pause()
	document = result.document
	path = next_path
	for index: int in range(_library_picker.item_count):
		if _library_picker.get_item_metadata(index)==path: _library_picker.select(index)
	audio_path = result.audio_path
	document.audio_path = audio_path
	file_revision = result.revision
	analysis = result.analysis
	_install_audio(result.audio)
	cursor = snap_beat(document.minimum())
	view_start = document.minimum()
	view_span = minf(16.0,document.maximum()-document.minimum())
	range_start = 0.0
	range_end = 0.0
	_paused = false
	_sync_document()
	seek_beat(cursor,false)
	_refresh_references()
	update_status()
	timeline.grab_focus()

func _install_audio(audio: AudioStream) -> void:
	preview.stop_preview()
	preview.song = audio
	preview.audio_id = audio_path.trim_prefix(library.root+"/")
	preview.game.backend._audio.stream = audio
	preview.game.backend._duration = audio.get_length()
	_audition_player.stream = audio
	waveform.begin(audio)

func _refresh_references() -> void:
	if _reference_picker==null:
		return
	_reference_picker.clear()
	_reference_picker.add_item("无参考")
	reference_chart = null
	for entry: Dictionary in library.charts:
		if entry.path!=path and str(entry.path).get_base_dir().path_join(str(entry.data.get("audio_file","")))==audio_path:
			_reference_picker.add_item(str(entry.name))
			_reference_picker.set_item_metadata(_reference_picker.item_count-1,entry.data)

func _select_reference(index: int) -> void:
	reference_chart = null if index==0 else _reference_picker.get_item_metadata(index)
	timeline.queue_redraw()
	update_status()

func _sync_document() -> void:
	if document==null:
		return
	if not document.audio_path.is_empty() and document.audio_path!=audio_path:
		audio_path = document.audio_path
		_install_audio(Library.load_audio(audio_path))
		_refresh_references()
	document.rebuild()
	_preview_revision += 1
	var result: Dictionary = preview.update_chart(document.compile(),_preview_revision,audio_path.trim_prefix(library.root+"/"))
	if not result.ok:
		status(result.error,true)
	_sync_controls = true
	_bpm.value = document.bpm
	_offset.value = document.offset_ms
	_range_start.value = range_start
	_range_end.value = range_end
	_seek_slider.min_value = document.minimum()
	_seek_slider.max_value = document.maximum()
	_sync_controls = false
	hold_notes = document.notes.filter(func(note: Dictionary) -> bool: return float(note.d)>0.0)
	_sorted_points.clear()
	for i: int in range(document.points.size()):
		_sorted_points.append(i)
	_sorted_points.sort_custom(func(a: int,b: int) -> bool: return float(document.points[a].t)<float(document.points[b].t))
	density.resize(80)
	density.fill(0)
	for note: Dictionary in document.notes:
		var bin: int = clampi(int((float(note.t)-document.minimum())/maxf(0.01,document.maximum()-document.minimum())*80),0,79)
		density[bin] += 1
	_update_visible()
	_update_range()
	update_status()
	timeline.queue_redraw()
	overview.queue_redraw()

func _update_visible() -> void:
	visible_points.clear()
	if document==null:
		return
	var lo: int = 0
	var hi: int = _sorted_points.size()
	while lo<hi:
		var mid: int = (lo+hi)/2
		if float(document.points[_sorted_points[mid]].t)<view_start-view_span*0.02:
			lo = mid+1
		else:
			hi = mid
	for i: int in range(lo,_sorted_points.size()):
		var index: int = _sorted_points[i]
		if float(document.points[index].t)>view_start+view_span*1.02:
			break
		visible_points.append(index)

func commit(before: Dictionary) -> void:
	var error: String = document.commit(before)
	_sync_document()
	if not error.is_empty():
		status(error,true)

func change_timing(value: float, tempo: bool) -> void:
	if _sync_controls or document==null:
		return
	pause()
	var before: Dictionary = document.snapshot()
	if tempo: document.bpm=value
	else: document.offset_ms=value
	commit(before)
	set_view(view_start)
	seek_beat(cursor,false)

func snap_beat(value: float) -> float:
	return snappedf(value,4.0/snap_division)

func seek_beat(value: float, audition: bool = false, constrain_view: bool = false) -> void:
	if document==null:
		return
	var step: float = 4.0/snap_division
	var low: float = ceil(document.minimum()/step)*step
	var high: float = floor(document.maximum()/step)*step
	if constrain_view:
		var visible_low: float = maxf(low,ceil(view_start/step)*step)
		var visible_high: float = minf(high,floor((view_start+view_span)/step)*step)
		if visible_low<=visible_high:
			low = visible_low
			high = visible_high
	cursor = clampf(snap_beat(value),low,maxf(low,high))
	if cursor<view_start:
		view_start = cursor
	elif cursor>view_start+view_span:
		view_start = cursor-view_span
	view_start = clampf(view_start,document.minimum(),maxf(document.minimum(),document.maximum()-view_span))
	_update_visible()
	if not preview.playing:
		preview.seek_to(document.seconds(cursor),false)
	if audition:
		_audition_cursor()
	_sync_controls = true
	_seek_slider.value = cursor
	_sync_controls = false
	timeline.queue_redraw()
	overview.queue_redraw()

func set_view(value: float) -> void:
	if document==null: return
	_view_interaction_until = Time.get_ticks_msec()+800
	view_start = clampf(value,document.minimum(),maxf(document.minimum(),document.maximum()-view_span))
	seek_beat(clampf(cursor,view_start,view_start+view_span),false,true)
	_update_visible()

func pan(delta: float) -> void:
	set_view(view_start+delta)

func zoom(delta: float) -> void:
	if document==null: return
	var anchor: float = clampf(cursor,view_start,view_start+view_span)
	var ratio: float = (anchor-view_start)/view_span
	var total: float = document.maximum()-document.minimum()
	view_span = clampf(view_span*exp(delta),minf(2.0,total),minf(128.0,total))
	set_view(anchor-ratio*view_span)

func move_cursor(direction: int) -> void:
	pause()
	var next: float = snap_beat(cursor)+direction*4.0/snap_division
	if next>view_start+view_span: view_start+=view_span
	elif next<view_start: view_start-=view_span
	seek_beat(next,true)

func set_marker(end: bool, value: float) -> void:
	if _sync_controls or document==null: return
	if end: range_end=maxf(0.0,value)
	else: range_start=maxf(0.0,value)
	_sync_controls = true
	_range_start.value = range_start
	_range_end.value = range_end
	_sync_controls = false
	_update_range()
	timeline.queue_redraw()
	overview.queue_redraw()

func _update_range() -> bool:
	if document==null: return false
	var start: float = document.seconds(maxf(document.minimum(),range_start))
	var end: float = document.duration if range_end==0.0 else document.seconds(range_end)
	if _play_picker.selected!=1:
		start = document.seconds(document.minimum())
		end = document.duration
	var result: Dictionary = preview.set_range(start,end,_loop.button_pressed and _play_picker.selected==1)
	if not result.ok: status(result.error,true)
	return bool(result.ok)

func play() -> void:
	if document==null: return
	if preview.playing:
		pause()
		_paused = true
		return
	_stop_audition()
	if not _update_range(): return
	var start: float = cursor
	var prepare: bool = false
	if not _paused:
		if _play_picker.selected==1: start=range_start
		elif _play_picker.selected==2: start=document.minimum(); prepare=true
	if document.seconds(start)>=preview.range_end:
		status("播放位置已到终点",true)
		return
	preview.seek_to(document.seconds(start),true,prepare)
	_paused = false

func resume_cursor() -> void:
	_stop_audition()
	if _update_range():
		preview.seek_to(document.seconds(cursor),true)

func pause() -> void:
	if preview==null: return
	if preview.playing and document!=null:
		var now: float = float(preview.status().cursor_time)
		preview.stop_preview()
		seek_beat(document.beat(now),false)
	_stop_audition()

func _process(_delta: float) -> void:
	if document==null: return
	if preview.playing:
		var state: Dictionary = preview.status()
		var time: float = float(state.cursor_time)
		var display_beat: float = document.beat(time)
		var step: float = 4.0/snap_division
		cursor = clampf(snap_beat(display_beat),ceil(document.minimum()/step)*step,floor(document.maximum()/step)*step)
		if Time.get_ticks_msec()>_view_interaction_until and (cursor>view_start+view_span or cursor<view_start):
			view_start = clampf(cursor,document.minimum(),maxf(document.minimum(),document.maximum()-view_span))
			_update_visible()
		timeline.queue_redraw()
		overview.queue_redraw()
		_sync_controls = true
		_seek_slider.value = cursor
		_sync_controls = false
		_clock.text = "%.3f 拍 · %.3f / %.2f s   AUTO %d" % [display_beat,time,document.duration,int(state.combo)]
	else:
		_clock.text = "%.3f 拍 · %.3f / %.2f s" % [cursor,document.seconds(cursor),document.duration]
	if not waveform.complete:
		_clock.text += " · 波形 %d%%" % int(waveform.progress*100)

func _stop_audition() -> void:
	_audition_serial += 1
	if _audition_tween!=null and _audition_tween.is_valid(): _audition_tween.kill()
	if _audition_player!=null: _audition_player.stop()

func _audition_cursor() -> void:
	if not _audition.button_pressed or preview.playing or timeline.drag.get("resume",false) or overview.drag.get("resume",false) or Time.get_ticks_msec()-_last_audition<35: return
	_last_audition = Time.get_ticks_msec()
	_stop_audition()
	var serial: int = _audition_serial
	var time: float = document.seconds(cursor)
	var length: float = 0.12
	if time+length<=0.0: return
	_audition_player.volume_linear = preview.game.backend._audio.volume_linear
	if time<0.0:
		await get_tree().create_timer(-time).timeout
		if serial!=_audition_serial or preview.playing: return
		length += time
		time = 0.0
	_audition_player.play(time)
	_audition_tween = create_tween()
	_audition_tween.tween_interval(maxf(0.0,length-0.015))
	_audition_tween.tween_property(_audition_player,"volume_linear",0.0,0.015)
	_audition_tween.tween_callback(func() -> void: _audition_player.stop())

func update_status() -> void:
	if document==null: return
	_title.text = "%s · %dK%s" % [document.data.get("project_name",document.data.get("title","")),document.key_count()," ●" if document.dirty else ""]
	if Time.get_ticks_msec()<_status_until: return
	var counts: Array[int] = [0,0,0,0]
	var subs: int = 0
	for note: Dictionary in document.notes:
		counts[int(note.l)] += 1
		subs += note.s.size()
	status("%s  · %d 音符 / %d Sub · 选中 %d 点%s" % ["W E / S D" if document.key_count()==2 else "Q W E R / A S D F",document.notes.size(),subs,document.selected.size()," · 落单长按 %d" % document.unpaired.size() if not document.unpaired.is_empty() else ""])

func show_metadata(mode: String) -> void:
	if document==null and mode!="new": return
	pause()
	_metadata_mode = mode
	_metadata_dialog.title = {"new":"新建工程","edit":"工程信息","save_as":"另存为","audio":"更换音乐"}[mode]
	_metadata_audio.clear()
	for audio: String in library.audios:
		_metadata_audio.add_item(audio.trim_prefix(library.root+"/"))
		_metadata_audio.set_item_metadata(_metadata_audio.item_count-1,audio)
		if audio==audio_path: _metadata_audio.select(_metadata_audio.item_count-1)
	_metadata_audio.disabled = mode not in ["new","audio"]
	_metadata_keys.disabled = mode!="new"
	_metadata_keys.select(1 if document!=null and document.key_count()==4 else 0)
	for key: String in _metadata_fields:
		(_metadata_fields[key] as LineEdit).text = str(document.data.get(key,"")) if mode!="new" and document!=null else ("Easy" if key=="difficulty" else "")
	if mode=="save_as":
		(_metadata_fields.project_name as LineEdit).text += "_copy"
	_metadata_dialog.popup_centered()

func _apply_metadata() -> void:
	if _metadata_audio.item_count==0:
		status("请先导入音乐",true); return
	var next_audio: String = str(_metadata_audio.get_item_metadata(_metadata_audio.selected))
	var audio: AudioStream = Library.load_audio(next_audio)
	if audio==null: status("音源读取失败",true); return
	var values: Dictionary = {}
	for key: String in _metadata_fields:
		values[key] = (_metadata_fields[key] as LineEdit).text.strip_edges()
	var name_error: String = Library.name_error(str(values.project_name))
	if not name_error.is_empty(): status(name_error,true); return
	for key: String in ["title","artist","difficulty"]:
		if str(values[key]).is_empty(): status("请填写音乐名、音乐作者和难度",true); return
	if _metadata_mode=="new":
		var data: Dictionary = {"format_version":3,"key_count":2 if _metadata_keys.selected==0 else 4,"note_type":"tap_hold","audio_file":next_audio.get_file(),"notes_ms":[],"lanes":[],"durations_ms":[],"subs_ms":[],"editor":{"bpm":120.0,"offset_ms":0.0,"note_points":[],"beat_notes":[]}}
		data.merge(values,true)
		var fresh: Document = Document.new()
		fresh.open(data,audio.get_length())
		var result: Dictionary = library.save(fresh,"",next_audio,"",true)
		if not result.ok: status(result.error,true); return
		_metadata_dialog.hide()
		refresh_library()
		_open(result.path)
		return
	if _metadata_mode=="save_as":
		var copy: Document = Document.new()
		copy.open(document.stored(),document.duration)
		copy.data.merge(values,true)
		var result: Dictionary = library.save(copy,"",audio_path,"",true)
		if not result.ok: status(result.error,true); return
		_metadata_dialog.hide()
		refresh_library()
		_open(result.path)
		return
	var before: Dictionary = document.snapshot()
	var old_duration: float = document.duration
	document.data.merge(values,true)
	document.data.audio_file = next_audio.get_file()
	document.duration = audio.get_length()
	document.audio_path = next_audio
	var error: String = document.commit(before)
	if not error.is_empty():
		document.duration = old_duration
		status(error,true)
		return
	audio_path = next_audio
	_install_audio(audio)
	_metadata_dialog.hide()
	_sync_document()

func save() -> void:
	if document==null: return
	pause()
	var result: Dictionary = library.save(document,path,audio_path,file_revision,false)
	if not result.ok: status(result.error,true); return
	path = result.path
	file_revision = result.revision
	refresh_library()
	update_status()
	status("已保存："+path.get_file())

func delete_chart() -> void:
	if document==null: return
	pause()
	_pending = func() -> void:
		var result: Dictionary = library.recover(path,file_revision)
		if not result.ok: status(result.error,true); return
		document = null
		path = ""
		refresh_library()
		if not library.charts.is_empty(): _open(library.charts[0].path)
		else: status("谱面已移入恢复目录："+result.path)
	_confirm.title = "删除工程"
	_confirm.dialog_text = "将工程移到恢复目录，音乐文件保留。"
	_confirm.ok_button_text = "删除工程"
	_confirm.popup_centered()

func export_chart() -> void:
	if document==null: return
	var dialog: FileDialog = FileDialog.new()
	dialog.transparent_bg = true
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.filters = PackedStringArray(["*.json ; 谱面 JSON"])
	dialog.current_file = Library.filename(str(document.data.project_name))
	add_child(dialog)
	dialog.file_selected.connect(func(target: String) -> void:
		var file: FileAccess = FileAccess.open(target,FileAccess.WRITE)
		if file==null: status("导出失败",true)
		else: file.store_string(JSON.stringify(document.stored(),"  ",false)); file.close(); status("已导出工程；音源需放在同目录")
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.7)

func show_statistics() -> void:
	if document==null: return
	var dialog: AcceptDialog=AcceptDialog.new()
	dialog.transparent_bg = true
	dialog.title="谱面统计"
	dialog.ok_button_text="关闭"
	var grid: GridContainer=GridContainer.new()
	grid.columns=3
	grid.add_theme_constant_override("h_separation",28)
	dialog.add_child(grid)
	var current: Dictionary=_statistics(document.compile())
	var reference: Dictionary=_statistics(reference_chart) if reference_chart!=null else {}
	for values: Array in [["","当前","参考"],["heads","主动按下",""],["holds","长按",""],["subs","Sub",""],["units","总判定",""],["peak","峰值 / 秒",""]]:
		if values[0]=="":
			for value: String in values: _label(grid,value)
		else:
			_label(grid,values[1])
			_label(grid,str(current[values[0]]))
			_label(grid,str(reference.get(values[0],"—")))
	for lane: int in range(document.key_count()):
		_label(grid,"轨道 %d" % (lane+1))
		_label(grid,str(current.lanes.count(lane)))
		_label(grid,str(reference.get("lanes",[]).count(lane)) if not reference.is_empty() else "—")
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(430,340))

func _statistics(chart: Dictionary) -> Dictionary:
	var holds: int=0
	var subs: int=0
	var peak: int=0
	var left: int=0
	for i: int in range(chart.notes_ms.size()):
		if float(chart.durations_ms[i])>0: holds+=1
		subs+=chart.subs_ms[i].size()
		while left<i and float(chart.notes_ms[left])<=float(chart.notes_ms[i])-1000:
			left+=1
		peak=maxi(peak,i-left+1)
	return {"heads":chart.notes_ms.size(),"holds":holds,"subs":subs,"units":chart.notes_ms.size()+holds+subs,"peak":peak,"lanes":chart.lanes}

func show_grid_settings() -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.transparent_bg = true
	dialog.title = "细分线显示"
	dialog.ok_button_text = "完成"
	var box: VBoxContainer = VBoxContainer.new()
	dialog.add_child(box)
	for division: int in [1,2,4,8,16,32,64]:
		_check(box,"1/%d" % division,not hidden_divisions.has(division),func(value: bool) -> void:
			if value: hidden_divisions.erase(division)
			else: hidden_divisions[division]=true
			timeline.queue_redraw())
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(300,350))

func show_settings() -> void:
	pause()
	if _settings_dialog!=null: _settings_dialog.queue_free()
	_settings_snapshot = preview.game.backend.settings.duplicate(true)
	_settings_controls.clear()
	_settings_dialog = ConfirmationDialog.new()
	_settings_dialog.transparent_bg = true
	_settings_dialog.title = "音效、同步与演奏按键"
	_settings_dialog.ok_button_text = "应用并保存"
	_settings_dialog.cancel_button_text = "取消"
	_settings_dialog.min_size = Vector2i(860,590)
	add_child(_settings_dialog)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(820, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_dialog.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var keys: KeySettings = KeySettings.new()
	keys.backend = preview.game.backend
	box.add_child(keys)
	for pair: Array in [["visual_ms","画面补偿 ms",-250,250,1],["input_ms","按压补偿 ms",-250,250,1],["approach","下落时间 s",0.5,3,0.05]]:
		var row: HBoxContainer = _row(box)
		_label(row,pair[1]).custom_minimum_size.x=180
		var key: String = pair[0]
		_settings_controls[key]=_number(row,pair[2],pair[3],pair[4],float(preview.game.backend.settings[key]),func(value: float) -> void: preview.game.backend.settings[key]=value)
	for pair: Array in [["volume","BGM"],["success_volume","成功敲击"],["empty_volume","空敲击"],["hold_start_volume","长按开始"],["hold_sub_volume","长按 Sub"],["hold_end_volume","长按结束"]]:
		var row: HBoxContainer = _row(box)
		_label(row,pair[1]).custom_minimum_size.x=150
		var key: String = pair[0]
		_number(row,0,200,1,float(preview.game.backend.settings[key])*100,func(value: float) -> void:
			preview.game.backend.settings[key]=value/100.0; preview.game.backend._apply_volume())
		_label(row,"%")
		if key=="volume": continue
		var kind: String = key.trim_suffix("_volume")
		var ids: Array = preview.game.backend.Synth.TAP_FILES.keys()
		var names: Array[String] = []
		for id: String in ids: names.append(preview.game.backend.Synth.TAP_NAMES[id])
		var option: OptionButton = _option(row,names,func(index: int) -> void: preview.game.backend.settings[kind+"_sound"]=ids[index])
		option.custom_minimum_size.x=300
		option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		option.select(maxi(0,ids.find(preview.game.backend.settings[kind+"_sound"])))
		_button(row,"试听",func() -> void: preview.game._play_sound(preview.game._tap_preview,kind))
	_check(box,"使用谱面指定音效",bool(preview.game.backend.settings.use_chart_sounds),func(value: bool) -> void: preview.game.backend.settings.use_chart_sounds=value)
	_label(box,"与游戏端共用音效、响度、声像和校准配置。")
	_settings_dialog.confirmed.connect(func() -> void:
		var result: Error = preview.game.backend._save_settings()
		status("共享设置已保存" if result==OK else "设置保存失败："+error_string(result),result!=OK)
		preview.game._tap_preview.stop())
	_settings_dialog.canceled.connect(func() -> void:
		preview.game.backend.settings=_settings_snapshot.duplicate(true)
		preview.game.backend._apply_volume()
		preview.game._tap_preview.stop())
	_settings_dialog.popup_centered()

func show_help() -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.transparent_bg = true
	dialog.title = "编辑快捷键"
	dialog.ok_button_text = "关闭"
	dialog.dialog_text = "4K：Q W E R 单击 / A S D F 长按标识\n2K：W E 单击 / S D 长按标识\n同类删除、异类覆盖；长按内单击自动成为 Sub\n← →：吸附移动，边缘翻页    [ ]：切换吸附\n滚轮：光标中心缩放    Ctrl+滚轮：平移\n中键拖动：平移视野    音频区左键拖动：吸附定位\n框选后拖动：移动时间 / 跨轨覆盖    右键：删除点\nCtrl+C / X / V：复制 / 剪切 / 粘贴\nCtrl+A：全选    Delete：删除    M：轨道镜像\nCtrl+Z / Shift+Z / Y：撤销 / 重做\nShift+F / G：选中长按头尾后填充 / 清除 Sub\nI / O：设置起止    Space：播放暂停    Esc：停止\nCtrl+S：保存    Enter：结束单行输入"
	add_child(dialog)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(700,520))

func _input(event: InputEvent) -> void:
	if not event is InputEventKey: return
	var key: InputEventKey = event
	if not key.pressed: return
	for child: Node in get_children():
		if child is Window and (child as Window).visible: return
	if _metadata_dialog.visible or _confirm.visible or (_settings_dialog!=null and _settings_dialog.visible) or _file_dialog.visible:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		if key.keycode==KEY_S and (key.ctrl_pressed or key.meta_pressed):
			if focused.get_parent() is SpinBox: (focused.get_parent() as SpinBox).apply()
			timeline.grab_focus()
			save()
			get_viewport().set_input_as_handled()
		elif key.keycode==KEY_ENTER and not focused is TextEdit:
			if focused.get_parent() is SpinBox: (focused.get_parent() as SpinBox).apply()
			timeline.grab_focus()
			get_viewport().set_input_as_handled()
		return
	if key.keycode==KEY_F1:
		show_help(); get_viewport().set_input_as_handled(); return
	if document==null: return
	var mod: bool = key.ctrl_pressed or key.meta_pressed
	if key.keycode==KEY_ESCAPE:
		timeline.cancel_gesture(); overview.cancel_gesture(); pause(); document.selected.clear(); _paused=false
	elif not timeline.drag.is_empty() or not overview.drag.is_empty():
		return
	elif mod:
		match key.keycode:
			KEY_S: save()
			KEY_A:
				for i: int in range(document.points.size()): document.selected[i]=true
			KEY_C, KEY_X:
				if not document.selected.is_empty():
					DisplayServer.clipboard_set(document.clipboard())
					if key.keycode==KEY_X: _edit(document.erase_selected)
			KEY_V:
				_edit(func() -> void:
					var error: String = document.paste(DisplayServer.clipboard_get(),cursor)
					if not error.is_empty(): status(error,true))
			KEY_Z, KEY_Y:
				document.undo(key.keycode==KEY_Y or key.shift_pressed); _sync_document()
			_: return
	elif key.keycode in [KEY_LEFT,KEY_RIGHT]:
		move_cursor(-1 if key.keycode==KEY_LEFT else 1)
	elif key.keycode in [KEY_BRACKETLEFT,KEY_BRACKETRIGHT]:
		var index: int = clampi(_snap_picker.selected+(-1 if key.keycode==KEY_BRACKETLEFT else 1),0,6)
		_snap_picker.select(index); snap_division=int(pow(2,index)); seek_beat(cursor,false)
	elif key.keycode==KEY_SPACE and not key.echo:
		play()
	elif key.keycode in [KEY_DELETE,KEY_BACKSPACE]:
		_edit(document.erase_selected)
	elif key.keycode==KEY_M and not key.echo:
		_edit(document.mirror)
	elif key.keycode in [KEY_I,KEY_O]:
		set_marker(key.keycode==KEY_O,cursor)
	elif key.shift_pressed and key.keycode in [KEY_F,KEY_G]:
		_edit(func() -> void: document.fill_subs(4.0/snap_division,key.keycode==KEY_G))
	else:
		if key.echo or key.shift_pressed or key.alt_pressed: return
		var taps: Array = [KEY_W,KEY_E] if document.key_count()==2 else [KEY_Q,KEY_W,KEY_E,KEY_R]
		var holds: Array = [KEY_S,KEY_D] if document.key_count()==2 else [KEY_A,KEY_S,KEY_D,KEY_F]
		var code: int = key.physical_keycode if key.physical_keycode!=0 else key.keycode
		var lane: int = taps.find(code)
		var hold: bool = false
		if lane<0: lane=holds.find(code); hold=true
		if lane<0: return
		_edit(func() -> void: document.toggle(cursor,lane,"hold" if hold else "tap"))
	get_viewport().set_input_as_handled()
	update_status()
	timeline.queue_redraw()

func _edit(action: Callable) -> void:
	if not timeline.drag.is_empty() or not overview.drag.is_empty(): return
	var before: Dictionary = document.snapshot()
	action.call()
	commit(before)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST:
		_guard(func() -> void: get_tree().quit())

func _exit_tree() -> void:
	_stop_audition()
