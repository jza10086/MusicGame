## Editable beat points are authoritative; gameplay arrays are derived without changing the judge.
extends RefCounted
const Chart = preload("../rhythm_chart.gd")
var data: Dictionary = {}
var points: Array = []
var notes: Array = []
var unpaired: Array = []
var bpm: float = 120.0
var offset_ms: float = 0.0
var duration: float = 1.0
var selected: Dictionary = {}
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var revision: int = 0
var dirty: bool = false
var audio_path: String = ""
var _minimum: float = 0.0

func key_count() -> int:
	return int(data.get("key_count", 2))

func seconds(beat: float) -> float:
	return offset_ms / 1000.0 + beat * 60.0 / bpm

func beat(seconds_value: float) -> float:
	return (seconds_value - offset_ms / 1000.0) * bpm / 60.0

func minimum() -> float:
	return _minimum

func maximum() -> float:
	return beat(duration)

func snapshot() -> Dictionary:
	return {"data": data.duplicate(true), "points": points.duplicate(true), "bpm": bpm, "offset_ms": offset_ms, "duration": duration, "audio_path": audio_path}

func restore(value: Dictionary) -> void:
	data = value.data.duplicate(true)
	points = value.points.duplicate(true)
	bpm = float(value.bpm)
	offset_ms = float(value.offset_ms)
	duration = float(value.duration)
	audio_path = str(value.audio_path)
	selected.clear()
	rebuild()

func open(value: Dictionary, length: float) -> void:
	data = value.duplicate(true)
	duration = length
	var meta: Dictionary = data.get("editor", {})
	bpm = float(meta.get("bpm", 120.0))
	offset_ms = float(meta.get("offset_ms", 0.0))
	points = []
	if meta.has("note_points"):
		points = meta.note_points.duplicate(true)
	elif meta.has("beat_notes"):
		for note: Dictionary in meta.beat_notes:
			_points_from_note(note)
	else:
		var sounds: Dictionary = {}
		for entry: Dictionary in data.get("hit_sounds", []):
			sounds[Chart.sound_key(float(entry.time_ms) / 1000.0, int(entry.lane))] = entry.sound
		for i: int in range(data.get("notes_ms", []).size()):
			var time: float = float(data.notes_ms[i]) / 1000.0
			var lane: int = int(data.lanes[i])
			var tail: float = time + float(data.durations_ms[i]) / 1000.0
			var note: Dictionary = {"t": beat(time), "l": lane, "d": (tail-time)*bpm/60.0, "s": [],
				"sound": sounds.get(Chart.sound_key(time,lane), ""), "end_sound": sounds.get(Chart.sound_key(tail,lane), ""), "sub_sounds": []}
			for sub: Variant in data.subs_ms[i]:
				note.s.append(beat(float(sub)/1000.0))
				note.sub_sounds.append(sounds.get(Chart.sound_key(float(sub)/1000.0,lane), ""))
			_points_from_note(note)
	undo_stack.clear()
	redo_stack.clear()
	selected.clear()
	dirty = false
	revision += 1
	rebuild()

func _points_from_note(note: Dictionary) -> void:
	_add_raw(float(note.t), int(note.l), "hold" if float(note.d)>0.0 else "tap", str(note.get("sound","")))
	if float(note.d)>0.0:
		_add_raw(float(note.t)+float(note.d), int(note.l), "hold", str(note.get("end_sound","")))
	for i: int in range(note.s.size()):
		var sounds: Array = note.get("sub_sounds", [])
		_add_raw(float(note.s[i]), int(note.l), "tap", str(sounds[i]) if i<sounds.size() else "")

func _add_raw(time: float, lane: int, kind: String, sound: String = "") -> void:
	var point: Dictionary = {"t":time,"l":lane,"k":kind}
	if not sound.is_empty():
		point.sound = sound
	points.append(point)

