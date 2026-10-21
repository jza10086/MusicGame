## Version 2 standalone 2K chart: absolute audio timestamps in milliseconds.
## Source BPM/stop integration belongs to conversion, never to the render clock.
extends RefCounted

static func read_chart(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "谱面不存在：" + path}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var report: Dictionary = validate(parsed)
	if not report.ok:
		return report
	var data: Dictionary = parsed
	var audio_path: String = path.get_base_dir().path_join(data.audio_file)
	var audio: AudioStream = load(audio_path) as AudioStream
	if audio == null:
		return {"ok": false, "error": "无法加载谱面音源：" + audio_path}
	var notes: Array[float] = report.notes
	if audio.get_length() <= notes.back() + 0.15:
		return {"ok": false, "error": "音源长度不足，无法覆盖最后的音符判定窗口"}
	return {"ok": true, "notes": notes, "lanes": report.lanes, "audio": audio, "duration": audio.get_length(), "data": data}

## Validate before changing playback state. Paths stay in the chart directory.
static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "谱面必须是 JSON 对象"}
	var data: Dictionary = value
	if data.get("format_version") != 2 or data.get("key_count") != 2 or data.get("note_type") != "tap":
		return {"ok": false, "error": "只支持版本 2 的双键 tap 谱面"}
	for key: String in ["title", "artist", "difficulty", "audio_file"]:
		if not data.get(key) is String or String(data[key]).is_empty():
			return {"ok": false, "error": "缺少谱面文本字段：" + key}
	var file: String = data.audio_file
	if file != file.get_file() or file.contains(":") or file.contains("..") or file.contains("\\") or file.get_extension().to_lower() != "ogg":
		return {"ok": false, "error": "音源必须是谱面目录内的 OGG 文件"}
	var raw: Variant = data.get("notes_ms")
	if not raw is Array or raw.is_empty() or raw.size() > 100000:
		return {"ok": false, "error": "音符数组为空或超过限制"}
	var raw_lanes: Variant = data.get("lanes")
	if not raw_lanes is Array or raw_lanes.size() != raw.size():
		return {"ok": false, "error": "每个音符必须对应一个轨道"}
	var lanes: Array[int] = []
	var notes: Array[float] = []
	var previous: float = -1.0
	var previous_lane: int = -1
	for index: int in range(raw.size()):
		var timestamp: Variant = raw[index]
		var lane: Variant = raw_lanes[index]
		if not (lane is int or lane is float) or (float(lane) != 0.0 and float(lane) != 1.0):
			return {"ok": false, "error": "轨道只能是 0（左）或 1（右）"}
		if not (timestamp is int or timestamp is float) or not is_finite(float(timestamp)):
			return {"ok": false, "error": "音符时间必须是有限数值"}
		var time: float = float(timestamp) / 1000.0
		if time < 0.0 or time < previous or (time == previous and int(lane) <= previous_lane):
			return {"ok": false, "error": "按时间和轨道升序排列，不可重复同轨同刻音符"}
		notes.append(time)
		lanes.append(int(lane))
		previous = time
		previous_lane = int(lane)
	return {"ok": true, "notes": notes, "lanes": lanes}
