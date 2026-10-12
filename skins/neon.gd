extends "res://skins/stage_canvas.gd"
## Original vector stage: two luminous runways suspended over a midnight arena.
@export var cyan := Color("43e8ff")
@export var pink := Color("ff61b9")
@export var stage_ink := Color("080b24")
var state: Dictionary = {}
const DESIGN := Vector2(1920.0, 1080.0)
const TOP_Y := 190.0
const HIT_Y := 870.0
const TRAVEL := 2.2

func set_state(data: Dictionary) -> void:
	state = data
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _a(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)

func _poly(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)

func _glow(a: Vector2, b: Vector2, color: Color, width: float = 2.0) -> void:
	draw_line(a, b, _a(color, 0.025), width + 20.0, true)
	draw_line(a, b, _a(color, 0.07), width + 8.0, true)
	draw_line(a, b, _a(color, 0.75), width, true)

func _lane_x(lane: int, progress: float) -> float:
	return 960.0 + (-1.0 if lane == 0 else 1.0) * lerpf(41.0, 130.0, progress)

func _lane_width(progress: float) -> float:
	return lerpf(79.0, 250.0, progress)

func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	_begin_environment()
	var t: float = float(state.get("time", 0.0))
	var mode: String = str(state.get("mode", "menu"))
	var gameplay: bool = mode == "playing" or mode == "paused"
	draw_rect(Rect2(Vector2.ZERO, DESIGN), stage_ink)
	_draw_arena(t, gameplay)
	if gameplay:
		_begin_playfield()
		_draw_runway(t)
		_draw_notes()
		_draw_impacts()
	_begin_environment()
	_draw_foreground(t, gameplay)
	draw_set_transform(Vector2.ZERO)

func _draw_arena(t: float, gameplay: bool) -> void:
	# Broad translucent cones intentionally stay behind the side HUD areas.
	for side: int in range(2):
		var sign_side: float = -1.0 if side == 0 else 1.0
		var color: Color = cyan if side == 0 else pink
		var origin := Vector2(960.0 + sign_side * 515.0, 115.0)
		var sway: float = sin(t * 0.45 + float(side) * 2.1) * 65.0
		_poly([origin, Vector2(origin.x + sign_side * 365.0 + sway, 980.0), Vector2(origin.x + sign_side * 80.0 + sway, 980.0)], _a(color, 0.025))
		_poly([origin, Vector2(origin.x + sign_side * 220.0 + sway, 980.0), Vector2(origin.x + sign_side * 150.0 + sway, 980.0)], _a(color, 0.026))
	# Concentric, segmented stadium canopy. The central space remains quiet.
	for ring: int in range(5):
		var radius: float = 535.0 + float(ring) * 88.0
		var col: Color = cyan if ring % 2 == 0 else pink
		for segment: int in range(12):
			var angle: float = PI + float(segment) * PI / 12.0 + 0.018
			draw_arc(Vector2(960.0, 744.0), radius, angle, angle + PI / 12.0 - 0.036, 22, _a(col, 0.045 if ring != 2 else 0.10), 2.0, true)
	# Roof gantry.
	_glow(Vector2(430.0, 135.0), Vector2(1490.0, 135.0), Color("7d7cff"), 1.0)
	for i: int in range(13):
		var x: float = 440.0 + float(i) * 86.0
		draw_line(Vector2(x, 119.0), Vector2(x + 43.0, 134.0), Color("252744"), 1.0, true)
		draw_line(Vector2(x + 43.0, 134.0), Vector2(x + 86.0, 119.0), Color("252744"), 1.0, true)
	# Backstage LED blades / structural towers on both sides.
	for side: int in range(2):
		var sign_side: float = -1.0 if side == 0 else 1.0
		var color: Color = cyan if side == 0 else pink
		for tower: int in range(3):
			var x: float = 960.0 + sign_side * (445.0 + float(tower) * 108.0)
			var top: float = 278.0 + float(tower) * 57.0
			_poly([Vector2(x - 19.0, top), Vector2(x + 19.0, top - 18.0), Vector2(x + 19.0, 790.0), Vector2(x - 19.0, 807.0)], Color("10172e"))
			_glow(Vector2(x - 19.0, top), Vector2(x - 19.0, 804.0), _a(color, 0.3), 1.0)
			for cell: int in range(18):
				var y: float = top + float(cell) * 25.0
				if y > 775.0:
					break
				var alpha: float = 0.055 + 0.07 * (0.5 + 0.5 * sin(float(cell) * 0.65 - t * 1.3 + float(tower)))
				draw_rect(Rect2(x - 12.0, y, 22.0, 10.0), _a(color, alpha))
		# Angled side-platform lips.
		_poly([Vector2(960.0 + sign_side * 350.0, 793.0), Vector2(960.0 + sign_side * 696.0, 848.0), Vector2(960.0 + sign_side * 748.0, 907.0), Vector2(960.0 + sign_side * 334.0, 835.0)], Color("11172e"))
		_glow(Vector2(960.0 + sign_side * 350.0, 794.0), Vector2(960.0 + sign_side * 696.0, 849.0), _a(color, 0.22), 2.0)
		_draw_speaker(Vector2(960.0 + sign_side * 466.0, 788.0), color)
	# Fine dust / stars: deterministic placement, very slow breathing.
	for i: int in range(62):
		var x: float = fmod(float(i * 137 + 73), 1790.0) + 65.0
		var y: float = fmod(float(i * 79 + 29), 650.0) + 178.0
		if x > 560.0 and x < 1360.0:
			continue
		var alpha: float = 0.10 + 0.08 * sin(t * 0.8 + float(i))
		draw_circle(Vector2(x, y), 1.0 if i % 5 != 0 else 1.7, Color(0.58, 0.72, 1.0, alpha))
	# Ground grid fading into the arena.
	for i: int in range(13):
		var x: float = float(i) * 160.0
		draw_line(Vector2(960.0 + (x - 960.0) * 0.4, 804.0), Vector2(x, 1080.0), Color(0.29, 0.33, 0.60, 0.065), 1.0, true)
	for i: int in range(6):
		var y: float = 832.0 + float(i * i) * 9.3
		draw_line(Vector2(0.0, y), Vector2(1920.0, y), Color(0.35, 0.33, 0.65, 0.06), 1.0, true)

