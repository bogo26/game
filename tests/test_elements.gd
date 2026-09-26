extends "res://tests/test_case.gd"
## Elemental attack upgrades: tiers unlock in order, and fire / ice / poison /
## lightning do what their cards say, including each chain's last tier.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0
const HIT := 10.0
const ROOM := """
##############################
#P...........................#
#............................#
#............................#
#............................#
#............................#
#............................#
#............................#
##############################
"""


func _data() -> LevelData:
	var d := LevelData.new()
	d.display_name = "Elements test"
	d.layout = ROOM
	d.corridor_spawn_rate = 0.0
	return d


func _make_world(hero_id: StringName = &"knight") -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = hero_id
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = _data()
	world.spawn_enemies = false
	world.level_ups_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.bots = null
	world.heroes[0].god_mode = true
	return world


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	(Engine.get_main_loop() as SceneTree).paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


## Gives hero 0 an element up to `tier` by taking its upgrade chain.
func _learn(world: World, element: String, tier: int) -> Hero:
	var hero := world.heroes[0]
	var library := UpgradePool.shared_library()
	for t in range(1, tier + 1):
		hero.apply_upgrade(library.find(StringName("%s_%d" % [element, t])))
	return hero


## A sturdy brute that stands still (no walking into the hero).
func _enemy(world: World, p: Vector2, hp: float = 200.0) -> int:
	var horde := world.horde
	var i := horde.spawn(horde.type_index(&"brute"), p)
	horde.hp[i] = hp
	horde.update(0.0, PackedVector2Array())  # hash, so zaps and spreading find it
	return horde.index_of_uid(horde.uid[i])


func _frames(world: World, n: int) -> void:
	for f in n:
		world._process(DT)


## Frames without enemies walking: statuses tick, the rest of the world runs.
func _still(world: World, seconds: float) -> void:
	for f in int(seconds / DT):
		for i in world.horde.count:
			world.horde.stun[i] = maxf(world.horde.stun[i], 1.0)
		world._process(DT)


func _at(world: World, uid: int) -> int:
	return world.horde.index_of_uid(uid)


# --- the upgrade chains -------------------------------------------------------------------

func test_element_tiers_unlock_in_order() -> void:
	var pool := UpgradePool.new(null, 7)
	var seen := {}
	for roll in 300:
		for u in pool.roll_offers(&"knight", {}):
			seen[u.id] = true
	assert_true(seen.has(&"fire_1") and seen.has(&"ice_1") and seen.has(&"poison_1") and seen.has(&"lightning_1"),
		"first tiers show up")
	for id in [&"fire_2", &"fire_3", &"ice_2", &"ice_3", &"poison_2", &"poison_3", &"lightning_2", &"lightning_3"]:
		assert_false(seen.has(id), "%s needs the tier before it" % id)
	seen.clear()
	for roll in 300:
		for u in pool.roll_offers(&"knight", {&"fire_1": 1}):
			seen[u.id] = true
	assert_true(seen.has(&"fire_2"), "tier II after tier I")
	assert_false(seen.has(&"fire_3"))
	assert_false(seen.has(&"fire_1"), "each tier is taken once")
	seen.clear()
	for roll in 300:
		for u in pool.roll_offers(&"knight", {&"fire_1": 1, &"fire_2": 1}):
			seen[u.id] = true
	assert_true(seen.has(&"fire_3"), "the last tier after tier II")


func test_upgrades_set_the_attack_element_tiers() -> void:
	var world := _make_world()
	var hero := world.heroes[0]
	assert_false(hero.has_elements())
	_learn(world, "fire", 2)
	_learn(world, "lightning", 1)
	assert_eq(hero.elements, PackedInt32Array([2, 0, 0, 1]))
	assert_true(hero.has_elements())
	_teardown(world)


# --- fire -------------------------------------------------------------------------------------

