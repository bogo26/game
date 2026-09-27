class_name BladeVortexAbility
extends ProjectileAbility
## Rogue legendary (Knife Ring): the knives whirl around the Rogue for a
## while, cutting whatever comes close, then fly outward as the old ring
## (Fan of Knives adds knives to the whirl).

@export var whirl_time := 3.0
@export var orbit_radius := 26.0
@export var orbit_speed := 7.0
## Share of a knife's damage each cut deals while it whirls.
@export var whirl_share := 0.6
## The same enemy is cut again at most this often.
@export var rehit := 0.4

var _knives: Array[HeroMissile] = []
var _left := 0.0


func _activate(_aim: Vector2) -> void:
	_release()  # a vortex still whirling (short cooldowns) flies off first
	var n := count + int(mod(&"count"))
	var cut := {}  # one memory for the whole vortex: each enemy is cut in turn
	for k in n:
		var m := HeroMissile.create(hero, look, hero.body_position(), HeroMissile.Mode.ORBIT)
		m.share_hits(cut)
		m.orbit_angle = TAU * k / n
		m.orbit_radius = orbit_radius * area_scale()
		m.orbit_speed = orbit_speed
		m.damage = scaled_damage(damage * whirl_share)
		m.radius = 4.0
		m.rehit = rehit
		m.knockback = knockback
		m.life = whirl_time + 10.0  # released by the ability, not by age
		_knives.append(m)
	_left = whirl_time + mod(&"duration")


func _tick_active(delta: float) -> void:
	if _knives.is_empty():
		return
	for m in _knives:
		m.tick(delta)
	_left -= delta
	if _left <= 0.0:
		_release()


## The knives fly off outward from where they are: the old Knife Ring.
func _release() -> void:
	if _knives.is_empty():
		return
	var center := hero.body_position()
	for m in _knives:
		var out := m.pos - center
		_fire(m.pos, out.normalized() if out.length_squared() > 0.01 else Vector2.RIGHT, 1, 0.0)
		m.free_sprite()
	_knives.clear()
	Audio.play(&"shoot_knife")


func is_active() -> bool:
	return not _knives.is_empty()


func cancel() -> void:
	for m in _knives:
		m.free_sprite()
	_knives.clear()
	_left = 0.0
