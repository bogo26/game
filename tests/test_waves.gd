extends "res://tests/test_case.gd"
## Endless Waves: every wave harder than the last, the horde's mix, The Pit,
## the wave loop (breaks, clears, stragglers, held picks), boss waves every
## 5th wave, the best-wave records, the screens, and bots holding out.

const WORLD_SCENE := "res://src/world/world.tscn"
const GAME_SCENE := "res://src/main/game.tscn"
const SELECT_SCENE := "res://src/ui/character_select.tscn"
const END_SCENE := "res://src/ui/end_screen.tscn"
const DT := 1.0 / 60.0
const MINIS: Array[String] = ["mini_a", "mini_b", "mini_c"]
const FINALS: Array[String] = ["final_a", "final_b", "final_c"]

## A small arena; the right-hand B is nearer the spawn than the left one.
const PIT := """
############################
#11111111111111111111111111#
#11111111111111111111111111#
#1B11111111111P11111111B111#
#11111111111111111111111111#
#11111111111111111111111111#
############################
"""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _pit() -> LevelData:
	var d := LevelData.new()
	d.display_name = "Wave test"
	d.layout = PIT
	d.corridor_spawn_rate = 0.0
	d.arena_quotas = PackedInt32Array([0])
	return d


## A World playing Endless Waves in `data` (the small PIT by default) from
## wave `start`, with god-mode heroes that stand still.
func _wave_world(start: int = 1, heroes: Array[StringName] = [&"knight"], data: LevelData = null) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	GameState.difficulty = GameState.Difficulty.NORMAL
	GameState.run_seed = 1234
	GameState.wave = start - 1
	for i in heroes.size():
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = heroes[i]
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data if data else _pit()
	world.run_mode = true
	world.wave_mode = true
	world.level_ups_enabled = false
	_tree().root.add_child(world)
	world.bots = null
	for hero in world.heroes:
		hero.god_mode = true
	return world


func _teardown(node: Node) -> void:
	node.get_parent().remove_child(node)
	node.free()
	_tree().paused = false
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.mode = GameState.Mode.RUN
	GameState.difficulty = GameState.Difficulty.NORMAL
	GameState.reset_run()
	GameState.run_active = false


func _step(world: World, seconds: float) -> void:
	for f in int(round(seconds / DT)):
		InputRouter._process(DT)
		world._process(DT)


## Every enemy (not props, not the boss) dies.
func _kill_all(world: World) -> void:
	var horde := world.horde
	for i in horde.count:
		var behavior := horde.t_behavior[horde.type[i]]
		if horde.hp[i] > 0.0 and behavior != EnemyData.Behavior.OBJECT and behavior != EnemyData.Behavior.NEST \
				and behavior != EnemyData.Behavior.BOSS:
			horde.damage(i, 99999.0, Vector2.ZERO, 0)


## Steps until the current wave is cleared, killing everything twice a second.
func _fight_out(world: World, limit: float = 60.0) -> float:
	var director := world.director as WaveDirector
	var t := 0.0
	while t < limit and director.phase == WaveDirector.Phase.FIGHT:
		_step(world, 0.5)
		_kill_all(world)
		t += 0.5
	return t


# --- the numbers ------------------------------------------------------------------------------

func test_every_wave_is_harder_than_the_last() -> void:
	var first := WaveDirector.settings(1, 1, 7, MINIS, FINALS)
	assert_eq(first.quota, WaveDirector.QUOTA_BASE)
	assert_eq(first.weights, {&"swarmer": 1.0}, "wave 1 is swarmers only")
	assert_near(first.hp, 1.0)
	assert_eq(first.elite_chance, 0.0, "no elites at first")
	var last := first
	var last_regular := first
	for n in range(2, 41):
		var w := WaveDirector.settings(n, 1, 7, MINIS, FINALS)
		assert_true(w.hp > last.hp, "wave %d: tougher enemies" % n)
		assert_true(w.rate >= last.rate and w.damage >= last.damage and w.elite_chance >= last.elite_chance,
			"wave %d: never easier" % n)
		assert_eq(w.is_boss(), n % 5 == 0, "wave %d: a boss every 5th wave" % n)
		if not w.is_boss():
			assert_true(w.quota > last_regular.quota or w.quota == last_regular.quota and w.quota >= 300,
				"wave %d: more enemies (up to the cap)" % n)
			last_regular = w
		last = w
	assert_near(WaveDirector.settings(20, 1, 7, MINIS, FINALS).hp, 3.185, 0.001,
		"wave 20 is about as tough as the final boss's level (x3.2)")
	assert_true(WaveDirector.settings(30, 1, 7, MINIS, FINALS).hp > 6.0, "after that it climbs faster")
	assert_eq(WaveDirector.settings(10, 4, 7, MINIS, FINALS).quota,
		int(round(WaveDirector.settings(10, 1, 7, MINIS, FINALS).quota * 2.2)), "more players, bigger waves")


