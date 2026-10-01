class_name WaveDirector
extends LevelDirector
## Endless Waves: the team holds one sealed arena (The Pit,
## src/levels/data/waves.tres) against waves that keep getting harder, until
## it falls. A wave's enemies come in through portals, and the wave is cleared
## once none of them is left (or once a few stragglers have held out for a
## while: they stay in the fight). A short break follows, where pick rounds
## earned during the wave open, and then the next wave comes. Every 5th wave
## is a boss: a mini boss on waves 5, 15, 25..., a final boss on 10, 20, 30...
## Beating one opens a legendary round (every boss counts here, until each
## hero has taken all three of its legendaries), refills the team's lives
## and gives everyone a bonus pick. settings() holds the numbers behind each
## wave.

const ARENA_PATH := "res://src/levels/data/waves.tres"
## The tile sheets the arena may wear (one per game).
const THEMES: Array[StringName] = [&"crypt", &"flooded", &"bones", &"ossuary", &"fungal", &"frost",
	&"forge", &"throne", &"grove", &"cistern", &"mycelium", &"glacier"]
const BOSS_EVERY := 5
## Seconds before the first wave (the game's banner is up) and between waves.
const FIRST_BREAK := 4.0
const BREAK_TIME := 5.0
## A boss steps out of its portal this long after its wave starts.
const BOSS_PORTAL_TIME := 1.0
## Once all of a wave has come in, at most STRAGGLERS left for STRAGGLER_TIME
## count as cleared (they stay in the fight).
const STRAGGLERS := 3
const STRAGGLER_TIME := 20.0
## With this few left, the arrow (and the bots) go for the nearest one.
const POINT_AT_LEFT := 5
## Enemies in a wave (solo): QUOTA_BASE, QUOTA_PER_WAVE more every wave, at
## most QUOTA_MAX; x(1 + 0.4 per extra player), like arena quotas.
const QUOTA_BASE := 24
const QUOTA_PER_WAVE := 9
const QUOTA_MAX := 300
## Enemy HP: +HP_PER_WAVE a wave up to wave HP_LINEAR_UNTIL (x3.2, about the
## final boss level's), then x HP_GROWTH a wave, so a game always ends.
const HP_PER_WAVE := 0.115
const HP_LINEAR_UNTIL := 20
const HP_GROWTH := 1.07
## Spawns per second while below the alive cap.
const RATE_BASE := 24.0
const RATE_PER_WAVE := 1.2
const RATE_MAX := 48.0
## Enemy damage: +DAMAGE_PER_WAVE a wave after wave DAMAGE_FROM.
const DAMAGE_FROM := 10
const DAMAGE_PER_WAVE := 0.03
## Elites from wave ELITES_FROM: Elites.CHANCE, +10% a wave, up to x3.
const ELITES_FROM := 4
const ELITES_PER_WAVE := 0.1
const ELITES_MAX := 3.0
## The rest of the horde next to swarmers: [from wave, weight then, + per
## wave, at most] (the Molten Forge has 0.22 / 0.12 / 0.2).
const MIX := {
	&"brute": [2, 0.04, 0.012, 0.25],
	&"spitter": [3, 0.04, 0.01, 0.16],
	&"exploder": [4, 0.03, 0.012, 0.22],
}
## The level enemies a wave can feature: one per regular wave from wave 2, in
## an order shuffled per game; from wave 12 the one before it too, from wave
## 24 the two before.
const FEATURED: Array[StringName] = [&"bat", &"drowned", &"bone_archer", &"revenant", &"sporecap",
	&"frost_boar", &"salamander", &"imp", &"sporeling", &"eel", &"puffball", &"frost_wraith"]
const FEATURED_WEIGHT := 0.15
const MORE_FEATURED_FROM: Array[int] = [12, 24]
const BOSS_COLOR := Color("ff8a70")
const CLEAR_COLOR := Color(1, 0.95, 0.6)

enum Phase { BREAK, FIGHT }


