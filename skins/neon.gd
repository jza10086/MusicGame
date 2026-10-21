extends "res://skins/stage_canvas.gd"
## A compact two-key runway with crisp crystal impacts and restrained bloom. Visuals only.
@export var cyan: Color = Color("74f5ff")
@export var pink: Color = Color("d9a0ff")
@export var stage_ink: Color = Color("080e2b")
const DESIGN: Vector2 = Vector2(1920.0, 1080.0)
const TOP_Y: float = 125.0
const HIT_Y: float = 880.0
const FAR_LANE_WIDTH: float = 45.0
const NEAR_LANE_WIDTH: float = 340.0
const DEPTH_RATIO: float = NEAR_LANE_WIDTH / FAR_LANE_WIDTH
const IMPACT_DURATION: float = 0.30
const CONSUME_DURATION: float = 0.105
var state: Dictionary = {}
var travel: float = 1.6
var _hit_light: Node2D
var _light_texture: GradientTexture2D
var _beam_texture: ImageTexture
var _sheet_texture: ImageTexture
var _runway_edges: ArrayMesh

func set_state(data: Dictionary) -> void:
	state = data
	travel = float(data.get("approach", 1.6))
	queue_redraw()
	if is_instance_valid(_hit_light):
		_hit_light.queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gradient: Gradient = Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.38, 0.68, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.72), Color(1, 1, 1, 0.27), Color(1, 1, 1, 0.035), Color(1, 1, 1, 0)])
	_light_texture = GradientTexture2D.new()
	_light_texture.width = 256
	_light_texture.height = 256
	_light_texture.fill = GradientTexture2D.FILL_RADIAL
	_light_texture.fill_from = Vector2(0.5, 0.5)
	_light_texture.fill_to = Vector2(1.0, 0.5)
	_light_texture.gradient = gradient
	# Floating-point alpha avoids visible bands in the broad, low-opacity gradients.
	_beam_texture = _make_lane_gradient()
	_sheet_texture = _make_soft_surface()
	_runway_edges = _make_runway_edges()
	_hit_light = Node2D.new()
	_hit_light.name = "HitLight"
	var light_material: CanvasItemMaterial = CanvasItemMaterial.new()
	light_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_hit_light.material = light_material
	_hit_light.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_hit_light.draw.connect(_draw_hit_light)
	add_child(_hit_light)

