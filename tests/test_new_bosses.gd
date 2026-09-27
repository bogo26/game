extends "res://tests/test_case.gd"
## The other bosses a run can meet: the Toadstool Tyrant and the Mire Serpent
## (mini bosses), the Spore Mother and the Frost Queen (final bosses) - each
## hits exactly where it warned - and their servants: sporelings, eels,
## puffballs and frost wraiths.

const WORLD_SCENE := "res://src/world/world.tscn"
const TYRANT_SCENE := "res://src/enemies/boss/toadstool_tyrant.tscn"
const SERPENT_SCENE := "res://src/enemies/boss/mire_serpent.tscn"
const MOTHER_SCENE := "res://src/enemies/boss/spore_mother.tscn"
const QUEEN_SCENE := "res://src/enemies/boss/frost_queen.tscn"
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

## A dry row (y=1) and a wet row (y=2).
const WET_ROOM := """
####################
#P.................#
#~~~~~~~~~~~~~~~~~~#
#..................#
####################
"""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _make_world(hero_count: int, layout: String = HALL) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in hero_count:
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = &"knight"
	var data := LevelData.new()
	data.display_name = "Boss test"
	data.layout = layout
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


## A boss with a fixed seed (its random choices repeat).
func _spawn(world: World, scene: String, at: Vector2) -> Boss:
	var boss: Boss = (load(scene) as PackedScene).instantiate()
	boss.setup(world, at, 1.0, 1.0)
	boss._rng.seed = 7
	world.entities.add_child(boss)
	world.boss = boss
	return boss


## Ticks the boss alone (no horde, no contact damage) for `seconds`.
func _run(boss: Boss, seconds: float) -> void:
	for f in int(seconds / DT) + 1:
		boss.tick(DT)


## Ticks the boss and the world around it (hazards, bombs, shots, the horde).
func _run_all(world: World, boss: Boss, seconds: float) -> void:
	for f in int(seconds / DT) + 1:
		boss.tick(DT)
		world._process(DT)


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	_tree().paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


func _cell(x: int, y: int) -> Vector2:
	return LevelGrid.cell_center(Vector2i(x, y))


func _body(world: World, boss: Boss) -> int:
	return world.horde.index_of_uid(boss.uid)


# --- the Toadstool Tyrant --------------------------------------------------------------------

func test_the_tyrant_bounces_onto_the_nearest_hero_hop_after_hop() -> void:
	var world := _make_world(2)
	var at := _cell(8, 9)
	var boss := _spawn(world, TYRANT_SCENE, at) as ToadstoolTyrant
	var near := world.heroes[0]
	var far := world.heroes[1]
	near.position = at + Vector2(70, 0)
	far.position = _cell(30, 3)
	boss.wind_up(ToadstoolTyrant.Attack.BOUNCE, at, near.position)
	assert_true(boss.landing().distance_to(near.position) < 2.0, "the first hop lands on the nearest hero")
	_run(boss, ToadstoolTyrant.BOUNCE_WINDUP + 0.05)
	assert_true(boss.is_airborne(), "in the air once it's done squatting")
	var horde := world.horde
	horde.hash.rebuild(horde.pos, horde.count)
	assert_eq(horde.contact_damage_at(horde.pos[_body(world, boss)], Hero.RADIUS), 0.0, "no contact damage in the air")
	_run(boss, ToadstoolTyrant.HOP_TIME)
	assert_true(boss.position.distance_to(near.position) < 4.0, "and comes down on them")
	assert_true(near.hp < near.max_hp, "who takes the blow")
	assert_eq(far.hp, far.max_hp, "the other hero is out of reach")
	# Hop after hop: it squats again for the next one, then walks once they're done.
	var hops := 1
	for k in ToadstoolTyrant.HOPS[0] - 1:
		assert_eq(boss.action, ToadstoolTyrant.Action.SQUAT, "squatting for hop %d" % (k + 2))
		_run(boss, ToadstoolTyrant.HOP_SQUAT + ToadstoolTyrant.HOP_TIME + 0.05)
		hops += 1
	assert_eq(hops, ToadstoolTyrant.HOPS[0])
	assert_eq(boss.action, ToadstoolTyrant.Action.WALK, "three hops, then it walks again")
	_teardown(world)


