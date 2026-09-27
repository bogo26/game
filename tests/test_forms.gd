extends "res://tests/test_case.gd"
## What each legendary form does, one test each (the round that offers them,
## and the rules they share: tests/test_legendaries.gd). Crits are turned off
## so damage is exact; brutes stand in for the horde.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0
const HP := 1000.0
const ROOM := """
########################################
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#...........P..........................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
#......................................#
########################################
"""
## The room's inside ends here on the right (the wall's first pixel).
const RIGHT_WALL := 39.0 * 16.0


func _make_world(hero_id: StringName, others: Array[StringName] = []) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	var team: Array[StringName] = [hero_id]
	team.append_array(others)
	for i in team.size():
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = team[i]
	var data := LevelData.new()
	data.display_name = "Forms test"
	data.layout = ROOM
	data.corridor_spawn_rate = 0.0
	data.arena_quotas = PackedInt32Array([0, 0, 0])
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.spawn_enemies = false
	world.level_ups_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.bots = null
	for hero in world.heroes:
		hero.god_mode = true
		hero.input.uses_mouse = false
		hero.input.aim = Vector2.RIGHT
		hero.crit_chance = 0.0
	return world


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	(Engine.get_main_loop() as SceneTree).paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


## Hero 0 takes a legendary (crits stay off).
func _learn(world: World, id: StringName) -> Hero:
	var hero := world.heroes[0]
	hero.apply_upgrade(UpgradePool.shared_library().find(id))
	hero.crit_chance = 0.0
	return hero


## A brute with `hp` at `p` (feet); returns its uid.
func _enemy(world: World, p: Vector2, hp: float = HP) -> int:
	var horde := world.horde
	var i := horde.spawn(horde.type_index(&"brute"), p)
	horde.hp[i] = hp
	horde.update(0.0, PackedVector2Array())  # hash, so queries find it at once
	return horde.uid[i]


func _at(world: World, uid: int) -> int:
	return world.horde.index_of_uid(uid)


## HP left (0 once it's dead and gone).
func _hp(world: World, uid: int) -> float:
	var i := _at(world, uid)
	return world.horde.hp[i] if i != -1 else 0.0


func _pos(world: World, uid: int) -> Vector2:
	return world.horde.pos[_at(world, uid)]


## World frames with every enemy held in place (only hits and the forms'
## pulls and pushes move them).
func _hold(world: World, seconds: float) -> void:
	for f in maxi(1, roundi(seconds / DT)):
		for i in world.horde.count:
			world.horde.stun[i] = maxf(world.horde.stun[i], 1.0)
		world._process(DT)


func _frames(world: World, seconds: float) -> void:
	for f in maxi(1, roundi(seconds / DT)):
		world._process(DT)


func _shots(world: World, look: ProjectileSim.Look) -> int:
	var n := 0
	for i in world.projectiles.count:
		if world.projectiles.look[i] == look:
			n += 1
	return n


func _minions(world: World, kind: Minion.Kind) -> Array[Minion]:
	var out: Array[Minion] = []
	for m in world.minions:
		if m.kind == kind and not m.is_expired():
			out.append(m)
	return out


# --- knight ---------------------------------------------------------------------------------

func test_crescent_wave_flies_on_from_every_third_swing() -> void:
	var world := _make_world(&"knight")
	var hero := _learn(world, &"knight_crescent_wave")
	var far := _enemy(world, hero.position + Vector2(100, 0))
	var attack := hero.attack()
	for swing in 3:
		attack.cooldown_left = 0.0
		assert_true(attack.try_activate(Vector2.RIGHT))
		assert_eq(_shots(world, ProjectileSim.Look.CRESCENT), 1 if swing == 2 else 0, "swing %d" % (swing + 1))
	_hold(world, 0.6)
	assert_near(HP - _hp(world, far), 12.0 * 1.5, 0.01, "the crescent cut an enemy 100 px away")
	_teardown(world)


