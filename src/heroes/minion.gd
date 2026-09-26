class_name Minion
extends Node2D
## Player-owned helpers, ticked by the World:
##   SKELETON  walks to the nearest enemy and hits it, follows its owner otherwise;
##             enemies hurt it on contact (they don't chase it)
##   TURRET    stationary, shoots rivets at the nearest enemy
##   TESLA     stationary, chain lightning that jumps between nearby enemies
## Damage is credited to the owner's slot (ultimate charge, lifesteal).

enum Kind { SKELETON, TURRET, TESLA }

const HORDE_ATLAS := preload("res://assets/sprites/enemies/horde_atlas.png")
const SKELETON_ROW := 4
const RETARGET_INTERVAL := 0.4
const SKELETON_SPEED := 72.0
const SKELETON_RADIUS := 4.0
const MELEE_REACH := 13.0
const FOLLOW_DISTANCE := 28.0
const CHAIN_JUMPS := 4
const CHAIN_RANGE := 64.0
const HURT_IFRAMES := 0.5
## Skeletons check for touching enemies at this rate instead of every frame.
const CONTACT_CHECK_INTERVAL := 0.12

var kind: Kind = Kind.SKELETON
var owner_hero: Hero
var world: World
var max_hp := 30.0
var hp := 30.0
var damage := 8.0
var attack_interval := 0.6
var attack_range := 140.0
var lifetime := 20.0

var _age := 0.0
var _attack_cd := 0.0
var _retarget_in := 0.0
var _target := -1
var _target_uid := -1
var _hurt_cd := 0.0
var _flash := 0.0
var _expired := false
var _aim := Vector2.RIGHT
var _sprite: Sprite2D
var _scratch := PackedInt32Array()


static func create(p_kind: Kind, owner: Hero, at: Vector2) -> Minion:
	var m := Minion.new()
	m.kind = p_kind
	m.owner_hero = owner
	m.world = owner.world
	m.position = at
	return m


func _ready() -> void:
	if kind == Kind.SKELETON:
		_sprite = Sprite2D.new()
		_sprite.texture = HORDE_ATLAS
		_sprite.region_enabled = true
		_sprite.region_rect = Rect2(0, SKELETON_ROW * 32, 32, 32)
		_sprite.offset = Vector2(0, -8)
		add_child(_sprite)
	_retarget_in = randf() * RETARGET_INTERVAL


func is_expired() -> bool:
	return _expired


func expire() -> void:
	if _expired:
		return
	_expired = true
	world.fx.disc(position + Vector2(0, -6), 6.0, Color(0.7, 0.7, 0.9, 0.5), 0.25)


func tick(dt: float) -> void:
	_age += dt
	if _age >= lifetime or hp <= 0.0 or not is_instance_valid(owner_hero):
		expire()
		return
	_attack_cd -= dt
	_retarget_in -= dt
	_hurt_cd -= dt
	_flash = maxf(0.0, _flash - dt)
	_validate_target()
	match kind:
		Kind.SKELETON:
			_tick_skeleton(dt)
		Kind.TURRET:
			_tick_turret()
		Kind.TESLA:
			_tick_tesla()
	queue_redraw()


func _validate_target() -> void:
	var horde := world.horde
	if _target >= 0 and (_target >= horde.count or horde.uid[_target] != _target_uid or horde.hp[_target] <= 0.0):
		_target = -1
	if _target == -1 and _retarget_in <= 0.0:
		_retarget_in = RETARGET_INTERVAL
		_target = horde.nearest(position, attack_range)
		_target_uid = horde.uid[_target] if _target >= 0 else -1


