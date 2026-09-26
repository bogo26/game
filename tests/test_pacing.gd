extends "res://tests/test_case.gd"
## Pacing: arena waves, the XP vacuum and banked XP, hearts for the hurt,
## ultimate charge carried between levels, grace periods, solo scaling, team
## lives (Second Wind) and pick rounds held until an arena fight ends.

const WORLD_SCENE := "res://src/world/world.tscn"
const GAME_SCENE := "res://src/main/game.tscn"
const DT := 1.0 / 60.0

const ARENA := """
######################
#P...D111111111111111#
#....D111111111111111#
#....D111111111111111#
#....D111111111111111#
######################
"""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _data(layout: String, quotas: PackedInt32Array = PackedInt32Array([0, 0, 0])) -> LevelData:
	var d := LevelData.new()
	d.display_name = "Pacing test"
	d.layout = layout
	d.corridor_spawn_rate = 0.0
	d.arena_quotas = quotas
	return d


func _make_world(data: LevelData, hero_count: int = 1) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in hero_count:
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = &"knight"
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.spawn_enemies = false
	world.level_ups_enabled = false
	_tree().root.add_child(world)
	world.bots = null
	return world


func _start_run(hero_count: int = 2) -> Node:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in hero_count:
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = &"knight"
	GameState.level_index = 0
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(game)
	return game


func _teardown(node: Node) -> void:
	node.get_parent().remove_child(node)
	node.free()
	_tree().paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


# --- arena waves ------------------------------------------------------------------------------

func test_quotas_split_into_waves() -> void:
	assert_eq(LevelDirector.split_waves(0), PackedInt32Array())
	for quota in [7, 45, 60, 61, 100, 242]:
		var waves := LevelDirector.split_waves(quota)
		assert_eq(waves.size(), 2 if quota <= 60 else 3, "quota %d" % quota)
		var total := 0
		for n in waves:
			total += n
			assert_true(n > 0)
		assert_eq(total, quota, "waves add up to the quota")


func test_arena_runs_its_waves_then_clears() -> void:
	var world := _make_world(_data(ARENA, PackedInt32Array([20])))
	world.heroes[0].god_mode = true
	world.spawner.enabled = true
	var waves := []
	world.director.wave_started.connect(func(w: int, n: int) -> void: waves.append("%d/%d" % [w, n]))
	var cleared := [0]
	world.director.arena_cleared.connect(func(_id: int) -> void: cleared[0] += 1)
	var room := world.director.room_by_id(1)
	world.director._activate(room, world.heroes[0])
	var t := 0.0
	var max_alive := 0
	while t < 30.0 and room.state != LevelDirector.RoomState.CLEARED:
		world._process(DT)
		t += DT
		max_alive = maxi(max_alive, world.horde.enemy_count())
		if int(t * 60.0) % 30 == 0:  # the team mows them down twice a second
			for i in world.horde.count:
				if world.horde.hp[i] > 0.0 and world.horde.is_mobile(i):
					world.horde.damage(i, 9999.0, Vector2.ZERO, 0)
	assert_eq(room.state, LevelDirector.RoomState.CLEARED, "cleared in %.1f s" % t)
	assert_eq(waves, ["1/2", "2/2"], "both waves were announced")
	assert_true(max_alive <= room.waves[1] + 2, "never the whole quota at once (%d alive at most)" % max_alive)
	assert_eq(cleared[0], 1)
	assert_true(room.killed >= 20, "the whole quota was beaten")
	_teardown(world)


# --- XP and hearts ----------------------------------------------------------------------------

func test_clearing_an_arena_vacuums_the_xp() -> void:
	var world := _make_world(_data(ARENA))
	var hero := world.heroes[0]
	for k in 10:
		world.pickups.spawn(hero.position + Vector2(200 + k * 10, 20), PickupSim.Kind.XP, 1)
	world.pickups.spawn(hero.position + Vector2(250, 0), PickupSim.Kind.HEART, 1)
	var xp_before := GameState.xp + GameState.team_level * 1000
	world._on_arena_cleared(1)
	for f in 180:
		world._snapshot_heroes()
		world.pickups.update(DT, world.hero_positions, world._hero_ranges, world._hero_active, world._hero_need)
		world._apply_pickups()
	assert_eq(world.pickups.count, 1, "every gem flew in; the heart stayed put")
	assert_true(GameState.xp + GameState.team_level * 1000 > xp_before, "and counted as XP")
	_teardown(world)


func test_leftover_xp_and_ult_charge_carry_to_the_next_level() -> void:
	var game := _start_run()
	var world: World = game.get("world")
	world.heroes[0].ult_charge = 0.7
	for k in 5:
		world.pickups.spawn(Vector2(k, 0), PickupSim.Kind.XP, 1)
	var xp_before := GameState.xp
	game.call("_carry_over")
	assert_eq(GameState.xp, xp_before + 5, "gems nobody picked up are banked")
	GameState.level_index += 1
	game.call("_load_level")
	world = game.get("world")
	assert_near(world.hero_for_slot(0).ult_charge, 0.7, 0.001, "the ultimate kept its charge")
	_teardown(game)


