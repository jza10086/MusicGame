## Local rhythm preferences. The native authoring tools use an explicit separate preview file.
extends RefCounted
const Synth = preload("rhythm_audio.gd")
const DEFAULTS: Dictionary = {"keys_2k": [KEY_D, KEY_F, KEY_J, KEY_K], "keys_4k": [KEY_D, KEY_F, KEY_J, KEY_K], "use_chart_sounds": true, "visual_ms": 0.0, "input_ms": 0.0, "approach": 1.6, "bpm": 120.0, "volume": 0.65, "success_volume": 0.65, "empty_volume": 0.50, "success_sound": "synth", "empty_sound": "synth", "hold_start_sound": "drum_snare", "hold_sub_sound": "drum_closed_hat", "hold_end_sound": "drum_cross_stick", "hold_start_volume": 0.65, "hold_sub_volume": 0.45, "hold_end_volume": 0.65}

static func schema() -> Dictionary:
	var fields: Dictionary = {}
	var layout: Array = []
	for key: String in DEFAULTS:
		var value: Variant = DEFAULTS[key]
		var field: Dictionary = {"default": value, "title": "settings." + key, "audience": "local", "apply": "next_activation"}
		if value is Array:
			field.merge({"type": "array", "control": "numbers", "items": {"type": "int", "min": 1}, "min_items": 4, "max_items": 4})
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