func rebuild() -> void:
	_minimum = minf(0.0,beat(0.0))
	for point: Dictionary in points:
		_minimum = minf(_minimum,float(point.t))
	notes.clear()
	unpaired.clear()
	for lane: int in range(key_count()):
		var holds: Array = points.filter(func(p: Dictionary) -> bool: return int(p.l)==lane and p.k=="hold")
		holds.sort_custom(_sort_time)
		var pairs: Array = []
		for i: int in range(0, holds.size()-1, 2):
			var note: Dictionary = {"t":float(holds[i].t),"l":lane,"d":float(holds[i+1].t)-float(holds[i].t),"s":[],"sub_sounds":[]}
			if holds[i].has("sound"):
				note.sound = holds[i].sound
			if holds[i+1].has("sound"):
				note.end_sound = holds[i+1].sound
			pairs.append(note)
			notes.append(note)
		if holds.size()%2:
			unpaired.append(holds[-1])
		var taps: Array = points.filter(func(p: Dictionary) -> bool: return int(p.l)==lane and p.k=="tap")
		taps.sort_custom(_sort_time)
		var cursor: int = 0
		for point: Dictionary in taps:
			while cursor<pairs.size() and float(point.t)>float(pairs[cursor].t)+float(pairs[cursor].d)+0.00000001:
				cursor += 1
			if cursor>=pairs.size() or float(point.t)<float(pairs[cursor].t)-0.00000001:
				var note: Dictionary = {"t":float(point.t),"l":lane,"d":0.0,"s":[]}
				if point.has("sound"):
					note.sound = point.sound
				notes.append(note)
			elif float(point.t)>float(pairs[cursor].t)+0.00000001 and float(point.t)<float(pairs[cursor].t)+float(pairs[cursor].d)-0.00000001:
				pairs[cursor].s.append(float(point.t))
				pairs[cursor].sub_sounds.append(str(point.get("sound","")))
	notes.sort_custom(_sort_time)

static func _sort_time(a: Dictionary, b: Dictionary) -> bool:
	return float(a.t)<float(b.t) if not is_equal_approx(float(a.t),float(b.t)) else int(a.l)<int(b.l)

func compile() -> Dictionary:
	var out: Dictionary = data.duplicate(true)
	out.erase("editor")
	out.erase("hit_sounds")
	out.notes_ms = []
	out.lanes = []
	out.durations_ms = []
	out.subs_ms = []
	var sounds: Array = []
	for note: Dictionary in notes:
		out.notes_ms.append(_ms(float(note.t)))
		out.lanes.append(int(note.l))
		out.durations_ms.append(snappedf(float(note.d)*60000.0/bpm,0.001))
		var subs: Array = []
		_sound(sounds, float(note.t), int(note.l), str(note.get("sound","")))
		if float(note.d)>0.0:
			_sound(sounds,float(note.t)+float(note.d),int(note.l),str(note.get("end_sound","")))
		for i: int in range(note.s.size()):
			subs.append(_ms(float(note.s[i])))
			var choices: Array = note.get("sub_sounds",[])
			if i<choices.size():
				_sound(sounds,float(note.s[i]),int(note.l),str(choices[i]))
		out.subs_ms.append(subs)
	if not sounds.is_empty():
		sounds.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.time_ms)<float(b.time_ms) if a.time_ms!=b.time_ms else int(a.lane)<int(b.lane))
		out.hit_sounds = sounds
	return out

func _ms(value: float) -> float:
	return snappedf(seconds(value)*1000.0,0.001)

func _sound(sounds: Array, value: float, lane: int, sound: String) -> void:
	if not sound.is_empty():
		sounds.append({"time_ms":_ms(value),"lane":lane,"sound":sound})

func stored() -> Dictionary:
	var out: Dictionary = compile()
	out.editor = {"bpm":bpm,"offset_ms":offset_ms,"note_points":points.duplicate(true),"beat_notes":notes.duplicate(true)}
	return out

func validate() -> String:
	if not is_finite(bpm) or bpm<30.0 or bpm>400.0 or not is_finite(offset_ms):
		return "BPM 必须为 30–400，起点必须为有限数值"
	var sorted: Array = points.duplicate()
	sorted.sort_custom(_sort_time)
	var previous: Array[float] = [-INF,-INF,-INF,-INF]
	for point: Dictionary in sorted:
		var lane: int = int(point.get("l",-1))
		if not point.get("t") is float and not point.get("t") is int:
			return "编辑点拍数无效"
		if not is_finite(float(point.t)) or lane<0 or lane>=key_count() or float(point.l)!=lane or point.get("k") not in ["tap","hold"]:
			return "编辑点字段无效"
		if seconds(float(point.t))+0.15>=duration:
			return "编辑点超出音乐末尾"
		if float(point.t)-previous[lane]<0.00001:
			return "同轨同拍只能有一个编辑点"
		previous[lane] = float(point.t)
	if notes.is_empty():
		return ""
	var result: Dictionary = Chart.validate(compile())
	return "" if result.ok else str(result.error)

## One gesture becomes one undo step; invalid edits restore the previous document.
func commit(before: Dictionary) -> String:
	rebuild()
	var error: String = validate()
	if not error.is_empty():
		restore(before)
		return error
	if before==snapshot():
		return ""
	undo_stack.append(before)
	if undo_stack.size()>80:
		undo_stack.pop_front()
	redo_stack.clear()
	revision += 1
	dirty = true
	return ""

