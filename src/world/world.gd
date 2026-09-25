class_name World
extends Node2D
## Gameplay root. Owns the level, heroes and the data-oriented sims, and ticks
## everything in a fixed order each frame (no per-node _process ordering):
##   input (InputRouter autoload) → bots → heroes (+abilities) → leash
##   → revives → flow field → spawner → horde → blasts/contact damage
##   → projectiles → zones → kills/drops → ult charge → pickups → camera → render
## Also exposes the combat helpers abilities use (damage_enemies_in_*, heal,
## revive, zones, fx, shake). Timings go to PerfMonitor (F3).

signal team_wiped

## Loaded at runtime: preloading would create a load cycle (hero.gd types World).
const HERO_SCENE_PATH := "res://src/heroes/hero.tscn"
const DEFAULT_HEROES: Array[StringName] = [&"knight", &"ranger", &"mage", &"cleric"]
const ENEMY_TYPES: Array[String] = [
	"res://src/enemies/data/swarmer.tres",
	"res://src/enemies/data/brute.tres",
	"res://src/enemies/data/spitter.tres",
	"res://src/enemies/data/exploder.tres",
]
const HORDE_ATLAS := preload("res://assets/sprites/enemies/horde_atlas.png")
const FX_ATLAS := preload("res://assets/sprites/fx/fx_atlas.png")
const MAX_DELTA := 1.0 / 30.0
const SPAWN_OFFSETS: Array[Vector2] = [Vector2(-12, -8), Vector2(12, -8), Vector2(-12, 8), Vector2(12, 8)]
const HEART_DROP_CHANCE := 0.004
const REVIVE_DECAY := 0.5
## Test rooms: seconds after a team wipe before everyone gets back up.
const TEST_ROOM_WIPE_RESET := 3.0

@export var level_data: LevelData
## Test rooms let players join mid-game by pressing A / Enter.
@export var allow_drop_in := true
## Bot players to add at start (also settable with --bots=N).
@export var bot_count := 0
@export var spawn_enemies := true
## Test rooms revive a wiped team automatically instead of ending the run.
@export var auto_revive_on_wipe := true

var grid: LevelGrid
var heroes: Array[Hero] = []
var zones: Array[EffectZone] = []
var bots: BotDriver
var flow := FlowField.new()
var horde := HordeSim.new()
var projectiles := ProjectileSim.new()
var pickups := PickupSim.new()
var spawner := SpawnDirector.new()

## Per-frame hero snapshots handed to the sims. `hero_positions` has every
## hero (camera, leash); `target_positions` only those enemies should chase.
var hero_positions := PackedVector2Array()
var target_positions := PackedVector2Array()
var _hero_targetable := PackedByteArray()
var _hero_ranges := PackedFloat32Array()
var _hero_active := PackedByteArray()
var _rng := RandomNumberGenerator.new()
var _scratch := PackedInt32Array()
var _wiped := false
var _wipe_timer := 0.0

@onready var level: Level = $Level
@onready var ground_fx: FxLayer = $GroundFx
@onready var entities: Node2D = $Entities
@onready var fx: FxLayer = $Fx
@onready var camera: SharedCamera = $Camera
@onready var pickup_layer: InstanceLayer = $PickupLayer
@onready var horde_layer: InstanceLayer = $HordeLayer
@onready var projectile_layer: InstanceLayer = $ProjectileLayer


func _ready() -> void:
	level.build(level_data)
	grid = level.grid
	camera.setup(grid.size_px())
	camera.snap_to(level.player_spawns[0])

	var enemy_types: Array[EnemyData] = []
	for path in ENEMY_TYPES:
		enemy_types.append(load(path) as EnemyData)
	flow.setup(grid)
	horde.setup(grid, flow, enemy_types)
	horde.projectiles = projectiles
	spawner.setup(horde, grid, flow, level.enemy_spawn_hints)
	spawner.enabled = spawn_enemies
	spawner.set_weight(&"brute", 0.07)
	spawner.set_weight(&"spitter", 0.08)
	spawner.set_weight(&"exploder", 0.06)
	horde_layer.setup(HORDE_ATLAS, Vector2i(32, 32), Vector2(16, 24), HordeSim.CAPACITY)
	projectile_layer.setup(FX_ATLAS, Vector2i(16, 16), Vector2(8, 8), ProjectileSim.CAPACITY)
	pickup_layer.setup(FX_ATLAS, Vector2i(16, 16), Vector2(8, 11), PickupSim.CAPACITY)

	var bots_wanted := maxi(bot_count, _cmdline_int("--bots=", 0))
	if bots_wanted > 0:
		BotDriver.add_bots(bots_wanted)
		bots = BotDriver.new(self)
		bots.fire_rate = float(_cmdline_int("--bot-fire=", 0))
		bots.use_abilities = bots.fire_rate <= 0.0
	for slot in InputRouter.assigned_slots():
		if GameState.slots[slot].hero_id == &"":
			GameState.slots[slot].hero_id = DEFAULT_HEROES[slot]
		spawn_hero(slot)
	if allow_drop_in:
		InputRouter.join_requested.connect(_on_join_requested)
	Events.player_device_lost.connect(_on_device_changed)
	Events.player_device_restored.connect(_on_device_changed)
	_snapshot_heroes()
	flow.compute_now(target_positions)


