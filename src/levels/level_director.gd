class_name LevelDirector
extends RefCounted
## Runs a level's objectives: arena rooms lock when the team walks in and
## spawn waves until their quota is beaten (and their nests are destroyed),
## the exit portal opens once every arena is cleared, and the boss level's
## throne room starts the boss fight. Wakes up nests (spawners) when heroes
## come near. Also keeps the objective text/target the HUD shows.

signal level_completed
signal boss_defeated
signal objective_changed(text: String)

enum RoomState { IDLE, ACTIVE, CLEARED }

const BOSS_SCENE := "res://src/enemies/boss/boss_demon.tscn"
const EXIT_RADIUS := 30.0
const EXIT_HOLD_TIME := 1.0
## Heroes must be this far inside an arena (from its doors) to trigger it.
const ACTIVATE_DEPTH := 36.0
const QUOTA_PER_EXTRA_PLAYER := 0.4
## Nests wake up when a living hero is this close...
const NEST_RANGE := 230.0
## ...and then spawn NEST_BATCH enemies about this often.
const NEST_INTERVAL := 2.6
const NEST_BATCH := 2
const NEST_POSE_TIME := 0.4


class Nest:
	var uid := 0
	var cell := Vector2i.ZERO
	var room := 0
	var index := -1
	var timer := 1.0


class Room:
	var id := 0
	var cells: Array[Vector2i] = []
	var doors: Array[Vector2i] = []
	var quota := 0
	var killed := 0
	var state := RoomState.IDLE
	var center := Vector2.ZERO


var world: World
var level: Level
var data: LevelData
var rooms: Array[Room] = []
var active_room: Room
var exit_open := false
var completed := false
var boss: BossDemon
var boss_hp_multiplier := 1.0
## Nests still standing (destroyed ones drop out on the next tick).
var nests: Array[Nest] = []
var objective := ""
## Where the objective is (for the HUD's off-screen arrow); INF when none.
var objective_target := Vector2.INF

var _exit_timer := 0.0
var _check_timer := 0.0
var _in_room_alive := 0


func setup(p_world: World) -> void:
	world = p_world
	level = world.level
	data = level.data
	var players := maxi(1, world.heroes.size())
	var quota_scale := 1.0 + QUOTA_PER_EXTRA_PLAYER * float(players - 1)
	var ids := level.room_cells.keys()
	ids.sort()
	for id: int in ids:
		var room := Room.new()
		room.id = id
		room.cells = level.room_cells[id]
		room.doors.assign(level.room_doors.get(id, []))
		var base_quota := data.arena_quotas[id - 1] if id - 1 < data.arena_quotas.size() else 50
		room.quota = int(round(base_quota * quota_scale))
		var sum := Vector2.ZERO
		for c in room.cells:
			sum += LevelGrid.cell_center(c)
		room.center = sum / maxf(1.0, room.cells.size())
		rooms.append(room)
	exit_open = rooms.is_empty() and not data.is_boss_level
	var spawner := world.spawner
	spawner.set_weights(data.enemy_weights)
	spawner.level_hp_multiplier = data.hp_multiplier
	spawner.corridor_cap_fraction = data.corridor_cap_fraction
	spawner.spawn_rate = data.corridor_spawn_rate
	spawner.mode = SpawnDirector.Mode.CORRIDOR if data.corridor_spawn_rate > 0.0 else SpawnDirector.Mode.OFF
	boss_hp_multiplier = spawner.effective_hp_multiplier()
	_update_objective()


func room_by_id(id: int) -> Room:
	for room in rooms:
		if room.id == id:
			return room
	return null


func arenas_cleared() -> int:
	var n := 0
	for room in rooms:
		if room.state == RoomState.CLEARED:
			n += 1
	return n


func tick(dt: float) -> void:
	if completed:
		return
	if boss:
		boss.tick(dt)
	_tick_nests(dt)
	if active_room:
		_tick_active_room(dt)
	else:
		_check_room_entry()
	if exit_open:
		_check_exit(dt)


func on_enemy_killed() -> void:
	if active_room:
		active_room.killed += 1
		_update_objective()


