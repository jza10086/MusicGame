extends "res://skins/stage_canvas.gd"
## A hand-drawn, resolution-independent nocturnal sculpture garden.
## All visual timing comes from the shared game state; no independent clock.
@export var ink: Color = Color("091e24")
@export var lagoon: Color = Color("17464a")
@export var sage: Color = Color("97b8a5")
@export var pearl: Color = Color("f3eed8")
@export var gold: Color = Color("d7c88e")

var state: Dictionary = {}
const JUDGE_Y: float = 870.0
const LANE_X: Array[float] = [830.0, 1090.0]

func set_state(data: Dictionary) -> void:
	state = data
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	_begin_environment()
	var t: float = float(state.get("time", 0.0))
	var mode: String = str(state.get("mode", "menu"))
	draw_rect(Rect2(0, 0, 1920, 1080), ink)
	_background(t)
	_sculptures(t)
	_fireflies(t)
	if mode == "playing" or mode == "paused":
		_begin_playfield()
		_runway(t)
		_notes()
		_impacts()
	_begin_environment()
	_foreground(t)
	draw_set_transform(Vector2.ZERO)

func _alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

func _ellipse(center: Vector2, radii: Vector2, color: Color, filled: bool = true, width: float = 1.0, rotation: float = 0.0) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(97):
		var a: float = float(i) / 96.0 * TAU
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(rotation))
	if filled:
		draw_colored_polygon(points, color)
	else:
		draw_polyline(points, color, width, true)

func _glow(center: Vector2, radius: float, color: Color, intensity: float = 0.1) -> void:
	for i in range(20, 0, -1):
		var f: float = float(i) / 20.0
		draw_circle(center, radius * f, _alpha(color, intensity * pow(1.0 - f, 2.0)), true, -1.0, true)

func _arc_ellipse(center: Vector2, radii: Vector2, begin: float, end: float, col: Color, width: float = 1.0, rotation: float = 0.0) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(81):
		var a: float = lerpf(begin, end, float(i) / 80.0)
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(rotation))
	draw_polyline(points, col, width, true)

func _background(t: float) -> void:
	# Fine bands of color, rather than a flat fill, preserve quiet space for UI.
	for i in range(42):
		var f: float = float(i) / 42.0
		var y: float = 1080.0 * f
		draw_rect(Rect2(0, y, 1920, 27), ink.lerp(lagoon, 0.26 * sin(f * PI)))
	_glow(Vector2(130, 650), 590.0, sage, 0.026)
	_glow(Vector2(1740, 380), 600.0, Color("648d79"), 0.025)
	_glow(Vector2(980, 1040), 650.0, lagoon, 0.055)
	# Long, quiet topographical contours wrap the negative space.
	for j in range(11):
		var pts: PackedVector2Array = PackedVector2Array()
		for i in range(100):
			var x: float = -40.0 + float(i) * 20.4
			var y: float = 880.0 + float(j) * 16.0 + 57.0 * sin(x / 490.0 + float(j) * 0.08)
			pts.append(Vector2(x, y))
		draw_polyline(pts, _alpha(sage, 0.018 + float(j) * 0.002), 1.0, true)
	# Almost invisible paper-grain grid made from deterministic fine points.
	for i in range(230):
		var x: float = fmod(float(i * 173 + 67), 1920.0)
		var y: float = fmod(float(i * 271 + 41), 1080.0)
		draw_circle(Vector2(x, y), 0.6, _alpha(pearl, 0.035), true, -1.0, true)
	# The moon floats just above the left monolith.
	var moon: Vector2 = Vector2(430, 250 + 5 * sin(t * 0.16))
	_glow(moon, 168, gold, 0.045)
	draw_circle(moon, 49, _alpha(gold, 0.10), true, -1, true)
	draw_circle(moon, 36, pearl.lerp(sage, 0.18), true, -1, true)
	draw_circle(moon + Vector2(14, -10), 33, ink.lerp(lagoon, 0.21), true, -1, true)
	_arc_ellipse(moon, Vector2(61, 61), -0.6, 2.5, _alpha(gold, 0.20), 1)
	draw_circle(moon + Vector2(-59, 14), 2, gold, true, -1, true)

