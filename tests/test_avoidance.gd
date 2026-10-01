extends "res://tests/test_case.gd"
## Enemies steer clear of the heroes' AoEs. Each frame the World hands the
## horde its dangers (World._collect_dangers(): lasting zones that hurt
## enemies, blasts about to land, auras round a hero), and every enemy that
## has noticed one gets out of it, goes round it, or waits at its edge while
## its hero stands inside (HordeSim._steer_clear()).

const T := LevelGrid.TILE
const DT := 1.0 / 60.0
const WORLD_SCENE := "res://src/world/world.tscn"
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


# --- the horde --------------------------------------------------------------------------------

func _open_grid(w: int, h: int) -> LevelGrid:
	var g := LevelGrid.new(w, h)
	for x in w:
		g.set_solid(x, 0, true)
		g.set_solid(x, h - 1, true)
	for y in h:
		g.set_solid(0, y, true)
		g.set_solid(w - 1, y, true)
	return g


func _walker() -> EnemyData:
	var d := EnemyData.new()
	d.id = &"test"
	d.max_hp = 10.0
	d.speed = 40.0
	d.radius = 5.0
	d.contact_damage = 7.0
	return d


## A horde of one kind (a plain walker by default) going after `targets`.
func _horde(g: LevelGrid, targets: PackedVector2Array, kind: EnemyData = null) -> HordeSim:
	var flow := FlowField.new()
	flow.setup(g)
	flow.compute_now(targets)
	var types: Array[EnemyData] = [kind if kind else _walker()]
	var h := HordeSim.new()
	h.setup(g, flow, types)
	return h


## Spawns one that walks at exactly its kind's speed and never arcs in.
func _steady(h: HordeSim, p: Vector2) -> int:
	var i := h.spawn(0, p)
	h.pace[i] = 1.0
	h.bend[i] = 0.0
	return i


func test_enemies_go_round_an_aoe_to_reach_their_hero() -> void:
	var g := _open_grid(40, 20)
	var hero := Vector2(30.5 * T, 10 * T)
	var target := PackedVector2Array([hero])
	var h := _horde(g, target)
	var c := Vector2(18 * T, 10 * T)  # right in its way
	h.add_danger(c, 40.0, 10.0)
	var i := _steady(h, Vector2(6 * T, 10 * T))
	var r := h.t_radius[0]
	var closest := INF
	var frames := 0
	while h.pos[i].distance_to(hero) > T and frames < 1200:
		h.update(DT, target)
		closest = minf(closest, h.pos[i].distance_to(c))
		frames += 1
	assert_true(closest > 40.0 + r, "never set foot in it (%.1f px from its middle at the closest)" % closest)
	assert_true(h.pos[i].distance_to(hero) <= T, "and went round it to its hero (%.1f s)" % (frames * DT))


func test_enemies_caught_in_an_aoe_get_out_the_nearest_way() -> void:
	var g := _open_grid(40, 20)
	var hero := Vector2(36 * T, 10 * T)  # off to the right
	var target := PackedVector2Array([hero])
	var h := _horde(g, target)
	var c := Vector2(16 * T, 10 * T)
	h.add_danger(c, 48.0, 10.0)
	var i := _steady(h, c + Vector2(-30, 0))  # its hero is across the middle
	var r := h.t_radius[0]
	var frames := 0
	while h.pos[i].distance_to(c) <= 48.0 + r and frames < 180:
		h.update(DT, target)
		frames += 1
	assert_true(h.pos[i].distance_to(c) > 48.0 + r, "it got out (%.1f s)" % (frames * DT))
	assert_true(h.pos[i].x < c.x, "on its own side, not across the middle toward its hero")
	var closest := INF
	while h.pos[i].distance_to(hero) > T and frames < 1800:
		h.update(DT, target)
		closest = minf(closest, h.pos[i].distance_to(c))
		frames += 1
	assert_true(closest > 48.0 + r, "then kept out of it (%.1f px at the closest)" % closest)
	assert_true(h.pos[i].distance_to(hero) <= T, "going round it to its hero")


