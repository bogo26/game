class_name ThrowingAxeAbility
extends MeleeArcAbility
## Berserker legendary (Axe Cleave): every combo finisher hurls the axe
## instead of swinging it. It spins out through the horde and back to the
## Berserker's hand, hitting everything both ways for the finisher's damage
## (with the Berserker's elements). One axe is out at a time: while it flies,
## the finisher is an ordinary heavy cleave.

@export var throw_reach := 110.0
@export var throw_speed := 230.0
@export var return_speed := 260.0
@export var throw_radius := 6.0

const TRAIL := Color(1.0, 0.7, 0.45)

var _axe: HeroMissile


func _activate(aim: Vector2) -> void:
	_swings += 1
	var heavy := is_combo_swing()
	if heavy and _axe == null:
		_throw(aim)
	else:
		_swing(aim, heavy)


func _throw(aim: Vector2) -> void:
	var m := HeroMissile.create(hero, ProjectileSim.Look.AXE, hero.body_position() + aim * 6.0,
		HeroMissile.Mode.RETURN)
	m.vel = aim * throw_speed
	m.reach = throw_reach * area_scale()
	m.return_speed = return_speed
	m.radius = throw_radius * sqrt(area_scale())
	m.damage = scaled_damage(damage * combo_multiplier)
	m.knockback = knockback * 0.6
	m.life = 3.0
	m.spin = 22.0
	m.elemental = hero.has_elements()
	_axe = m
	world().fx.slash(hero.position + Vector2(0, -4) + aim * 3.0, reach * 0.8, aim.angle(), 1.2, Color(1, 0.8, 0.4))


func _tick_active(delta: float) -> void:
	if _axe == null:
		return
	var was_returning := _axe.returning
	_axe.tick(delta)
	if _axe.returning and not was_returning:
		Audio.play(&"slash", -6.0, 0.7)
	if randf() < 0.5:
		world().particles.burst(_axe.pos, 1, TRAIL, 15.0, 0.25, 1)
	if _axe.done:
		world().fx.ring(hero.body_position(), 8.0, TRAIL, 0.2)  # caught
		_axe.free_sprite()
		_axe = null


func is_active() -> bool:
	return _axe != null


func cancel() -> void:
	if _axe:
		_axe.free_sprite()
		_axe = null
