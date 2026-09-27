extends "res://tests/test_case.gd"

const T := LevelGrid.TILE
const DT := 1.0 / 60.0


func _open_grid(w: int, h: int) -> LevelGrid:
	var g := LevelGrid.new(w, h)
	for x in w:
		g.set_solid(x, 0, true)
		g.set_solid(x, h - 1, true)
	for y in h:
		g.set_solid(0, y, true)
		g.set_solid(w - 1, y, true)
	return g


func _swarmer() -> EnemyData:
	var d := EnemyData.new()
	d.id = &"test"
	d.max_hp = 10.0
	d.speed = 40.0
	d.radius = 5.0
	d.contact_damage = 7.0
	d.xp = 2
	return d


func _horde(g: LevelGrid, flow: FlowField) -> HordeSim:
	var types: Array[EnemyData] = [_swarmer()]
	var h := HordeSim.new()
	h.setup(g, flow, types)
	return h


# --- spatial hash ------------------------------------------------------------------

func test_spatial_hash_gathers_nearby_items() -> void:
	var hash := SpatialHash.new()
	hash.setup(Vector2(160, 160), 16.0, 8)
	var positions := PackedVector2Array([Vector2(8, 8), Vector2(20, 8), Vector2(150, 150), Vector2(-5, 300)])
	hash.rebuild(positions, positions.size())
	var out := PackedInt32Array()
	hash.gather(Vector2(10, 10), 12.0, out)
	assert_true(out.has(0) and out.has(1), "both near items found")
	assert_false(out.has(2), "far item excluded")
	out.clear()
	hash.gather(Vector2(150, 150), 4.0, out)
	assert_true(out.has(2))
	out.clear()
	hash.gather(Vector2(4, 156), 3.0, out)
	assert_true(out.has(3), "out-of-range positions clamp into edge cells")


# --- flow field ----------------------------------------------------------------------

func test_flow_field_routes_around_walls() -> void:
	# 12x7 room with a wall column at x=6 open only at y=5.
	var g := _open_grid(12, 7)
	for y in range(1, 5):
		g.set_solid(6, y, true)
	var flow := FlowField.new()
	flow.setup(g)
	flow.compute_now(PackedVector2Array([LevelGrid.cell_center(Vector2i(9, 2))]))
	var w := g.width
	assert_eq(flow.dist[2 * w + 9], 0, "source cell")
	# From (3,2) the path must detour through the gap at (6,5).
	var d := flow.dist[2 * w + 3]
	assert_true(d > 6, "detour distance %d is longer than straight line" % d)
	# Walk the field from (3,2); it must reach the source without entering walls.
	var cell := Vector2i(3, 2)
	var steps := 0
	while flow.dist[cell.y * w + cell.x] != 0 and steps < 50:
		var dir := flow.dirs[cell.y * w + cell.x]
		assert_true(dir != 0, "every reachable cell has a direction")
		if dir == 0:
			return
		cell += Vector2i(FlowField.OFFSET_X[dir], FlowField.OFFSET_Y[dir])
		assert_false(g.is_solid(cell.x, cell.y), "path stays on floor at %s" % cell)
		steps += 1
	assert_eq(flow.dist[cell.y * w + cell.x], 0, "reached the player")


func test_flow_field_nearest_of_several_sources() -> void:
	var g := _open_grid(20, 5)
	var flow := FlowField.new()
	flow.setup(g)
	flow.compute_now(PackedVector2Array([
		LevelGrid.cell_center(Vector2i(2, 2)), LevelGrid.cell_center(Vector2i(17, 2))]))
	var w := g.width
	assert_eq(flow.dist[2 * w + 4], 2, "left source is nearer")
	assert_eq(flow.dist[2 * w + 15], 2, "right source is nearer")
	assert_eq(FlowField.OFFSET_X[flow.dirs[2 * w + 4]], -1, "points left")
	assert_eq(FlowField.OFFSET_X[flow.dirs[2 * w + 15]], 1, "points right")