func test_challenge_yanks_enemies_in_and_hardens_the_knight() -> void:
	var world := _make_world(&"knight")
	var hero := _learn(world, &"knight_challenge")
	var near := _enemy(world, hero.position + Vector2(50, 0))
	var above := _enemy(world, hero.position + Vector2(0, -70))
	var far := _enemy(world, hero.position + Vector2(-120, 0))
	assert_true(hero.special().try_activate(Vector2.RIGHT))
	for uid in [near, above]:
		assert_true(_pos(world, uid).distance_to(hero.position) < 14.0, "yanked to the Knight's feet")
		assert_true(world.horde.stun[_at(world, uid)] > 1.0, "and stunned")
		assert_near(HP - _hp(world, uid), 10.0, 0.01)
	assert_near(_pos(world, far).distance_to(hero.position), 120.0, 0.5, "out of reach: left alone")
	assert_near(hero.buff_product(&"damage_taken_factor"), 0.92, 0.001, "4% less damage per enemy caught")
	_hold(world, 5.2)
	assert_near(hero.buff_product(&"damage_taken_factor"), 1.0, 0.001, "for a while")
	_teardown(world)


func test_juggernaut_carries_the_path_and_crashes() -> void:
	var world := _make_world(&"knight")
	var hero := _learn(world, &"knight_juggernaut")
	var start := hero.position
	var riders: Array[int] = []
	for x: float in [14.0, 26.0, 38.0]:
		riders.append(_enemy(world, start + Vector2(x, 0)))
	assert_true(hero.movement().try_activate(Vector2.RIGHT))
	_hold(world, 0.4)
	var travelled := hero.position.x - start.x
	assert_true(travelled > 60.0, "the charge went its whole way (%.0f px)" % travelled)
	for uid in riders:
		assert_true(_pos(world, uid).x > start.x + travelled - 4.0, "carried along on the shield")
		# 10 when picked up, then the crash: 14 + 3 per enemy carried.
		assert_near(HP - _hp(world, uid), 10.0 + 14.0 + 3.0 * 3.0, 0.01)
	_teardown(world)


func test_juggernaut_hits_harder_into_a_wall() -> void:
	var world := _make_world(&"knight")
	var hero := _learn(world, &"knight_juggernaut")
	hero.position = Vector2(RIGHT_WALL - 34.0, hero.position.y)
	var rider := _enemy(world, hero.position + Vector2(14, 0))
	assert_true(hero.movement().try_activate(Vector2.RIGHT))
	_hold(world, 0.4)
	assert_true(hero.position.x > RIGHT_WALL - 12.0, "stopped by the wall")
	assert_near(HP - _hp(world, rider), 10.0 + (14.0 + 3.0) * 1.5, 0.01, "crushed against it")
	_teardown(world)


# --- ranger ---------------------------------------------------------------------------------

func test_ricochet_turns_arrows_toward_the_next_enemy() -> void:
	for legendary: bool in [false, true]:
		var world := _make_world(&"ranger")
		var hero := world.heroes[0]
		if legendary:
			hero = _learn(world, &"ranger_ricochet")
		var first := _enemy(world, hero.position + Vector2(60, 0))
		var second := _enemy(world, hero.position + Vector2(90, 40))
		assert_true(hero.attack().try_activate(Vector2.RIGHT))
		_hold(world, 0.8)
		assert_true(_hp(world, first) < HP, "the arrow hit the first enemy")
		if legendary:
			assert_true(_hp(world, second) < HP, "then glanced off toward the second")
		else:
			assert_near(_hp(world, second), HP, 0.001, "a plain arrow flies straight on")
		_teardown(world)


func test_cluster_arrow_bursts_into_a_ring() -> void:
	var world := _make_world(&"ranger")
	var hero := _learn(world, &"ranger_cluster_arrow")
	var target := _enemy(world, hero.position + Vector2(80, 0))
	var special := hero.special()
	assert_true(special.try_activate(Vector2.RIGHT))
	var frames := 0
	while special.is_active() and frames < 60:
		_hold(world, DT)
		frames += 1
	assert_false(special.is_active(), "the heavy arrow landed")
	assert_true(HP - _hp(world, target) >= 20.0, "on its target")
	assert_eq(_shots(world, ProjectileSim.Look.ARROW), 12, "and burst into a ring of 12 arrows")
	_teardown(world)


