extends Control
## Uniform artwork transforms: scenery covers the viewport; the playfield fits safely.
const ART_SIZE := Vector2(1920.0, 1080.0)
const PLAY_ZOOM := 1.25

func environment_transform() -> Transform2D:
	var factor := maxf(size.x / ART_SIZE.x, size.y / ART_SIZE.y)
	return Transform2D(0.0, Vector2.ONE * factor, 0.0, (size - ART_SIZE * factor) * 0.5)

func playfield_transform() -> Transform2D:
	var factor := minf(size.x / ART_SIZE.x, size.y / ART_SIZE.y) * PLAY_ZOOM
	return Transform2D(0.0, Vector2.ONE * factor, 0.0, (size - ART_SIZE * factor) * 0.5)

func _begin_environment() -> void:
	draw_set_transform_matrix(environment_transform())

func _begin_playfield() -> void:
	draw_set_transform_matrix(playfield_transform())

func lane_at_position(point: Vector2, mouse: bool = false) -> int:
	var local := playfield_transform().affine_inverse() * point
	# Keep HUD, side scenery and pause controls outside the playable hit region.
	if local.y < (800.0 if mouse else 330.0) or local.y > 975.0 or local.x < 645.0 or local.x > 1275.0:
		return -1
	return 0 if local.x < 960.0 else 1
