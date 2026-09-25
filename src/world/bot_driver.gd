class_name BotDriver
extends RefCounted
## Drives bot-controlled players (device DEVICE_BOT) for demos, screenshots and
## the stress test: wander around the group, aim around, dash now and then,
## and hold every ability button when `use_abilities` is set.

var world: World
var use_abilities := false
## Stress testing: each bot fires this many projectiles per second directly
## (stand-in for hero abilities until milestone 4).
var fire_rate := 0.0
var projectile_cap := 400
var _rng := RandomNumberGenerator.new()
var _targets: Dictionary = {}      # slot -> Vector2
var _retarget_in: Dictionary = {}  # slot -> float
var _time := 0.0
var _fire_budget: Dictionary = {}  # slot -> float


func _init(p_world: World, seed_value: int = 7) -> void:
	world = p_world
	_rng.seed = seed_value


## Adds up to `count` bot players in free slots. Returns the slots used.
static func add_bots(count: int) -> Array[int]:
	var slots: Array[int] = []
	for i in count:
		var slot := InputRouter.free_slot()
		if slot == -1:
			break
		InputRouter.assign(slot, PlayerInput.DEVICE_BOT)
		slots.append(slot)
	return slots


## Call after InputRouter polled and before heroes tick.
func tick(delta: float) -> void:
	_time += delta
	var center := world.camera.target
	for hero in world.heroes:
		var input := hero.input
		if not input.is_bot():
			continue
		var slot := hero.slot
		_retarget_in[slot] = float(_retarget_in.get(slot, 0.0)) - delta
		if _retarget_in[slot] <= 0.0 or not _targets.has(slot):
			_retarget_in[slot] = _rng.randf_range(1.0, 2.5)
			var offset := Vector2(_rng.randf_range(-120, 120), _rng.randf_range(-70, 70))
			_targets[slot] = world.grid.nearest_open(center + offset)
		var to_target: Vector2 = _targets[slot] - hero.position
		input.move = to_target.normalized() if to_target.length() > 6.0 else Vector2.ZERO
		var enemy := world.horde.nearest(hero.position, 160.0)
		if enemy != -1:
			input.aim = (world.horde.pos[enemy] - hero.position).normalized()
		else:
			input.aim = Vector2.from_angle(_time * (1.0 + slot * 0.37) + slot)
		input.aim_active = true
		input.set_action(PlayerInput.Action.MOVEMENT, _rng.randf() < 0.01)
		input.set_action(PlayerInput.Action.ATTACK, use_abilities)
		input.set_action(PlayerInput.Action.SPECIAL, use_abilities and enemy != -1 and _rng.randf() < 0.05)
		input.set_action(PlayerInput.Action.ULTIMATE, use_abilities and enemy != -1 and _rng.randf() < 0.02)
		if fire_rate > 0.0:
			_fire(hero, delta)


func _fire(hero: Hero, delta: float) -> void:
	var budget: float = _fire_budget.get(hero.slot, 0.0) + fire_rate * delta
	var target := world.horde.nearest(hero.position, 200.0)
	while budget >= 1.0 and world.projectiles.count < projectile_cap:
		budget -= 1.0
		var dir := Vector2.from_angle(_rng.randf() * TAU)
		if target != -1 and _rng.randf() < 0.7:
			dir = (world.horde.pos[target] - hero.position).normalized().rotated(_rng.randf_range(-0.2, 0.2))
		world.projectiles.spawn(hero.position + Vector2(0, -6), dir * 220.0, 4.0, 3.0, 1.6,
			ProjectileSim.Team.PLAYER, hero.slot, ProjectileSim.Look.ARROW, 1, 30.0)
	_fire_budget[hero.slot] = minf(budget, 5.0)
