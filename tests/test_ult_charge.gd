extends "res://tests/test_case.gd"
## Ultimate charge: damage from a hero's attack, special and movement (and
## the minions and zones they make) charges the ultimate; the ultimate never
## charges itself: not with its own hits, the minions and zones it makes, the
## statuses it applies (and the burns, explosions and clouds they lead to) or
## the barrels it sets off.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0
const ROOM := """
##############################
#............................#
#............................#
#............................#
#....P.......................#
#............................#
#............................#
#............................#
##############################
"""
## Where the pack stands, from the hero: in reach of every ultimate aimed right.
const PACK: Array[Vector2] = [Vector2(26, 0), Vector2(30, -8), Vector2(30, 8), Vector2(36, 0),
	Vector2(40, -8), Vector2(40, 8)]


func _make_world(hero_id: StringName) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = hero_id
	var data := LevelData.new()
	data.display_name = "Ult charge test"
	data.layout = ROOM
	data.corridor_spawn_rate = 0.0
	data.arena_quotas = PackedInt32Array([0, 0, 0])
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.spawn_enemies = false
	world.level_ups_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.bots = null
	world.heroes[0].god_mode = true
	# Joining doesn't reset these, and other tests leave player 1 aiming
	# with the mouse or wherever their bots last looked.
	world.heroes[0].input.uses_mouse = false
	world.heroes[0].input.aim = Vector2.RIGHT
	return world


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	(Engine.get_main_loop() as SceneTree).paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


## Every playable hero, from the hero data files.
func _hero_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for file in DirAccess.get_files_at("res://src/heroes/data"):
		if file.get_extension() == "tres":
			ids.append(StringName(file.get_basename()))
	return ids


## A brute at `p` (returns its uid).
func _enemy(world: World, p: Vector2, hp: float = 1e6) -> int:
	var horde := world.horde
	var i := horde.spawn(horde.type_index(&"brute"), p)
	horde.hp[i] = hp
	horde.update(0.0, PackedVector2Array())  # hash, so the first hits find it
	return horde.uid[i]


func _pack(world: World, hp: float = 1e6) -> void:
	for offset in PACK:
		_enemy(world, world.heroes[0].position + offset, hp)


## World frames with the pack held in place (only hits move it). With
## `signal_attacks` the hero signals an attack every 0.2 s without swinging:
## Shadow Clones copy it, nothing else happens.
func _run(world: World, seconds: float, signal_attacks: bool = false) -> void:
	for f in int(seconds / DT):
		for i in world.horde.count:
			world.horde.stun[i] = maxf(world.horde.stun[i], 1.0)
		if signal_attacks and f % 12 == 0:
			world.heroes[0].attack_performed.emit(Vector2.RIGHT)
		world._process(DT)


## Presses the ultimate with a full meter (one world frame).
func _use_ultimate(world: World) -> void:
	var hero := world.heroes[0]
	hero.ult_charge = 1.0
	hero.input.set_action(PlayerInput.Action.ULTIMATE, true)
	world._process(DT)
	hero.input.set_action(PlayerInput.Action.ULTIMATE, false)
	hero.input.consume_presses()


## What the meter's passive trickle adds over `seconds`.
func _passive(hero: Hero, seconds: float) -> float:
	return Hero.ULT_PASSIVE_PER_SECOND * hero.ult_charge_mult * seconds


func test_no_ultimate_charges_itself() -> void:
	for id in _hero_ids():
		var world := _make_world(id)
		var hero := world.heroes[0]
		_pack(world)
		var t0 := world.elapsed
		_use_ultimate(world)
		assert_eq(hero.used_abilities[Ability.Slot.ULTIMATE], 1, "%s used its ultimate" % id)
		_run(world, 11.0, true)  # the longest ultimates last 10 s
		if not (hero.ultimate() is BuffAbility):  # Rampage only makes the hero's own hits stronger
			assert_true(GameState.slots[0].damage_dealt > 0.0, "%s: the ultimate hit the pack" % id)
		assert_near(hero.ult_charge, _passive(hero, world.elapsed - t0), 0.001,
			"%s: only the passive trickle charged it (dealt %.0f)" % [id, GameState.slots[0].damage_dealt])
		_teardown(world)


