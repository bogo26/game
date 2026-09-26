extends "res://tests/test_case.gd"
## Bosses: the Bone Colossus (the mini boss) hits exactly where it warned -
## the sweep's wedge, spikes under heroes, the leap's landing - can't hurt
## anyone by touch while airborne, and enrages at half HP; and every boss
## puts its own name on the HUD.

const WORLD_SCENE := "res://src/world/world.tscn"
const COLOSSUS_SCENE := "res://src/enemies/boss/bone_colossus.tscn"
const DEMON_SCENE := "res://src/enemies/boss/boss_demon.tscn"
const DT := 1.0 / 60.0

## A big open hall.
const HALL := """
##################################
#P...............................#
#................................#
#................................#
#................................#
#................................#
#................................#
#................................#
#................................#
#................................#
#................................#
#................................#
#................................#
#................................#
#................................#
#................................#
#................................#
#................................#
##################################
"""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _make_world(hero_count: int) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in hero_count:
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = &"knight"
	var data := LevelData.new()
	data.display_name = "Boss test"
	data.layout = HALL
	data.corridor_spawn_rate = 0.0
	data.arena_quotas = PackedInt32Array([0])
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.spawn_enemies = false
	world.level_ups_enabled = false
	_tree().root.add_child(world)
	world.bots = null
	for hero in world.heroes:
		hero.invulnerable_time = 0.0  # past the spawn protection
	return world


func _spawn(world: World, scene: String, at: Vector2) -> Boss:
	var boss: Boss = (load(scene) as PackedScene).instantiate()
	boss.setup(world, at, 1.0, 1.0)
	world.entities.add_child(boss)
	world.boss = boss
	return boss


## Ticks the boss alone (no horde, no contact damage) for `seconds`.
func _run(boss: Boss, seconds: float) -> void:
	for f in int(seconds / DT) + 1:
		boss.tick(DT)


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	_tree().paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


func _cell(x: int, y: int) -> Vector2:
	return LevelGrid.cell_center(Vector2i(x, y))


func test_the_sweep_hits_in_front_not_behind() -> void:
	var world := _make_world(2)
	var at := _cell(18, 9)
	var boss := _spawn(world, COLOSSUS_SCENE, at) as BoneColossus
	var front := world.heroes[0]
	var behind := world.heroes[1]
	front.position = at + Vector2(40, 0)
	behind.position = at + Vector2(-40, 0)
	boss.wind_up(BoneColossus.Attack.SWEEP, at, front.position)
	assert_true(boss.in_sweep(at, front.position) and not boss.in_sweep(at, behind.position), "the wedge faces the target")
	_run(boss, BoneColossus.SWEEP_WINDUP + 0.05)
	assert_true(front.hp < front.max_hp, "the hero in front is hit")
	assert_eq(behind.hp, behind.max_hp, "the one behind it isn't")
	_teardown(world)


func test_grave_spikes_burst_where_the_heroes_stood() -> void:
	var world := _make_world(2)
	var at := _cell(10, 9)
	var boss := _spawn(world, COLOSSUS_SCENE, at) as BoneColossus
	var stays := world.heroes[0]
	var steps_away := world.heroes[1]
	stays.position = _cell(22, 5)
	steps_away.position = _cell(22, 13)
	boss.wind_up(BoneColossus.Attack.SPIKES, at, stays.position)
	steps_away.position += Vector2(64, 0)  # out of its circle before they burst
	_run(boss, BoneColossus.SPIKE_WINDUP + 0.05)
	assert_true(stays.hp < stays.max_hp, "spikes burst under the hero who stayed put")
	assert_eq(steps_away.hp, steps_away.max_hp, "the one who moved is safe")
	_teardown(world)


func test_the_leap_lands_on_the_hero_furthest_away() -> void:
	var world := _make_world(2)
	var at := _cell(8, 9)
	var boss := _spawn(world, COLOSSUS_SCENE, at) as BoneColossus
	var near := world.heroes[0]
	var far := world.heroes[1]
	near.position = at + Vector2(48, 0)
	far.position = _cell(28, 12)
	boss.wind_up(BoneColossus.Attack.LEAP, at, near.position)
	_run(boss, BoneColossus.LEAP_WINDUP + 0.05)
	assert_true(boss.is_airborne(), "it jumps once the wind-up ends")
	var horde := world.horde
	var i := horde.index_of_uid(boss.uid)
	horde.hash.rebuild(horde.pos, horde.count)
	assert_eq(horde.contact_damage_at(horde.pos[i], Hero.RADIUS), 0.0, "no contact damage in the air")
	var shots := world.projectiles.count
	_run(boss, BoneColossus.LEAP_TIME + 0.05)
	assert_false(boss.is_airborne(), "then it lands")
	assert_true(boss.position.distance_to(far.position) < 16.0, "on the hero furthest away")
	assert_true(far.hp < far.max_hp, "who takes the blow")
	assert_eq(near.hp, near.max_hp, "while the near one is out of reach")
	assert_true(world.projectiles.count >= shots + BoneColossus.SHARD_COUNT, "bone shards burst from the landing")
	i = horde.index_of_uid(boss.uid)
	horde.hash.rebuild(horde.pos, horde.count)
	assert_true(horde.contact_damage_at(horde.pos[i], Hero.RADIUS) > 0.0, "and its touch hurts again")
	_teardown(world)


func test_the_colossus_enrages_at_half_health() -> void:
	var world := _make_world(1)
	world.heroes[0].position = _cell(28, 3)
	var boss := _spawn(world, COLOSSUS_SCENE, _cell(10, 9)) as BoneColossus
	boss.tick(DT)
	assert_eq(boss.phase, BoneColossus.Phase.ONE)
	var i := world.horde.index_of_uid(boss.uid)
	world.horde.hp[i] = boss.max_hp * (BoneColossus.ENRAGE_AT - 0.05)
	var pending := world.spawner.pending_count()
	boss.tick(DT)
	assert_eq(boss.phase, BoneColossus.Phase.TWO, "enraged below half HP")
	assert_true(world.spawner.pending_count() > pending, "and the dead rise around it")
	_teardown(world)


func test_every_boss_names_itself_on_the_hud() -> void:
	for pair: Array in [[DEMON_SCENE, "DEMON LORD"], [COLOSSUS_SCENE, "BONE COLOSSUS"]]:
		var world := _make_world(1)
		_spawn(world, pair[0], _cell(18, 9))
		world.hud._process(DT)
		assert_eq(world.hud._boss_label.text, pair[1])
		_teardown(world)