func test_decoy_draws_the_horde_then_bursts_into_caltrops() -> void:
	var world := _make_world(&"ranger")
	var hero := _learn(world, &"ranger_decoy")
	var spot := hero.position
	assert_true(hero.movement().try_activate(Vector2.RIGHT))  # flips away from the aim
	var decoys := _minions(world, Minion.Kind.DECOY)
	assert_eq(decoys.size(), 1, "a decoy where the Ranger stood")
	var decoy: Minion = decoys[0]
	assert_true(decoy.lure and decoy.position.distance_to(spot) < 2.0)
	var walker := _enemy(world, spot + Vector2(40, 0))
	world.horde.pace[_at(world, walker)] = 1.0
	world.horde.bend[_at(world, walker)] = 0.0
	world._process(DT)
	assert_true(world.target_positions.has(decoy.position), "the horde goes after it like a hero")
	var before := _pos(world, walker).distance_to(decoy.position)
	_frames(world, 1.0)  # a brute takes a moment to get going
	assert_true(_pos(world, walker).distance_to(decoy.position) < before - 8.0, "an enemy walked up to it")
	var at := decoy.position
	_frames(world, 2.5)
	assert_false(decoy in world.minions, "it's gone")
	var caltrops := world.zones.filter(func(z: EffectZone) -> bool: return z.slow_time > 0.0)
	assert_eq(caltrops.size(), 1, "it burst into caltrops")
	if caltrops.size() == 1:
		assert_near(caltrops[0].radius, 34.0, 0.01)
		assert_true(caltrops[0].position.distance_to(at) < 1.0)
	_teardown(world)


# --- mage -----------------------------------------------------------------------------------

func test_frozen_orb_sprays_shards_then_bursts_into_a_nova() -> void:
	var world := _make_world(&"mage")
	var hero := _learn(world, &"mage_frozen_orb")
	var end := _enemy(world, hero.position + Vector2(130, 0))
	var special := hero.special()
	assert_true(special.try_activate(Vector2.RIGHT))
	_hold(world, 0.5)
	assert_true(_shots(world, ProjectileSim.Look.ICE_SHARD) >= 4, "shards spray from the orb")
	assert_true(special.is_active(), "while it drifts")
	_hold(world, 1.1)
	assert_false(special.is_active(), "then it bursts")
	assert_true(world.horde.slow[_at(world, end)] > 2.0, "into a Frost Nova where it stopped")
	assert_true(_hp(world, end) < HP)
	_teardown(world)


func test_chronoshift_snaps_back_and_undoes_half_the_damage() -> void:
	var world := _make_world(&"mage")
	var hero := _learn(world, &"mage_chronoshift")
	hero.god_mode = false
	var start := hero.position
	var before := hero.hp
	assert_true(hero.movement().try_activate(Vector2.RIGHT))
	assert_true(hero.position.x > start.x + 60.0, "blinked away")
	hero.invulnerable_time = 0.0
	assert_true(hero.take_hit(20.0))
	_frames(world, 2.6)
	assert_true(hero.position.distance_to(start) < 1.0, "snapped back to the echo")
	assert_near(hero.hp, before - 10.0, 0.01, "half the damage undone")
	_teardown(world)


func test_singularity_drags_enemies_in_then_collapses() -> void:
	var world := _make_world(&"mage")
	var hero := _learn(world, &"mage_singularity")
	var center := hero.position + Vector2(100, 0)
	var caught: Array[int] = [_enemy(world, center + Vector2(60, 0)), _enemy(world, center + Vector2(0, -50))]
	var ult := hero.ultimate()
	assert_true(ult.try_activate(Vector2.RIGHT))
	_hold(world, 1.5)
	for uid in caught:
		assert_true(_pos(world, uid).distance_to(center) < 20.0,
			"dragged into the core (%.0f px out)" % _pos(world, uid).distance_to(center))
	_hold(world, 1.7)
	assert_false(ult.is_active(), "then it collapsed")
	for uid in caught:
		assert_true(HP - _hp(world, uid) >= 120.0, "ground down and blasted (%.0f)" % (HP - _hp(world, uid)))
	_teardown(world)


