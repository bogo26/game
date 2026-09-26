class_name Level
extends Node2D
## Builds a level from LevelData: fills the tile maps for rendering (floor and
## walls, then decorations, then torch light) and the LevelGrid used by
## collision/pathfinding, and collects spawn points, arena rooms, traps and
## the props the World places (barrels, urns, nests, chests, shrines).
## Each LevelData names a theme; tiles come from assets/tiles/tiles_<theme>.png.

enum Tile {
	FLOOR0, FLOOR1, FLOOR2, FLOOR3, FLOOR_SHADOW, WALL_TOP, WALL_FACE, VOID,
	DOOR, EXIT, SPAWN_DEBUG, FLOOR_ARENA, SPIKES_DOWN, SPIKES_WARN, SPIKES_UP, WATER_EDGE,
	WATER, CHASM_EDGE, CHASM,
}
## Atlas coordinates of each Tile in the theme sheet (8 columns).
const TILE_COORDS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
	Vector2i(4, 1), Vector2i(5, 1), Vector2i(6, 1), Vector2i(7, 1),
	Vector2i(0, 2), Vector2i(3, 2), Vector2i(4, 2),
]
## Tiles whose next two atlas cells to the right are animation frames.
const ANIMATED_TILES: Array[Tile] = [Tile.WATER, Tile.CHASM]
enum Decor { BONES, SKULL, COBWEB_L, COBWEB_R, RUBBLE, PUDDLE, MOSS, CRACKS, TORCH, BANNER, CHAINS, WALL_CRACK }
const DECOR_COORDS: Array[Vector2i] = [
	Vector2i(0, 3), Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
	Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3),
	Vector2i(0, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4),
]
## Floor clutter per theme: [chance per floor tile, {Decor: weight}].
const FLOOR_DECOR := {
	&"crypt": [0.05, {Decor.BONES: 2, Decor.SKULL: 1, Decor.RUBBLE: 3, Decor.CRACKS: 3, Decor.MOSS: 1, Decor.PUDDLE: 1}],
	&"flooded": [0.07, {Decor.PUDDLE: 4, Decor.MOSS: 5, Decor.RUBBLE: 2, Decor.CRACKS: 1}],
	&"bones": [0.09, {Decor.BONES: 5, Decor.SKULL: 3, Decor.RUBBLE: 2, Decor.CRACKS: 2}],
	&"throne": [0.04, {Decor.SKULL: 2, Decor.BONES: 1, Decor.CRACKS: 3, Decor.RUBBLE: 2}],
}
const TILE_SHEET := "res://assets/tiles/tiles_%s.png"
const GLOW_TEXTURE := preload("res://assets/sprites/fx/glow.png")
const TORCH_SPACING := 6
const TORCH_GLOW_SIZE := 84.0
const TORCH_GLOW_COLOR := Color(1.0, 0.6, 0.26, 0.2)
const LAVA_GLOW_COLOR := Color(1.0, 0.42, 0.12, 0.09)

## What each cell shows as on the minimap.
enum MapKind { VOID, WALL, FLOOR, DOOR, EXIT, WATER, CHASM, SPIKES }

## Something the World places on a cell: a horde object (barrel, urn, nest)
## or a node prop (chest, shrine).
class Prop:
	var kind: StringName
	var cell: Vector2i
	var room := 0

	func _init(p_kind: StringName, p_cell: Vector2i) -> void:
		kind = p_kind
		cell = p_cell

## Layout character -> prop kind.
const PROP_CHARS := {"b": &"barrel", "u": &"urn", "N": &"nest", "C": &"chest", "A": &"shrine"}

var grid: LevelGrid
var data: LevelData
var theme: StringName = &"crypt"
var player_spawns: Array[Vector2] = []
var enemy_spawn_hints: Array[Vector2] = []
var exit_cells: Array[Vector2i] = []
var door_cells: Array[Vector2i] = []
var boss_spawns: Array[Vector2] = []
var spike_cells: Array[Vector2i] = []
var props: Array[Prop] = []
## Arena room id (1-9) -> its cells / its door cells.
var room_cells: Dictionary = {}
var room_doors: Dictionary = {}
## Cell index -> arena room id (0 = not in an arena).
var room_of_cell := PackedByteArray()
## Cell index -> MapKind.
var map_kind := PackedByteArray()
## Torch flame positions (for their light).
var torches: Array[Vector2] = []