func test_enemies_wait_at_the_edge_of_an_aoe_their_hero_stands_in() -> void:
	var g := _open_grid(40, 30)
	var hero := Vector2(20 * T, 15 * T)
	var target := PackedVector2Array([hero])
	var h := _horde(g, target)
	h.add_danger(hero, 34.0, 10.0)  # a Whirlwind
	for k in 8:
		h.spawn(0, hero + Vector2.from_angle(TAU * k / 8.0) * 110.0)
	for f in 240:
		h.update(DT, target)
	var r := h.t_radius[0]
	for i in h.count:
		var d := h.pos[i].distance_to(hero)
		assert_true(d > 34.0 + r, "keeps out of it (%.1f px from the hero)" % d)
		assert_true(d < 34.0 + r + HordeSim.DANGER_MARGIN + HordeSim.DANGER_BAND,
			"but waits right at its edge (%.1f px)" % d)
	assert_near(h.contact_damage_at(hero, HordeSim.HERO_RADIUS), 0.0, 0.0001, "so nobody touches the hero")


func test_enemies_take_a_moment_to_notice_a_new_aoe() -> void:
	var g := _open_grid(30, 20)
	var none := PackedVector2Array()
	var h := _horde(g, none)
	var c := Vector2(15 * T, 10 * T)
	h.add_danger(c, 48.0, 0.0)  # just cast, on two enemies standing about
	var ids: Array[int] = [_steady(h, c + Vector2(-20, 0)), _steady(h, c + Vector2(20, 0))]
	var starts: Array[Vector2] = [h.pos[ids[0]], h.pos[ids[1]]]
	var reacts: Array[float] = [h.reaction_time(ids[0]), h.reaction_time(ids[1])]
	for react in reacts:
		assert_true(react >= HordeSim.REACT_MIN and react <= HordeSim.REACT_MIN + HordeSim.REACT_SPREAD,
			"a moment (%.2f s)" % react)
	assert_true(absf(reacts[0] - reacts[1]) > 0.02, "and some are quicker than others")
	var moved_at: Array[float] = [-1.0, -1.0]
	var age := 0.0
	for f in 60:
		h.danger_age[0] = age  # as the World would hand it over
		h.update(DT, none)
		for k in 2:
			if moved_at[k] < 0.0 and h.pos[ids[k]].distance_to(starts[k]) > 0.001:
				moved_at[k] = age
		age += DT
	for k in 2:
		# (Half of the horde looks again each frame, so it may take one more.)
		assert_true(moved_at[k] >= reacts[k] - 0.0001 and moved_at[k] < reacts[k] + 2.0 * DT + 0.0001,
			"it stays put until it notices, then gets going (%.3f s, reacts at %.3f s)" % [moved_at[k], reacts[k]])


func test_a_blast_on_its_way_scatters_its_rim_but_catches_its_middle() -> void:
	# A Meteor's mark: 1 s to get out of 72 px.
	var g := _open_grid(40, 24)
	var none := PackedVector2Array()
	var h := _horde(g, none)
	var c := Vector2(20 * T, 12 * T)
	var radius := 72.0
	h.add_danger(c, radius, 0.0)
	var middle := _steady(h, c + Vector2(4, 0))
	var rim := _steady(h, c + Vector2(64, 0))
	var age := 0.0
	while age < 1.0:
		h.danger_age[0] = age
		h.update(DT, none)
		age += DT
	var r := h.t_radius[0]
	assert_true(h.pos[rim].distance_to(c) > radius + r,
		"the rim got out in time (%.1f px from the middle)" % h.pos[rim].distance_to(c))
	assert_true(h.pos[rim].x > c.x + 64.0, "straight out, the nearest way")
	assert_true(h.pos[middle].distance_to(c) <= radius + r,
		"the middle couldn't (%.1f px from the middle)" % h.pos[middle].distance_to(c))


func test_enemies_busy_with_an_attack_hold_their_ground() -> void:
	# A lit fuse (like a wind-up or a charge) isn't dropped for an AoE.
	var g := _open_grid(20, 12)
	var hero := Vector2(10 * T, 6 * T)
	var target := PackedVector2Array([hero])
	var kind := _walker()
	kind.behavior = EnemyData.Behavior.EXPLODER
	kind.explosion_radius = 30.0
	kind.fuse_time = 0.6
	var h := _horde(g, target, kind)
	var i := _steady(h, hero + Vector2(12, 0))
	h.update(DT, target)
	assert_eq(h.state[i], 1, "its fuse is lit")
	var at := h.pos[i]
	h.add_danger(hero, 40.0, 10.0)
	var frames := 0
	while h.blast_pos.is_empty() and frames < 120:
		h.update(DT, target)
		frames += 1
	assert_eq(h.blast_pos.size(), 1, "it went off")
	if h.blast_pos.size() == 1:
		assert_vec_near(h.blast_pos[0], at, 0.01, "where it stood")


