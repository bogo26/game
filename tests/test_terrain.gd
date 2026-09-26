extends "res://tests/test_case.gd"
## Terrain: chasms (no walking, shots fly over, enemies knocked in fall),
## water (slows everyone), spike traps (waves that stab heroes and enemies),
## and arena rooms owning everything inside their walls.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0
const T := LevelGrid.TILE

## 20x7 room; a chasm column at x=10 (rows 1-5) splits it in two.
const CHASM_ROOM := """
####################
#P........:........#
#.........:........#
#.........:........#
#.........:........#
#.........:........#
####################
"""


func _data(layout: String) -> LevelData:
	var d := LevelData.new()
	d.display_name = "Terrain test"
	d.layout = layout
	d.corridor_spawn_rate = 0.0
	d.arena_quotas = PackedInt32Array([0, 0, 0])
	return d


func _swarmer() -> EnemyData:
	var d := EnemyData.new()
	d.id = &"test"
	d.max_hp = 10.0
	d.speed = 40.0
	d.radius = 5.0
	d.xp = 3
	return d


func _horde(level: Level) -> HordeSim:
	var flow := FlowField.new()
	flow.setup(level.grid)
	var types: Array[EnemyData] = [_swarmer()]
	var h := HordeSim.new()
	h.setup(level.grid, flow, types)
	return h


func _level(layout: String) -> Level:
	var level := Level.new()
	level.build(_data(layout))
	return level


# --- chasms --------------------------------------------------------------------------

func test_chasms_block_walking_but_not_shots_or_sight() -> void:
	var level := _level(CHASM_ROOM)
	var g := level.grid
	assert_true(g.is_solid(10, 3), "can't walk into the chasm")
	assert_false(g.is_shot_solid(10, 3), "but it doesn't stop shots")
	assert_eq(g.terrain[3 * g.width + 10], LevelGrid.Terrain.CHASM)
	var stopped := g.move_and_slide(LevelGrid.cell_center(Vector2i(8, 3)), Vector2(60, 0), 5.0)
	assert_true(stopped.x < 10 * T - 4.0, "walker stops at the edge (x=%.1f)" % stopped.x)
	assert_true(g.line_of_sight(LevelGrid.cell_center(Vector2i(4, 3)), LevelGrid.cell_center(Vector2i(16, 3))),
		"sight crosses the chasm")
	g.set_solid(10, 3, true)
	assert_false(g.line_of_sight(LevelGrid.cell_center(Vector2i(4, 3)), LevelGrid.cell_center(Vector2i(16, 3))),
		"a wall still blocks it")
	level.free()


func test_shots_fly_over_chasms() -> void:
	var level := _level(CHASM_ROOM)
	var h := _horde(level)
	h.spawn(0, LevelGrid.cell_center(Vector2i(15, 3)))
	h.update(0.0, PackedVector2Array())
	var shots := ProjectileSim.new()
	shots.spawn(LevelGrid.cell_center(Vector2i(4, 3)) + Vector2(0, -6), Vector2(300, 0), 4.0, 3.0, 2.0,
		ProjectileSim.Team.PLAYER, 0, ProjectileSim.Look.ARROW)
	for frame in 60:
		shots.update(DT, h, level.grid, PackedVector2Array(), PackedByteArray(), 5.0)
	assert_near(h.hp[0], 6.0, 0.001, "arrow crossed the chasm and hit")
	level.free()


func test_enemies_only_fall_when_knocked_in() -> void:
	var level := _level(CHASM_ROOM)
	var h := _horde(level)
	var edge := Vector2(10 * T - 6.0, 3.5 * T)  # standing right at the edge
	h.spawn(0, edge)
	h.update(0.0, PackedVector2Array())
	h.push(0, Vector2(20, 0), 1)  # a nudge isn't enough
	for frame in 30:
		h.update(DT, PackedVector2Array())
	assert_eq(h.count, 1, "nudged enemy keeps its footing")
	assert_true(h.pos[0].x < 10 * T, "still on the floor")
	h.push(0, Vector2(180, 0), 2)  # a real shove
	var fell := false
	for frame in 60:
		h.update(DT, PackedVector2Array())
		fell = fell or h.falls > 0
	assert_true(fell, "went over the edge")
	assert_eq(h.count, 0, "gone after the fall")
	assert_eq(h.kill_slot.size(), 1)
	assert_eq(h.kill_slot[0], 2, "the shover gets the kill")
	level.free()


