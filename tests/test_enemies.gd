extends "res://tests/test_case.gd"
## Each level's own enemy: bats (Crypt Entrance), drowned (Flooded Halls),
## bone archers (Bone Pits), revenants (the Ossuary), sporecaps (Fungal
## Caverns), frost boars (Frozen Vaults), salamanders (Molten Forge) and imps
## (Demon's Throne) - and that every level of the run has one of its own,
## the other bosses' levels included (their servants are in test_new_bosses).

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0
const T := LevelGrid.TILE
## Every level's own enemy, by level name.
const OWN := {
	"Crypt Entrance": &"bat", "Flooded Halls": &"drowned", "Bone Pits": &"bone_archer",
	"The Ossuary": &"revenant", "Fungal Caverns": &"sporecap", "Frozen Vaults": &"frost_boar",
	"Molten Forge": &"salamander", "Demon's Throne": &"imp",
	"Toadstool Hollow": &"sporeling", "The Sunken Cistern": &"eel", "The Mycelium Deep": &"puffball",
	"The Frozen Court": &"frost_wraith",
}

const ROOM := """
##############################
#P...........................#
#............................#
#............................#
#............................#
#............................#
#............................#
#............................#
#............................#
##############################
"""

## A dry row (y=1), a wet row (y=2) and a chasm column at x=10 (rows 4-6).
const WET_ROOM := """
####################
#P.................#
#~~~~~~~~~~~~~~~~~~#
#..................#
#.........:........#
#.........:........#
#.........:........#
####################
"""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _data(layout: String) -> LevelData:
	var d := LevelData.new()
	d.display_name = "Enemy test"
	d.layout = layout
	d.corridor_spawn_rate = 0.0
	d.arena_quotas = PackedInt32Array([0, 0, 0])
	return d


func _make_world(layout: String = ROOM) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = &"knight"
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = _data(layout)
	world.spawn_enemies = false
	world.level_ups_enabled = false
	_tree().root.add_child(world)
	world.bots = null
	world.heroes[0].invulnerable_time = 0.0
	return world


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	_tree().paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


func _run(world: World, seconds: float) -> void:
	for f in int(ceilf(seconds / DT)):
		world._process(DT)


## Runs frames until `done` returns true (at most `seconds`).
func _run_until(world: World, done: Callable, seconds: float = 3.0) -> void:
	for f in int(seconds / DT):
		if done.call():
			return
		world._process(DT)


## A bare horde (no World) of the shipped enemy kinds `ids` on `layout`.
func _horde(level: Level, ids: Array[StringName]) -> HordeSim:
	var types: Array[EnemyData] = []
	for id in ids:
		types.append(load("res://src/enemies/data/%s.tres" % id) as EnemyData)
	var flow := FlowField.new()
	flow.setup(level.grid)
	var h := HordeSim.new()
	h.setup(level.grid, flow, types)
	h.projectiles = ProjectileSim.new()
	return h


func _level(layout: String) -> Level:
	var level := Level.new()
	level.build(_data(layout))
	return level


# --- the run ---------------------------------------------------------------------------------

func test_every_level_has_an_enemy_of_its_own() -> void:
	var run := RunConfig.load_default()
	var known: Array[StringName] = []
	for path in World.ENEMY_TYPES:
		known.append((load(path) as EnemyData).id)
	# Every level a run can meet: the run's levels and the other bosses' levels.
	var levels: Array[LevelData] = []
	levels.append_array(run.levels)
	levels.append_array(run.boss_pool)
	for index in levels.size():
		var data := levels[index]
		var own: Array[StringName] = []
		for id: StringName in data.enemy_weights:
			assert_true(id in known, "%s: %s is an enemy" % [data.display_name, id])
			var elsewhere := false
			for other in levels.size():
				if other != index and levels[other].enemy_weights.has(id):
					elsewhere = true
			if not elsewhere and float(data.enemy_weights[id]) > 0.0:
				own.append(id)
		assert_true(OWN.has(data.display_name), "%s is listed" % data.display_name)
		assert_true(OWN.get(data.display_name) in own, "%s has its own enemy (%s)" % [data.display_name, own])
		if index < run.alternates.size() and run.alternates[index]:
			assert_eq(run.alternates[index].enemy_weights, data.enemy_weights,
				"%s: the second layout meets the same enemies" % data.display_name)
	assert_eq(levels.size(), OWN.size(), "every level is in the table")


