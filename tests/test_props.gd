extends "res://tests/test_case.gd"
## Breakable objects and nests placed by the layout: explosive barrels
## (chain, never hurt heroes), urns (loot), and nests (sleep until heroes
## come near or their arena starts; destroying them clears a nest arena).

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0

const BARREL_ROOM := """
####################
#P......b.b........#
#..................#
#.......u..........#
####################
"""
const NEST_ARENA := """
##################################
#P...........D2222222222222222222#
#............#2N22222222222222222#
#............#2222222222222222222#
#............#22222222222222N2222#
#............D2222222222222222222#
##################################
"""


func _data(layout: String, quotas: Array[int] = [0, 0, 0]) -> LevelData:
	var d := LevelData.new()
	d.display_name = "Props test"
	d.layout = layout
	d.corridor_spawn_rate = 0.0
	d.arena_spawn_rate = 30.0
	d.arena_quotas = PackedInt32Array(quotas)
	return d


## Enemy spawning stays on (nests need it); the test layouts have no
## corridor spawns (corridor_spawn_rate 0), so only nests and arenas spawn.
func _make_world(data: LevelData, run_mode: bool = false) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = &"knight"
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.run_mode = run_mode
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


func _step(world: World, frames: int) -> void:
	for f in frames:
		world._process(DT)


func _all_of(world: World, id: StringName) -> Array[int]:
	var out: Array[int] = []
	var t := world.horde.type_index(id)
	for i in world.horde.count:
		if world.horde.type[i] == t and world.horde.hp[i] > 0.0:
			out.append(i)
	return out


func test_props_come_from_the_layout_and_block_their_tile() -> void:
	var world := _make_world(_data(BARREL_ROOM))
	assert_eq(_all_of(world, &"barrel").size(), 2)
	assert_eq(_all_of(world, &"urn").size(), 1)
	assert_true(world.grid.is_solid(8, 1) and world.grid.is_solid(10, 1), "barrels block walking")
	assert_false(world.grid.is_shot_solid(8, 1), "but not shots")
	assert_eq(world.horde.enemy_count(), 0, "objects aren't enemies")
	assert_eq(world.horde.nearest(LevelGrid.cell_center(Vector2i(8, 2)), 40.0, false), -1,
		"bots and minions don't target them")
	_teardown(world)


func test_barrels_explode_chain_and_spare_heroes() -> void:
	var world := _make_world(_data(BARREL_ROOM))
	var horde := world.horde
	var hero := world.heroes[0]
	hero.position = LevelGrid.cell_center(Vector2i(9, 2))  # right next to both barrels
	hero.invulnerable_time = 0.0
	var victim := horde.spawn(horde.type_index(&"swarmer"), LevelGrid.cell_center(Vector2i(12, 1)))
	horde.apply_stun(victim, 60.0)
	var hp0 := hero.hp
	var first := _all_of(world, &"barrel")[0]
	world.hit_enemy(first, 5.0, Vector2.ZERO, 0)
	_step(world, 30)
	assert_eq(_all_of(world, &"barrel").size(), 0, "the second barrel went off too")
	assert_eq(_all_of(world, &"swarmer").size(), 0, "the blast killed the enemy by the far barrel")
	assert_eq(world.kills, 1, "barrels don't count as kills")
	assert_near(hero.hp, hp0, 0.001, "heroes are never hurt by barrels")
	assert_false(world.grid.is_solid(8, 1) or world.grid.is_solid(10, 1), "tiles are free again")
	_teardown(world)


func test_urns_drop_loot() -> void:
	var world := _make_world(_data(BARREL_ROOM))
	var urn := _all_of(world, &"urn")[0]
	var urn_data := world.horde.types[world.horde.type[urn]]
	world.hit_enemy(urn, 5.0, Vector2.ZERO, 0)
	_step(world, 1)
	var xp := 0
	for k in world.pickups.count:
		if world.pickups.kind[k] == PickupSim.Kind.XP:
			xp += world.pickups.value[k]
	assert_eq(xp, (urn_data.loot_xp / World.URN_GEMS) * World.URN_GEMS, "gems worth its loot")
	assert_false(world.grid.is_solid(8, 3), "tile freed")
	assert_eq(world.kills, 0)
	_teardown(world)


func test_nests_wake_up_when_heroes_come_near() -> void:
	var world := _make_world(_data("""
############################################
#P.........................................#
#.......................................N..#
#..........................................#
############################################
"""))
	_step(world, 300)
	assert_eq(world.horde.enemy_count(), 0, "asleep while nobody is near")
	world.heroes[0].position = LevelGrid.cell_center(Vector2i(30, 2))
	_step(world, 240)
	assert_true(world.horde.enemy_count() >= LevelDirector.NEST_BATCH, "spawning once a hero is near")
	_teardown(world)