func test_flow_field_unreachable_cells() -> void:
	var g := _open_grid(10, 5)
	for y in 5:
		g.set_solid(5, y, true)  # sealed wall
	var flow := FlowField.new()
	flow.setup(g)
	flow.compute_now(PackedVector2Array([LevelGrid.cell_center(Vector2i(2, 2))]))
	assert_eq(flow.dist[2 * g.width + 7], FlowField.UNREACHED)
	assert_eq(flow.dirs[2 * g.width + 7], 0)


func test_flow_field_background_job_completes() -> void:
	var g := _open_grid(30, 30)
	var flow := FlowField.new()
	flow.setup(g)
	flow.tick(0.0, PackedVector2Array([LevelGrid.cell_center(Vector2i(15, 15))]))
	assert_true(flow.is_busy(), "job started on a worker thread")
	flow.finish()
	assert_false(flow.is_busy())
	assert_eq(flow.dist[15 * 30 + 15], 0)
	assert_eq(flow.dist[15 * 30 + 20], 5)


# --- horde -----------------------------------------------------------------------------

func test_horde_spawn_kill_compact() -> void:
	var g := _open_grid(20, 20)
	var flow := FlowField.new()
	flow.setup(g)
	var h := _horde(g, flow)
	for i in 5:
		h.spawn(0, Vector2(40 + i * 20, 40))
	assert_eq(h.count, 5)
	var uid_last := h.uid[4]
	assert_true(h.damage(1, 100.0, Vector2.ZERO, 2), "lethal hit reports a kill")
	assert_false(h.damage(1, 100.0, Vector2.ZERO, 2), "dead enemies can't be killed twice")
	assert_eq(h.kill_pos.size(), 1)
	assert_eq(h.kill_slot[0], 2)
	assert_near(h.damage_by_slot[2], 10.0, 0.001, "overkill isn't counted")
	assert_eq(h.alive_count(), 4)
	h.update(0.016, PackedVector2Array([Vector2(160, 160)]))
	assert_eq(h.count, 4, "dead removed on update")
	assert_eq(h.uid[1], uid_last, "last enemy swapped into the hole")
	for i in h.count:
		assert_true(h.hp[i] > 0.0)


func test_horde_moves_toward_target_and_respects_walls() -> void:
	var g := _open_grid(20, 10)
	for y in range(1, 9):
		g.set_solid(10, y, true)  # sealed wall between enemy and target
	var flow := FlowField.new()
	flow.setup(g)
	var target := PackedVector2Array([LevelGrid.cell_center(Vector2i(15, 5))])
	flow.compute_now(target)
	var h := _horde(g, flow)
	h.spawn(0, LevelGrid.cell_center(Vector2i(8, 5)))
	for frame in 120:
		h.update(1.0 / 60.0, target)
	assert_true(h.pos[0].x < 10 * T, "never walks through the wall (x=%f)" % h.pos[0].x)
	assert_true(h.pos[0].x > 8.5 * T, "but did walk toward the target")


func test_horde_separation_spreads_stacked_enemies() -> void:
	var g := _open_grid(20, 20)
	var flow := FlowField.new()
	flow.setup(g)
	var h := _horde(g, flow)
	for i in 6:
		h.spawn(0, Vector2(160, 160) + Vector2(i * 0.1, 0))
	h.update(0.0, PackedVector2Array())  # build the hash
	for frame in 60:
		h.update(1.0 / 60.0, PackedVector2Array())
	var min_d := INF
	for i in h.count:
		for j in range(i + 1, h.count):
			min_d = minf(min_d, h.pos[i].distance_to(h.pos[j]))
	assert_true(min_d > 4.0, "stack spread out (closest pair %.2f px)" % min_d)