# --- cleric ---------------------------------------------------------------------------------

func test_prism_orbs_split_at_the_wall() -> void:
	var world := _make_world(&"cleric")
	var hero := _learn(world, &"cleric_prism_orbs")
	hero.position = Vector2(RIGHT_WALL - 40.0, hero.position.y)
	assert_true(hero.attack().try_activate(Vector2.RIGHT))
	var sim := world.projectiles
	assert_eq(sim.count, 1)
	var damage := sim.damage[0]
	var frames := 0
	while sim.count == 1 and frames < 60:
		world._process(DT)
		frames += 1
	assert_eq(sim.count, 3, "the orb split in three at the wall")
	for k in sim.count:
		assert_eq(sim.look[k], ProjectileSim.Look.PRISM)
		assert_near(sim.damage[k], damage * ProjectileSim.SPLIT_DAMAGE, 0.01)
	_teardown(world)


func test_bastion_stops_shots_pushes_enemies_out_and_heals() -> void:
	var world := _make_world(&"cleric")
	var hero := _learn(world, &"cleric_bastion")
	hero.god_mode = false
	hero.hp = 50.0
	var inside := _enemy(world, hero.position + Vector2(20, 0))
	assert_true(hero.special().try_activate(Vector2.RIGHT))
	var sim := world.projectiles
	sim.spawn(hero.position + Vector2(-30, -6), Vector2(40, 0), 5.0, 3.0, 3.0, ProjectileSim.Team.ENEMY, -1,
		ProjectileSim.Look.SPIT)
	sim.spawn(hero.position + Vector2(-120, -6), Vector2(-40, 0), 5.0, 3.0, 3.0, ProjectileSim.Team.ENEMY, -1,
		ProjectileSim.Look.SPIT)
	_hold(world, 1.0)
	assert_eq(sim.count, 1, "the shot inside fizzled, the one outside flies on")
	assert_true(_pos(world, inside).distance_to(hero.position) >= 44.0, "the enemy was pushed out to its edge")
	assert_true(hero.hp >= 58.0, "the Cleric healed inside (%.0f)" % hero.hp)
	_teardown(world)


func test_judgement_revives_then_strikes_the_toughest_first() -> void:
	var world := _make_world(&"cleric", [&"knight"])
	var cleric := _learn(world, &"cleric_judgement")
	var knight := world.heroes[1]
	knight.god_mode = false
	knight.invulnerable_time = 0.0
	knight.take_hit(10000.0)
	assert_true(knight.is_downed())
	var tough := _enemy(world, cleric.position + Vector2(80, 0), 500.0)
	var middling := _enemy(world, cleric.position + Vector2(-80, 0), 300.0)
	var weak := _enemy(world, cleric.position + Vector2(0, -70), 100.0)
	_hold(world, DT)  # (the camera finds the team)
	var ult := cleric.ultimate()
	assert_true(ult.try_activate(Vector2.RIGHT))
	assert_false(knight.is_downed(), "it still revives everyone")
	_hold(world, DT)
	assert_near(_hp(world, tough), 410.0, 0.01, "the first pillar strikes the toughest")
	assert_near(_hp(world, middling), 300.0, 0.001)
	_hold(world, 0.12)
	assert_near(_hp(world, middling), 210.0, 0.01, "then the next toughest")
	assert_near(_hp(world, weak), 100.0, 0.001)
	_hold(world, 1.6)
	assert_false(ult.is_active(), "12 pillars, then it's over")
	assert_true(_hp(world, tough) <= 0.0 and _hp(world, middling) <= 0.0 and _hp(world, weak) <= 0.0,
		"1080 damage between them")
	_teardown(world)


