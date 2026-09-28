class_name LevelDirector
extends RefCounted
## Runs a level's objectives: arena rooms lock when the team walks in and
## spawn their quota in 2-3 waves (the next one comes, after a breather, once
## most of the current one is beaten), until it's cleared (and their nests are
## destroyed), and the exit portal opens once every arena is cleared. A boss
## level's boss room starts a fight with its boss instead: beating a mini boss
## clears the room and opens the exit behind it; beating the final boss wins
## the run. Wakes up nests (spawners) when heroes come near. Also keeps the
## objective text/target the HUD shows, and the clock that keeps the team
## moving: dawdle between objectives and the horde grows restless (see
## RESTLESS_AFTER).

signal level_completed
## The final boss died: the run is won.
signal boss_defeated
## A mini boss died: its room clears and the exit portal opens.
signal mini_boss_defeated(boss_name: String)
signal objective_changed(text: String)
## A wave of the active arena started (1-based) - for the HUD callout.
signal wave_started(wave: int, waves: int)
## An arena room was cleared (the World vacuums up the XP).
signal arena_cleared(room_id: int)
## The horde grew restless (stage 1 when the clock runs out, then one more
## every RESTLESS_EVERY seconds) or calmed down again (0).
signal restless_changed(stage: int)

enum RoomState { IDLE, ACTIVE, CLEARED }

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
## Arena quotas above this come in 3 waves, others in 2; shares of the quota.
const THREE_WAVES_FROM := 61
const WAVE_SHARES_2: Array[float] = [0.45, 0.55]
const WAVE_SHARES_3: Array[float] = [0.3, 0.33, 0.37]
## The next wave comes once this share of the current one is left (or after
## WAVE_MAX_TIME), after a WAVE_BREATHER pause.
const WAVE_NEXT_SHARE := 0.25
const WAVE_MAX_TIME := 12.0
const WAVE_BREATHER := 2.0
## Keep moving: out of fights the team has this long to reach its next
## objective (an arena or the boss room cleared, then the exit), and each one
## reached starts the clock over. Levels without a corridor horde (nothing to
## farm) have no clock.
const RESTLESS_AFTER := 60.0
## When the clock runs out the horde grows restless: a stage straight away and
## another every RESTLESS_EVERY seconds, until the next objective. Each stage
## enemies drop RESTLESS_DROPS less of their XP and hearts (none from the
## 4th), and the corridor horde spawns RESTLESS_RATE faster, fills
## RESTLESS_CAP more of the alive cap, and comes with RESTLESS_HP more HP,
## RESTLESS_DAMAGE more damage, RESTLESS_SPEED more speed (at most
## RESTLESS_MAX_SPEED) and one more Elites.CHANCE of an elite. Fights hold
## the horde at the level's own settings (and full drops).
const RESTLESS_EVERY := 15.0
const RESTLESS_DROPS := 0.25
const RESTLESS_RATE := 0.25
const RESTLESS_CAP := 0.1
const RESTLESS_HP := 0.2
const RESTLESS_DAMAGE := 0.1
const RESTLESS_SPEED := 0.05
const RESTLESS_MAX_SPEED := 1.3


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
	## Enemies per wave (sums to the quota), the current wave, seconds since
	## it started, and the pause left before the next one (> 0 while waiting).
	var waves := PackedInt32Array()
	var wave := 0
	var wave_time := 0.0
	var breather := 0.0


var world: World
var level: Level
var data: LevelData
var rooms: Array[Room] = []
var active_room: Room
var exit_open := false
var completed := false
var boss: Boss
## The level's boss once it has appeared (kept after it dies).
var boss_name := ""
var boss_hp_multiplier := 1.0
## Nests still standing (destroyed ones drop out on the next tick).
var nests: Array[Nest] = []
var objective := ""
## Where the objective is (for the HUD's off-screen arrow); INF when none.
var objective_target := Vector2.INF
## The keep-moving clock (see RESTLESS_AFTER): whether this level has one,
## what it starts at (--restless-after shortens it), the seconds left on it,
## and how restless the horde is (0: calm).
var has_clock := false
var clock_length := RESTLESS_AFTER
var restless_in := RESTLESS_AFTER
var restless_stage := 0