func test_bosses_bring_their_own() -> void:
	var dead := Boss._crowd(BoneColossus.RAISE_COUNT, &"revenant", BoneColossus.RAISE_REVENANTS)
	assert_eq(dead.size(), BoneColossus.RAISE_COUNT)
	assert_eq(dead.count(&"revenant"), BoneColossus.RAISE_REVENANTS, "the Colossus raises revenants")
	var adds := Boss._crowd(BossDemon.SUMMON_COUNT, &"imp", BossDemon.SUMMON_IMPS)
	assert_eq(adds.count(&"imp"), BossDemon.SUMMON_IMPS, "the Demon Lord summons imps")
	for k in adds.size() - 1:
		assert_false(adds[k] == &"imp" and adds[k + 1] == &"imp", "spread around the ring")
	var world := _make_world()
	var boss: BossDemon = (load("res://src/enemies/boss/boss_demon.tscn") as PackedScene).instantiate()
	var at := LevelGrid.cell_center(Vector2i(15, 4))
	boss.setup(world, at, 1.0, 1.0)
	world.entities.add_child(boss)
	boss.wind_up(BossDemon.Attack.SUMMON, at, world.heroes[0].position)
	var imp := world.horde.type_index(&"imp")
	assert_eq(Array(world.spawner._pending_type).count(imp), BossDemon.SUMMON_IMPS, "imps wait in the portals")
	boss.get_parent().remove_child(boss)
	boss.free()
	_teardown(world)


# --- bats ------------------------------------------------------------------------------------

func test_bats_come_in_flocks() -> void:
	var level := _level(ROOM)
	var h := _horde(level, [&"bat"])
	var hero := LevelGrid.cell_center(Vector2i(15, 5))
	h.flow.compute_now(PackedVector2Array([hero]))
	var spawner := SpawnDirector.new()
	var hints: Array[Vector2] = []
	spawner.setup(h, level.grid, h.flow, hints)
	spawner.set_weights({&"bat": 1.0})
	spawner.spawn_rate = 1.0
	spawner.tick(1.0, Rect2(hero - Vector2(100, 50), Vector2(200, 100)), PackedVector2Array([hero]))
	assert_eq(h.count, 3, "one spawn is a whole flock")
	for i in h.count:
		assert_true(h.pos[i].distance_to(h.pos[0]) <= SpawnDirector.PACK_SPREAD * 2.0, "flying together")
	level.free()


func test_bats_weave_and_fly_over_water() -> void:
	var level := _level(WET_ROOM)
	var h := _horde(level, [&"bat"])
	assert_near(h.t_water[0], 1.0, 0.001, "water doesn't slow a flyer")
	var dry := h.spawn(0, LevelGrid.cell_center(Vector2i(2, 1)))
	var wet := h.spawn(0, LevelGrid.cell_center(Vector2i(2, 2)))
	h.anim[dry] = 0.0
	h.anim[wet] = 0.0
	h.update(0.0, PackedVector2Array())
	var start := h.pos[wet]
	var dry_start := h.pos[dry]
	var targets := PackedVector2Array([Vector2(1000, 1.5 * T), Vector2(1000, 2.5 * T)])
	var low := start.y
	var high := start.y
	for frame in 40:
		h.update(DT, targets)
		low = minf(low, h.pos[wet].y)
		high = maxf(high, h.pos[wet].y)
	assert_true(high - low > 3.0, "flutters from side to side (%.1f px)" % (high - low))
	var ratio := (h.pos[wet].x - start.x) / (h.pos[dry].x - dry_start.x)
	assert_near(ratio, 1.0, 0.15, "as fast over water as over floor (ratio %.2f)" % ratio)
	level.free()


