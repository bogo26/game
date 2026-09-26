class_name Stats
extends RefCounted
## Base values plus stacked modifiers: value = (base + flat) * (1 + pct).
## Upgrades only ever add modifiers, so the run's state is just "which
## upgrades were taken" and can be rebuilt on every level load.

const MAX_HP := &"max_hp"
const ARMOR := &"armor"
const MOVE_SPEED := &"move_speed"
const DAMAGE := &"damage"                ## multiplier, base 1
const ATTACK_SPEED := &"attack_speed"    ## multiplier, base 1
const CRIT_CHANCE := &"crit_chance"
const CRIT_DAMAGE := &"crit_damage"      ## crit multiplier
const PICKUP_RANGE := &"pickup_range"
const REGEN := &"regen"                  ## HP per second
const ULT_CHARGE := &"ult_charge"        ## multiplier on ultimate charge gain
const LIFE_ON_KILL := &"life_on_kill"    ## HP per kill
const REVIVE_SPEED := &"revive_speed"    ## multiplier when reviving teammates

var _base: Dictionary = {}
var _flat: Dictionary = {}
var _pct: Dictionary = {}


func set_base(stat: StringName, value: float) -> void:
	_base[stat] = value


func add_flat(stat: StringName, amount: float) -> void:
	_flat[stat] = float(_flat.get(stat, 0.0)) + amount


func add_pct(stat: StringName, amount: float) -> void:
	_pct[stat] = float(_pct.get(stat, 0.0)) + amount


func get_value(stat: StringName) -> float:
	var base := float(_base.get(stat, 0.0)) + float(_flat.get(stat, 0.0))
	return base * maxf(0.0, 1.0 + float(_pct.get(stat, 0.0)))


func clear_modifiers() -> void:
	_flat.clear()
	_pct.clear()