func test_bosses_come_every_fifth_wave() -> void:
	var kinds: Array[String] = []
	var minis: Array[String] = []
	var finals: Array[String] = []
	for n: int in [5, 10, 15, 20, 25, 30]:
		var scene := WaveDirector.settings(n, 1, 99, MINIS, FINALS).boss_scene
		kinds.append("mini" if scene in MINIS else ("final" if scene in FINALS else "?"))
		(minis if scene in MINIS else finals).append(scene)
	assert_eq(kinds, ["mini", "final", "mini", "final", "mini", "final"] as Array[String])
	minis.sort()
	finals.sort()
	assert_eq(minis, MINIS, "all three mini bosses before any comes back")
	assert_eq(finals, FINALS, "and all three final bosses")
	var orders := {}
	for seed_value in 8:
		orders[WaveDirector.settings(5, 1, seed_value, MINIS, FINALS).boss_scene] = true
	assert_true(orders.size() > 1, "which comes first changes from game to game")
	# The real bosses come from the run's levels and boss pools.
	var real_minis := WaveDirector.boss_scenes(false)
	var real_finals := WaveDirector.boss_scenes(true)
	assert_eq(real_minis.size(), 3)
	assert_eq(real_finals.size(), 3)
	assert_true("res://src/enemies/boss/bone_colossus.tscn" in real_minis)
	assert_true("res://src/enemies/boss/frost_queen.tscn" in real_finals)


func test_the_horde_grows_and_features_every_level_enemy() -> void:
	var known := {}
	for path in World.ENEMY_TYPES:
		known[(load(path) as EnemyData).id] = true
	var seen := {}
	for n in range(1, 17):
		var w := WaveDirector.settings(n, 1, 99, MINIS, FINALS)
		for id: StringName in w.weights:
			assert_true(known.has(id), "wave %d: %s is an enemy" % [n, id])
		for id in WaveDirector.featured(n, 99):
			seen[id] = true
	assert_eq(seen.size(), WaveDirector.FEATURED.size(), "every level enemy has had its wave by wave 16")
	var w2 := WaveDirector.settings(2, 1, 99, MINIS, FINALS)
	assert_true(w2.weights.has(&"brute") and not w2.weights.has(&"spitter"), "brutes first, spitters later")
	assert_true(WaveDirector.settings(4, 1, 99, MINIS, FINALS).weights.has(&"exploder"), "exploders from wave 4")
	var late := WaveDirector.settings(41, 1, 99, MINIS, FINALS)
	assert_near(late.weights[&"brute"], 0.25, 0.0001, "brutes top out")
	assert_eq(WaveDirector.settings(40, 1, 99, MINIS, FINALS).weights, {&"swarmer": 1.0},
		"a boss wave spawns nothing of its own: the boss calls its servants")
	assert_eq(WaveDirector.featured(1, 99).size(), 0)
	assert_eq(WaveDirector.featured(5, 99).size(), 0, "a boss wave brings its own")
	assert_eq(WaveDirector.featured(11, 99).size(), 1)
	assert_eq(WaveDirector.featured(12, 99).size(), 2, "two level enemies from wave 12")
	assert_eq(WaveDirector.featured(24, 99).size(), 3, "three from wave 24")
	assert_eq(WaveDirector.featured(12, 99)[1], WaveDirector.featured(11, 99)[0], "the last wave's stays on")
	var first_three := {}
	for seed_value in 6:
		first_three[str(WaveDirector.featured(2, seed_value) + WaveDirector.featured(3, seed_value))] = true
	assert_true(first_three.size() > 1, "the order changes from game to game")


# --- The Pit ----------------------------------------------------------------------------------

