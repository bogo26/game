class_name EffectZone
extends RefCounted
## A persistent circular area ticked by the World: damages/slows enemies and/or
## heals heroes inside it every `interval` seconds (Sanctuary, Arrow Rain,
## caltrops, fire trails).

var position := Vector2.ZERO
var radius := 32.0
var duration := 4.0
var interval := 0.5
var damage := 0.0
var heal := 0.0
var slow_time := 0.0
var stun_time := 0.0
var knockback := 0.0
var owner_slot := -1
## Made by an ultimate (set by World.add_zone): its hits don't charge ultimates.
var ultimate := false
## > 0: a toxic cloud (Plague) adding a poison stack of this strength per tick.
var poison_dps := 0.0
var color := Color.WHITE
## Optional visual per tick: "arrows" draws falling arrow streaks.
var tick_visual := ""

var elapsed := 0.0
var _next_tick := 0.0


func is_finished() -> bool:
	return elapsed >= duration


## Returns true on frames where the zone applies its effect.
func advance(delta: float) -> bool:
	elapsed += delta
	if elapsed >= _next_tick:
		_next_tick += interval
		return true
	return false