# --- arenas ----------------------------------------------------------------------------------

func _check_room_entry() -> void:
	for hero in world.heroes:
		if hero.is_downed():
			continue
		var id := level.room_at_position(hero.position)
		if id == 0:
			continue
		var room := room_by_id(id)
		if room and room.state == RoomState.IDLE and _distance_to_doors(room, hero.position) >= ACTIVATE_DEPTH:
			_activate(room, hero)
			return


func _distance_to_doors(room: Room, p: Vector2) -> float:
	var best := INF
	for door in room.doors:
		best = minf(best, LevelGrid.cell_center(door).distance_to(p))
	return best


func _activate(room: Room, leader: Hero) -> void:
	room.state = RoomState.ACTIVE
	active_room = room
	# Pull everyone who isn't inside the room (or stands in a doorway) in with the leader.
	for hero in world.heroes:
		if level.room_at_position(hero.position) != room.id:
			var spot := world.grid.nearest_open(leader.position + Vector2(randf_range(-10, 10), randf_range(-10, 10)))
			hero.position = spot
			world.fx.ring(spot, 12.0, hero.color, 0.4)
	level.set_doors_locked(room.id, true)
	Audio.play(&"door")
	for door in room.doors:
		world.fx.disc(LevelGrid.cell_center(door), 10.0, Color(0.9, 0.7, 0.4, 0.6), 0.3)
	world.shake(3.0)
	if data.is_boss_level and not level.boss_spawns.is_empty():
		_spawn_boss(level.boss_spawns[0])
		world.spawner.mode = SpawnDirector.Mode.OFF
	else:
		world.spawner.start_arena(room.cells, room.quota, data.arena_spawn_rate)
	_update_objective()


func _tick_active_room(dt: float) -> void:
	var room := active_room
	if data.is_boss_level:
		if boss == null or not is_instance_valid(boss):
			_clear(room)
		return
	_check_timer -= dt
	if _check_timer > 0.0:
		return
	_check_timer = 0.25
	_in_room_alive = 0
	var horde := world.horde
	for i in horde.count:
		if horde.hp[i] > 0.0 and not horde.is_object(i) and level.room_at_position(horde.pos[i]) == room.id:
			_in_room_alive += 1
	if world.spawner.arena_remaining <= 0 and _in_room_alive == 0:
		_clear(room)


func _clear(room: Room) -> void:
	room.state = RoomState.CLEARED
	active_room = null
	level.set_doors_locked(room.id, false)
	Audio.play(&"clear")
	world.spawner.mode = SpawnDirector.Mode.CORRIDOR if data.corridor_spawn_rate > 0.0 else SpawnDirector.Mode.OFF
	world.spawner.spawn_rate = data.corridor_spawn_rate
	world.pickups.spawn(room.center, PickupSim.Kind.HEART, 1)
	world.fx.ring(room.center, 60.0, Color(1, 0.95, 0.6), 0.6)
	if arenas_cleared() == rooms.size() and not data.is_boss_level:
		exit_open = true
		Audio.play(&"portal")
	_update_objective()


# --- nests ------------------------------------------------------------------------------------

func add_nest(uid: int, cell: Vector2i, room: int) -> void:
	var nest := Nest.new()
	nest.uid = uid
	nest.cell = cell
	nest.room = room
	nest.timer = randf_range(0.5, 1.5)
	nests.append(nest)
	_update_objective()


## Nest positions still standing, optionally only those in one arena room.
func nest_positions(room_id: int = -1) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var horde := world.horde
	for nest in nests:
		var i := horde.index_of_uid(nest.uid, nest.index)
		if i != -1 and horde.hp[i] > 0.0 and (room_id == -1 or nest.room == room_id):
			out.append(horde.pos[i])
	return out