var _exit_timer := 0.0
var _check_timer := 0.0
var _in_room_alive := 0
## Seconds since the clock ran out.
var _restless_time := 0.0
## The level's own horde settings: a calm horde's (see _apply_horde).
var _calm_rate := 0.0
var _calm_cap := 0.0
var _calm_hp := 1.0
var _calm_elites := 0.0
var _calm_damage := 1.0


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
	spawner.level_hp_multiplier = data.hp_multiplier * GameState.difficulty_value("hp")
	# Elites join the horde from the second level on (always in the test room).
	var elites := not world.run_mode or GameState.level_index >= 1
	spawner.elite_chance = Elites.CHANCE * GameState.difficulty_value("elites") if elites else 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--elite-chance="):  # debug: see (lots of) elites anywhere
			spawner.elite_chance = arg.get_slice("=", 1).to_float()
	world.horde.damage_mult = GameState.difficulty_value("damage")
	spawner.corridor_cap_fraction = data.corridor_cap_fraction
	spawner.spawn_rate = _rate(data.corridor_spawn_rate)
	spawner.mode = SpawnDirector.Mode.CORRIDOR if data.corridor_spawn_rate > 0.0 else SpawnDirector.Mode.OFF
	boss_hp_multiplier = spawner.unique_hp_multiplier() * data.boss_hp_multiplier
	_calm_rate = spawner.spawn_rate
	_calm_cap = spawner.corridor_cap_fraction
	_calm_hp = spawner.level_hp_multiplier
	_calm_elites = spawner.elite_chance
	_calm_damage = world.horde.damage_mult
	has_clock = world.run_mode and data.corridor_spawn_rate > 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--restless-after="):  # debug: see the horde grow restless sooner
			clock_length = maxf(1.0, arg.get_slice("=", 1).to_float())
	restless_in = clock_length
	_update_objective()


## A spawn rate adjusted for the difficulty.
static func _rate(rate: float) -> float:
	return rate * GameState.difficulty_value("spawn")


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
		if completed:
			return  # that was the final boss: the run is won
	_tick_nests(dt)
	if active_room:
		_tick_active_room(dt)
	else:
		_check_room_entry()
	if exit_open:
		_check_exit(dt)
	_tick_clock(dt)


## Pick rounds wait while an arena fight is on (chests' treasure rounds
## aside: see World.can_open_pick_round); in corridors and the boss fight
## they open right away.
func picks_held() -> bool:
	return active_room != null and not data.is_boss_level


func on_enemy_killed() -> void:
	if active_room:
		active_room.killed += 1
		_in_room_alive = maxi(0, _in_room_alive - 1)  # recounted every 0.25 s
		_update_objective()


## Enemies still to beat in the active arena: not yet spawned (this wave and
## the ones after it, or still in a spawn portal) + alive inside.
func enemies_left() -> int:
	if active_room == null:
		return 0
	var later := 0
	for k in range(active_room.wave + 1, active_room.waves.size()):
		later += active_room.waves[k]
	return world.spawner.arena_remaining + world.spawner.pending_count() + _in_room_alive + later


