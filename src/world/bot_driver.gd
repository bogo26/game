class_name BotDriver
extends RefCounted
## Drives bot-controlled players (device DEVICE_BOT) for demos, screenshots,
## automated playthroughs and the stress test. Bots path-find (A*) toward the
## level's current objective (next arena, exit, boss) or wander around the
## group, aim at the nearest enemy and use their abilities.

const RETARGET_MIN := 1.0
const RETARGET_MAX := 2.2
const WAYPOINT_REACHED := 6.0

var world: World
var use_abilities := false
## Head for the level objective instead of wandering around the group.
var follow_objective := true
## Stress testing: each bot also fires this many projectiles per second
## directly, on top of its abilities.
var fire_rate := 0.0
var projectile_cap := 400

var _rng := RandomNumberGenerator.new()
var _paths: Dictionary = {}        # slot -> PackedVector2Array of waypoints
var _retarget_in: Dictionary = {}  # slot -> float
var _time := 0.0
var _fire_budget: Dictionary = {}  # slot -> float
var _astar := AStarGrid2D.new()
var _astar_version := -1


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
	for hero in world.heroes:
		var input := hero.input
		if not input.is_bot():
			continue
		var slot := hero.slot
		_retarget_in[slot] = float(_retarget_in.get(slot, 0.0)) - delta
		if _retarget_in[slot] <= 0.0 or not _paths.has(slot):
			_retarget_in[slot] = _rng.randf_range(RETARGET_MIN, RETARGET_MAX)
			_paths[slot] = _plan_path(hero)
		var path: PackedVector2Array = _paths[slot]
		while not path.is_empty() and hero.position.distance_to(path[0]) < WAYPOINT_REACHED:
			path.remove_at(0)
		_paths[slot] = path  # packed arrays are copy-on-write: store the pruned path
		input.move = (path[0] - hero.position).normalized() if not path.is_empty() else Vector2.ZERO
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


func _plan_path(hero: Hero) -> PackedVector2Array:
	var goal := world.director.objective_target if follow_objective else Vector2.INF
	if not goal.is_finite():
		# Wander around the group.
		var offset := Vector2(_rng.randf_range(-100, 100), _rng.randf_range(-60, 60))
		goal = world.grid.nearest_open(world.camera.target + offset)
	else:
		goal = world.grid.nearest_open(goal + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-20, 20)))
	_sync_astar()
	var from := world.grid.cell_of(hero.position)
	var to := world.grid.cell_of(goal)
	if not _astar.is_in_boundsv(from) or not _astar.is_in_boundsv(to) or _astar.is_point_solid(to):
		return PackedVector2Array([goal])
	var cells := _astar.get_id_path(from, to, true)
	var path := PackedVector2Array()
	for i in range(1, cells.size()):
		path.append(LevelGrid.cell_center(cells[i]))
	if path.is_empty():
		path.append(goal)
	return path


func _sync_astar() -> void:
	var grid := world.grid
	if _astar_version == grid.version:
		return
	_astar_version = grid.version
	_astar.region = Rect2i(0, 0, grid.width, grid.height)
	_astar.cell_size = Vector2(LevelGrid.TILE, LevelGrid.TILE)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()  # no-op unless the region changed, so set every cell below
	for y in grid.height:
		for x in grid.width:
			_astar.set_point_solid(Vector2i(x, y), grid.is_solid(x, y))


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