func test_destroying_the_nests_clears_their_arena() -> void:
	var world := _make_world(_data(NEST_ARENA, [0, 0, 0]), true)
	var director := world.director
	var hero := world.heroes[0]
	hero.god_mode = true
	assert_eq(director.nests.size(), 2)
	# Right outside the arena wall, close to a nest: still asleep.
	hero.position = LevelGrid.cell_center(Vector2i(11, 2))
	_step(world, 240)
	assert_eq(world.horde.enemy_count(), 0, "arena nests sleep until the fight starts")
	var room: LevelDirector.Room = director.rooms[0]
	hero.position = world.grid.nearest_open(room.center)
	_step(world, 2)
	assert_eq(director.active_room, room)
	assert_eq(director.objective, "Destroy the nests!  2 left")
	_step(world, 200)
	assert_true(world.horde.enemy_count() > 0, "nests spawn during the fight")
	for i in _all_of(world, &"nest"):
		world.hit_enemy(i, 1e6, Vector2.ZERO, 0)
	for second in 20:
		for i in world.horde.count:
			if world.horde.is_mobile(i):
				world.horde.damage(i, 1e6, Vector2.ZERO, 0)
		_step(world, 30)
		if room.state == LevelDirector.RoomState.CLEARED:
			break
	assert_eq(room.state, LevelDirector.RoomState.CLEARED, "cleared once nests and spawns are dead")
	assert_eq(director.nests.size(), 0)
	_teardown(world)


# --- chests and shrines ------------------------------------------------------------------

const SHRINE_ROOM := """
####################
#P.......C.........#
#..................#
#.......A..........#
#..................#
####################
"""


func _touch(world: World, it: Interactable) -> void:
	# Walk into it from below: stops against the blocked tile, close enough to use.
	var hero := world.heroes[0]
	hero.position = it.position + Vector2(0, 16)
	for f in 20:
		hero.input.move = Vector2.UP
		world._process(DT)
	hero.input.move = Vector2.ZERO


func _find(world: World, kind: Interactable.Kind) -> Interactable:
	for it in world.interactables:
		if it.kind == kind:
			return it
	return null


func test_chest_gives_everyone_a_treasure_pick() -> void:
	var world := _make_world(_data(SHRINE_ROOM))
	world.level_ups_enabled = true
	var chest := _find(world, Interactable.Kind.CHEST)
	assert_true(world.grid.is_solid(chest.cell.x, chest.cell.y), "chests block their tile")
	_touch(world, chest)
	assert_true(chest.used, "walked up and opened it")
	assert_true(world.level_up.is_open(), "pick screen opened")
	assert_eq(world.level_up._title.text, "TREASURE!  PICK AN UPGRADE")
	assert_eq(GameState.pending_treasures, 1)
	world.get_tree().paused = false
	world.level_up.close()
	GameState.pending_level_ups = 0
	_touch(world, chest)
	assert_eq(GameState.pending_level_ups, 0, "a chest opens only once")
	_teardown(world)


func test_shrine_blessings() -> void:
	var world := _make_world(_data(SHRINE_ROOM))
	var shrine := _find(world, Interactable.Kind.SHRINE)
	var hero := world.heroes[0]
	shrine.blessing = Interactable.Blessing.FURY
	_touch(world, shrine)
	assert_true(shrine.used)
	assert_near(hero.buff_product(&"damage_factor"), 1.5, 0.001, "Fury: +50% damage")
	assert_eq(world.blessing_name, "FURY")
	for f in int(World.BLESSING_TIME / DT) + 5:
		hero.tick(DT)
	assert_near(hero.buff_product(&"damage_factor"), 1.0, 0.001, "wears off")
	_touch(world, shrine)
	assert_near(hero.buff_product(&"damage_factor"), 1.0, 0.001, "a shrine blesses only once")
	# Life: heals and revives.
	hero.hp = 1.0
	var life := Interactable.new()
	life.setup(Interactable.Kind.SHRINE, Vector2i(3, 2), Interactable.Blessing.LIFE)
	world._use_interactable(life, hero)
	assert_near(hero.hp, hero.max_hp, 0.001, "Life: full heal")
	life.free()
	# Wrath: everything on screen takes a beating.
	var horde := world.horde
	var near := horde.spawn(horde.type_index(&"brute"), hero.position + Vector2(60, 0))
	var wrath := Interactable.new()
	wrath.setup(Interactable.Kind.SHRINE, Vector2i(3, 2), Interactable.Blessing.WRATH)
	var hp0 := horde.hp[near]
	world._use_interactable(wrath, hero)
	assert_true(horde.hp[near] < hp0, "Wrath: on-screen enemies are struck")
	wrath.free()
	_teardown(world)
