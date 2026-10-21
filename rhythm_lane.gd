## Scalable private lane view. It never owns the audio clock or judgement.
extends Control

var note_lanes: Array[int] = []
var pressed_right: bool = false
var right_binding: String = "K"
var notes: Array[float] = []
var judged: Array[bool] = []
var song_time: float = 0.0
var visual_time: float = 0.0
var approach: float = 1.6
var pressed: bool = false
var hide_notes: bool = false
var running: bool = false
var last_error: float = 0.0
var errors: Array[float] = []
var judgement: String = "READY"
var flash: float = 0.0
var combo: int = 0
var binding: String = "SPACE"
const CYAN: Color = Color("#65e2df")
const GOLD: Color = Color("#ffd18a")
const MUTED: Color = Color("#8293af")

func _process(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 3.0)
	queue_redraw()

func _draw() -> void:
	var center: float = size.x * 0.5
	var top: float = 70.0
	var target: float = size.y * 0.73
	var width: float = minf(340.0, size.x * 0.52)
	draw_style_box(_panel(Color("#0c1629"), 24), Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(center - width * 0.5, top, width, target - top), Color("#101f34"))
	for side: float in [-1.0, 1.0]:
		draw_line(Vector2(center + side * width * 0.5, top), Vector2(center + side * width * 0.5, target + 42.0), Color("#2b425c"), 2.0)
	if not hide_notes:
		for index: int in range(notes.size()):
			if judged.size() > index and judged[index]:
				continue
			var until: float = notes[index] - visual_time
			if until > approach or until < -0.20:
				continue
			var y: float = target - until / approach * (target - top)
			var lane: int = note_lanes[index] if index < note_lanes.size() else 0
			draw_style_box(_panel(CYAN if lane == 0 else GOLD, 7), Rect2(center - width * 0.5 + lane * width * 0.5 + 8.0, y - 8.0, width * 0.5 - 16.0, 16.0))
	if not hide_notes and running:
		var nearest: float = 100.0
		for note: float in notes:
			nearest = minf(nearest, absf(note - visual_time))
		if nearest < 0.07:
			draw_circle(Vector2(center, target), 42.0 + (0.07 - nearest) * 300.0, Color(0.4, 0.9, 0.87, 0.18))
	draw_rect(Rect2(center - width * 0.5 - 12.0, target - 3.0, width + 24.0, 6.0), GOLD if pressed else CYAN)
	draw_style_box(_panel(Color("#304e63") if pressed else Color("#182b43"), 12), Rect2(center - width * 0.5, target + 20.0, width, 52.0))
	draw_line(Vector2(center, top), Vector2(center, target), MUTED, 2.0)
	_center_text(binding + (" ▼" if pressed else " ·") + "    |    " + right_binding + (" ▼" if pressed_right else " ·"), target + 54.0, 23, CYAN)
	_center_text("AUDIO ONLY" if hide_notes else "TWO KEYS / SYNC LAB", 42.0, 21, MUTED)
	_center_text(judgement, size.y * 0.36, 36, GOLD if flash > 0.0 else Color("#e7f0ff"))
	if running or combo > 0:
		_center_text("%03d COMBO" % combo, size.y * 0.43, 23, MUTED)
	if flash > 0.0 and judgement != "MISS":
		_center_text("%+.1f ms" % last_error, size.y * 0.49, 26, CYAN)
	var gauge_y: float = size.y - 54.0
	draw_line(Vector2(center - 180.0, gauge_y), Vector2(center + 180.0, gauge_y), MUTED, 2.0)
	draw_rect(Rect2(center - 48.0, gauge_y - 5.0, 96.0, 10.0), Color(0.4, 0.9, 0.87, 0.16))
	draw_line(Vector2(center, gauge_y - 13.0), Vector2(center, gauge_y + 13.0), CYAN, 2.0)
	for index: int in range(errors.size()):
		var x: float = center + clampf(errors[index], -150.0, 150.0) * 1.2
		draw_line(Vector2(x, gauge_y - 7.0), Vector2(x, gauge_y + 7.0), Color(1.0, 0.82, 0.54, float(index + 1) / float(errors.size())), 2.0)
	_center_text("EARLY  -150 ms                  +150 ms  LATE", size.y - 17.0, 16, MUTED)

func _center_text(value: String, y: float, font_size: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var extent: Vector2 = font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, Vector2((size.x - extent.x) * 0.5, y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _panel(color: Color, radius: int) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	return box
