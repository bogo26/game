class_name LevelGrid
extends RefCounted
## Tile-resolution walkability grid shared by collision, the flow field and
## spawning. Cells outside the grid count as solid. World position (0, 0) is
## the top-left corner of cell (0, 0).
## Two blocking layers: `solid` stops walkers (walls, closed doors, chasms)
## and `shot_solid` stops projectiles and sight (walls and closed doors only),
## so shots fly across chasms. `terrain` marks what walkable floor is made of.

enum Terrain { FLOOR, WATER, CHASM, SPIKES }

const TILE := 16
const INV_TILE := 1.0 / TILE
const EPSILON := 0.001
## Walking speed multiplier in water (heroes and enemies).
const WATER_SPEED := 0.6

var width := 0
var height := 0
## 1 = blocks movement.
var solid := PackedByteArray()
## 1 = blocks projectiles and line of sight.
var shot_solid := PackedByteArray()
## Terrain per cell.
var terrain := PackedByteArray()
## Bumped on every change so cached data (flow fields) knows to refresh.
var version := 0
## Cell indices whose walkability changed, in order (consumers that mirror
## the grid, like the bots' A*, catch up from where they last read).
var changes := PackedInt32Array()


func _init(p_width: int = 0, p_height: int = 0) -> void:
	resize(p_width, p_height)


func resize(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	solid = PackedByteArray()
	solid.resize(width * height)
	shot_solid = PackedByteArray()
	shot_solid.resize(width * height)
	terrain = PackedByteArray()
	terrain.resize(width * height)
	changes.clear()
	version += 1


func size_px() -> Vector2:
	return Vector2(width * TILE, height * TILE)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func is_solid(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= width or y >= height:
		return true
	return solid[y * width + x] != 0


## Walls and doors: block walking and shots alike.
func set_solid(x: int, y: int, value: bool) -> void:
	if in_bounds(x, y):
		solid[y * width + x] = 1 if value else 0
		shot_solid[y * width + x] = 1 if value else 0
		_changed(y * width + x)


## Props standing on a tile (barrels, nests, chests): block walking only.
func set_blocker(x: int, y: int, value: bool) -> void:
	if in_bounds(x, y):
		solid[y * width + x] = 1 if value else 0
		_changed(y * width + x)


func _changed(i: int) -> void:
	changes.append(i)
	version += 1


## A chasm: can't be walked on, but shots and sight cross it.
func set_chasm(x: int, y: int) -> void:
	if in_bounds(x, y):
		var i := y * width + x
		solid[i] = 1
		shot_solid[i] = 0
		terrain[i] = Terrain.CHASM
		_changed(i)


## Walkable terrain (floor, water, spikes).
func set_terrain(x: int, y: int, value: Terrain) -> void:
	if in_bounds(x, y):
		terrain[y * width + x] = value


func terrain_at(pos: Vector2) -> Terrain:
	var x := floori(pos.x * INV_TILE)
	var y := floori(pos.y * INV_TILE)
	if not in_bounds(x, y):
		return Terrain.FLOOR
	return terrain[y * width + x] as Terrain


## Walking speed multiplier at a position (slowed in water).
func speed_factor_at(pos: Vector2) -> float:
	return WATER_SPEED if terrain_at(pos) == Terrain.WATER else 1.0


func is_shot_solid(x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= width or y >= height:
		return true
	return shot_solid[y * width + x] != 0


func is_solid_at(pos: Vector2) -> bool:
	return is_solid(floori(pos.x * INV_TILE), floori(pos.y * INV_TILE))


func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x * INV_TILE), floori(pos.y * INV_TILE))


static func cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * TILE, (cell.y + 0.5) * TILE)


## True if an axis-aligned box of half-size `r` centred at `pos` overlaps a solid tile.
func box_hits(pos: Vector2, r: float) -> bool:
	var x0 := floori((pos.x - r) * INV_TILE)
	var x1 := floori((pos.x + r - EPSILON) * INV_TILE)
	var y0 := floori((pos.y - r) * INV_TILE)
	var y1 := floori((pos.y + r - EPSILON) * INV_TILE)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if is_solid(x, y):
				return true
	return false


## Moves a body (box of half-size `r`) by `motion`, sliding along walls.
## Sub-steps so fast movers (dashes, projectiles) can't tunnel through tiles.
func move_and_slide(pos: Vector2, motion: Vector2, r: float) -> Vector2:
	var max_step := TILE * 0.5
	var steps := maxi(1, ceili(maxf(absf(motion.x), absf(motion.y)) / max_step))
	var step := motion / steps
	for i in steps:
		if step.x != 0.0:
			var nx := Vector2(pos.x + step.x, pos.y)
			if box_hits(nx, r):
				if step.x > 0.0:
					pos.x = floorf((nx.x + r) * INV_TILE) * TILE - r - EPSILON
				else:
					pos.x = (floorf((nx.x - r) * INV_TILE) + 1.0) * TILE + r + EPSILON
			else:
				pos.x = nx.x
		if step.y != 0.0:
			var ny := Vector2(pos.x, pos.y + step.y)
			if box_hits(ny, r):
				if step.y > 0.0:
					pos.y = floorf((ny.y + r) * INV_TILE) * TILE - r - EPSILON
				else:
					pos.y = (floorf((ny.y - r) * INV_TILE) + 1.0) * TILE + r + EPSILON
			else:
				pos.y = ny.y
	return pos