var _tiles: TileMapLayer
var _decor: TileMapLayer
var _lights: TorchLights
static var _tilesets: Dictionary = {}  # theme -> [tiles TileSet, decor TileSet]


func build(p_data: LevelData) -> void:
	data = p_data
	theme = data.theme if ResourceLoader.exists(TILE_SHEET % data.theme) else &"crypt"
	var rows := _parse_rows(data.layout)
	var height := rows.size()
	var width := 0
	for row in rows:
		width = maxi(width, row.length())
	grid = LevelGrid.new(width, height)
	player_spawns.clear()
	enemy_spawn_hints.clear()
	exit_cells.clear()
	door_cells.clear()
	boss_spawns.clear()
	spike_cells.clear()
	props.clear()
	room_cells.clear()
	room_doors.clear()
	torches.clear()
	room_of_cell = PackedByteArray()
	room_of_cell.resize(width * height)
	map_kind = PackedByteArray()
	map_kind.resize(width * height)

	var chars: Array[PackedStringArray] = []
	for y in height:
		var row := rows[y].rpad(width)
		var line := PackedStringArray()
		for x in width:
			var ch := row[x]
			line.append(ch)
			var cell := Vector2i(x, y)
			match ch:
				"#", " ":
					grid.set_solid(x, y, true)
				"P":
					player_spawns.append(LevelGrid.cell_center(cell))
				"S":
					enemy_spawn_hints.append(LevelGrid.cell_center(cell))
				"X":
					exit_cells.append(cell)
				"D":
					door_cells.append(cell)
				"B":
					boss_spawns.append(LevelGrid.cell_center(cell))
				"~":
					grid.set_terrain(x, y, LevelGrid.Terrain.WATER)
				":":
					grid.set_chasm(x, y)
				"^":
					grid.set_terrain(x, y, LevelGrid.Terrain.SPIKES)
					spike_cells.append(cell)
				_:
					if PROP_CHARS.has(ch):
						props.append(Prop.new(PROP_CHARS[ch], cell))
			map_kind[y * width + x] = _map_kind_of(ch)
		chars.append(line)
	_find_rooms(chars, width, height)
	for prop in props:
		prop.room = room_of_cell[prop.cell.y * width + prop.cell.x]

	_ensure_layers()
	_tiles.clear()
	_decor.clear()
	for y in height:
		for x in width:
			var tile := _pick_tile(chars, x, y, width, height)
			if tile != Tile.VOID:
				_tiles.set_cell(Vector2i(x, y), 0, TILE_COORDS[tile])
	_place_decor(chars, width, height)
	if player_spawns.is_empty():
		player_spawns.append(grid.nearest_open(grid.size_px() * 0.5, 64))
	_tiles.modulate = data.tint
	_decor.modulate = data.tint
	_lights.setup(torches, _lava_glows(chars, width, height))


func room_at_position(p: Vector2) -> int:
	var c := grid.cell_of(p)
	return _room_at(c, grid.width, grid.height)


func _room_at(c: Vector2i, width: int, height: int) -> int:
	if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height:
		return 0
	return room_of_cell[c.y * width + c.x]


## Closes (solid, door tile) or opens (floor) an arena room's doors.
func set_doors_locked(room: int, locked: bool) -> void:
	for door: Vector2i in room_doors.get(room, []):
		grid.set_solid(door.x, door.y, locked)
		_tiles.set_cell(door, 0, TILE_COORDS[Tile.DOOR if locked else Tile.FLOOR0])


## Shows spike traps retracted (0), about to fire (1) or up (2).
func set_spikes(cells: Array[Vector2i], state: int) -> void:
	var coords := TILE_COORDS[Tile.SPIKES_DOWN + clampi(state, 0, 2)]
	for c in cells:
		_tiles.set_cell(c, 0, coords)