func test_bats_never_go_over_a_chasm_edge() -> void:
	var level := _level(WET_ROOM)
	var h := _horde(level, [&"bat"])
	h.spawn(0, Vector2(10 * T - 6.0, 5.5 * T))
	h.update(0.0, PackedVector2Array())
	h.push(0, Vector2(250, 0), 1)
	for frame in 60:
		h.update(DT, PackedVector2Array())
	assert_eq(h.falls, 0, "a shove doesn't send it down")
	assert_eq(h.count, 1)
	level.free()


# --- drowned ---------------------------------------------------------------------------------

func test_drowned_swim_fast_through_water() -> void:
	var level := _level(WET_ROOM)
	var h := _horde(level, [&"drowned"])
	var dry := h.spawn(0, LevelGrid.cell_center(Vector2i(2, 1)))
	var wet := h.spawn(0, LevelGrid.cell_center(Vector2i(2, 2)))
	h.update(0.0, PackedVector2Array())
	var dry_start := h.pos[dry].x
	var wet_start := h.pos[wet].x
	var targets := PackedVector2Array([Vector2(1000, 1.5 * T), Vector2(1000, 2.5 * T)])
	for frame in 30:
		h.update(DT, targets)
	var ratio := (h.pos[wet].x - wet_start) / (h.pos[dry].x - dry_start)
	assert_near(ratio, h.types[0].swim_speed, 0.2, "swims %.2fx as fast as it walks" % ratio)
	level.free()


func test_drowned_are_drawn_swimming_in_water() -> void:
	var world := _make_world(WET_ROOM)
	var t := world.horde.type_index(&"drowned")
	world.horde.spawn(t, LevelGrid.cell_center(Vector2i(15, 2)))
	world._process(DT)
	var frame := int(world.horde_layer.buffer[8]) - world.horde.types[t].atlas_row * HordeSim.ATLAS_COLUMNS
	assert_true(frame >= 4, "the swim frames (frame %d)" % frame)
	_teardown(world)


# --- bone archers ----------------------------------------------------------------------------

func test_bone_archers_aim_first_and_shoot_along_the_line() -> void:
	var world := _make_world()
	var h := world.horde
	var hero := world.heroes[0]
	hero.god_mode = true
	hero.position = LevelGrid.cell_center(Vector2i(20, 4))
	var t := h.type_index(&"bone_archer")
	var i := h.spawn(t, LevelGrid.cell_center(Vector2i(10, 4)))
	h.action[i] = 0.0
	world._process(DT)
	assert_eq(h.state[i], 1, "drawing its bow")
	var aim := h.aim[i]
	assert_true(aim.x > 0.95, "aimed at the hero")
	assert_eq(world.warn_fx._band_from.size(), 1, "its aim is shown")
	assert_true(world.warn_fx._band_width[0] <= 1.0, "as a line")
	assert_true(world.warn_fx._band_to[0].x > hero.position.x, "running past the hero")
	hero.position += Vector2(0, 48)  # steps out of the line
	_run_until(world, func() -> bool: return world.projectiles.count > 0)
	assert_eq(world.projectiles.count, 1, "looses")
	assert_eq(world.projectiles.look[0], ProjectileSim.Look.SHARD)
	assert_eq(world.projectiles.team[0], ProjectileSim.Team.ENEMY)
	assert_vec_near(world.projectiles.vel[0].normalized(), aim, 0.001, "along the line it showed")
	assert_eq(world.warn_fx._band_from.size(), 0, "the line is gone")
	_teardown(world)


func test_an_archers_line_goes_when_it_dies() -> void:
	var world := _make_world()
	var h := world.horde
	world.heroes[0].position = LevelGrid.cell_center(Vector2i(20, 4))
	var i := h.spawn(h.type_index(&"bone_archer"), LevelGrid.cell_center(Vector2i(10, 4)))
	h.action[i] = 0.0
	world._process(DT)
	assert_eq(world.warn_fx._band_from.size(), 1)
	world.hit_enemy(i, 9999.0, Vector2.ZERO, 0)
	world._process(DT)
	assert_eq(world.warn_fx._band_from.size(), 0, "no line without an archer")
	assert_eq(world.projectiles.count, 0, "and no shot")
	_teardown(world)