func test_a_hop_reaches_only_so_far() -> void:
	var world := _make_world(1)
	var at := _cell(4, 9)
	var boss := _spawn(world, TYRANT_SCENE, at) as ToadstoolTyrant
	world.heroes[0].position = _cell(30, 9)
	boss.wind_up(ToadstoolTyrant.Attack.BOUNCE, at, world.heroes[0].position)
	assert_near(boss.landing().distance_to(at), ToadstoolTyrant.HOP_REACH, 16.0, "a hop covers HOP_REACH at most")
	_teardown(world)


func test_a_spore_burst_rings_the_tyrant_with_clouds() -> void:
	var world := _make_world(2)
	var at := _cell(10, 9)
	var boss := _spawn(world, TYRANT_SCENE, at) as ToadstoolTyrant
	var close := world.heroes[0]
	var away := world.heroes[1]
	close.position = at + Vector2(ToadstoolTyrant.BURST_RING, 0)
	away.position = _cell(28, 9)
	boss.wind_up(ToadstoolTyrant.Attack.BURST, at, close.position)
	var clouds := boss._burst_spots.size()
	assert_eq(clouds, 1 + ToadstoolTyrant.BURST_CLOUDS[0], "a cloud under it and a ring around it")
	var hazards := world._hazards.size()
	_run(boss, ToadstoolTyrant.BURST_WINDUP + 0.05)
	assert_eq(world._hazards.size(), hazards + clouds, "each warned spot becomes a spore cloud")
	for f in 60:
		world._process(DT)
	assert_true(close.hp < close.max_hp, "the clouds hurt a hero standing in them")
	assert_eq(away.hp, away.max_hp, "not one standing clear")
	_teardown(world)


func test_the_tyrant_enrages_and_lobs_spore_bombs() -> void:
	var world := _make_world(2)
	var at := _cell(8, 9)
	var boss := _spawn(world, TYRANT_SCENE, at) as ToadstoolTyrant
	world.heroes[0].position = _cell(24, 5)
	world.heroes[1].position = _cell(24, 13)
	boss.tick(DT)
	world.horde.hp[_body(world, boss)] = boss.max_hp * (ToadstoolTyrant.ENRAGE_AT - 0.05)
	var pending := world.spawner.pending_count()
	boss.tick(DT)
	assert_eq(boss.phase, ToadstoolTyrant.Phase.TWO, "enraged below half HP")
	var sporeling := world.horde.type_index(&"sporeling")
	var sprouted := Array(world.spawner._pending_type).count(sporeling)
	assert_eq(sprouted, ToadstoolTyrant.ENRAGE_SPROUT, "sporelings sprout around it")
	assert_true(world.spawner.pending_count() >= pending + sprouted)
	boss.wind_up(ToadstoolTyrant.Attack.LOB, boss.position, world.heroes[0].position)
	_run(boss, ToadstoolTyrant.LOB_WINDUP + 0.05)
	assert_eq(world._lobs.size(), 2 + ToadstoolTyrant.LOB_EXTRA, "a bomb at every hero and a few more")
	for bomb in world._lobs:
		assert_eq(bomb[4], &"spores", "spore bombs")
	var hazards := world._hazards.size()
	for f in int((ToadstoolTyrant.LOB_FLIGHT + 0.2) / DT):  # (the enrage's hitstop holds the world a moment)
		world._process(DT)
	assert_true(world._hazards.size() >= hazards + 2 + ToadstoolTyrant.LOB_EXTRA, "each leaves a spore cloud")
	assert_true(world.heroes[0].hp < world.heroes[0].max_hp, "the bomb at a hero's feet hits them")
	_teardown(world)


# --- the Mire Serpent ------------------------------------------------------------------------

