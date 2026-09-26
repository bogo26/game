extends "res://tests/test_case.gd"
## Run flow: pick rounds (titles, timing around level banners and level ends),
## the arena objective and arrow, blasts and walls, and the menu guards
## against accidental presses.

const GAME_SCENE := "res://src/main/game.tscn"
const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0

## Arena 1 is right under the spawn but its only door is at the end of a
## winding corridor; arena 2 is further away in a straight line but its door
## is a few steps from the spawn.
const TWO_ARENAS := """
########################
#P....D2222222222222222#
#####.##################
#111#.#
#111#.#
#111#.#
##D##.#
#...#.#
#...#.#
#.....#
#######
"""

## A wall between a hero and a blast.
const WALLED := """
##########
#P...#...#
##########
"""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _data(layout: String, quotas: PackedInt32Array = PackedInt32Array([0, 0, 0])) -> LevelData:
	var d := LevelData.new()
	d.display_name = "Run flow test"
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
	_tree().root.add_child(world)
	world.bots = null
	return world


func _teardown(node: Node) -> void:
	node.get_parent().remove_child(node)
	node.free()
	_tree().paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


func _start_run() -> Node:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in 2:
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = &"knight"
	GameState.level_index = 0
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(game)
	return game


# --- pick rounds -------------------------------------------------------------------------------

func test_pick_round_titles_follow_the_queue() -> void:
	GameState.reset_run()
	GameState.add_xp(GameState.xp_to_next())  # level 2
	GameState.add_xp(GameState.xp_to_next())  # level 3
	GameState.add_treasure_pick()             # a chest: shown first
	assert_eq(GameState.pending_level_ups, 3)
	assert_eq(GameState.pending_treasures, 1)
	var titles: Array[String] = []
	while GameState.pending_level_ups > 0:
		titles.append(LevelUpScreen.round_title(GameState.next_round()))
		GameState.pop_round()
	assert_eq(titles, ["TREASURE!  PICK AN UPGRADE", "LEVEL 2!  PICK AN UPGRADE",
		"LEVEL 3!  PICK AN UPGRADE"] as Array[String])
	GameState.pending_level_ups = 2  # debug / test picks
	assert_eq(LevelUpScreen.round_title(GameState.next_round()), "BONUS!  PICK AN UPGRADE",
		"picks that aren't level-ups never show a made-up level")
	GameState.reset_run()


func test_last_pick_shows_picked_before_the_screen_closes() -> void:
	var world := _make_world(_data(WALLED))
	GameState.pending_level_ups = 1
	world._process(DT)
	assert_true(world.level_up.is_open())
	var t := 0.0
	while t < 1.0 and not world.level_up.is_round_finished():
		InputRouter._process(DT)
		world.level_up._process(DT)
		t += DT
	assert_true(world.level_up.is_round_finished(), "the bot picked")
	assert_true(world.level_up.is_open(), "the result stays up for a moment")
	for f in int(LevelUpScreen.ROUND_END_DELAY / DT) + 2:
		world.level_up._process(DT)
	assert_false(world.level_up.is_open(), "then the game resumes")
	_teardown(world)


func test_pick_rounds_wait_for_the_level_banner() -> void:
	var game := _start_run()
	var world: World = game.get("world")
	GameState.pending_level_ups = 1
	world._process(DT)
	assert_false(world.level_up.is_open(), "no pick screen under the level banner")
	world.level_up_delay = 0.0
	world._process(DT)
	assert_true(world.level_up.is_open(), "it opens once the banner is gone")
	_teardown(game)


func test_rounds_earned_as_a_level_ends_carry_over() -> void:
	var game := _start_run()
	var world: World = game.get("world")
	world.level_up_delay = 0.0
	world.level_ups_enabled = false  # what the Game does when the exit is reached
	GameState.pending_level_ups = 1
	world._process(DT)
	assert_false(world.level_up.is_open(), "no pick screen once the level is over")
	assert_false(_tree().paused, "so nothing pauses the level change")
	assert_eq(GameState.pending_level_ups, 1, "the round waits for the next level")
	_teardown(game)


func test_the_mini_boss_does_not_end_the_run() -> void:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in 2:
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = &"knight"
	GameState.level_index = 3
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(game)
	assert_eq((game.get_node("%Banner") as Label).text, "MINI BOSS")
	assert_eq((game.get_node("%BannerSub") as Label).text, "The Ossuary")
	var world: World = game.get("world")
	var room: LevelDirector.Room = world.director.rooms[0]
	for hero in world.heroes:
		hero.god_mode = true
		hero.position = world.grid.nearest_open(room.center + Vector2(0, 60))
	for f in 2:
		world._process(DT)
	assert_true(world.boss is BoneColossus)
	world.horde.damage(world.horde.index_of_uid(world.boss.uid), 1e9, Vector2.ZERO, 0)
	for f in 3:
		world._process(DT)
	assert_true(world.boss == null, "the Colossus is dead")
	assert_false(game.get("_ending"), "but the run goes on")
	assert_true(world.director.exit_open, "through the exit behind its hall")
	_teardown(game)
	GameState.level_index = 0