# --- revenants -------------------------------------------------------------------------------

func test_revenants_get_back_up_unless_their_bones_are_smashed() -> void:
	var world := _make_world()
	var h := world.horde
	world.heroes[0].god_mode = true
	var revenant := h.type_index(&"revenant")
	var pile := h.type_index(&"bone_pile")
	var i := h.spawn(revenant, LevelGrid.cell_center(Vector2i(20, 6)))
	world.hit_enemy(i, 9999.0, Vector2.ZERO, 0)
	world._process(DT)
	assert_eq(h.count_of_type(revenant), 0)
	assert_eq(h.count_of_type(pile), 1, "it falls apart into a bone pile")
	_run(world, h.types[pile].reform_time + 0.1)
	assert_eq(h.count_of_type(pile), 0)
	assert_eq(h.count_of_type(revenant), 1, "left alone, it gets back up")
	for j in h.count:
		if h.type[j] == revenant:
			world.hit_enemy(j, 9999.0, Vector2.ZERO, 0)
	world._process(DT)
	var kills := world.kills
	var gems := world.pickups.count
	for j in h.count:
		if h.type[j] == pile:
			world.hit_enemy(j, 9999.0, Vector2.ZERO, 0)
	world._process(DT)
	assert_eq(world.kills, kills + 1, "smashing the bones is a kill")
	assert_true(world.pickups.count > gems, "with XP")
	_run(world, h.types[pile].reform_time + 0.5)
	assert_eq(h.count_of_type(revenant) + h.count_of_type(pile), 0, "and it stays down")
	_teardown(world)


func test_bone_piles_count_as_enemies() -> void:
	var world := _make_world()
	var h := world.horde
	var pile := h.type_index(&"bone_pile")
	h.spawn(pile, LevelGrid.cell_center(Vector2i(20, 6)))
	assert_eq(h.enemy_count(), 1, "a pile is an enemy (an arena waits for it)")
	assert_false(h.is_object(0))
	assert_false(h.is_mobile(0), "though it doesn't walk")
	_teardown(world)


# --- sporecaps -------------------------------------------------------------------------------

func test_sporecaps_burst_into_clouds_that_hurt() -> void:
	var world := _make_world()
	var hero := world.heroes[0]
	var t := world.horde.type_index(&"sporecap")
	var i := world.horde.spawn(t, hero.position + Vector2(14, 0))
	world.hit_enemy(i, 9999.0, Vector2.ZERO, 0)
	world._process(DT)
	assert_eq(world._hazards.size(), 1, "a spore cloud where it burst")
	world._process(DT)
	assert_true(hero.hp < hero.max_hp, "hurting the hero standing in it")
	hero.position += Vector2(0, 80)
	var hp := hero.hp
	_run(world, world.horde.types[t].cloud_time)
	assert_near(hero.hp, hp, 0.001, "outside it's safe")
	assert_eq(world._hazards.size(), 0, "then the cloud settles")
	_teardown(world)


# --- frost boars -----------------------------------------------------------------------------

func test_frost_boars_line_up_then_charge() -> void:
	var world := _make_world()
	var h := world.horde
	var hero := world.heroes[0]
	hero.god_mode = true
	hero.position = LevelGrid.cell_center(Vector2i(10, 4))
	var t := h.type_index(&"frost_boar")
	var i := h.spawn(t, LevelGrid.cell_center(Vector2i(18, 4)))
	h.action[i] = 0.0
	world._process(DT)
	assert_eq(h.state[i], 1, "lining up")
	assert_eq(world.warn_fx._band_from.size(), 1, "the band it will charge down is shown")
	assert_near(world.warn_fx._band_width[0], (h.t_radius[t] + Hero.RADIUS) * 2.0, 0.001, "as wide as what it hits")
	var start := h.pos[i]
	_run_until(world, func() -> bool: return h.state[i] != 1)
	world._process(DT)
	assert_true(h.is_charging(i), "charging")
	assert_near(h.contact_damage_at(h.pos[i], Hero.RADIUS), h.t_damage[t] * HordeSim.CHARGE_HIT_MULT, 0.01,
		"a charge hits harder than a touch")
	while h.state[i] == 2:
		world._process(DT)
	assert_eq(h.state[i], 3, "then it stops")
	var travelled := start.x - h.pos[i].x
	var reach := h.t_charge_speed[t] * h.t_charge_time[t]
	assert_true(travelled > reach * 0.8, "straight past the hero (%.0f px)" % travelled)
	assert_near(h.action[i], HordeSim.CHARGE_RECOVER, 0.05, "catching its breath in the open")
	_teardown(world)


