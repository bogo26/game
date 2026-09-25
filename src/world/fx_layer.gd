class_name FxLayer
extends Node2D
## Short-lived vector effects (slashes, rings, flashes, telegraphs, beams)
## drawn with crisp non-antialiased primitives. Two instances exist: one under
## the horde for ground effects and one above heroes. Replaced/augmented by
## sprite particles in the art pass.

enum Kind { RING, DISC, SLASH, LINE, TELEGRAPH, ZONE, WARN_LINE }

const MAX_EFFECTS := 256

var _kind := PackedInt32Array()
var _pos := PackedVector2Array()
var _pos2 := PackedVector2Array()
var _radius := PackedFloat32Array()
var _time := PackedFloat32Array()
var _duration := PackedFloat32Array()
var _angle := PackedFloat32Array()
var _arc := PackedFloat32Array()
var _color := PackedColorArray()


func tick(delta: float) -> void:
	var i := 0
	while i < _kind.size():
		_time[i] += delta
		if _time[i] >= _duration[i]:
			_remove(i)
		else:
			i += 1
	queue_redraw()


func clear() -> void:
	_kind.clear()
	_pos.clear()
	_pos2.clear()
	_radius.clear()
	_time.clear()
	_duration.clear()
	_angle.clear()
	_arc.clear()
	_color.clear()


## Expanding circle outline.
func ring(p: Vector2, radius: float, color: Color, duration: float = 0.25) -> void:
	_add(Kind.RING, p, p, radius, duration, 0.0, 0.0, color)


## Filled circle that fades out (explosions, heals).
func disc(p: Vector2, radius: float, color: Color, duration: float = 0.18) -> void:
	_add(Kind.DISC, p, p, radius, duration, 0.0, 0.0, color)


## Melee swoosh: an arc of `arc` radians facing `angle`.
func slash(p: Vector2, radius: float, angle: float, arc: float, color: Color, duration: float = 0.12) -> void:
	_add(Kind.SLASH, p, p, radius, duration, angle, arc, color)


func line(a: Vector2, b: Vector2, color: Color, duration: float = 0.1) -> void:
	_add(Kind.LINE, a, b, 1.0, duration, 0.0, 0.0, color)


## Warning line that stays solid until it fires (charges).
func warn_line(a: Vector2, b: Vector2, color: Color, duration: float) -> void:
	_add(Kind.WARN_LINE, a, b, 3.0, duration, 0.0, 0.0, color)


## Warning circle that fills up until the effect lands.
func telegraph(p: Vector2, radius: float, color: Color, duration: float) -> void:
	_add(Kind.TELEGRAPH, p, p, radius, duration, 0.0, 0.0, color)


## Persistent area (ground effects); fades in the last 20%.
func zone(p: Vector2, radius: float, color: Color, duration: float) -> void:
	_add(Kind.ZONE, p, p, radius, duration, 0.0, 0.0, color)


func _add(kind: Kind, a: Vector2, b: Vector2, radius: float, duration: float, angle: float,
		arc: float, color: Color) -> void:
	if _kind.size() >= MAX_EFFECTS:
		_remove(0)
	_kind.append(kind)
	_pos.append(a)
	_pos2.append(b)
	_radius.append(radius)
	_time.append(0.0)
	_duration.append(maxf(duration, 0.001))
	_angle.append(angle)
	_arc.append(arc)
	_color.append(color)


func _remove(i: int) -> void:
	_kind.remove_at(i)
	_pos.remove_at(i)
	_pos2.remove_at(i)
	_radius.remove_at(i)
	_time.remove_at(i)
	_duration.remove_at(i)
	_angle.remove_at(i)
	_arc.remove_at(i)
	_color.remove_at(i)


func _draw() -> void:
	for i in _kind.size():
		var t := _time[i] / _duration[i]
		var p := _pos[i].round()
		var c := _color[i]
		var r := _radius[i]
		match _kind[i]:
			Kind.RING:
				c.a *= 1.0 - t
				draw_arc(p, lerpf(r * 0.35, r, sqrt(t)), 0.0, TAU, _segments(r), c, 1.0, false)
			Kind.DISC:
				c.a *= 1.0 - t
				draw_circle(p, lerpf(r * 0.6, r, t), c, true, -1.0, false)
			Kind.SLASH:
				c.a *= 1.0 - t * t
				var a0 := _angle[i] - _arc[i] * 0.5
				var a1 := _angle[i] + _arc[i] * 0.5
				draw_arc(p, r, a0, a1, 12, c, 2.0, false)
				draw_arc(p, r - 3.0, a0 + 0.15, a1 - 0.15, 10, Color(c, c.a * 0.5), 1.0, false)
			Kind.LINE:
				c.a *= 1.0 - t
				draw_line(p, _pos2[i].round(), c, 1.0, false)
			Kind.TELEGRAPH:
				draw_arc(p, r, 0.0, TAU, _segments(r), Color(c, 0.9), 1.0, false)
				draw_circle(p, r * t, Color(c, 0.22), true, -1.0, false)
			Kind.WARN_LINE:
				draw_line(p, _pos2[i].round(), Color(c, 0.35 + 0.4 * t), r, false)
			Kind.ZONE:
				var fade := clampf((1.0 - t) / 0.2, 0.0, 1.0)
				draw_circle(p, r, Color(c, c.a * 0.25 * fade), true, -1.0, false)
				draw_arc(p, r, 0.0, TAU, _segments(r), Color(c, c.a * 0.8 * fade), 1.0, false)


static func _segments(radius: float) -> int:
	return clampi(int(radius * 0.8), 12, 64)