# --- berserker ------------------------------------------------------------------------------

func test_throwing_axe_goes_out_and_comes_back() -> void:
	var world := _make_world(&"berserker")
	var hero := _learn(world, &"berserker_throwing_axe")
	var target := _enemy(world, hero.position + Vector2(70, 0))
	var attack := hero.attack()
	for swing in 3:
		attack.cooldown_left = 0.0
		assert_true(attack.try_activate(Vector2.RIGHT))
	assert_true(attack.is_active(), "the third swing hurled the axe")
	_hold(world, 1.5)
	assert_false(attack.is_active(), "and it came back to hand")
	assert_near(HP - _hp(world, target), 13.0 * 2.2 * 2.0, 0.01, "hitting on the way out and back")
	_teardown(world)


func test_bloodbath_kills_burst_and_chain() -> void:
	var world := _make_world(&"berserker")
	var hero := _learn(world, &"berserker_bloodbath")
	var first := _enemy(world, hero.position + Vector2(40, 0), 5.0)
	var second := _enemy(world, hero.position + Vector2(62, 0), 5.0)
	var third := _enemy(world, hero.position + Vector2(84, 0))
	assert_true(hero.special().try_activate(Vector2.RIGHT))
	var hp := hero.hp
	world.hit_enemy(_at(world, first), 50.0, Vector2.ZERO, hero.slot, hero)
	_hold(world, 0.2)
	assert_eq(_at(world, second), -1, "the kill burst in blood and killed its neighbour")
	assert_near(HP - _hp(world, third), 12.0, 0.01, "whose burst hit the next one: it chains")
	assert_true(hero.hp >= hp + 4.0, "each burst healed the Berserker")
	_hold(world, 5.0)  # the frenzy is over
	var late := _enemy(world, hero.position + Vector2(-40, 0), 5.0)
	var bystander := _enemy(world, hero.position + Vector2(-60, 0))
	world.hit_enemy(_at(world, late), 50.0, Vector2.ZERO, hero.slot, hero)
	_hold(world, 0.2)
	assert_near(_hp(world, bystander), HP, 0.001, "outside the frenzy kills don't burst")
	_teardown(world)


func test_rebound_chains_slams_onto_the_next_enemy() -> void:
	var world := _make_world(&"berserker")
	var hero := _learn(world, &"berserker_rebound")
	var start := hero.position
	var first := _enemy(world, start + Vector2(80, 0))
	var second := _enemy(world, start + Vector2(150, 0))
	var third := _enemy(world, start + Vector2(150, 60))
	assert_true(hero.movement().try_activate(Vector2.RIGHT))
	_hold(world, 2.0)
	assert_near(HP - _hp(world, first), 20.0, 0.01, "the first slam")
	assert_true(_hp(world, second) < HP, "a second leap onto the next enemy")
	assert_near(HP - _hp(world, third), 20.0 * 1.25 * 1.25, 0.01, "a third, harder still")
	assert_true(hero.position.distance_to(_pos(world, third)) < 30.0, "landing on it")
	_teardown(world)


# --- rogue ----------------------------------------------------------------------------------

func test_blade_vortex_whirls_then_flies_out() -> void:
	var world := _make_world(&"rogue")
	var hero := _learn(world, &"rogue_blade_vortex")
	var close := _enemy(world, hero.position + Vector2(26, 6))  # in the knives' path around the body
	var special := hero.special()
	assert_true(special.try_activate(Vector2.RIGHT))
	_hold(world, 1.0)
	assert_true(special.is_active(), "the knives whirl for a while")
	var cut := HP - _hp(world, close)
	assert_true(cut >= 9.0 * 0.6 * 2.0 - 0.01 and cut <= 9.0 * 0.6 * 3.0 + 0.01,
		"cutting what comes close, at most every 0.4 s (%.1f)" % cut)
	_hold(world, 2.1)
	assert_false(special.is_active(), "then they flew outward")
	assert_true(_shots(world, ProjectileSim.Look.KNIFE) >= 10, "as the old Knife Ring")
	_teardown(world)