func test_horde_queries() -> void:
	var g := _open_grid(20, 20)
	var flow := FlowField.new()
	flow.setup(g)
	var h := _horde(g, flow)
	h.spawn(0, Vector2(100, 100))
	h.spawn(0, Vector2(130, 100))
	h.spawn(0, Vector2(70, 100))
	h.update(0.0, PackedVector2Array())
	var out := PackedInt32Array()
	assert_eq(h.query_circle(Vector2(100, 100), 10.0, out), 1)
	assert_eq(h.query_circle(Vector2(100, 100), 30.0, out), 3, "radius includes enemy body")
	assert_eq(h.query_arc(Vector2(100, 100), Vector2.RIGHT, 40.0, 0.5, out), 2, "cone right + touching centre")
	assert_true(out.has(0) and out.has(1))
	assert_eq(h.nearest(Vector2(125, 100), 50.0), 1)
	assert_near(h.contact_damage_at(Vector2(104, 100), 5.0), 7.0)
	assert_near(h.contact_damage_at(Vector2(115, 90), 3.0), 0.0)


# --- projectiles & pickups ------------------------------------------------------------

func test_projectile_pierce_and_walls() -> void:
	var g := _open_grid(20, 10)
	var flow := FlowField.new()
	flow.setup(g)
	var h := _horde(g, flow)
	h.spawn(0, Vector2(100, 80))
	h.spawn(0, Vector2(140, 80))
	h.update(0.0, PackedVector2Array())
	var p := ProjectileSim.new()
	p.spawn(Vector2(60, 80), Vector2(400, 0), 4.0, 3.0, 2.0, ProjectileSim.Team.PLAYER, 1,
		ProjectileSim.Look.ARROW, 1)
	for frame in 30:
		p.update(1.0 / 60.0, h, g, PackedVector2Array(), PackedByteArray(), 5.0)
	assert_near(h.hp[0], 6.0, 0.001, "first enemy hit once")
	assert_near(h.hp[1], 6.0, 0.001, "pierced into the second")
	assert_eq(p.count, 0, "gone after pierce ran out")

	p.spawn(Vector2(40, 40), Vector2(0, -600), 1.0, 2.0, 5.0, ProjectileSim.Team.PLAYER, 0,
		ProjectileSim.Look.BOLT)
	p.update(0.1, h, g, PackedVector2Array(), PackedByteArray(), 5.0)
	assert_eq(p.count, 0, "wall stops a non-bouncing projectile")


func test_enemy_projectile_hits_targetable_hero() -> void:
	var g := _open_grid(20, 10)
	var flow := FlowField.new()
	flow.setup(g)
	var h := _horde(g, flow)
	h.update(0.0, PackedVector2Array())
	var p := ProjectileSim.new()
	p.spawn(Vector2(60, 80), Vector2(200, 0), 9.0, 3.0, 2.0, ProjectileSim.Team.ENEMY, -1,
		ProjectileSim.Look.SPIT)
	var heroes := PackedVector2Array([Vector2(100, 80), Vector2(80, 80)])
	var targetable := PackedByteArray([1, 0])
	for frame in 20:
		p.update(1.0 / 60.0, h, g, heroes, targetable, 5.0)
		if p.hero_hits.size() > 0:
			break
	assert_eq(p.hero_hits.size(), 2)
	assert_eq(int(p.hero_hits[0]), 0, "untargetable hero was skipped")
	assert_near(p.hero_hits[1], 9.0)


func test_pickups_home_in_and_merge_when_full() -> void:
	var pk := PickupSim.new()
	pk.spawn(Vector2(100, 100), PickupSim.Kind.XP, 3)
	var heroes := PackedVector2Array([Vector2(120, 100)])
	var ranges := PackedFloat32Array([30.0])
	var active := PackedByteArray([1])
	var got := 0
	for frame in 60:
		pk.update(1.0 / 60.0, heroes, ranges, active)
		for k in range(0, pk.collected.size(), 3):
			got += pk.collected[k + 2]
	assert_eq(got, 3, "collected the gem's value")
	assert_eq(pk.count, 0)

	for i in PickupSim.CAPACITY:
		pk.spawn(Vector2(10, 10), PickupSim.Kind.XP, 1)
	pk.spawn(Vector2(10, 10), PickupSim.Kind.XP, 5)
	var total := 0
	for i in pk.count:
		total += pk.value[i]
	assert_eq(pk.count, PickupSim.CAPACITY)
	assert_eq(total, PickupSim.CAPACITY + 5, "overflow merged, no XP lost")