## Grid ray march (DDA). True if nothing that stops shots lies between a
## and b (chasms don't).
func line_of_sight(a: Vector2, b: Vector2) -> bool:
	return _ray_clear(a, b, shot_solid)


## True if a walker can go straight from a to b: no wall, closed door, chasm
## or prop on the line (water doesn't stop it). Enemies head straight at a
## hero while it holds, instead of following the flow field.
func walk_line_clear(a: Vector2, b: Vector2) -> bool:
	return _ray_clear(a, b, solid)


## DDA from a to b: false if a cell set in `blocked` (or off the grid) lies on the way.
func _ray_clear(a: Vector2, b: Vector2, blocked: PackedByteArray) -> bool:
	var w := width
	var h := height
	var cx := floori(a.x * INV_TILE)
	var cy := floori(a.y * INV_TILE)
	var ex := floori(b.x * INV_TILE)
	var ey := floori(b.y * INV_TILE)
	if cx < 0 or cy < 0 or cx >= w or cy >= h or blocked[cy * w + cx] != 0:
		return false
	var d := b - a
	var step_x := 1 if d.x > 0.0 else -1
	var step_y := 1 if d.y > 0.0 else -1
	var t_delta_x := INF if d.x == 0.0 else absf(TILE / d.x)
	var t_delta_y := INF if d.y == 0.0 else absf(TILE / d.y)
	var next_x := (cx + (1 if step_x > 0 else 0)) * TILE
	var next_y := (cy + (1 if step_y > 0 else 0)) * TILE
	var t_max_x := INF if d.x == 0.0 else (next_x - a.x) / d.x
	var t_max_y := INF if d.y == 0.0 else (next_y - a.y) / d.y
	# Every step crosses into the next cell along x or y: b's cell is exactly this many away.
	for s in absi(ex - cx) + absi(ey - cy):
		if t_max_x < t_max_y:
			t_max_x += t_delta_x
			cx += step_x
		else:
			t_max_y += t_delta_y
			cy += step_y
		if cx < 0 or cy < 0 or cx >= w or cy >= h or blocked[cy * w + cx] != 0:
			return false
	return true


## Where something flying from a toward b stops: b, or where the line enters
## the first tile that stops shots (so warning lines end at the wall).
func shot_reach(a: Vector2, b: Vector2) -> Vector2:
	var cell := cell_of(a)
	var end := cell_of(b)
	if is_shot_solid(cell.x, cell.y):
		return a
	var d := b - a
	var step_x := 1 if d.x > 0.0 else -1
	var step_y := 1 if d.y > 0.0 else -1
	var t_delta_x := INF if d.x == 0.0 else absf(TILE / d.x)
	var t_delta_y := INF if d.y == 0.0 else absf(TILE / d.y)
	var next_x := (cell.x + (1 if step_x > 0 else 0)) * TILE
	var next_y := (cell.y + (1 if step_y > 0 else 0)) * TILE
	var t_max_x := INF if d.x == 0.0 else (next_x - a.x) / d.x
	var t_max_y := INF if d.y == 0.0 else (next_y - a.y) / d.y
	var guard := absi(end.x - cell.x) + absi(end.y - cell.y) + 2
	while cell != end and guard > 0:
		guard -= 1
		var t_enter := 0.0
		if t_max_x < t_max_y:
			t_enter = t_max_x
			t_max_x += t_delta_x
			cell.x += step_x
		else:
			t_enter = t_max_y
			t_max_y += t_delta_y
			cell.y += step_y
		if is_shot_solid(cell.x, cell.y):
			return a + d * t_enter
	return b


## Furthest point along a→b that a body of half-size r can reach (for blinks).
func sweep_until_blocked(a: Vector2, b: Vector2, r: float) -> Vector2:
	var dist := a.distance_to(b)
	if dist <= 0.0:
		return a
	var dir := (b - a) / dist
	var travelled := 0.0
	var pos := a
	while travelled < dist:
		var step := minf(4.0, dist - travelled)
		var next := pos + dir * step
		if box_hits(next, r):
			break
		pos = next
		travelled += step
	return pos


## Walking distance in tiles from `from` to every cell (-1 = unreachable).
## Walls, closed doors and chasms block; props don't (they can be broken or
## walked around).
func walk_distances(from: Vector2i) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	if not in_bounds(from.x, from.y):
		return dist
	var queue := PackedInt32Array()
	queue.resize(width * height)
	var head := 0
	var tail := 0
	var start := from.y * width + from.x
	dist[start] = 0
	queue[tail] = start
	tail += 1
	var chasm := Terrain.CHASM
	while head < tail:
		var i := queue[head]
		head += 1
		var x := i % width
		var next_d := dist[i] + 1
		for n: int in [i - 1, i + 1, i - width, i + width]:
			if n < 0 or n >= dist.size() or dist[n] != -1:
				continue
			if (n == i - 1 and x == 0) or (n == i + 1 and x == width - 1):
				continue  # don't wrap around the row
			if shot_solid[n] != 0 or terrain[n] == chasm:
				continue
			dist[n] = next_d
			queue[tail] = n
			tail += 1
	return dist


## Nearest walkable cell centre to `pos` (spiral search), for safe spawns.
func nearest_open(pos: Vector2, max_radius: int = 6) -> Vector2:
	var c := cell_of(pos)
	if not is_solid(c.x, c.y):
		return pos
	for radius in range(1, max_radius + 1):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				if not is_solid(c.x + dx, c.y + dy):
					return cell_center(Vector2i(c.x + dx, c.y + dy))
	return pos