func test_blinkers_never_blink_into_an_aoe() -> void:
	var g := _open_grid(40, 20)
	var hero := Vector2(20 * T, 10 * T)
	var target := PackedVector2Array([hero])
	var kind := _walker()
	kind.behavior = EnemyData.Behavior.BLINKER
	kind.flying = true
	kind.attack_range = 220.0
	kind.attack_cooldown = 0.5
	kind.windup_time = 0.3
	for guarded: bool in [false, true]:
		var h := _horde(g, target, kind)
		if guarded:
			h.add_danger(hero, 60.0, 10.0)  # every spot at the hero's side is in it
		var i := _steady(h, hero + Vector2(-150, 0))
		h.action[i] = 0.0  # ready to blink
		for f in 120:
			h.update(DT, target)
		if guarded:
			assert_true(h.blink_to.is_empty(), "it never blinks into it")
		else:
			assert_false(h.blink_to.is_empty(), "it blinks to the hero's side when there's no AoE")


## Frames until `inside` stops holding for enemy `i` (INF if it never does).
func _time_to_leave(h: HordeSim, i: int, targets: PackedVector2Array, inside: Callable,
		max_seconds: float) -> float:
	var frames := 0
	while inside.call(h.pos[i]):
		if frames * DT >= max_seconds:
			return INF
		h.update(DT, targets)
		frames += 1
	return frames * DT


func test_enemies_caught_against_a_wall_get_out_along_it() -> void:
	# Straight out of the AoE is into the wall: it goes along the wall instead.
	var g := _open_grid(40, 20)
	var c := Vector2(3.5 * T, 10 * T)
	for targets: PackedVector2Array in [PackedVector2Array(), PackedVector2Array([Vector2(36 * T, 10 * T)])]:
		var h := _horde(g, targets)
		h.add_danger(c, 48.0, 10.0)
		var i := _steady(h, Vector2(T + 6, 10 * T))  # against the left wall
		var edge := 48.0 + h.t_radius[0]
		var t := _time_to_leave(h, i, targets, func(p: Vector2) -> bool: return p.distance_to(c) <= edge, 3.0)
		assert_true(t < 2.0, "got out along the wall (%.2f s, %d heroes)" % [t, targets.size()])


func test_enemies_caught_in_a_corner_get_out_along_a_wall() -> void:
	var g := _open_grid(40, 20)
	var none := PackedVector2Array()
	var h := _horde(g, none)
	var c := Vector2(4 * T, 4 * T)
	h.add_danger(c, 56.0, 10.0)
	var i := _steady(h, Vector2(T + 6, T + 6))  # straight out is into the corner
	var edge := 56.0 + h.t_radius[0]
	var t := _time_to_leave(h, i, none, func(p: Vector2) -> bool: return p.distance_to(c) <= edge, 5.0)
	assert_true(t < 3.5, "got out of the corner (%.2f s)" % t)


func test_enemies_dont_flee_one_aoe_into_another() -> void:
	# Straight out of a is into b, right next to it: it leaves a the other way.
	var g := _open_grid(40, 24)
	var none := PackedVector2Array()
	var h := _horde(g, none)
	var a := Vector2(20 * T, 12 * T)
	var b := a + Vector2(-80, 0)
	h.add_danger(a, 40.0, 10.0)
	h.add_danger(b, 40.0, 10.0)
	var i := _steady(h, a + Vector2(-25, 0))
	var edge := 40.0 + h.t_radius[0]
	var closest_b := INF
	var frames := 0
	while (h.pos[i].distance_to(a) <= edge or h.pos[i].distance_to(b) <= edge) and frames < 180:
		h.update(DT, none)
		closest_b = minf(closest_b, h.pos[i].distance_to(b))
		frames += 1
	assert_true(closest_b > edge, "never set foot in b (%.1f px from its middle at the closest)" % closest_b)
	assert_true(frames < 120, "and was clear of both soon (%.2f s)" % (frames * DT))


func test_enemies_go_round_an_aoe_on_the_side_that_is_open() -> void:
	# The AoE reaches the wall on the side its hero is on: it goes round the
	# other side instead of pressing into the wall.
	var g := _open_grid(40, 20)
	var hero := Vector2(30 * T, 2 * T)
	var target := PackedVector2Array([hero])
	var h := _horde(g, target)
	var c := Vector2(18 * T, 3 * T)
	h.add_danger(c, 44.0, 10.0)
	var i := _steady(h, Vector2(6 * T, 3 * T))
	var edge := 44.0 + h.t_radius[0]
	var closest := INF
	var frames := 0
	while h.pos[i].distance_to(hero) > T and frames < 1200:
		h.update(DT, target)
		closest = minf(closest, h.pos[i].distance_to(c))
		frames += 1
	assert_true(closest > edge, "never set foot in it (%.1f px from its middle at the closest)" % closest)
	assert_true(h.pos[i].distance_to(hero) <= T, "and went round below it to its hero (%.1f s)" % (frames * DT))


