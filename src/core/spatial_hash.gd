class_name SpatialHash
extends RefCounted
## Uniform grid of linked lists stored in packed arrays, rebuilt every frame
## without allocations. `head[cell]` is the first item in a cell and
## `next[item]` the next one; -1 terminates. Items are indices into a sim's
## arrays. Hot loops read head/next directly; other code uses gather().

var cell_size := 16.0
var inv_cell := 1.0 / 16.0
var cols := 1
var rows := 1
var head := PackedInt32Array()
var next := PackedInt32Array()


func setup(world_size: Vector2, p_cell_size: float, capacity: int) -> void:
	cell_size = p_cell_size
	inv_cell = 1.0 / cell_size
	cols = maxi(1, ceili(world_size.x * inv_cell))
	rows = maxi(1, ceili(world_size.y * inv_cell))
	head.resize(cols * rows)
	head.fill(-1)
	next.resize(capacity)
	next.fill(-1)


func rebuild(positions: PackedVector2Array, count: int) -> void:
	head.fill(-1)
	var h := head
	var nx := next
	var inv := inv_cell
	var max_x := cols - 1
	var max_y := rows - 1
	var c := cols
	for i in count:
		var p := positions[i]
		var cell := clampi(int(p.y * inv), 0, max_y) * c + clampi(int(p.x * inv), 0, max_x)
		nx[i] = h[cell]
		h[cell] = i
	head = h
	next = nx


## Appends every item in cells overlapping the circle to `out` (unfiltered:
## callers check exact distances against their own radii).
func gather(center: Vector2, radius: float, out: PackedInt32Array) -> void:
	var x0 := clampi(int((center.x - radius) * inv_cell), 0, cols - 1)
	var x1 := clampi(int((center.x + radius) * inv_cell), 0, cols - 1)
	var y0 := clampi(int((center.y - radius) * inv_cell), 0, rows - 1)
	var y1 := clampi(int((center.y + radius) * inv_cell), 0, rows - 1)
	for cy in range(y0, y1 + 1):
		var row := cy * cols
		for cx in range(x0, x1 + 1):
			var j := head[row + cx]
			while j != -1:
				out.append(j)
				j = next[j]