func test_shadowstrike_appears_behind_and_crits() -> void:
	var world := _make_world(&"rogue")
	var hero := _learn(world, &"rogue_shadowstrike")
	var start := hero.position
	var target := _enemy(world, start + Vector2(60, 0))
	var beside := _enemy(world, start + Vector2(60, 22))
	assert_true(hero.movement().try_activate(Vector2.RIGHT))
	var at := _pos(world, target)
	assert_true(hero.position.x > at.x and hero.position.distance_to(at) < 24.0, "the Rogue appeared behind it")
	assert_near(HP - _hp(world, target), 24.0 * hero.crit_mult, 0.01, "a guaranteed critical stab")
	assert_true(world.horde.mark[_at(world, beside)] > 0.0, "and those around it are marked")
	_teardown(world)
	world = _make_world(&"rogue")
	hero = _learn(world, &"rogue_shadowstrike")
	assert_true(hero.movement().try_activate(Vector2.RIGHT))
	assert_true(hero.is_dashing(), "with nobody in reach it's a Shadow Step")
	_teardown(world)


func test_shadow_hunt_clones_hunt_on_their_own() -> void:
	var world := _make_world(&"rogue")
	var hero := _learn(world, &"rogue_shadow_hunt")
	var prey: Array[int] = []
	for offset: Vector2 in [Vector2(70, 0), Vector2(-70, 0), Vector2(0, -60)]:
		prey.append(_enemy(world, hero.position + offset))
	assert_true(hero.ultimate().try_activate(Vector2.RIGHT))
	_hold(world, 1.5)
	for uid in prey:
		assert_true(_hp(world, uid) < HP, "the clones stabbed an enemy the Rogue never swung at")
		assert_true(world.horde.mark[_at(world, uid)] > 0.0, "and marked it")
	_teardown(world)


# --- engineer -------------------------------------------------------------------------------

func test_flamethrower_sets_what_it_reaches_ablaze() -> void:
	var world := _make_world(&"engineer")
	var hero := _learn(world, &"engineer_flamethrower")
	var near := _enemy(world, hero.position + Vector2(40, 0))
	var far := _enemy(world, hero.position + Vector2(130, 0))
	var attack := hero.attack()
	for f in 30:
		if attack.can_activate():
			attack.try_activate(Vector2.RIGHT)
		_hold(world, DT)
	assert_true(_shots(world, ProjectileSim.Look.FLAME) > 0, "a gout of fire")
	assert_true(world.horde.is_burning(_at(world, near)), "that sets what it reaches ablaze")
	assert_true(_hp(world, near) < HP)
	assert_near(_hp(world, far), HP, 0.001, "but it's short")
	_teardown(world)


func test_mortars_shell_the_biggest_pack() -> void:
	var world := _make_world(&"engineer")
	var hero := _learn(world, &"engineer_mortar")
	var pack: Array[int] = []
	for offset: Vector2 in [Vector2(150, 0), Vector2(158, 6), Vector2(150, 12), Vector2(160, -6)]:
		pack.append(_enemy(world, hero.position + offset))
	var lone := _enemy(world, hero.position + Vector2(-90, 0))
	assert_true(hero.special().try_activate(Vector2.RIGHT))
	assert_eq(_minions(world, Minion.Kind.MORTAR).size(), 1, "a mortar, not a turret")
	_hold(world, 1.2)
	for uid in pack:
		assert_true(_hp(world, uid) < HP, "the shell landed on the pack")
	assert_near(_hp(world, lone), HP, 0.001, "not on the lone enemy")
	_teardown(world)


