class_name ShadowHuntAbility
extends ShadowClonesAbility
## Rogue legendary (Shadow Clones): the clones stop copying the Rogue and
## hunt on their own: each blinks to an enemy near the Rogue every so often,
## stabs it (the Rogue's elements included) and marks it. With nothing to
## hunt they circle the Rogue.

@export var hunt_range := 140.0
@export var hop_interval := 0.35
@export var hunt_mark := 2.0

const STREAK := Color(0.55, 0.35, 0.9, 0.6)

## Per clone: where it stands (while hunting), and the time to its next hop.
var _spots := PackedVector2Array()
var _hop_in := PackedFloat32Array()
var _hunting := PackedByteArray()
var _found := PackedInt32Array()


func _activate(aim: Vector2) -> void:
	super(aim)
	var n := _ghosts.size()
	_spots.resize(n)
	_hop_in.resize(n)
	_hunting.resize(n)
	for i in n:
		_spots[i] = _ghost_position(i)
		_hop_in[i] = hop_interval * float(i) / maxf(1.0, n)  # staggered
		_hunting[i] = 0


func _tick_active(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	_angle += delta * 3.0
	for i in _ghosts.size():
		_hop_in[i] -= delta
		if _hop_in[i] <= 0.0:
			_hop_in[i] += hop_interval
			_hop(i)
		var at := _spots[i] if _hunting[i] != 0 else _ghost_position(i)
		var ghost := _ghosts[i]
		ghost.position = (at + Hero.SPRITE_FEET_OFFSET).round()
		ghost.frame = hero.sprite.frame
		ghost.modulate.a = 0.5 + 0.35 * clampf(_hop_in[i] / hop_interval, 0.0, 1.0)
	if _time_left <= 0.0:
		_clear_ghosts()


## Clone `i` blinks beside the nearest enemy to it near the Rogue (unmarked
## ones first) and stabs it.
func _hop(i: int) -> void:
	var w := world()
	var horde := w.horde
	var from := _spots[i] if _hunting[i] != 0 else _ghost_position(i)
	horde.query_circle(hero.position, hunt_range, _found)
	var best := -1
	var best_d2 := INF
	for j in _found:
		if horde.is_object(j):
			continue
		var d2 := from.distance_squared_to(horde.pos[j]) + (1e6 if horde.mark[j] > 0.0 else 0.0)
		if d2 < best_d2:
			best_d2 = d2
			best = j
	if best == -1:
		_hunting[i] = 0
		return
	var at := horde.pos[best]
	var side := (from - at).normalized() if from.distance_squared_to(at) > 1.0 else Vector2.LEFT
	var to := w.grid.nearest_open(at + side * (horde.t_radius[horde.type[best]] + 6.0))
	w.fx.line(from + Vector2(0, -6), to + Vector2(0, -6), STREAK, 0.15)
	_spots[i] = to
	_hunting[i] = 1
	_ghosts[i].flip_h = at.x < to.x
	var dir := (at - to).normalized() if at.distance_squared_to(to) > 0.01 else -side
	var arc := deg_to_rad(arc_degrees)
	hero.on_hits(w.damage_enemies_in_arc(to + Vector2(0, -4), dir, reach, arc * 0.5,
		scaled_damage(damage * damage_fraction), 30.0, hero.slot, 0.0, hero if hero.has_elements() else null))
	horde.apply_mark(best, hunt_mark)
	w.fx.slash(to + Vector2(0, -4) + dir * 3.0, reach * 0.8, dir.angle(), arc, Color(0.6, 0.4, 1.0, 0.8), 0.1)
	Audio.play(&"blink", -10.0, 1.3)


## Hunters don't copy the Rogue's swings.
func _on_attack(_aim: Vector2) -> void:
	pass
