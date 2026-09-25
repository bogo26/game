class_name BuffAbility
extends Ability
## Timed self-buff (Blood Frenzy, Rampage): optionally costs HP, then boosts
## damage / attack speed / speed / area, adds lifesteal or heal-on-kill,
## reduces damage taken and can grow the hero.

@export var duration := 5.0
## Fraction of current HP paid on activation.
@export var hp_cost := 0.0
@export var damage_multiplier := 1.0
@export var attack_speed_multiplier := 1.0
@export var move_speed_multiplier := 1.0
@export var damage_taken_multiplier := 1.0
@export var area_multiplier := 1.0
@export var lifesteal_fraction := 0.0
@export var heal_per_kill := 0.0
@export var scale := 1.0
@export var color := Color(1, 0.3, 0.3)

var _time_left := 0.0


func _activate(_aim: Vector2) -> void:
	if hp_cost > 0.0:
		hero.hp = maxf(1.0, hero.hp * (1.0 - hp_cost))
	_time_left = duration + mod(&"duration")
	world().fx.ring(hero.position + Vector2(0, -6), 16.0, color, 0.4)


func is_active() -> bool:
	return _time_left > 0.0


func cancel() -> void:
	_time_left = 0.0


func _tick_active(delta: float) -> void:
	if _time_left > 0.0:
		_time_left -= delta
		if int(_time_left * 8.0) % 2 == 0:
			world().fx.disc(hero.position + Vector2(randf_range(-5, 5), randf_range(-12, 0)), 2.0, color, 0.25)


func damage_factor() -> float:
	return damage_multiplier * (1.0 + mod(&"buff_damage")) if is_active() else 1.0


func attack_speed_factor() -> float:
	return attack_speed_multiplier if is_active() else 1.0


func move_speed_factor() -> float:
	return move_speed_multiplier if is_active() else 1.0


func damage_taken_factor() -> float:
	return damage_taken_multiplier if is_active() else 1.0


func area_factor() -> float:
	return area_multiplier if is_active() else 1.0


func lifesteal() -> float:
	return lifesteal_fraction + mod(&"lifesteal") if is_active() else 0.0


func heal_on_kill() -> float:
	return heal_per_kill if is_active() else 0.0


func sprite_scale() -> float:
	return scale if is_active() else 1.0