func test_the_pit_is_one_sealed_arena() -> void:
	var data := load(WaveDirector.ARENA_PATH) as LevelData
	assert_false(data.layout.contains(":"), "no chasms: flyers could hover out of reach over one")
	for flips: Array in [[false, false], [true, true]]:
		var level := Level.new()
		level.build(data.mirrored(flips[0], flips[1]))
		var g := level.grid
		assert_eq(level.room_cells.size(), 1, "one arena")
		assert_true(level.door_cells.is_empty() and level.exit_cells.is_empty(), "no doors, no exit")
		assert_false(level.player_spawns.is_empty())
		for p in level.player_spawns:
			assert_eq(level.room_at_position(p), 1, "the team starts inside")
		assert_true(level.boss_spawns.size() >= 2, "bosses have spots to come in at")
		for p in level.boss_spawns:
			assert_eq(level.room_at_position(p), 1, "inside too")
		for prop in level.props:
			assert_true(prop.kind == &"barrel" or prop.kind == &"urn", "no nests, chests or shrines (%s)" % prop.kind)
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
					assert_eq(level.room_of_cell[y * g.width + x], 1, "every floor cell is the arena's")
		assert_eq(seen.size(), floor_cells, "all of it reachable")
		level.free()
	var themes := {}
	for seed_value in 60:
		var arena := WaveDirector.arena_for(seed_value)
		assert_eq(arena.display_name, "The Pit")
		themes[arena.theme] = true
	assert_true(themes.size() >= 8, "games wear different themes (%d seen)" % themes.size())
	for theme in WaveDirector.THEMES:
		assert_true(ResourceLoader.exists(Level.TILE_SHEET % theme), "%s has a tile sheet" % theme)


# --- the wave loop ----------------------------------------------------------------------------

func test_a_wave_comes_is_cleared_and_the_next_follows() -> void:
	var world := _wave_world()
	var director := world.director as WaveDirector
	var cleared := [0]
	director.arena_cleared.connect(func(_id: int) -> void: cleared[0] += 1)
	assert_eq(director.phase, WaveDirector.Phase.BREAK)
	assert_eq(director.objective, "Get ready!  Wave 1 in 4")
	assert_eq(world.spawner.mode, SpawnDirector.Mode.OFF, "nothing comes during the break")
	_step(world, WaveDirector.FIRST_BREAK - 0.5)
	assert_eq(director.objective, "Get ready!  Wave 1 in 1", "the countdown")
	_step(world, 0.6)
	assert_eq(director.phase, WaveDirector.Phase.FIGHT)
	assert_eq(GameState.wave, 1)
	assert_eq(world.spawner.mode, SpawnDirector.Mode.ARENA)
	assert_eq(director.enemies_left(), WaveDirector.QUOTA_BASE, "the whole wave is still to beat")
	assert_eq(director.objective, "Wave 1  -  %d left" % WaveDirector.QUOTA_BASE)
	assert_eq(director.room.state, LevelDirector.RoomState.ACTIVE)
	assert_eq(world.hud._callout_label.text, "WAVE 1")
	var t := _fight_out(world)
	assert_eq(director.phase, WaveDirector.Phase.BREAK, "cleared in %.1f s" % t)
	assert_eq(cleared[0], 1, "the XP vacuum and the pick delay come with it")
	assert_eq(director.room.state, LevelDirector.RoomState.CLEARED)
	assert_eq(world.spawner.mode, SpawnDirector.Mode.OFF)
	var hearts := 0
	for i in world.pickups.count:
		hearts += 1 if world.pickups.kind[i] == PickupSim.Kind.HEART else 0
	assert_true(hearts >= 1, "a heart for the team")
	assert_eq(world.hud._callout_label.text, "WAVE 1 CLEARED")
	assert_true(director.objective.begins_with("Wave 1 cleared!  Wave 2 in "), director.objective)
	_step(world, WaveDirector.BREAK_TIME + 0.1)
	assert_eq(GameState.wave, 2, "and the next wave comes")
	assert_eq(director.wave.quota, WaveDirector.QUOTA_BASE + WaveDirector.QUOTA_PER_WAVE, "a bigger one")
	assert_near(world.spawner.level_hp_multiplier, director.wave.hp, 0.0001, "with tougher enemies")
	_teardown(world)


