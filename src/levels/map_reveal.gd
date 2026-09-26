class_name MapReveal
extends RefCounted
## Which tiles the team has seen, for the minimap. Everything that has been
## inside the camera view (plus a small margin) counts as seen, so side rooms
## stay off the map until someone walks past them.

const MARGIN_TILES := 2
const INTERVAL := 0.1

var width := 0
var height := 0
## 1 = seen, per cell.
var seen := PackedByteArray()
var seen_count := 0
## Cells seen since the minimap last drained them (it repaints only these).
var fresh := PackedInt32Array()

var _timer := 0.0


func setup(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	seen = PackedByteArray()
	seen.resize(width * height)
	seen_count = 0
	fresh.clear()
	_timer = 0.0


func tick(dt: float, view: Rect2) -> void:
	_timer -= dt
	if _timer > 0.0:
		return
	_timer = INTERVAL
	reveal_rect(view)


func reveal_rect(view: Rect2) -> void:
	var x0 := maxi(0, floori(view.position.x * LevelGrid.INV_TILE) - MARGIN_TILES)
	var y0 := maxi(0, floori(view.position.y * LevelGrid.INV_TILE) - MARGIN_TILES)
	var x1 := mini(width - 1, floori(view.end.x * LevelGrid.INV_TILE) + MARGIN_TILES)
	var y1 := mini(height - 1, floori(view.end.y * LevelGrid.INV_TILE) + MARGIN_TILES)
	var s := seen
	for y in range(y0, y1 + 1):
		var row := y * width
		for x in range(x0, x1 + 1):
			if s[row + x] == 0:
				s[row + x] = 1
				fresh.append(row + x)
				seen_count += 1
	seen = s


func is_seen(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height:
		return false
	return seen[cell.y * width + cell.x] != 0


func is_seen_at(p: Vector2) -> bool:
	return is_seen(Vector2i(floori(p.x * LevelGrid.INV_TILE), floori(p.y * LevelGrid.INV_TILE)))
