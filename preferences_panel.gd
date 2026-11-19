## Connect the generated form to rhythm audio and the protocol master-gain override.
extends Control
const Backend = preload("rhythm_backend.gd")
const Settings = preload("settings.gd")
const Form = preload("res://core/ui/party_config_form.gd")
var _form: Form
var _has_protocol: bool
var _protocol_master: float = 1.0
var _calibration_settings: Dictionary = {}
@onready var _preview: AudioStreamPlayer = %Preview

func configure(value: Dictionary, editable: bool, context: Dictionary) -> void:
	var workspace: Control = context.workspace
	var draft: Dictionary = value.own.duplicate(true)
	if draft.has("bpm"):
		_calibration_settings["bpm"] = draft.bpm
		draft.erase("bpm")
	_has_protocol = not context.protocol_id.is_empty()
	if _has_protocol:
		_protocol_master = context.base["audio.master"]
		draft.inherit_master = not value.common.has("audio.master")
		draft.master_volume = value.common.get("audio.master", _protocol_master)
	_form = preload("res://core/ui/party_config_form.tscn").instantiate()
	_form.configure(draft, editable, {"audience": "local", "schema": Settings.preferences_schema(context)})
	_form.rebuilt.connect(_connect_fields)
	_connect_fields()
	_form.field_changed.connect(func(_key: String, _value: Variant) -> void: _preview.stop())
	workspace.add_form(_form)
	workspace.visibility_changed.connect(func() -> void:
		if not workspace.is_visible_in_tree():
			_preview.stop())

func _connect_fields() -> void:
	for kind: String in Settings.SOUND_KINDS:
		_form.get_field_control(kind + "_sound").get_node("%Preview").pressed.connect(_preview_sound.bind(kind))

## The core commits only the declared common_keys; hidden protocol overrides are untouched.
func get_value() -> Dictionary:
	_preview.stop()
	var own: Dictionary = _form.get_value()
	own.merge(_calibration_settings)
	var common: Dictionary = {}
	var common_keys: Array = []
	if _has_protocol:
		common_keys.append("audio.master")
		if not own.inherit_master:
			common["audio.master"] = own.master_volume
		own.erase("inherit_master")
		own.erase("master_volume")
	return {"ok": true, "own": own, "common": common, "common_keys": common_keys}

func _preview_sound(kind: String) -> void:
	_form.flush()
	var id: String = _form.effective_value(kind + "_sound")
	var master: float = _protocol_master if _has_protocol and _form.effective_value("inherit_master") else (float(_form.effective_value("master_volume")) if _has_protocol else 1.0)
	_preview.stop()
	_preview.stream = Backend.Synth.build_tap() if id == "synth" else load(Backend.Paths.resolve(Backend.Synth.TAP_ROOT + Backend.Synth.TAP_FILES[id]))
	_preview.volume_linear = master * float(_form.effective_value(kind + "_volume")) * db_to_linear(Backend.Synth.TAP_GAIN_DB[id])
	_preview.play()

