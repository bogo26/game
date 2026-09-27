@abstract
class_name Ability
extends Resource
## Base for hero abilities. Subclasses export their tuning and implement
## _activate(); per-hero runtime state (cooldowns, upgrade modifiers) lives on
## the duplicated instance bound to a Hero.
## An ultimate never charges itself: while it works (_activate, _tick_active)
## the horde logs its hits as an ultimate's (HordeSim.ult_hits), and minions
## and zones made meanwhile keep that (World.add_minion, World.add_zone).

enum Slot { ATTACK, SPECIAL, MOVEMENT, ULTIMATE }

@export var display_name := "Ability"
@export_multiline var description := ""
@export var cooldown := 1.0
## Attack-style abilities keep firing while the button is held.
@export var hold_to_repeat := false

var hero: Hero
var slot: Slot = Slot.ATTACK
var cooldown_left := 0.0
## Upgrade modifiers, e.g. {&"pierce": 1, &"count": 2}; read with mod().
var mods: Dictionary = {}


func bind(p_hero: Hero, p_slot: Slot) -> void:
	hero = p_hero
	slot = p_slot


## Called when a legendary form replaces this ability (after cancel()): drop
## any connection made in bind().
func unbind() -> void:
	pass


func world() -> World:
	return hero.world


func tick(delta: float) -> void:
	if cooldown_left > 0.0:
		cooldown_left -= delta
	var horde := world().horde
	horde.ult_hits = slot == Slot.ULTIMATE
	_tick_active(delta)
	horde.ult_hits = false


func can_activate() -> bool:
	return cooldown_left <= 0.0


func try_activate(aim: Vector2) -> bool:
	if not can_activate():
		return false
	var horde := world().horde
	horde.ult_hits = slot == Slot.ULTIMATE
	_activate(aim)
	horde.ult_hits = false
	cooldown_left = effective_cooldown()
	Audio.play(sound())
	if slot == Slot.ULTIMATE:
		Audio.play(&"ult")
	return true


## Sound played on activation (subclasses pick one that fits).
func sound() -> StringName:
	return &"cast"


func effective_cooldown() -> float:
	var scale := 1.0 + mod(&"cooldown_pct", 0.0)
	if slot == Slot.ATTACK:
		scale /= maxf(0.1, hero.attack_speed_mult * hero.buff_product(&"attack_speed_factor"))
	return maxf(0.05, cooldown * scale)


## 0 when ready, 1 right after use.
func cooldown_ratio() -> float:
	var total := effective_cooldown()
	return clampf(cooldown_left / total, 0.0, 1.0) if total > 0.0 else 0.0


## True while the ability is still doing something (channels, dashes).
func is_active() -> bool:
	return false


## Called when the hero goes down or the ability must stop early.
func cancel() -> void:
	pass


## While true, the hero can't use attack/special/ultimate (channels).
func blocks_other_abilities() -> bool:
	return false


## Multiplier on damage the hero takes while this ability is running.
func damage_taken_factor() -> float:
	return 1.0


## Multiplier on the hero's move speed while this ability is running.
func move_speed_factor() -> float:
	return 1.0


# Buff hooks (BuffAbility overrides these while active).
func damage_factor() -> float:
	return 1.0


func attack_speed_factor() -> float:
	return 1.0


func area_factor() -> float:
	return 1.0


## Fraction of damage dealt returned as healing.
func lifesteal() -> float:
	return 0.0


func heal_on_kill() -> float:
	return 0.0


func sprite_scale() -> float:
	return 1.0


## Tint multiplied into the hero's sprite (Lich Form).
func sprite_modulate() -> Color:
	return Color.WHITE


## Extra projectiles for every attack (Lich Form); summed over the abilities.
func shot_bonus() -> float:
	return 0.0


## An enemy the hero (or its minions) hit last just died at `at`.
func on_kill(_at: Vector2) -> void:
	pass


## Radius multiplier from upgrades (area_pct) and active buffs.
func area_scale() -> float:
	return (1.0 + mod(&"area_pct")) * hero.buff_product(&"area_factor")


func mod(key: StringName, default_value: float = 0.0) -> float:
	return float(mods.get(key, default_value))


func add_mod(key: StringName, amount: float) -> void:
	mods[key] = float(mods.get(key, 0.0)) + amount


## Damage with upgrades and the hero's multipliers. Crits are rolled per hit
## by World.hit_enemy (and at spawn for projectiles), so zones and multi-hit
## abilities crit per enemy instead of all-or-nothing.
func scaled_damage(base: float) -> float:
	return hero.base_damage(base * (1.0 + mod(&"damage_pct", 0.0)))


@abstract func _activate(aim: Vector2) -> void


func _tick_active(_delta: float) -> void:
	pass
