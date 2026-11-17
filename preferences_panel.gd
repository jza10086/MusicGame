## Rhythm-specific preference presentation. The framework owns Apply and persistence.
## Bindings retain the same four physical keys per mode used by the playback backend.
extends Control
const Backend = preload("rhythm_backend.gd")
const Form = preload("res://core/ui/party_config_form.gd")
const SectionScene: PackedScene = preload("res://core/ui/settings/setting_section.tscn")
const BindingSlot: PackedScene = preload("res://core/ui/settings/binding_slot.tscn")
const ButtonScene: PackedScene = preload("res://core/ui/ambient_reveal/components/button.tscn")
const SOUND_KINDS: Array[String] = ["success", "empty", "hold_start", "hold_sub", "hold_end"]
var _form: Form
var _workspace: Control
var _keys: Dictionary = {}
var _slots: Dictionary[String, Array] = {}
var _has_protocol: bool
var _protocol_master: float = 1.0
var _editable: bool
@onready var _preview: AudioStreamPlayer = %Preview

func configure(value: Dictionary, editable: bool, context: Dictionary) -> void:
	_workspace = context.workspace
	_editable = editable
	_has_protocol = not context.protocol_id.is_empty()
	var fields: Dictionary = context.schema.fields.duplicate(true)
	var draft: Dictionary = value.own.duplicate(true)
	for mode: String in ["keys_2k", "keys_4k"]:
		_keys[mode] = draft.get(mode, Backend.DEFAULTS[mode]).duplicate()
		fields.erase(mode)
		draft.erase(mode)
	var audio_layout: Array = []
	if _has_protocol:
		_protocol_master = float(context.base["audio.master"])
		fields["inherit_master"] = {"type": "bool", "default": true, "title": "继承协议总音量", "audience": "local", "apply": "immediate"}
		fields["master_volume"] = context.common_schema.fields["audio.master"].duplicate(true)
		fields.master_volume.title = "总音量"
		fields.master_volume.default = _protocol_master
		draft.inherit_master = not value.common.has("audio.master")
		draft.master_volume = value.common.get("audio.master", _protocol_master)
		audio_layout.append({"field": "inherit_master", "children": [{"field": "master_volume", "enabled_when": {"field": "inherit_master", "equals": false}}]})
	audio_layout.append({"field": "volume"})
	audio_layout.append({"field": "use_chart_sounds"})
	for kind: String in SOUND_KINDS:
		var field: Dictionary = fields[kind + "_sound"]
		field.labels = []
		for id: String in field.values:
			field.labels.append(Backend.Synth.TAP_NAMES[id])
		audio_layout.append({"field": kind + "_sound", "children": [{"field": kind + "_volume"}]})
	audio_layout.append({"id": "timing", "title": "音画校准", "expanded": false, "children": [
		{"field": "visual_ms"}, {"field": "input_ms"}, {"field": "approach"}, {"field": "bpm"}]})
	_form = preload("res://core/ui/party_config_form.tscn").instantiate()
	_form.configure(draft, editable, {"audience": "local", "schema": {
		"schema_format": 3, "settings_version": 1, "fields": fields,
		"layout": [{"id": "audio", "title": "音效", "children": audio_layout}]}})
	_form.rebuilt.connect(_attach_previews)
	_attach_previews()
	_form.field_changed.connect(func(_key: String, _value: Variant) -> void: _preview.stop())
	_workspace.add_form(_form)
	var bindings: VBoxContainer = VBoxContainer.new()
	bindings.add_theme_constant_override("separation", 12)
	_build_bindings(bindings)
	_workspace.add_option(bindings)
	_workspace.add_page("按键绑定", bindings)
	_workspace.reset_requested.connect(_reset_keys)
	_workspace.visibility_changed.connect(func() -> void:
		if not _workspace.is_visible_in_tree():
			_preview.stop())