func test_a_charge_into_a_wall_dazes_it() -> void:
	var world := _make_world()
	var h := world.horde
	var hero := world.heroes[0]
	hero.god_mode = true
	hero.position = LevelGrid.cell_center(Vector2i(3, 4))
	var t := h.type_index(&"frost_boar")
	var i := h.spawn(t, LevelGrid.cell_center(Vector2i(11, 4)))
	h.action[i] = 0.0
	world._process(DT)
	_run_until(world, func() -> bool: return h.state[i] == 3)
	assert_true(h.action[i] > HordeSim.CHARGE_RECOVER, "dazed by the wall (%.2f s)" % h.action[i])
	assert_true(h.pos[i].x < 2 * T, "right up against it")
	_teardown(world)


# --- salamanders -----------------------------------------------------------------------------

func test_salamanders_lob_slag_where_the_hero_stood() -> void:
	var world := _make_world()
	var h := world.horde
	var hero := world.heroes[0]
	hero.position = LevelGrid.cell_center(Vector2i(10, 4))
	var t := h.type_index(&"salamander")
	var i := h.spawn(t, LevelGrid.cell_center(Vector2i(18, 4)))
	h.action[i] = 0.0
	var spot := hero.position
	world._process(DT)
	assert_eq(h.state[i], 1, "winding up")
	_run_until(world, func() -> bool: return not world._lobs.is_empty())
	assert_eq(world._lobs.size(), 1, "a glob in the air")
	assert_vec_near(world._lobs[0][0], spot, 0.5, "coming down on the hero's feet")
	assert_true(world.warn_fx._kind.has(FxLayer.Kind.TELEGRAPH), "where it lands is shown")
	assert_true(world.fx._kind.has(FxLayer.Kind.LOB), "and the glob flies")
	hero.invulnerable_time = 0.0
	var hp := hero.hp
	_run(world, float(world._lobs[0][1]) - 3.0 * DT)
	assert_near(hero.hp, hp, 0.001, "nothing until it lands")
	_run(world, 6.0 * DT)
	assert_true(hero.hp < hp, "then it bursts")
	assert_eq(world._hazards.size(), 1, "leaving burning slag")
	_teardown(world)


# --- imps ------------------------------------------------------------------------------------

func test_imps_blink_to_a_far_hero_through_a_portal() -> void:
	var world := _make_world()
	var h := world.horde
	var hero := world.heroes[0]
	hero.god_mode = true
	hero.position = LevelGrid.cell_center(Vector2i(4, 4))
	var t := h.type_index(&"imp")
	var i := h.spawn(t, LevelGrid.cell_center(Vector2i(16, 4)))
	h.action[i] = 0.0
	world._process(DT)
	assert_eq(h.state[i], 1, "sinking into its portal")
	assert_true(world.warn_fx._kind.has(FxLayer.Kind.PORTAL), "a portal shows where it will come out")
	var spot := h.aim[i]
	assert_true(spot.distance_to(hero.position) <= HordeSim.BLINK_NEAR * 1.3, "next to the hero")
	assert_false(world.grid.is_solid_at(spot), "on open floor")
	_run_until(world, func() -> bool: return h.state[i] == 0)
	assert_eq(h.state[i], 0)
	assert_true(h.pos[i].distance_to(hero.position) < 50.0, "and out it comes")
	h.action[i] = 0.0
	world._process(DT)
	assert_eq(h.state[i], 0, "close by, it just flies at the hero")
	_teardown(world)
