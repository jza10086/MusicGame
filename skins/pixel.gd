@tool
extends "res://skins/stage_canvas.gd"

## Original pixel-night radio station. All shapes are native, resolution-independent canvas art.
@export var rain_enabled: bool = true
@export_range(0.0, 1.0) var city_glow: float = 0.7
var state: Dictionary = {}
const INK = Color("101c30")
const NIGHT = Color("16283f")
const BLUE = Color("29435b")
const STEEL = Color("526d79")
const CREAM = Color("f6e6b5")
const AMBER = Color("ffc56e")
const CORAL = Color("f17d76")
const MINT = Color("97c8b1")
const TRACK_TOP := 186.0
const NOTE_ENTRY_Y := 216.0
const HIT_Y := 870.0
var font: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = ThemeDB.fallback_font
	queue_redraw()

func set_state(data: Dictionary) -> void:
	state = data
	queue_redraw()

func box(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(x, y, w, h), c)

func txt(s: String, p: Vector2, size_px: int, c: Color) -> void:
	if font == null: font = ThemeDB.fallback_font
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, c)

func pixel_line(points: Array, color: Color, thickness: float = 4.0) -> void:
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, thickness)

func _draw() -> void:
	_begin_environment()
	var t: float = float(state.get("time", 0.0))
	var active: bool = str(state.get("mode", "menu")) in ["playing", "paused"]
	box(0, 0, 1920, 1080, INK)
	# Broad bands preserve the stillness of a hand-built sixteen-colour sky.
	box(0, 130, 1920, 510, NIGHT)
	box(0, 510, 1920, 220, Color("1b3047"))
	box(0, 660, 1920, 340, Color("24394b"))
	for i in range(88):
		var sx: float = float((i * 317 + 101) % 1920)
		var sy: float = float((i * 163 + 51) % 610)
		if sx > 490 and sx < 1430 and sy > 155: continue
		var tw: float = 0.24 + 0.2 * sin(t * 0.7 + i)
		box(sx, sy, 3, 3, Color(0.91, 0.88, 0.73, tw))
	# Stepped moon, with a night-blue bite and a faint block halo.
	box(1648, 178, 100, 100, Color("293e51"))
	box(1636, 190, 124, 76, Color("293e51"))
	box(1663, 190, 65, 73, CREAM.darkened(0.16))
	box(1651, 202, 89, 49, CREAM.darkened(0.16))
	box(1687, 183, 64, 65, NIGHT)
	_skyline(t)
	if rain_enabled:
		for i in range(75):
			var rx: float = float((i * 347 + 53) % 1920)
			var ry: float = fmod(float(i * 113) + t * (44.0 + float(i % 4) * 15.0), 1040.0)
			if rx > 510 and rx < 1410: continue
			box(rx, ry, 2, 13, Color(0.6, 0.76, 0.79, 0.095))
	_station(t)
	if active:
		_begin_playfield()
		_track(t)
		_begin_environment()
	else:
		# The empty central night window is reserved for the song-select overlay.
		box(516, 155, 888, 800, Color(0.055, 0.095, 0.15, 0.91))
		box(516, 155, 888, 3, BLUE)
		box(516, 952, 888, 3, BLUE)
	_radio(t)
	_traveler(t)
	# Foreground platform edge and its sparse amber inlays.
	box(0, 966, 1920, 10, Color("0c1525"))
	box(0, 976, 1920, 4, STEEL.darkened(0.35))
	for i in range(32):
		box(i * 64 + 8, 961, 29, 4, AMBER.darkened(0.5))
	draw_set_transform(Vector2.ZERO)

func _skyline(t: float) -> void:
	for layer in range(2):
		for i in range(21):
			var x: float = float(i * 103 + (layer * 43) - 50)
			var h: float = float(70 + (i * 47 + layer * 97) % 210)
			var y: float = 760 - h + layer * 75
			var color: Color = Color("243a50") if layer == 0 else Color("16293e")
			box(x, y, 84, h + 150, color)
			box(x + 12, y - 12, 51, 12, color)
			if i % 3 == 0:
				box(x + 44, y - 50, 3, 40, color)
				box(x + 31, y - 38, 26, 3, color)
			for row in range(7):
				for col in range(4):
					if (i * 11 + row * 5 + col * 3) % 5 > 1: continue
					var lit: Color = AMBER if (row + i) % 3 == 0 else MINT
					lit.a = city_glow * (0.16 if layer == 0 else 0.32)
					box(x + col * 18 + 8, y + row * 28 + 13, 7, 10, lit)
	# Red aircraft beacon on a sleeping water tower.
	box(310, 418, 83, 74, Color("102036"))
	box(322, 408, 59, 10, Color("102036"))
	box(325, 491, 5, 76, Color("102036"))
	box(377, 491, 5, 76, Color("102036"))
	box(349, 399, 5, 5, CORAL * (0.6 + 0.25 * sin(t * 2.0)))

