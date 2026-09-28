extends "res://tests/test_case.gd"
## Level data sanity + the arena / exit / boss objective flow, headless:
## levels 1-3, the mini boss, levels 4-6 and the final boss.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0


func _build(data: LevelData) -> Level:
	var level := Level.new()
	level.build(data)
	return level


func test_run_config_lists_the_run() -> void:
	var run := RunConfig.load_default()
	var titles: Array[String] = []
	for index in run.levels.size():
		titles.append(run.title(index))
	assert_eq(titles, ["LEVEL 1", "LEVEL 2", "LEVEL 3", "MINI BOSS", "LEVEL 4", "LEVEL 5", "LEVEL 6",
		"FINAL BOSS"] as Array[String], "1-2-3, the mini boss, 4-5-6, the final boss")
	var last := run.levels.size() - 1
	for index in run.levels.size():
		var data := run.levels[index]
		assert_eq(data.is_final_boss, index == last, "%s: only the last level is the final boss" % data.display_name)
		if index < run.alternates.size() and run.alternates[index]:
			var alternate := run.alternates[index]
			assert_eq(alternate.display_name, data.display_name, "a second layout is the same level")
			assert_eq(alternate.arena_quotas, data.arena_quotas, "%s: same quotas" % data.display_name)
			assert_eq(alternate.theme, data.theme, "%s: same theme" % data.display_name)
	assert_eq(run.levels[3].boss_scene, "res://src/enemies/boss/bone_colossus.tscn", "the mini boss")
	assert_eq(run.levels[last].boss_scene, "res://src/enemies/boss/boss_demon.tscn", "the final boss")
	for index in last:
		assert_true(run.levels[index + 1].hp_multiplier > run.levels[index].hp_multiplier,
			"%s is tougher than %s" % [run.levels[index + 1].display_name, run.levels[index].display_name])
	# The boss pools: three mini bosses and three final bosses, each in a level
	# of its own, as tough as the boss level it stands in for.
	var scenes := {3: [], last: []}
	for index: int in scenes:
		for data in run.choices(index):
			assert_true(data.is_boss_level, "%s is a boss level" % data.display_name)
			assert_eq(data.is_final_boss, index == last, "%s: in the right pool" % data.display_name)
			assert_eq(data.hp_multiplier, run.levels[index].hp_multiplier, "%s: as tough as %s"
				% [data.display_name, run.levels[index].display_name])
			assert_eq(data.boss_hp_multiplier, run.levels[index].boss_hp_multiplier, "%s: its boss too"
				% data.display_name)
			scenes[index].append(data.boss_scene.get_file().get_basename())
	assert_eq(scenes[3], ["bone_colossus", "toadstool_tyrant", "mire_serpent"], "the mini bosses")
	assert_eq(scenes[last], ["boss_demon", "spore_mother", "frost_queen"], "the final bosses")
	assert_eq(run.choices(0).size(), 1, "a regular level is just itself")


func test_every_level_is_connected_and_complete() -> void:
	# Every layout a run can pick, in every way it can be mirrored.
	for base in RunConfig.load_default().all_layouts():
		for flips: Array in [[false, false], [true, false], [false, true], [true, true]]:
			if flips[1] and base.is_boss_level:
				continue  # the boss level only mirrors left-right
			var data := base.mirrored(flips[0], flips[1])
			data.display_name = "%s (%s%s)" % [base.resource_path.get_file(), "h" if flips[0] else "",
				"v" if flips[1] else ""]
			_check_level(data)


func test_mirroring_moves_everything_consistently() -> void:
	var data: LevelData = RunConfig.load_default().levels[0]
	var plain := _build(data)
	var flipped := _build(data.mirrored(true, true))
	assert_eq(flipped.grid.width, plain.grid.width)
	assert_eq(flipped.grid.height, plain.grid.height)
	assert_eq(flipped.room_cells.size(), plain.room_cells.size(), "same arenas")
	assert_eq(flipped.props.size(), plain.props.size(), "same props")
	var p := plain.grid.cell_of(plain.player_spawns[0])
	var q := flipped.grid.cell_of(flipped.player_spawns[0])
	assert_eq(q, Vector2i(plain.grid.width - 1 - p.x, plain.grid.height - 1 - p.y), "the spawn moved to the mirrored cell")
	plain.free()
	flipped.free()