func _sculptures(t: float) -> void:
	# Suspended left torus, with its back half laid behind a fluted stone.
	var left: Vector2 = Vector2(315, 613 + sin(t * 0.29) * 8)
	_ellipse(left + Vector2(0, 286), Vector2(185, 24), _alpha(Color.BLACK, 0.12))
	_arc_ellipse(left, Vector2(225, 90), PI, TAU, _alpha(sage, 0.23), 1.5, -0.52)
	# Sculptural pebble's silhouette and carved, latitude-like curves.
	_ellipse(left, Vector2(117, 191), Color("244c4d"), true, 1, 0.13)
	for i in range(20, 0, -1):
		var f: float = float(i) / 20.0
		_ellipse(left + Vector2(-22, -24) * (1.0 - f), Vector2(112, 186) * f, _alpha(sage, 0.014), true, 1, 0.13)
	for i in range(19):
		var f: float = (float(i) - 9.0) / 10.0
		var y: float = f * 180.0
		var w: float = sqrt(maxf(0.0, 1.0 - f * f)) * 114.0
		_arc_ellipse(left + Vector2(0, y), Vector2(w, 26 * (1.0 - absf(f))), 0.04, PI - 0.04, _alpha(sage, 0.08 + 0.03 * (1.0 - f)), 1.0, 0.13)
	_arc_ellipse(left, Vector2(225, 90), 0, PI, _alpha(gold, 0.65), 1.6, -0.52)
	_arc_ellipse(left, Vector2(235, 98), 0.1, 2.7, _alpha(sage, 0.13), 1.0, -0.52)
	var bead_angle: float = t * 0.19 + 1.7
	var bead: Vector2 = left + Vector2(cos(bead_angle) * 225, sin(bead_angle) * 90).rotated(-0.52)
	_glow(bead, 25, pearl, 0.09)
	draw_circle(bead, 4.2, pearl, true, -1, true)
	# Right mobile: a crescent stone and suspended opal nested inside fine orbits.
	var right: Vector2 = Vector2(1607, 468 + cos(t * 0.23) * 10)
	_ellipse(right, Vector2(211, 247), _alpha(sage, 0.08), false, 1.0, 0.28)
	_arc_ellipse(right, Vector2(197, 231), -1.6, 1.4, _alpha(gold, 0.22), 1.0, 0.28)
	_ellipse(right + Vector2(0, 363), Vector2(158, 20), _alpha(Color.BLACK, 0.10))
	var crescent: PackedVector2Array = PackedVector2Array()
	for i in range(65):
		var a: float = lerpf(-PI / 2.0, PI / 2.0, float(i) / 64)
		crescent.append(right + Vector2(cos(a) * 133, sin(a) * 179).rotated(0.23))
	for i in range(1, 64):
		var a: float = lerpf(PI / 2.0, -PI / 2.0, float(i) / 64)
		crescent.append(right + Vector2(cos(a) * 69, sin(a) * 179).rotated(0.23))
	draw_colored_polygon(crescent, Color("6b8d80"))
	for j in range(6):
		_arc_ellipse(right, Vector2(105 + j * 4, 169 + j * 1.6), -1.35, 1.35, _alpha(pearl, 0.045), 1.0, 0.23)
	var opal: Vector2 = right + Vector2(-39, -18)
	_glow(opal, 105, sage, 0.058)
	draw_circle(opal, 46, Color("9fb9a7"), true, -1, true)
	for i in range(18, 0, -1):
		var f: float = float(i) / 18
		draw_circle(opal + Vector2(-9, -10) * (1 - f), f * 44, _alpha(pearl, 0.037), true, -1, true)
	_arc_ellipse(opal, Vector2(57, 57), -2.6, -0.7, _alpha(pearl, 0.27), 1)
	var pendant: Vector2 = right + Vector2(-44, 229)
	draw_line(right + Vector2(-44, 190), pendant + Vector2(0, 54), _alpha(gold, 0.28), 1, true)
	_ellipse(pendant, Vector2(9, 19), gold.lerp(sage, 0.4))
	draw_circle(right + Vector2(49, -231), 3.2, sage, true, -1, true)

func _fireflies(t: float) -> void:
	for i in range(42):
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var x: float = 960.0 + side * (490.0 + fmod(float(i * 97), 450.0))
		var y: float = fmod(float(i * 71) + t * (3.0 + float(i % 4)), 800.0) + 130
		var pt: Vector2 = Vector2(x + sin(t * 0.4 + i) * 13, y)
		var a: float = 0.12 + 0.18 * (0.5 + 0.5 * sin(t * 0.75 + i * 2.7))
		if i % 7 == 0:
			_glow(pt, 19, gold, a * 0.13)
		draw_circle(pt, 1.0 + float(i % 3) * 0.45, _alpha(gold, a), true, -1, true)

