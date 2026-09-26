extends "res://tests/test_case.gd"
## Minimap: what counts as explored, when the overlay shows (only while MAP
## is held), and what it paints.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0


func _make_world() -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_KEYBOARD)
	GameState.slots[0].hero_id = &"knight"
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = RunConfig.load_default().levels[0]
	world.run_mode = true
	world.spawn_enemies = false
	world.level_ups_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	return world


func _teardown(world: World) -> void:
	_key(KEY_TAB, false)
	_key(KEY_M, false)
	world.get_parent().remove_child(world)
	world.free()
	(Engine.get_main_loop() as SceneTree).paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _frames(world: World, n: int) -> void:
	for i in n:
		InputRouter._process(DT)
		if not world.get_tree().paused:
			world._process(DT)
		world.hud.minimap._process(DT)


func _pixel(world: World, cell: Vector2i) -> Color:
	world.hud.minimap.refresh()
	return world.hud.minimap._image.get_pixel(cell.x, cell.y)


## The map image stores 8-bit colours.
func assert_color(actual: Color, expected: Color, message: String = "") -> void:
	var close := absf(actual.r - expected.r) < 0.004 and absf(actual.g - expected.g) < 0.004 \
		and absf(actual.b - expected.b) < 0.004 and absf(actual.a - expected.a) < 0.004
	assert_true(close, "expected %s, got %s. %s" % [expected, actual, message])


func test_reveal_marks_what_the_camera_saw() -> void:
	var reveal := MapReveal.new()
	reveal.setup(100, 60)
	reveal.reveal_rect(Rect2(160, 160, 640, 360))  # cells 10..50 x 10..32.5, plus a 2-tile margin
	assert_true(reveal.is_seen(Vector2i(8, 8)), "margin counts")
	assert_true(reveal.is_seen(Vector2i(52, 34)))
	assert_false(reveal.is_seen(Vector2i(53, 20)), "past the margin")
	assert_false(reveal.is_seen(Vector2i(5, 5)))
	assert_eq(reveal.fresh.size(), 45 * 27)
	assert_eq(reveal.seen_count, 45 * 27)
	reveal.fresh.clear()
	reveal.reveal_rect(Rect2(160, 160, 640, 360))
	assert_eq(reveal.fresh.size(), 0, "seeing a tile again isn't news")


func test_map_shows_only_while_map_is_held() -> void:
	var world := _make_world()
	var minimap := world.hud.minimap
	_frames(world, 5)
	assert_false(minimap.is_shown(), "hidden by default")
	_key(KEY_TAB, true)
	_frames(world, 5)
	assert_true(minimap.is_shown(), "Tab shows it")
	_key(KEY_TAB, false)
	_frames(world, 10)
	assert_false(minimap.is_shown(), "gone when released")
	_key(KEY_M, true)
	_frames(world, 5)
	assert_true(minimap.is_shown(), "M works too")
	world.get_tree().paused = true
	_frames(world, 10)
	assert_false(minimap.is_shown(), "not over the pause / upgrade screens")
	_teardown(world)


func test_map_paints_only_seen_tiles() -> void:
	var world := _make_world()
	_frames(world, 2)
	var start := world.grid.cell_of(world.heroes[0].position)
	var exit := world.grid.cell_of(world.level.exit_center())
	assert_color(_pixel(world, start), Minimap.COLOR_FLOOR, "start room is on the map")
	assert_eq(_pixel(world, exit).a, 0.0, "the far-away exit isn't yet")
	world.reveal.reveal_rect(Rect2(world.level.exit_center() - Vector2(40, 40), Vector2(80, 80)))
	assert_color(_pixel(world, exit), Minimap.COLOR_EXIT, "seen exit shows up")
	_teardown(world)


func test_arena_state_and_locked_doors_show() -> void:
	var world := _make_world()
	world.reveal.reveal_rect(Rect2(Vector2.ZERO, world.grid.size_px()))
	var room: LevelDirector.Room = world.director.rooms[0]
	var door: Vector2i = room.doors[0]
	var floor_cell: Vector2i = room.cells[room.cells.size() / 2]
	assert_color(_pixel(world, floor_cell), Minimap.COLOR_ARENA)
	assert_color(_pixel(world, door), Minimap.COLOR_DOOR)
	world.heroes[0].position = world.grid.nearest_open(room.center)
	_frames(world, 2)
	assert_eq(room.state, LevelDirector.RoomState.ACTIVE)
	assert_color(_pixel(world, floor_cell), Minimap.COLOR_ARENA_ACTIVE, "active arena turns red")
	assert_color(_pixel(world, door), Minimap.COLOR_DOOR_LOCKED, "locked doors show")
	_teardown(world)


func test_every_level_fits_on_screen() -> void:
	var world := _make_world()
	var minimap := world.hud.minimap
	var view := minimap.get_viewport_rect().size
	for data in RunConfig.load_default().levels:
		var level := Level.new()
		level.build(data)
		world.grid = level.grid
		var s := minimap.map_scale()
		assert_true(s >= 1.0 and s == floorf(s), "%s: whole pixels per tile (%.2f)" % [data.display_name, s])
		var origin := minimap.map_origin()
		var size := Vector2(level.grid.width, level.grid.height) * s
		assert_true(origin.x >= 0.0 and origin.y >= Minimap.TITLE_HEIGHT and origin.x + size.x <= view.x
			and origin.y + size.y <= view.y - Minimap.LEGEND_HEIGHT, "%s fits" % data.display_name)
		level.free()
	world.grid = world.level.grid
	_teardown(world)