func test_the_last_few_are_pointed_out_and_stragglers_dont_stall_the_game() -> void:
	var world := _wave_world()
	var director := world.director as WaveDirector
	_step(world, WaveDirector.FIRST_BREAK + 0.1)
	var t := 0.0
	while t < 10.0 and (world.spawner.arena_remaining > 0 or world.spawner.pending_count() > 0):
		_step(world, 0.25)
		t += 0.25
	assert_eq(world.spawner.arena_remaining + world.spawner.pending_count(), 0, "the whole wave came in")
	# All but two die; nobody goes after the last two.
	var spared := 0
	for i in world.horde.count:
		if world.horde.hp[i] <= 0.0 or not world.horde.is_mobile(i) or world.horde.is_object(i):
			continue
		if spared < 2:
			spared += 1
		else:
			world.horde.damage(i, 99999.0, Vector2.ZERO, 0)
	_step(world, 0.5)
	assert_eq(director.enemies_left(), 2)
	assert_true(director.objective_target.is_finite(), "the arrow points at one of the last few")
	_step(world, WaveDirector.STRAGGLER_TIME - 2.0)
	assert_eq(director.phase, WaveDirector.Phase.FIGHT, "they get a while")
	_step(world, 3.0)
	assert_eq(director.phase, WaveDirector.Phase.BREAK, "then the wave counts as cleared")
	assert_eq(world.horde.enemy_count(), 2, "and they stay in the fight")
	_teardown(world)


func test_picks_wait_for_the_break() -> void:
	var world := _wave_world()
	var director := world.director as WaveDirector
	GameState.pending_level_ups = 0
	GameState.add_xp(GameState.xp_to_next())  # a level-up
	assert_true(world.can_open_pick_round(), "in the break it opens at once")
	_step(world, WaveDirector.FIRST_BREAK + 0.1)
	assert_true(world.picks_held(), "held during the wave")
	assert_false(world.can_open_pick_round())
	GameState.add_treasure_pick()
	assert_true(world.can_open_pick_round(), "a treasure round still opens")
	GameState.pop_round()
	director._clear_wave()
	assert_false(world.picks_held())
	assert_true(world.can_open_pick_round(), "the wave is over")
	assert_true(world.level_up_delay >= World.PICKS_AFTER_CLEAR - 0.001, "after a short moment")
	_teardown(world)


# --- boss waves -------------------------------------------------------------------------------

func test_boss_waves() -> void:
	for start: int in [5, 10]:
		var world := _wave_world(start)
		var director := world.director as WaveDirector
		var slain: Array[String] = []
		director.mini_boss_defeated.connect(func(boss_name: String) -> void: slain.append(boss_name))
		var won := [false]
		world.boss_defeated.connect(func() -> void: won[0] = true)
		GameState.team_lives = 0  # spent
		var treasures := GameState.pending_treasures
		assert_eq(director.objective, "Get ready!  Boss wave in 4")
		_step(world, WaveDirector.FIRST_BREAK + 0.1)
		assert_true(director.wave.is_boss(), "wave %d is a boss wave" % start)
		assert_eq(world.spawner.mode, SpawnDirector.Mode.OFF, "the boss brings its own")
		assert_true(world.boss == null, "it's still in its portal")
		assert_false(world.picks_held(), "picks open at once in a boss fight")
		_step(world, WaveDirector.BOSS_PORTAL_TIME + 0.1)
		assert_true(world.boss != null, "wave %d: the boss stepped out" % start)
		var pool := WaveDirector.boss_scenes(start == 10)
		assert_true(director.wave.boss_scene in pool, "a %s boss" % ("final" if start == 10 else "mini"))
		var team := world.heroes[0].position
		var furthest := world.level.boss_spawns[0]
		for p in world.level.boss_spawns:
			if p.distance_to(team) > furthest.distance_to(team):
				furthest = p
		assert_true(world.boss.position.distance_to(furthest) < 24.0, "at the B furthest from the team")
		assert_near(world.spawner.level_hp_multiplier, director.wave.hp, 0.0001, "as tough as its wave")
		_step(world, 2.0)
		_kill_boss(world, slain)
		assert_eq(slain.size(), 1, "wave %d: the boss is slain" % start)
		assert_false(won[0], "and the game goes on")
		assert_eq(director.phase, WaveDirector.Phase.BREAK)
		assert_eq(GameState.next_round(), GameState.LEGENDARY_ROUND, "wave %d: a legendary round first" % start)
		assert_eq(GameState.pending_rounds[1], GameState.TREASURE_ROUND, "then a bonus pick for everyone")
		assert_eq(GameState.pending_treasures, treasures + 1)
		assert_eq(GameState.team_lives, GameState.lives_per_level(), "the team's lives are back")
		_step(world, WaveDirector.BREAK_TIME)
		assert_eq(GameState.wave, start + 1)
		assert_false(director.wave.is_boss())
		_teardown(world)