func _tick_nests(dt: float) -> void:
	if nests.is_empty():
		return
	var horde := world.horde
	var spawner := world.spawner
	var k := 0
	while k < nests.size():
		var nest := nests[k]
		var i := horde.index_of_uid(nest.uid, nest.index)
		if i == -1 or horde.hp[i] <= 0.0:
			nests.remove_at(k)  # destroyed
			_update_objective()
			continue
		k += 1
		nest.index = i
		horde.action[i] = maxf(0.0, horde.action[i] - dt)  # spawning pose
		# Nests inside an arena sleep until that arena's fight starts.
		if nest.room != 0 and (room_by_id(nest.room) == null or room_by_id(nest.room).state != RoomState.ACTIVE):
			continue
		var p := horde.pos[i]
		if not _hero_within(p, NEST_RANGE):
			continue
		nest.timer -= dt
		if nest.timer > 0.0:
			continue
		nest.timer = NEST_INTERVAL * randf_range(0.85, 1.15)
		if horde.enemy_count() >= spawner.alive_cap:
			continue
		for n in NEST_BATCH:
			var spot := world.grid.nearest_open(p + Vector2.from_angle(randf() * TAU) * randf_range(12.0, 20.0))
			horde.spawn(spawner.pick_type(), spot, spawner.effective_hp_multiplier())
			world.fx.ring(spot, 7.0, Color(0.9, 0.3, 0.6), 0.3)
		horde.action[i] = NEST_POSE_TIME
		if world.camera.visible_rect().has_point(p):
			Audio.play(&"nest")


func _hero_within(p: Vector2, distance: float) -> bool:
	for hero in world.heroes:
		if not hero.is_downed() and hero.position.distance_squared_to(p) <= distance * distance:
			return true
	return false


# --- boss ------------------------------------------------------------------------------------

func _spawn_boss(at: Vector2) -> void:
	boss = (load(BOSS_SCENE) as PackedScene).instantiate()
	boss.setup(world, at, boss_hp_multiplier, world.spawner.effective_hp_multiplier())
	world.entities.add_child(boss)
	world.boss = boss
	boss.defeated.connect(_on_boss_defeated)
	world.fx.ring(at, 60.0, Color(1, 0.3, 0.2), 0.8)
	Audio.play(&"roar")


func _on_boss_defeated() -> void:
	boss = null
	world.boss = null
	completed = true
	objective = "The demon is slain!"
	objective_target = Vector2.INF
	objective_changed.emit(objective)
	boss_defeated.emit()


# --- exit ------------------------------------------------------------------------------------

func _check_exit(dt: float) -> void:
	var center := level.exit_center()
	if not center.is_finite():
		return
	var living := 0
	var inside := 0
	for hero in world.heroes:
		if hero.is_downed():
			continue
		living += 1
		if hero.position.distance_to(center) <= EXIT_RADIUS:
			inside += 1
	if living > 0 and inside == living:
		_exit_timer += dt
		if _exit_timer >= EXIT_HOLD_TIME:
			completed = true
			level_completed.emit()
	else:
		_exit_timer = 0.0


func _update_objective() -> void:
	objective_target = Vector2.INF
	if active_room:
		var room_nests := nest_positions(active_room.id)
		if data.is_boss_level:
			objective = "Defeat the Demon Lord!"
		elif not room_nests.is_empty():
			objective = "Destroy the nests!  %d left" % room_nests.size()
			objective_target = _nearest(room_nests)
		elif active_room.quota > 0:
			objective = "Survive the arena!  %d / %d" % [mini(active_room.killed, active_room.quota), active_room.quota]
		else:
			objective = "Clear the arena!"
	elif exit_open:
		objective = "Reach the exit portal"
		objective_target = level.exit_center()
	else:
		var next := _nearest_idle_room()
		if data.is_boss_level:
			objective = "Enter the throne room"
		else:
			objective = "Clear the arenas  %d / %d" % [arenas_cleared(), rooms.size()]
		if next:
			objective_target = next.center
	objective_changed.emit(objective)


func _nearest(points: Array[Vector2]) -> Vector2:
	var from := world.camera.global_position
	var best := Vector2.INF
	var best_d := INF
	for q in points:
		var d := q.distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = q
	return best


func _nearest_idle_room() -> Room:
	var from := world.camera.global_position
	var best: Room
	var best_d := INF
	for room in rooms:
		if room.state == RoomState.IDLE:
			var d := room.center.distance_squared_to(from)
			if d < best_d:
				best_d = d
				best = room
	return best