func _station(t: float) -> void:
	# Old station pillars frame, rather than obscure, the common UI.
	for x in [24, 470, 1434, 1872]:
		box(x, 112, 24, 850, Color("0d1929"))
		box(x + 3, 116, 3, 842, BLUE.darkened(0.35))
		box(x - 7, 902, 38, 62, Color("142234"))
	box(0, 130, 1920, 18, Color("0b1727"))
	box(0, 145, 1920, 4, BLUE)
	for i in range(48):
		box(i * 40, 151, 24, 5, Color("152438"))
	# Rain shelter trim and hanging warm platform lamps.
	for x in [130, 1720]:
		box(x, 150, 3, 94, BLUE)
		box(x - 34, 242, 72, 10, Color("0d1727"))
		box(x - 26, 252, 56, 6, AMBER)
		box(x - 43, 258, 90, 5, Color(1.0, 0.72, 0.36, 0.07))
	# Physical platform railing across the distant sides.
	for x in [55, 1448]:
		box(x, 714, 405, 7, STEEL.darkened(0.5))
		box(x, 797, 405, 5, BLUE)
		for i in range(8): box(x + i * 56, 721, 5, 174, BLUE.darkened(0.2))
	box(54, 899, 400, 60, Color("122238"))
	box(1457, 899, 405, 60, Color("122238"))
	# A few wet tile reflections.
	for i in range(18):
		var x: float = 65 + i * 21
		box(x, 929 + (i % 4) * 6, 11 + i % 5 * 3, 3, Color(0.85, 0.59, 0.36, 0.13))
		box(1470 + i * 21, 922 + (i % 5) * 7, 14, 3, Color(0.51, 0.68, 0.67, 0.12))
	# Antenna wire steps, deliberately orthogonal to retain pixel grammar.
	pixel_line([Vector2(44, 312), Vector2(184, 325), Vector2(320, 325), Vector2(482, 300)], Color("101c2c"), 3)

func _radio(t: float) -> void:
	# A battered shortwave set on a station bench.
	box(107, 849, 290, 17, Color("0b1727"))
	box(125, 866, 12, 76, Color("101b2a"))
	box(367, 866, 12, 76, Color("101b2a"))
	box(165, 757, 8, 47, STEEL)
	box(172, 718, 4, 45, STEEL)
	box(159, 788, 215, 60, Color("091321"))
	box(153, 782, 215, 60, Color("87775d"))
	box(158, 787, 205, 50, Color("b6a07a"))
	box(165, 794, 85, 34, Color("233343"))
	for row in range(5):
		for col in range(13): box(169 + col * 6, 798 + row * 6, 2, 2, Color("728079"))
	box(260, 794, 93, 14, Color("263b43"))
	for i in range(14): box(264 + i * 6, 797, 1, 4 + (3 if i % 3 == 0 else 0), AMBER.darkened(0.28))
	box(295 + sin(t * 0.25) * 5, 794, 2, 14, CORAL)
	box(267, 816, 15, 12, Color("243240"))
	box(327, 814, 22, 16, Color("243240"))
	box(331, 816, 14, 3, STEEL)
	box(292, 820, 5, 4, AMBER)
	# Warm heartbeat as a radio signal, softly moving in the physical display.
	for i in range(22):
		var h: float = 3 + 11 * abs(sin(t * 2.0 + i * 0.71))
		box(181 + i * 7, 916 - h, 3, h, Color(0.96, 0.67, 0.42, 0.30))

func _traveler(t: float) -> void:
	# A scarf, a warm cup, and one last train. Chunk silhouettes are hand-built.
	var bob: float = floor(sin(t * 1.5) + 1.0) * 2.0
	box(1632, 874, 69, 13, Color("0b1524"))
	box(1643, 834, 17, 47, Color("101a2a"))
	box(1675, 834, 16, 47, Color("101a2a"))
	box(1637, 879, 24, 8, Color("77868a"))
	box(1674, 879, 26, 8, Color("77868a"))
	box(1628, 760 + bob, 73, 80, Color("49687a"))
	box(1618, 774 + bob, 15, 52, Color("355468"))
	box(1699, 774 + bob, 14, 48, Color("355468"))
	box(1637, 728 + bob, 51, 40, Color("d6aa87"))
	box(1631, 717 + bob, 61, 23, Color("101a28"))
	box(1625, 730 + bob, 15, 27, Color("101a28"))
	box(1681, 735 + bob, 13, 26, Color("101a28"))
	box(1630, 758 + bob, 66, 12, CORAL.darkened(0.13))
	box(1637, 769 + bob, 14, 44, CORAL.darkened(0.22))
	box(1637, 810 + bob, 14, 4, AMBER.darkened(0.2))
	box(1682, 787 + bob, 20, 17, CREAM)
	box(1702, 790 + bob, 6, 10, CREAM.darkened(0.14))
	box(1687, 785 + bob, 11, 3, Color("9b6651"))
	for i in range(3):
		var sy: float = 780 - fmod(t * 12 + i * 10, 33)
		box(1686 + i % 2 * 5, sy, 3, 6, Color(0.94, 0.89, 0.73, 0.16))
	# Ginger station cat, including a curling stepped tail.
	box(1772, 868, 35, 22, Color("b28163"))
	box(1769, 855, 25, 22, Color("d5a379"))
	box(1769, 850, 7, 10, Color("d5a379"))
	box(1787, 850, 7, 10, Color("d5a379"))
	box(1773, 862, 3, 3, INK)
	box(1784, 862, 3, 3, INK)
	box(1770, 887, 13, 4, CREAM.darkened(0.3))
	box(1794, 887, 13, 4, CREAM.darkened(0.3))
	pixel_line([Vector2(1804, 885), Vector2(1816, 885), Vector2(1816, 870), Vector2(1823, 870)], Color("b28163"), 6)