func test_falling_enemies_cannot_be_hit_or_hurt_anyone() -> void:
	var level := _level(CHASM_ROOM)
	var h := _horde(level)
	h.spawn(0, Vector2(10 * T - 6.0, 3.5 * T))
	h.update(0.0, PackedVector2Array())
	h.push(0, Vector2(180, 0), 0)
	for frame in 10:
		h.update(DT, PackedVector2Array())
		if h.is_falling(0):
			break
	assert_true(h.is_falling(0))
	assert_false(h.damage(0, 100.0, Vector2.ZERO, 1), "no hits on the way down")
	assert_near(h.contact_damage_at(h.pos[0], 5.0), 0.0, 0.001, "no contact damage either")
	assert_eq(h.nearest(h.pos[0], 50.0), -1, "not a target")
	level.free()


# --- water ---------------------------------------------------------------------------

func test_water_slows_enemies() -> void:
	var level := _level("""
####################
#P.................#
#~~~~~~~~~~~~~~~~~~#
#..................#
####################
""")
	var h := _horde(level)
	var wet := h.spawn(0, LevelGrid.cell_center(Vector2i(2, 2)))
	var dry := h.spawn(0, LevelGrid.cell_center(Vector2i(2, 3)))
	h.update(0.0, PackedVector2Array())
	var start_wet := h.pos[wet].x
	var start_dry := h.pos[dry].x
	var targets := PackedVector2Array([Vector2(1000, 2.5 * T), Vector2(1000, 3.5 * T)])
	for frame in 30:
		h.update(DT, targets)
	var ratio := (h.pos[wet].x - start_wet) / (h.pos[dry].x - start_dry)
	assert_near(ratio, LevelGrid.WATER_SPEED, 0.08, "wading is slower (ratio %.2f)" % ratio)
	level.free()


func _make_world(data: LevelData) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = &"knight"
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.spawn_enemies = false
	world.level_ups_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.bots = null
	return world


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	(Engine.get_main_loop() as SceneTree).paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


## How far hero 0 walks right in `frames` starting from `start`.
func _walk(world: World, start: Vector2, frames: int) -> float:
	var hero := world.heroes[0]
	hero.position = start
	hero.velocity = Vector2.ZERO
	for f in frames:
		hero.input.move = Vector2.RIGHT
		hero.tick(DT)
	hero.input.move = Vector2.ZERO
	return hero.position.x - start.x


func test_water_slows_heroes() -> void:
	var world := _make_world(_data("""
######################
#P...................#
#~~~~~~~~~~~~~~~~~~~~#
#....................#
######################
"""))
	var wet := _walk(world, LevelGrid.cell_center(Vector2i(2, 2)), 30)
	var dry := _walk(world, LevelGrid.cell_center(Vector2i(2, 3)), 30)
	assert_true(wet < dry * 0.75, "wading %.1f px vs %.1f px on dry floor" % [wet, dry])
	_teardown(world)


func test_knocked_off_enemies_drop_xp_on_the_floor() -> void:
	var world := _make_world(_data(CHASM_ROOM))
	var horde := world.horde
	var i := horde.spawn(0, Vector2(10 * T - 6.0, 3.5 * T))
	horde.update(0.0, world.target_positions)
	horde.push(i, Vector2(200, 0), 0)
	for frame in 60:
		world._process(DT)
	assert_eq(horde.count, 0, "fell")
	assert_true(world.pickups.count > 0, "dropped its XP")
	for k in world.pickups.count:
		assert_false(world.grid.is_solid_at(world.pickups.pos[k]), "gem lands on walkable floor")
	_teardown(world)


# --- spike traps -------------------------------------------------------------------------