func exit_center() -> Vector2:
	if exit_cells.is_empty():
		return Vector2.INF
	var sum := Vector2.ZERO
	for c in exit_cells:
		sum += LevelGrid.cell_center(c)
	return sum / exit_cells.size()


## Arena rooms: each group of digit cells seeds a flood fill over everything
## inside the room's walls (water, traps, chasms, props), stopping at doors.
func _find_rooms(chars: Array[PackedStringArray], width: int, height: int) -> void:
	for y in height:
		for x in width:
			var ch := chars[y][x]
			if not ch.is_valid_int() or ch == "0" or room_of_cell[y * width + x] != 0:
				continue
			var room := ch.to_int()
			if not room_cells.has(room):
				room_cells[room] = [] as Array[Vector2i]
			var cells: Array[Vector2i] = room_cells[room]
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			room_of_cell[y * width + x] = room
			while not queue.is_empty():
				var c: Vector2i = queue.pop_back()
				cells.append(c)
				for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var n := c + d
					if n.x < 0 or n.y < 0 or n.x >= width or n.y >= height:
						continue
					var i := n.y * width + n.x
					if room_of_cell[i] != 0 or chars[n.y][n.x] in ["#", " ", "D"]:
						continue
					room_of_cell[i] = room
					queue.append(n)
	# A door belongs to the arena room it touches.
	for door in door_cells:
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var room := _room_at(door + d, width, height)
			if room != 0:
				if not room_doors.has(room):
					room_doors[room] = [] as Array[Vector2i]
				(room_doors[room] as Array[Vector2i]).append(door)
				break


func _pick_tile(chars: Array[PackedStringArray], x: int, y: int, w: int, h: int) -> Tile:
	var ch := chars[y][x]
	var above := chars[y - 1][x] if y > 0 else " "
	match ch:
		" ":
			return Tile.VOID
		"D":
			return Tile.FLOOR0
		"#":
			var below_open := y + 1 < h and chars[y + 1][x] not in ["#", " "]
			return Tile.WALL_FACE if below_open else Tile.WALL_TOP
		"X":
			return Tile.EXIT
		"~":
			return Tile.WATER if above in ["~", ":"] else Tile.WATER_EDGE
		":":
			return Tile.CHASM if above == ":" else Tile.CHASM_EDGE
		"^":
			return Tile.SPIKES_DOWN
	if above in ["#", " "]:
		return Tile.FLOOR_SHADOW
	# Mostly plain floor with a sprinkle of detail, stable per cell.
	var hash_value := _cell_hash(x, y) % 100
	if hash_value < 80:
		return Tile.FLOOR0
	if hash_value < 88:
		return Tile.FLOOR1
	if hash_value < 95:
		return Tile.FLOOR2
	return Tile.FLOOR3


## Floor clutter, cobwebs in corners, and torches / banners on walls. All
## decided by a per-cell hash, so a level always looks the same.
func _place_decor(chars: Array[PackedStringArray], w: int, h: int) -> void:
	var settings: Array = FLOOR_DECOR.get(theme, FLOOR_DECOR[&"crypt"])
	var chance: float = settings[0]
	var weights: Dictionary = settings[1]
	var total := 0
	for k: int in weights:
		total += int(weights[k])
	var since_torch := {}  # row -> x of the last torch on it
	for y in h:
		for x in w:
			var ch := chars[y][x]
			var cell := Vector2i(x, y)
			var roll := _cell_hash(x * 7 + 3, y * 13 + 1)
			if ch == "#":
				# Wall faces (open floor right below) carry torches and hangings.
				if y + 1 >= h or not _is_open_floor(chars[y + 1][x]):
					continue
				var last: int = since_torch.get(y, -100)
				if x - last >= TORCH_SPACING and roll % 3 != 0:
					_decor.set_cell(cell, 0, DECOR_COORDS[Decor.TORCH])
					torches.append(Vector2(x * LevelGrid.TILE + 8, y * LevelGrid.TILE + 4))
					since_torch[y] = x
				elif roll % 100 < 10:
					_decor.set_cell(cell, 0, DECOR_COORDS[Decor.BANNER])
				elif roll % 100 < 15:
					_decor.set_cell(cell, 0, DECOR_COORDS[Decor.CHAINS])
				elif roll % 100 < 21:
					_decor.set_cell(cell, 0, DECOR_COORDS[Decor.WALL_CRACK])
				continue
			if not (ch in [".", "S"] or ch.is_valid_int()):
				continue
			var wall_up := y > 0 and chars[y - 1][x] == "#"
			if wall_up and x > 0 and chars[y][x - 1] == "#" and roll % 10 < 6:
				_decor.set_cell(cell, 0, DECOR_COORDS[Decor.COBWEB_L])
				continue
			if wall_up and x + 1 < w and chars[y][x + 1] == "#" and roll % 10 < 6:
				_decor.set_cell(cell, 0, DECOR_COORDS[Decor.COBWEB_R])
				continue
			if float(roll % 1000) / 1000.0 >= chance:
				continue
			var pick := (roll / 1000) % maxi(1, total)
			for k: int in weights:
				pick -= int(weights[k])
				if pick < 0:
					_decor.set_cell(cell, 0, DECOR_COORDS[k])
					break