func test_fire_burns_and_wildfire_spreads() -> void:
	var world := _make_world()
	var hero := _learn(world, "fire", 2)
	var a := world.horde.uid[_enemy(world, Vector2(200, 60))]
	var b := world.horde.uid[_enemy(world, Vector2(214, 60))]  # touching a
	var far := world.horde.uid[_enemy(world, Vector2(360, 100))]
	world.elements.on_attack_hit(hero, _at(world, a), HIT)
	assert_true(world.horde.is_burning(_at(world, a)))
	var hp0 := world.horde.hp[_at(world, a)]
	_still(world, 1.0)
	var burned := hp0 - world.horde.hp[_at(world, a)]
	var expected := HIT * Elements.BURN_SHARE[2]
	assert_near(burned, expected, expected * 0.1, "burns for %.1f per second" % expected)
	assert_true(world.horde.is_burning(_at(world, b)), "fire spread to the enemy touching it")
	assert_false(world.horde.is_burning(_at(world, far)), "but not across the room")
	_teardown(world)


func test_inferno_explodes_and_ignites_neighbours() -> void:
	var world := _make_world()
	var hero := _learn(world, "fire", 3)
	var a := _enemy(world, Vector2(200, 60), 50.0)
	var near := world.horde.uid[_enemy(world, Vector2(230, 70))]
	world.elements.on_attack_hit(hero, a, HIT)
	var hp0 := world.horde.hp[_at(world, near)]
	world.horde.damage(a, 1000.0, Vector2.ZERO, hero.slot)  # dies burning
	_frames(world, 2)
	var j := _at(world, near)
	assert_true(world.horde.hp[j] <= hp0 - HIT * Elements.BURN_SHARE[3] * Elements.INFERNO_DAMAGE + 0.01,
		"caught in the explosion")
	assert_true(world.horde.is_burning(j), "and set on fire")
	_teardown(world)


# --- ice ----------------------------------------------------------------------------------------

func test_frostbite_slows() -> void:
	var world := _make_world()
	var hero := _learn(world, "ice", 1)
	var horde := world.horde
	var cold := horde.uid[_enemy(world, Vector2(100, 40))]
	var warm := horde.uid[_enemy(world, Vector2(100, 100))]
	world.elements.on_attack_hit(hero, _at(world, cold), HIT)
	var targets := PackedVector2Array([Vector2(440, 40), Vector2(440, 100)])
	for f in 30:
		horde.update(DT, targets)
	var ratio := horde.pos[_at(world, cold)].distance_to(Vector2(100, 40)) \
		/ horde.pos[_at(world, warm)].distance_to(Vector2(100, 100))
	assert_near(ratio, HordeSim.CHILL_SPEED, 0.08, "chilled enemies walk at %.0f%%" % (ratio * 100.0))
	_teardown(world)


func test_permafrost_freezes_every_third_hit() -> void:
	var world := _make_world()
	var hero := _learn(world, "ice", 2)
	var j := _enemy(world, Vector2(200, 60))
	world.elements.on_attack_hit(hero, j, HIT)
	world.elements.on_attack_hit(hero, j, HIT)
	assert_false(world.horde.is_frozen(j), "two hits: just chilled")
	world.elements.on_attack_hit(hero, j, HIT)
	assert_true(world.horde.is_frozen(j), "third hit: frozen solid")
	assert_true(world.horde.stun[j] >= Elements.FREEZE_TIME - 0.01, "can't move")
	_teardown(world)


