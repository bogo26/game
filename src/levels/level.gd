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
const TILES_TEXTURE := preload("res://assets/tiles/dungeon_tiles.png")

var grid: LevelGrid
var player_spawns: Array[Vector2] = []
var enemy_spawn_hints: Array[Vector2] = []
var exit_cells: Array[Vector2i] = []
var door_cells: Array[Vector2i] = []

var _tiles: TileMapLayer


func build(data: LevelData) -> void:
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
		chars.append(line)

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
	if player_spawns.is_empty():
		player_spawns.append(grid.nearest_open(grid.size_px() * 0.5, 64))


func _pick_tile(chars: Array[PackedStringArray], x: int, y: int, w: int, h: int) -> Tile:
	var ch := chars[y][x]
	if ch == " ":
		return Tile.VOID
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