## One-dimensional half-float gradient, constant across the entire lane width.
## The judgement line is the brightest point; the foreground remains filled to the road end.
func _make_lane_gradient() -> ImageTexture:
	var pixels: Image = Image.create(2, 1024, false, Image.FORMAT_RGBAH)
	for row: int in range(1024):
		var progress: float = float(row) / 1023.0 * 1.40
		var alpha: float = smoothstep(0.0, 1.0, progress)
		for column: int in range(2):
			pixels.set_pixel(column, row, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(pixels)

## Full-width lane fill below notes, with no lateral blur or additive brightness stacking.
func _draw_lane_highlights() -> void:
	var pressed: Array = state.get("pressed", [false, false])
	var uv: PackedVector2Array = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	for lane: int in range(2):
		var opacity: float = 0.20 if pressed.size() > lane and bool(pressed[lane]) else 0.0
		for effect: Dictionary in state.get("effects", []):
			var age: float = float(effect.get("age", 0.0))
			if int(effect.get("lane", 0)) != lane or age < 0.0 or age >= 0.25 or hit_note_geometry(effect).is_empty():
				continue
			var quality: String = str(effect.get("quality", ""))
			var strength: float = 1.0 if quality == "PERFECT" else (0.82 if quality == "GOOD" else 0.62)
			opacity = maxf(opacity, (1.0 - smoothstep(0.035, 0.25, age)) * strength * 0.28)
		if opacity > 0.004:
			# V depends only on screen depth, so both triangles interpolate the same gradient.
			draw_polygon(_lane_quad(lane, 0.0, 1.40), PackedColorArray([_a(cyan if lane == 0 else pink, opacity)]), uv, _beam_texture)

## Small impact floor sheet; its feathering does not affect the lane highlight.
func _make_soft_surface() -> ImageTexture:
	var pixels: Image = Image.create(96, 192, false, Image.FORMAT_RGBAH)
	for y: int in range(192):
		var v: float = float(y) / 191.0
		var longitudinal: float = sin(PI * v) * sin(PI * v)
		for x: int in range(96):
			var u: float = float(x) / 95.0
			var edge: float = smoothstep(0.0, 0.14, u) * (1.0 - smoothstep(0.86, 1.0, u))
			pixels.set_pixel(x, y, Color(1, 1, 1, longitudinal * edge))
	return ImageTexture.create_from_image(pixels)

func _a(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, alpha)

func _poly(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)

func playfield_transform() -> Transform2D:
	var factor: float = minf(size.x / DESIGN.x, size.y / DESIGN.y) * 1.10
	return Transform2D(0.0, Vector2.ONE * factor, 0.0, (size - DESIGN * factor) * 0.5)

func _lane_width(progress: float) -> float:
	return lerpf(FAR_LANE_WIDTH, NEAR_LANE_WIDTH, progress)

func _lane_x(lane: int, progress: float) -> float:
	return 960.0 + (-0.5 if lane == 0 else 0.5) * _lane_width(progress)

func _lane_point(lane: int, across: float, progress: float) -> Vector2:
	return Vector2(_lane_x(lane, progress) + across * _lane_width(progress) * 0.5, lerpf(TOP_Y, HIT_Y, progress))

func _lane_quad(lane: int, far_progress: float, near_progress: float, spread: float = 1.0) -> PackedVector2Array:
	return PackedVector2Array([_lane_point(lane, -spread, far_progress), _lane_point(lane, spread, far_progress), _lane_point(lane, spread, near_progress), _lane_point(lane, -spread, near_progress)])

## Hit testing follows the widened runway at every aspect ratio; keyboard mappings are independent.
func lane_at_position(point: Vector2, mouse: bool = false) -> int:
	var local: Vector2 = playfield_transform().affine_inverse() * point
	if local.y < (HIT_Y - 115.0 if mouse else TOP_Y + 80.0) or local.y > HIT_Y + 80.0:
		return -1
	var progress: float = (local.y - TOP_Y) / (HIT_Y - TOP_Y)
	if absf(local.x - 960.0) > _lane_width(progress):
		return -1
	return 0 if local.x < 960.0 else 1

func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	_begin_environment()
	_draw_arena(float(state.get("time", 0.0)))
	if str(state.get("mode", "menu")) in ["playing", "paused"]:
		_begin_playfield()
		_draw_runway()
		_draw_notes()
		_draw_impacts()
	draw_set_transform(Vector2.ZERO)

func _draw_arena(time: float) -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN), stage_ink)
	draw_polygon(PackedVector2Array([Vector2(0, 320), Vector2(1920, 320), Vector2(1920, 1080), Vector2(0, 1080)]), PackedColorArray([Color(0.12, 0.06, 0.27, 0), Color(0.12, 0.06, 0.27, 0), Color(0.23, 0.08, 0.38, 0.75), Color(0.10, 0.13, 0.34, 0.75)]))
	draw_texture_rect(_light_texture, Rect2(0, 300, 1150, 850), false, Color(0.04, 0.31, 0.53, 0.48))
	draw_texture_rect(_light_texture, Rect2(850, 400, 1150, 800), false, Color(0.36, 0.10, 0.53, 0.45))
	# Low-contrast floating glass panels keep the centre readable without copied artwork.
	for side: int in range(2):
		var color: Color = cyan if side == 0 else pink
		for panel: int in range(3):
			var x: float = 105.0 + float(panel) * 160.0 if side == 0 else 1340.0 + float(panel) * 160.0
			var y: float = 250.0 + float((panel * 97 + side * 73) % 220) + sin(time * 0.3 + float(panel)) * 5.0
			var frame: PackedVector2Array = PackedVector2Array([Vector2(x, y + 12), Vector2(x + 205, y), Vector2(x + 205, y + 155), Vector2(x, y + 167)])
			draw_colored_polygon(frame, _a(color, 0.018))
			draw_line(frame[0], frame[1], _a(color, 0.10), 1.0, true)
			draw_line(frame[1], frame[2], _a(color, 0.06), 1.0, true)
			for bar: int in range(12):
				var height: float = 8.0 + 55.0 * (0.5 + 0.5 * sin(float(bar) * 1.7 + time * 0.6 + float(panel)))
				draw_rect(Rect2(x + 13.0 + float(bar) * 15.0, y + 145.0 - height, 5.0, height), _a(color, 0.045))
	for index: int in range(58):
		var point: Vector2 = Vector2(fmod(float(index * 137 + 53), 1850.0) + 35.0, fmod(float(index * 83 + 71), 880.0) + 95.0)
		var alpha: float = 0.07 + 0.06 * sin(time * 0.45 + float(index))
		draw_circle(point, 1.0 if index % 4 else 1.5, Color(0.70, 0.80, 1.0, alpha))