func test_everything_else_still_charges_it() -> void:
	# Melee, projectiles, a slam, a charge, turrets, skeletons and a burning
	# trail: damage dealt / the hero's ult cost, as before.
	for id: StringName in [&"knight", &"engineer", &"necromancer"]:
		var world := _make_world(id)
		var hero := world.heroes[0]
		_pack(world)
		hero.ult_charge = 0.0
		var t0 := world.elapsed
		for ability: Ability in [hero.attack(), hero.special(), hero.movement()]:
			assert_true(ability.try_activate(Vector2.RIGHT), "%s: %s" % [id, ability.display_name])
		_run(world, 3.0)
		var dealt := GameState.slots[0].damage_dealt
		assert_true(dealt > 0.0, "%s hit the pack" % id)
		var expected := _passive(hero, world.elapsed - t0) + dealt * hero.ult_charge_mult / hero.data.ult_cost
		assert_near(hero.ult_charge, minf(1.0, expected), 0.001, "%s: charged by what it dealt" % id)
		_teardown(world)


func test_shadow_clones_elements_dont_charge_it_either() -> void:
	# Clones copy the attack, elements included: their zaps, thunderbolts,
	# burns and poison, and the infernos, spreading fire and plague clouds
	# those lead to, are all still the ultimate.
	var world := _make_world(&"rogue")
	var hero := world.heroes[0]
	var library := UpgradePool.shared_library()
	for element: String in ["fire", "poison", "lightning"]:
		for tier in range(1, 4):
			hero.apply_upgrade(library.find(StringName("%s_%d" % [element, tier])))
	_pack(world, 60.0)
	var t0 := world.elapsed
	_use_ultimate(world)
	_run(world, 6.0, true)  # the clones swing, the dagger doesn't
	_run(world, 8.0)  # burns and poison run out, clouds fade
	assert_true(GameState.slots[0].kills > 0, "enemies died burning and poisoned")
	assert_near(hero.ult_charge, _passive(hero, world.elapsed - t0), 0.001,
		"only the passive trickle charged it (dealt %.0f)" % GameState.slots[0].damage_dealt)
	_teardown(world)


func test_a_burn_charges_it_unless_the_ultimate_lit_it() -> void:
	var world := _make_world(&"rogue")
	var hero := world.heroes[0]
	var horde := world.horde
	var j := horde.index_of_uid(_enemy(world, hero.position + Vector2(80, 0)))
	var cost := hero.data.ult_cost / hero.ult_charge_mult
	for by_ult: bool in [true, false]:  # the latest status decides
		hero.ult_charge = 0.0
		horde.ult_hits = by_ult
		horde.ignite(j, 20.0, 2.0, hero.slot)
		horde.ult_hits = false
		horde.update(0.5, PackedVector2Array())  # 10 damage of burning
		world._apply_ult_charge()
		assert_near(hero.ult_charge, 0.0 if by_ult else 10.0 / cost, 0.0001,
			"lit by the ultimate: %s" % by_ult)
	assert_near(GameState.slots[0].damage_dealt, 20.0, 0.01, "both burns count as damage dealt")
	_teardown(world)


func test_a_barrel_blows_up_for_whatever_broke_it() -> void:
	for by_ult: bool in [false, true]:
		var world := _make_world(&"mage")
		var hero := world.heroes[0]
		var horde := world.horde
		var barrel := horde.uid[horde.spawn(horde.type_index(&"barrel"), hero.position + Vector2(60, 0))]
		var brute := _enemy(world, hero.position + Vector2(84, 0))
		hero.ult_charge = 0.0
		horde.ult_hits = by_ult
		world.hit_enemy(horde.index_of_uid(barrel), 1.0, Vector2.ZERO, hero.slot)
		horde.ult_hits = false
		world._process_kills()
		world._update_barrel_blasts(1.0)
		world._apply_ult_charge()
		assert_true(horde.hp[horde.index_of_uid(brute)] < 1e6, "the blast hit the brute")
		var dealt := GameState.slots[0].damage_dealt
		var expected := 0.0 if by_ult else dealt * hero.ult_charge_mult / hero.data.ult_cost
		assert_near(hero.ult_charge, expected, 0.0001, "broken by the ultimate: %s" % by_ult)
		_teardown(world)