func test_legendary_rounds_stop_once_every_legendary_is_taken() -> void:
	var world := _wave_world(5)
	var hero := world.heroes[0]
	var offers := world.upgrade_pool.legendary_offers(hero.hero_id, hero.upgrade_stacks)
	assert_eq(offers.size(), 3, "a hero has three legendaries")
	hero.apply_upgrade(offers[0], false)
	hero.apply_upgrade(offers[1], false)
	assert_true(world.legendaries_left(), "one left")
	GameState.pending_rounds.clear()
	world._on_mini_boss_defeated("Test Boss")
	assert_eq(GameState.next_round(), GameState.LEGENDARY_ROUND, "so a boss still brings a round")
	hero.apply_upgrade(offers[2], false)
	assert_false(world.legendaries_left(), "all three taken")
	GameState.pending_rounds.clear()
	var slain: Array[String] = []
	world.director.mini_boss_defeated.connect(func(boss_name: String) -> void: slain.append(boss_name))
	_step(world, WaveDirector.FIRST_BREAK + WaveDirector.BOSS_PORTAL_TIME + 0.2)
	_kill_boss(world, slain)
	assert_eq(slain.size(), 1, "the boss is slain")
	assert_false(GameState.pending_rounds.has(GameState.LEGENDARY_ROUND), "no empty legendary round")
	assert_eq(GameState.next_round(), GameState.TREASURE_ROUND, "just the bonus pick")
	_teardown(world)


## Kills the boss (once it can be hit) and lets its death play out.
func _kill_boss(world: World, slain: Array[String]) -> void:
	var t := 0.0
	while slain.is_empty() and t < 10.0:  # (the Mire Serpent can't be hit while it's under)
		if world.boss:
			world.horde.damage(world.horde.index_of_uid(world.boss.uid), 1e9, Vector2.ZERO, 0)
		_step(world, 0.5)
		t += 0.5
	_step(world, 2.0)


# --- records and screens ----------------------------------------------------------------------

func test_best_waves_are_kept_per_difficulty() -> void:
	var p := Profile.new()
	var news := p.record_waves(GameState.Difficulty.NORMAL, 7)
	assert_true(news["best_wave"], "the first game is a best")
	assert_eq(p.best_wave[GameState.Difficulty.NORMAL], 7)
	news = p.record_waves(GameState.Difficulty.NORMAL, 5)
	assert_false(news["best_wave"], "not as far: the record stands")
	assert_eq(p.best_wave[GameState.Difficulty.NORMAL], 7)
	assert_true(p.record_waves(GameState.Difficulty.CASUAL, 3)["best_wave"], "each difficulty has its own")
	assert_false(p.hard_unlocked())
	news = p.record_waves(GameState.Difficulty.NORMAL, Profile.HARD_UNLOCK_WAVE)
	assert_true(news["hard_unlocked"], "wave %d on Normal unlocks Hard" % Profile.HARD_UNLOCK_WAVE)
	assert_true(p.hard_unlocked())
	assert_eq(p.runs_played, 0, "waves don't count as runs")
	var loaded := Profile.load_profile()
	assert_eq(loaded.best_wave, p.best_wave, "saved")
	assert_true(loaded.hard_unlocked())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.path))


func test_the_game_plays_waves_until_the_team_falls() -> void:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	GameState.mode = GameState.Mode.WAVES
	for i in 2:
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = &"knight"
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(game)
	var world: World = game.get("world")
	assert_true(world.wave_mode and world.director is WaveDirector, "an Endless Waves world")
	assert_eq(world.level_data.display_name, "The Pit")
	assert_eq((game.get("banner") as Label).text, "ENDLESS WAVES")
	assert_eq(GameState.team_lives, GameState.lives_per_level())
	GameState.wave = 3
	GameState.team_lives = 0
	for hero in world.heroes:
		hero.go_down()
	world._check_wipe(DT)
	assert_eq((game.get("banner") as Label).text, "GAME OVER")
	assert_eq((game.get("banner_sub") as Label).text, "You reached wave 3")
	_teardown(game)