func test_spike_trap_cycle() -> void:
	var t_warn := SpikeTraps.PERIOD - SpikeTraps.UP_TIME - SpikeTraps.WARN_TIME
	var t_up := SpikeTraps.PERIOD - SpikeTraps.UP_TIME
	assert_eq(SpikeTraps.state_at(0, 0.1), SpikeTraps.State.DOWN)
	assert_eq(SpikeTraps.state_at(0, t_warn + 0.01), SpikeTraps.State.WARN)
	assert_eq(SpikeTraps.state_at(0, t_up + 0.01), SpikeTraps.State.UP)
	assert_eq(SpikeTraps.state_at(0, SpikeTraps.PERIOD + 0.01), SpikeTraps.State.DOWN, "repeats")
	# Groups go off a third of a period apart: a wave.
	var shift := SpikeTraps.PERIOD / SpikeTraps.GROUPS
	assert_eq(SpikeTraps.state_at(1, t_up - shift + 0.01), SpikeTraps.State.UP)
	assert_eq(SpikeTraps.state_at(0, t_up - shift + 0.01), SpikeTraps.State.DOWN)


func test_spikes_stab_heroes_and_enemies_standing_on_them() -> void:
	# Cells (4..6, 1..2): pick a trap for the hero and a same-group trap for an enemy.
	var world := _make_world(_data("""
############
#P..^^^....#
#...^^^....#
############
"""))
	var hero := world.heroes[0]
	var by_group := {}
	for c in world.level.spike_cells:
		by_group.get_or_add(SpikeTraps.group_for(c), []).append(c)
	var pair: Array = []
	for g: int in by_group:
		if (by_group[g] as Array).size() >= 2:
			pair = by_group[g]
	assert_true(pair.size() >= 2, "test setup: two traps in the same wave")
	var trap: Vector2i = pair[0]
	var other: Vector2i = pair[1]
	hero.position = LevelGrid.cell_center(trap)
	hero.invulnerable_time = 0.0
	var horde := world.horde
	horde.spawn(0, LevelGrid.cell_center(other))
	horde.spawn(0, LevelGrid.cell_center(Vector2i(9, 2)))
	for i in horde.count:
		horde.apply_stun(i, 60.0)  # stand still, no contact damage
	var hp0 := hero.hp
	var stabbed := false
	for frame in int(SpikeTraps.PERIOD / DT) + 5:
		world._process(DT)
		if hero.hp < hp0:
			stabbed = true
			break
	world._process(DT)  # remove the dead
	assert_true(stabbed, "hero on the trap got stabbed")
	assert_near(hp0 - hero.hp, SpikeTraps.HERO_DAMAGE - hero.armor, 0.01, "by the spikes, nothing else")
	assert_eq(horde.count, 1, "enemy on a trap died, the one beside lived")
	if horde.count == 1:
		assert_true(horde.pos[0].distance_to(LevelGrid.cell_center(Vector2i(9, 2))) < 1.0, "survivor is beside the traps")
	_teardown(world)


# --- arena rooms ---------------------------------------------------------------------------

func test_arena_rooms_own_everything_inside_their_walls() -> void:
	var level := _level("""
##############
#P...D1111111#
#....#1~~:^11#
#....#1bu111N#
#....D111C11A#
##############
""")
	var room := level.room_at_position(LevelGrid.cell_center(Vector2i(7, 2)))
	assert_eq(room, 1, "water cell belongs to the arena")
	for c: Vector2i in [Vector2i(9, 2), Vector2i(10, 2), Vector2i(7, 3), Vector2i(12, 3), Vector2i(9, 4), Vector2i(12, 4)]:
		assert_eq(level.room_at_position(LevelGrid.cell_center(c)), 1, "%s is in the arena" % c)
	assert_eq(level.room_at_position(LevelGrid.cell_center(Vector2i(5, 1))), 0, "doors aren't")
	assert_eq(level.room_at_position(LevelGrid.cell_center(Vector2i(2, 2))), 0, "outside isn't")
	assert_eq((level.room_doors[1] as Array).size(), 2)
	var kinds := {}
	for prop in level.props:
		kinds[prop.kind] = prop.room
	assert_eq(kinds, {&"barrel": 1, &"urn": 1, &"nest": 1, &"chest": 1, &"shrine": 1}, "props know their room")
	assert_eq(level.spike_cells.size(), 1)
	assert_eq(level.spike_cells[0], Vector2i(10, 2))
	level.free()