func test_shatter_double_damage_and_nova() -> void:
	var world := _make_world()
	var hero := _learn(world, "ice", 3)
	hero.crit_chance = 0.0
	var horde := world.horde
	var a := horde.uid[_enemy(world, Vector2(200, 60), 500.0)]
	var b := horde.uid[_enemy(world, Vector2(225, 60))]
	world.elements.on_attack_hit(hero, _at(world, b), HIT)  # b: one frost already
	for k in Elements.FREEZE_HITS:
		world.elements.on_attack_hit(hero, _at(world, a), HIT)
	assert_true(horde.is_frozen(_at(world, a)))
	var hp0 := horde.hp[_at(world, a)]
	world.elements.on_attack_hit(hero, _at(world, a), HIT)
	assert_near(hp0 - horde.hp[_at(world, a)], HIT * Elements.SHATTER_BONUS, 0.01, "frozen: the hit lands twice")
	horde.damage(_at(world, a), 1e6, Vector2.ZERO, hero.slot)  # dies frozen
	_frames(world, 2)
	assert_true(horde.is_frozen(_at(world, b)), "the shatter froze its neighbour")
	_teardown(world)


# --- poison -------------------------------------------------------------------------------------

func test_poison_stacks_hurt_and_slow() -> void:
	var world := _make_world()
	var hero := _learn(world, "poison", 1)
	var j := world.horde.uid[_enemy(world, Vector2(200, 60), 500.0)]
	for k in 6:
		world.elements.on_attack_hit(hero, _at(world, j), HIT)
	assert_near(world.horde.poison_stacks[_at(world, j)], 4.0, 0.001, "Venom stacks 4 times")
	var hp0 := world.horde.hp[_at(world, j)]
	_still(world, 1.0)
	var expected := HIT * Elements.POISON_SHARE * 4.0
	assert_near(hp0 - world.horde.hp[_at(world, j)], expected, expected * 0.1, "each stack hurts")
	hero.apply_upgrade(UpgradePool.shared_library().find(&"poison_2"))
	for k in 6:
		world.elements.on_attack_hit(hero, _at(world, j), HIT)
	assert_near(world.horde.poison_stacks[_at(world, j)], 8.0, 0.001, "Virulence stacks 8 times")
	_teardown(world)


func test_plague_clouds_spread_the_poison() -> void:
	var world := _make_world()
	var hero := _learn(world, "poison", 3)
	var horde := world.horde
	var a := _enemy(world, Vector2(200, 60), 50.0)
	var near := horde.uid[_enemy(world, Vector2(215, 70))]
	world.elements.on_attack_hit(hero, a, HIT)
	horde.damage(a, 1e6, Vector2.ZERO, hero.slot)  # dies poisoned
	_still(world, 0.6)
	var clouds := 0
	for zone in world.zones:
		if zone.poison_dps > 0.0:
			clouds += 1
	assert_eq(clouds, 1, "left a toxic cloud")
	assert_true(horde.poison_stacks[_at(world, near)] >= 1.0, "which poisoned its neighbour")
	_teardown(world)


# --- lightning ------------------------------------------------------------------------------------

func test_static_charge_zaps_the_nearest_enemy() -> void:
	var world := _make_world()
	var hero := _learn(world, "lightning", 1)
	hero.crit_chance = 0.0
	var horde := world.horde
	var a := horde.uid[_enemy(world, Vector2(200, 60))]
	var near := horde.uid[_enemy(world, Vector2(230, 60))]
	var far := horde.uid[_enemy(world, Vector2(330, 60))]
	world.elements.on_attack_hit(hero, _at(world, a), HIT)
	assert_near(200.0 - horde.hp[_at(world, near)], HIT * Elements.ZAP_SHARE[1], 0.01, "zapped for half")
	assert_near(horde.hp[_at(world, far)], 200.0, 0.001, "out of reach")
	assert_true(horde.stun[_at(world, near)] > 0.0 and horde.stun[_at(world, a)] > 0.0, "both staggered")
	assert_true(horde.vel[_at(world, near)].x > 0.0, "and shoved away")
	_teardown(world)