func test_enemies_wait_at_an_aoe_that_shuts_the_way() -> void:
	# A corridor the AoE fills from wall to wall: no way round, so it waits.
	var g := LevelGrid.new(40, 5)
	for x in 40:
		for y in 5:
			g.set_solid(x, y, y == 0 or y == 4 or x == 0 or x == 39)
	var hero := Vector2(34 * T, 2.5 * T)
	var target := PackedVector2Array([hero])
	var h := _horde(g, target)
	var c := Vector2(20 * T, 2.5 * T)
	h.add_danger(c, 40.0, 10.0)
	var i := _steady(h, Vector2(4 * T, 2.5 * T))
	var edge := 40.0 + h.t_radius[0]
	var closest := INF
	for f in 600:
		h.update(DT, target)
		closest = minf(closest, h.pos[i].distance_to(c))
	assert_true(closest > edge, "kept out (%.1f px from its middle at the closest)" % closest)
	assert_true(h.pos[i].distance_to(c) < edge + HordeSim.DANGER_MARGIN + HordeSim.DANGER_BAND,
		"waiting at its edge (%.1f px)" % h.pos[i].distance_to(c))


# --- the World's dangers -----------------------------------------------------------------------

func _make_world(team: Array[StringName]) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in team.size():
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = team[i]
	var data := LevelData.new()
	data.display_name = "Avoidance test"
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
	return world


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	(Engine.get_main_loop() as SceneTree).paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


func _frames(world: World, seconds: float) -> void:
	for f in maxi(1, roundi(seconds / DT)):
		world._process(DT)


## An enemy of kind `id` with `hp` at `p` (feet); returns its uid.
func _enemy(world: World, id: StringName, p: Vector2, hp: float = HP) -> int:
	var horde := world.horde
	var i := horde.spawn(horde.type_index(id), p)
	horde.hp[i] = hp
	horde.update(0.0, PackedVector2Array())  # hash, so queries find it at once
	return horde.uid[i]


func _hp(world: World, uid: int) -> float:
	var i := world.horde.index_of_uid(uid)
	return world.horde.hp[i] if i != -1 else 0.0


func _pos(world: World, uid: int) -> Vector2:
	return world.horde.pos[world.horde.index_of_uid(uid)]


## The horde's danger at `p` (its index), or -1.
func _danger_at(world: World, p: Vector2) -> int:
	var horde := world.horde
	for k in horde.danger_pos.size():
		if horde.danger_pos[k].distance_to(p) < 0.01:
			return k
	return -1


func test_zones_that_do_something_to_enemies_are_dangers() -> void:
	var world := _make_world([&"ranger", &"cleric"])
	var ranger := world.heroes[0]
	var cleric := world.heroes[1]
	cleric.position = ranger.position + Vector2(-140, 0)
	assert_true(ranger.ultimate().try_activate(Vector2.RIGHT))  # Arrow Rain ahead
	assert_true(ranger.movement().try_activate(Vector2.RIGHT))  # Backflip: caltrops where it stood
	assert_true(cleric.special().try_activate(Vector2.RIGHT))  # Sanctuary
	_frames(world, 0.5)
	var rain: Array = world.zones.filter(func(z: EffectZone) -> bool: return z.tick_visual == "arrows")
	var caltrops: Array = world.zones.filter(func(z: EffectZone) -> bool: return z.slow_time > 0.0)
	var sanctuary: Array = world.zones.filter(func(z: EffectZone) -> bool: return z.heal > 0.0)
	assert_eq([rain.size(), caltrops.size(), sanctuary.size()], [1, 1, 1], "all three are down")
	if rain.size() + caltrops.size() + sanctuary.size() != 3:
		_teardown(world)
		return
	for zone: EffectZone in [rain[0], caltrops[0]]:
		var k := _danger_at(world, zone.position)
		assert_true(k != -1, "a zone that hurts enemies is a danger (radius %.0f)" % zone.radius)
		if k != -1:
			assert_near(world.horde.danger_radius[k], zone.radius, 0.01, "as big as the zone")
			# (handed over before the zones tick, so a frame younger)
			assert_near(world.horde.danger_age[k], zone.elapsed - DT, 0.001, "and as old")
	assert_eq(_danger_at(world, sanctuary[0].position), -1, "one that only heals heroes isn't")
	_frames(world, 5.0)
	assert_eq(world.horde.danger_pos.size(), 0, "and they're gone with the zones")
	_teardown(world)


