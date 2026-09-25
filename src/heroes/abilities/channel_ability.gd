class_name ChannelAbility
extends Ability
## Timed stance around the hero (Whirlwind): pulses damage in a radius while
## it lasts, reduces damage taken and blocks the other non-movement abilities.

@export var duration := 4.0
@export var radius := 34.0
@export var interval := 0.2
@export var damage := 9.0
@export var knockback := 60.0
@export var damage_taken_multiplier := 0.5
@export var move_speed_multiplier := 1.1
@export var color := Color(0.85, 0.9, 1.0)

var _time_left := 0.0
var _tick_left := 0.0
var _spin := 0.0


func _activate(_aim: Vector2) -> void:
	_time_left = duration + mod(&"duration")
	_tick_left = 0.0


func is_active() -> bool:
	return _time_left > 0.0


func cancel() -> void:
	_time_left = 0.0


func blocks_other_abilities() -> bool:
	return is_active()


func damage_taken_factor() -> float:
	return damage_taken_multiplier if is_active() else 1.0


func move_speed_factor() -> float:
	return move_speed_multiplier if is_active() else 1.0


func _tick_active(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	_tick_left -= delta
	_spin += delta * 18.0
	var w := world()
	var r := radius * (1.0 + mod(&"area_pct"))
	w.fx.slash(hero.position + Vector2(0, -5), r * 0.75, _spin, PI * 0.9, Color(color, 0.8), 0.08)
	if _tick_left <= 0.0:
		_tick_left = interval
		hero.on_hits(w.damage_enemies_in_circle(hero.position, r, scaled_damage(damage), knockback, hero.slot))