func _tick_skeleton(dt: float) -> void:
	var horde := world.horde
	var move := Vector2.ZERO
	if _target >= 0:
		var to := horde.pos[_target] - position
		var dist := to.length()
		if dist > 0.01:
			_aim = to / dist
		if dist > MELEE_REACH:
			move = _aim
		elif _attack_cd <= 0.0:
			_attack_cd = attack_interval
			world.hit_enemy(_target, damage, _aim * 40.0, owner_hero.slot, owner_hero)
			world.fx.slash(position + Vector2(0, -6) + _aim * 3.0, 9.0, _aim.angle(), 1.6, Color(0.9, 0.9, 0.8, 0.8), 0.1)
	else:
		var to_owner := owner_hero.position - position
		if to_owner.length() > FOLLOW_DISTANCE:
			move = to_owner.normalized()
	if move != Vector2.ZERO:
		position = world.grid.move_and_slide(position, move * SKELETON_SPEED * dt, SKELETON_RADIUS)
	if _hurt_cd <= 0.0:
		var hit := horde.contact_damage_at(position, SKELETON_RADIUS)
		if hit > 0.0:
			hp -= hit
			_hurt_cd = HURT_IFRAMES
			_flash = 0.1
		else:
			_hurt_cd = CONTACT_CHECK_INTERVAL
	var frame := int(_age * 8.0) % 4 if move != Vector2.ZERO else 0
	_sprite.region_rect = Rect2(frame * 32, SKELETON_ROW * 32, 32, 32)
	_sprite.flip_h = _aim.x < 0.0
	var fade := clampf((lifetime - _age) / 1.5, 0.3, 1.0)
	_sprite.modulate = Color(2, 2, 2, fade) if _flash > 0.0 else Color(0.85, 0.95, 1.0, fade)


func _tick_turret() -> void:
	if _target < 0 or _attack_cd > 0.0:
		return
	_attack_cd = attack_interval
	var to := world.horde.pos[_target] - position
	_aim = to.normalized()
	Audio.play(&"shoot_rivet", -4.0)
	var crit := owner_hero.roll_crit()
	var shot := world.projectiles.spawn(position + Vector2(0, -8) + _aim * 5.0, _aim * 300.0,
		damage * (owner_hero.crit_mult if crit else 1.0), 3.0, 0.8,
		ProjectileSim.Team.PLAYER, owner_hero.slot, ProjectileSim.Look.RIVET, 0, 20.0)
	if crit and shot >= 0:
		world.projectiles.set_crit(shot)


func _tick_tesla() -> void:
	if _target < 0 or _attack_cd > 0.0:
		return
	_attack_cd = attack_interval
	var horde := world.horde
	var hit := {}
	var from := position + Vector2(0, -16)
	Audio.play(&"tesla")
	var current := _target
	for jump in CHAIN_JUMPS + 1:
		if current < 0:
			break
		hit[horde.uid[current]] = true
		var p := horde.pos[current] + Vector2(0, -6)
		_lightning(from, p)
		world.hit_enemy(current, damage, Vector2.ZERO, owner_hero.slot, owner_hero)
		horde.apply_stun(current, 0.15)
		from = p
		current = _next_chain_target(p, hit)


func _next_chain_target(p: Vector2, hit: Dictionary) -> int:
	var horde := world.horde
	horde.query_circle(p, CHAIN_RANGE, _scratch)
	var best := -1
	var best_d := INF
	for j in _scratch:
		if hit.has(horde.uid[j]):
			continue
		var d := horde.pos[j].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = j
	return best


func _lightning(a: Vector2, b: Vector2) -> void:
	# Jagged two-segment bolt.
	var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * randf_range(-6.0, 6.0)
	world.fx.line(a, mid, Color(0.6, 0.9, 1.0), 0.12)
	world.fx.line(mid, b, Color(0.9, 0.97, 1.0), 0.12)


func _draw() -> void:
	var fade := clampf((lifetime - _age) / 1.5, 0.3, 1.0)
	match kind:
		Kind.TURRET:
			draw_rect(Rect2(-5, -6, 10, 6), Color(0.35, 0.38, 0.42, fade))
			draw_rect(Rect2(-4, -10, 8, 5), Color(0.55, 0.6, 0.65, fade))
			draw_line(Vector2(0, -8), (Vector2(0, -8) + _aim * 8.0).round(), Color(0.8, 0.85, 0.9, fade), 2.0)
			draw_rect(Rect2(-5, -6, 10, 6), Color(owner_hero.color, fade), false, 1.0)
		Kind.TESLA:
			draw_rect(Rect2(-5, -4, 10, 4), Color(0.3, 0.32, 0.38, fade))
			draw_rect(Rect2(-2, -18, 4, 14), Color(0.5, 0.45, 0.35, fade))
			var glow := 0.6 + 0.4 * sin(_age * 12.0)
			draw_circle(Vector2(0, -18), 3.0, Color(0.6, 0.9, 1.0, glow * fade), true, -1.0, false)
			draw_rect(Rect2(-5, -4, 10, 4), Color(owner_hero.color, fade), false, 1.0)
