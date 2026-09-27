class_name ClusterArrowAbility
extends ProjectileAbility
## Ranger legendary (Fan Volley): one heavy arrow that bursts, where it hits
## an enemy or a wall or where its flight ends, into a ring of piercing
## arrows (the volley's arrows: Wide Volley and Piercing Shots still apply).

@export var heavy_damage := 20.0
@export var heavy_speed := 240.0
@export var heavy_lifetime := 0.6
@export var heavy_radius := 5.0
@export var heavy_knockback := 60.0

const BURST_COLOR := Color(0.6, 1.0, 0.55)

var _arrows: Array[HeroMissile] = []


func _activate(aim: Vector2) -> void:
	var m := HeroMissile.create(hero, ProjectileSim.Look.HEAVY_ARROW, hero.muzzle_position())
	m.vel = aim * heavy_speed * (1.0 + mod(&"speed_pct"))
	m.damage = scaled_damage(heavy_damage)
	m.radius = heavy_radius
	m.life = heavy_lifetime
	m.pierce = 0
	m.knockback = heavy_knockback
	_arrows.append(m)


func _tick_active(delta: float) -> void:
	var i := 0
	while i < _arrows.size():
		var m := _arrows[i]
		m.tick(delta)
		if m.done:
			_burst(m.pos - m.heading() * (4.0 if m.hit_wall else 0.0))
			m.free_sprite()
			_arrows.remove_at(i)
		else:
			i += 1


func _burst(p: Vector2) -> void:
	var w := world()
	_fire(p, Vector2.RIGHT.rotated(randf() * TAU), count + int(mod(&"count")), TAU)
	w.fx.ring(p, 18.0, BURST_COLOR, 0.3)
	w.fx.disc(p, 8.0, Color(0.85, 1.0, 0.7, 0.7), 0.15)
	w.particles.burst(p, 10, BURST_COLOR, 90.0, 0.35, 2)
	Audio.play(&"shoot_arrow", 0.0, 0.8)


func is_active() -> bool:
	return not _arrows.is_empty()


func cancel() -> void:
	for m in _arrows:
		m.free_sprite()
	_arrows.clear()
