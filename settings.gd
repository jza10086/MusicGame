## Local rhythm preferences. The native authoring tools use an explicit separate preview file.
extends RefCounted
const Synth = preload("rhythm_audio.gd")
const DEFAULTS: Dictionary = {"keys_2k": [KEY_D, KEY_F, KEY_J, KEY_K], "keys_4k": [KEY_D, KEY_F, KEY_J, KEY_K], "use_chart_sounds": true, "visual_ms": 0.0, "input_ms": 0.0, "approach": 1.6, "bpm": 120.0, "volume": 0.65, "success_volume": 0.65, "empty_volume": 0.50, "success_sound": "synth", "empty_sound": "synth", "hold_start_sound": "drum_snare", "hold_sub_sound": "drum_closed_hat", "hold_end_sound": "drum_cross_stick", "hold_start_volume": 0.65, "hold_sub_volume": 0.45, "hold_end_volume": 0.65}

const SOUND_KINDS: Array[String] = ["success", "empty", "hold_start", "hold_sub", "hold_end"]

static func schema() -> Dictionary:
	var fields: Dictionary = {}
	var layout: Array = []
	for key: String in DEFAULTS:
		var value: Variant = DEFAULTS[key]
		var field: Dictionary = {"default": value, "title": "settings." + key, "audience": "local", "apply": "next_activation"}
		if value is Array:
			field.merge({"type": "array", "control": "keycodes", "unique": true, "items": {"type": "int", "min": 1}, "min_items": 4, "max_items": 4})
			field.labels = ["keys.left_primary", "keys.left_alt", "keys.right_primary", "keys.right_alt"] if key == "keys_2k" else ["keys.outer_left", "keys.inner_left", "keys.inner_right", "keys.outer_right"]
		elif value is bool:
			field.type = "bool"
		elif value is String:
			field.merge({"type": "string", "values": Synth.TAP_FILES.keys(), "control": "select"})
		else:
			var bounds: Array[float] = [0.0, 2.0]
			match key:
				"visual_ms", "input_ms": bounds = [-250.0, 250.0]
				"approach": bounds = [0.5, 3.0]
				"bpm": bounds = [60.0, 180.0]
			field.merge({"type": "float", "min": bounds[0], "max": bounds[1], "control": "number"})
			if key.ends_with("volume"):
				field.merge({"display_scale": 100.0, "suffix": "%"})
		fields[key] = field
		layout.append({"field": key})
	return {"schema_format": 3, "settings_version": 1, "fields": fields, "layout": layout}

## Project the localized storage fields into the three player-facing tabs.
## Calibration BPM belongs to the authoring tools. Only master gain has a protocol override.
static func preferences_schema(context: Dictionary) -> Dictionary:
	var fields: Dictionary = context.schema.fields.duplicate(true)
	fields.erase("bpm")
	var volume_layout: Array = []
	if not context.protocol_id.is_empty():
		fields["inherit_master"] = {"type": "bool", "default": true, "title": "继承协议总音量", "audience": "local", "apply": "immediate"}
		fields["master_volume"] = context.common_schema.fields["audio.master"].duplicate(true)
		fields.master_volume.title = "总音量"
		fields.master_volume.default = context.base["audio.master"]
		volume_layout.append({"field": "inherit_master", "children": [{"field": "master_volume", "enabled_when": {"field": "inherit_master", "equals": false}}]})
	volume_layout.append({"field": "volume"})
	var sound_layout: Array = [{"field": "use_chart_sounds"}]
	for kind: String in SOUND_KINDS:
		var field: Dictionary = fields[kind + "_sound"]
		field.preview = true
		field.labels = []
		for id: String in field.values:
			field.labels.append(Synth.TAP_NAMES[id])
		sound_layout.append({"field": kind + "_sound", "children": [{"field": kind + "_volume"}]})
	return {"schema_format": 3, "settings_version": 1, "fields": fields, "layout": [
		{"id": "audio", "title": "音效", "children": [
			{"id": "volume", "title": "音量", "children": volume_layout},
			{"id": "hit_sounds", "title": "敲击音效", "children": sound_layout}]},
		{"id": "timing", "title": "音画同步", "children": [
			{"id": "offsets", "title": "时间补偿", "children": [{"field": "visual_ms"}, {"field": "input_ms"}]},
			{"id": "scroll", "title": "下落显示", "children": [{"field": "approach"}]}]},
		{"id": "bindings", "title": "按键绑定", "children": [{"field": "keys_2k"}, {"field": "keys_4k"}]}
	]}