func _typed(behavior: EnemyData.Behavior) -> EnemyData:
	var d := _swarmer()
	d.behavior = behavior
	d.attack_range = 100.0
	d.attack_cooldown = 0.5
	d.projectile_speed = 100.0
	d.explosion_radius = 30.0
	d.fuse_time = 0.3
	return d


func test_spitter_keeps_distance_and_fires() -> void:
	var g := _open_grid(30, 10)
	var flow := FlowField.new()
	flow.setup(g)
	var target := PackedVector2Array([LevelGrid.cell_center(Vector2i(20, 5))])
	flow.compute_now(target)
	var types: Array[EnemyData] = [_typed(EnemyData.Behavior.RANGED)]
	var h := HordeSim.new()
	h.setup(g, flow, types)
	var shots := ProjectileSim.new()
	h.projectiles = shots
	h.spawn(0, LevelGrid.cell_center(Vector2i(10, 5)))
	var fired := 0
	for frame in 300:  # walk into range, a random first cooldown (<= 1.5 s), then the wind-up
		h.update(1.0 / 60.0, target)
		fired = maxi(fired, shots.count)
	var dist := h.pos[0].distance_to(target[0])
	assert_true(fired > 0, "fired at the hero")
	assert_eq(shots.team[0], ProjectileSim.Team.ENEMY)
	assert_true(dist > 100.0 * 0.5 and dist <= 100.0 + 2.0, "holds position inside range (%.1f px)" % dist)


func test_exploder_fuses_then_blasts() -> void:
	var g := _open_grid(20, 10)
	var flow := FlowField.new()
	flow.setup(g)
	var target := PackedVector2Array([Vector2(160, 80)])
	flow.compute_now(target)
	var types: Array[EnemyData] = [_typed(EnemyData.Behavior.EXPLODER)]
	var h := HordeSim.new()
	h.setup(g, flow, types)
	h.spawn(0, Vector2(150, 80))
	for frame in 60:
		h.update(1.0 / 60.0, target)
	assert_eq(h.blast_pos.size(), 1, "exploded once")
	assert_eq(h.count, 0, "exploder removed")
	assert_eq(h.kill_slot[0], HordeSim.SELF_KILL, "self-destruct gives no XP credit")


func test_killing_exploder_during_fuse_prevents_blast() -> void:
	var g := _open_grid(20, 10)
	var flow := FlowField.new()
	flow.setup(g)
	var target := PackedVector2Array([Vector2(160, 80)])
	flow.compute_now(target)
	var types: Array[EnemyData] = [_typed(EnemyData.Behavior.EXPLODER)]
	var h := HordeSim.new()
	h.setup(g, flow, types)
	h.spawn(0, Vector2(150, 80))
	h.update(1.0 / 60.0, target)
	assert_eq(h.state[0], 1, "fuse lit when close")
	h.damage(0, 100.0, Vector2.ZERO, 0)
	for frame in 60:
		h.update(1.0 / 60.0, target)
	assert_eq(h.blast_pos.size(), 0)


# --- how enemies move -------------------------------------------------------------------------

## Spawns one that walks at exactly its kind's speed and never arcs in.
func _steady(h: HordeSim, p: Vector2, type_id: int = 0) -> int:
	var i := h.spawn(type_id, p)
	h.pace[i] = 1.0
	h.bend[i] = 0.0
	return i


## The atlas column the only enemy on screen is drawn with.
func _drawn_column(h: HordeSim) -> int:
	var layer := InstanceLayer.new()
	layer.setup(PlaceholderTexture2D.new(), HordeSim.SPRITE_CELL, HordeSim.SPRITE_FEET, HordeSim.CAPACITY)
	h.render(layer)
	var column := int(layer.buffer[8]) - h.t_frame0[h.type[0]]
	layer.free()
	return column


