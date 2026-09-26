class_name SharedCamera
extends Camera2D
## One camera for all players. Follows the centre of the group's bounding box
## at a fixed (integer) zoom and exposes the leash size: how far apart players
## may spread before the World stops them at the screen edge.

const LEASH_MARGIN := 14.0
const FOLLOW_SHARPNESS := 10.0
const SHAKE_DECAY := 18.0
const MAX_SHAKE := 6.0

var target := Vector2.ZERO
var _smoothed := Vector2.ZERO
var _bounds := Rect2()
var _has_target := false
var _shake := 0.0
var _rng := RandomNumberGenerator.new()


func setup(level_size_px: Vector2) -> void:
	_bounds = Rect2(Vector2.ZERO, level_size_px)
	_has_target = false


func view_size() -> Vector2:
	return get_viewport_rect().size


## Maximum extent of the players' bounding box.
func leash_size() -> Vector2:
	return view_size() - Vector2(LEASH_MARGIN, LEASH_MARGIN) * 2.0


func visible_rect() -> Rect2:
	var size := view_size()
	return Rect2(global_position - size * 0.5, size)


func follow(points: Array[Vector2], delta: float) -> void:
	if points.is_empty():
		return
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	target = box.get_center()
	if not _has_target:
		_smoothed = target
		_has_target = true
	_smoothed = _smoothed.lerp(target, 1.0 - exp(-FOLLOW_SHARPNESS * delta))
	global_position = _clamp_to_bounds(_smoothed).round()
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - SHAKE_DECAY * delta)
		offset = Vector2(_rng.randf_range(-_shake, _shake), _rng.randf_range(-_shake, _shake)).round()
	else:
		offset = Vector2.ZERO


## Screen shake in whole pixels; stronger calls override weaker ones. Scaled
## (or turned off) by the screen-shake setting.
func add_shake(strength: float) -> void:
	_shake = minf(MAX_SHAKE, maxf(_shake, strength * Settings.shake_scale()))


func snap_to(point: Vector2) -> void:
	target = point
	_smoothed = point
	_has_target = true
	global_position = _clamp_to_bounds(point).round()


func _clamp_to_bounds(p: Vector2) -> Vector2:
	var half := view_size() * 0.5
	var out := p
	if _bounds.size.x <= half.x * 2.0:
		out.x = _bounds.get_center().x
	else:
		out.x = clampf(p.x, _bounds.position.x + half.x, _bounds.end.x - half.x)
	if _bounds.size.y <= half.y * 2.0:
		out.y = _bounds.get_center().y
	else:
		out.y = clampf(p.y, _bounds.position.y + half.y, _bounds.end.y - half.y)
	return out