func _exit_tree() -> void:
	flow.finish()


func spawn_hero(slot: int) -> Hero:
	var hero: Hero = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	hero.setup(slot, GameState.slots[slot].hero_id, self)
	var anchor := level.player_spawns[slot % level.player_spawns.size()]
	if not heroes.is_empty():
		anchor = heroes[0].position  # drop-in joins next to the team
	hero.position = grid.nearest_open(anchor + SPAWN_OFFSETS[slot])
	entities.add_child(hero)
	heroes.append(hero)
	spawner.set_player_count(heroes.size())
	Events.hero_spawned.emit(slot)
	return hero


func hero_for_slot(slot: int) -> Hero:
	for hero in heroes:
		if hero.slot == slot:
			return hero
	return null


func _process(delta: float) -> void:
	var dt := minf(delta, MAX_DELTA)
	var t_start := Time.get_ticks_usec()

	if bots:
		bots.tick(dt)
	for hero in heroes:
		hero.tick(dt)
	_apply_leash()
	_update_revives(dt)
	_snapshot_heroes()
	var t_heroes := Time.get_ticks_usec()

	flow.tick(dt, target_positions)
	spawner.tick(dt, camera.visible_rect(), hero_positions)
	horde.update(dt, target_positions)
	_apply_blasts()
	_apply_contact_damage()
	var t_horde := Time.get_ticks_usec()

	projectiles.update(dt, horde, grid, hero_positions, _hero_targetable, Hero.RADIUS)
	_apply_projectile_hits()
	_update_zones(dt)
	var t_projectiles := Time.get_ticks_usec()

	_process_kills()
	_apply_ult_charge()
	pickups.update(dt, hero_positions, _hero_ranges, _hero_active)
	_apply_pickups()
	_check_wipe(dt)
	camera.follow(hero_positions, dt)
	var t_sim_end := Time.get_ticks_usec()

	horde.render(horde_layer)
	projectiles.render(projectile_layer)
	pickups.render(pickup_layer)
	ground_fx.tick(dt)
	fx.tick(dt)
	var t_end := Time.get_ticks_usec()

	PerfMonitor.record(&"heroes", t_heroes - t_start)
	PerfMonitor.record(&"horde", t_horde - t_heroes)
	PerfMonitor.record(&"proj", t_projectiles - t_horde)
	PerfMonitor.record(&"render", t_end - t_sim_end)
	PerfMonitor.record(&"sim", t_end - t_start)
	PerfMonitor.set_counter(&"enemies", horde.alive_count())
	PerfMonitor.set_counter(&"projectiles", projectiles.count)
	PerfMonitor.set_counter(&"gems", pickups.count)


# --- combat helpers for abilities -------------------------------------------------------------

## Damages enemies overlapping a circle, knocking them away from the centre.
## Returns how many were hit.
func damage_enemies_in_circle(center: Vector2, radius: float, damage: float, knockback: float,
		source_slot: int, stun_time: float = 0.0, slow_time: float = 0.0) -> int:
	horde.query_circle(center, radius, _scratch)
	return _damage_scratch(center, damage, knockback, source_slot, stun_time, slow_time)


## Damages enemies in a cone (melee swings).
func damage_enemies_in_arc(center: Vector2, dir: Vector2, radius: float, half_angle: float,
		damage: float, knockback: float, source_slot: int, stun_time: float = 0.0) -> int:
	horde.query_arc(center, dir, radius, half_angle, _scratch)
	return _damage_scratch(center, damage, knockback, source_slot, stun_time, 0.0)


