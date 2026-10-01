extends "res://tests/test_case.gd"
## Keep moving: out of fights the team has a minute to reach its next
## objective; then the horde grows restless, a stage more every 15 s: enemies
## drop less and less XP and hearts, and the corridor horde comes faster,
## fuller, tougher and more often elite. Fights hold it off, and every
## objective reached starts the clock over (LevelDirector.RESTLESS_AFTER).

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 30.0

## A corridor with the exit, and one arena.
const LAYOUT := """
############################
#P........D1111111111111111#
#.........D1111111111111111#
#.........D1111111111111111#
#....X....D1111111111111111#
#.........D1111111111111111#
############################
"""


func _data(corridor_rate: float = 16.0) -> LevelData:
	var d := LevelData.new()
	d.display_name = "Restless test"
	d.layout = LAYOUT
	d.corridor_spawn_rate = corridor_rate
	d.corridor_cap_fraction = 0.4
	d.arena_quotas = PackedInt32Array([20])
	return d


## A run's world (level 1, Normal unless told) with no enemies spawning on
## their own: the director still sets the spawner up as the clock says.
func _world(data: LevelData, run_mode: bool = true, wave_mode: bool = false,
		difficulty: GameState.Difficulty = GameState.Difficulty.NORMAL) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.difficulty = difficulty
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = &"knight"
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.run_mode = run_mode
	world.wave_mode = wave_mode
	world.spawn_enemies = false
	world.level_ups_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.heroes[0].god_mode = true
	return world


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	(Engine.get_main_loop() as SceneTree).paused = false
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.difficulty = GameState.Difficulty.NORMAL


func _wait(world: World, seconds: float) -> void:
	for f in roundi(seconds / DT):
		world._process(DT)


## Kills `count` enemies of type `id` at the hero's feet and returns the XP
## and hearts they dropped.
func _drops(world: World, id: StringName, count: int) -> Vector2i:
	world.pickups.clear()
	var t := world.horde.type_index(id)
	var at := world.heroes[0].position + Vector2(40, 0)
	for k in count:
		var i := world.horde.spawn(t, at, 1.0)
		world.horde.damage(i, 99999.0, Vector2.ZERO, 0)
	world._process_kills()
	var xp := 0
	var hearts := 0
	for k in world.pickups.count:
		if world.pickups.kind[k] == PickupSim.Kind.HEART:
			hearts += 1
		else:
			xp += world.pickups.value[k]
	world.pickups.clear()
	return Vector2i(xp, hearts)


func test_the_clock_runs_out_of_fights_and_starts_over_at_each_objective() -> void:
	var world := _world(_data())
	var director := world.director
	var room := director.room_by_id(1)
	assert_true(director.has_clock, "a level with a corridor horde has a clock")
	assert_near(director.restless_in, LevelDirector.RESTLESS_AFTER, 0.001, "a minute to reach the first arena")
	_wait(world, 20.0)
	assert_near(director.restless_in, 40.0, 0.01, "it runs down while the team walks")
	director._activate(room, world.heroes[0])
	assert_false(director.clock_running(), "an arena fight stops it")
	_wait(world, 50.0)
	assert_near(director.restless_in, 40.0, 0.01, "however long the fight takes")
	assert_eq(director.restless_stage, 0)
	director._clear(room)
	assert_true(director.exit_open, "the last arena opens the exit")
	assert_true(director.clock_running())
	assert_near(director.restless_in, LevelDirector.RESTLESS_AFTER, 0.001, "and a fresh minute to reach it")
	_teardown(world)


