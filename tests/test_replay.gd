extends "res://tests/test_case.gd"
## Replay: per-player stats and awards, the profile's records (best times,
## Hard unlocked, hero stars), difficulties, "Change heroes" keeping the team,
## and elite enemies (stats, only from level 2, Splitting, Volatile).

const WORLD_SCENE := "res://src/world/world.tscn"
const SELECT_SCENE := "res://src/ui/character_select.tscn"
const DT := 1.0 / 60.0
const GameStateScript := preload("res://src/autoload/game_state.gd")
const ROOM := """
####################
#P.................#
#..................#
#..................#
#..................#
####################
"""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _make_world(hero_count: int = 1, run_mode: bool = false) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in hero_count:
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = &"knight"
	var data := LevelData.new()
	data.display_name = "Replay test"
	data.layout = ROOM
	data.corridor_spawn_rate = 0.0
	data.arena_quotas = PackedInt32Array([0, 0, 0])
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.run_mode = run_mode
	world.spawn_enemies = false
	world.level_ups_enabled = false
	_tree().root.add_child(world)
	world.bots = null
	return world


func _teardown(node: Node) -> void:
	node.get_parent().remove_child(node)
	node.free()
	_tree().paused = false
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.difficulty = GameState.Difficulty.NORMAL
	GameState.level_index = 0
	GameState.profile = Profile.new()


func _slot(index: int, stats: Dictionary) -> RefCounted:
	var s: RefCounted = GameStateScript.PlayerSlot.new(index)
	s.hero_id = &"knight"
	for key: String in stats:
		s.set(key, stats[key])
	return s


# --- stats and awards -------------------------------------------------------------------------

func test_awards_go_to_the_best_at_each_thing() -> void:
	var p1 := _slot(0, {"kills": 300, "revives": 0, "damage_taken": 120.0, "biggest_hit": 90.0, "downs": 1})
	var p2 := _slot(1, {"kills": 120, "revives": 3, "damage_taken": 400.0, "biggest_hit": 250.0, "downs": 0})
	var awards := EndScreen.awards([p1, p2])
	assert_eq(awards[0], PackedStringArray(["Slayer"]))
	assert_eq(awards[1], PackedStringArray(["Medic", "Tank", "Sharpshooter", "Untouchable"]))
	var solo := EndScreen.awards([_slot(0, {"kills": 50, "downs": 0})])
	assert_eq(solo[0], PackedStringArray(["Untouchable"]), "solo: nobody to beat, but never downed counts")
	assert_eq(EndScreen.short_number(12345.0), "12k")
	assert_eq(EndScreen.short_number(1234.0), "1.2k")


func test_per_player_stats_are_counted() -> void:
	var world := _make_world(2)
	var t := world.horde.type_index(&"swarmer")
	var i := world.horde.spawn(t, LevelGrid.cell_center(Vector2i(10, 2)))
	world.hit_enemy(i, 999.0, Vector2.ZERO, 1)
	world._apply_ult_charge()
	world._process_kills()
	var p2 := GameState.slots[1]
	assert_eq(p2.kills, 1)
	assert_true(p2.damage_dealt > 0.0 and p2.biggest_hit >= 999.0)
	var p1_hero := world.heroes[0]
	p1_hero.invulnerable_time = 0.0
	p1_hero.take_hit(10.0)
	assert_true(GameState.slots[0].damage_taken > 0.0)
	p1_hero.go_down()
	assert_eq(GameState.slots[0].downs, 1)
	world.heroes[1].position = p1_hero.position
	for f in int(Hero.REVIVE_TIME / DT) + 5:
		world._update_revives(DT)
	assert_false(p1_hero.is_downed())
	assert_eq(p2.revives, 1, "P2 gets the revive")
	_teardown(world)


# --- profile and difficulty -------------------------------------------------------------------

func test_profile_records() -> void:
	var p := Profile.new()
	var news := p.record_run(false, GameState.Difficulty.NORMAL, 300.0, [&"knight"])
	assert_eq(p.runs_played, 1)
	assert_false(news["best_time"], "a defeat sets no time")
	assert_false(p.hard_unlocked())
	news = p.record_run(true, GameState.Difficulty.NORMAL, 600.0, [&"knight", &"mage"])
	assert_true(news["best_time"], "the first win is a best time")
	assert_true(news["hard_unlocked"], "a Normal win unlocks Hard")
	assert_eq(p.hero_rank(&"knight"), GameState.Difficulty.NORMAL, "the knight's star")
	news = p.record_run(true, GameState.Difficulty.NORMAL, 700.0, [&"knight"])
	assert_false(news["best_time"], "slower: the record stands")
	assert_near(p.best_time[GameState.Difficulty.NORMAL], 600.0, 0.001)
	var loaded := Profile.load_profile()
	assert_eq(loaded.runs_played, 3, "saved")
	assert_true(loaded.hard_unlocked())
	assert_eq(loaded.hero_rank(&"mage"), GameState.Difficulty.NORMAL)


func test_hard_waits_for_a_normal_win() -> void:
	GameState.profile = Profile.new()
	var select: Node = (load(SELECT_SCENE) as PackedScene).instantiate()
	select.set("game_scene", "")
	_tree().root.add_child(select)
	GameState.difficulty = GameState.Difficulty.NORMAL
	select.call("change_difficulty", 1)
	assert_eq(GameState.difficulty, GameState.Difficulty.CASUAL, "Hard is skipped while locked")
	GameState.profile.wins[GameState.Difficulty.NORMAL] = 1
	GameState.difficulty = GameState.Difficulty.NORMAL
	select.call("change_difficulty", 1)
	assert_eq(GameState.difficulty, GameState.Difficulty.HARD, "unlocked")
	_teardown(select)