## Splits an arena quota into waves (see THREE_WAVES_FROM).
static func split_waves(quota: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if quota <= 0:
		return out
	var shares := WAVE_SHARES_3 if quota >= THREE_WAVES_FROM else WAVE_SHARES_2
	var given := 0
	for k in shares.size():
		var n := quota - given if k == shares.size() - 1 else int(round(quota * shares[k]))
		out.append(n)
		given += n
	return out


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
	if restless_stage != 0:
		_apply_horde(0)  # the clock waits during the fight, with the level's own horde (and the boss's adds)
	if data.is_boss_level and not level.boss_spawns.is_empty():
		_spawn_boss(level.boss_spawns[0])
		world.spawner.mode = SpawnDirector.Mode.OFF
		Audio.play_music(&"boss")
	else:
		room.waves = split_waves(room.quota)
		room.wave = 0
		room.wave_time = 0.0
		room.breather = 0.0
		world.spawner.start_arena(room.cells, room.waves[0] if not room.waves.is_empty() else 0,
			_rate(data.arena_spawn_rate))
		_announce_wave(room)
	_update_objective()


func _announce_wave(room: Room) -> void:
	if room.waves.size() > 1:
		wave_started.emit(room.wave + 1, room.waves.size())


func _tick_active_room(dt: float) -> void:
	var room := active_room
	if data.is_boss_level:
		if boss == null or not is_instance_valid(boss):
			_clear(room)
		else:
			_follow_boss()
		return
	room.wave_time += dt
	if room.breather > 0.0:
		room.breather -= dt
		if room.breather <= 0.0:
			_next_wave(room)
	_check_timer -= dt
	if _check_timer > 0.0:
		return
	_check_timer = 0.25
	_in_room_alive = 0
	var horde := world.horde
	for i in horde.count:
		if horde.hp[i] > 0.0 and not horde.is_object(i) and level.room_at_position(horde.pos[i]) == room.id:
			_in_room_alive += 1
	var spawner := world.spawner
	var wave_out := spawner.arena_remaining <= 0 and spawner.pending_count() == 0
	var more_waves := room.wave < room.waves.size() - 1
	if more_waves:
		if wave_out and room.breather <= 0.0 and (_in_room_alive <= int(room.waves[room.wave] * WAVE_NEXT_SHARE)
				or room.wave_time >= WAVE_MAX_TIME):
			room.breather = WAVE_BREATHER
	elif wave_out and _in_room_alive == 0:
		_clear(room)
		return
	_update_objective()


func _next_wave(room: Room) -> void:
	room.wave += 1
	room.wave_time = 0.0
	world.spawner.arena_remaining += room.waves[room.wave]
	_announce_wave(room)
	_update_objective()


func _clear(room: Room) -> void:
	room.state = RoomState.CLEARED
	active_room = null
	level.set_doors_locked(room.id, false)
	Audio.play(&"clear")
	world.spawner.mode = SpawnDirector.Mode.CORRIDOR if data.corridor_spawn_rate > 0.0 else SpawnDirector.Mode.OFF
	world.spawner.spawn_rate = _rate(data.corridor_spawn_rate)
	_reset_clock()  # an objective reached
	world.pickups.spawn(room.center, PickupSim.Kind.HEART, 1)
	world.fx.ring(room.center, 60.0, Color(1, 0.95, 0.6), 0.6)
	if arenas_cleared() == rooms.size() and not data.is_final_boss:
		exit_open = true
		Audio.play(&"portal")
	arena_cleared.emit(room.id)
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
	if nests.is_empty() or not world.spawner.enabled:
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
		if horde.enemy_count() + spawner.pending_count() >= spawner.alive_cap:
			continue
		for n in NEST_BATCH:
			var spot := world.grid.nearest_open(p + Vector2.from_angle(randf() * TAU) * randf_range(12.0, 20.0))
			spawner.queue_spawn(spawner.pick_type(), spot, spawner.effective_hp_multiplier())
		horde.action[i] = NEST_POSE_TIME + SpawnDirector.PORTAL_TIME
		if world.camera.visible_rect().has_point(p):
			Audio.play(&"nest")


func _hero_within(p: Vector2, distance: float) -> bool:
	for hero in world.heroes:
		if not hero.is_downed() and hero.position.distance_squared_to(p) <= distance * distance:
			return true
	return false


# --- keep moving ------------------------------------------------------------------------------

## Whether the keep-moving clock is running: out of fights, until the level ends.
func clock_running() -> bool:
	return has_clock and not completed and active_room == null


## How much of their XP and hearts enemies drop now: less and less while the
## horde is restless (never in a fight).
func drop_share() -> float:
	if active_room != null or restless_stage <= 0:
		return 1.0
	return maxf(0.0, 1.0 - RESTLESS_DROPS * restless_stage)


func _tick_clock(dt: float) -> void:
	if not clock_running():
		return
	var left := restless_in - dt
	restless_in = maxf(0.0, left)
	if left > 0.0:
		return
	_restless_time += minf(dt, -left)  # the part of this frame past the clock
	var stage := 1 + int(_restless_time / RESTLESS_EVERY)
	if stage != restless_stage:
		_set_restless(stage)


## An objective was reached: the clock starts over and the horde calms down.
func _reset_clock() -> void:
	restless_in = clock_length
	_restless_time = 0.0
	if restless_stage != 0:
		_set_restless(0)


func _set_restless(stage: int) -> void:
	restless_stage = stage
	_apply_horde(stage)
	restless_changed.emit(stage)


## Sets the horde up as restless as `stage` (0: the level's own settings).
## New spawns get the HP; damage and speed apply to every enemy at once.
func _apply_horde(stage: int) -> void:
	var s := float(stage)
	var spawner := world.spawner
	spawner.spawn_rate = _calm_rate * (1.0 + RESTLESS_RATE * s)
	spawner.corridor_cap_fraction = minf(1.0, _calm_cap + RESTLESS_CAP * s)
	spawner.level_hp_multiplier = _calm_hp * (1.0 + RESTLESS_HP * s)
	spawner.elite_chance = _calm_elites + Elites.CHANCE * GameState.difficulty_value("elites") * s
	world.horde.damage_mult = _calm_damage * (1.0 + RESTLESS_DAMAGE * s)
	world.horde.speed_mult = minf(RESTLESS_MAX_SPEED, 1.0 + RESTLESS_SPEED * s)


# --- boss ------------------------------------------------------------------------------------

## Spawns the level's boss (or the one in `scene`) at `at`.
func _spawn_boss(at: Vector2, scene: String = "") -> void:
	boss = (load(scene if scene != "" else data.boss_scene) as PackedScene).instantiate()
	boss.setup(world, at, boss_hp_multiplier, world.spawner.effective_hp_multiplier())
	boss_name = boss.display_name
	world.entities.add_child(boss)
	world.boss = boss
	boss.defeated.connect(_on_boss_defeated)
	world.fx.ring(at, 60.0, Color(1, 0.3, 0.2), 0.8)
	Audio.play(&"roar")


func _on_boss_defeated() -> void:
	boss = null
	world.boss = null
	if not data.is_final_boss:
		# A mini boss: its room clears this frame, and that opens the exit.
		Audio.play_music(&"dungeon")
		mini_boss_defeated.emit(boss_name)
		return
	completed = true
	objective = "The %s is slain!" % boss_name
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
	# Someone's in the portal: tell the others they're being waited for.
	if inside > 0 and inside < living:
		var missing := PackedStringArray()
		for hero in world.heroes:
			if not hero.is_downed() and hero.position.distance_to(center) > EXIT_RADIUS:
				missing.append("P%d" % (hero.slot + 1))
		objective = "Waiting for %s at the exit" % ", ".join(missing)
	elif objective.begins_with("Waiting for"):
		_update_objective()


func _update_objective() -> void:
	if completed:
		return  # the level is over (or the run won): its last word stands
	objective_target = Vector2.INF
	if active_room:
		var room_nests := nest_positions(active_room.id)
		if data.is_boss_level:
			objective = _boss_objective()
			if boss and is_instance_valid(boss):
				objective_target = boss.objective_point()
		elif not room_nests.is_empty():
			objective = "Destroy the nests!  %d left" % room_nests.size()
			objective_target = _nearest(room_nests)
		elif active_room.waves.size() > 1:
			objective = "Wave %d/%d  -  %d left" % [active_room.wave + 1, active_room.waves.size(), enemies_left()]
		elif active_room.quota > 0:
			objective = "Defeat the horde!  %d left" % enemies_left()
		else:
			objective = "Clear the arena!"
	elif exit_open:
		objective = "Reach the exit portal"
		objective_target = level.exit_center()
	else:
		var next := _next_idle_room()
		if data.is_boss_level:
			objective = "Enter the %s" % data.boss_room
		else:
			objective = "Clear the arenas  %d / %d" % [arenas_cleared(), rooms.size()]
		if next:
			objective_target = next.center
	objective_changed.emit(objective)


## During the fight: the boss's own call ("Burst the spore pods!") or "Defeat the <boss>!".
func _boss_objective() -> String:
	var hint := boss.objective_hint() if boss and is_instance_valid(boss) else ""
	return hint if hint != "" else "Defeat the %s!" % boss_name


## The arrow (and the bots) follow the fight as the boss moves; the text
## changes when the boss calls for something else.
func _follow_boss() -> void:
	objective_target = boss.objective_point()
	var text := _boss_objective()
	if text != objective:
		objective = text
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


## The idle arena the team can walk to soonest (by path, not straight line:
## rooms behind a wall are often far away on foot).
func _next_idle_room() -> Room:
	var idle: Array[Room] = []
	for room in rooms:
		if room.state == RoomState.IDLE:
			idle.append(room)
	if idle.size() <= 1:
		return idle[0] if not idle.is_empty() else null
	var grid := world.grid
	var dist := grid.walk_distances(grid.cell_of(grid.nearest_open(_team_position())))
	var best: Room
	var best_d := 0x7fffffff
	for room in idle:
		for c in room.cells:
			var d := dist[c.y * grid.width + c.x]
			if d >= 0 and d < best_d:
				best_d = d
				best = room
	if best == null:  # nothing reachable (shouldn't happen): fall back to straight line
		var from := _team_position()
		for room in idle:
			if best == null or room.center.distance_squared_to(from) < best.center.distance_squared_to(from):
				best = room
	return best


## Middle of the living heroes (the camera's centre when nobody is up).
func _team_position() -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for hero in world.heroes:
		if not hero.is_downed():
			sum += hero.position
			n += 1
	return sum / n if n > 0 else world.camera.global_position
