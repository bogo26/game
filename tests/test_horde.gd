extends "res://tests/test_case.gd"

const T := LevelGrid.TILE


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