## Shared mesh vertices interpolate alpha continuously along all three runway lines.
## Feathered sides avoid segment caps and preserve thin edges under fractional UI scaling.
func _make_runway_edges() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var offsets: Array[float] = [-1.2, -0.25, 0.25, 1.2]
	for edge: int in range(3):
		# The middle line uses the inner edge of the left lane, exactly x=960.
		var lane: int = 1 if edge == 2 else 0
		var across: float = -1.0 if edge == 0 else 1.0
		var start: Vector2 = _lane_point(lane, across, 0.0)
		var end: Vector2 = _lane_point(lane, across, 1.40)
		var normal: Vector2 = (end - start).normalized().orthogonal()
		var base: int = vertices.size()
		for row: int in range(65):
			var fraction: float = float(row) / 64.0
			var progress: float = fraction * 1.40
			var alpha: float = smoothstep(0.0, 0.30, progress) * (1.0 - smoothstep(1.14, 1.40, progress)) * (0.13 if edge == 1 else 0.40)
			for column: int in range(4):
				var point: Vector2 = start.lerp(end, fraction) + normal * offsets[column] * (0.8 if edge == 1 else 1.0)
				vertices.append(Vector3(point.x, point.y, 0.0))
				colors.append(Color(0.72, 0.79, 1.0, alpha if column == 1 or column == 2 else 0.0))
			if row < 64:
				for column: int in range(3):
					var vertex: int = base + row * 4 + column
					indices.append_array(PackedInt32Array([vertex, vertex + 1, vertex + 5, vertex, vertex + 5, vertex + 4]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _draw_runway() -> void:
	# Both halves meet at exactly x=960: one translucent road, no central black gutter.
	var road: PackedVector2Array = PackedVector2Array([_lane_point(0, -1, 0), _lane_point(1, 1, 0), _lane_point(1, 1, 1.40), _lane_point(0, -1, 1.40)])
	draw_polygon(road, PackedColorArray([Color(0.04, 0.06, 0.15, 0), Color(0.04, 0.06, 0.15, 0), Color(0.035, 0.045, 0.12, 0.72), Color(0.035, 0.045, 0.12, 0.72)]))
	_draw_lane_highlights()
	draw_mesh(_runway_edges, null)
	var left: float = 960.0 - NEAR_LANE_WIDTH
	var right: float = 960.0 + NEAR_LANE_WIDTH
	# One continuous line with a cyan-to-lilac gradient; its centre has no gap.
	draw_polygon(PackedVector2Array([Vector2(left, HIT_Y - 1.3), Vector2(right, HIT_Y - 1.3), Vector2(right, HIT_Y + 1.3), Vector2(left, HIT_Y + 1.3)]), PackedColorArray([_a(cyan, 0.80), _a(pink, 0.80), _a(pink, 0.80), _a(cyan, 0.80)]))
	var apron: PackedVector2Array = PackedVector2Array([_lane_point(0, -1, 1.0), _lane_point(1, 1, 1.0), _lane_point(1, 1, 1.065), _lane_point(0, -1, 1.065)])
	draw_polygon(apron, PackedColorArray([_a(cyan, 0.07), _a(pink, 0.07), _a(pink, 0), _a(cyan, 0)]))

func _draw_notes() -> void:
	var now: float = float(state.get("song_time", 0.0))
	var notes: Array = state.get("notes", [])
	for entry: Variant in notes:
		var note: Dictionary = entry
		if bool(note.get("hit", false)) or bool(note.get("missed", false)):
			continue
		var dt: float = float(note.get("time", 0.0)) - now
		if dt > travel or dt < -0.16:
			continue
		var lane: int = int(note.get("lane", 0))
		var p: float = project_progress(1.0 - dt / travel)
		var position: Vector2 = note_position(lane, dt)
		var y: float = position.y
		var x: float = position.x
		var w: float = _lane_width(p) * 0.84
		var h: float = maxf(7.0, 23.0 * _lane_width(p) / NEAR_LANE_WIDTH)
		var col: Color = cyan if lane == 0 else pink
		draw_texture_rect(_light_texture, Rect2(x - w * 0.56, y - h * 2.0, w * 1.12, h * 4.0), false, _a(col, 0.22))
		_draw_note_body(position, w, h, col)

## Shared silhouette keeps the hit transition attached to the note the player saw.
func _draw_note_body(center: Vector2, width: float, height: float, color: Color, alpha: float = 1.0, flash: float = 0.0) -> void:
	var x: float = center.x
	var y: float = center.y
	var bevel: float = minf(8.0, width * 0.12)
	_poly([Vector2(x - width * 0.5 + bevel, y - height * 0.5), Vector2(x + width * 0.5 - bevel, y - height * 0.5), Vector2(x + width * 0.5, y), Vector2(x + width * 0.5 - bevel, y + height * 0.5), Vector2(x - width * 0.5 + bevel, y + height * 0.5), Vector2(x - width * 0.5, y)], _a(color.lightened(0.35).lerp(Color.WHITE, flash), alpha))
	draw_line(Vector2(x - width * 0.5 + bevel, y - height * 0.38), Vector2(x + width * 0.5 - bevel, y - height * 0.38), _a(color.lightened(0.65), alpha), maxf(1.0, height * 0.22), true)
	draw_line(Vector2(x - width * 0.36, y + height * 0.27), Vector2(x + width * 0.36, y + height * 0.27), _a(color.darkened(0.5), alpha * (1.0 - flash)), 2.0, true)
	_poly([center + Vector2(-6, 0), center + Vector2(0, -height * 0.17), center + Vector2(6, 0), center + Vector2(0, height * 0.17)], _a(Color.WHITE, alpha))

## Snapshot uses the actual input-edge visual time, not compensated judgement error.
## MISS has no consumed sprite; later approach changes cannot move an existing effect.
func hit_note_geometry(effect: Dictionary) -> Dictionary:
	var until: float = float(effect.get("seconds_until", INF))
	if str(effect.get("quality", "")) == "MISS" or not is_finite(until):
		return {}
	var approach: float = float(effect["approach"])
	var projected: float = project_progress(1.0 - until / approach)
	return {"position": Vector2(_lane_x(int(effect["lane"]), projected), lerpf(TOP_Y, HIT_Y, projected)), "width": _lane_width(projected) * 0.84, "height": maxf(7.0, 23.0 * _lane_width(projected) / NEAR_LANE_WIDTH)}

## Pull the original silhouette into the receptor, whiten it, then bury it in the core.
## Uses a frozen visual snapshot only; never delays consumption or samples the audio clock.
func _draw_consumed_note(geometry: Dictionary, lane: int, age: float, color: Color) -> void:
	if age >= CONSUME_DURATION:
		return
	var progress: float = age / CONSUME_DURATION
	var pull: float = pow(progress, 1.35)
	var origin: Vector2 = geometry.position
	var core: Vector2 = Vector2(_lane_x(lane, 1.0), HIT_Y - 3.0)
	var center: Vector2 = origin.lerp(core, pull)
	var width: float = maxf(16.0, float(geometry.width) * pow(1.0 - progress, 1.35))
	var height: float = maxf(1.5, float(geometry.height) * (1.0 - progress * 0.88))
	var opacity: float = 1.0 - smoothstep(0.08, 0.86, progress)
	if opacity > 0.015:
		_draw_note_body(center, width, height, color, opacity, lerpf(0.45, 1.0, progress))

func _draw_impacts() -> void:
	for effect: Dictionary in state.get("effects", []):
		var age: float = float(effect.get("age", 0.0))
		if age < 0.0 or age >= IMPACT_DURATION:
			continue
		var lane: int = int(effect.get("lane", 0))
		if str(effect.get("quality", "")) == "MISS":
			var center: Vector2 = Vector2(_lane_x(lane, 1.0), HIT_Y)
			var alpha: float = maxf(0.0, 1.0 - age / 0.18)
			draw_line(center - Vector2(NEAR_LANE_WIDTH * 0.44, 0), center + Vector2(NEAR_LANE_WIDTH * 0.44, 0), Color(1.0, 0.25, 0.35, alpha * 0.65), 3.0, true)
			continue
		var geometry: Dictionary = hit_note_geometry(effect)
		if not geometry.is_empty():
			_draw_consumed_note(geometry, lane, age, cyan if lane == 0 else pink)

## Soft textured quads replace hard-edged slab faces. UV alpha feathers all four edges.
func _light_surface(points: PackedVector2Array, texture: Texture2D, color: Color, opacity: float) -> void:
	if opacity <= 0.004:
		return
	# Subdivide in depth so affine triangle UVs do not leave a diagonal crease in a wide trapezoid.
	var colors: PackedColorArray = PackedColorArray([_a(color, opacity)])
	for strip: int in range(12):
		var from: float = float(strip) / 12.0
		var to: float = float(strip + 1) / 12.0
		var vertices: PackedVector2Array = PackedVector2Array([points[0].lerp(points[3], from), points[1].lerp(points[2], from), points[1].lerp(points[2], to), points[0].lerp(points[3], to)])
		var uv: PackedVector2Array = PackedVector2Array([Vector2(0, from), Vector2(1, from), Vector2(1, to), Vector2(0, to)])
		_hit_light.draw_polygon(vertices, colors, uv, texture)

func _light_blob(center: Vector2, extent: Vector2, color: Color, opacity: float) -> void:
	if opacity > 0.004:
		_hit_light.draw_texture_rect(_light_texture, Rect2(center - extent * 0.5, extent), false, _a(color, opacity))

## A small diamond on the runway plane, lifted as a separate sheet of light.
## Bright front edges and quiet rear edges keep the shape legible without an opaque slab.
func _draw_crystal_sheet(lane: int, spread: float, depth: float, lift: float, color: Color, opacity: float) -> void:
	if opacity < 0.015:
		return
	var points: PackedVector2Array = PackedVector2Array([
		_lane_point(lane, 0, 1.0 - depth) - Vector2(0, lift),
		_lane_point(lane, spread, 1.0) - Vector2(0, lift),
		_lane_point(lane, 0, 1.0 + depth) - Vector2(0, lift),
		_lane_point(lane, -spread, 1.0) - Vector2(0, lift)])
	_hit_light.draw_polygon(points, PackedColorArray([_a(color, opacity * 0.02), _a(color, opacity * 0.09), _a(color.lightened(0.35), opacity * 0.06), _a(color, opacity * 0.09)]))
	for edge: int in range(4):
		var from: Vector2 = points[edge]
		var to: Vector2 = points[(edge + 1) % 4]
		var front: bool = edge == 1 or edge == 2
		_hit_light.draw_line(from, to, _a(color, opacity * 0.055), 5.0, true)
		_hit_light.draw_line(from, to, _a(color.lightened(0.55), opacity * (0.64 if front else 0.25)), 1.15, true)

## Compact white core -> two defined perspective sheets -> four fading crystal flecks.
## Width scales with the two-key road; low-frequency bloom supports rather than hides the edges.
func _draw_hit_light() -> void:
	if size.x < 1.0 or size.y < 1.0 or str(state.get("mode", "menu")) not in ["playing", "paused"]:
		return
	_hit_light.draw_set_transform_matrix(playfield_transform())
	_light_blob(Vector2(960, HIT_Y), Vector2(NEAR_LANE_WIDTH * 2.1, 12), Color(0.65, 0.75, 1.0), 0.13)
	for effect: Dictionary in state.get("effects", []):
		var age: float = float(effect.get("age", 0.0))
		var quality: String = str(effect.get("quality", ""))
		if age < 0.0 or age >= IMPACT_DURATION or quality == "MISS" or hit_note_geometry(effect).is_empty():
			continue
		var lane: int = int(effect["lane"])
		var col: Color = cyan if lane == 0 else pink
		var center: Vector2 = Vector2(_lane_x(lane, 1.0), HIT_Y - 2.0)
		var strength: float = 1.0 if quality == "PERFECT" else (0.82 if quality == "GOOD" else 0.62)
		var expansion: float = 1.0 - pow(1.0 - clampf(age / 0.14, 0.0, 1.0), 3.0)
		var surface: float = (1.0 - smoothstep(0.035, 0.25, age)) * strength
		var core: float = (1.0 - smoothstep(0.02, 0.135, age)) * strength
		var onset: float = pow(maxf(0.0, 1.0 - age / 0.05), 2.0) * strength
		var floor: PackedVector2Array = _lane_quad(lane, 0.965, 1.035, 0.62)
		_light_surface(floor, _sheet_texture, col, surface * 0.16)
		# Two offset sheets, not concentric circles or a growing full-lane box.
		_draw_crystal_sheet(lane, 0.40 + expansion * 0.23, 0.025 + expansion * 0.018, 0.0, col, surface)
		_draw_crystal_sheet(lane, 0.32 + expansion * 0.18, 0.020 + expansion * 0.013, 12.0 + expansion * 21.0, col, surface * 0.72)
		_light_blob(center, Vector2(NEAR_LANE_WIDTH * 0.62, 65), col, core * 0.27)
		_light_blob(center, Vector2(NEAR_LANE_WIDTH * 0.40, 25), col.lightened(0.45), core * 0.60)
		_light_blob(center, Vector2(NEAR_LANE_WIDTH * 0.24, 12), Color.WHITE, core * 0.95)
		if core > 0.02:
			var radius: float = 18.0 + core * 13.0
			_hit_light.draw_colored_polygon(PackedVector2Array([center - Vector2(radius, 0), center - Vector2(0, 5), center + Vector2(radius, 0), center + Vector2(0, 4)]), _a(Color.WHITE, core * 0.70))
		_light_blob(center, Vector2(NEAR_LANE_WIDTH * 0.62, 5), Color.WHITE, onset * 0.55)
		_light_blob(center - Vector2(0, 5), Vector2(8, 40), Color.WHITE, onset * 0.35)
		var origins: Array[float] = [-0.27, -0.07, 0.14, 0.30]
		for index: int in range(origins.size()):
			var life: float = age / (0.17 + float(index % 3) * 0.035)
			if life >= 0.97:
				continue
			var velocity: Vector2 = Vector2(origins[index] * 130.0, -100.0 - float((index * 47) % 105))
			var pos: Vector2 = center + Vector2(origins[index] * NEAR_LANE_WIDTH, -7) + velocity * age
			var fade: float = pow(1.0 - life, 1.5) * strength
			var radius: float = (2.1 + float(index % 2) * 0.7) * (1.0 - life * 0.4)
			var axis: Vector2 = Vector2(radius, 0).rotated(age * 2.0 + float(index) * 0.6)
			var normal: Vector2 = axis.orthogonal()
			_light_blob(pos, Vector2(10, 10), col, fade * 0.20)
			_hit_light.draw_colored_polygon(PackedVector2Array([pos - axis, pos - normal, pos + axis, pos + normal]), _a(col.lightened(0.65), fade * 0.85))
	_hit_light.draw_set_transform(Vector2.ZERO)

## Constant world-depth speed projected onto the trapezoidal runway.
## p is linear in audio time; division by depth makes screen motion accelerate near us.
func project_progress(progress: float) -> float:
	var depth: float = DEPTH_RATIO - (DEPTH_RATIO - 1.0) * progress
	return progress / maxf(0.05, depth)

func note_position(lane: int, seconds_until: float) -> Vector2:
	var projected: float = project_progress(1.0 - seconds_until / travel)
	return Vector2(_lane_x(lane, projected), TOP_Y + (HIT_Y - TOP_Y) * projected)