func test_the_serpent_dives_out_of_reach_and_bursts_up_under_its_prey() -> void:
	var world := _make_world(1)
	var at := _cell(10, 9)
	var boss := _spawn(world, SERPENT_SCENE, at) as MireSerpent
	var hero := world.heroes[0]
	hero.position = at + Vector2(100, 0)
	boss.dive()
	_run(boss, MireSerpent.DIVE_TIME + 0.05)
	assert_true(boss.is_submerged(), "under the murk")
	assert_eq(boss.status_text(), "SUBMERGED", "the HUD says so")
	var horde := world.horde
	var i := _body(world, boss)
	var hp := horde.hp[i]
	assert_false(horde.damage(i, 50.0, Vector2.ZERO, 0), "out of reach")
	assert_eq(horde.hp[i], hp, "nothing hurts it")
	horde.hash.rebuild(horde.pos, horde.count)
	assert_eq(horde.nearest(hero.position, 400.0), -1, "and nothing finds it")
	assert_eq(horde.contact_damage_at(horde.pos[i], Hero.RADIUS), 0.0, "or touches it")
	_run(boss, MireSerpent.HUNT_TIME[0] + MireSerpent.RISE_TIME)
	assert_false(boss.is_submerged(), "then it bursts up")
	assert_true(boss.position.distance_to(hero.position) < MireSerpent.RISE_RADIUS, "under the hero who stood still")
	assert_true(hero.hp < hero.max_hp, "who takes the blow")
	assert_true(horde.damage(_body(world, boss), 5.0, Vector2.ZERO, 0) or true)
	assert_true(horde.hp[_body(world, boss)] < hp, "and it can be hit again")
	_teardown(world)


func test_a_hero_who_keeps_moving_outruns_the_fin() -> void:
	var world := _make_world(1)
	var at := _cell(4, 9)
	var boss := _spawn(world, SERPENT_SCENE, at) as MireSerpent
	var hero := world.heroes[0]
	hero.position = at + Vector2(60, 0)
	boss.dive()
	_run(boss, MireSerpent.DIVE_TIME + 0.05)
	var run_speed := 88.0
	for f in int((MireSerpent.HUNT_TIME[0] + MireSerpent.RISE_TIME) / DT) + 2:
		hero.position += Vector2(run_speed * DT, 0)
		boss.tick(DT)
	assert_false(boss.is_submerged())
	assert_eq(hero.hp, hero.max_hp, "a hero on the move is never where it bursts up")
	_teardown(world)


func test_the_lunge_hits_down_its_band() -> void:
	var world := _make_world(2)
	var at := _cell(10, 9)
	var boss := _spawn(world, SERPENT_SCENE, at) as MireSerpent
	var ahead := world.heroes[0]
	var aside := world.heroes[1]
	ahead.position = at + Vector2(60, 0)
	aside.position = at + Vector2(40, 40)
	boss.wind_up(MireSerpent.Attack.LUNGE, at, ahead.position)
	assert_true(boss.lunge_end(at).distance_to(at + Vector2(MireSerpent.LUNGE_LENGTH, 0)) < 1.0, "the band it shows")
	_run(boss, MireSerpent.LUNGE_WINDUP + 0.05)
	assert_true(ahead.hp < ahead.max_hp, "the hero down the band is bitten")
	assert_eq(aside.hp, aside.max_hp, "the one beside it isn't")
	_teardown(world)


func test_the_spit_fans_at_the_nearest_hero() -> void:
	var world := _make_world(1)
	var at := _cell(10, 9)
	var boss := _spawn(world, SERPENT_SCENE, at) as MireSerpent
	world.heroes[0].position = at + Vector2(120, 0)
	var shots := world.projectiles.count
	boss.wind_up(MireSerpent.Attack.SPIT, at, world.heroes[0].position)
	_run(boss, MireSerpent.SPIT_WINDUP + 0.05)
	assert_eq(world.projectiles.count, shots + MireSerpent.FAN_SHOTS[0], "a fan of water")
	for k in range(shots, world.projectiles.count):
		assert_eq(world.projectiles.team[k], ProjectileSim.Team.ENEMY)
		assert_true(world.projectiles.vel[k].x > 0.0, "towards the hero")
	_teardown(world)


