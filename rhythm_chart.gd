## Version 3 standalone 2K / 4K chart: absolute audio timestamps in milliseconds.
## Source BPM/stop integration belongs to conversion, never to the render clock.
extends RefCounted
const Paths = preload("rhythm_paths.gd")

static func read_chart(path: String) -> Dictionary:
	if not path.is_absolute_path():
		path = Paths.resolve(path)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "谱面不存在：" + path}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var report: Dictionary = validate(parsed)
	if not report.ok:
		return report
	var data: Dictionary = parsed
	var audio_path: String = path.get_base_dir().path_join(data.audio_file)
	var audio: AudioStream = load_audio(audio_path)
	if audio == null:
		return {"ok": false, "error": "无法加载谱面音源：" + audio_path}
	var notes: Array[float] = report.notes
	if audio.get_length() <= float(report.ends.max()) + 0.15:
		return {"ok": false, "error": "音源长度不足，无法覆盖最后的音符判定窗口"}
	return {"ok": true, "notes": notes, "lanes": report.lanes, "ends": report.ends, "subs": report.subs, "sounds": report.sounds, "audio": audio, "duration": audio.get_length(), "data": data}

## Load imported assets or newly copied authoring audio without requiring an editor import.
static func load_audio(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return ResourceLoader.load(path) as AudioStream
	var absolute: String = ProjectSettings.globalize_path(path)
	match path.get_extension().to_lower():
		"wav": return AudioStreamWAV.load_from_file(absolute)
		"ogg": return AudioStreamOggVorbis.load_from_file(absolute)
	return null

## Validate before changing playback state. Paths stay in the chart directory.
static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary:
		return {"ok": false, "error": "谱面必须是 JSON 对象"}
	var data: Dictionary = value
	if data.get("format_version") != 3 or (data.get("key_count") != 2 and data.get("key_count") != 4) or data.get("note_type") != "tap_hold":
		return {"ok": false, "error": "只支持版本 3 的 2K / 4K tap / hold 谱面"}
	for key: String in ["title", "artist", "difficulty", "audio_file"]:
		if not data.get(key) is String or String(data[key]).is_empty():
			return {"ok": false, "error": "缺少谱面文本字段：" + key}
	var file: String = data.audio_file
	if file != file.get_file() or file.contains(":") or file.contains("..") or file.contains("\\") or file.get_extension().to_lower() not in ["ogg", "wav"]:
		return {"ok": false, "error": "音源必须是谱面目录内的 OGG / WAV 文件"}
	var raw: Variant = data.get("notes_ms")
	if not raw is Array or raw.is_empty() or raw.size() > 100000:
		return {"ok": false, "error": "音符数组为空或超过限制"}
	var raw_lanes: Variant = data.get("lanes")
	if not raw_lanes is Array or raw_lanes.size() != raw.size():
		return {"ok": false, "error": "每个音符必须对应一个轨道"}
	var durations: Variant = data.get("durations_ms")
	if not durations is Array or durations.size() != raw.size():
		return {"ok": false, "error": "每个音符必须有持续时长（tap 为 0）"}
	var raw_subs: Variant = data.get("subs_ms")
	if not raw_subs is Array or raw_subs.size() != raw.size():
		return {"ok": false, "error": "每个音符必须有 sub 数组"}
	var subs: Array = []
	var ends: Array[float] = []
	var key_count: int = int(data.key_count)
	var lane_ends: Array[float] = []
	lane_ends.resize(key_count)
	lane_ends.fill(-INF)
	var lanes: Array[int] = []
	var notes: Array[float] = []
	var previous: float = -INF
	var previous_lane: int = -1
	for index: int in range(raw.size()):
		var timestamp: Variant = raw[index]
		var lane: Variant = raw_lanes[index]
		if not (lane is int or lane is float) or (not is_finite(float(lane)) or float(lane) != floorf(float(lane)) or float(lane) < 0.0 or float(lane) >= key_count):
			return {"ok": false, "error": "轨道编号必须是 0 到 key_count - 1 的整数"}
		if not (timestamp is int or timestamp is float) or not is_finite(float(timestamp)):
			return {"ok": false, "error": "音符时间必须是有限数值"}
		var time: float = float(timestamp) / 1000.0
		if time < previous or (time == previous and int(lane) <= previous_lane):
			return {"ok": false, "error": "按时间和轨道升序排列，不可重复同轨同刻音符"}
		var duration: Variant = durations[index]
		if not (duration is int or duration is float) or not is_finite(float(duration)) or float(duration) < 0.0:
			return {"ok": false, "error": "持续时长必须是非负有限数"}
		if time <= lane_ends[int(lane)]:
			return {"ok": false, "error": "同轨音符不可与长按重叠或共用尾部时刻"}
		var end: float = time + float(duration) / 1000.0
		if not is_finite(end):
			return {"ok": false, "error": "长按结束时间无效"}
		var sub_values: Variant = raw_subs[index]
		if not sub_values is Array or sub_values.size() > 4096:
			return {"ok": false, "error": "sub 必须是有限长度数组"}
		var sub_times: Array[float] = []
		var previous_sub: float = time
		for sub: Variant in sub_values:
			if not (sub is int or sub is float) or not is_finite(float(sub)):
				return {"ok": false, "error": "sub 时间必须是有限数值"}
			var sub_time: float = float(sub) / 1000.0
			if sub_time <= previous_sub or sub_time >= end:
				return {"ok": false, "error": "sub 须严格递增且位于长按头尾之间"}
			sub_times.append(sub_time)
			previous_sub = sub_time
		subs.append(sub_times)
		ends.append(end)
		lane_ends[int(lane)] = end
		notes.append(time)
		lanes.append(int(lane))
		previous = time
		previous_lane = int(lane)

	var sounds: Dictionary[String, String] = {}
	var raw_sounds: Variant = data.get("hit_sounds", [])
	if not raw_sounds is Array or raw_sounds.size() > 300000:
		return {"ok": false, "error": "谱面音效数组无效"}
	var points: Dictionary[String, bool] = {}
	for index: int in range(notes.size()):
		points[sound_key(notes[index], lanes[index])] = true
		points[sound_key(ends[index], lanes[index])] = true
		for sub: float in subs[index]:
			points[sound_key(sub, lanes[index])] = true
	for entry: Variant in raw_sounds:
		if not entry is Dictionary or not entry.get("sound") is String or not entry.get("lane") is float and not entry.get("lane") is int:
			return {"ok": false, "error": "谱面音效字段无效"}
		var at: Variant = entry.get("time_ms")
		if not (at is int or at is float) or not is_finite(float(at)) or not is_finite(float(entry.lane)) or float(entry.lane) != floorf(float(entry.lane)):
			return {"ok": false, "error": "谱面音效时间或轨道无效"}
		var id: String = entry.sound
		var key: String = sound_key(float(at) / 1000.0, int(entry.lane))
		if id.is_empty() or id.length() > 64 or not id.is_valid_identifier() or not points.has(key) or sounds.has(key):
			return {"ok": false, "error": "谱面音效必须对应唯一的有效音符节点"}
		sounds[key] = id
	return {"ok": true, "notes": notes, "lanes": lanes, "ends": ends, "subs": subs, "sounds": sounds}

## Chart timestamps are stored to microsecond precision; keys remain stable through seek and Auto.
static func sound_key(seconds: float, lane: int) -> String:
	return "%d:%d" % [roundi(seconds * 1000000.0), lane]




## Discover only playable current-format charts; analysis JSON and empty drafts stay out.
static func discover_paths(directory: String = "charts") -> Array[String]:
	if not directory.is_absolute_path():
		directory = Paths.resolve(directory)
	var result: Array[String] = []
	var folder: DirAccess = DirAccess.open(directory)
	if folder == null:
		return result
	for child: String in folder.get_directories():
		if not child.begins_with("."):
			result.append_array(discover_paths(directory.path_join(child)))
	for file: String in folder.get_files():
		if file.get_extension().to_lower() != "json":
			continue
		var path: String = directory.path_join(file)
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if validate(value).ok and ResourceLoader.exists(directory.path_join(str(value.audio_file))):
			result.append(path)
	result.sort()
	return result

