class_name FxLayer
extends Node2D
## Short-lived vector effects (slashes, rings, flashes, telegraphs, beams)
## drawn with crisp non-antialiased primitives. Three instances exist: one
## under the horde for ground effects, one just above the horde for warnings
## (telegraphs, spawn portals: enemies must never hide them) and one above
## heroes. "Live" warnings are replaced every frame by their owner (exploder
## fuses follow the exploders and vanish when they die).

enum Kind { RING, DISC, SLASH, LINE, TELEGRAPH, ZONE, WARN_LINE, BOLT, WARN_BAND, DOT_RING, PORTAL }

## Everything hostile warns in this colour (enemy shots use it too).
const DANGER := Color(1.0, 0.24, 0.5)

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
var _live_pos := PackedVector2Array()
var _live_radius := PackedFloat32Array()
var _live_progress := PackedFloat32Array()


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


## Lightning between two points: a jagged line that flickers.
func bolt(a: Vector2, b: Vector2, color: Color, duration: float = 0.12) -> void:
	_add(Kind.BOLT, a, b, 1.0, duration, 0.0, 0.0, color)


## Warning line that stays solid until it fires (aim lines).
func warn_line(a: Vector2, b: Vector2, color: Color, duration: float, width: float = 3.0) -> void:
	_add(Kind.WARN_LINE, a, b, width, duration, 0.0, 0.0, color)


## Warning strip `width` wide from a to b (charges): exactly where it will hit.
func warn_band(a: Vector2, b: Vector2, width: float, color: Color, duration: float) -> void:
	_add(Kind.WARN_BAND, a, b, width, duration, 0.0, 0.0, color)


## Warning circle that fills up until the effect lands. Heroes' own
## telegraphs are dashed so they never read as an enemy's.
func telegraph(p: Vector2, radius: float, color: Color, duration: float, dashed: bool = false) -> void:
	_add(Kind.TELEGRAPH, p, p, radius, duration, 1.0 if dashed else 0.0, 0.0, color)


## A ring of `dots` points turning around p (a ring of shots is coming).
func dot_ring(p: Vector2, radius: float, dots: int, color: Color, duration: float) -> void:
	_add(Kind.DOT_RING, p, p, radius, duration, 0.0, float(dots), color)


## A swirling dark hole where an enemy is about to appear.
func portal(p: Vector2, radius: float, color: Color, duration: float) -> void:
	_add(Kind.PORTAL, p, p, radius, duration, 0.0, 0.0, color)


## Replaces this frame's live warnings: filling circles (progress 0..1).
func set_live(positions: PackedVector2Array, radii: PackedFloat32Array, progress: PackedFloat32Array) -> void:
	_live_pos = positions
	_live_radius = radii
	_live_progress = progress


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
				draw_line(p, _pos2[i].round(), c, -1.0, false)
			Kind.TELEGRAPH:
				if _angle[i] > 0.5:
					_dashed_circle(p, r, Color(c, 0.9))
				else:
					draw_arc(p, r, 0.0, TAU, _segments(r), Color(c, 0.9), 1.0, false)
				draw_circle(p, r * t, Color(c, 0.22), true, -1.0, false)
			Kind.WARN_LINE:
				# 1 px lines are drawn as line primitives: a 1 px wide quad at an
				# angle collapses to nothing once vertices snap to pixels.
				draw_line(p, _pos2[i].round(), Color(c, 0.5 + 0.4 * t), r if r > 1.0 else -1.0, false)
			Kind.WARN_BAND:
				var b := _pos2[i].round()
				var side := (b - p).orthogonal().normalized() * (r * 0.5)
				var quad := PackedVector2Array([p + side, b + side, b - side, p - side])
				draw_colored_polygon(quad, Color(c, 0.1 + 0.25 * t))
				draw_line((p + side).round(), (b + side).round(), Color(c, 0.9), -1.0, false)
				draw_line((p - side).round(), (b - side).round(), Color(c, 0.9), -1.0, false)
			Kind.DOT_RING:
				var dots := int(_arc[i])
				var turn := t * 1.2
				for k in dots:
					var q := (p + Vector2.from_angle(turn + TAU * k / dots) * r * lerpf(0.6, 1.0, t)).round()
					draw_rect(Rect2(q - Vector2(1, 1), Vector2(3, 3)), Color(c, 0.45 + 0.55 * t))
			Kind.PORTAL:
				var grow := lerpf(0.35, 1.0, minf(1.0, t * 2.5))
				var rr := r * grow
				draw_circle(p, rr, Color(0.07, 0.02, 0.1, 0.7), true, -1.0, false)
				draw_arc(p, rr, t * 9.0, t * 9.0 + PI * 1.3, 10, c, 1.0, false)
				draw_arc(p, rr * 0.55, -t * 12.0, -t * 12.0 + PI, 8, Color(c, 0.7), 1.0, false)
			Kind.BOLT:
				c.a *= 1.0 - t * t
				var b := _pos2[i].round()
				var side := (b - p).orthogonal().normalized()
				var points := PackedVector2Array([p])
				for k in range(1, 4):
					points.append((p.lerp(b, k / 4.0) + side * randf_range(-4.0, 4.0)).round())
				points.append(b)
				draw_polyline(points, Color(c, c.a * 0.35), 3.0, false)
				draw_polyline(points, c, 1.0, false)
			Kind.ZONE:
				var fade := clampf((1.0 - t) / 0.2, 0.0, 1.0)
				draw_circle(p, r, Color(c, c.a * 0.25 * fade), true, -1.0, false)
				draw_arc(p, r, 0.0, TAU, _segments(r), Color(c, c.a * 0.8 * fade), 1.0, false)
	for k in _live_pos.size():
		var lp := _live_pos[k].round()
		var lr := _live_radius[k]
		draw_arc(lp, lr, 0.0, TAU, _segments(lr), Color(DANGER, 0.9), 1.0, false)
		draw_circle(lp, lr * clampf(_live_progress[k], 0.0, 1.0), Color(DANGER, 0.25), true, -1.0, false)


func _dashed_circle(p: Vector2, r: float, c: Color) -> void:
	var segments := _segments(r) & ~1
	var step := TAU / segments
	for k in range(0, segments, 2):
		draw_arc(p, r, k * step, (k + 1) * step, 2, c, 1.0, false)


static func _segments(radius: float) -> int:
	return clampi(int(radius * 0.8), 12, 64)