## One wave's numbers, before the difficulty's multipliers.
class Wave:
	var number := 1
	## The boss's scene on a boss wave, "" on a regular one.
	var boss_scene := ""
	## Enemies in a regular wave.
	var quota := 0
	## Enemy HP, spawns per second, enemy damage and the elite chance.
	var hp := 1.0
	var rate := 24.0
	var damage := 1.0
	var elite_chance := 0.0
	## Spawn weights by enemy id.
	var weights: Dictionary = {}

	func is_boss() -> bool:
		return boss_scene != ""


var phase: Phase = Phase.BREAK
## The wave being fought, or the last one (null before the first).
var wave: Wave
## The next wave's number, and the seconds left before it comes.
var next_wave := 1
var break_left := FIRST_BREAK
## The arena.
var room: Room

var _minis: Array[String] = []
var _finals: Array[String] = []
var _seed := 0
var _straggle := 0.0
## A boss wave's portal: seconds until the boss steps out, and where.
var _boss_in := 0.0
var _boss_at := Vector2.ZERO
var _elite_override := -1.0
var _shown_countdown := -1


func setup(p_world: World) -> void:
	super.setup(p_world)
	room = rooms[0]
	world.spawner.mode = SpawnDirector.Mode.OFF
	has_clock = false  # the waves keep the pressure on themselves
	_seed = GameState.run_seed
	_minis = boss_scenes(false)
	_finals = boss_scenes(true)
	next_wave = GameState.wave + 1  # --wave=N starts further in
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--elite-chance="):  # debug: see (lots of) elites
			_elite_override = arg.get_slice("=", 1).to_float()
	_update_objective()


func tick(dt: float) -> void:
	if boss:
		boss.tick(dt)
	if phase == Phase.BREAK:
		break_left -= dt
		if break_left <= 0.0:
			_start_wave(next_wave)
		elif ceili(break_left) != _shown_countdown:
			_update_objective()
	elif wave.is_boss():
		_tick_boss_wave(dt)
	else:
		_tick_fight(dt)


## Picks earned during a regular wave wait for the break after it; during a
## boss wave they open at once, like in the run's boss fights.
func picks_held() -> bool:
	return phase == Phase.FIGHT and wave != null and not wave.is_boss()


static func is_boss_wave(n: int) -> bool:
	return n > 0 and n % BOSS_EVERY == 0


## Wave `n`'s numbers for `players` heroes: see the constants. The featured
## enemies and the bosses' order come from `seed_value`; `minis` and `finals`
## are the boss scenes to pick from. No autoloads: the difficulty is applied
## when the wave starts.
static func settings(n: int, players: int, seed_value: int, minis: Array[String],
		finals: Array[String]) -> Wave:
	var w := Wave.new()
	w.number = n
	w.hp = (1.0 + HP_PER_WAVE * float(mini(n, HP_LINEAR_UNTIL) - 1)) \
		* pow(HP_GROWTH, float(maxi(0, n - HP_LINEAR_UNTIL)))
	w.rate = minf(RATE_BASE + RATE_PER_WAVE * float(n - 1), RATE_MAX)
	w.damage = 1.0 + DAMAGE_PER_WAVE * float(maxi(0, n - DAMAGE_FROM))
	if n >= ELITES_FROM:
		w.elite_chance = Elites.CHANCE * minf(1.0 + ELITES_PER_WAVE * float(n - ELITES_FROM), ELITES_MAX)
	w.weights = {&"swarmer": 1.0}
	if is_boss_wave(n):
		# Odd boss waves (5, 15, ...) bring a mini boss, even ones a final
		# boss; each kind's three come in a shuffled order before any repeats.
		var final := (n / BOSS_EVERY) % 2 == 0
		var pool := finals if final else minis
		if not pool.is_empty():
			var order := _order(pool.size(), hash(seed_value * 7919 + (2 if final else 1)))
			w.boss_scene = pool[order[((n / BOSS_EVERY - 1) / 2) % pool.size()]]
			return w
	var extra_players := clampi(players, 1, 4) - 1
	w.quota = int(round(minf(QUOTA_BASE + QUOTA_PER_WAVE * (n - 1), QUOTA_MAX)
		* (1.0 + QUOTA_PER_EXTRA_PLAYER * float(extra_players))))
	for id: StringName in MIX:
		var m: Array = MIX[id]
		if n >= int(m[0]):
			w.weights[id] = minf(float(m[1]) + float(m[2]) * float(n - int(m[0])), float(m[3]))
	for id in featured(n, seed_value):
		w.weights[id] = FEATURED_WEIGHT
	return w