func test_runs_pick_their_layouts_from_the_seed() -> void:
	var run := RunConfig.load_default()
	var a := run.layout_for(0, 12345).layout
	assert_eq(run.layout_for(0, 12345).layout, a, "the same seed gives the same level")
	var different := false
	for seed_value in range(1, 40):
		if run.layout_for(0, seed_value).layout != a:
			different = true
	assert_true(different, "other runs get other layouts")
	var met := {}
	for seed_value in range(1, 40):
		for index in run.levels.size():
			var picked := run.layout_for(index, seed_value)
			assert_eq(picked.is_boss_level, run.levels[index].is_boss_level, "boss levels stay boss levels")
			assert_eq(picked.is_final_boss, run.levels[index].is_final_boss, "and the final boss stays last")
			var names: Array[String] = []
			for data in run.choices(index):
				names.append(data.display_name)
			assert_true(picked.display_name in names, "every level stays itself (or its boss's pool)")
			met[picked.display_name] = true
	for data in run.boss_pool:
		assert_true(met.has(data.display_name), "runs meet %s too" % data.display_name)


func _check_level(data: LevelData) -> void:
	var level := _build(data)
	var g := level.grid
	assert_false(level.player_spawns.is_empty(), "%s has a player spawn" % data.display_name)
	for room: int in level.room_cells:
		assert_true(level.room_doors.has(room), "%s arena %d has doors" % [data.display_name, room])
	if data.is_boss_level:
		assert_false(level.boss_spawns.is_empty(), "boss level has a boss spawn")
		assert_eq(level.room_cells.size(), 1, "%s: the boss room is its only arena" % data.display_name)
		assert_true(level.room_at_position(level.boss_spawns[0]) != 0, "boss spawns inside the arena")
		var boss := (load(data.boss_scene) as PackedScene).instantiate()
		assert_true(boss is Boss, "%s: its boss is a Boss" % data.display_name)
		boss.free()
		# Beating a mini boss opens the exit behind its room; the final boss's level has none.
		assert_eq(level.exit_cells.is_empty(), data.is_final_boss, "%s: an exit unless it's the final boss"
			% data.display_name)
	else:
		assert_false(level.exit_cells.is_empty(), "%s has an exit" % data.display_name)
		assert_true(data.arena_quotas.size() >= level.room_cells.size(), "quota per arena")
	for cell in level.exit_cells:
		assert_eq(level.room_of_cell[cell.y * g.width + cell.x], 0, "%s: the exit isn't in an arena"
			% data.display_name)
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
	# With its doors shut an arena is sealed: walking from inside never
	# leaves it (so the fight can't leak out and the room outline is right).
	for room: int in level.room_cells:
		var doors: Array = level.room_doors.get(room, [])
		var inside: Vector2i = Vector2i(-1, -1)
		for c: Vector2i in level.room_cells[room]:
			if not g.is_solid(c.x, c.y):
				inside = c
				break
		var reached := {inside: true}
		var todo: Array[Vector2i] = [inside]
		var leaked := false
		while not todo.is_empty():
			var c: Vector2i = todo.pop_back()
			for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n := c + d
				if reached.has(n) or g.is_solid(n.x, n.y) or n in doors:
					continue
				reached[n] = true
				todo.append(n)
				if level.room_of_cell[n.y * g.width + n.x] != room:
					leaked = true
		assert_false(leaked, "%s: arena %d is sealed by its doors" % [data.display_name, room])
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
	assert_eq(world.director.objective, "Enter the throne room")
	for hero in world.heroes:
		hero.position = world.grid.nearest_open(room.center + Vector2(0, 60))
	_step(world, 2)
	assert_true(world.boss is BossDemon, "the Demon Lord spawned when the team entered")
	assert_eq(world.director.objective, "Defeat the Demon Lord!")
	_step(world, 240)  # let it attack for a few seconds
	var i := world.horde.index_of_uid(world.boss.uid)
	assert_true(i >= 0)
	world.horde.damage(i, 1e9, Vector2.ZERO, 0)
	_step(world, 3)
	assert_true(defeated[0], "boss_defeated emitted")
	assert_true(world.director.completed)
	assert_eq(world.director.objective, "The Demon Lord is slain!", "the run is won: no more objectives")
	assert_false(world.director.exit_open)
	_teardown(world)