func _draw_speaker(origin: Vector2, color: Color) -> void:
	var box := Rect2(origin - Vector2(30.0, 105.0), Vector2(60.0, 105.0))
	draw_rect(box, Color("080c1b"))
	draw_rect(box, Color("262940"), false, 1.0)
	for i: int in range(2):
		var center: Vector2 = origin - Vector2(0.0, 29.0 + float(i) * 46.0)
		draw_circle(center, 18.0, Color("101628"))
		draw_arc(center, 16.0, 0.0, TAU, 32, _a(color, 0.15), 1.0, true)
		draw_circle(center, 6.0, Color("20273e"))

func _draw_runway(t: float) -> void:
	# The runway is built in layers: floating rim, asphalt glass and inner rails.
	_poly([Vector2(866.0, 182.0), Vector2(1054.0, 182.0), Vector2(1262.0, 953.0), Vector2(658.0, 953.0)], Color("060815"))
	_poly([Vector2(872.0, TOP_Y), Vector2(1048.0, TOP_Y), Vector2(1230.0, 915.0), Vector2(690.0, 915.0)], Color("15172d"))
	_poly([Vector2(875.0, TOP_Y), Vector2(960.0, TOP_Y), Vector2(960.0, 915.0), Vector2(697.0, 915.0)], Color("0d1b2a"))
	_poly([Vector2(960.0, TOP_Y), Vector2(1045.0, TOP_Y), Vector2(1223.0, 915.0), Vector2(960.0, 915.0)], Color("211328"))
	for lane: int in range(2):
		var color: Color = cyan if lane == 0 else pink
		var x_top: float = 874.0 if lane == 0 else 1046.0
		var x_bottom: float = 698.0 if lane == 0 else 1222.0
		_glow(Vector2(x_top, TOP_Y), Vector2(x_bottom, 917.0), color, 2.0)
		# Horizontal seam marks drift gently towards the judgment line.
		for i: int in range(10):
			var p: float = fposmod(float(i) / 10.0 + t * 0.04, 1.0)
			p *= p
			var y: float = lerpf(TOP_Y, HIT_Y, p)
			var half: float = _lane_width(p) * 0.46
			var x: float = _lane_x(lane, p)
			draw_line(Vector2(x - half, y), Vector2(x + half, y), _a(color, 0.035 + p * 0.045), 1.0, true)
		var pressed: Array = state.get("pressed", [false, false])
		if pressed.size() > lane and bool(pressed[lane]):
			_poly([Vector2(_lane_x(lane, 0.4) - _lane_width(0.4) * 0.48, 462.0), Vector2(_lane_x(lane, 0.4) + _lane_width(0.4) * 0.48, 462.0), Vector2(_lane_x(lane, 1.0) + 120.0, HIT_Y), Vector2(_lane_x(lane, 1.0) - 120.0, HIT_Y)], _a(color, 0.08))
		var center := Vector2(_lane_x(lane, 1.0), HIT_Y)
		draw_circle(center, 37.0, _a(color, 0.025))
		draw_arc(center, 30.0, 0.0, TAU, 48, _a(color, 0.12), 1.0, true)
		draw_arc(center, 23.0, 0.0, TAU, 40, _a(color, 0.24), 1.0, true)
		_glow(Vector2(center.x - 121.0, HIT_Y), Vector2(center.x + 121.0, HIT_Y), color, 4.0)
		_poly([Vector2(center.x - 7.0, 927.0), Vector2(center.x, 933.0), Vector2(center.x + 7.0, 927.0), Vector2(center.x, 921.0)], _a(color, 0.45))
	_glow(Vector2(960.0, TOP_Y), Vector2(960.0, 915.0), Color("606589"), 1.0)
	# A black horizon cap makes distant notes emerge cleanly.
	draw_line(Vector2(873.0, TOP_Y), Vector2(1047.0, TOP_Y), Color("323753"), 2.0, true)