func test_the_screens_follow_the_mode() -> void:
	GameState.reset_run()
	GameState.mode = GameState.Mode.WAVES
	GameState.wave = 12
	GameState.run_kills = 345
	GameState.run_active = false
	GameState.last_run_news = {"best_wave": true, "hard_unlocked": false}
	assert_true(EndScreen.stats_line().begins_with("Endless Waves   Normal   Wave 12   Enemies 345"),
		EndScreen.stats_line())
	var screen: Control = (load(END_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(screen)
	assert_eq((screen.get_node("%Title") as Label).text, "GAME OVER")
	assert_eq((screen.get_node("%Records") as Label).text, "NEW BEST WAVE!")
	_teardown(screen)
	GameState.mode = GameState.Mode.WAVES
	GameState.profile = Profile.new()
	GameState.profile.best_wave[GameState.Difficulty.NORMAL] = 9
	var select: Node = (load(SELECT_SCENE) as PackedScene).instantiate()
	select.set("game_scene", "")
	_tree().root.add_child(select)
	select._process(DT)
	assert_eq((select.get("_title") as Label).text, "ENDLESS WAVES")
	assert_eq((select.get("_record_label") as Label).text, "Best: wave 9")
	_teardown(select)
	GameState.profile = Profile.new()
	assert_true(EndScreen.stats_line().contains("Levels 0/"), "a run shows its levels")


# --- bots -------------------------------------------------------------------------------------

func test_bots_hold_out_in_the_pit() -> void:
	# Four god-mode bots with real abilities in The Pit: the first waves, then a
	# boss wave. Checks the arena's navigation, the arrow to the last few, and
	# that no wave stalls.
	for start: int in [1, 5]:
		var world := _wave_world(start, [&"knight", &"ranger", &"mage", &"cleric"], WaveDirector.arena_for(1234))
		world.bots = BotDriver.new(world, 7 + start)
		world.bots.use_abilities = true
		var goal := start + 3 if start == 1 else start + 1
		var seconds := 0
		while seconds < 300 and GameState.wave < goal:
			_step(world, 1.0)
			seconds += 1
		assert_true(GameState.wave >= goal, "bots got from wave %d to wave %d (%d s, now wave %d: %s)" % [
			start, goal, seconds, GameState.wave, world.director.objective])
		print("  Endless Waves: bots from wave %d to %d in %d s of game time" % [start, goal, seconds])
		_teardown(world)


func test_every_boss_can_fight_in_the_pit() -> void:
	# Each boss was made for a room of its own: here it fights four god-mode
	# bots in The Pit for a while (any engine error fails the test), then falls.
	for final: bool in [false, true]:
		for scene in WaveDirector.boss_scenes(final):
			var start := 10 if final else 5
			var world := _wave_world(start, [&"knight", &"ranger", &"mage", &"cleric"], WaveDirector.arena_for(99))
			var director := world.director as WaveDirector
			director._minis = [scene] as Array[String]
			director._finals = [scene] as Array[String]
			world.bots = BotDriver.new(world, 3)
			world.bots.use_abilities = true
			var slain: Array[String] = []
			director.mini_boss_defeated.connect(func(boss_name: String) -> void: slain.append(boss_name))
			_step(world, WaveDirector.FIRST_BREAK + WaveDirector.BOSS_PORTAL_TIME + 0.2)
			assert_true(world.boss != null and world.boss.scene_file_path == scene, "%s came in" % scene.get_file())
			var t := 0.0
			while slain.is_empty() and t < 30.0:
				_step(world, 0.5)
				t += 0.5
				if t >= 20.0 and world.boss:  # the bots had their go: finish it
					world.horde.damage(world.horde.index_of_uid(world.boss.uid), 1e9, Vector2.ZERO, 0)
			_step(world, 2.0)
			assert_eq(slain.size(), 1, "%s fell" % scene.get_file())
			assert_eq(director.phase, WaveDirector.Phase.BREAK, "and its wave is over")
			_teardown(world)


func test_late_waves_run() -> void:
	# Wave 33 with four players: a full horde (the alive cap), three featured
	# enemies and elites, against god-mode bots.
	var world := _wave_world(33, [&"knight", &"ranger", &"mage", &"cleric"], WaveDirector.arena_for(5))
	world.bots = BotDriver.new(world, 5)
	world.bots.use_abilities = true
	var director := world.director as WaveDirector
	_step(world, WaveDirector.FIRST_BREAK + 0.1)
	assert_eq(GameState.wave, 33)
	assert_eq(director.wave.quota, int(round(300 * 2.2)), "the biggest waves")
	assert_true(world.spawner.elite_chance > Elites.CHANCE * 2.9, "lots of elites")
	var most := 0
	for s in 20:
		_step(world, 1.0)
		most = maxi(most, world.horde.enemy_count() + world.spawner.pending_count())
	assert_true(most > 200, "a big horde (%d at most)" % most)
	assert_true(most <= world.spawner.alive_cap + 8, "within the alive cap (%d at most)" % most)
	_teardown(world)
