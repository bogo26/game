class_name Hero
extends Node2D
## Generic hero body: twin-stick movement and aim, the movement ability
## (a generic dash until hero abilities land in milestone 4), and rendering.
## Heroes have no _process of their own; the World ticks them in order.

enum Frame { IDLE0, IDLE1, RUN0, RUN1, RUN2, RUN3, DASH, DOWNED }

const RADIUS := 5.0
const HIT_IFRAMES := 0.5
const SPRITE_FEET_OFFSET := Vector2(0, -6)
const RETICLE_DISTANCE := 22.0
const ACCELERATION := 14.0

# Generic attack (replaced by per-hero abilities in milestone 4).
const ATTACK_INTERVAL := 0.16
const ATTACK_DAMAGE := 6.0
const ATTACK_SPEED := 260.0

# Generic dash (replaced by per-hero movement abilities in milestone 4).
const DASH_DISTANCE := 56.0
const DASH_DURATION := 0.14
const DASH_COOLDOWN := 1.1
const DASH_IFRAMES := 0.2

var slot := 0
var hero_id: StringName = &"knight"
var color := Color.WHITE
var input: PlayerInput
var world: World

var move_speed := 88.0
var velocity := Vector2.ZERO
var aim_dir := Vector2.RIGHT
var invulnerable_time := 0.0

var max_hp := 100.0
var hp := 100.0
## XP gems within this distance home in on the hero.
var pickup_range := 28.0
## Ignores all damage (stress test, debug).
var god_mode := false
var _hurt_flash := 0.0

var dash_time_left := 0.0
var dash_cooldown_left := 0.0
var _dash_velocity := Vector2.ZERO
var _anim_time := 0.0
var _attack_cooldown := 0.0

@onready var sprite: Sprite2D = $Sprite


func setup(p_slot: int, p_hero_id: StringName, p_world: World) -> void:
	slot = p_slot
	hero_id = p_hero_id
	world = p_world
	input = InputRouter.get_player(slot)
	color = GameState.player_color(slot)


func _ready() -> void:
	sprite.texture = load("res://assets/sprites/heroes/%s.png" % hero_id)
	sprite.hframes = Frame.size()
	sprite.position = SPRITE_FEET_OFFSET


func is_dashing() -> bool:
	return dash_time_left > 0.0


## Whether enemies and enemy projectiles can currently hurt this hero.
func is_targetable() -> bool:
	return invulnerable_time <= 0.0 and not god_mode


## Applies a hit; returns true if damage was taken.
func take_hit(amount: float) -> bool:
	if not is_targetable() or amount <= 0.0:
		return false
	# Milestone 3: heroes can't go down yet (downed/revive lands in milestone 4).
	hp = maxf(1.0, hp - amount)
	invulnerable_time = HIT_IFRAMES
	_hurt_flash = 0.12
	Events.hero_damaged.emit(slot, amount)
	input.rumble(0.4, 0.6, 0.12)
	return true


func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)


func tick(delta: float) -> void:
	_update_aim()
	if dash_time_left > 0.0:
		dash_time_left -= delta
		position = world.grid.move_and_slide(position, _dash_velocity * delta, RADIUS)
	else:
		var target_velocity := input.move * move_speed
		velocity = velocity.lerp(target_velocity, 1.0 - exp(-ACCELERATION * delta))
		position = world.grid.move_and_slide(position, velocity * delta, RADIUS)
		if input.just_pressed(PlayerInput.Action.MOVEMENT) and dash_cooldown_left <= 0.0:
			_start_dash()
	_attack_cooldown -= delta
	if input.is_down(PlayerInput.Action.ATTACK) and _attack_cooldown <= 0.0:
		_attack_cooldown = ATTACK_INTERVAL
		world.projectiles.spawn(position + SPRITE_FEET_OFFSET, aim_dir * ATTACK_SPEED, ATTACK_DAMAGE, 3.0,
			1.2, ProjectileSim.Team.PLAYER, slot, ProjectileSim.Look.ARROW, 0, 40.0)
	dash_cooldown_left = maxf(0.0, dash_cooldown_left - delta)
	invulnerable_time = maxf(0.0, invulnerable_time - delta)
	_update_visuals(delta)


func _update_aim() -> void:
	if input.uses_mouse:
		var to_mouse := get_global_mouse_position() - (global_position + SPRITE_FEET_OFFSET)
		if to_mouse.length_squared() > 4.0:
			aim_dir = to_mouse.normalized()
	else:
		aim_dir = input.aim


func _start_dash() -> void:
	var dir := input.move.normalized() if input.move != Vector2.ZERO else aim_dir
	_dash_velocity = dir * (DASH_DISTANCE / DASH_DURATION)
	dash_time_left = DASH_DURATION
	dash_cooldown_left = DASH_COOLDOWN
	invulnerable_time = maxf(invulnerable_time, DASH_IFRAMES)
	velocity = dir * move_speed


func _update_visuals(delta: float) -> void:
	_anim_time += delta
	var frame: int = Frame.IDLE0
	if is_dashing():
		frame = Frame.DASH
	elif velocity.length_squared() > 100.0:
		frame = Frame.RUN0 + int(_anim_time * 10.0) % 4
	else:
		frame = Frame.IDLE0 + int(_anim_time * 2.0) % 2
	sprite.frame = frame
	if absf(aim_dir.x) > 0.05:
		sprite.flip_h = aim_dir.x < 0.0
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	if _hurt_flash > 0.0:
		sprite.modulate = Color(2.0, 0.6, 0.6)
	elif is_dashing():
		sprite.modulate = Color(1.6, 1.6, 1.6)
	elif invulnerable_time > 0.0:
		sprite.modulate = Color(1, 1, 1, 0.55 if int(invulnerable_time * 20.0) % 2 == 0 else 1.0)
	else:
		sprite.modulate = Color.WHITE
	queue_redraw()


func _draw() -> void:
	# Player-colour ring under the feet.
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.35))
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, color, 1.0)
	draw_set_transform(Vector2.ZERO)
	# Aim reticle.
	var reticle := (SPRITE_FEET_OFFSET + aim_dir * RETICLE_DISTANCE).round()
	draw_rect(Rect2(reticle - Vector2(1, 1), Vector2(3, 3)), color)
	draw_rect(Rect2(reticle, Vector2(1, 1)), Color.WHITE)
