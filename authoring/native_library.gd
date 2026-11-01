## Native chart-library IO. Preserve current JSON, recover replaced/deleted files, never write defaults.
extends RefCounted
const Paths = preload("../rhythm_paths.gd")
const Document = preload("chart_document.gd")
var root: String = Paths.resolve("charts")
var charts: Array[Dictionary] = []
var audios: Array[String] = []

func scan() -> void:
	charts.clear()
	audios.clear()
	_scan(root)
	charts.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return str(a.name).naturalnocasecmp_to(str(b.name))<0)
	audios.sort()

func _scan(folder: String) -> void:
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null:
		return
	for name: String in directory.get_directories():
		if not name.begins_with("."):
			_scan(folder.path_join(name))
	for name: String in directory.get_files():
		if name.begins_with("."):
			continue
		var path: String = folder.path_join(name)
		if name.get_extension().to_lower() in ["wav","ogg"]:
			audios.append(path)
		elif name.get_extension().to_lower()=="json":
			var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary and data.get("format_version")==3 and int(data.get("key_count",0)) in [2,4] and data.get("notes_ms") is Array:
				charts.append({"path":path,"name":str(data.get("project_name",name.get_basename())),"data":data})

static func load_audio(path: String) -> AudioStream:
	return Document.Chart.load_audio(path)

