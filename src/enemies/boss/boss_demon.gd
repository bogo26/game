class_name BossDemon
extends Boss
## The Demon Lord, the final boss (see Boss for what every boss shares).
## Phase-based attack patterns:
##   phase 1 (100-60%): walks at the nearest hero, fireball fans and ground slams
##   phase 2 (60-25%):  adds fire rings and summons swarmers
##   phase 3 (<25%):    enraged: faster, adds telegraphed charges
## Every attack is announced during its wind-up (the boss glows and growls),
## drawn above the horde: the slam's area, the charge's exact path, the fan's
## aim lines (the aim is locked when the wind-up starts), a turning ring of
## dots for the fire ring, and spawn portals where summoned adds will appear.

enum Phase { ONE, TWO, THREE }
enum Action { WALK, WINDUP, CHARGE }
enum Attack { FAN, SLAM, RING, SUMMON, CHARGE }

## 4 frames: walk0, walk1, windup, charge.
const SPRITE := preload("res://assets/sprites/enemies/boss_demon.png")
## Fireballs leave from the chest.
const MUZZLE := Vector2(0, -24)
const BODY_RADIUS := 12.0
const SPEEDS: Array[float] = [22.0, 28.0, 38.0]
const ATTACK_GAPS: Array[float] = [2.4, 2.0, 1.5]
const FIREBALL_DAMAGE := 14.0
const SLAM_RADIUS := 60.0
const SLAM_DAMAGE := 30.0
const CHARGE_DAMAGE := 26.0
const CHARGE_SPEED := 260.0
const CHARGE_DISTANCE := 200.0
## A charge hits heroes whose feet come this close to its path.
const CHARGE_REACH := BODY_RADIUS + Hero.RADIUS + 4.0
const WINDUP_TIME := 0.5
const SLAM_WINDUP := 0.9
const CHARGE_WINDUP := 0.7
## Fireball fans spread over ±FAN_SPREAD radians.
const FAN_SPREAD := 0.6

var phase: Phase = Phase.ONE
var action: Action = Action.WALK
var pending_attack: Attack = Attack.FAN

var _attack_timer := 2.0
var _action_time := 0.0
var _charge_dir := Vector2.ZERO
var _fan_dir := Vector2.DOWN
var _charge_left := 0.0
var _charge_hit: Dictionary = {}


func _init() -> void:
	body_type = &"boss_demon"
	display_name = "Demon Lord"


func _sprite_texture() -> Texture2D:
	return SPRITE


func is_winding_up() -> bool:
	return action == Action.WINDUP


func _think(p: Vector2, dt: float) -> Vector2:
	_update_phase()
	var target := _nearest_hero(p)
	match action:
		Action.WALK:
			if target.is_finite():
				var to := target - p
				if to.length() > 24.0:
					p = world.grid.move_and_slide(p, to.normalized() * SPEEDS[phase] * dt, BODY_RADIUS)
				sprite.flip_h = to.x < 0.0
			_attack_timer -= dt
			if _attack_timer <= 0.0 and target.is_finite():
				_begin_attack(p, target)
		Action.WINDUP:
			_action_time -= dt
			if _action_time <= 0.0:
				_execute_attack(p, target)
		Action.CHARGE:
			var step := CHARGE_SPEED * dt
			var next := world.grid.move_and_slide(p, _charge_dir * step, BODY_RADIUS)
			var moved := next.distance_to(p)
			p = next
			_charge_left -= step
			for hero in world.heroes:
				if not _charge_hit.has(hero.slot) and hero.position.distance_to(p) < CHARGE_REACH:
					_charge_hit[hero.slot] = true
					hero.take_hit(CHARGE_DAMAGE * world.horde.damage_mult)
			world.fx.disc(p + Vector2(0, -10), 10.0, Color(1, 0.4, 0.2, 0.4), 0.15)
			if _charge_left <= 0.0 or moved < step * 0.3:
				world.shake(3.0)
				_end_action()
	return p


func _frame() -> int:
	if action == Action.WINDUP:
		return 2
	if action == Action.CHARGE:
		return 3
	return super()


func _tint() -> Color:
	return Color(1.3, 0.8, 0.8) if phase == Phase.THREE else Color.WHITE


