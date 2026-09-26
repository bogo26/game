class_name Level
extends Node2D
## Builds a level from LevelData: fills the tile map for rendering and the
## LevelGrid used by collision/pathfinding, and collects spawn points.

enum Tile {
	FLOOR0, FLOOR1, FLOOR2, FLOOR3, FLOOR_SHADOW, WALL_TOP, WALL_FACE, VOID,
	DOOR, EXIT, SPAWN_DEBUG, FLOOR_ARENA,
}
## Atlas coordinates in assets/tiles/dungeon_tiles.png (8 columns).
const TILE_COORDS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0),
	Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
]
const SOLID_TILES: Array[Tile] = [Tile.WALL_TOP, Tile.WALL_FACE, Tile.VOID, Tile.DOOR]
## What each cell shows as on the minimap.
enum MapKind { VOID, WALL, FLOOR, DOOR, EXIT, WATER, CHASM, SPIKES }
const TILES_TEXTURE := preload("res://assets/tiles/dungeon_tiles.png")

var grid: LevelGrid
var data: LevelData
var player_spawns: Array[Vector2] = []
var enemy_spawn_hints: Array[Vector2] = []
var exit_cells: Array[Vector2i] = []
var door_cells: Array[Vector2i] = []
var boss_spawns: Array[Vector2] = []
## Arena room id (1-9) -> its floor cells / its door cells.
var room_cells: Dictionary = {}
var room_doors: Dictionary = {}
## Cell index -> arena room id (0 = not in an arena).
var room_of_cell := PackedByteArray()
## Cell index -> MapKind.
var map_kind := PackedByteArray()

var _tiles: TileMapLayer


func build(p_data: LevelData) -> void:
	data = p_data
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
	room_cells.clear()
	room_doors.clear()
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
				"1", "2", "3", "4", "5", "6", "7", "8", "9":
					var room := ch.to_int()
					room_of_cell[y * width + x] = room
					if not room_cells.has(room):
						room_cells[room] = [] as Array[Vector2i]
					(room_cells[room] as Array[Vector2i]).append(cell)
		chars.append(line)
	# Boss markers sit inside arenas: count them as floor of the room they're in.
	for p in boss_spawns:
		var c := grid.cell_of(p)
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var room := _room_at(c + d, width, height)
			if room != 0:
				room_of_cell[c.y * width + c.x] = room
				(room_cells[room] as Array[Vector2i]).append(c)
				break
	# A door belongs to the arena room it touches.
	for door in door_cells:
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var room := _room_at(door + d, width, height)
			if room != 0:
				if not room_doors.has(room):
					room_doors[room] = [] as Array[Vector2i]
				(room_doors[room] as Array[Vector2i]).append(door)
				break

	if _tiles == null:
		_tiles = TileMapLayer.new()
		_tiles.name = "Tiles"
		_tiles.tile_set = _make_tileset()
		add_child(_tiles)
	_tiles.clear()
	for y in height:
		for x in width:
			var tile := _pick_tile(chars, x, y, width, height)
			if tile != Tile.VOID:
				_tiles.set_cell(Vector2i(x, y), 0, TILE_COORDS[tile])
			map_kind[y * width + x] = _map_kind_of(chars[y][x])
	if player_spawns.is_empty():
		player_spawns.append(grid.nearest_open(grid.size_px() * 0.5, 64))
	_tiles.modulate = data.tint


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


func exit_center() -> Vector2:
	if exit_cells.is_empty():
		return Vector2.INF
	var sum := Vector2.ZERO
	for c in exit_cells:
		sum += LevelGrid.cell_center(c)
	return sum / exit_cells.size()


func _pick_tile(chars: Array[PackedStringArray], x: int, y: int, w: int, h: int) -> Tile:
	var ch := chars[y][x]
	if ch == " ":
		return Tile.VOID
	if ch == "D":
		return Tile.FLOOR0
	if ch == "#":
		var below_open := y + 1 < h and chars[y + 1][x] not in ["#", " "]
		return Tile.WALL_FACE if below_open else Tile.WALL_TOP
	if ch == "X":
		return Tile.EXIT
	var above_wall := y > 0 and chars[y - 1][x] in ["#", " "]
	if above_wall:
		return Tile.FLOOR_SHADOW
	# Mostly plain floor with a sprinkle of detail, stable per cell.
	var hash_value := absi((x * 73856093) ^ (y * 19349663)) % 100
	if hash_value < 80:
		return Tile.FLOOR0
	if hash_value < 88:
		return Tile.FLOOR1
	if hash_value < 95:
		return Tile.FLOOR2
	return Tile.FLOOR3


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


static func _make_tileset() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(LevelGrid.TILE, LevelGrid.TILE)
	tile_set.add_custom_data_layer()
	tile_set.set_custom_data_layer_name(0, "solid")
	tile_set.set_custom_data_layer_type(0, TYPE_BOOL)
	var source := TileSetAtlasSource.new()
	source.texture = TILES_TEXTURE
	source.texture_region_size = Vector2i(LevelGrid.TILE, LevelGrid.TILE)
	for coords in TILE_COORDS:
		source.create_tile(coords)
	tile_set.add_source(source, 0)
	for tile in SOLID_TILES:
		source.get_tile_data(TILE_COORDS[tile], 0).set_custom_data("solid", true)
	return tile_set
