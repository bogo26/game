extends "res://tests/test_case.gd"
## The level must actually stop (not just set the pause flag) while players
## pick upgrades or the pause menu is open - including inside a run, where the
## World lives under the always-processing Game node.

const GAME_SCENE := "res://src/main/game.tscn"
const DT := 1.0 / 60.0


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _start_run() -> Node:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in 2:
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = &"knight"
	GameState.slots[1].hero_id = &"mage"
	GameState.level_index = 0
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(game)
	return game


func _teardown(game: Node) -> void:
	game.get_parent().remove_child(game)
	game.free()
	_tree().paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


func test_upgrade_picks_freeze_the_level_in_a_run() -> void:
	var game := _start_run()
	var world: World = game.get("world")
	assert_true(world.can_process(), "level runs normally")
	GameState.pending_level_ups = 1
	world._process(DT)  # a level-up is pending: opens the pick screen
	assert_true(world.level_up.is_open(), "pick screen opened")
	assert_true(_tree().paused, "tree paused")
	assert_false(world.can_process(), "level (enemies, heroes, projectiles) frozen while picking")
	assert_true(world.level_up.can_process(), "pick screen still takes input")
	assert_true(world.hud.can_process(), "HUD still updates")
	for frame in 120:
		InputRouter._process(DT)
		world.level_up._process(DT)
		if not world.level_up.is_open():
			break
	assert_false(world.level_up.is_open(), "bots picked, screen closed")
	assert_false(_tree().paused, "unpaused after picking")
	assert_true(world.can_process(), "level resumes")
	_teardown(game)


func test_pause_menu_freezes_the_level_in_a_run() -> void:
	var game := _start_run()
	var world: World = game.get("world")
	world.pause_menu.open()
	assert_false(world.can_process(), "level frozen while the pause menu is open")
	assert_true(world.pause_menu.can_process())
	world.pause_menu.close()
	assert_true(world.can_process(), "level resumes")
	_teardown(game)


func test_joining_is_ignored_while_picking_upgrades() -> void:
	var world: World = (load("res://src/world/world.tscn") as PackedScene).instantiate()
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	GameState.run_active = false
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = &"knight"
	_tree().root.add_child(world)
	GameState.pending_level_ups = 1
	world._process(DT)
	assert_true(world.level_up.is_open())
	InputRouter.join_requested.emit(PlayerInput.DEVICE_KEYBOARD)
	assert_eq(world.heroes.size(), 1, "no hero drops in mid-pick")
	world.get_parent().remove_child(world)
	world.free()
	_tree().paused = false
	InputRouter.unassign_all()
	GameState.clear_players()