## Damages every enemy inside a rectangle (screen-wide ultimates).
func damage_enemies_in_rect(rect: Rect2, damage: float, knock_from: Vector2, knockback: float,
		source_slot: int, stun_time: float = 0.0, slow_time: float = 0.0) -> int:
	_scratch.clear()
	for i in horde.count:
		if horde.hp[i] > 0.0 and rect.has_point(horde.pos[i]):
			_scratch.append(i)
	return _damage_scratch(knock_from, damage, knockback, source_slot, stun_time, slow_time)


func _damage_scratch(center: Vector2, damage: float, knockback: float, source_slot: int,
		stun_time: float, slow_time: float) -> int:
	var hits := 0
	for j in _scratch:
		var push := Vector2.ZERO
		if knockback != 0.0:
			var away := horde.pos[j] - center
			push = away.normalized() * knockback if away.length_squared() > 0.01 else Vector2.UP * knockback
		if damage > 0.0:
			horde.damage(j, damage, push, source_slot)
		elif push != Vector2.ZERO:
			horde.vel[j] += push
		if stun_time > 0.0:
			horde.apply_stun(j, stun_time)
		if slow_time > 0.0:
			horde.apply_slow(j, slow_time)
		hits += 1
	return hits


## Heals living heroes within `radius` by a fraction of their max HP.
func heal_heroes(center: Vector2, radius: float, fraction: float) -> void:
	for hero in heroes:
		if not hero.is_downed() and (radius == INF or hero.position.distance_to(center) <= radius):
			hero.heal(hero.max_hp * fraction)
			fx.disc(hero.position + Vector2(0, -6), 8.0, Color(0.5, 1.0, 0.5, 0.6), 0.3)


func revive_all(hp_fraction: float) -> void:
	for hero in heroes:
		if hero.is_downed():
			hero.revive(hp_fraction)
			fx.ring(hero.position, 20.0, Color(1, 1, 0.6), 0.5)


func add_zone(zone: EffectZone) -> void:
	zones.append(zone)
	ground_fx.zone(zone.position, zone.radius, zone.color, zone.duration)


func shake(strength: float) -> void:
	camera.add_shake(strength)


# --- per-frame steps -----------------------------------------------------------------------------

func _snapshot_heroes() -> void:
	var n := heroes.size()
	hero_positions.resize(n)
	_hero_targetable.resize(n)
	_hero_ranges.resize(n)
	_hero_active.resize(n)
	target_positions.clear()
	for i in n:
		var hero := heroes[i]
		hero_positions[i] = hero.position
		_hero_targetable[i] = 1 if hero.is_targetable() else 0
		_hero_ranges[i] = hero.pickup_range
		_hero_active[i] = 0 if hero.is_downed() else 1
		if not hero.is_downed():
			target_positions.append(hero.position)


## Downed heroes are revived by living teammates standing next to them.
func _update_revives(dt: float) -> void:
	for hero in heroes:
		if not hero.is_downed():
			continue
		var helped := false
		for other in heroes:
			if other != hero and not other.is_downed() \
					and other.position.distance_to(hero.position) <= Hero.REVIVE_RADIUS:
				helped = true
				break
		if helped:
			hero.add_revive_progress(dt)
		else:
			hero.revive_progress = maxf(0.0, hero.revive_progress - dt * REVIVE_DECAY)


func _check_wipe(dt: float) -> void:
	if heroes.is_empty():
		return
	var all_down := true
	for hero in heroes:
		if not hero.is_downed():
			all_down = false
			break
	if all_down and not _wiped:
		_wiped = true
		_wipe_timer = TEST_ROOM_WIPE_RESET
		Events.all_heroes_downed.emit()
		team_wiped.emit()
	elif not all_down:
		_wiped = false
	if _wiped and auto_revive_on_wipe:
		_wipe_timer -= dt
		if _wipe_timer <= 0.0:
			revive_all(0.6)
			_wiped = false


func _apply_contact_damage() -> void:
	for hero in heroes:
		if hero.is_targetable():
			var dmg := horde.contact_damage_at(hero.position, Hero.RADIUS)
			if dmg > 0.0:
				hero.take_hit(dmg)