func _update_phase() -> void:
	var ratio := hp_ratio()
	var new_phase := Phase.ONE
	if ratio < 0.25:
		new_phase = Phase.THREE
	elif ratio < 0.6:
		new_phase = Phase.TWO
	if new_phase != phase:
		phase = new_phase
		_announce_phase()
		_summon(&"swarmer", 6 + 3 * phase)


func _begin_attack(p: Vector2, target: Vector2) -> void:
	var options: Array[Attack] = [Attack.FAN, Attack.SLAM]
	if phase >= Phase.TWO:
		options.append_array([Attack.RING, Attack.SUMMON])
	if phase == Phase.THREE:
		options.append_array([Attack.CHARGE, Attack.CHARGE])
	wind_up(options[_rng.randi_range(0, options.size() - 1)], p, target)


## Starts `attack`'s wind-up and draws its warning.
func wind_up(attack: Attack, p: Vector2, target: Vector2) -> void:
	pending_attack = attack
	action = Action.WINDUP
	_action_time = WINDUP_TIME
	var warn := world.warn_fx
	var danger := FxLayer.DANGER
	match pending_attack:
		Attack.SLAM:
			_action_time = SLAM_WINDUP
			warn.telegraph(p, SLAM_RADIUS, danger, _action_time)
		Attack.CHARGE:
			_action_time = CHARGE_WINDUP
			_charge_dir = (target - p).normalized()
			warn.warn_band(p, p + _charge_dir * CHARGE_DISTANCE, CHARGE_REACH * 2.0, danger, _action_time)
		Attack.FAN:
			_fan_dir = _aim_at(p, target)
			var count := _fan_count()
			for k in count:
				var d := _fan_dir.rotated(_fan_angle(k, count))
				warn.warn_line(p + MUZZLE + d * 12.0, p + MUZZLE + d * 96.0, danger, _action_time, 1.0)
		Attack.RING:
			# On the top layer and wider than the body, so the boss can't hide it.
			world.fx.dot_ring(p + MUZZLE, 44.0, 12, danger, _action_time)
		Attack.SUMMON:
			_summon(&"swarmer", 8)  # the adds step out of their portals as the wind-up ends
	Audio.play(&"windup")


func _execute_attack(p: Vector2, _target: Vector2) -> void:
	match pending_attack:
		Attack.FAN:
			var count := _fan_count()
			for k in count:
				_fireball(p, _fan_dir.rotated(_fan_angle(k, count)), 115.0)
		Attack.SLAM:
			for hero in world.heroes:
				if hero.position.distance_to(p) <= SLAM_RADIUS + Hero.RADIUS \
						and world.grid.line_of_sight(p, hero.position):
					hero.take_hit(SLAM_DAMAGE * world.horde.damage_mult)
			world.fx.disc(p, SLAM_RADIUS, Color(1, 0.45, 0.2, 0.55), 0.3)
			world.fx.ring(p, SLAM_RADIUS * 1.1, Color(1, 0.8, 0.4), 0.35)
			world.shake(5.0)
			Audio.play(&"slam")
		Attack.RING:
			var count := 18 + 4 * phase
			var offset := _rng.randf() * TAU
			for k in count:
				_fireball(p, Vector2.from_angle(offset + TAU * k / count), 95.0)
		Attack.SUMMON:
			pass  # summoned when the wind-up started
		Attack.CHARGE:
			action = Action.CHARGE
			_charge_left = CHARGE_DISTANCE
			_charge_hit.clear()
			return
	_end_action()


## Aim from the chest at the hero's body, so the middle fireball flies
## straight at them instead of over their head.
func _aim_at(p: Vector2, target: Vector2) -> Vector2:
	if target.is_finite():
		var to := target + Hero.SPRITE_FEET_OFFSET - (p + MUZZLE)
		if to.length_squared() > 1.0:
			return to.normalized()
	return Vector2.DOWN


func _fan_count() -> int:
	return 7 + 2 * phase


func _fan_angle(k: int, count: int) -> float:
	return lerpf(-FAN_SPREAD, FAN_SPREAD, float(k) / float(count - 1))


func _end_action() -> void:
	action = Action.WALK
	_attack_timer = ATTACK_GAPS[phase] * _rng.randf_range(0.8, 1.2)


func _fireball(p: Vector2, dir: Vector2, speed: float) -> void:
	Audio.play(&"fireball")
	_shoot(p + MUZZLE, dir * speed, FIREBALL_DAMAGE, ProjectileSim.Look.FIRE)