func test_enemies_get_up_to_speed_and_turn_round_smoothly() -> void:
	var g := _open_grid(40, 20)
	var flow := FlowField.new()
	flow.setup(g)
	var h := _horde(g, flow)
	var i := _steady(h, Vector2(320, 160))
	var right := PackedVector2Array([Vector2(600, 160)])
	var full := h.t_speed[0]
	h.update(DT, right)
	assert_true(h.walk[i].length() < full * 0.3, "not at full speed at once (%.1f px/s)" % h.walk[i].length())
	for f in 36:
		h.update(DT, right)
	assert_true(h.walk[i].length() > full * 0.9, "up to speed in 0.6 s (%.1f px/s)" % h.walk[i].length())
	var left := PackedVector2Array([Vector2(40, 160)])  # the hero is suddenly behind it
	var frames := 0
	while h.walk[i].x > 0.0 and frames < 60:
		h.update(DT, left)
		frames += 1
	assert_true(frames >= 4, "turning round takes a moment (%d frames)" % frames)
	assert_true(h.walk[i].x < 0.0, "but it does turn round")


func test_enemies_walk_straight_at_a_hero_in_the_open() -> void:
	var g := _open_grid(30, 16)
	var flow := FlowField.new()
	flow.setup(g)
	var start := LevelGrid.cell_center(Vector2i(4, 4))
	var target := PackedVector2Array([LevelGrid.cell_center(Vector2i(14, 7))])  # 10 tiles right, 3 down
	flow.compute_now(target)
	var h := _horde(g, flow)
	var i := _steady(h, start)
	var line := (target[0] - start).normalized()
	var worst := 0.0
	for f in 360:
		h.update(DT, target)
		worst = maxf(worst, absf((h.pos[i] - start).cross(line)))
	assert_true(h.pos[i].distance_to(target[0]) < T, "got there")
	# The flow field alone goes diagonally first, then straight: 30 px off the line.
	assert_true(worst < 6.0, "along the straight line (at most %.1f px off it)" % worst)


func test_enemies_go_round_a_pillar_to_reach_the_hero() -> void:
	var g := _open_grid(30, 16)
	for y in range(5, 11):
		for x in range(12, 15):
			g.set_solid(x, y, true)
	var flow := FlowField.new()
	flow.setup(g)
	var target := PackedVector2Array([LevelGrid.cell_center(Vector2i(22, 8))])
	flow.compute_now(target)
	var h := _horde(g, flow)
	var i := _steady(h, LevelGrid.cell_center(Vector2i(5, 8)))
	var in_wall := false
	var frames := 0
	while h.pos[i].distance_to(target[0]) > T and frames < 900:
		h.update(DT, target)
		in_wall = in_wall or g.is_solid_at(h.pos[i])
		frames += 1
	assert_false(in_wall, "never inside the pillar")
	assert_true(h.pos[i].distance_to(target[0]) <= T, "and got round it (%.1f s)" % (frames * DT))


func test_chasers_stop_at_the_hero_instead_of_piling_on() -> void:
	var g := _open_grid(20, 20)
	var flow := FlowField.new()
	flow.setup(g)
	var hero := Vector2(160, 160)
	var target := PackedVector2Array([hero])
	flow.compute_now(target)
	var h := _horde(g, flow)
	var i := _steady(h, hero + Vector2(60, 0))
	for f in 180:
		h.update(DT, target)
	var d := h.pos[i].distance_to(hero)
	assert_true(d > 2.0, "not on top of the hero (%.1f px)" % d)
	assert_true(d < HordeSim.HERO_RADIUS + h.t_radius[0], "but touching (%.1f px)" % d)
	assert_true(h.contact_damage_at(hero, HordeSim.HERO_RADIUS) > 0.0, "so it still hurts")
	assert_true(h.walk[i].length() < 1.0, "and it stands its ground")


