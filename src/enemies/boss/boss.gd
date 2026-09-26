class_name Boss
extends Node2D
## What every boss shares. Its body (HP, hurtbox, contact damage) is a
## HordeSim entry of its own enemy type, so every hero ability hits it like
## any enemy; the boss node moves that entry (_think(), per boss), draws the
## sprite and runs its attack patterns. While an attack winds up
## (is_winding_up()) the sprite throbs hot pink - a flash that hit flashes
## can't wash out - and each boss draws that attack's warning above the horde.
## Bosses: BossDemon (the final boss), BoneColossus (the mini boss).

signal defeated

const FLASH_SHADER := preload("res://assets/shaders/sprite_flash.gdshader")
## Boss sheets are 64x64 frames drawn with the feet (the node's position) at (32, 58).
const SPRITE_OFFSET := Vector2(0, -26)
const FRAME_SIZE := 64
const FRAMES := 4

## Each boss sets these in its _init(): its EnemyData id (the body), and the
## name on the HUD's boss bar and in the objective ("Defeat the Demon Lord!").
var body_type: StringName = &""
var display_name := "Boss"
var world: World
var uid := -1
var max_hp := 1.0

var _index := -1
var _anim := 0.0
var _add_hp_multiplier := 1.0
var _rng := RandomNumberGenerator.new()
var _dead := false

@onready var sprite: Sprite2D = $Sprite


## `add_hp_multiplier` scales the adds the boss summons.
func setup(p_world: World, spawn_position: Vector2, hp_multiplier: float, add_hp_multiplier: float) -> void:
	world = p_world
	position = spawn_position
	_add_hp_multiplier = add_hp_multiplier
	_index = world.horde.spawn(world.horde.type_index(body_type), spawn_position, hp_multiplier)
	uid = world.horde.uid[_index]
	max_hp = world.horde.hp[_index]
	_rng.randomize()


func _ready() -> void:
	sprite.texture = _sprite_texture()
	sprite.hframes = FRAMES
	sprite.offset = SPRITE_OFFSET
	var mat := ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	sprite.material = mat


func hp_ratio() -> float:
	if _index < 0 or _dead:
		return 0.0
	return clampf(world.horde.hp[_index] / max_hp, 0.0, 1.0)


func tick(dt: float) -> void:
	if _dead:
		return
	var horde := world.horde
	_index = horde.index_of_uid(uid, _index)
	if _index == -1 or horde.hp[_index] <= 0.0:
		_die()
		return
	_anim += dt
	var p := _think(horde.pos[_index], dt)
	horde.pos[_index] = p
	position = p.round()
	_update_sprite()


# --- per boss -------------------------------------------------------------------------------

## The sprite sheet: FRAMES frames of FRAME_SIZE (walk0, walk1, wind-up, action).
func _sprite_texture() -> Texture2D:
	return null


## Moves and attacks for one frame; returns the body's new position.
func _think(p: Vector2, _dt: float) -> Vector2:
	return p


## The frame to show (see _sprite_texture()).
func _frame() -> int:
	return int(_anim * 4.0) % 2


## The sprite's tint when it isn't winding up (e.g. enraged).
func _tint() -> Color:
	return Color.WHITE


## An attack is winding up: the sprite throbs hot pink.
func is_winding_up() -> bool:
	return false


# --- shared helpers -------------------------------------------------------------------------

## The living hero nearest to `p`, or Vector2.INF.
func _nearest_hero(p: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for hero in world.heroes:
		if hero.is_downed():
			continue
		var d := hero.position.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = hero.position
	return best


## Adds of type `type_id` in a ring around the boss, each through a spawn portal.
func _summon(type_id: StringName, count: int, radius: float = 44.0) -> void:
	var t := world.horde.type_index(type_id)
	var center := position
	for k in count:
		var spot := world.grid.nearest_open(center + Vector2.from_angle(TAU * k / count) * radius)
		world.spawner.queue_spawn(t, spot, _add_hp_multiplier)


## A new phase: a moment of hitstop, a shake, a ring and a roar.
func _announce_phase() -> void:
	world.hitstop(0.08)
	world.shake(5.0)
	world.fx.ring(position, 50.0, Color(1, 0.3, 0.2), 0.5)
	Audio.play(&"roar")


## A hostile shot (hot pink, like every enemy shot).
func _shoot(from: Vector2, velocity: Vector2, damage: float, look: ProjectileSim.Look) -> void:
	world.projectiles.spawn(from, velocity, damage * world.horde.damage_mult, 5.0, 4.0,
		ProjectileSim.Team.ENEMY, -1, look)


func _update_sprite() -> void:
	sprite.frame = _frame()
	var mat := sprite.material as ShaderMaterial
	if is_winding_up():
		# A hot pink throb that hit flashes can't wash out: an attack is coming.
		var pulse := 0.5 + 0.5 * sin(_anim * 30.0)
		mat.set_shader_parameter("flash_color", FxLayer.DANGER.lightened(0.35))
		mat.set_shader_parameter("flash_amount", (0.35 + 0.35 * pulse) * maxf(0.5, Settings.flash_scale()))
		sprite.modulate = Color.WHITE
		return
	var flash := world.horde.flash[_index] > 0.0
	mat.set_shader_parameter("flash_color", Color.WHITE)
	mat.set_shader_parameter("flash_amount", 0.75 * Settings.flash_scale() if flash else 0.0)
	sprite.modulate = _tint()


func _die() -> void:
	_dead = true
	world.hitstop(0.3, 0.6)
	world.shake(6.0)
	Audio.play(&"boss_death")
	for k in 6:
		world.fx.disc(position + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-30, 0)), 24.0,
			Color(1, 0.5, 0.2, 0.7), 0.5 + k * 0.1)
	world.fx.ring(position, 90.0, Color(1, 0.9, 0.5), 0.8)
	defeated.emit()
	queue_free()