func test_the_enraged_serpent_bursts_up_twice_with_its_brood() -> void:
	var world := _make_world(1)
	var at := _cell(10, 9)
	var boss := _spawn(world, SERPENT_SCENE, at) as MireSerpent
	var hero := world.heroes[0]
	hero.god_mode = true
	hero.position = at + Vector2(80, 0)
	boss.tick(DT)
	world.horde.hp[_body(world, boss)] = boss.max_hp * (MireSerpent.ENRAGE_AT - 0.05)
	boss.tick(DT)
	assert_eq(boss.phase, MireSerpent.Phase.TWO, "enraged below half HP")
	var eel := world.horde.type_index(&"eel")
	assert_eq(Array(world.spawner._pending_type).count(eel), MireSerpent.ENRAGE_BROOD, "its brood comes up")
	boss.dive()
	_run(boss, MireSerpent.DIVE_TIME + MireSerpent.HUNT_TIME[1] + MireSerpent.RISE_TIME + 0.05)
	assert_false(boss.is_submerged(), "up once")
	assert_eq(Array(world.spawner._pending_type).count(eel), MireSerpent.ENRAGE_BROOD + MireSerpent.BROOD,
		"with eels around the burst")
	_run(boss, MireSerpent.BREATH + MireSerpent.DIVE_TIME + 0.05)
	assert_true(boss.is_submerged(), "and straight back under for a second burst")
	_teardown(world)


# --- the Spore Mother ------------------------------------------------------------------------

func test_pods_shield_the_spore_mother_until_they_burst() -> void:
	var world := _make_world(1)
	var at := _cell(17, 9)
	var boss := _spawn(world, MOTHER_SCENE, at) as SporeMother
	world.heroes[0].position = _cell(2, 2)
	boss.tick(DT)
	assert_eq(boss.pods.size(), SporeMother.PODS[0], "pods sprout as the fight starts")
	for q in boss.pod_positions():
		var d := q.distance_to(at)
		assert_true(d >= SporeMother.POD_NEAR - 16.0 and d <= SporeMother.POD_FAR + 16.0, "around her (%.0f px)" % d)
	assert_true(boss.is_shielded())
	assert_eq(boss.status_text(), "SHIELDED")
	assert_eq(boss.objective_hint(), "Burst the spore pods!  %d left" % SporeMother.PODS[0])
	var horde := world.horde
	var i := _body(world, boss)
	var hp := horde.hp[i]
	horde.damage(i, 100.0, Vector2.ZERO, 0)
	assert_near(hp - horde.hp[i], 100.0 * (1.0 - SporeMother.SHIELD), 0.01, "she shrugs off most of a hit")
	for q in boss.pod_positions():
		for j in horde.count:
			if horde.pos[j] == q:
				horde.damage(j, 1e6, Vector2.ZERO, 0)
	world._process(DT)  # the burst pods leave the horde
	boss.tick(DT)
	assert_false(boss.is_shielded(), "every pod burst: the shield is down")
	assert_eq(boss.objective_hint(), "", "back to \"Defeat the Spore Mother!\"")
	i = _body(world, boss)
	hp = horde.hp[i]
	horde.damage(i, 100.0, Vector2.ZERO, 0)
	assert_near(hp - horde.hp[i], 100.0, 0.01, "and a hit lands in full")
	_teardown(world)


func test_the_pods_grow_back_in_phase_two() -> void:
	var world := _make_world(1)
	var at := _cell(17, 9)
	var boss := _spawn(world, MOTHER_SCENE, at) as SporeMother
	world.heroes[0].position = _cell(2, 2)
	boss.tick(DT)
	var horde := world.horde
	horde.hp[_body(world, boss)] = boss.max_hp * (SporeMother.PHASE_TWO_AT - 0.05)
	boss.tick(DT)
	assert_eq(boss.phase, SporeMother.Phase.TWO)
	assert_eq(boss.pods.size(), SporeMother.PODS[0] + SporeMother.PODS[1], "more pods: shielded again")
	var puffball := horde.type_index(&"puffball")
	assert_true(Array(world.spawner._pending_type).count(puffball) > 0, "and puffballs come")
	_teardown(world)


func test_roots_burst_along_the_bands_toward_every_hero() -> void:
	var world := _make_world(2)
	var at := _cell(17, 9)
	var boss := _spawn(world, MOTHER_SCENE, at) as SporeMother
	var stays := world.heroes[0]
	var steps := world.heroes[1]
	stays.position = at + Vector2(120, 0)
	steps.position = at + Vector2(-120, 0)
	boss.wind_up(SporeMother.Attack.ROOTS, at)
	assert_eq(boss._bands.size(), 2, "a band toward each hero")
	steps.position += Vector2(0, 30)  # out of its band
	_run(boss, SporeMother.ROOTS_WINDUP + 0.05)
	assert_true(stays.hp < stays.max_hp, "roots burst under the hero who stayed")
	assert_eq(steps.hp, steps.max_hp, "the one who stepped aside is safe")
	_teardown(world)


