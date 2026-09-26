class_name FlowField
extends RefCounted
## Distance + direction field toward the nearest player over the LevelGrid.
## A multi-source BFS runs on a WorkerThreadPool thread every
## `refresh_interval` seconds and the result is swapped in when done, so the
## main thread never pays for it. Enemies read the packed arrays directly:
##   dist[cell]  BFS steps to the nearest player (UNREACHED if none)
##   dirs[cell]  0 = no direction, 1..8 = index into DIRS (8-way, no corner cutting)

const UNREACHED := 1 << 30
const DIAG := 0.70710678
const DIRS: Array[Vector2] = [
	Vector2(0, 0),
	Vector2(1, 0), Vector2(DIAG, DIAG), Vector2(0, 1), Vector2(-DIAG, DIAG),
	Vector2(-1, 0), Vector2(-DIAG, -DIAG), Vector2(0, -1), Vector2(DIAG, -DIAG),
]
const OFFSET_X: Array[int] = [0, 1, 1, 0, -1, -1, -1, 0, 1]
const OFFSET_Y: Array[int] = [0, 0, 1, 1, 1, 0, -1, -1, -1]
## Tiles around the players' bounding box that get computed; the rest of the
## level keeps its last value (enemies that far away get recycled anyway).
const WINDOW_MARGIN := 48


class Job:
	extends RefCounted
	var width := 0
	var height := 0
	var solid := PackedByteArray()
	var sources := PackedInt32Array()
	var window := Rect2i()
	var previous_dist := PackedInt32Array()
	var previous_dirs := PackedByteArray()
	var dist := PackedInt32Array()
	var dirs := PackedByteArray()

	func run() -> void:
		FlowField.compute(self)


var grid: LevelGrid
var dist := PackedInt32Array()
var dirs := PackedByteArray()
var refresh_interval := 0.2

var _refresh_in := 0.0
var _task_id := -1
var _job: Job


func setup(p_grid: LevelGrid) -> void:
	finish()
	grid = p_grid
	dist.resize(grid.width * grid.height)
	dist.fill(UNREACHED)
	dirs.resize(grid.width * grid.height)
	dirs.fill(0)


## Swaps in finished results and starts a new background job when due.
func tick(delta: float, sources: PackedVector2Array) -> void:
	if _task_id != -1 and WorkerThreadPool.is_task_completed(_task_id):
		_collect()
	_refresh_in -= delta
	if _task_id == -1 and _refresh_in <= 0.0 and not sources.is_empty():
		_refresh_in = refresh_interval
		_job = _make_job(sources)
		_task_id = WorkerThreadPool.add_task(_job.run, false, "flow field")


## Synchronous computation (level start, tests).
func compute_now(sources: PackedVector2Array) -> void:
	finish()
	var job := _make_job(sources)
	compute(job)
	dist = job.dist
	dirs = job.dirs


## Waits for any in-flight job. Call before discarding the field.
func finish() -> void:
	if _task_id != -1:
		_collect()


func is_busy() -> bool:
	return _task_id != -1


func _collect() -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	dist = _job.dist
	dirs = _job.dirs
	_job = null


func _make_job(sources: PackedVector2Array) -> Job:
	var job := Job.new()
	job.width = grid.width
	job.height = grid.height
	job.solid = grid.solid  # copy-on-write: later door changes don't race the thread
	job.previous_dist = dist
	job.previous_dirs = dirs
	var box := Rect2i()
	for i in sources.size():
		var cell := grid.cell_of(sources[i])
		if not grid.in_bounds(cell.x, cell.y):
			continue
		job.sources.append(cell.y * grid.width + cell.x)
		box = Rect2i(cell, Vector2i.ONE) if job.sources.size() == 1 else box.expand(cell)
	job.window = box.grow(WINDOW_MARGIN).intersection(Rect2i(0, 0, grid.width, grid.height))
	return job


static func compute(job: Job) -> void:
	var w := job.width
	var n := w * job.height
	var solid := job.solid
	var d := PackedInt32Array()
	var dir := PackedByteArray()
	if job.previous_dist.size() == n:
		d = job.previous_dist.duplicate()
		dir = job.previous_dirs.duplicate()
	else:
		d.resize(n)
		dir.resize(n)
	var x0 := job.window.position.x
	var y0 := job.window.position.y
	var x1 := job.window.end.x - 1
	var y1 := job.window.end.y - 1
	for y in range(y0, y1 + 1):
		var row := y * w
		for x in range(x0, x1 + 1):
			d[row + x] = UNREACHED
			dir[row + x] = 0

	# Multi-source BFS (4-neighbour) inside the window.
	var queue := PackedInt32Array()
	queue.resize(n)
	var q_head := 0
	var q_tail := 0
	for s in job.sources:
		if solid[s] == 0 and d[s] != 0:
			d[s] = 0
			queue[q_tail] = s
			q_tail += 1
	while q_head < q_tail:
		var c := queue[q_head]
		q_head += 1
		var next_d := d[c] + 1
		var cx := c % w
		var cy := c / w
		if cx > x0:
			var nc := c - 1
			if solid[nc] == 0 and d[nc] > next_d:
				d[nc] = next_d
				queue[q_tail] = nc
				q_tail += 1
		if cx < x1:
			var nc := c + 1
			if solid[nc] == 0 and d[nc] > next_d:
				d[nc] = next_d
				queue[q_tail] = nc
				q_tail += 1
		if cy > y0:
			var nc := c - w
			if solid[nc] == 0 and d[nc] > next_d:
				d[nc] = next_d
				queue[q_tail] = nc
				q_tail += 1
		if cy < y1:
			var nc := c + w
			if solid[nc] == 0 and d[nc] > next_d:
				d[nc] = next_d
				queue[q_tail] = nc
				q_tail += 1

	# Direction toward the lowest-distance neighbour (8-way, no corner cutting).
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c := cy * w + cx
			var cd := d[c]
			if cd == UNREACHED or cd == 0:
				continue
			var best := cd
			var best_dir := 0
			for k in range(1, 9):
				var ox := OFFSET_X[k]
				var oy := OFFSET_Y[k]
				var nx := cx + ox
				var ny := cy + oy
				if nx < x0 or ny < y0 or nx > x1 or ny > y1:
					continue
				var nc := ny * w + nx
				if solid[nc] != 0:
					continue
				if ox != 0 and oy != 0 and (solid[cy * w + nx] != 0 or solid[ny * w + cx] != 0):
					continue
				if d[nc] < best:
					best = d[nc]
					best_dir = k
			dir[c] = best_dir
	job.dist = d
	job.dirs = dir