func _track(t: float) -> void:
	box(653, TRACK_TOP, 614, 948 - TRACK_TOP, Color("091523"))
	box(647, TRACK_TOP, 6, 948 - TRACK_TOP, STEEL.darkened(0.35))
	box(1267, TRACK_TOP, 6, 948 - TRACK_TOP, STEEL.darkened(0.35))
	box(653, TRACK_TOP, 614, 5, AMBER.darkened(0.46))
	box(676, 190, 568, 713, Color("14263a"))
	box(957, 190, 6, 713, Color("30475b"))
	for lane in range(2):
		var x: float = 830.0 + lane * 260.0
		var accent: Color = AMBER if lane == 0 else CORAL
		box(x - 112, 191, 224, 713, Color(0.2, 0.31, 0.4, 0.14))
		for k in range(29):
			box(x - 120, 197 + k * 24, 3, 10, accent.darkened(0.71))
			box(x + 117, 197 + k * 24, 3, 10, accent.darkened(0.71))
		for k in range(8):
			var yy: float = NOTE_ENTRY_Y + fposmod(k * 95.0 + float(state.get("song_time", 0.0)) * ((HIT_Y - NOTE_ENTRY_Y) / 2.2), HIT_Y - NOTE_ENTRY_Y)
			box(x - 110, yy, 220, 2, Color(0.6, 0.72, 0.77, 0.055))
		var pressed: Array = state.get("pressed", [false, false])
		var held: bool = lane < pressed.size() and bool(pressed[lane])
		box(x - 107, 851, 214, 40, accent.darkened(0.75 if not held else 0.46))
		box(x - 111, 867, 222, 6, accent)
		box(x - 111, 851, 4, 39, accent)
		box(x + 107, 851, 4, 39, accent)
	for note in state.get("notes", []):
		if bool(note.get("hit", false)) or bool(note.get("missed", false)): continue
		var delta: float = float(note.get("time", 0.0)) - float(state.get("song_time", 0.0))
		if delta < -0.18 or delta > 2.2: continue
		var lane: int = int(note.get("lane", 0))
		var x: float = 830.0 + lane * 260.0
		var y: float = HIT_Y - delta / 2.2 * (HIT_Y - NOTE_ENTRY_Y)
		var accent: Color = AMBER if lane == 0 else CORAL
		box(x - 94, y - 11, 188, 30, Color("081221"))
		box(x - 100, y - 17, 200, 28, accent.darkened(0.46))
		box(x - 94, y - 22, 188, 28, accent)
		box(x - 94, y - 22, 188, 5, CREAM)
		box(x - 88, y - 10, 26, 9, accent.darkened(0.33))
		box(x + 62, y - 10, 26, 9, accent.darkened(0.33))
		if lane == 0:
			pixel_line([Vector2(x - 28, y - 6), Vector2(x - 13, y - 6), Vector2(x - 6, y - 16), Vector2(x + 3, y + 0), Vector2(x + 12, y - 9), Vector2(x + 27, y - 9)], INK, 3)
		else:
			for n in range(3): box(x - 19 + n * 16, y - 15, 7, 14, INK)
	for effect in state.get("effects", []):
		var age: float = float(effect.get("age", 0.0))
		if age < 0 or age > 0.55: continue
		var lane: int = int(effect.get("lane", 0))
		var x: float = 830.0 + lane * 260.0
		var accent: Color = AMBER if lane == 0 else CORAL
		accent.a = maxf(0.0, 1.0 - age / 0.55)
		var spread: float = age * 145.0
		box(x - 113 - spread, 866 - spread * 0.18, 18, 5, accent)
		box(x + 95 + spread, 866 - spread * 0.18, 18, 5, accent)
		for p in range(9):
			var dx: float = (p - 4) * (14 + age * 40)
			var dy: float = age * (85 + (p * 37) % 91)
			box(x + dx, 850 - dy, 5, 5, accent)
	# Radio meters form the track's narrow side rails.
	for side in range(2):
		for i in range(31):
			var lit: bool = sin(t * 2.4 + i * 0.38) > 0.0
			box(659 + side * 594, 208 + i * 21, 8, 7, (AMBER if side == 0 else CORAL).darkened(0.45 if lit else 0.85))
