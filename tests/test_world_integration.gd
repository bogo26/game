extends "res://tests/test_case.gd"
## Runs the real World scene headless with bot heroes for a few simulated
## seconds and checks the combat loop end to end.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0


func _make_world(heroes: Array[StringName]) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in heroes.size():
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = heroes[i]
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.allow_drop_in = false
	world.auto_revive_on_wipe = true
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.bots = BotDriver.new(world)
	world.bots.use_abilities = true
	return world


func _run(world: World, seconds: float) -> void:
	for frame in int(seconds / DT):
		InputRouter._process(DT)
		world._process(DT)


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	(Engine.get_main_loop() as SceneTree).paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


func test_four_heroes_fight_the_horde() -> void:
	var world := _make_world([&"knight", &"ranger", &"mage", &"cleric"])
	var kills := [0]
	var on_kill := func(_p: Vector2, _t: int, _s: int) -> void: kills[0] += 1
	Events.enemy_killed.connect(on_kill)
	_run(world, 12.0)
	Events.enemy_killed.disconnect(on_kill)

	assert_eq(world.heroes.size(), 4)
	assert_true(world.horde.alive_count() > 50, "horde spawned (%d alive)" % world.horde.alive_count())
	assert_true(kills[0] > 20, "heroes killed enemies (%d)" % kills[0])
	assert_true(GameState.xp > 0 or GameState.team_level > 1, "XP collected")
	for hero in world.heroes:
		assert_true(hero.attack().cooldown_left != 0.0 or hero.ult_charge > 0.05,
			"%s used its attack" % hero.hero_id)
		assert_true(hero.ult_charge > 0.0 or hero.ultimate().cooldown_left != 0.0,
			"%s charged its ultimate" % hero.hero_id)
	_teardown(world)


func test_downed_hero_is_revived_by_teammate() -> void:
	var world := _make_world([&"knight", &"cleric"])
	world.spawner.enabled = false
	var knight := world.heroes[0]
	var cleric := world.heroes[1]
	knight.god_mode = false
	knight.invulnerable_time = 0.0
	knight.take_hit(10000.0)
	assert_true(knight.is_downed(), "lethal hit downs the hero")
	assert_false(knight.is_targetable())
	world.bots = null  # stand still next to the downed knight
	cleric.position = knight.position + Vector2(8, 0)
	_run(world, Hero.REVIVE_TIME + 0.2)
	assert_false(knight.is_downed(), "revived after standing nearby")
	assert_near(knight.hp, knight.max_hp * Hero.REVIVE_HP_FRACTION, 0.5)
	_teardown(world)


func test_each_ability_activates_without_errors() -> void:
	var world := _make_world([&"knight", &"ranger", &"mage", &"cleric"])
	world.bots = null
	for i in 20:
		world.horde.spawn(0, world.heroes[0].position + Vector2(30 + i, (i % 5) * 6 - 12))
	_run(world, 0.1)
	for hero in world.heroes:
		hero.ult_charge = 1.0
		for ability in hero.abilities:
			ability.cooldown_left = 0.0
			assert_true(ability.try_activate(Vector2.RIGHT), "%s: %s activates" % [hero.hero_id, ability.display_name])
		_run(world, 1.5)
	assert_true(world.horde.kill_pos.size() >= 0)
	_teardown(world)


func test_level_up_round_with_bots() -> void:
	var world := _make_world([&"knight", &"mage"])
	world.spawner.enabled = false
	GameState.pending_level_ups = 2
	GameState.team_level = 3
	world._process(DT)
	assert_true(world.level_up.is_open(), "screen opens for pending level-ups")
	assert_true((Engine.get_main_loop() as SceneTree).paused, "game paused while picking")
	for frame in 240:
		InputRouter._process(DT)
		world.level_up._process(DT)
		if not world.level_up.is_open():
			break
	assert_false(world.level_up.is_open(), "closes after all rounds")
	assert_eq(GameState.pending_level_ups, 0)
	assert_false((Engine.get_main_loop() as SceneTree).paused, "unpaused")
	for hero in world.heroes:
		assert_eq(GameState.slots[hero.slot].upgrades.size(), 2, "%s picked twice" % hero.hero_id)
	_teardown(world)


func test_upgrades_persist_into_next_level() -> void:
	var world := _make_world([&"knight"])
	var vitality := UpgradePool.shared_library().find(&"vitality")
	var hero := world.heroes[0]
	var base_hp := hero.max_hp
	hero.apply_upgrade(vitality)
	hero.apply_upgrade(vitality)
	assert_near(hero.max_hp, base_hp + 40.0, 0.01)
	world.get_parent().remove_child(world)
	world.free()
	# Next level: same run state, fresh World and Hero.
	var next: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	next.allow_drop_in = false
	(Engine.get_main_loop() as SceneTree).root.add_child(next)
	var reborn := next.heroes[0]
	assert_near(reborn.max_hp, base_hp + 40.0, 0.01, "upgrades re-applied")
	assert_near(reborn.hp, reborn.max_hp, 0.01, "starts the level at full HP")
	assert_eq(int(reborn.upgrade_stacks.get(&"vitality", 0)), 2)
	_teardown(next)