func test_the_mini_boss_opens_the_way_on() -> void:
	var run := RunConfig.load_default()
	var data: LevelData = run.levels[3]
	var world := _run_world(data, [&"knight", &"ranger"])
	var won := [false]
	var slain: Array[String] = []
	var completed := [false]
	world.boss_defeated.connect(func() -> void: won[0] = true)
	world.director.mini_boss_defeated.connect(func(boss_name: String) -> void: slain.append(boss_name))
	world.level_completed.connect(func() -> void: completed[0] = true)
	var director := world.director
	var room: LevelDirector.Room = director.rooms[0]
	assert_eq(director.objective, "Enter the ossuary")
	assert_false(director.exit_open, "the way on is shut behind the boss")
	for hero in world.heroes:
		hero.position = world.grid.nearest_open(room.center + Vector2(0, 60))
	_step(world, 2)
	assert_true(world.boss is BoneColossus, "the Bone Colossus spawned when the team entered")
	assert_eq(director.objective, "Defeat the Bone Colossus!")
	assert_false(world.picks_held(), "picks don't wait for a boss fight")
	var door: Vector2i = room.doors[0]
	assert_true(world.grid.is_solid(door.x, door.y), "the doors lock for the fight")
	_step(world, 240)  # let it attack for a few seconds
	var i := world.horde.index_of_uid(world.boss.uid)
	world.horde.damage(i, 1e9, Vector2.ZERO, 0)
	_step(world, 3)
	assert_eq(slain, ["Bone Colossus"] as Array[String], "mini_boss_defeated emitted once")
	assert_false(won[0], "a mini boss doesn't end the run")
	assert_false(director.completed)
	assert_eq(room.state, LevelDirector.RoomState.CLEARED, "its room is cleared")
	assert_false(world.grid.is_solid(door.x, door.y), "the doors open")
	assert_true(director.exit_open, "and so does the exit")
	assert_eq(director.objective, "Reach the exit portal")
	for hero in world.heroes:
		hero.position = world.level.exit_center()
	_step(world, 150)  # the boss's death froze time for a moment; then a second in the portal
	assert_true(completed[0], "the portal takes the team on to level 4")
	_teardown(world)


func test_a_boss_is_tougher_than_its_level() -> void:
	# The boss level's boss_hp_multiplier goes to its boss alone: the servants
	# it calls get the level's HP like every other enemy there.
	var data: LevelData = RunConfig.load_default().levels[3]
	assert_true(data.boss_hp_multiplier > 1.0, "the boss is the level's big fight")
	var world := _run_world(data, [&"knight", &"ranger"])
	var room: LevelDirector.Room = world.director.rooms[0]
	for hero in world.heroes:
		hero.position = world.grid.nearest_open(room.center + Vector2(0, 60))
	_step(world, 2)
	var spawner := world.spawner
	var base := world.horde.types[world.horde.type_index(world.boss.body_type)].max_hp
	assert_near(world.boss.max_hp, base * spawner.unique_hp_multiplier() * data.boss_hp_multiplier, 0.01,
		"its own HP, the level's, the team's and the boss multiplier")
	assert_near(world.boss._add_hp_multiplier, spawner.effective_hp_multiplier(), 0.0001,
		"its servants only get the level's")
	_teardown(world)


func test_bots_can_finish_every_level() -> void:
	# Four god-mode bots with real abilities follow the objectives through the
	# whole run: arenas, exits and the boss - and through every second layout,
	# mirrored both ways. Checks navigation + objectives.
	var run := RunConfig.load_default()
	var playthroughs: Array[LevelData] = []
	playthroughs.append_array(run.levels)
	for alternate in run.alternates:
		if alternate:
			var mirrored := alternate.mirrored(true, true)
			mirrored.display_name += " (second layout, mirrored)"
			playthroughs.append(mirrored)
	for boss in run.boss_pool:
		var mirrored := boss.mirrored(true, false)
		mirrored.display_name += " (mirrored)"
		playthroughs.append(mirrored)
	for index in playthroughs.size():
		var data: LevelData = playthroughs[index]
		var world := _run_world(data, [&"knight", &"ranger", &"mage", &"cleric"])
		world.bots = BotDriver.new(world, 11 + index)
		world.bots.use_abilities = true
		var done := [false]
		world.level_completed.connect(func() -> void: done[0] = true)
		world.boss_defeated.connect(func() -> void: done[0] = true)
		# Walking straight from objective to objective, they never let the
		# keep-moving clock run out (LevelDirector.RESTLESS_AFTER).
		var restless := [0]
		world.director.restless_changed.connect(func(stage: int) -> void: restless[0] = maxi(restless[0], stage))
		var longest_walk := 0.0
		var seconds := 0
		while seconds < 600 and not done[0]:
			_step(world, 60)
			seconds += 1
			if world.director.clock_running():
				longest_walk = maxf(longest_walk, world.director.clock_length - world.director.restless_in)
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
		assert_eq(restless[0], 0, "%s: bots reach every objective in time (longest walk %d s)" % [
			data.display_name, roundi(longest_walk)])
		print("  %s: bots finished in %d s of game time (longest walk between objectives %d s)" % [
			data.display_name, seconds, roundi(longest_walk)])
		_teardown(world)