## Lava lights up its surroundings: one soft glow per few lava tiles.
func _lava_glows(chars: Array[PackedStringArray], w: int, h: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if theme != &"throne":
		return out
	for y in range(0, h, 3):
		for x in range(0, w, 3):
			if chars[y][x] == ":":
				out.append(LevelGrid.cell_center(Vector2i(x, y)))
	return out


func _ensure_layers() -> void:
	if _tiles == null:
		_tiles = TileMapLayer.new()
		_tiles.name = "Tiles"
		add_child(_tiles)
		_decor = TileMapLayer.new()
		_decor.name = "Decor"
		add_child(_decor)
		_lights = TorchLights.new()
		_lights.name = "Lights"
		add_child(_lights)
	var sets := _tilesets_for(theme)
	_tiles.tile_set = sets[0]
	_decor.tile_set = sets[1]


static func _tilesets_for(p_theme: StringName) -> Array:
	if not _tilesets.has(p_theme):
		var texture := load(TILE_SHEET % p_theme) as Texture2D
		var tiles := _make_tileset(texture, TILE_COORDS, ANIMATED_TILES.map(func(t: Tile) -> Vector2i:
			return TILE_COORDS[t]), 0.3)
		var decor := _make_tileset(texture, DECOR_COORDS, [DECOR_COORDS[Decor.TORCH]], 0.14)
		_tilesets[p_theme] = [tiles, decor]
	return _tilesets[p_theme]


static func _is_open_floor(ch: String) -> bool:
	return ch in [".", "P", "S", "B", "~", "^"] or ch.is_valid_int()


static func _cell_hash(x: int, y: int) -> int:
	return absi((x * 73856093) ^ (y * 19349663))


static func _map_kind_of(ch: String) -> MapKind:
	match ch:
		" ":
			return MapKind.VOID
		"#":
			return MapKind.WALL
		"D":
			return MapKind.DOOR
		"X":
			return MapKind.EXIT
		"~":
			return MapKind.WATER
		":":
			return MapKind.CHASM
		"^":
			return MapKind.SPIKES
	return MapKind.FLOOR


static func _parse_rows(layout: String) -> PackedStringArray:
	var rows := PackedStringArray()
	for line in layout.replace("\r", "").split("\n"):
		rows.append(line)
	while not rows.is_empty() and rows[0].strip_edges() == "":
		rows.remove_at(0)
	while not rows.is_empty() and rows[rows.size() - 1].strip_edges() == "":
		rows.remove_at(rows.size() - 1)
	return rows


## `animated` tiles get three frames (themselves and the next two cells).
static func _make_tileset(texture: Texture2D, coords: Array[Vector2i], animated: Array,
		frame_time: float) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(LevelGrid.TILE, LevelGrid.TILE)
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(LevelGrid.TILE, LevelGrid.TILE)
	for c in coords:
		source.create_tile(c)
		if c in animated:
			source.set_tile_animation_frames_count(c, 3)
			for f in 3:
				source.set_tile_animation_frame_duration(c, f, frame_time)
	tile_set.add_source(source, 0)
	return tile_set
