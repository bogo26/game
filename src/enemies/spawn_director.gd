class_name SpawnDirector
extends RefCounted
## Keeps the horde topped up around the players: spawns just outside the
## camera on reachable floor at a steady rate, falls back to the level's spawn
## hints when nothing off-screen is open, and recycles enemies that fall far
## behind so the pressure stays on the team.

const ALIVE_CAP_BY_PLAYERS: Array[int] = [150, 150, 200, 250, 300]
const HP_SCALE_PER_EXTRA_PLAYER := 0.35
const SPAWN_MARGIN_MIN := 20.0
const SPAWN_MARGIN_MAX := 90.0
const RECYCLE_INTERVAL := 0.5
## Spawn points further than this (in flow-field steps) from any player are skipped.
const MAX_PATH_TILES := 70
const HINT_MIN_DISTANCE := 96.0

enum Mode {
	OFF,       ## nothing spawns
	CORRIDOR,  ## steady trickle just outside the camera
	ARENA,     ## waves inside the active arena room until its quota is spawned
}

var horde: HordeSim
var grid: LevelGrid
var flow: FlowField
var spawn_hints: Array[Vector2] = []
var enabled := true
var mode: Mode = Mode.CORRIDOR
## Fraction of the alive cap used in CORRIDOR mode.
var corridor_cap_fraction := 1.0
## ARENA mode: floor cells to spawn on and how many enemies are left to spawn.
var arena_cells: Array[Vector2i] = []
var arena_remaining := 0
## Emitted for each arena spawn so the World can draw a spawn portal.
signal spawned_in_arena(position: Vector2)
var alive_cap := 150
## Enemies per second while below the cap.
var spawn_rate := 30.0
var hp_multiplier := 1.0
## Per-level difficulty on top of the player-count scaling.
var level_hp_multiplier := 1.0
## Relative spawn weight per enemy type index.
var weights := PackedFloat32Array()

var _budget := 0.0
var _recycle_in := RECYCLE_INTERVAL
var _rng := RandomNumberGenerator.new()


func setup(p_horde: HordeSim, p_grid: LevelGrid, p_flow: FlowField, hints: Array[Vector2]) -> void:
	horde = p_horde
	grid = p_grid
	flow = p_flow
	spawn_hints = hints
	weights.resize(horde.types.size())
	weights.fill(0.0)
	if weights.size() > 0:
		weights[0] = 1.0


func effective_hp_multiplier() -> float:
	return hp_multiplier * level_hp_multiplier


func set_player_count(players: int) -> void:
	var n := clampi(players, 1, 4)
	alive_cap = ALIVE_CAP_BY_PLAYERS[n]
	hp_multiplier = 1.0 + HP_SCALE_PER_EXTRA_PLAYER * float(n - 1)


func set_weight(type_id: StringName, weight: float) -> void:
	var index := horde.type_index(type_id)
	if index >= 0:
		weights[index] = weight


func set_weights(by_id: Dictionary) -> void:
	weights.fill(0.0)
	for id in by_id:
		set_weight(StringName(id), float(by_id[id]))


func start_arena(cells: Array[Vector2i], quota: int, rate: float) -> void:
	mode = Mode.ARENA
	arena_cells = cells
	arena_remaining = quota
	spawn_rate = rate
	_budget = 0.0


func tick(dt: float, view: Rect2, hero_positions: PackedVector2Array) -> void:
	if not enabled or mode == Mode.OFF:
		return
	_budget = minf(_budget + spawn_rate * dt, 30.0)
	var cap := alive_cap
	if mode == Mode.CORRIDOR:
		cap = int(alive_cap * corridor_cap_fraction)
	var attempts := 0
	var alive := horde.enemy_count()
	while _budget >= 1.0 and alive < cap and attempts < 24:
		if mode == Mode.ARENA and arena_remaining <= 0:
			break
		attempts += 1
		var p := find_spawn_point(view, hero_positions) if mode == Mode.CORRIDOR \
			else find_arena_point(hero_positions)
		if not p.is_finite():
			continue
		horde.spawn(pick_type(), p, effective_hp_multiplier())
		alive += 1
		_budget -= 1.0
		if mode == Mode.ARENA:
			arena_remaining -= 1
			spawned_in_arena.emit(p)
	if mode == Mode.CORRIDOR:
		_recycle_in -= dt
		if _recycle_in <= 0.0:
			_recycle_in = RECYCLE_INTERVAL
			_recycle(view, hero_positions)


## A random arena floor cell at least HINT_MIN_DISTANCE from every hero.
func find_arena_point(hero_positions: PackedVector2Array) -> Vector2:
	if arena_cells.is_empty():
		return Vector2.INF
	for attempt in 8:
		var c := arena_cells[_rng.randi_range(0, arena_cells.size() - 1)]
		if grid.is_solid(c.x, c.y):
			continue
		var p := LevelGrid.cell_center(c)
		var far_enough := true
		for q in hero_positions:
			if q.distance_squared_to(p) < HINT_MIN_DISTANCE * HINT_MIN_DISTANCE:
				far_enough = false
				break
		if far_enough:
			return p + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3))
	return Vector2.INF


func pick_type() -> int:
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return 0
	var roll := _rng.randf() * total
	for i in weights.size():
		roll -= weights[i]
		if roll <= 0.0:
			return i
	return weights.size() - 1


## A reachable floor point just outside `view`, or Vector2.INF.
func find_spawn_point(view: Rect2, hero_positions: PackedVector2Array) -> Vector2:
	for attempt in 6:
		var margin := _rng.randf_range(SPAWN_MARGIN_MIN, SPAWN_MARGIN_MAX)
		var outer := view.grow(margin)
		var p := Vector2.ZERO
		match _rng.randi_range(0, 3):
			0:
				p = Vector2(_rng.randf_range(outer.position.x, outer.end.x), outer.position.y)
			1:
				p = Vector2(_rng.randf_range(outer.position.x, outer.end.x), outer.end.y)
			2:
				p = Vector2(outer.position.x, _rng.randf_range(outer.position.y, outer.end.y))
			_:
				p = Vector2(outer.end.x, _rng.randf_range(outer.position.y, outer.end.y))
		if _is_good_cell(p):
			return p + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3))
	# Nothing open off-screen (small rooms): use a spawn hint away from heroes.
	if not spawn_hints.is_empty():
		var hint := spawn_hints[_rng.randi_range(0, spawn_hints.size() - 1)]
		var far_enough := true
		for q in hero_positions:
			if q.distance_squared_to(hint) < HINT_MIN_DISTANCE * HINT_MIN_DISTANCE:
				far_enough = false
				break
		if far_enough and _is_good_cell(hint):
			return hint
	return Vector2.INF


func _is_good_cell(p: Vector2) -> bool:
	var c := grid.cell_of(p)
	if not grid.in_bounds(c.x, c.y) or grid.is_solid(c.x, c.y):
		return false
	return flow.dist[c.y * grid.width + c.x] < MAX_PATH_TILES


func _recycle(view: Rect2, hero_positions: PackedVector2Array) -> void:
	var keep := view.grow(maxf(view.size.x, view.size.y))
	for i in horde.count:
		if horde.hp[i] > 0.0 and horde.is_mobile(i) and not keep.has_point(horde.pos[i]):
			var p := find_spawn_point(view, hero_positions)
			if p.is_finite():
				horde.relocate(i, p)
