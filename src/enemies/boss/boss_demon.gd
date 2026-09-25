class_name BossDemon
extends Node2D
## The Big Demon. Its body (HP, hitbox, contact damage) is a HordeSim entry so
## every hero ability hits it like any enemy; this node moves that entry,
## draws the sprite and runs the phase-based attack patterns:
##   phase 1 (100-60%): walks at the nearest hero, fireball fans and ground slams
##   phase 2 (60-25%):  adds fire rings and summons swarmers
##   phase 3 (<25%):    enraged: faster, adds telegraphed charges

signal defeated

enum Phase { ONE, TWO, THREE }
enum Action { WALK, WINDUP, CHARGE }
enum Attack { FAN, SLAM, RING, SUMMON, CHARGE }

const SPRITE := preload("res://assets/sprites/enemies/boss_demon.png")
const BODY_RADIUS := 12.0
const SPEEDS: Array[float] = [22.0, 28.0, 38.0]
const ATTACK_GAPS: Array[float] = [2.4, 2.0, 1.5]
const FIREBALL_DAMAGE := 14.0
const SLAM_RADIUS := 60.0
const SLAM_DAMAGE := 30.0
const CHARGE_DAMAGE := 26.0
const CHARGE_SPEED := 260.0
const CHARGE_DISTANCE := 200.0

var world: World
var uid := -1
var max_hp := 1.0
var phase: Phase = Phase.ONE
var action: Action = Action.WALK
var pending_attack: Attack = Attack.FAN

var _index := -1
var _attack_timer := 2.0
var _action_time := 0.0
var _anim := 0.0
var _charge_dir := Vector2.ZERO
var _charge_left := 0.0
var _charge_hit: Dictionary = {}
var _add_hp_multiplier := 1.0
var _rng := RandomNumberGenerator.new()
var _dead := false

@onready var sprite: Sprite2D = $Sprite


func setup(p_world: World, spawn_position: Vector2, hp_multiplier: float, add_hp_multiplier: float) -> void:
	world = p_world
	position = spawn_position
	_add_hp_multiplier = add_hp_multiplier
	var type_id := world.horde.type_index(&"boss_demon")
	_index = world.horde.spawn(type_id, spawn_position, hp_multiplier)
	uid = world.horde.uid[_index]
	max_hp = world.horde.hp[_index]
	_rng.randomize()


func _ready() -> void:
	sprite.texture = SPRITE
	sprite.hframes = 4
	sprite.offset = Vector2(0, -26)


func hp_ratio() -> float:
	if _index < 0 or _dead:
		return 0.0
	return clampf(world.horde.hp[_index] / max_hp, 0.0, 1.0)


func tick(dt: float) -> void:
	if _dead:
		return
	var horde := world.horde
	_index = horde.index_of_uid(uid, _index)
	if _index == -1 or horde.hp[_index] <= 0.0:
		_die()
		return
	var p := horde.pos[_index]
	_update_phase()
	var target := _nearest_hero(p)
	_anim += dt
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
				if not _charge_hit.has(hero.slot) and hero.position.distance_to(p) < BODY_RADIUS + Hero.RADIUS + 4.0:
					_charge_hit[hero.slot] = true
					hero.take_hit(CHARGE_DAMAGE)
			world.fx.disc(p + Vector2(0, -10), 10.0, Color(1, 0.4, 0.2, 0.4), 0.15)
			if _charge_left <= 0.0 or moved < step * 0.3:
				world.shake(3.0)
				_end_action()
	horde.pos[_index] = p
	position = p.round()
	_update_sprite()


func _update_phase() -> void:
	var ratio := hp_ratio()
	var new_phase := Phase.ONE
	if ratio < 0.25:
		new_phase = Phase.THREE
	elif ratio < 0.6:
		new_phase = Phase.TWO
	if new_phase != phase:
		phase = new_phase
		world.shake(5.0)
		world.fx.ring(position, 50.0, Color(1, 0.3, 0.2), 0.5)
		Audio.play(&"roar")
		_summon(6 + 3 * phase)


func _begin_attack(p: Vector2, target: Vector2) -> void:
	var options: Array[Attack] = [Attack.FAN, Attack.SLAM]
	if phase >= Phase.TWO:
		options.append_array([Attack.RING, Attack.SUMMON])
	if phase == Phase.THREE:
		options.append_array([Attack.CHARGE, Attack.CHARGE])
	pending_attack = options[_rng.randi_range(0, options.size() - 1)]
	action = Action.WINDUP
	match pending_attack:
		Attack.SLAM:
			_action_time = 0.9
			world.ground_fx.telegraph(p, SLAM_RADIUS, Color(1, 0.3, 0.2), _action_time)
		Attack.CHARGE:
			_action_time = 0.7
			_charge_dir = (target - p).normalized()
			world.ground_fx.warn_line(p, p + _charge_dir * CHARGE_DISTANCE, Color(1, 0.3, 0.2), _action_time)
		_:
			_action_time = 0.5


func _execute_attack(p: Vector2, target: Vector2) -> void:
	match pending_attack:
		Attack.FAN:
			var dir := (target - p).normalized() if target.is_finite() else Vector2.DOWN
			var count := 7 + 2 * phase
			for k in count:
				var a := lerpf(-0.6, 0.6, float(k) / float(count - 1))
				_fireball(p, dir.rotated(a), 115.0)
		Attack.SLAM:
			for hero in world.heroes:
				if hero.position.distance_to(p) <= SLAM_RADIUS + Hero.RADIUS:
					hero.take_hit(SLAM_DAMAGE)
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
			_summon(8)
		Attack.CHARGE:
			action = Action.CHARGE
			_charge_left = CHARGE_DISTANCE
			_charge_hit.clear()
			return
	_end_action()


func _end_action() -> void:
	action = Action.WALK
	_attack_timer = ATTACK_GAPS[phase] * _rng.randf_range(0.8, 1.2)


func _fireball(p: Vector2, dir: Vector2, speed: float) -> void:
	Audio.play(&"fireball")
	world.projectiles.spawn(p + Vector2(0, -24), dir * speed, FIREBALL_DAMAGE, 5.0, 4.0,
		ProjectileSim.Team.ENEMY, -1, ProjectileSim.Look.FIRE)


func _summon(count: int) -> void:
	var type_id := world.horde.type_index(&"swarmer")
	var center := position
	for k in count:
		var spot := world.grid.nearest_open(center + Vector2.from_angle(TAU * k / count) * 44.0)
		world.horde.spawn(type_id, spot, _add_hp_multiplier)
		world.fx.ring(spot, 10.0, Color(0.8, 0.3, 1.0), 0.4)


func _nearest_hero(p: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for hero in world.heroes:
		if hero.is_downed():
			continue
		var d := hero.position.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = hero.position
	return best


func _update_sprite() -> void:
	var frame := int(_anim * 4.0) % 2
	if action == Action.WINDUP:
		frame = 2
	elif action == Action.CHARGE:
		frame = 3
	sprite.frame = frame
	var flash := world.horde.flash[_index] > 0.0
	sprite.modulate = Color(3, 3, 3) if flash else (Color(1.3, 0.8, 0.8) if phase == Phase.THREE else Color.WHITE)


func _die() -> void:
	_dead = true
	world.shake(6.0)
	for k in 6:
		world.fx.disc(position + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-30, 0)), 24.0,
			Color(1, 0.5, 0.2, 0.7), 0.5 + k * 0.1)
	world.fx.ring(position, 90.0, Color(1, 0.9, 0.5), 0.8)
	defeated.emit()
	queue_free()
