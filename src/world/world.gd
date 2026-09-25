class_name World
extends Node2D
## Gameplay root. Owns the level, heroes and the data-oriented sims, and ticks
## everything in a fixed order each frame (no per-node _process ordering):
##   input (InputRouter autoload) → bots → heroes (+abilities) → leash
##   → flow field → spawner → horde → contact damage → projectiles
##   → kills/drops → pickups → camera → render
## Timings go to PerfMonitor (F3).

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

@export var level_data: LevelData
## Test rooms let players join mid-game by pressing A / Enter.
@export var allow_drop_in := true
## Bot players to add at start (also settable with --bots=N).
@export var bot_count := 0
@export var spawn_enemies := true

var grid: LevelGrid
var heroes: Array[Hero] = []
var bots: BotDriver
var flow := FlowField.new()
var horde := HordeSim.new()
var projectiles := ProjectileSim.new()
var pickups := PickupSim.new()
var spawner := SpawnDirector.new()

# Per-frame hero snapshots handed to the sims.
var hero_positions := PackedVector2Array()
var _hero_targetable := PackedByteArray()
var _hero_ranges := PackedFloat32Array()
var _hero_active := PackedByteArray()
var _rng := RandomNumberGenerator.new()

@onready var level: Level = $Level
@onready var entities: Node2D = $Entities
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
	spawner.setup(horde, grid, flow, level.enemy_spawn_hints)
	spawner.enabled = spawn_enemies
	spawner.set_weight(&"brute", 0.08)
	horde_layer.setup(HORDE_ATLAS, Vector2i(32, 32), Vector2(16, 24), HordeSim.CAPACITY)
	projectile_layer.setup(FX_ATLAS, Vector2i(16, 16), Vector2(8, 8), ProjectileSim.CAPACITY)
	pickup_layer.setup(FX_ATLAS, Vector2i(16, 16), Vector2(8, 11), PickupSim.CAPACITY)

	var bots_wanted := maxi(bot_count, _cmdline_int("--bots=", 0))
	if bots_wanted > 0:
		BotDriver.add_bots(bots_wanted)
		bots = BotDriver.new(self)
		bots.fire_rate = float(_cmdline_int("--bot-fire=", 0))
	for slot in InputRouter.assigned_slots():
		if GameState.slots[slot].hero_id == &"":
			GameState.slots[slot].hero_id = DEFAULT_HEROES[slot]
		spawn_hero(slot)
	if allow_drop_in:
		InputRouter.join_requested.connect(_on_join_requested)
	Events.player_device_lost.connect(_on_device_changed)
	Events.player_device_restored.connect(_on_device_changed)
	_snapshot_heroes()
	flow.compute_now(hero_positions)


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


func _process(delta: float) -> void:
	var dt := minf(delta, MAX_DELTA)
	var t_start := Time.get_ticks_usec()

	if bots:
		bots.tick(dt)
	for hero in heroes:
		hero.tick(dt)
	_apply_leash()
	_snapshot_heroes()
	var t_heroes := Time.get_ticks_usec()

	flow.tick(dt, hero_positions)
	spawner.tick(dt, camera.visible_rect(), hero_positions)
	horde.update(dt, hero_positions)
	_apply_contact_damage()
	var t_horde := Time.get_ticks_usec()

	projectiles.update(dt, horde, grid, hero_positions, _hero_targetable, Hero.RADIUS)
	_apply_projectile_hits()
	var t_projectiles := Time.get_ticks_usec()

	_process_kills()
	pickups.update(dt, hero_positions, _hero_ranges, _hero_active)
	_apply_pickups()
	camera.follow(hero_positions, dt)
	var t_sim_end := Time.get_ticks_usec()

	horde.render(horde_layer)
	projectiles.render(projectile_layer)
	pickups.render(pickup_layer)
	var t_end := Time.get_ticks_usec()

	PerfMonitor.record(&"heroes", t_heroes - t_start)
	PerfMonitor.record(&"horde", t_horde - t_heroes)
	PerfMonitor.record(&"proj", t_projectiles - t_horde)
	PerfMonitor.record(&"render", t_end - t_sim_end)
	PerfMonitor.record(&"sim", t_end - t_start)
	PerfMonitor.set_counter(&"enemies", horde.alive_count())
	PerfMonitor.set_counter(&"projectiles", projectiles.count)
	PerfMonitor.set_counter(&"gems", pickups.count)


func _snapshot_heroes() -> void:
	var n := heroes.size()
	hero_positions.resize(n)
	_hero_targetable.resize(n)
	_hero_ranges.resize(n)
	_hero_active.resize(n)
	for i in n:
		var hero := heroes[i]
		hero_positions[i] = hero.position
		_hero_targetable[i] = 1 if hero.is_targetable() else 0
		_hero_ranges[i] = hero.pickup_range
		_hero_active[i] = 1


func _apply_contact_damage() -> void:
	for hero in heroes:
		if hero.is_targetable():
			var dmg := horde.contact_damage_at(hero.position, Hero.RADIUS)
			if dmg > 0.0:
				hero.take_hit(dmg)


func _apply_projectile_hits() -> void:
	var hits := projectiles.hero_hits
	for k in range(0, hits.size(), 2):
		var index := int(hits[k])
		if index < heroes.size():
			heroes[index].take_hit(hits[k + 1])


func _process_kills() -> void:
	var n := horde.kill_pos.size()
	for k in n:
		var p := horde.kill_pos[k]
		var t := horde.kill_type[k]
		pickups.spawn(p, PickupSim.Kind.XP, horde.t_xp[t])
		if _rng.randf() < HEART_DROP_CHANCE:
			pickups.spawn(p + Vector2(4, 0), PickupSim.Kind.HEART, 1)
		Events.enemy_killed.emit(p, t, horde.kill_slot[k])
	horde.clear_kill_log()


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