func test_fairy_rings_erupt_then_the_rings_between() -> void:
	var world := _make_world(2)
	var at := _cell(17, 9)
	var boss := _spawn(world, MOTHER_SCENE, at) as SporeMother
	var odd := world.heroes[0]
	var even := world.heroes[1]
	odd.position = at + Vector2(SporeMother.RING_INNER + 1.5 * SporeMother.RING_WIDTH, 0)
	even.position = at + Vector2(-(SporeMother.RING_INNER + 2.5 * SporeMother.RING_WIDTH), 0)
	assert_eq(SporeMother.ring_of(odd.position.distance_to(at)), 1)
	assert_eq(SporeMother.ring_of(even.position.distance_to(at)), 2)
	assert_eq(SporeMother.ring_of(1000.0), -1, "beyond the last ring is safe")
	boss.wind_up(SporeMother.Attack.RINGS, at)
	_run(boss, SporeMother.RINGS_WINDUP + 0.05)
	assert_true(even.hp < even.max_hp, "the first rings erupt")
	assert_eq(odd.hp, odd.max_hp, "the rings between them wait")
	odd.invulnerable_time = 0.0
	_run(boss, SporeMother.RINGS_SECOND + 0.05)
	assert_true(odd.hp < odd.max_hp, "then they erupt too")
	assert_eq(boss.action, SporeMother.Action.IDLE)
	_teardown(world)


func test_spore_spirals_wheel_out_of_her() -> void:
	var world := _make_world(1)
	var at := _cell(17, 9)
	var boss := _spawn(world, MOTHER_SCENE, at) as SporeMother
	world.heroes[0].position = _cell(2, 2)
	var shots := world.projectiles.count
	boss.wind_up(SporeMother.Attack.SPIRAL, at)
	_run(boss, SporeMother.SPIRAL_WINDUP + 0.5)
	var arms := SporeMother.SPIRAL_ARMS[0]
	assert_true(world.projectiles.count >= shots + arms * 4, "arms of spores (%d shots)" % (world.projectiles.count - shots))
	_run(boss, SporeMother.SPIRAL_TIME)
	assert_eq(boss.action, SporeMother.Action.IDLE, "until the spiral is done")
	_teardown(world)


func test_her_pods_wither_when_she_dies() -> void:
	var world := _make_world(1)
	var boss := _spawn(world, MOTHER_SCENE, _cell(17, 9)) as SporeMother
	world.heroes[0].position = _cell(2, 2)
	boss.tick(DT)
	var pods := boss.pod_positions().size()
	assert_true(pods > 0)
	var i := _body(world, boss)
	world.horde.guard[i] = 0.0
	world.horde.damage(i, 1e9, Vector2.ZERO, 0)
	boss.tick(DT)
	var pod := world.horde.type_index(&"spore_pod")
	var alive := 0
	for j in world.horde.count:
		if world.horde.type[j] == pod and world.horde.hp[j] > 0.0:
			alive += 1
	assert_eq(alive, 0, "no pod outlives her")
	_teardown(world)


# --- the Frost Queen -------------------------------------------------------------------------

func test_the_frost_nova_rolls_out_and_a_dash_gets_through() -> void:
	var world := _make_world(3)
	var at := _cell(17, 9)
	var boss := _spawn(world, QUEEN_SCENE, at) as FrostQueen
	var caught := world.heroes[0]
	var dashing := world.heroes[1]
	var clear := world.heroes[2]
	caught.position = at + Vector2(100, 0)
	dashing.position = at + Vector2(-100, 0)
	clear.position = at + Vector2(0, FrostQueen.NOVA_RADIUS + 30.0)
	clear.position.x = at.x
	boss.wind_up(FrostQueen.Attack.NOVA, at, caught.position)
	_run(boss, FrostQueen.NOVA_WINDUP + 0.02)
	# The ring passes 100 px out at 100 / NOVA_SPEED s: dash through it then.
	dashing.invulnerable_time = 100.0 / FrostQueen.NOVA_SPEED + 0.15
	_run(boss, FrostQueen.NOVA_RADIUS / FrostQueen.NOVA_SPEED + 0.2)
	assert_true(caught.hp < caught.max_hp, "the ring hits a hero it rolls over")
	assert_true(caught.chill_time > 0.0, "and chills them")
	assert_true(caught._speed_factor() < 1.0, "they walk slower")
	assert_eq(dashing.hp, dashing.max_hp, "a dash gets through it")
	assert_eq(clear.hp, clear.max_hp, "and nothing reaches past its circle")
	assert_true(boss._novas.is_empty(), "then it's gone")
	_teardown(world)