## The level enemies wave `n` features (see FEATURED).
static func featured(n: int, seed_value: int) -> Array[StringName]:
	var out: Array[StringName] = []
	if n < 2 or is_boss_wave(n):
		return out
	var order := _order(FEATURED.size(), hash(seed_value * 7919 + 3))
	# This is the index-th regular wave from wave 2 on (boss waves skipped).
	var index := n - 2 - n / BOSS_EVERY
	var count := 1
	for from in MORE_FEATURED_FROM:
		if n >= from:
			count += 1
	for k in mini(count, index + 1):
		out.append(FEATURED[order[(index - k) % FEATURED.size()]])
	return out


## 0 .. count - 1 in an order shuffled by `seed_value`.
static func _order(count: int, seed_value: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in count:
		out.append(i)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := out[i]
		out[i] = out[j]
		out[j] = t
	return out


## The run's bosses of one kind (RunConfig: its levels and boss pools), so
## bosses added to the run come to Endless Waves too.
static func boss_scenes(final: bool) -> Array[String]:
	var out: Array[String] = []
	for data in RunConfig.load_default().all_layouts():
		if data.is_boss_level and data.is_final_boss == final and not out.has(data.boss_scene):
			out.append(data.boss_scene)
	return out


## The arena for a game seeded with `seed_value`: The Pit, maybe mirrored,
## in one of the tile themes.
static func arena_for(seed_value: int) -> LevelData:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value * 7919 + 5)
	var data := (load(ARENA_PATH) as LevelData).mirrored(rng.randf() < 0.5, rng.randf() < 0.5)
	data.theme = THEMES[rng.randi_range(0, THEMES.size() - 1)]
	return data


# --- waves -----------------------------------------------------------------------------------

func _start_wave(n: int) -> void:
	wave = settings(n, world.heroes.size(), _seed, _minis, _finals)
	GameState.wave = n
	phase = Phase.FIGHT
	_straggle = 0.0
	_check_timer = 0.0
	var spawner := world.spawner
	spawner.set_weights(wave.weights)
	spawner.level_hp_multiplier = wave.hp * GameState.difficulty_value("hp")
	spawner.elite_chance = _elite_override if _elite_override >= 0.0 \
		else wave.elite_chance * GameState.difficulty_value("elites")
	world.horde.damage_mult = wave.damage * GameState.difficulty_value("damage")
	world.horde.speed_mult = GameState.difficulty_value("speed")
	room.state = RoomState.ACTIVE
	room.quota = wave.quota
	room.killed = 0
	Audio.play(&"wave")
	if wave.is_boss():
		active_room = null
		spawner.mode = SpawnDirector.Mode.OFF
		_boss_at = _boss_spot()
		_boss_in = BOSS_PORTAL_TIME
		world.warn_fx.portal(_boss_at, 22.0, FxLayer.DANGER, BOSS_PORTAL_TIME)
		Audio.play_music(&"boss")
		world.hud.callout("BOSS WAVE", BOSS_COLOR)
	else:
		active_room = room
		spawner.start_arena(room.cells, wave.quota, _rate(wave.rate))
		world.hud.callout("WAVE %d" % n)
		world.tip(&"waves", "Every wave is harder than the last: survive as many as you can")
	_in_room_alive = world.horde.enemy_count()
	_update_objective()


