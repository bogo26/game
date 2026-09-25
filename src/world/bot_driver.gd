class_name BotDriver
extends RefCounted
## Drives bot-controlled players (device DEVICE_BOT) for demos, screenshots and
## the stress test: wander around the group, aim around, dash now and then,
## and hold every ability button when `use_abilities` is set.

var world: World
var use_abilities := false
var _rng := RandomNumberGenerator.new()
var _targets: Dictionary = {}      # slot -> Vector2
var _retarget_in: Dictionary = {}  # slot -> float
var _time := 0.0


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
		input.aim = Vector2.from_angle(_time * (1.0 + slot * 0.37) + slot)
		input.aim_active = true
		input.set_action(PlayerInput.Action.MOVEMENT, _rng.randf() < 0.01)
		input.set_action(PlayerInput.Action.ATTACK, use_abilities)
		input.set_action(PlayerInput.Action.SPECIAL, use_abilities and _rng.randf() < 0.05)
		input.set_action(PlayerInput.Action.ULTIMATE, use_abilities and _rng.randf() < 0.01)