func test_the_glacial_beam_sweeps_the_wedge_it_shows() -> void:
	var world := _make_world(2)
	var at := _cell(17, 9)
	var boss := _spawn(world, QUEEN_SCENE, at) as FrostQueen
	var inside := world.heroes[0]
	var behind := world.heroes[1]
	inside.position = at + Vector2(90, 0)
	behind.position = at + Vector2(-90, 0)
	boss.wind_up(FrostQueen.Attack.BEAM, at, inside.position)
	assert_near(absf(angle_difference(boss.beam_angle(0.0), 0.0)), FrostQueen.BEAM_SWEEP * 0.5, 0.001,
		"it starts at one edge of the wedge")
	assert_near(absf(angle_difference(boss.beam_angle(FrostQueen.BEAM_TIME * 0.5), 0.0)), 0.0, 0.001,
		"crosses the hero it aimed at halfway")
	_run(boss, FrostQueen.BEAM_WINDUP + FrostQueen.BEAM_TIME + 0.05)
	assert_true(inside.hp < inside.max_hp, "the hero in the wedge is swept")
	assert_true(inside.chill_time > 0.0, "and chilled")
	assert_eq(behind.hp, behind.max_hp, "the one behind her isn't")
	assert_eq(boss.action, FrostQueen.Action.GLIDE)
	_teardown(world)


func test_icicles_fall_where_their_circles_show() -> void:
	var world := _make_world(1)
	var at := _cell(4, 9)
	var boss := _spawn(world, QUEEN_SCENE, at) as FrostQueen
	var hero := world.heroes[0]
	hero.position = _cell(20, 9)
	boss.wind_up(FrostQueen.Attack.HAIL, at, hero.position)
	_run(boss, FrostQueen.HAIL_WINDUP + 0.05)
	var seen: Array = []
	for f in int(FrostQueen.HAIL_TIME / DT):
		boss.tick(DT)
		for icicle in boss._icicles:
			if not seen.any(func(other: Array) -> bool: return is_same(other, icicle)):
				seen.append(icicle)
	assert_true(seen.size() >= int(FrostQueen.HAIL_TIME / FrostQueen.HAIL_EVERY) - 2, "a hail of icicles (%d)" % seen.size())
	for icicle: Array in seen:
		assert_true(icicle[0].distance_to(hero.position) <= FrostQueen.ICICLE_SCATTER + 1.0, "all around the hero")
	_run(boss, FrostQueen.ICICLE_FALL + 0.05)
	assert_true(hero.hp < hero.max_hp, "a hero who stands still gets hit")
	assert_true(boss._icicles.is_empty(), "every icicle landed")
	_teardown(world)


func test_ice_lances_fly_down_their_aim_lines() -> void:
	var world := _make_world(2)
	var at := _cell(17, 9)
	var boss := _spawn(world, QUEEN_SCENE, at) as FrostQueen
	world.heroes[0].position = at + Vector2(120, 30)
	world.heroes[1].position = at + Vector2(-120, 30)
	var shots := world.projectiles.count
	boss.wind_up(FrostQueen.Attack.LANCES, at, world.heroes[0].position)
	var dirs := boss._lance_dirs.duplicate()
	assert_eq(dirs.size(), 2, "a lance for every hero")
	_run(boss, FrostQueen.LANCE_WINDUP + 0.02)
	assert_eq(world.projectiles.count, shots + 2)
	for k in 2:
		var v := world.projectiles.vel[shots + k].normalized()
		assert_true(v.dot(dirs[k]) > 0.999, "along the line it showed")
	_teardown(world)


