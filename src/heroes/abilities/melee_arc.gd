class_name MeleeArcAbility
extends Ability
## Melee swing hitting every enemy in a cone in front of the hero.

@export var reach := 26.0
@export var arc_degrees := 120.0
@export var damage := 12.0
@export var knockback := 90.0
@export var stun_time := 0.0
## Every Nth swing is a heavy hit (combo finisher); 0 disables.
@export var combo_every := 0
@export var combo_multiplier := 2.0
@export var color := Color(1, 1, 1, 0.9)

var _swings := 0


func _activate(aim: Vector2) -> void:
	_swings += 1
	var multiplier := 1.0
	var reach_now := reach * area_scale()
	var heavy := combo_every > 0 and _swings % combo_every == 0
	if heavy:
		multiplier = combo_multiplier
		reach_now *= 1.3
	var center := hero.position + Vector2(0, -4)
	var arc := deg_to_rad(arc_degrees + mod(&"arc_deg"))
	var elemental: Hero = hero if slot == Slot.ATTACK and hero.has_elements() else null
	var hits := world().damage_enemies_in_arc(center, aim, reach_now, arc * 0.5,
		scaled_damage(damage * multiplier), knockback * (1.5 if heavy else 1.0), hero.slot,
		stun_time + mod(&"stun_time"), elemental)
	hero.on_hits(hits)
	world().fx.slash(center + aim * 3.0, reach_now * 0.8, aim.angle(), arc,
		color if not heavy else Color(1, 0.8, 0.4))


func sound() -> StringName:
	return &"slash"