func _runway(t: float) -> void:
	# Two columns of luminous silk descend into an elliptical reflecting pool.
	for lane in range(2):
		var x: float = LANE_X[lane]
		for j in range(24):
			var f: float = float(j) / 24
			var a: float = 0.022 + f * 0.07
			draw_rect(Rect2(x - 88, 180 + j * 29, 176, 30), _alpha(sage, a))
		draw_line(Vector2(x - 89, 190), Vector2(x - 89, 908), _alpha(sage, 0.22), 1, true)
		draw_line(Vector2(x + 89, 190), Vector2(x + 89, 908), _alpha(sage, 0.22), 1, true)
		for j in range(11):
			var y: float = 227 + j * 60
			draw_line(Vector2(x - 93, y), Vector2(x - 86, y), _alpha(sage, 0.20), 1, true)
			draw_line(Vector2(x + 86, y), Vector2(x + 93, y), _alpha(sage, 0.20), 1, true)
		var pressed: Array = state.get("pressed", [false, false])
		var down: bool = lane < pressed.size() and bool(pressed[lane])
		_glow(Vector2(x, JUDGE_Y), 114, sage, 0.085 if down else 0.033)
		_ellipse(Vector2(x, JUDGE_Y), Vector2(80, 27), _alpha(sage, 0.1 if down else 0.035))
		_ellipse(Vector2(x, JUDGE_Y), Vector2(80, 27), _alpha(pearl, 0.92 if down else 0.53), false, 2 if down else 1)
		_ellipse(Vector2(x, JUDGE_Y), Vector2(88, 32), _alpha(gold, 0.26), false, 1)
		draw_line(Vector2(x - 60, JUDGE_Y), Vector2(x + 60, JUDGE_Y), _alpha(pearl, 0.8), 2, true)
		draw_circle(Vector2(x, JUDGE_Y), 4 if down else 2.5, pearl, true, -1, true)
		for s in [-1, 1]:
			var p: Vector2 = Vector2(x + s * 101, JUDGE_Y)
			draw_colored_polygon(PackedVector2Array([p + Vector2(0,-4),p + Vector2(3,0),p + Vector2(0,4),p + Vector2(-3,0)]), _alpha(gold,0.65))
	_ellipse(Vector2(960, 939), Vector2(350, 20), _alpha(sage, 0.055), false, 1)
	_ellipse(Vector2(960, 939), Vector2(300 + sin(t * 0.6) * 6, 13), _alpha(sage, 0.035), false, 1)

func _notes() -> void:
	var song_time: float = float(state.get("song_time", 0.0))
	var notes: Array = state.get("notes", [])
	for entry in notes:
		var note: Dictionary = entry
		if bool(note.get("hit", false)) or bool(note.get("missed", false)):
			continue
		var delta: float = float(note.get("time", 0.0)) - song_time
		if delta > 2.2 or delta < -0.22:
			continue
		var lane: int = clampi(int(note.get("lane", 0)), 0, 1)
		var y: float = JUDGE_Y - delta / 2.2 * 680.0
		var x: float = LANE_X[lane]
		var fade: float = clampf((2.2 - delta) / 0.20, 0.0, 1.0)
		var col: Color = pearl if lane == 0 else sage.lightened(0.2)
		for j in range(8):
			var f: float = float(j) / 8
			draw_line(Vector2(x, y - 8 - j * 6), Vector2(x, y - 14 - j * 6), _alpha(col, (1-f)*0.20*fade), 14 * (1-f), true)
		_glow(Vector2(x,y), 62, col, 0.035 * fade)
		_ellipse(Vector2(x, y + 4), Vector2(62, 12), _alpha(ink, 0.6 * fade))
		_ellipse(Vector2(x, y), Vector2(62, 14), _alpha(col, 0.15 * fade))
		_ellipse(Vector2(x, y), Vector2(56, 10), _alpha(col, fade))
		_arc_ellipse(Vector2(x, y), Vector2(49, 7), PI + 0.14, TAU - 0.14, _alpha(Color.WHITE, 0.8 * fade), 1.4)
		draw_circle(Vector2(x - 25, y - 2), 2, _alpha(Color.WHITE, fade), true, -1, true)

func _impacts() -> void:
	var effects: Array = state.get("effects", [])
	for entry in effects:
		var effect: Dictionary = entry
		var age: float = float(effect.get("age", 0.0))
		if age > 0.75 or age < 0:
			continue
		var lane: int = clampi(int(effect.get("lane", 0)), 0, 1)
		var center: Vector2 = Vector2(LANE_X[lane], JUDGE_Y)
		var f: float = clampf(age / 0.75, 0, 1)
		var quality: String = str(effect.get("quality", "perfect")).to_lower()
		var color: Color = gold if quality == "perfect" else sage
		if quality == "miss":
			color = Color("c99183")
		_glow(center, 140 * (1-f), color, 0.14 * (1-f))
		_ellipse(center, Vector2(75 + f * 108, 24 + f * 49), _alpha(color, (1-f) * 0.75), false, 1.6)
		_ellipse(center, Vector2(56 + f * 90, 19 + f * 39), _alpha(pearl, (1-f) * 0.42), false, 1)
		for i in range(9):
			var a: float = float(i) / 9 * TAU
			var pt: Vector2 = center + Vector2(cos(a) * (28 + f * 96), sin(a) * (18 + f * 49) - f * 33)
			draw_circle(pt, (1-f) * 2.7, _alpha(color, (1-f) * 0.8), true, -1, true)

func _foreground(t: float) -> void:
	# Three small floating stones provide depth below the principal sculptures.
	for i in range(3):
		var p: Vector2 = Vector2(1520 + i * 84, 863 + sin(t * 0.32 + i) * 7 + i * 9)
		_ellipse(p, Vector2(14 + i * 4, 8 + i * 3), Color("466d63"), true, 1, -0.3 + i * 0.4)
		_arc_ellipse(p, Vector2(12 + i * 4, 6 + i * 3), PI, TAU, _alpha(sage, 0.34), 1, -0.3 + i * 0.4)