func _apply_blasts() -> void:
	for k in horde.blast_pos.size():
		var p := horde.blast_pos[k]
		var r := horde.blast_radius[k]
		for hero in heroes:
			if hero.position.distance_to(p) <= r + Hero.RADIUS:
				hero.take_hit(horde.blast_damage[k])
		fx.disc(p, r, Color(1.0, 0.55, 0.2, 0.7), 0.25)
		fx.ring(p, r * 1.15, Color(1.0, 0.9, 0.5), 0.3)
		shake(2.5)
	horde.clear_blasts()


func _apply_projectile_hits() -> void:
	var hits := projectiles.hero_hits
	for k in range(0, hits.size(), 2):
		var index := int(hits[k])
		if index < heroes.size():
			heroes[index].take_hit(hits[k + 1])
	for k in projectiles.impacts.size():
		fx.ring(projectiles.impacts[k], projectiles.impact_radius[k], Color(0.8, 0.6, 1.0), 0.2)


func _update_zones(dt: float) -> void:
	var i := 0
	while i < zones.size():
		var zone := zones[i]
		if zone.advance(dt):
			if zone.damage > 0.0 or zone.slow_time > 0.0 or zone.stun_time > 0.0:
				damage_enemies_in_circle(zone.position, zone.radius, zone.damage, zone.knockback,
					zone.owner_slot, zone.stun_time, zone.slow_time)
			if zone.heal > 0.0:
				for hero in heroes:
					if not hero.is_downed() and hero.position.distance_to(zone.position) <= zone.radius:
						hero.heal(zone.heal)
			if zone.tick_visual == "arrows":
				for n in 4:
					var p := zone.position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * zone.radius
					fx.line(p + Vector2(-3, -14), p, Color(0.9, 0.85, 0.7), 0.08)
		if zone.is_finished():
			zones.remove_at(i)
		else:
			i += 1


func _process_kills() -> void:
	var n := horde.kill_pos.size()
	for k in n:
		var p := horde.kill_pos[k]
		var t := horde.kill_type[k]
		var killer := horde.kill_slot[k]
		if killer != HordeSim.SELF_KILL:
			pickups.spawn(p, PickupSim.Kind.XP, horde.t_xp[t])
			if _rng.randf() < HEART_DROP_CHANCE:
				pickups.spawn(p + Vector2(4, 0), PickupSim.Kind.HEART, 1)
		Events.enemy_killed.emit(p, t, killer)
	horde.clear_kill_log()


func _apply_ult_charge() -> void:
	var dealt := horde.damage_by_slot
	for hero in heroes:
		if hero.slot < dealt.size() and dealt[hero.slot] > 0.0:
			hero.add_ult_charge(dealt[hero.slot])
	dealt.fill(0.0)
	horde.damage_by_slot = dealt


func _apply_pickups() -> void:
	var c := pickups.collected
	for k in range(0, c.size(), 3):
		var hero_index := c[k]
		if c[k + 1] == PickupSim.Kind.HEART:
			if hero_index < heroes.size():
				var hero := heroes[hero_index]
				hero.heal(hero.max_hp * 0.25)
		else:
			GameState.add_xp(c[k + 2])


func _on_join_requested(device: int) -> void:
	var slot := InputRouter.free_slot()
	if slot == -1:
		return
	GameState.slots[slot].hero_id = DEFAULT_HEROES[slot]
	InputRouter.assign(slot, device)
	spawn_hero(slot)


## Pause while any player's controller is unplugged; resume once all are back.
func _on_device_changed(_slot: int) -> void:
	get_tree().paused = InputRouter.has_disconnected_player()


## Keeps the group within one screen: a hero can't move further from the
## others than the camera can show. Blocks the runner rather than dragging
## everyone else along.
func _apply_leash() -> void:
	if heroes.size() < 2:
		return
	var leash := camera.leash_size()
	for hero in heroes:
		var others := Rect2()
		var first := true
		for other in heroes:
			if other == hero:
				continue
			if first:
				others = Rect2(other.position, Vector2.ZERO)
				first = false
			else:
				others = others.expand(other.position)
		var min_p := others.end - leash
		var max_p := others.position + leash
		var clamped := Vector2(clampf(hero.position.x, min_p.x, max_p.x), clampf(hero.position.y, min_p.y, max_p.y))
		if clamped != hero.position:
			hero.position = grid.move_and_slide(hero.position, clamped - hero.position, Hero.RADIUS)


static func _cmdline_int(prefix: String, default_value: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).to_int()
	return default_value
