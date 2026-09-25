extends "res://tests/test_case.gd"
## Level data sanity + the arena / exit / boss objective flow, headless.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0


func _build(data: LevelData) -> Level:
	var level := Level.new()
	level.build(data)
	return level


func test_run_config_lists_the_run() -> void:
	var run := RunConfig.load_default()
	assert_eq(run.levels.size(), 4, "3 levels + boss")
	assert_true(run.levels[run.levels.size() - 1].is_boss_level, "run ends with the boss")


func test_every_level_is_connected_and_complete() -> void:
	for data in RunConfig.load_default().levels:
		var level := _build(data)
		var g := level.grid
		assert_false(level.player_spawns.is_empty(), "%s has a player spawn" % data.display_name)
		for room: int in level.room_cells:
			assert_true(level.room_doors.has(room), "%s arena %d has doors" % [data.display_name, room])
		if data.is_boss_level:
			assert_false(level.boss_spawns.is_empty(), "boss level has a boss spawn")
			assert_true(level.room_at_position(level.boss_spawns[0]) != 0, "boss spawns inside the arena")
		else:
			assert_false(level.exit_cells.is_empty(), "%s has an exit" % data.display_name)
			assert_true(data.arena_quotas.size() >= level.room_cells.size(), "quota per arena")
		# Every floor cell is reachable from the spawn (doors open).
		var start := g.cell_of(level.player_spawns[0])
		var seen := {start: true}
		var queue: Array[Vector2i] = [start]
		while not queue.is_empty():
			var c: Vector2i = queue.pop_back()
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := c + d
				if not seen.has(n) and not g.is_solid(n.x, n.y):
					seen[n] = true
					queue.append(n)
		var floor_cells := 0
		for y in g.height:
			for x in g.width:
				if not g.is_solid(x, y):
					floor_cells += 1
		assert_eq(seen.size(), floor_cells, "%s: all floor reachable" % data.display_name)
		level.free()


func _run_world(data: LevelData, heroes: Array[StringName]) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in heroes.size():
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = heroes[i]
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.run_mode = true
	world.level_ups_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	for hero in world.heroes:
		hero.god_mode = true
	return world


func _step(world: World, frames: int, kill_everything: bool = false) -> void:
	for f in frames:
		InputRouter._process(DT)
		world._process(DT)
		if kill_everything:
			for i in world.horde.count:
				if world.horde.t_behavior[world.horde.type[i]] != EnemyData.Behavior.BOSS:
					world.horde.damage(i, 99999.0, Vector2.ZERO, 0)


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	(Engine.get_main_loop() as SceneTree).paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


func test_arenas_lock_clear_and_open_the_exit() -> void:
	var data: LevelData = RunConfig.load_default().levels[0]
	var world := _run_world(data, [&"knight"])
	var director := world.director
	var hero := world.heroes[0]
	var completed := [false]
	world.level_completed.connect(func() -> void: completed[0] = true)
	assert_false(director.exit_open, "exit closed while arenas remain")
	for room in director.rooms:
		hero.position = world.grid.nearest_open(room.center)
		_step(world, 2)
		assert_eq(director.active_room, room, "arena %d activates" % room.id)
		var door: Vector2i = room.doors[0]
		assert_true(world.grid.is_solid(door.x, door.y), "doors lock")
		assert_eq(world.spawner.mode, SpawnDirector.Mode.ARENA)
		# Kill everything as it spawns until the quota is exhausted.
		for second in 90:
			_step(world, 30, true)
			if room.state == LevelDirector.RoomState.CLEARED:
				break
		assert_eq(room.state, LevelDirector.RoomState.CLEARED, "arena %d cleared" % room.id)
		assert_false(world.grid.is_solid(door.x, door.y), "doors reopen")
		assert_true(room.killed >= room.quota, "quota reached (%d/%d)" % [room.killed, room.quota])
	assert_true(director.exit_open, "exit opens after all arenas")
	hero.position = world.level.exit_center()
	_step(world, 90)
	assert_true(completed[0], "standing in the portal completes the level")
	_teardown(world)


func test_boss_fight_spawns_and_ends_the_run() -> void:
	var run := RunConfig.load_default()
	var data: LevelData = run.levels[run.levels.size() - 1]
	var world := _run_world(data, [&"mage", &"cleric"])
	var defeated := [false]
	world.boss_defeated.connect(func() -> void: defeated[0] = true)
	var room: LevelDirector.Room = world.director.rooms[0]
	for hero in world.heroes:
		hero.position = world.grid.nearest_open(room.center + Vector2(0, 60))
	_step(world, 2)
	assert_true(world.boss != null, "boss spawned when the team entered")
	_step(world, 240)  # let it attack for a few seconds
	var i := world.horde.index_of_uid(world.boss.uid)
	assert_true(i >= 0)
	world.horde.damage(i, 1e9, Vector2.ZERO, 0)
	_step(world, 3)
	assert_true(defeated[0], "boss_defeated emitted")
	assert_true(world.director.completed)
	_teardown(world)


func test_bots_can_finish_every_level() -> void:
	# Four god-mode bots with real abilities follow the objectives through the
	# whole run: arenas, exits and the boss. Checks navigation + objectives.
	var run := RunConfig.load_default()
	for index in run.levels.size():
		var data: LevelData = run.levels[index]
		var world := _run_world(data, [&"knight", &"ranger", &"mage", &"cleric"])
		world.bots = BotDriver.new(world, 11 + index)
		world.bots.use_abilities = true
		var done := [false]
		world.level_completed.connect(func() -> void: done[0] = true)
		world.boss_defeated.connect(func() -> void: done[0] = true)
		var seconds := 0
		while seconds < 600 and not done[0]:
			_step(world, 60)
			seconds += 1
			if OS.get_cmdline_user_args().has("--verbose") and seconds % 30 == 0:
				var d := world.director
				var states := []
				for r in d.rooms:
					states.append("%d:%d k%d/%d" % [r.id, r.state, r.killed, r.quota])
				print("%s t=%ds active=%s rooms=%s alive=%d obj=%s boss=%.2f" % [data.display_name, seconds,
					d.active_room.id if d.active_room else 0, states, world.horde.alive_count(), d.objective,
					world.boss.hp_ratio() if world.boss else -1.0])
		assert_true(done[0], "%s finished by bots (%d s, arenas %d/%d)" % [
			data.display_name, seconds, world.director.arenas_cleared(), world.director.rooms.size()])
		print("  %s: bots finished in %d s of game time" % [data.display_name, seconds])
		_teardown(world)