func test_the_blizzard_pushes_everyone_downwind() -> void:
	var world := _make_world(1)
	var at := _cell(4, 3)
	var boss := _spawn(world, QUEEN_SCENE, at) as FrostQueen
	var hero := world.heroes[0]
	hero.position = _cell(12, 12)
	world._process(DT)  # the camera finds the hero
	boss._start_blizzard(at)
	boss._wind = Vector2.RIGHT
	assert_eq(boss.status_text(), "BLIZZARD")
	var start := hero.position
	var shots := world.projectiles.count
	for f in 60:
		boss._update_blizzard(DT)
	assert_near(hero.position.x - start.x, FrostQueen.WIND_PUSH, 2.0, "blown along with the wind")
	assert_true(world.projectiles.count >= shots + 5, "ice shards ride it (%d)" % (world.projectiles.count - shots))
	for k in range(shots, world.projectiles.count):
		assert_true(world.projectiles.vel[k].x > 0.0, "downwind")
		assert_false(world.grid.is_solid_at(world.projectiles.pos[k]), "from inside the room")
	_teardown(world)


func test_the_queen_keeps_her_distance() -> void:
	var world := _make_world(1)
	var at := _cell(17, 9)
	var boss := _spawn(world, QUEEN_SCENE, at) as FrostQueen
	var hero := world.heroes[0]
	hero.position = at + Vector2(40, 0)
	boss._attack_timer = 99.0
	_run(boss, 1.0)
	assert_true(boss.position.x < at.x - 10.0, "she glides away from a hero who comes close")
	hero.position = boss.position + Vector2(260, 0)
	var before := boss.position
	_run(boss, 1.0)
	assert_true(boss.position.x > before.x + 10.0, "and after one who strays far")
	_teardown(world)


func test_cornered_she_steps_through_the_ice() -> void:
	var world := _make_world(1)
	var at := _cell(17, 1)  # against the top wall
	var boss := _spawn(world, QUEEN_SCENE, at) as FrostQueen
	var hero := world.heroes[0]
	hero.position = at + Vector2(0, 40)
	boss._attack_timer = 99.0
	_run(boss, FrostQueen.STUCK_TIME + 0.1)
	assert_true(boss.is_stepping(), "backed into the wall, she steps away")
	var to := boss._step_to
	assert_true(to.distance_to(hero.position) > FrostQueen.STEP_REACH - 24.0, "to a spot well away from the hero")
	for f in int(FrostQueen.STEP_TIME / DT) + 1:
		if not boss.is_stepping():
			break
		boss.tick(DT)
	assert_false(boss.is_stepping())
	assert_true(boss.position.distance_to(to) < 1.0, "and appears there")
	_teardown(world)


# --- all of them -----------------------------------------------------------------------------

func test_the_other_bosses_name_themselves_on_the_hud() -> void:
	var names := {TYRANT_SCENE: "TOADSTOOL TYRANT", SERPENT_SCENE: "MIRE SERPENT", MOTHER_SCENE: "SPORE MOTHER",
		QUEEN_SCENE: "FROST QUEEN"}
	for scene: String in names:
		var world := _make_world(1)
		world.heroes[0].position = _cell(2, 2)
		var boss := _spawn(world, scene, _cell(17, 9))
		world.hud._process(DT)
		assert_eq(world.hud._boss_label.text, names[scene])
		if boss is SporeMother:
			boss.tick(DT)  # her pods sprout
			world.hud._process(DT)
			assert_eq(world.hud._boss_label.text, "SPORE MOTHER  -  SHIELDED", "and says when she's shielded")
		_teardown(world)


func test_the_spore_mothers_objective_points_at_her_pods() -> void:
	var run := RunConfig.load_default()
	var data: LevelData
	for level in run.boss_pool:
		if level.boss_scene == MOTHER_SCENE:
			data = level
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = &"knight"
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.run_mode = true
	world.level_ups_enabled = false
	_tree().root.add_child(world)
	world.bots = null
	var hero := world.heroes[0]
	hero.god_mode = true
	var director := world.director
	assert_eq(director.objective, "Enter the deep")
	hero.position = world.grid.nearest_open(director.rooms[0].center + Vector2(0, 150))
	for f in 3:
		InputRouter._process(DT)
		world._process(DT)
	var boss := world.boss as SporeMother
	assert_true(boss != null, "the Spore Mother awakes as the hero walks in")
	assert_eq(director.objective, "Burst the spore pods!  %d left" % SporeMother.PODS[0])
	assert_true(director.objective_target in boss.pod_positions(), "the arrow points at a pod")
	for id in boss.pods:
		world.horde.damage(world.horde.index_of_uid(id), 1e6, Vector2.ZERO, 0)
	for f in 3:
		InputRouter._process(DT)
		world._process(DT)
	assert_eq(director.objective, "Defeat the Spore Mother!", "then at her")
	assert_true(director.objective_target.distance_to(boss.position) < 1.0)
	_teardown(world)