func test_a_crowd_round_a_hero_does_not_flicker() -> void:
	var g := _open_grid(24, 24)
	var flow := FlowField.new()
	flow.setup(g)
	var hero := Vector2(192, 192)
	var target := PackedVector2Array([hero])
	flow.compute_now(target)
	var h := _horde(g, flow)
	for k in 12:
		h.spawn(0, hero + Vector2.from_angle(TAU * k / 12.0) * 48.0)
	for f in 120:  # gather round
		h.update(DT, target)
	var flips := PackedInt32Array()
	flips.resize(h.count)
	var before := h.facing.duplicate()
	for f in 120:
		h.update(DT, target)
		for k in h.count:
			if h.facing[k] != before[k]:
				flips[k] += 1
		before = h.facing.duplicate()
	var most := 0
	for k in h.count:
		most = maxi(most, flips[k])
	assert_true(most <= 2, "each faces one way (at most %d flips in 2 s)" % most)


func test_the_walk_cycle_follows_the_feet() -> void:
	var g := _open_grid(40, 10)
	for x in range(1, 39):
		g.set_terrain(x, 3, LevelGrid.Terrain.WATER)
	var flow := FlowField.new()
	flow.setup(g)
	var h := _horde(g, flow)
	var dry := _steady(h, LevelGrid.cell_center(Vector2i(2, 2)))
	var wet := _steady(h, LevelGrid.cell_center(Vector2i(2, 3)))
	var targets := PackedVector2Array([Vector2(1000, 2.5 * T), Vector2(1000, 3.5 * T)])
	for f in 60:  # up to speed
		h.update(DT, targets)
	var dry_from := h.stride[dry]
	var wet_from := h.stride[wet]
	for f in 60:
		h.update(DT, targets)
	var fps := h.types[0].anim_fps
	assert_near(h.stride[dry] - dry_from, fps, fps * 0.05, "a walk cycle at full speed on the floor")
	assert_near(h.stride[wet] - wet_from, fps * LevelGrid.WATER_SPEED, fps * 0.05, "slower wading")


func test_walkers_stand_still_but_flyers_keep_flapping() -> void:
	var g := _open_grid(20, 20)
	var flow := FlowField.new()
	flow.setup(g)
	var bat := _swarmer()
	bat.flying = true
	for kind: EnemyData in [_swarmer(), bat]:
		var types: Array[EnemyData] = [kind]
		var h := HordeSim.new()
		h.setup(g, flow, types)
		_steady(h, Vector2(160, 160))
		var columns := {}
		for f in 60:  # nobody to go after
			h.update(DT, PackedVector2Array())
			columns[_drawn_column(h)] = true
		if kind.flying:
			assert_true(columns.size() > 1, "a hovering flyer keeps flapping")
		else:
			assert_eq(columns.keys(), [0], "a walker stands in its neutral pose")


func test_every_enemy_has_its_own_pace_and_angle() -> void:
	var g := _open_grid(30, 10)
	var flow := FlowField.new()
	flow.setup(g)
	var h := _horde(g, flow)
	for k in 20:
		h.spawn(0, Vector2(24 + k * 20, 80))
	var paces := {}
	var bends := {}
	for k in h.count:
		paces[snappedf(h.pace[k], 0.001)] = true
		bends[snappedf(h.bend[k], 0.001)] = true
		assert_true(absf(h.pace[k] - 1.0) <= HordeSim.PACE_SPREAD + 0.0001, "pace %.3f" % h.pace[k])
		assert_true(absf(h.bend[k]) <= HordeSim.ARC_BEND + 0.0001, "bend %.3f" % h.bend[k])
	assert_true(paces.size() > 1 and bends.size() > 1, "no two alike")


func test_ranged_enemies_stand_still_to_shoot() -> void:
	var g := _open_grid(30, 10)
	var flow := FlowField.new()
	flow.setup(g)
	var target := PackedVector2Array([LevelGrid.cell_center(Vector2i(20, 5))])
	flow.compute_now(target)
	var types: Array[EnemyData] = [_typed(EnemyData.Behavior.RANGED)]
	var h := HordeSim.new()
	h.setup(g, flow, types)
	h.projectiles = ProjectileSim.new()
	var i := _steady(h, LevelGrid.cell_center(Vector2i(15, 5)))
	h.walk[i] = Vector2(0, 20)  # circling when its shot is ready
	h.action[i] = 0.0
	h.update(DT, target)
	assert_eq(h.state[i], 1, "winding up")
	var at := h.pos[i]
	while h.state[i] == 1:
		h.update(DT, target)
	assert_true(h.projectiles.count > 0, "shot")
	assert_true(h.pos[i].distance_to(at) < 0.01, "without taking a step")


