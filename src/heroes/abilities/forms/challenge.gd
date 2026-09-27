class_name ChallengeAbility
extends AreaBurstAbility
## Knight legendary (Ground Slam): a roar that yanks every enemy around the
## Knight (in line of sight) to the Knight's feet and stuns it there, then
## hardens the Knight for a while: the more it caught, the less damage the
## Knight takes. Bosses, props and nests don't budge (bosses still count).

## How close to the Knight's feet they land.
@export var pull_to := 12.0
@export var guard_per_enemy := 0.04
@export var max_guard := 0.4
@export var guard_time := 5.0

var _guard := 0.0
var _guard_left := 0.0
var _pulse_in := 0.0
var _found := PackedInt32Array()


func _land(p: Vector2) -> void:
	var w := world()
	var horde := w.horde
	var r := _radius()
	var stun := stun_time + mod(&"stun_time")
	var dmg := scaled_damage(damage)
	var caught := 0
	horde.query_circle(p, r, _found)
	for j in _found:
		if horde.is_object(j) or not w.grid.line_of_sight(p, horde.pos[j]):
			continue
		if horde.is_mobile(j):
			var from := horde.pos[j]
			var away := from - p
			var dir := away.normalized() if away.length_squared() > 0.01 else Vector2.RIGHT.rotated(randf() * TAU)
			var to := p + dir * randf_range(pull_to * 0.6, pull_to)
			if not w.grid.is_solid_at(to):
				horde.relocate(j, to)
				w.fx.line(from + Vector2(0, -4), to + Vector2(0, -4), Color(color, 0.45), 0.15)
		w.hit_enemy(j, dmg, Vector2.ZERO, hero.slot, hero)
		horde.apply_stun(j, stun)
		caught += 1
	hero.on_hits(caught)
	_guard = minf(max_guard, guard_per_enemy * caught)
	_guard_left = guard_time if caught > 0 else 0.0
	_pulse_in = 0.0
	w.fx.implode(p + Vector2(0, -2), r, color, 0.25)
	w.fx.disc(p, pull_to + 6.0, Color(color, 0.5), 0.2)
	for k in 10:
		var a := TAU * k / 10.0
		w.particles.burst(p + Vector2.from_angle(a) * r, 1, Color(0.8, 0.72, 0.55), r * 3.0, 0.3, 2,
			-Vector2.from_angle(a), 0.3)
	w.shake(3.0)
	Audio.play(&"buff", 0.0, 0.8)


func _tick_active(delta: float) -> void:
	super(delta)
	if _guard_left <= 0.0:
		return
	_guard_left -= delta
	_pulse_in -= delta
	if _pulse_in <= 0.0:
		_pulse_in = 0.3
		world().fx.ring(hero.position + Vector2(0, -6), 11.0, color, 0.3)  # the shield shimmers


func damage_taken_factor() -> float:
	return 1.0 - _guard if _guard_left > 0.0 else 1.0


func cancel() -> void:
	_guard_left = 0.0


func sound() -> StringName:
	return &"slam"
