extends "res://tests/test_case.gd"
## Critical hits: rolled per hit with the attacker's crit chance, multiplied
## exactly once, carried through to the hit log, and always shown on screen.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0


func _make_world(heroes: Array[StringName]) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in heroes.size():
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = heroes[i]
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.allow_drop_in = false
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


## A sturdy enemy next to hero 0, with the hash rebuilt and the hit log empty.
func _enemy(world: World, offset: Vector2 = Vector2(20, 0)) -> int:
	var j := world.horde.spawn(0, world.heroes[0].position + offset, 100.0)
	world.horde.update(0.0, world.target_positions)
	world.horde.clear_hit_log()
	return world.horde.index_of_uid(world.horde.uid[j])


func test_crit_chance_zero_and_one() -> void:
	var world := _make_world([&"knight"])
	var hero := world.heroes[0]
	hero.crit_chance = 0.0
	var any := false
	for i in 100:
		any = any or hero.roll_crit()
	assert_false(any, "0% never crits")
	hero.crit_chance = 1.0
	var all := true
	for i in 100:
		all = all and hero.roll_crit()
	assert_true(all, "100% always crits")
	_teardown(world)


func test_hit_enemy_applies_and_logs_crits() -> void:
	var world := _make_world([&"knight"])
	var hero := world.heroes[0]
	hero.crit_mult = 2.0
	var j := _enemy(world)
	var hp0 := world.horde.hp[j]
	hero.crit_chance = 1.0
	world.hit_enemy(j, 10.0, Vector2.ZERO, hero.slot)
	assert_near(hp0 - world.horde.hp[j], 20.0, 0.001, "crit doubles the hit")
	assert_eq(world.horde.hit_crit[0], 1, "logged as a crit")
	hero.crit_chance = 0.0
	var hp1 := world.horde.hp[j]
	world.hit_enemy(j, 10.0, Vector2.ZERO, hero.slot)
	assert_near(hp1 - world.horde.hp[j], 10.0, 0.001, "normal hit")
	assert_eq(world.horde.hit_crit[1], 0, "logged as normal")
	_teardown(world)


func test_marked_enemies_always_crit_but_only_once() -> void:
	var world := _make_world([&"rogue"])
	var hero := world.heroes[0]
	hero.crit_mult = 2.0
	var j := _enemy(world)
	world.horde.apply_mark(j, 5.0)
	hero.crit_chance = 0.0
	var hp0 := world.horde.hp[j]
	world.hit_enemy(j, 10.0, Vector2.ZERO, hero.slot)
	assert_near(hp0 - world.horde.hp[j], 20.0, 0.001, "mark forces a crit")
	assert_eq(world.horde.hit_crit[0], 1)
	hero.crit_chance = 1.0
	var hp1 := world.horde.hp[j]
	world.hit_enemy(j, 10.0, Vector2.ZERO, hero.slot)
	assert_near(hp1 - world.horde.hp[j], 20.0, 0.001, "crit + mark is not x4")
	# Hits that bypass hit_enemy (projectiles) get the mark bonus exactly once too.
	var hp2 := world.horde.hp[j]
	world.horde.damage(j, 10.0, Vector2.ZERO, hero.slot, false)
	assert_near(hp2 - world.horde.hp[j], 10.0 * HordeSim.MARK_DAMAGE_MULT, 0.001)
	var hp3 := world.horde.hp[j]
	world.horde.damage(j, 20.0, Vector2.ZERO, hero.slot, true)
	assert_near(hp3 - world.horde.hp[j], 20.0, 0.001, "crit projectile on a mark isn't multiplied again")
	_teardown(world)


func test_zones_roll_crits_per_tick() -> void:
	var world := _make_world([&"ranger"])
	var hero := world.heroes[0]
	hero.crit_mult = 2.0
	# Casting doesn't bake a crit into the zone...
	hero.crit_chance = 1.0
	var rain := hero.ultimate()
	rain.try_activate(Vector2.RIGHT)
	var zone: EffectZone = world.zones[world.zones.size() - 1]
	assert_near(zone.damage, rain.scaled_damage(7.0), 0.001, "zone damage has no crit baked in")
	world.zones.clear()
	# ...each tick rolls its own.
	var j := _enemy(world)
	zone = EffectZone.new()
	zone.position = world.horde.pos[j]
	zone.radius = 16.0
	zone.duration = 5.0
	zone.interval = 0.25
	zone.damage = 10.0
	zone.owner_slot = hero.slot
	world.add_zone(zone)
	var hp0 := world.horde.hp[j]
	world._update_zones(0.01)
	assert_near(hp0 - world.horde.hp[j], 20.0, 0.001, "tick crits with 100% chance")
	hero.crit_chance = 0.0
	var hp1 := world.horde.hp[j]
	world._update_zones(0.3)
	assert_near(hp1 - world.horde.hp[j], 10.0, 0.001, "next tick rolls again (0% -> normal)")
	_teardown(world)


func test_crit_projectiles_carry_the_flag() -> void:
	var world := _make_world([&"ranger"])
	var hero := world.heroes[0]
	hero.crit_chance = 1.0
	hero.crit_mult = 2.0
	var j := _enemy(world, Vector2(40, -6))
	hero.attack().try_activate(Vector2.RIGHT)
	var shot := world.projectiles.count - 1
	assert_eq(world.projectiles.crit[shot], 1, "arrow rolled a crit at spawn")
	assert_near(world.projectiles.damage[shot], hero.attack().scaled_damage(9.0) * 2.0, 0.001)
	for frame in 30:
		world.projectiles.update(DT, world.horde, world.grid, world.hero_positions,
			PackedByteArray([0]), Hero.RADIUS)
		if world.horde.hit_pos.size() > 0:
			break
	assert_true(world.horde.hit_pos.size() > 0, "arrow hit the enemy")
	assert_eq(world.horde.hit_crit[0], 1, "hit logged as a crit")
	_teardown(world)


func test_summons_can_crit() -> void:
	var world := _make_world([&"necromancer"])
	var hero := world.heroes[0]
	hero.crit_chance = 1.0
	var j := _enemy(world, Vector2(30, 0))
	var skeleton := Minion.create(Minion.Kind.SKELETON, hero, world.horde.pos[j] + Vector2(-8, 0))
	skeleton.damage = 8.0
	world.add_minion(skeleton)
	for frame in 60:
		skeleton.tick(DT)
		if world.horde.hit_pos.size() > 0:
			break
	assert_true(world.horde.hit_pos.size() > 0, "skeleton attacked")
	assert_eq(world.horde.hit_crit[0], 1, "skeleton hit used the owner's crit chance")
	_teardown(world)


func test_crits_always_get_a_number() -> void:
	var world := _make_world([&"rogue"])
	var hero := world.heroes[0]
	var j := _enemy(world)
	hero.crit_chance = 1.0
	world.hit_enemy(j, 2.0, Vector2.ZERO, hero.slot)  # tiny crit, below the number threshold
	hero.crit_chance = 0.0
	world.hit_enemy(j, 2.0, Vector2.ZERO, hero.slot)  # tiny normal hit
	world._emit_hit_effects()
	assert_eq(world.numbers.crit_count(), 1, "the crit shows a number")
	assert_eq(world.numbers.count(), 1, "the tiny normal hit doesn't")
	# A full screen of ordinary numbers never pushes crits out.
	for i in DamageNumbers.MAX_NUMBERS * 2:
		world.numbers.add(Vector2.ZERO, 50.0, Color.WHITE)
	assert_eq(world.numbers.crit_count(), 1, "crit kept")
	_teardown(world)
