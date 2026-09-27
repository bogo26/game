extends "res://tests/test_case.gd"

const T := LevelGrid.TILE


## 10x10 room: border walls plus a 1-tile wall column at x=5 (rows 1..8).
func _room() -> LevelGrid:
	var g := LevelGrid.new(10, 10)
	for i in 10:
		g.set_solid(i, 0, true)
		g.set_solid(i, 9, true)
		g.set_solid(0, i, true)
		g.set_solid(9, i, true)
	for y in range(1, 9):
		g.set_solid(5, y, true)
	return g


func test_out_of_bounds_is_solid() -> void:
	var g := LevelGrid.new(4, 4)
	assert_true(g.is_solid(-1, 0))
	assert_true(g.is_solid(0, 4))
	assert_false(g.is_solid(1, 1))


func test_slides_along_wall_without_entering_it() -> void:
	var g := _room()
	var start := Vector2(3.5 * T, 4.5 * T)
	var r := 5.0
	var end := g.move_and_slide(start, Vector2(40, 10), r)
	assert_true(end.x + r <= 5 * T, "stopped at the wall's left face (x=%f)" % end.x)
	assert_near(end.x + r, 5 * T, 0.01, "flush against the wall")
	assert_near(end.y, start.y + 10, 0.001, "y motion still applied")


func test_fast_motion_does_not_tunnel() -> void:
	var g := _room()
	var start := Vector2(2.5 * T, 4.5 * T)
	# A dash worth several tiles in a single frame must still stop at the wall.
	var end := g.move_and_slide(start, Vector2(6 * T, 0), 5.0)
	assert_true(end.x < 5 * T, "did not pass through the 1-tile wall")


func test_moving_left_stops_at_right_face() -> void:
	var g := _room()
	var start := Vector2(7.5 * T, 3.5 * T)
	var end := g.move_and_slide(start, Vector2(-50, 0), 4.0)
	assert_near(end.x - 4.0, 6 * T, 0.01)


func test_line_of_sight() -> void:
	var g := _room()
	assert_true(g.line_of_sight(Vector2(1.5 * T, 1.5 * T), Vector2(4.5 * T, 8.5 * T)), "same side")
	assert_false(g.line_of_sight(Vector2(2.5 * T, 4.5 * T), Vector2(7.5 * T, 4.5 * T)), "blocked by wall")


func test_a_clear_walk_is_stopped_by_whatever_stops_walkers() -> void:
	var g := LevelGrid.new(20, 5)
	var a := LevelGrid.cell_center(Vector2i(1, 2))
	var b := LevelGrid.cell_center(Vector2i(18, 3))
	assert_true(g.walk_line_clear(a, b), "open floor")
	g.set_terrain(9, 2, LevelGrid.Terrain.WATER)
	g.set_terrain(9, 3, LevelGrid.Terrain.WATER)
	assert_true(g.walk_line_clear(a, b), "water slows walkers but doesn't stop them")
	g.set_chasm(10, 2)
	g.set_chasm(10, 3)
	assert_false(g.walk_line_clear(a, b), "a chasm does")
	assert_true(g.line_of_sight(a, b), "though sight crosses it")
	g = LevelGrid.new(20, 5)
	g.set_blocker(12, 3, true)
	assert_false(g.walk_line_clear(a, b), "so does a barrel")
	assert_true(g.line_of_sight(a, b), "which shots fly past")
	g.set_blocker(12, 3, false)
	g.set_solid(15, 3, true)
	assert_false(g.walk_line_clear(a, b), "and a wall")
	assert_false(g.line_of_sight(a, b))
	assert_false(g.walk_line_clear(Vector2(-8, 40), b), "and the edge of the grid")


func test_sweep_until_blocked_stops_before_wall() -> void:
	var g := _room()
	var end := g.sweep_until_blocked(Vector2(2.5 * T, 4.5 * T), Vector2(8.5 * T, 4.5 * T), 4.0)
	assert_true(end.x + 4.0 <= 5 * T)
	assert_true(end.x > 3.5 * T, "moved some distance")


func test_nearest_open() -> void:
	var g := _room()
	var p := g.nearest_open(Vector2(5.5 * T, 4.5 * T))
	var c := g.cell_of(p)
	assert_false(g.is_solid(c.x, c.y))
	assert_true(absi(c.x - 5) == 1, "adjacent to the wall column")