## The core commits only the declared common_keys; hidden protocol overrides are untouched.
func get_value() -> Dictionary:
	_preview.stop()
	var own: Dictionary = _form.get_value()
	var common: Dictionary = {}
	var common_keys: Array = []
	if _has_protocol:
		common_keys.append("audio.master")
		if not own.inherit_master:
			common["audio.master"] = own.master_volume
		own.erase("inherit_master")
		own.erase("master_volume")
	for mode: String in _keys:
		own[mode] = _keys[mode].duplicate()
	return {"ok": true, "own": own, "common": common, "common_keys": common_keys}

func _attach_previews() -> void:
	for kind: String in SOUND_KINDS:
		var row: Control = _form.get_field_control(kind + "_sound")
		var choice: OptionButton = row.get_node("%Value")
		choice.get_popup().max_size = Vector2i(1920, 400)
		var line: HBoxContainer = HBoxContainer.new()
		row.add_child(line)
		choice.owner = null
		choice.reparent(line, false)
		choice.owner = row
		choice.unique_name_in_owner = true
		var button: Button = ButtonScene.instantiate()
		button.text = "试听"
		button.custom_minimum_size = Vector2(90, 56)
		button.disabled = not _editable
		button.pressed.connect(_preview_sound.bind(kind))
		line.add_child(button)

func _preview_sound(kind: String) -> void:
	_form.flush()
	var id: String = _form.effective_value(kind + "_sound")
	var master: float = _protocol_master if _has_protocol and _form.effective_value("inherit_master") else (float(_form.effective_value("master_volume")) if _has_protocol else 1.0)
	_preview.stop()
	_preview.stream = Backend.Synth.build_tap() if id == "synth" else load(Backend.Paths.resolve(Backend.Synth.TAP_ROOT + Backend.Synth.TAP_FILES[id]))
	_preview.volume_linear = master * float(_form.effective_value(kind + "_volume")) * db_to_linear(Backend.Synth.TAP_GAIN_DB[id])
	_preview.play()

func _build_bindings(parent: VBoxContainer) -> void:
	for count: int in [2, 4]:
		var mode: String = "keys_%dk" % count
		_slots[mode] = []
		var section: Control = SectionScene.instantiate()
		section.configure("%dK" % count, true)
		parent.add_child(section)
		for lane: int in range(count):
			var row: Control = SectionScene.instantiate()
			row.configure((["左轨", "右轨"] if count == 2 else ["左外轨", "左内轨", "右内轨", "右外轨"])[lane], true)
			section.body().add_child(row)
			var controls: HBoxContainer = HBoxContainer.new()
			controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.set_field(controls, false)
			for alternate: int in range(2 if count == 2 else 1):
				var index: int = lane * 2 + alternate if count == 2 else lane
				var slot: Control = BindingSlot.instantiate()
				slot.configure({"kind": "key", "physical": true, "code": _keys[mode][index]}, _editable, false)
				# Rhythm uses required physical keyboard slots, not mouse or empty bindings.
				slot.get_node("%Kind").hide()
				slot.get_node("%Clear").hide()
				slot.changed.connect(_key_changed.bind(mode, index))
				controls.add_child(slot)
				_slots[mode].append(slot)

func _key_changed(mode: String, index: int) -> void:
	var candidate: Array = _keys[mode].duplicate()
	candidate[index] = int(_slots[mode][index].get_value().code)
	if not Backend.validate_play_keys(candidate):
		_slots[mode][index].get_node("%Capture").configure({"kind": "key", "physical": true, "code": _keys[mode][index]})
		_workspace.status.text = "请选择未被当前模式占用的演奏按键；不能使用修饰键。"
		return
	_keys[mode] = candidate
	_workspace.status.text = ""

func _reset_keys() -> void:
	if not _editable:
		return
	for mode: String in _keys:
		_keys[mode] = Backend.DEFAULTS[mode].duplicate()
		for index: int in range(4):
			_slots[mode][index].get_node("%Capture").configure({"kind": "key", "physical": true, "code": _keys[mode][index]})
