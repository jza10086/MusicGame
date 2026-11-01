## Native canvas: only visible geometry is drawn; editing gestures commit once on release.
extends Control
const Document = preload("chart_document.gd")
var editor: Variant
var overview: bool = false
var drag: Dictionary = {}
var _font: Font
const COLORS: Array[Color] = [Color("#6edcda"),Color("#a0cbe8"),Color("#c0afe4"),Color("#e995d7")]
const GRID_ALPHA: Dictionary = {1:1.0,2:0.62,4:0.40,8:0.23,16:0.14,32:0.28,64:0.19}

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	clip_contents = true
	_font = get_theme_default_font()
	resized.connect(queue_redraw)

func color(lane: int) -> Color:
	return COLORS[lane*3 if editor.document.key_count()==2 else lane]

func bounds() -> Vector2:
	if overview:
		return Vector2(editor.document.minimum(),editor.document.maximum()-editor.document.minimum())
	return Vector2(editor.view_start,editor.view_span)

func x_at(beat: float) -> float:
	var view: Vector2 = bounds()
	return (beat-view.x)/view.y*size.x

func beat_at(x: float) -> float:
	var view: Vector2 = bounds()
	return view.x+x/maxf(1.0,size.x)*view.y

func lane_step() -> float:
	return (size.y-108.0)/editor.document.key_count()

func lane_at(y: float) -> int:
	return clampi(int((y-100.0)/lane_step()),0,editor.document.key_count()-1)

func lane_y(lane: int) -> float:
	return 100.0+lane_step()*(lane+0.5)

func glyph(point: Dictionary) -> Vector2:
	return Vector2(x_at(float(point.t)),lane_y(int(point.l)))

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#0d1628"))
	if editor==null or editor.document==null:
		return
	var document: Document = editor.document
	var view: Vector2 = bounds()
	if view.y<=0.0:
		return
	if editor.waveform!=null:
		editor.waveform.draw_wave(self,Rect2(0,0,size.x,65.0 if overview else 75.0),document.seconds(view.x),document.seconds(view.x+view.y),Color("#476a82"))
	if overview:
		_draw_density()
		var left: float = x_at(editor.view_start)
		var right: float = x_at(editor.view_start+editor.view_span)
		draw_rect(Rect2(left,0,right-left,size.y),Color(0.6,0.9,1,0.05))
		draw_rect(Rect2(left,0,right-left,size.y),Color("#aac5e1"),false,1.0)
	else:
		_draw_grid()
		_draw_notes()
	_draw_markers()
	var cursor_x: float = x_at(editor.cursor)
	draw_line(Vector2(cursor_x,0),Vector2(cursor_x,size.y),Color("#ffe19a"),2.0)
	if not overview:
		draw_string(_font,Vector2(clampf(cursor_x+5,0,size.x-80),91),("%.3f" % editor.cursor).trim_suffix("0").trim_suffix("0"),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("#ffe7b1"))
		if drag.get("mode","")=="box":
			var rect: Rect2 = Rect2(drag.origin,drag.current-drag.origin).abs()
			draw_rect(rect,Color(0.4,0.8,1,0.10))
			draw_rect(rect,Color("#a9dcff"),false)
		elif drag.get("mode","")=="move":
			for point: Dictionary in _moved_points():
				var pos: Vector2 = glyph(point)
				draw_rect(Rect2(pos-Vector2(5,18),Vector2(10,36)),Color(1,1,1,0.75))
		var selection: Rect2 = selection_rect()
		if selection.size!=Vector2.ZERO:
			draw_rect(selection,Color("#ffe19a"),false,1.5)

