class_name DashAbility
extends Ability
## Movement ability: a quick dash with i-frames that can bash, stun, slow or
## mark enemies it passes, heal allies it passes, drop a trap where it starts,
## or leave a burning trail.

enum Direction { MOVE_OR_AIM, AIM, AWAY_FROM_AIM }

@export var direction: Direction = Direction.MOVE_OR_AIM
@export var distance := 64.0
@export var duration := 0.18
@export var iframes := 0.25
@export_group("Enemies passed")
@export var damage := 0.0
@export var hit_radius := 10.0
@export var knockback := 0.0
@export var stun_time := 0.0
@export var slow_time := 0.0
## Marked enemies take guaranteed critical hits for this long (Rogue).
@export var mark_time := 0.0
@export_group("Allies passed")
@export var heal_allies := 0.0
@export_group("Zones")
## Trap dropped where the dash starts (Ranger caltrops).
@export var start_zone_radius := 0.0
@export var start_zone_duration := 4.0
@export var start_zone_damage := 0.0
@export var start_zone_slow := 0.0
## Burning trail left along the path (Engineer); damage per tick.
@export var trail_damage := 0.0
@export_group("Leap")
## > 0 turns the dash into a jump arc (visual) that lands with an impact.
@export var arc_height := 0.0
@export var landing_damage := 0.0
@export var landing_radius := 36.0
@export var landing_stun := 0.0
@export var color := Color(1, 1, 1, 0.6)

var _active := false
var _hit_uids: Dictionary = {}
var _healed: Dictionary = {}
var _trail_timer := 0.0
var _scratch := PackedInt32Array()


func _activate(aim: Vector2) -> void:
	var dir := aim
	match direction:
		Direction.MOVE_OR_AIM:
			if hero.input.move != Vector2.ZERO:
				dir = hero.input.move.normalized()
		Direction.AWAY_FROM_AIM:
			dir = -aim
	var w := world()
	if start_zone_radius > 0.0:
		var zone := EffectZone.new()
		zone.position = hero.position
		zone.radius = start_zone_radius
		zone.duration = start_zone_duration
		zone.interval = 0.4
		zone.damage = scaled_damage(start_zone_damage)
		zone.slow_time = start_zone_slow
		zone.owner_slot = hero.slot
		zone.color = Color(0.8, 0.8, 0.8)
		w.add_zone(zone)
	hero.start_dash(dir, distance * (1.0 + mod(&"distance_pct")), duration, iframes + mod(&"iframes"))
	_active = true
	_hit_uids.clear()
	_healed.clear()
	_trail_timer = 0.0
	w.fx.ring(hero.position, 10.0, color, 0.2)


func is_active() -> bool:
	return _active


func cancel() -> void:
	_active = false
	hero.air_height = 0.0


func _tick_active(delta: float) -> void:
	if not _active:
		return
	var w := world()
	if arc_height > 0.0:
		var t := 1.0 - clampf(hero.dash_time_left / maxf(duration, 0.01), 0.0, 1.0)
		hero.air_height = sin(t * PI) * arc_height if hero.is_dashing() else 0.0
	if not hero.is_dashing():
		_active = false
		hero.air_height = 0.0
		if landing_damage > 0.0:
			var r := landing_radius * area_scale()
			hero.on_hits(w.damage_enemies_in_circle(hero.position, r, scaled_damage(landing_damage),
				160.0, hero.slot, landing_stun + mod(&"stun_time")))
			w.fx.disc(hero.position, r, Color(color, 0.45), 0.2)
			w.fx.ring(hero.position, r * 1.15, color, 0.3)
			w.shake(3.0)
			Audio.play(&"slam")
		var burst := mod(&"end_burst")
		if burst > 0.0:
			hero.on_hits(w.damage_enemies_in_circle(hero.position, 30.0, scaled_damage(burst), 150.0, hero.slot, 0.3))
			w.fx.ring(hero.position, 30.0, color, 0.3)
			w.shake(2.0)
		return
	w.fx.disc(hero.position + Vector2(0, -6), 4.0, Color(color, 0.35), 0.15)
	if damage > 0.0 or knockback > 0.0 or stun_time > 0.0 or slow_time > 0.0 or mark_time > 0.0:
		var horde := w.horde
		horde.query_circle(hero.position, hit_radius, _scratch)
		for j in _scratch:
			var id := horde.uid[j]
			if _hit_uids.has(id):
				continue
			_hit_uids[id] = true
			var push := (horde.pos[j] - hero.position).normalized() * knockback
			if damage > 0.0:
				horde.damage(j, scaled_damage(damage), push, hero.slot)
			elif push != Vector2.ZERO:
				horde.vel[j] += push
			if stun_time > 0.0:
				horde.apply_stun(j, stun_time + mod(&"stun_time"))
			if slow_time > 0.0:
				horde.apply_slow(j, slow_time)
			if mark_time > 0.0:
				horde.apply_mark(j, mark_time)
	var heal_amount := heal_allies + mod(&"heal_allies")
	if heal_amount > 0.0:
		for ally in w.heroes:
			if ally != hero and not _healed.has(ally.slot) and ally.position.distance_to(hero.position) < 18.0:
				_healed[ally.slot] = true
				if ally.is_downed():
					ally.add_revive_progress(Hero.REVIVE_TIME * 0.5)
				else:
					ally.heal(heal_amount)
				w.fx.disc(ally.position + Vector2(0, -6), 10.0, Color(1, 0.95, 0.5, 0.6), 0.3)
	if trail_damage > 0.0:
		_trail_timer -= delta
		if _trail_timer <= 0.0:
			_trail_timer = 0.04
			var zone := EffectZone.new()
			zone.position = hero.position
			zone.radius = 9.0
			zone.duration = 2.0
			zone.interval = 0.3
			zone.damage = scaled_damage(trail_damage)
			zone.owner_slot = hero.slot
			zone.color = Color(1.0, 0.5, 0.15)
			w.add_zone(zone)


func sound() -> StringName:
	return &"dash"