func test_arc_lightning_chains() -> void:
	var world := _make_world()
	var hero := _learn(world, "lightning", 2)
	var horde := world.horde
	var a := _enemy(world, Vector2(100, 60))
	var chain: Array[int] = []
	for k in 4:
		chain.append(horde.uid[_enemy(world, Vector2(140 + k * 40, 60))])
	world.elements.on_attack_hit(hero, _at(world, horde.uid[a]), HIT)
	var zapped := 0
	for id in chain:
		if horde.hp[_at(world, id)] < 200.0:
			zapped += 1
	assert_eq(zapped, Elements.ZAP_CHAIN[2], "jumped through 3 enemies")
	_teardown(world)


func test_thunderstrike_every_fifth_hit() -> void:
	var world := _make_world()
	var hero := _learn(world, "lightning", 3)
	hero.crit_chance = 0.0
	var horde := world.horde
	var j := horde.uid[_enemy(world, Vector2(200, 60), 1000.0)]
	for k in Elements.STRIKE_EVERY - 1:
		world.elements.on_attack_hit(hero, _at(world, j), HIT)
	var hp0 := horde.hp[_at(world, j)]
	world.elements.on_attack_hit(hero, _at(world, j), HIT)
	assert_near(hp0 - horde.hp[_at(world, j)], HIT * Elements.STRIKE_DAMAGE, 0.01, "thunderbolt")
	assert_true(horde.stun[_at(world, j)] >= Elements.STRIKE_STUN - 0.01, "stunned")
	_teardown(world)


# --- which hits carry elements ------------------------------------------------------------------

func test_projectile_attacks_carry_elements_but_specials_dont() -> void:
	var world := _make_world(&"ranger")
	var hero := _learn(world, "fire", 1)
	hero.position = Vector2(240, 70)
	var horde := world.horde
	var target := horde.uid[_enemy(world, hero.position + Vector2(50, -6))]
	hero.attack().try_activate(Vector2.RIGHT)
	for f in 20:
		world.projectiles.update(DT, horde, world.grid, PackedVector2Array(), PackedByteArray(), 5.0)
		world.elements.process_projectile_hits(world.projectiles)
	assert_true(horde.is_burning(_at(world, target)), "the arrow set it on fire")
	var other := horde.uid[_enemy(world, hero.position + Vector2(-50, -6))]
	hero.special().try_activate(Vector2.LEFT)
	for f in 20:
		world.projectiles.update(DT, horde, world.grid, PackedVector2Array(), PackedByteArray(), 5.0)
		world.elements.process_projectile_hits(world.projectiles)
	assert_true(horde.hp[_at(world, other)] < 200.0, "the volley hit")
	assert_false(horde.is_burning(_at(world, other)), "but specials don't carry the element")
	_teardown(world)


func test_melee_attacks_carry_elements() -> void:
	var world := _make_world(&"knight")
	var hero := _learn(world, "ice", 1)
	hero.position = Vector2(240, 70)
	var j := world.horde.uid[_enemy(world, hero.position + Vector2(14, 0))]
	hero.attack().try_activate(Vector2.RIGHT)
	assert_true(world.horde.chill[_at(world, j)] > 0.0, "the sword chilled it")
	_teardown(world)


func test_scenery_and_bosses_resist() -> void:
	var world := _make_world()
	var hero := _learn(world, "ice", 2)
	_learn(world, "fire", 1)
	var horde := world.horde
	var barrel := horde.spawn(horde.type_index(&"barrel"), Vector2(200, 60))
	horde.hp[barrel] = 1000.0
	var boss := horde.spawn(horde.type_index(&"boss_demon"), Vector2(300, 60))
	horde.update(0.0, PackedVector2Array())
	for k in 4:
		world.elements.on_attack_hit(hero, _at(world, horde.uid[barrel]), HIT)
		world.elements.on_attack_hit(hero, _at(world, horde.uid[boss]), HIT)
	assert_false(horde.is_burning(_at(world, horde.uid[barrel])), "barrels don't burn")
	assert_true(horde.is_burning(_at(world, horde.uid[boss])), "the boss does")
	assert_false(horde.is_frozen(_at(world, horde.uid[boss])), "but never freezes")
	_teardown(world)