func test_difficulty_scales_the_horde_and_lives() -> void:
	GameState.difficulty = GameState.Difficulty.HARD
	var world := _make_world()
	assert_near(world.spawner.level_hp_multiplier, 1.3, 0.001, "tougher enemies")
	assert_near(world.horde.damage_mult, 1.3, 0.001, "that hit harder")
	assert_eq(GameState.lives_per_level(), 0, "and no Second Wind")
	var t := world.horde.type_index(&"swarmer")
	world.horde.spawn(t, world.heroes[0].position)
	world.horde.hash.rebuild(world.horde.pos, world.horde.count)
	assert_near(world.horde.contact_damage_at(world.heroes[0].position, Hero.RADIUS),
		world.horde.types[t].contact_damage * 1.3, 0.001)
	_teardown(world)
	GameState.difficulty = GameState.Difficulty.CASUAL
	assert_eq(GameState.lives_per_level(), 2, "Casual: two lives a level")
	GameState.difficulty = GameState.Difficulty.NORMAL


func test_change_heroes_keeps_the_team() -> void:
	InputRouter.unassign_all()
	GameState.clear_players()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	InputRouter.assign(1, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = &"rogue"
	GameState.slots[1].hero_id = &"cleric"
	GameState.keep_team = true
	var select: Node = (load(SELECT_SCENE) as PackedScene).instantiate()
	select.set("game_scene", "")
	_tree().root.add_child(select)
	assert_true(InputRouter.get_player(0).is_assigned() and InputRouter.get_player(1).is_assigned(), "still joined")
	var roster: Array[StringName] = select.get("ROSTER")
	assert_eq(roster[select.get("_choice")[0]], &"rogue", "with their last hero")
	assert_eq(roster[select.get("_choice")[1]], &"cleric")
	assert_false(select.get("_is_ready")[0], "but not readied")
	assert_false(GameState.keep_team, "a one-time thing")
	_teardown(select)


# --- elites -----------------------------------------------------------------------------------

func test_elite_stats() -> void:
	var swarmer := load("res://src/enemies/data/swarmer.tres") as EnemyData
	var e := Elites.make(swarmer, Elites.Trait.SWIFT)
	assert_near(e.max_hp, swarmer.max_hp * Elites.HP_MULT, 0.001)
	assert_near(e.speed, swarmer.speed * Elites.SWIFT_SPEED, 0.001)
	assert_near(e.contact_damage, swarmer.contact_damage * Elites.DAMAGE_MULT, 0.001)
	assert_near(e.knockback_taken, swarmer.knockback_taken * Elites.KNOCKBACK_MULT, 0.001)
	assert_eq(e.xp, Elites.XP, "a big gem")
	assert_near(e.hurt_size.y, swarmer.hurt_size.y * Elites.SCALE, 0.001, "hurtbox as big as the drawing")
	assert_eq(Elites.variants([swarmer]).size(), 3, "one per trait")


func test_elites_join_from_the_second_level() -> void:
	GameState.level_index = 0
	var world := _make_world(1, true)
	assert_eq(world.spawner.elite_chance, 0.0, "none in the first level")
	_teardown(world)
	GameState.level_index = 1
	world = _make_world(1, true)
	GameState.level_index = 1
	world.director.setup(world)
	assert_near(world.spawner.elite_chance, Elites.CHANCE, 0.0001, "then about 1 in 40")
	var t := world.horde.type_index(&"swarmer")
	world.spawner.elite_chance = 1.0
	var elites := 0
	for k in 20:
		var u := world.spawner.maybe_elite(t)
		if world.horde.t_elite[u] != 0:
			elites += 1
			world.horde.spawn(u, LevelGrid.cell_center(Vector2i(3 + k % 10, 2)))
	assert_eq(elites, Elites.MAX_ALIVE, "never more than a few at once")
	_teardown(world)


func test_splitting_elites_break_apart() -> void:
	var world := _make_world()
	var t := world.horde.type_index(&"swarmer_splitting")
	var i := world.horde.spawn(t, LevelGrid.cell_center(Vector2i(10, 2)))
	world.horde.damage(i, 99999.0, Vector2.ZERO, 0)
	world.horde.update(DT, world.target_positions)
	world._process_kills()
	var swarmer := world.horde.type_index(&"swarmer")
	assert_eq(world.horde.count_of_type(swarmer), Elites.SPLIT_COUNT, "three ordinary swarmers")
	_teardown(world)


func test_volatile_elites_warn_then_blow_up() -> void:
	var world := _make_world()
	var hero := world.heroes[0]
	hero.invulnerable_time = 0.0
	var spot := hero.position + Vector2(20, 0)
	var t := world.horde.type_index(&"brute_volatile")
	var i := world.horde.spawn(t, spot)
	world.horde.damage(i, 99999.0, Vector2.ZERO, 0)
	world.horde.update(DT, world.target_positions)
	world._process_kills()
	assert_true(world.warn_fx._kind.has(FxLayer.Kind.TELEGRAPH), "the blast is announced")
	assert_eq(hero.hp, hero.max_hp, "not yet")
	for f in int(Elites.VOLATILE_DELAY / DT) + 2:
		world._update_volatile_blasts(DT)
	assert_true(hero.hp < hero.max_hp, "then it goes off")
	_teardown(world)