func _tick_fight(dt: float) -> void:
	var spawner := world.spawner
	var all_in := spawner.arena_remaining <= 0 and spawner.pending_count() == 0
	_straggle = _straggle + dt if all_in and _in_room_alive <= STRAGGLERS else 0.0
	_check_timer -= dt
	if _check_timer > 0.0:
		return
	_check_timer = 0.25
	_in_room_alive = world.horde.enemy_count()
	if all_in and (_in_room_alive == 0 or _straggle >= STRAGGLER_TIME):
		_clear_wave()
		return
	_update_objective()


func _tick_boss_wave(dt: float) -> void:
	if _boss_in > 0.0:
		_boss_in -= dt
		if _boss_in <= 0.0:
			boss_hp_multiplier = world.spawner.unique_hp_multiplier()
			_spawn_boss(_boss_at, wave.boss_scene)
			_update_objective()
	elif boss and is_instance_valid(boss):
		_follow_boss()


func _on_boss_defeated() -> void:
	boss = null
	world.boss = null
	Audio.play_music(&"dungeon")
	_clear_wave()
	# Any boss, mini or final: the World calls out "<NAME> SLAIN!" and queues
	# a legendary round ahead of the treasure round _clear_wave() queued.
	mini_boss_defeated.emit(boss_name)


## The wave is over: a heart for the team, the XP vacuum (the World's
## arena_cleared), a boss's rewards, and the break before the next one.
func _clear_wave() -> void:
	phase = Phase.BREAK
	break_left = BREAK_TIME
	next_wave = wave.number + 1
	active_room = null
	room.state = RoomState.CLEARED
	world.spawner.mode = SpawnDirector.Mode.OFF
	world.spawner.arena_remaining = 0
	Audio.play(&"clear")
	var spot := world.grid.nearest_open(_team_position())
	world.pickups.spawn(spot, PickupSim.Kind.HEART, 1)
	world.fx.ring(spot, 60.0, CLEAR_COLOR, 0.6)
	if wave.is_boss():
		GameState.add_treasure_pick()
		GameState.team_lives = GameState.lives_per_level()
	else:
		world.hud.callout("WAVE %d CLEARED" % wave.number, CLEAR_COLOR)
	arena_cleared.emit(room.id)
	_update_objective()


## Where a boss comes in: the arena's B spot furthest from the team.
func _boss_spot() -> Vector2:
	var team := _team_position()
	var best := room.center
	var best_d := -1.0
	for p in level.boss_spawns:
		var d := p.distance_squared_to(team)
		if d > best_d:
			best_d = d
			best = p
	return best


## The living enemy nearest the team (INF when there's none).
func _nearest_enemy() -> Vector2:
	var horde := world.horde
	var from := _team_position()
	var best := Vector2.INF
	var best_d := INF
	for i in horde.count:
		var behavior := horde.t_behavior[horde.type[i]]
		if horde.hp[i] <= 0.0 or behavior == EnemyData.Behavior.OBJECT or behavior == EnemyData.Behavior.NEST:
			continue
		var d := horde.pos[i].distance_squared_to(from)
		if d < best_d:
			best_d = d
			best = horde.pos[i]
	return best


func _update_objective() -> void:
	objective_target = Vector2.INF
	if phase == Phase.BREAK:
		_shown_countdown = ceili(break_left)
		var done := "Get ready!" if wave == null else "Wave %d cleared!" % wave.number
		var coming := "Boss wave" if is_boss_wave(next_wave) else "Wave %d" % next_wave
		objective = "%s  %s in %d" % [done, coming, _shown_countdown]
	elif wave.is_boss():
		objective = _boss_objective() if boss and is_instance_valid(boss) else "Boss wave!"
		if boss and is_instance_valid(boss):
			objective_target = boss.objective_point()
	else:
		var left := enemies_left()
		objective = "Wave %d  -  %d left" % [wave.number, left]
		if left <= POINT_AT_LEFT and world.spawner.arena_remaining <= 0:
			objective_target = _nearest_enemy()
	objective_changed.emit(objective)