func test_blasts_on_their_way_down_are_dangers_until_they_land() -> void:
	var world := _make_world([&"mage"])
	var mage := world.heroes[0]
	var spot := world.grid.sweep_until_blocked(mage.position, mage.position + Vector2.RIGHT * 100.0, 2.0)
	assert_true(mage.ultimate().try_activate(Vector2.RIGHT))  # Meteor: lands in 1 s
	_frames(world, 0.5)
	assert_eq(world.horde.danger_pos.size(), 1, "its mark is a danger")
	if world.horde.danger_pos.size() == 1:
		assert_vec_near(world.horde.danger_pos[0], spot, 0.01, "where it will land")
		assert_near(world.horde.danger_radius[0], 72.0, 0.01, "as big as the blast")
		assert_near(world.horde.danger_age[0], 0.5, DT * 1.5, "there since the cast")
	mage.god_mode = false
	mage.invulnerable_time = 0.0
	mage.take_hit(1e6)
	_frames(world, DT)
	assert_eq(world.horde.danger_pos.size(), 0, "a downed Mage's Meteor waits with them")
	mage.revive(1.0)
	_frames(world, 0.6)
	assert_eq(world.horde.danger_pos.size(), 0, "and it's no danger once it's landed")
	_teardown(world)

	world = _make_world([&"engineer"])
	var engineer := world.heroes[0]
	engineer.apply_upgrade(UpgradePool.shared_library().find(&"engineer_mortar"))
	var pack := _enemy(world, &"brute", engineer.position + Vector2(150, 0))
	assert_true(engineer.special().try_activate(Vector2.RIGHT))
	var shell := -1
	for f in 30:
		world.horde.stun[world.horde.index_of_uid(pack)] = 1.0
		world._process(DT)
		if not world.horde.danger_pos.is_empty():
			shell = 0
			break
	assert_eq(shell, 0, "a mortar shell in the air is a danger")
	if shell == 0:
		assert_true(world.horde.danger_pos[0].distance_to(_pos(world, pack)) < 1.0, "on the pack it's shelling")
		assert_near(world.horde.danger_radius[0], Minion.MORTAR_BLAST, 0.01, "as big as its blast")
	_teardown(world)


func test_auras_round_a_hero_are_dangers_that_go_with_them() -> void:
	var world := _make_world([&"knight", &"rogue"])
	var knight := world.heroes[0]
	var rogue := world.heroes[1]
	rogue.position = knight.position + Vector2(0, 80)
	rogue.apply_upgrade(UpgradePool.shared_library().find(&"rogue_blade_vortex"))
	assert_true(knight.ultimate().try_activate(Vector2.RIGHT))  # Whirlwind
	assert_true(rogue.special().try_activate(Vector2.RIGHT))  # Blade Vortex
	_frames(world, 0.1)
	assert_eq(world.horde.danger_pos.size(), 2, "both spin round their hero")
	var k := _danger_at(world, knight.position)
	assert_true(k != -1, "the Whirlwind round the Knight")
	if k != -1:
		assert_near(world.horde.danger_radius[k], 34.0, 0.01, "as far as it reaches")
	k = _danger_at(world, rogue.position)
	assert_true(k != -1, "the knives round the Rogue")
	if k != -1:
		assert_near(world.horde.danger_radius[k], 26.0 + 4.0, 0.01, "as far as they reach")
	knight.position += Vector2(40, 0)
	_frames(world, DT)
	assert_true(_danger_at(world, knight.position) != -1, "wherever the Knight goes")
	_frames(world, 4.0)
	assert_eq(world.horde.danger_pos.size(), 0, "until they stop")
	_teardown(world)


func test_enemies_go_round_arrow_rain_instead_of_through_it() -> void:
	var world := _make_world([&"ranger"])
	var ranger := world.heroes[0]
	var walker := _enemy(world, &"swarmer", ranger.position + Vector2(230, 0))
	assert_true(ranger.ultimate().try_activate(Vector2.RIGHT))  # the rain falls between them
	var start := _pos(world, walker)
	var furthest_off := 0.0
	for f in roundi(4.9 / DT):
		world._process(DT)
		furthest_off = maxf(furthest_off, absf(_pos(world, walker).y - start.y))
	assert_near(_hp(world, walker), HP, 0.001, "it never walked into the rain")
	assert_true(furthest_off > 40.0, "it went round it (%.0f px off its straight line)" % furthest_off)
	_teardown(world)