func test_a_new_level_never_starts_paused() -> void:
	var game := _start_run()
	_tree().paused = true  # e.g. a pick screen was still open when the old level ended
	game.call("_load_level")
	var world: World = game.get("world")
	assert_false(_tree().paused, "the next level isn't frozen")
	assert_true(world.can_process())
	_teardown(game)


# --- objectives ------------------------------------------------------------------------------

func test_arrow_points_to_the_arena_nearest_on_foot() -> void:
	var world := _make_world(_data(TWO_ARENAS))
	var director := world.director
	director._update_objective()
	assert_vec_near(director.objective_target, director.room_by_id(2).center, 0.01,
		"arena 2 is 6 steps away; arena 1 is closer in a straight line but 19 steps on foot")
	_teardown(world)


func test_walk_distances() -> void:
	var world := _make_world(_data(TWO_ARENAS))
	var grid := world.grid
	var dist := grid.walk_distances(Vector2i(1, 1))
	assert_eq(dist[1 * grid.width + 7], 6, "first cell of arena 2")
	assert_eq(dist[5 * grid.width + 2], 19, "arena 1 through its door")
	assert_eq(dist[0], -1, "walls are unreachable")
	_teardown(world)


func test_arena_objective_counts_enemies_left() -> void:
	var world := _make_world(_data(TWO_ARENAS, PackedInt32Array([5, 7])))
	var director := world.director
	var room := director.room_by_id(2)
	director._activate(room, world.heroes[0])
	assert_eq(director.enemies_left(), 7, "nothing spawned yet: the whole quota")
	assert_eq(director.objective, "Wave 1/2  -  7 left")
	var t := world.horde.type_index(&"swarmer")
	for k in 3:  # the spawner lets three in
		world.horde.spawn(t, LevelGrid.cell_center(room.cells[k * 3]), 1.0)
	world.spawner.arena_remaining -= 3
	director._check_timer = 0.0
	director._tick_active_room(DT)
	assert_eq(director.enemies_left(), 7, "3 inside + 4 still to come")
	director.on_enemy_killed()
	assert_eq(director.objective, "Wave 1/2  -  6 left")
	_teardown(world)


# --- blasts and walls ------------------------------------------------------------------------

func test_blasts_do_not_hurt_through_walls() -> void:
	var world := _make_world(_data(WALLED))
	var hero := world.heroes[0]
	hero.invulnerable_time = 0.0  # past the spawn protection
	hero.position = LevelGrid.cell_center(Vector2i(4, 1))
	var blast := LevelGrid.cell_center(Vector2i(6, 1))
	world.horde.blast_pos.append(blast)
	world.horde.blast_radius.append(30.0)
	world.horde.blast_damage.append(22.0)
	world._apply_blasts()
	assert_eq(hero.hp, hero.max_hp, "the wall took the blast")
	world.grid.set_solid(5, 1, false)
	world.horde.blast_pos.append(blast)
	world.horde.blast_radius.append(30.0)
	world.horde.blast_damage.append(22.0)
	world._apply_blasts()
	assert_true(hero.hp < hero.max_hp, "with the wall gone it hits")
	_teardown(world)


# --- menus -----------------------------------------------------------------------------------

func test_quit_to_menu_needs_a_second_press() -> void:
	var menu: PauseMenu = (load("res://src/ui/pause_menu.tscn") as PackedScene).instantiate()
	_tree().root.add_child(menu)
	var quits := [0]
	menu.quit_requested.connect(func() -> void: quits[0] += 1)
	menu.open()
	menu._on_quit_pressed()
	assert_eq(quits[0], 0, "the first press only asks")
	assert_eq((menu.get_node("%QuitButton") as Button).text, PauseMenu.QUIT_CONFIRM_TEXT)
	menu._on_quit_pressed()
	assert_eq(quits[0], 1, "the second press quits")
	menu.close()
	menu._on_quit_pressed()
	menu._opened_this_frame = false
	menu.visible = true
	menu._process(PauseMenu.QUIT_CONFIRM_TIME + 0.1)
	assert_eq((menu.get_node("%QuitButton") as Button).text, PauseMenu.QUIT_TEXT, "the question times out")
	_teardown(menu)


func test_end_screen_ignores_input_at_first() -> void:
	GameState.reset_run()
	GameState.run_active = false
	var screen: Control = (load("res://src/ui/end_screen.tscn") as PackedScene).instantiate()
	_tree().root.add_child(screen)
	var again: Button = screen.get_node("%AgainButton")
	assert_true(again.disabled, "buttons start disabled")
	screen._process(0.7)
	assert_false(again.disabled, "and wake up after the grace time")
	_teardown(screen)