func test_ranged_enemies_circle_while_they_wait_to_shoot() -> void:
	var g := _open_grid(30, 16)
	var flow := FlowField.new()
	flow.setup(g)
	var hero := LevelGrid.cell_center(Vector2i(15, 8))
	var target := PackedVector2Array([hero])
	flow.compute_now(target)
	var types: Array[EnemyData] = [_typed(EnemyData.Behavior.RANGED)]
	var h := HordeSim.new()
	h.setup(g, flow, types)
	h.projectiles = ProjectileSim.new()
	var i := _steady(h, hero + Vector2(-80, 0))
	h.action[i] = 5.0  # no shot for a while
	h.anim[i] = 0.0  # and no change of sides
	var start := (h.pos[i] - hero).angle()
	var nearest := INF
	var furthest := 0.0
	for f in 90:
		h.update(DT, target)
		var d := h.pos[i].distance_to(hero)
		nearest = minf(nearest, d)
		furthest = maxf(furthest, d)
	var turned := absf(angle_difference(start, (h.pos[i] - hero).angle()))
	assert_true(turned > deg_to_rad(10.0), "it circles the hero (%.0f degrees)" % rad_to_deg(turned))
	var attack_range := h.t_range[0]
	assert_true(nearest > attack_range * HordeSim.RANGED_BACKOFF and furthest < attack_range,
		"within its range all along (%.0f to %.0f px)" % [nearest, furthest])


func test_melee_enemies_arc_in_from_their_own_sides() -> void:
	var g := _open_grid(30, 30)
	var flow := FlowField.new()
	flow.setup(g)
	var hero := Vector2(240, 240)
	var target := PackedVector2Array([hero])
	flow.compute_now(target)
	var h := _horde(g, flow)
	var a := _steady(h, hero + Vector2(-110, -6))
	var b := _steady(h, hero + Vector2(-110, 6))
	h.bend[a] = HordeSim.ARC_BEND
	h.bend[b] = -HordeSim.ARC_BEND
	for f in 360:
		h.update(DT, target)
	var spread := absf(angle_difference((h.pos[a] - hero).angle(), (h.pos[b] - hero).angle()))
	assert_true(spread > deg_to_rad(60.0), "they close in from different sides (%.0f degrees apart)" % rad_to_deg(spread))
	for i: int in [a, b]:
		assert_true(h.pos[i].distance_to(hero) < HordeSim.HERO_RADIUS + h.t_radius[0], "and both reach the hero")


func test_a_shove_breaks_an_enemys_stride() -> void:
	var g := _open_grid(40, 10)
	var flow := FlowField.new()
	flow.setup(g)
	var types: Array[EnemyData] = [_swarmer(), load("res://src/enemies/data/brute.tres") as EnemyData]
	var h := HordeSim.new()
	h.setup(g, flow, types)
	var target := PackedVector2Array([Vector2(600, 80)])
	var light := _steady(h, Vector2(40, 48))
	var heavy := _steady(h, Vector2(40, 112), 1)
	for f in 60:  # up to speed
		h.update(DT, target)
	var light_speed := h.walk[light].length()
	var heavy_speed := h.walk[heavy].length()
	h.push(light, Vector2(-150, 0), 0)
	h.push(heavy, Vector2(-150, 0), 0)
	assert_true(h.walk[light].length() < light_speed * 0.4, "a swarmer loses its stride")
	assert_true(h.walk[heavy].length() > heavy_speed * 0.6, "a brute barely notices")
	for f in 30:
		h.update(DT, target)
	assert_true(h.walk[light].length() > light_speed * 0.9, "then it gets going again")
