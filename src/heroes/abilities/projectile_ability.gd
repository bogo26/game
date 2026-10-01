class_name ProjectileAbility
extends Ability
## Fires one or more projectiles: single shots, cone volleys, or full rings.

## Extra attack shots from buffs (Lich Form) widen a single shot into a fan
## this many degrees per extra shot.
const BONUS_SPREAD := 10.0

@export var count := 1
## Total spread of the volley; 360 fires an even ring.
@export var spread_degrees := 0.0
@export var damage := 8.0
@export var speed := 260.0
@export var radius := 3.0
@export var lifetime := 1.2
@export var pierce := 0
@export var bounces := 0
@export var knockback := 40.0
## > 0: impacts also hit enemies around the target for 60% damage.
@export var splash_radius := 0.0
@export var look: ProjectileSim.Look = ProjectileSim.Look.ARROW
@export var effect: ProjectileSim.Effect = ProjectileSim.Effect.NONE
@export var effect_time := 0.0
## Each shot leaves up to this many degrees off its line, and this share
## faster or slower (a flamethrower's gout instead of a neat fan).
@export var jitter_deg := 0.0
@export var speed_jitter := 0.0
## Area upgrades (Amplify) lengthen the shots' reach too (the Flamethrower).
@export var area_reach := false
## Shots turn toward the next enemy after each hit (Ricochet).
@export var ricochet := false
## Shots fork in three at a wall bounce, this many times (Prism Orbs).
@export var splits := 0
## Kills the shots make are logged for the ability (Haunt).
@export var reap := false


func _activate(aim: Vector2) -> void:
	var n := count + int(mod(&"count"))
	var spread := spread_degrees + mod(&"spread_deg")
	if slot == Slot.ATTACK:
		var bonus := int(hero.buff_sum(&"shot_bonus"))
		if bonus > 0:
			n += bonus
			spread += BONUS_SPREAD * bonus
	_fire(hero.muzzle_position(), aim, n, deg_to_rad(spread))


## Fires `n` shots from `origin`: a volley `spread` radians wide around `aim`
## (a full circle fires an even ring).
func _fire(origin: Vector2, aim: Vector2, n: int, spread: float) -> void:
	var shot_speed := speed * (1.0 + mod(&"speed_pct"))
	var shot_pierce := pierce + int(mod(&"pierce"))
	var shot_bounces := bounces + int(mod(&"bounces"))
	var splash := splash_radius * area_scale() if splash_radius > 0.0 else 0.0
	var shot_life := lifetime * area_scale() if area_reach else lifetime
	var sim := world().projectiles
	var elemental := slot == Slot.ATTACK and hero.has_elements()
	var bits := (ProjectileSim.TRAIT_RICOCHET if ricochet else 0) | (ProjectileSim.TRAIT_REAP if reap else 0)
	for k in n:
		var offset := 0.0
		if n > 1:
			if spread >= TAU - 0.01:
				offset = TAU * float(k) / float(n)
			else:
				offset = lerpf(-spread * 0.5, spread * 0.5, float(k) / float(n - 1))
		if jitter_deg > 0.0:
			offset += deg_to_rad(randf_range(-jitter_deg, jitter_deg))
		var dir := aim.rotated(offset)
		var v := shot_speed * (1.0 + randf_range(-speed_jitter, speed_jitter)) if speed_jitter > 0.0 else shot_speed
		var dmg := scaled_damage(damage)
		var crit := hero.roll_crit()
		if crit:
			dmg *= hero.crit_mult
		var i := sim.spawn(origin, dir * v, dmg, radius, shot_life,
			ProjectileSim.Team.PLAYER, hero.slot, look, shot_pierce, knockback, shot_bounces)
		if i < 0:
			break
		if crit:
			sim.set_crit(i)
		if elemental:
			sim.set_elemental(i)
		if effect != ProjectileSim.Effect.NONE:
			sim.set_effect(i, effect, effect_time + mod(&"effect_time"))
		if splash > 0.0:
			sim.set_splash(i, splash)
		if bits != 0:
			sim.set_traits(i, bits)
		if splits > 0:
			sim.set_splits(i, splits)


func sound() -> StringName:
	match look:
		ProjectileSim.Look.ARROW, ProjectileSim.Look.HEAVY_ARROW:
			return &"shoot_arrow"
		ProjectileSim.Look.BOLT:
			return &"shoot_magic"
		ProjectileSim.Look.ORB, ProjectileSim.Look.PRISM:
			return &"shoot_orb"
		ProjectileSim.Look.KNIFE:
			return &"shoot_knife"
		ProjectileSim.Look.RIVET:
			return &"shoot_rivet"
		ProjectileSim.Look.SOUL:
			return &"shoot_soul"
		ProjectileSim.Look.FLAME:
			return &"flame"
	return &"shoot_arrow"