func undo(redo: bool = false) -> void:
	var source: Array[Dictionary] = redo_stack if redo else undo_stack
	var target: Array[Dictionary] = undo_stack if redo else redo_stack
	if source.is_empty():
		return
	target.append(snapshot())
	restore(source.pop_back())
	revision += 1
	dirty = true

func toggle(time: float, lane: int, kind: String) -> void:
	var same: bool = points.any(func(p: Dictionary) -> bool: return int(p.l)==lane and absf(float(p.t)-time)<0.00001 and p.k==kind)
	points = points.filter(func(p: Dictionary) -> bool: return int(p.l)!=lane or absf(float(p.t)-time)>=0.00001)
	if not same:
		_add_raw(time,lane,kind)
	selected.clear()

func erase_selected() -> void:
	var kept: Array = []
	for i: int in range(points.size()):
		if not selected.has(i):
			kept.append(points[i])
	points = kept
	selected.clear()

func place(incoming: Array) -> void:
	for p: Dictionary in incoming:
		points = points.filter(func(q: Dictionary) -> bool: return int(q.l)!=int(p.l) or absf(float(q.t)-float(p.t))>=0.00001)
	selected.clear()
	for p: Dictionary in incoming:
		selected[points.size()] = true
		points.append(p.duplicate(true))

func picked() -> Array:
	var result: Array = []
	for i: Variant in selected:
		if int(i)<points.size():
			result.append(points[int(i)].duplicate(true))
	return result

func move_selected(delta: float, lane_delta: int) -> void:
	var moving: Array = picked()
	if moving.is_empty():
		return
	var lo: int = key_count()-1
	var hi: int = 0
	for p: Dictionary in moving:
		lo = mini(lo,int(p.l))
		hi = maxi(hi,int(p.l))
	lane_delta = clampi(lane_delta,-lo,key_count()-1-hi)
	erase_selected()
	for p: Dictionary in moving:
		p.t = float(p.t)+delta
		p.l = int(p.l)+lane_delta
	place(moving)

func mirror() -> void:
	var moving: Array = picked()
	erase_selected()
	for p: Dictionary in moving:
		p.l = key_count()-1-int(p.l)
	place(moving)

func fill_subs(step: float, clear: bool) -> void:
	var picked_points: Array = picked()
	var incoming: Array = []
	for note: Dictionary in notes:
		if float(note.d)<=0.0:
			continue
		var head: bool = picked_points.any(func(p: Dictionary) -> bool: return p.k=="hold" and p.l==note.l and absf(float(p.t)-float(note.t))<0.00001)
		var tail: bool = picked_points.any(func(p: Dictionary) -> bool: return p.k=="hold" and p.l==note.l and absf(float(p.t)-float(note.t)-float(note.d))<0.00001)
		if not head or not tail:
			continue
		if clear:
			points = points.filter(func(p: Dictionary) -> bool: return not(p.k=="tap" and p.l==note.l and float(p.t)>float(note.t) and float(p.t)<float(note.t)+float(note.d)))
		else:
			var value: float = float(note.t)+step
			while value<float(note.t)+float(note.d)-0.00000001:
				incoming.append({"t":value,"l":int(note.l),"k":"tap"})
				value += step
	if clear:
		selected.clear()
	elif not incoming.is_empty():
		place(incoming)

func clipboard() -> String:
	return JSON.stringify({"type":"duet-note-points","version":1,"points":picked()})

func paste(text: String, cursor: float) -> String:
	var value: Variant = JSON.parse_string(text)
	if not value is Dictionary or value.get("type")!="duet-note-points" or value.get("version")!=1 or not value.get("points") is Array:
		return "剪贴板不是谱面编辑点"
	var incoming: Array = value.points
	if incoming.is_empty() or incoming.size()>300000:
		return "剪贴板编辑点数量无效"
	var earliest: float = INF
	for p: Variant in incoming:
		if not p is Dictionary or (not p.get("t") is float and not p.get("t") is int) or not is_finite(float(p.t)) or (not p.get("l") is float and not p.get("l") is int):
			return "剪贴板编辑点无效"
		if float(p.l)!=int(p.l) or int(p.l)<0 or int(p.l)>=key_count() or p.get("k") not in ["tap","hold"]:
			return "剪贴板轨道超出当前键数"
		if p.has("sound") and (not p.sound is String or str(p.sound).length()>64):
			return "剪贴板音效无效"
		earliest = minf(earliest,float(p.t))
	for p: Dictionary in incoming:
		p.t = float(p.t)+cursor-earliest
		p.l = int(p.l)
	place(incoming)
	return ""