# --- their servants --------------------------------------------------------------------------

## A bare horde (no World) of the shipped enemy kinds `ids` on `layout`.
func _horde(layout: String, ids: Array[StringName]) -> HordeSim:
	var data := LevelData.new()
	data.layout = layout
	var level := Level.new()
	level.build(data)
	var types: Array[EnemyData] = []
	for id in ids:
		types.append(load("res://src/enemies/data/%s.tres" % id) as EnemyData)
	var flow := FlowField.new()
	flow.setup(level.grid)
	var h := HordeSim.new()
	h.setup(level.grid, flow, types)
	level.free()
	return h


func test_sporelings_get_about_in_hops() -> void:
	var h := _horde(HALL, [&"sporeling"])
	var t := 0
	assert_true(h.t_hop[t] > 0.0, "a hopper")
	var i := h.spawn(t, _cell(4, 9))
	h.anim[i] = 0.0
	h.update(0.0, PackedVector2Array())
	var targets := PackedVector2Array([_cell(30, 9)])
	var still := 0
	var fast := 0
	var last := h.pos[i]
	for f in 60:
		h.update(DT, targets)
		var step := h.pos[i].distance_to(last) / DT
		last = h.pos[i]
		if step < 1.0:
			still += 1
		elif step > h.t_speed[t] * 1.3:
			fast += 1
	assert_true(still > 10, "it sits between hops (%d frames)" % still)
	assert_true(fast > 10, "and leaps quicker than it would walk (%d frames)" % fast)
	assert_eq(HordeSim.hop_frame(0.3), 3, "drawn up high mid-hop")
	assert_eq(HordeSim.hop_frame(0.9), 0, "and sitting after it")


func test_eels_slither_fast_through_water() -> void:
	var h := _horde(WET_ROOM, [&"eel"])
	var t := 0
	var dry := h.spawn(t, _cell(2, 1))
	var wet := h.spawn(t, _cell(2, 2))
	for i: int in [dry, wet]:
		h.anim[i] = 0.0
		h.pace[i] = 1.0
		h.bend[i] = 0.0
	h.update(0.0, PackedVector2Array())
	var dry_start := h.pos[dry].x
	var wet_start := h.pos[wet].x
	var targets := PackedVector2Array([Vector2(1000, 1.5 * LevelGrid.TILE), Vector2(1000, 2.5 * LevelGrid.TILE)])
	for frame in 30:
		h.update(DT, targets)
	var ratio := (h.pos[wet].x - wet_start) / (h.pos[dry].x - dry_start)
	assert_true(ratio > 1.6, "much faster in the water (%.2fx)" % ratio)


func test_puffballs_burst_into_spore_clouds() -> void:
	var world := _make_world(1)
	var h := world.horde
	var hero := world.heroes[0]
	hero.position = _cell(10, 9)
	var t := h.type_index(&"puffball")
	h.spawn(t, hero.position + Vector2(12, 0))
	var hazards := world._hazards.size()
	for f in int((h.types[t].fuse_time + 0.3) / DT):
		world._process(DT)
	assert_true(hero.hp < hero.max_hp, "its burst hurts")
	assert_eq(world._hazards.size(), hazards + 1, "and it leaves a spore cloud")
	_teardown(world)


func test_frost_wraiths_fly_and_shoot() -> void:
	var world := _make_world(1)
	var h := world.horde
	var t := h.type_index(&"frost_wraith")
	assert_eq(h.t_flying[t], 1, "a flyer")
	assert_eq(h.t_behavior[t], EnemyData.Behavior.RANGED, "that shoots")
	var hero := world.heroes[0]
	hero.god_mode = true
	hero.position = _cell(20, 9)
	var i := h.spawn(t, _cell(12, 9))
	h.action[i] = 0.0
	var shots := world.projectiles.count
	for f in 90:
		world._process(DT)
	assert_true(world.projectiles.count > shots, "a shard of ice at the hero")
	_teardown(world)