func _draw_notes() -> void:
	var now: float = float(state.get("song_time", 0.0))
	var notes: Array = state.get("notes", [])
	for entry: Variant in notes:
		var note: Dictionary = entry
		if bool(note.get("hit", false)) or bool(note.get("missed", false)):
			continue
		var dt: float = float(note.get("time", 0.0)) - now
		if dt > TRAVEL or dt < -0.16:
			continue
		var lane: int = int(note.get("lane", 0))
		var p: float = 1.0 - dt / TRAVEL
		var y: float = lerpf(TOP_Y, HIT_Y, p)
		var x: float = _lane_x(lane, p)
		var w: float = _lane_width(p) * 0.84
		var h: float = lerpf(10.0, 23.0, p)
		var col: Color = cyan if lane == 0 else pink
		_poly([Vector2(x - w * 0.46, y - h * 2.3), Vector2(x + w * 0.46, y - h * 2.3), Vector2(x + w * 0.5, y), Vector2(x - w * 0.5, y)], _a(col, 0.045))
		draw_line(Vector2(x - w * 0.44, y + 3.0), Vector2(x + w * 0.44, y + 3.0), _a(col, 0.11), h + 12.0, true)
		var corners: Array[Vector2] = [Vector2(x - w * 0.5 + 8.0, y - h * 0.5), Vector2(x + w * 0.5 - 8.0, y - h * 0.5), Vector2(x + w * 0.5, y), Vector2(x + w * 0.5 - 7.0, y + h * 0.5), Vector2(x - w * 0.5 + 7.0, y + h * 0.5), Vector2(x - w * 0.5, y)]
		_poly(corners, col.darkened(0.18))
		draw_line(Vector2(x - w * 0.5 + 9.0, y - h * 0.38), Vector2(x + w * 0.5 - 9.0, y - h * 0.38), col.lightened(0.65), maxf(2.0, h * 0.22), true)
		draw_line(Vector2(x - w * 0.36, y + h * 0.27), Vector2(x + w * 0.36, y + h * 0.27), col.darkened(0.5), 2.0, true)
		_poly([Vector2(x - 6.0, y), Vector2(x, y - 4.0), Vector2(x + 6.0, y), Vector2(x, y + 4.0)], Color("ffffff"))

func _draw_impacts() -> void:
	var effects: Array = state.get("effects", [])
	for entry: Variant in effects:
		var effect: Dictionary = entry
		var age: float = float(effect.get("age", 0.0))
		if age > 0.55:
			continue
		var lane: int = int(effect.get("lane", 0))
		var col: Color = cyan if lane == 0 else pink
		if str(effect.get("quality", "")) == "MISS":
			col = Color("ff626e")
		var alpha: float = clampf(1.0 - age / 0.55, 0.0, 1.0)
		var center := Vector2(_lane_x(lane, 1.0), HIT_Y)
		draw_circle(center, 32.0 + age * 130.0, _a(col, alpha * 0.045))
		draw_arc(center, 16.0 + age * 165.0, 0.0, TAU, 64, _a(col, alpha * 0.7), 2.0, true)
		draw_arc(center, 11.0 + age * 110.0, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, alpha * 0.45), 1.0, true)
		for i: int in range(8):
			var angle: float = float(i) * TAU / 8.0 + 0.2
			var direction := Vector2(cos(angle), sin(angle))
			var pos: Vector2 = center + direction * (22.0 + age * 240.0)
			draw_line(pos, pos + direction * 11.0 * alpha, _a(col, alpha * 0.8), 2.0, true)

func _draw_foreground(t: float, gameplay: bool) -> void:
	# Low-level audience lights and dark silhouettes frame the stage, never the UI.
	for side: int in range(2):
		var color: Color = cyan if side == 0 else pink
		for i: int in range(18):
			var x: float = 43.0 + float(i) * 34.0 if side == 0 else 1295.0 + float(i) * 34.0
			var y: float = 967.0 + float((i * 13) % 29)
			var bob: float = sin(t * 1.6 + float(i) * 1.8) * 2.0
			draw_circle(Vector2(x, y + 7.0), 8.0, Color("080b1b"))
			draw_line(Vector2(x - 7.0, y + 30.0), Vector2(x + 7.0, y + 30.0), Color("080b1b"), 21.0)
			if i % 3 != 1:
				var a := Vector2(x + 9.0, y - 11.0 + bob)
				var b := Vector2(x + 12.0, y - 22.0 + bob)
				_glow(a, b, _a(color, 0.4), 2.0)
	# Quiet edge accents, leaving the footer area available to shared controls.
	if not gameplay:
		_glow(Vector2(472.0, 875.0), Vector2(530.0, 886.0), cyan, 2.0)
		_glow(Vector2(1390.0, 886.0), Vector2(1448.0, 875.0), pink, 2.0)
