class_name HauntAbility
extends ProjectileAbility
## Necromancer legendary (Soul Bolt): enemies the bolts kill rise as vengeful
## wisps that seek out another enemy and burst on it (with the Necromancer's
## elements). Kills by the wisps release wisps too.

@export var wisp_share := 0.7
@export var wisp_speed := 120.0
@export var wisp_turn := 6.0
@export var wisp_range := 140.0
@export var wisp_life := 2.0
@export var wisp_burst := 16.0
@export var max_wisps := 10
## A wisp rises this long before it can burst on anything.
@export var wisp_rise := 0.15

const WISP := Color(0.55, 1.0, 0.9)

var _wisps: Array[HeroMissile] = []
var _found := PackedInt32Array()


func _tick_active(delta: float) -> void:
	var w := world()
	# Last frame's kills by this hero's bolts (the ProjectileSim logs them).
	var reaped := w.projectiles.reaped
	for k in reaped.size():
		if w.projectiles.reaped_owner[k] == hero.slot:
			_rise(reaped[k])
	var i := 0
	while i < _wisps.size():
		var m := _wisps[i]
		m.tick(delta)
		if m.done:
			if m.hit_enemy:
				_burst(m.pos)
			m.free_sprite()
			_wisps.remove_at(i)
		else:
			i += 1


## A wisp rises from a fallen enemy at `at` (its feet).
func _rise(at: Vector2) -> void:
	if _wisps.size() >= max_wisps:
		return
	var m := HeroMissile.create(hero, ProjectileSim.Look.SOUL, at + Vector2(0, -6), HeroMissile.Mode.HOMING)
	m.vel = Vector2.UP.rotated(randf_range(-0.8, 0.8)) * wisp_speed
	m.turn_rate = wisp_turn
	m.seek_range = wisp_range
	m.life = wisp_life
	m.radius = 4.0
	m.detonate = true
	m.arm_time = wisp_rise
	_wisps.append(m)
	world().particles.burst(at + Vector2(0, -6), 5, WISP, 40.0, 0.4, 2, Vector2.UP, 0.8, -40.0)
	Audio.play(&"shoot_soul", -8.0, 1.3)


## A wisp bursts on the enemy it reached: whoever it kills rises too.
func _burst(p: Vector2) -> void:
	var w := world()
	var horde := w.horde
	var dmg := scaled_damage(damage * wisp_share)
	horde.query_bodies(p, wisp_burst, _found)
	for j in _found:
		if horde.is_object(j):
			continue
		var at := horde.pos[j]
		if w.hit_enemy(j, dmg, (at - p).normalized() * 40.0, hero.slot, hero):
			_rise(at)
		if hero.has_elements():
			w.elements.on_attack_hit(hero, j, dmg)
	hero.on_hits(_found.size())
	w.fx.disc(p, wisp_burst * 0.7, Color(WISP, 0.5), 0.18)
	w.fx.ring(p, wisp_burst, WISP, 0.25)
	w.particles.burst(p, 6, WISP, 70.0, 0.35, 2)


func is_active() -> bool:
	return not _wisps.is_empty()


func cancel() -> void:
	for m in _wisps:
		m.free_sprite()
	_wisps.clear()