static func revision(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path,FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text() # Compare source text directly, including same-second edits; no file hashes.

## Reject malformed source fields before pairing or sorting editable points.
func _source_error(data: Dictionary) -> String:
	var probe: Dictionary = data.duplicate(true)
	if probe.get("notes_ms")==[]:
		if probe.get("lanes")!=[] or probe.get("durations_ms")!=[] or probe.get("subs_ms")!=[] or not probe.get("hit_sounds",[]).is_empty():
			return "空谱面数组不一致"
		probe.notes_ms=[0.0]
		probe.lanes=[0]
		probe.durations_ms=[0.0]
		probe.subs_ms=[[]]
	var report: Dictionary=Document.Chart.validate(probe)
	if not report.ok: return str(report.error)
	var meta: Variant=data.get("editor",{})
	if not meta is Dictionary: return "工程编辑信息无效"
	for field: String in ["bpm","offset_ms"]:
		var value: Variant=meta.get(field,120.0 if field=="bpm" else 0.0)
		if not (value is int or value is float) or not is_finite(float(value)):
			return "工程拍子参数无效"
	if float(meta.get("bpm",120))<30 or float(meta.get("bpm",120))>400: return "BPM 必须为 30–400"
	for field: String in ["note_points","beat_notes"]:
		if not meta.has(field): continue
		if not meta[field] is Array or meta[field].size()>300000: return "编辑点数组无效"
		for point: Variant in meta[field]:
			if not point is Dictionary: return "编辑点不是对象"
			for key: String in ["t","l"]:
				if not (point.get(key) is int or point.get(key) is float) or not is_finite(float(point[key])): return "编辑点位置无效"
			if int(point.l)!=float(point.l) or int(point.l)<0 or int(point.l)>=int(data.key_count): return "编辑点轨道无效"
			if field=="note_points":
				if point.get("k") not in ["tap","hold"]: return "编辑点类型无效"
			else:
				if not (point.get("d") is int or point.get("d") is float) or not is_finite(float(point.d)) or float(point.d)<0 or not point.get("s") is Array: return "拍子音符无效"
				for sub: Variant in point.s:
					if not (sub is int or sub is float) or not is_finite(float(sub)): return "Sub 拍子无效"
			if point.has("sound") and not point.sound is String: return "编辑点音效无效"
	return ""

func open_chart(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or data.get("format_version")!=3 or int(data.get("key_count",0)) not in [2,4]:
		return {"ok":false,"error":"不是当前 2K / 4K 谱面工程"}
	if str(data.get("project_name","")).is_empty():
		data.project_name = path.get_file().get_basename()
	var name: String = str(data.get("audio_file",""))
	if name.is_empty() or name!=name.get_file() or name.contains("..") or name.contains(":") or name.contains("\\"):
		return {"ok":false,"error":"音源须在谱面同目录"}
	var audio_path: String = path.get_base_dir().path_join(name)
	var audio: AudioStream = load_audio(audio_path)
	if audio == null:
		return {"ok":false,"error":"无法读取 WAV / OGG 音源："+audio_path}
	if not data.has("editor"):
		var candidate: String = path.get_basename()+"_source.json"
		if not FileAccess.file_exists(candidate):
			candidate = path.get_base_dir().path_join("authoring_analysis.json")
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(candidate)) if FileAccess.file_exists(candidate) else {}
		if meta is Dictionary:
			data.editor = {"bpm":meta.get("bpm",120.0),"offset_ms":meta.get("offset_ms",0.0)}
	var source_error: String = _source_error(data)
	if not source_error.is_empty():
		return {"ok":false,"error":source_error}
	var document: Document = Document.new()
	document.open(data,audio.get_length())
	var error: String = document.validate()
	if not error.is_empty():
		return {"ok":false,"error":error}
	var analysis: Dictionary = {}
	var analysis_path: String = path.get_base_dir().path_join("authoring_analysis.json")
	if FileAccess.file_exists(analysis_path) and name=="bad_apple.ogg":
		var candidate: Variant = JSON.parse_string(FileAccess.get_file_as_string(analysis_path))
		if candidate is Dictionary:
			analysis = candidate
	return {"ok":true,"document":document,"audio":audio,"audio_path":audio_path,"revision":revision(path),"analysis":analysis}

static func filename(name: String) -> String:
	var regex: RegEx = RegEx.new()
	regex.compile("\\s+")
	return regex.sub(name.strip_edges(),"_",true)+".json"

static func name_error(name: String) -> String:
	if name.is_empty() or name!=name.strip_edges() or name.length()>80 or name.begins_with(".") or name.ends_with(".") or name.to_lower().ends_with(".json"):
		return "工程名须为 1–80 字符，不含首尾空格、句点或 .json 后缀"
	for i: int in range(name.length()):
		if name.unicode_at(i)<32 or name[i] in ["<",">",":","\"","/","\\","|","?","*"]:
			return "工程名包含非法文件名字符"
	var base: String = name.get_slice(".",0).to_lower()
	if base in ["con","prn","aux","nul"] or (base.length()==4 and (base.begins_with("com") or base.begins_with("lpt")) and base[3].is_valid_int()):
		return "工程名是系统保留名称"
	return ""

## Save to a sibling temporary file, retaining a recovery copy before replacement or rename.
func save(document: Document, original: String, audio_path: String, expected: String, create: bool) -> Dictionary:
	var error: String = document.validate()
	if error.is_empty():
		error = name_error(str(document.data.get("project_name","")))
	for key: String in ["title","artist","difficulty"]:
		if str(document.data.get(key,"")).strip_edges().is_empty():
			error = "请填写音乐名、音乐作者和难度"
	if not error.is_empty():
		return {"ok":false,"error":error}
	var target: String = audio_path.get_base_dir().path_join(filename(str(document.data.project_name)))
	if not create and revision(original)!=expected:
		return {"ok":false,"error":"文件已被其他程序修改，请重新打开或另存为"}
	if FileAccess.file_exists(target) and (create or target!=original):
		return {"ok":false,"error":"同名工程已存在"}
	var output: Dictionary = document.stored()
	output.audio_file = audio_path.get_file()
	var temporary: String = target.get_base_dir().path_join(".native_editor_%s.tmp" % Time.get_ticks_usec())
	var file: FileAccess = FileAccess.open(temporary,FileAccess.WRITE)
	if file == null:
		return {"ok":false,"error":"不能写入谱面目录："+error_string(FileAccess.get_open_error())}
	file.store_string(JSON.stringify(output,"  ",false)+"\n")
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error!=OK:
		return {"ok":false,"error":"谱面写入失败："+error_string(write_error)}
	var recovery: String = ""
	if not create and FileAccess.file_exists(original):
		var result: Dictionary = recover(original,expected)
		if not result.ok:
			return result
		recovery = result.path
	var move_error: Error = DirAccess.rename_absolute(temporary,target)
	if move_error!=OK:
		if not recovery.is_empty():
			DirAccess.rename_absolute(recovery,original)
		return {"ok":false,"error":"保存替换失败："+error_string(move_error)}
	document.data = output
	document.dirty = false
	return {"ok":true,"path":target,"revision":revision(target),"recovery":recovery}

func recover(path: String, expected: String) -> Dictionary:
	if revision(path)!=expected or expected.is_empty():
		return {"ok":false,"error":"文件已变化，请重新打开"}
	var folder: String = root.path_join(".editor_recovery").path_join("%s_%s" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec()])
	var error: Error = DirAccess.make_dir_recursive_absolute(folder)
	if error!=OK:
		return {"ok":false,"error":"无法创建恢复目录："+error_string(error)}
	var target: String = folder.path_join(path.get_file())
	error = DirAccess.rename_absolute(path,target)
	return {"ok":error==OK,"path":target,"error":"无法移动到恢复目录："+error_string(error)}

func import_audio(source: String) -> Dictionary:
	if source.get_extension().to_lower() not in ["wav","ogg"]:
		return {"ok":false,"error":"支持 WAV / OGG"}
	var folder: String = root.path_join(source.get_file().get_basename())
	var target: String = folder.path_join(source.get_file())
	if FileAccess.file_exists(target):
		if ProjectSettings.globalize_path(target).simplify_path()==source.simplify_path():
			return {"ok":true,"path":target}
		return {"ok":false,"error":"音乐目录已有同名文件，请重命名后导入"}
	var error: Error = DirAccess.make_dir_recursive_absolute(folder)
	if error==OK:
		error = DirAccess.copy_absolute(source,target)
	return {"ok":error==OK,"path":target,"error":"导入失败："+error_string(error)}