func test_hearts_go_to_whoever_needs_them_most() -> void:
	var pickups := PickupSim.new()
	var heroes := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var ranges := PackedFloat32Array([30.0, 30.0])
	var active := PackedByteArray([1, 1])
	pickups.spawn(Vector2(5, 5), PickupSim.Kind.HEART, 1)
	pickups.update(DT, heroes, ranges, active, PackedFloat32Array([0.0, 0.0]))
	assert_eq(pickups.target[0], -1, "nobody is hurt: the heart waits")
	pickups.update(DT, heroes, ranges, active, PackedFloat32Array([0.2, 0.6]))
	assert_eq(pickups.target[0], 1, "the more hurt hero gets it")


# --- grace and solo ---------------------------------------------------------------------------

func test_grace_periods() -> void:
	var world := _make_world(_data(ARENA))
	var hero := world.heroes[0]
	assert_false(hero.take_hit(10.0), "protected right after spawning")
	hero.invulnerable_time = 0.0
	world.pause_menu.open()
	world.pause_menu.close()
	assert_true(hero.invulnerable_time >= World.RESUME_GRACE, "a moment of grace after the pause menu")
	hero.invulnerable_time = 0.0
	world._on_level_up_closed()
	assert_true(hero.invulnerable_time >= World.RESUME_GRACE, "and after picking upgrades")
	_teardown(world)


func test_boss_and_nests_scale_less_for_solo_players() -> void:
	var spawner := SpawnDirector.new()
	spawner.set_player_count(1)
	assert_near(spawner.fixed_hp_multiplier, 0.6, 0.001)
	assert_near(spawner.hp_multiplier, 1.0, 0.001, "ordinary enemies unchanged")
	spawner.set_player_count(4)
	assert_near(spawner.fixed_hp_multiplier, 1.95, 0.001)


func test_team_only_upgrades_are_not_offered_solo() -> void:
	var pool := UpgradePool.new()
	var seen_solo := false
	var seen_team := false
	for k in 300:
		for u in pool.roll_offers(&"knight", {}, 3, true):
			seen_solo = seen_solo or u.team_only
		for u in pool.roll_offers(&"knight", {}, 3, false):
			seen_team = seen_team or u.team_only
	assert_false(seen_solo, "never offered to a solo player")
	assert_true(seen_team, "still offered in a team")


# --- team lives -------------------------------------------------------------------------------

func test_a_wipe_spends_a_team_life() -> void:
	var game := _start_run()
	var world: World = game.get("world")
	assert_eq(GameState.team_lives, GameState.LIVES_PER_LEVEL, "lives refill every level")
	var wiped := [0]
	world.team_wiped.connect(func() -> void: wiped[0] += 1)
	world.projectiles.spawn(world.heroes[0].position + Vector2(20, 0), Vector2(-10, 0), 5.0, 3.0, 2.0,
		ProjectileSim.Team.ENEMY, -1, ProjectileSim.Look.SPIT)
	for hero in world.heroes:
		hero.go_down()
	world._check_wipe(DT)
	assert_eq(wiped[0], 0, "not over: a life was spent")
	assert_eq(GameState.team_lives, 0)
	assert_eq(GameState.lives_used, 1)
	for hero in world.heroes:
		assert_false(hero.is_downed(), "everyone got back up")
		assert_near(hero.hp, hero.max_hp * World.SECOND_WIND_HP, 0.5)
	assert_eq(world.projectiles.count, 0, "enemy shots on screen are gone")
	for hero in world.heroes:
		hero.invulnerable_time = 0.0
		hero.go_down()
	world._check_wipe(DT)
	assert_eq(wiped[0], 1, "no lives left: the run ends")
	_teardown(game)


# --- pick rounds ------------------------------------------------------------------------------

func test_picks_wait_until_the_arena_fight_is_over() -> void:
	var world := _make_world(_data(ARENA, PackedInt32Array([10])))
	world.level_ups_enabled = true
	GameState.pending_level_ups = 0
	GameState.add_xp(GameState.xp_to_next())  # a level-up
	assert_true(world.can_open_pick_round(), "in a corridor it opens at once")
	var room := world.director.room_by_id(1)
	world.director._activate(room, world.heroes[0])
	assert_false(world.can_open_pick_round(), "held during the fight")
	world._process(DT)
	assert_false(world.level_up.is_open())
	GameState.add_treasure_pick()
	assert_true(world.can_open_pick_round(), "a chest's round still opens")
	GameState.pop_round()
	world.director._clear(room)
	assert_true(world.can_open_pick_round(), "the fight is over")
	assert_true(world.level_up_delay >= World.PICKS_AFTER_CLEAR - 0.001, "after a short moment")
	_teardown(world)