func _draw_grid() -> void:
	for lane: int in range(editor.document.key_count()):
		var top: float = 100.0+lane*lane_step()
		draw_rect(Rect2(0,top,size.x,lane_step()-3),Color(color(lane),0.055))
		draw_line(Vector2(0,lane_y(lane)),Vector2(size.x,lane_y(lane)),Color(color(lane),0.18))
		draw_string(_font,Vector2(9,top+20),str(lane+1),HORIZONTAL_ALIGNMENT_LEFT,-1,14,color(lane))
	var step: float = 4.0/editor.snap_division
	var first: int = int(ceil(editor.view_start/step-0.000001))
	var last: int = int(floor((editor.view_start+editor.view_span)/step+0.000001))
	var pixels: Dictionary = {}
	var pixels_per_beat: float = size.x/editor.view_span
	var label_bars: int = int(pow(2,maxf(0,ceil(log(74.0/(4.0*pixels_per_beat))/log(2.0)))))
	for i: int in range(first,last+1):
		var value: float = i*step
		var division: int = 64
		for denominator: int in [1,2,4,8,16,32,64]:
			var q: float = value/(4.0/denominator)
			if absf(q-round(q))<0.00001:
				division=denominator
				break
		var x: float = roundf(x_at(value))
		if not pixels.has(x) or division<int(pixels[x]):
			pixels[x]=division
		if division==1 and int(round(value/4))%label_bars==0:
			draw_string(_font,Vector2(x+5,76),"%d 小节" % (int(round(value/4))+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("#f0f3fa"))
		elif division<=4 and pixels_per_beat>=32:
			draw_string(_font,Vector2(x+4,91),str(posmod(int(round(value)),4)+1),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#91a0b5"))
	var ticks: Dictionary={1:20,2:16,4:12,8:9,16:6,32:4,64:2}
	for pixel: float in pixels:
		var division: int=int(pixels[pixel])
		if editor.hidden_divisions.has(division): continue
		var width: float=2.0 if division==1 else 1.0
		var tint: Color=Color("#e7effc")
		tint.a=float(GRID_ALPHA[division])
		if division==1:
			draw_line(Vector2(pixel,100),Vector2(pixel,size.y),tint,width)
		else:
			for lane: int in range(editor.document.key_count()):
				var top: float=100+lane*lane_step()
				if division>=32:
					var y: float=top+4
					while y<top+lane_step()-8:
						draw_rect(Rect2(pixel,y,width,2 if division==32 else 1),tint)
						y+=10
				else:
					draw_line(Vector2(pixel,top),Vector2(pixel,top+lane_step()-8),tint,width)
		tint.a=maxf(0.48,tint.a)
		draw_rect(Rect2(pixel,100-int(ticks[division]),width,int(ticks[division])),tint)

func _draw_notes() -> void:
	var document: Document = editor.document
	for note: Dictionary in editor.hold_notes:
		if float(note.t)>editor.view_start+editor.view_span:
			break
		if float(note.d)>0.0 and float(note.t)+float(note.d)>=editor.view_start:
			var rect: Rect2 = Rect2(x_at(float(note.t)),lane_y(int(note.l))-22,x_at(float(note.t)+float(note.d))-x_at(float(note.t)),44)
			draw_rect(rect,Color(color(int(note.l)),0.22))
			draw_line(Vector2(rect.position.x,rect.get_center().y),Vector2(rect.end.x,rect.get_center().y),Color(color(int(note.l)),0.8))
	if editor.reference_chart!=null:
		var reference: Dictionary = editor.reference_chart
		for i: int in range(reference.get("notes_ms",[]).size()):
			var t: float = document.beat(float(reference.notes_ms[i])/1000.0)
			if t<editor.view_start or t>editor.view_start+editor.view_span:
				continue
			var lane: int = int(reference.lanes[i])
			if lane<document.key_count():
				draw_rect(Rect2(x_at(t)-3,lane_y(lane)-38,6,12),Color(1,1,1,0.35),false)
	if editor.show_onsets:
		for ms: Variant in editor.analysis.get("onset_times_ms",[]):
			var t: float = document.beat(float(ms)/1000.0)
			if t>=editor.view_start and t<=editor.view_start+editor.view_span:
				draw_line(Vector2(x_at(t),96),Vector2(x_at(t),104),Color("#efbf8c"),2.0)
	for i: int in editor.visible_points:
		var point: Dictionary = document.points[i]
		var pos: Vector2 = glyph(point)
		var tint: Color = Color.WHITE if document.selected.has(i) else color(int(point.l))
		if point.k=="hold":
			draw_rect(Rect2(pos-Vector2(4,31),Vector2(8,62)),tint)
			draw_colored_polygon(PackedVector2Array([pos+Vector2(0,-9),pos+Vector2(7,0),pos+Vector2(0,9),pos+Vector2(-7,0)]),tint)
			if document.unpaired.has(point):
				draw_circle(pos,12,Color("#ffb56e"),false,2.0,true)
		else:
			draw_rect(Rect2(pos-Vector2(3,15),Vector2(6,30)),tint)
		if point.has("sound"):
			draw_circle(pos+Vector2(0,22),2.0,tint)

func _draw_density() -> void:
	if editor.density.is_empty():
		return
	var highest: float = maxf(1.0,float(editor.density.max()))
	for i: int in range(editor.density.size()):
		var left: float = float(i)/editor.density.size()*size.x
		var height: float = float(editor.density[i])/highest*23.0
		draw_rect(Rect2(left,size.y-height,size.x/editor.density.size()-1,height),Color("#65cfcd"))

func _draw_markers() -> void:
	var end: float = editor.document.maximum() if editor.range_end==0.0 else editor.range_end
	for entry: Array in [[editor.range_start,Color("#57adff"),"起点"],[end,Color("#ff6b83"),"终点"]]:
		var x: float = x_at(float(entry[0]))
		draw_line(Vector2(x,0),Vector2(x,size.y),entry[1],1.5)
		draw_rect(Rect2(x-4,0,8,10),entry[1])
		if overview:
			draw_string(_font,Vector2(clampf(x+6,0,size.x-35),16),entry[2],HORIZONTAL_ALIGNMENT_LEFT,-1,12,entry[1])

func selection_rect() -> Rect2:
	var result: Rect2 = Rect2()
	var first: bool = true
	for i: Variant in editor.document.selected:
		if int(i)>=editor.document.points.size():
			continue
		var point: Dictionary = editor.document.points[int(i)]
		var pos: Vector2 = glyph(point)
		var rect: Rect2 = Rect2(pos-Vector2(6,34),Vector2(12,68))
		result = rect if first else result.merge(rect)
		first = false
	return result

func hit(position: Vector2) -> int:
	for i: int in editor.visible_points:
		var point: Dictionary = editor.document.points[i]
		var pos: Vector2 = glyph(point)
		if absf(pos.x-position.x)<=9.0 and absf(pos.y-position.y)<=(34.0 if point.k=="hold" else 19.0):
			return i
	return -1

func _gui_input(event: InputEvent) -> void:
	if editor==null or editor.document==null:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			if not drag.is_empty():
				return
			var direction: float = -1.0 if button.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0
			if button.ctrl_pressed:
				editor.pan(direction*editor.view_span/5.0)
			else:
				editor.zoom(direction*0.18)
			accept_event()
			return
		if not button.pressed and not drag.is_empty():
			_finish(button.position)
			accept_event()
			return
		if not button.pressed:
			return
		grab_focus()
		var position: Vector2 = button.position
		var marker_end: float = editor.document.maximum() if editor.range_end==0.0 else editor.range_end
		if button.button_index==MOUSE_BUTTON_LEFT and position.y<22.0 and (absf(position.x-x_at(editor.range_start))<10 or absf(position.x-x_at(marker_end))<10):
			drag = {"mode":"marker","end":absf(position.x-x_at(marker_end))<absf(position.x-x_at(editor.range_start))}
		elif button.button_index==MOUSE_BUTTON_MIDDLE and not overview:
			editor.pause()
			drag = {"mode":"pan","origin":position,"start":editor.view_start}
		elif button.button_index==MOUSE_BUTTON_LEFT and (overview or position.y<100.0):
			drag = {"mode":"scrub","resume":editor.preview.playing}
			editor.pause()
			editor.seek_beat(beat_at(position.x),true,not overview)
		elif not overview:
			var index: int = hit(position)
			if button.button_index==MOUSE_BUTTON_RIGHT:
				if index>=0:
					editor.pause()
					var before: Dictionary = editor.document.snapshot()
					editor.document.points.remove_at(index)
					editor.document.selected.clear()
					editor.commit(before)
			elif button.button_index==MOUSE_BUTTON_LEFT:
				editor.pause()
				var document: Document = editor.document
				if index>=0 or (not button.shift_pressed and selection_rect().has_point(position) and selection_rect().size!=Vector2.ZERO):
					if index>=0 and button.shift_pressed and document.selected.has(index):
						document.selected.erase(index)
					else:
						if index>=0 and not document.selected.has(index):
							if not button.shift_pressed:
								document.selected.clear()
							document.selected[index] = true
						drag = {"mode":"move","origin":position,"current":position,"beat":editor.snap_beat(beat_at(position.x)),"lane":lane_at(position.y),"points":document.picked(),"before":document.snapshot()}
				else:
					if not button.shift_pressed:
						document.selected.clear()
					drag = {"mode":"box","origin":position,"current":position}
		accept_event()
		queue_redraw()
	elif event is InputEventMouseMotion and not drag.is_empty():
		_motion((event as InputEventMouseMotion).position)
		accept_event()

func _motion(position: Vector2) -> void:
	drag.current = position
	match str(drag.mode):
		"scrub": editor.seek_beat(beat_at(position.x),true,not overview)
		"pan": editor.set_view(float(drag.start)-(position.x-drag.origin.x)/size.x*editor.view_span)
		"marker":
			var value: float = maxf(0.0,editor.snap_beat(beat_at(clampf(position.x,0,size.x))))
			editor.set_marker(bool(drag.end),value)
	queue_redraw()

func _moved_points() -> Array:
	var delta: float = 0.0 if absf(drag.current.x-drag.origin.x)<7.0 else editor.snap_beat(beat_at(drag.current.x))-float(drag.beat)
	var lane_delta: int = lane_at(drag.current.y)-int(drag.lane)
	var lo: int = editor.document.key_count()-1
	var hi: int = 0
	for p: Dictionary in drag.points:
		lo = mini(lo,int(p.l))
		hi = maxi(hi,int(p.l))
	lane_delta = clampi(lane_delta,-lo,editor.document.key_count()-1-hi)
	var result: Array = drag.points.duplicate(true)
	for point: Dictionary in result:
		point.t = float(point.t)+delta
		point.l = int(point.l)+lane_delta
	return result

func _finish(position: Vector2) -> void:
	_motion(position)
	var mode: String = str(drag.mode)
	if mode=="box":
		var rect: Rect2 = Rect2(drag.origin,position-drag.origin).abs()
		for i: int in range(editor.document.points.size()):
			if rect.has_point(glyph(editor.document.points[i])):
				editor.document.selected[i] = true
	elif mode=="move":
		var incoming: Array = _moved_points()
		var before: Dictionary = drag.before
		editor.document.erase_selected()
		editor.document.place(incoming)
		editor.commit(before)
	elif mode=="scrub" and bool(drag.resume):
		editor.resume_cursor()
	drag.clear()
	editor.update_status()
	queue_redraw()

func cancel_gesture() -> void:
	drag.clear()
	queue_redraw()