func test_the_horde_grows_restless_a_stage_every_15_seconds() -> void:
	var world := _world(_data())
	var director := world.director
	var spawner := world.spawner
	var horde := world.horde
	var rate := spawner.spawn_rate
	var cap := spawner.corridor_cap_fraction
	var hp := spawner.level_hp_multiplier
	var damage := horde.damage_mult
	assert_near(spawner.elite_chance, 0.0, 0.0001, "no elites on the first level...")
	var stages: Array[int] = []
	director.restless_changed.connect(func(stage: int) -> void: stages.append(stage))
	_wait(world, 59.5)
	assert_eq(director.restless_stage, 0, "calm for a minute")
	assert_near(director.drop_share(), 1.0, 0.0001)
	_wait(world, 1.0)
	assert_eq(stages, [1] as Array[int], "then restless at once")
	assert_eq(world.hud._callout_label.text, "THE HORDE GROWS RESTLESS")
	assert_near(director.drop_share(), 0.75, 0.0001, "a quarter less drops")
	assert_near(spawner.spawn_rate, rate * 1.25, 0.001, "faster spawns")
	assert_near(spawner.corridor_cap_fraction, cap + 0.1, 0.0001, "more of them")
	assert_near(spawner.level_hp_multiplier, hp * 1.2, 0.0001, "tougher")
	assert_near(horde.damage_mult, damage * 1.1, 0.0001, "hitting harder")
	assert_near(horde.speed_mult, 1.05, 0.0001, "quicker")
	assert_near(spawner.elite_chance, Elites.CHANCE, 0.0001, "...until the horde grows restless")
	_wait(world, 15.0)
	assert_eq(stages, [1, 2] as Array[int], "another stage 15 s later")
	assert_near(director.drop_share(), 0.5, 0.0001)
	assert_near(spawner.spawn_rate, rate * 1.5, 0.001)
	assert_near(spawner.level_hp_multiplier, hp * 1.4, 0.0001)
	assert_near(spawner.elite_chance, Elites.CHANCE * 2.0, 0.0001)
	_wait(world, 30.0)
	assert_eq(director.restless_stage, 4)
	assert_near(director.drop_share(), 0.0, 0.0001, "nothing drops from the 4th stage")
	_wait(world, 15.0 * 6)
	assert_eq(director.restless_stage, 10, "and it keeps growing")
	assert_near(spawner.level_hp_multiplier, hp * 3.0, 0.0001)
	assert_near(horde.speed_mult, LevelDirector.RESTLESS_MAX_SPEED, 0.0001, "speed tops out")
	assert_near(spawner.corridor_cap_fraction, 1.0, 0.0001, "the alive cap is the limit")
	_teardown(world)


func test_restless_enemies_drop_less_and_less() -> void:
	var world := _world(_data())
	world._rng.seed = 7  # heart rolls
	var director := world.director
	assert_eq(_drops(world, &"swarmer", 40).x, 40, "calm: every gem")
	director._set_restless(2)
	assert_eq(_drops(world, &"swarmer", 40).x, 20, "half as much XP at stage 2")
	assert_eq(_drops(world, &"brute", 8).x, 20, "brutes too (5 XP each)")
	director._set_restless(4)
	assert_eq(_drops(world, &"swarmer", 40), Vector2i.ZERO, "none at stage 4")
	var elite := _drops(world, &"swarmer_swift", 20)
	assert_eq(elite, Vector2i.ZERO, "not even an elite's big gem or its heart")
	director._set_restless(0)
	var calm_elites := _drops(world, &"swarmer_swift", 20)
	assert_eq(calm_elites.x, 20 * Elites.XP, "calm again: full drops")
	assert_true(calm_elites.y > 0, "hearts too (%d from 20 elites)" % calm_elites.y)
	_teardown(world)


func test_a_fight_calms_the_horde_and_clearing_it_starts_the_clock_over() -> void:
	var world := _world(_data())
	var director := world.director
	var spawner := world.spawner
	var hp := spawner.level_hp_multiplier
	var damage := world.horde.damage_mult
	_wait(world, 90.5)
	assert_eq(director.restless_stage, 3)
	var room := director.room_by_id(1)
	director._activate(room, world.heroes[0])
	assert_near(spawner.level_hp_multiplier, hp, 0.0001, "the arena's horde is the level's own")
	assert_near(world.horde.damage_mult, damage, 0.0001)
	assert_near(world.horde.speed_mult, 1.0, 0.0001)
	assert_near(spawner.spawn_rate, LevelDirector._rate(world.level.data.arena_spawn_rate), 0.001,
		"at the arena's pace")
	assert_near(director.drop_share(), 1.0, 0.0001, "with full drops")
	_wait(world, 30.0)
	assert_near(spawner.level_hp_multiplier, hp, 0.0001, "for the whole fight")
	var stages: Array[int] = []
	director.restless_changed.connect(func(stage: int) -> void: stages.append(stage))
	director._clear(room)
	assert_eq(stages, [0] as Array[int], "the objective calms the horde")
	assert_eq(director.restless_stage, 0)
	assert_near(director.restless_in, LevelDirector.RESTLESS_AFTER, 0.001, "and starts the clock over")
	assert_near(spawner.spawn_rate, LevelDirector._rate(world.level.data.corridor_spawn_rate), 0.001,
		"back to the corridor trickle")
	_teardown(world)


