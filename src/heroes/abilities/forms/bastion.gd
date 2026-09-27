class_name BastionAbility
extends ZoneAbility
## Cleric legendary (Sanctuary): the holy ground becomes a dome of light.
## Enemy shots that reach it fizzle (boss fireballs and ice lances too),
## enemies inside are pushed out to its edge, and allies inside still heal.
## Bosses, props and nests don't budge.

## How fast enemies inside are pushed out (px/s): faster than any walks.
@export var push_speed := 160.0

## Enemy shots fly at body height: the dome reaches up this far.
const DOME_HEIGHT := Vector2(0, -6)

var _center := Vector2.ZERO
var _radius := 0.0
var _left := 0.0
var _pulse_in := 0.0
var _found := PackedInt32Array()


func _activate(aim: Vector2) -> void:
	super(aim)
	_center = _zone.position
	_radius = _zone.radius
	_left = _zone.duration
	_pulse_in = 0.0
	world().fx.implode(_center, _radius * 1.3, color, 0.3)


func _tick_active(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	var w := world()
	for p in w.projectiles.clear_enemy_shots_in_circle(_center + DOME_HEIGHT, _radius):
		w.particles.burst(p, 4, color, 60.0, 0.25, 1)
		w.fx.ring(p, 6.0, Color(1, 1, 0.85), 0.15)
		Audio.play(&"hit", -6.0, 1.5)
	var horde := w.horde
	horde.query_circle(_center, _radius, _found)
	for j in _found:
		if not horde.is_mobile(j):
			continue
		var away := horde.pos[j] - _center
		var d := away.length()
		var dir := away / d if d > 0.5 else Vector2.RIGHT.rotated(randf() * TAU)
		var next := horde.pos[j] + dir * minf(push_speed * delta, _radius + 3.0 - d)
		if not w.grid.is_solid_at(next):
			horde.relocate(j, next)
	_pulse_in -= delta
	if _pulse_in <= 0.0:
		_pulse_in = 0.5
		w.fx.ring(_center + DOME_HEIGHT * 0.5, _radius, color, 0.5)  # the dome's edge shimmers
		w.fx.dot_ring(_center + DOME_HEIGHT * 0.5, _radius * 0.9, 10, Color(1, 1, 0.85), 0.5)


func is_active() -> bool:
	return _left > 0.0


func cancel() -> void:
	_left = 0.0
