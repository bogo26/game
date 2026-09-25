class_name World
extends Node2D
## Gameplay root. Owns the level, heroes and (from milestone 3) the horde,
## projectile and pickup sims, and ticks everything in a fixed order each
## frame so there are no per-node ordering surprises:
##   input (InputRouter autoload) → heroes → leash → camera

## Loaded at runtime: preloading would create a load cycle (hero.gd types World).
const HERO_SCENE_PATH := "res://src/heroes/hero.tscn"
const DEFAULT_HEROES: Array[StringName] = [&"knight", &"ranger", &"mage", &"cleric"]
const MAX_DELTA := 1.0 / 30.0
const SPAWN_OFFSETS: Array[Vector2] = [Vector2(-12, -8), Vector2(12, -8), Vector2(-12, 8), Vector2(12, 8)]

@export var level_data: LevelData
## Test rooms let players join mid-game by pressing A / Enter.
@export var allow_drop_in := true

var grid: LevelGrid
var heroes: Array[Hero] = []
var bots: BotDriver

@onready var level: Level = $Level
@onready var entities: Node2D = $Entities
@onready var camera: SharedCamera = $Camera


func _ready() -> void:
	level.build(level_data)
	grid = level.grid
	camera.setup(grid.size_px())
	camera.snap_to(level.player_spawns[0])
	var bot_count := _cmdline_int("--bots=", 0)
	if bot_count > 0:
		BotDriver.add_bots(bot_count)
		bots = BotDriver.new(self)
	for slot in InputRouter.assigned_slots():
		if GameState.slots[slot].hero_id == &"":
			GameState.slots[slot].hero_id = DEFAULT_HEROES[slot]
		spawn_hero(slot)
	if allow_drop_in:
		InputRouter.join_requested.connect(_on_join_requested)
	Events.player_device_lost.connect(_on_device_changed)
	Events.player_device_restored.connect(_on_device_changed)


func spawn_hero(slot: int) -> Hero:
	var hero: Hero = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	hero.setup(slot, GameState.slots[slot].hero_id, self)
	var anchor := level.player_spawns[slot % level.player_spawns.size()]
	if not heroes.is_empty():
		anchor = heroes[0].position  # drop-in joins next to the team
	hero.position = grid.nearest_open(anchor + SPAWN_OFFSETS[slot])
	entities.add_child(hero)
	heroes.append(hero)
	Events.hero_spawned.emit(slot)
	return hero


func _process(delta: float) -> void:
	var dt := minf(delta, MAX_DELTA)
	var t0 := Time.get_ticks_usec()
	if bots:
		bots.tick(dt)
	for hero in heroes:
		hero.tick(dt)
	_apply_leash()
	camera.follow(_hero_points(), dt)
	PerfMonitor.record(&"heroes", Time.get_ticks_usec() - t0)


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


func _hero_points() -> Array[Vector2]:
	var points: Array[Vector2] = []
	for hero in heroes:
		points.append(hero.position)
	return points


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