func test_the_mini_boss_counts_as_an_objective() -> void:
	var data: LevelData = RunConfig.load_default().levels[3]
	var world := _world(data)
	var director := world.director
	assert_true(director.has_clock, "the mini boss's level has a corridor horde")
	_wait(world, 70.0)
	assert_eq(director.restless_stage, 1)
	var room: LevelDirector.Room = director.rooms[0]
	director._activate(room, world.heroes[0])
	assert_true(world.boss != null, "the boss fight is on")
	assert_near(world.boss._add_hp_multiplier, world.spawner.effective_hp_multiplier(), 0.0001)
	assert_near(world.spawner.level_hp_multiplier, data.hp_multiplier * GameState.difficulty_value("hp"), 0.0001,
		"its adds get the level's HP, not a restless horde's")
	world.boss.queue_free()
	director.boss = null
	world.boss = null
	world._process(DT)
	assert_eq(room.state, LevelDirector.RoomState.CLEARED, "the boss is gone: its room clears")
	assert_eq(director.restless_stage, 0)
	assert_near(director.restless_in, LevelDirector.RESTLESS_AFTER, 0.05, "a fresh minute to reach the exit")
	_teardown(world)


func test_only_levels_with_a_corridor_horde_have_a_clock() -> void:
	for data in RunConfig.load_default().all_layouts():
		assert_eq(data.corridor_spawn_rate > 0.0, not data.is_final_boss,
			"%s: a clock on every level but the final boss's" % data.display_name)
	var quiet := _world(_data(0.0))
	assert_false(quiet.director.has_clock, "no corridor horde: nothing to farm")
	_wait(quiet, 70.0)
	assert_eq(quiet.director.restless_stage, 0)
	_teardown(quiet)
	var sandbox := _world(_data(), false)
	assert_false(sandbox.director.has_clock, "the test room never ends")
	_teardown(sandbox)
	var waves := _world(WaveDirector.arena_for(1234), true, true)
	assert_true(waves.director is WaveDirector)
	assert_false(waves.director.has_clock, "Endless Waves keeps the pressure on by itself")
	_teardown(waves)


func test_the_hud_shows_the_clock() -> void:
	var world := _world(_data())
	var hud := world.hud
	var label: Label = hud._clock_label
	hud._process(DT)
	assert_true(label.visible)
	assert_eq(label.text, "1:00")
	assert_eq(label.label_settings.font_color, Hud.CLOCK_COLOR)
	_wait(world, 18.5)
	hud._process(DT)
	assert_eq(label.text, "0:42")
	_wait(world, 32.0)
	hud._process(DT)
	assert_eq(label.label_settings.font_color, Hud.CLOCK_HURRY_COLOR, "gold for the last 10 s")
	_wait(world, 25.0)
	hud._process(DT)
	assert_eq(label.text, "RESTLESS  XP 50%")
	assert_eq(label.label_settings.font_color, Hud.RESTLESS_COLOR)
	_wait(world, 30.0)
	hud._process(DT)
	assert_eq(label.text, "RESTLESS  no XP")
	world.director._activate(world.director.room_by_id(1), world.heroes[0])
	hud._process(DT)
	assert_false(label.visible, "hidden during a fight")
	_teardown(world)


func test_a_faster_difficulty_stays_faster_when_restless() -> void:
	# Torment's horde walks faster to begin with; growing restless speeds it up
	# on top of that (and tops out at the same share above it). Fights bring it
	# back to Torment's own pace.
	var world := _world(_data(), true, false, GameState.Difficulty.TORMENT)
	var director := world.director
	var horde := world.horde
	var own := float(GameState.DIFFICULTY[GameState.Difficulty.TORMENT]["speed"])
	assert_true(own > 1.0, "Torment walks faster")
	assert_near(horde.speed_mult, own, 0.0001, "from the start")
	_wait(world, 60.5)
	assert_eq(director.restless_stage, 1)
	assert_near(horde.speed_mult, own * (1.0 + LevelDirector.RESTLESS_SPEED), 0.0001, "quicker still")
	_wait(world, 15.0 * 9)
	assert_near(horde.speed_mult, own * LevelDirector.RESTLESS_MAX_SPEED, 0.0001, "tops out above its own")
	director._activate(director.room_by_id(1), world.heroes[0])
	assert_near(horde.speed_mult, own, 0.0001, "a fight brings it back to Torment's pace")
	_teardown(world)
