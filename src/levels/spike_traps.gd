class_name SpikeTraps
extends RefCounted
## Spike trap tiles ('^' in a layout). Each trap cycles retracted → warning
## (tips poke out) → up, and the moment it shoots up it stabs every hero and
## enemy standing on it, so luring the horde over traps pays off. Traps go
## off in waves: diagonal stripes two tiles wide fire one after another.

enum State { DOWN, WARN, UP }

const PERIOD := 3.0
const GROUPS := 3
const WARN_TIME := 0.75
const UP_TIME := 0.55
const HERO_DAMAGE := 14.0
## Enemy damage, scaled by the level's enemy HP multiplier: kills swarmers,
## spitters and exploders outright, hurts brutes.
const ENEMY_DAMAGE := 24.0

var time := 0.0
## Per grid cell: 0 = no trap, otherwise group + 1.
var group_of_cell := PackedByteArray()
var group_cells: Array = []  # group -> Array[Vector2i]
var group_state := PackedInt32Array()
var width := 0


func setup(cells: Array[Vector2i], grid: LevelGrid) -> void:
	width = grid.width
	group_of_cell = PackedByteArray()
	group_of_cell.resize(grid.width * grid.height)
	group_cells.clear()
	for g in GROUPS:
		group_cells.append([] as Array[Vector2i])
	for c in cells:
		var g := group_for(c)
		group_of_cell[c.y * width + c.x] = g + 1
		(group_cells[g] as Array[Vector2i]).append(c)
	group_state = PackedInt32Array()
	group_state.resize(GROUPS)
	time = 0.0
	for g in GROUPS:
		group_state[g] = state_at(g, 0.0)


func is_empty() -> bool:
	return group_state.is_empty() or group_of_cell.is_empty()


static func group_for(cell: Vector2i) -> int:
	return ((cell.x + cell.y) / 2) % GROUPS


## A group's state at time `t` (groups are a third of a period apart).
static func state_at(group: int, t: float) -> State:
	var phase := fposmod(t + group * PERIOD / GROUPS, PERIOD)
	if phase >= PERIOD - UP_TIME:
		return State.UP
	if phase >= PERIOD - UP_TIME - WARN_TIME:
		return State.WARN
	return State.DOWN


## Advances time; returns [group, new state] pairs for groups that changed.
## A change to UP is the stab.
func tick(dt: float) -> Array[Vector2i]:
	var changes: Array[Vector2i] = []
	time += dt
	for g in group_state.size():
		var s := state_at(g, time)
		if s != group_state[g]:
			group_state[g] = s
			changes.append(Vector2i(g, s))
	return changes


## Whether a stab from `group` hits something standing at `p`.
func is_in_group(p: Vector2, group: int) -> bool:
	var x := floori(p.x * LevelGrid.INV_TILE)
	var y := floori(p.y * LevelGrid.INV_TILE)
	var i := y * width + x
	return x >= 0 and y >= 0 and x < width and i < group_of_cell.size() and group_of_cell[i] == group + 1
