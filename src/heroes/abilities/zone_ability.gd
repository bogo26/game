class_name ZoneAbility
extends Ability
## Places a lasting area at the hero or the aim point that damages/slows
## enemies and/or heals heroes on an interval (Sanctuary, Arrow Rain).

enum Target { SELF, AIM_POINT }

@export var target: Target = Target.SELF
@export var distance := 80.0
@export var radius := 44.0
@export var duration := 5.0
@export var interval := 0.5
@export var damage := 0.0
## HP restored to heroes inside per tick.
@export var heal := 0.0
@export var slow_time := 0.0
@export var stun_time := 0.0
## "arrows" draws falling arrow streaks each tick.
@export var tick_visual := ""
@export var color := Color.WHITE

## The zone placed last.
var _zone: EffectZone


func _activate(aim: Vector2) -> void:
	var w := world()
	var zone := EffectZone.new()
	zone.position = hero.position
	if target == Target.AIM_POINT:
		zone.position = w.grid.sweep_until_blocked(hero.position, hero.position + aim * distance, 2.0)
	zone.radius = radius * area_scale()
	zone.duration = duration + mod(&"duration")
	zone.interval = interval
	var base_damage := damage + mod(&"zone_damage")
	zone.damage = scaled_damage(base_damage) if base_damage > 0.0 else 0.0
	zone.heal = heal * (1.0 + mod(&"heal_pct"))
	zone.slow_time = slow_time
	zone.stun_time = stun_time
	zone.owner_slot = hero.slot
	zone.color = color
	zone.tick_visual = tick_visual
	w.add_zone(zone)
	_zone = zone


func sound() -> StringName:
	return &"heal" if heal > 0.0 else &"cast"
