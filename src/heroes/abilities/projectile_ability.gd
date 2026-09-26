class_name ProjectileAbility
extends Ability
## Fires one or more projectiles: single shots, cone volleys, or full rings.

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


func _activate(aim: Vector2) -> void:
	var n := count + int(mod(&"count"))
	var spread := deg_to_rad(spread_degrees + mod(&"spread_deg"))
	var origin := hero.muzzle_position()
	var shot_speed := speed * (1.0 + mod(&"speed_pct"))
	var shot_pierce := pierce + int(mod(&"pierce"))
	var shot_bounces := bounces + int(mod(&"bounces"))
	var splash := splash_radius * area_scale() if splash_radius > 0.0 else 0.0
	var sim := world().projectiles
	for k in n:
		var offset := 0.0
		if n > 1:
			if spread >= TAU - 0.01:
				offset = TAU * float(k) / float(n)
			else:
				offset = lerpf(-spread * 0.5, spread * 0.5, float(k) / float(n - 1))
		var dir := aim.rotated(offset)
		var i := sim.spawn(origin, dir * shot_speed, scaled_damage(damage), radius, lifetime,
			ProjectileSim.Team.PLAYER, hero.slot, look, shot_pierce, knockback, shot_bounces)
		if i < 0:
			break
		if effect != ProjectileSim.Effect.NONE:
			sim.set_effect(i, effect, effect_time + mod(&"effect_time"))
		if splash > 0.0:
			sim.set_splash(i, splash)


func sound() -> StringName:
	match look:
		ProjectileSim.Look.ARROW:
			return &"shoot_arrow"
		ProjectileSim.Look.BOLT:
			return &"shoot_magic"
		ProjectileSim.Look.ORB:
			return &"shoot_orb"
		ProjectileSim.Look.KNIFE:
			return &"shoot_knife"
		ProjectileSim.Look.RIVET:
			return &"shoot_rivet"
		ProjectileSim.Look.SOUL:
			return &"shoot_soul"
	return &"shoot_arrow"