func test_tesla_grid_links_shock_what_crosses_them() -> void:
	var world := _make_world(&"engineer")
	var hero := _learn(world, &"engineer_tesla_grid")
	assert_true(hero.ultimate().try_activate(Vector2.RIGHT))
	var towers := _minions(world, Minion.Kind.TESLA)
	assert_eq(towers.size(), 1)
	var tower := towers[0]
	assert_true(tower.grid, "the tower powers the grid instead of zapping")
	hero.position = tower.position + Vector2(-90, 0)
	var on_link := _enemy(world, tower.position + Vector2(-45, 0))
	var off_link := _enemy(world, tower.position + Vector2(-45, 40))
	_hold(world, 1.0)
	assert_true(HP - _hp(world, on_link) >= 40.0, "shocked again and again on the link")
	assert_near(_hp(world, off_link), HP, 0.001, "nothing off it")
	_teardown(world)


# --- necromancer ----------------------------------------------------------------------------

func test_haunt_raises_a_wisp_from_every_bolt_kill() -> void:
	var world := _make_world(&"necromancer")
	var hero := _learn(world, &"necro_haunt")
	var victim := _enemy(world, hero.position + Vector2(40, 0), 1.0)
	var next := _enemy(world, hero.position + Vector2(40, 60))
	assert_true(hero.attack().try_activate(Vector2.RIGHT))
	_hold(world, 1.5)
	assert_eq(_at(world, victim), -1, "the bolt killed its target")
	assert_near(HP - _hp(world, next), 9.0 * 0.7, 0.01, "whose wisp sought out the next enemy")
	_teardown(world)


func test_bone_golem_is_built_from_corpses_and_draws_the_horde() -> void:
	var world := _make_world(&"necromancer")
	var hero := _learn(world, &"necro_bone_golem")
	for k in 4:
		var uid := _enemy(world, hero.position + Vector2(30 + k * 8, 20), 1.0)
		world.horde.damage(_at(world, uid), 10.0, Vector2.ZERO, hero.slot)
	world._process(DT)  # the corpses are counted
	var special := hero.special()
	assert_true(special.try_activate(Vector2.RIGHT))
	var golems := _minions(world, Minion.Kind.GOLEM)
	assert_eq(golems.size(), 1, "one golem instead of skeletons")
	assert_eq(_minions(world, Minion.Kind.SKELETON).size(), 0)
	var golem := golems[0]
	assert_near(golem.max_hp, 80.0 + 20.0 * 4.0, 0.01, "tougher for every corpse")
	assert_near(golem.scale_factor, 1.4 + 0.1 * 4.0, 0.001, "and bigger")
	world._process(DT)
	assert_true(world.target_positions.has(golem.position), "the horde goes after it")
	var foe := _enemy(world, golem.position + Vector2(12, 0))
	_hold(world, 1.5)
	assert_true(_hp(world, foe) < HP, "it slams what comes close")
	special.cooldown_left = 0.0
	assert_true(special.try_activate(Vector2.RIGHT))
	assert_eq(_minions(world, Minion.Kind.GOLEM).size(), 1, "casting again feeds the same golem")
	_teardown(world)


func test_lich_form_floats_grows_and_fires_in_threes() -> void:
	var world := _make_world(&"necromancer")
	var hero := _learn(world, &"necro_lich_form")
	assert_true(hero.ultimate().try_activate(Vector2.RIGHT))
	_frames(world, DT)
	assert_near(hero.buff_product(&"sprite_scale"), 1.3, 0.001, "bigger")
	assert_near(hero.buff_product(&"damage_taken_factor"), 0.75, 0.001, "tougher")
	assert_true(hero.air_height > 0.0, "floating")
	var attack := hero.attack()
	attack.cooldown_left = 0.0
	assert_true(attack.try_activate(Vector2.RIGHT))
	assert_eq(_shots(world, ProjectileSim.Look.SOUL), 3, "Soul Bolts fire in threes")
	_frames(world, 10.0)
	assert_near(hero.buff_product(&"sprite_scale"), 1.0, 0.001, "until it wears off")
	assert_near(hero.air_height, 0.0, 0.001)
	attack.cooldown_left = 0.0
	assert_true(attack.try_activate(Vector2.RIGHT))
	assert_eq(_shots(world, ProjectileSim.Look.SOUL), 1)
	_teardown(world)
