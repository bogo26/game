class_name HeroMissile
extends RefCounted
## A shot an ability flies itself, a few at a time (ProjectileSim flies the
## hundreds): a thrown axe that comes back, knives orbiting their hero, a
## homing wisp, a slow ice orb. It is drawn with a sprite from the fx atlas
## and hits what's drawn (HordeSim.query_bodies): each enemy once, or again
## after `rehit` seconds, through World.hit_enemy, so crits and marks work as
## usual. The owning ability ticks it in _tick_active (so an ultimate's hits
## are flagged as the ultimate's) and calls free_sprite() when it's done.

enum Mode {
	STRAIGHT,  ## flies on until its life, pierce or a wall ends it
	RETURN,    ## flies `reach` px out (or to a wall), then back to the hero
	ORBIT,     ## circles the hero's body at `orbit_radius`
	HOMING,    ## turns toward the nearest enemy within `seek_range`
}

const FX_ATLAS := preload("res://assets/sprites/fx/fx_atlas.png")
const CELL := 16
## ORBIT: how long the knives take to spread out to their radius.
const ORBIT_SPREAD_TIME := 0.25
## HOMING: how often it looks for the nearest enemy again.
const SEEK_INTERVAL := 0.2
## RETURN: caught once it's this close to the hero.
const CATCH_DISTANCE := 8.0

var mode: Mode = Mode.STRAIGHT
var hero: Hero
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var radius := 4.0
## 0: it flies without hitting anything (the Frozen Orb only sprays shards).
var damage := 0.0
var knockback := 30.0
var life := 1.0
## Hits left before it stops; -1: it never stops for enemies.
var pierce := -1
## 0: each enemy is hit once (once each way for RETURN); else again after this.
var rehit := 0.0
## An attack's shot: its hits carry the hero's elements.
var elemental := false
## Ends on the first body it touches without hitting it: the owner blows it
## up there (Haunt's wisps).
var detonate := false
## Touches nothing for this long after it's made (a wisp rising from a corpse).
var arm_time := 0.0
var stop_at_walls := true
## Radians per second the sprite spins; 0: it points where it flies.
var spin := 0.0
var reach := 110.0
var return_speed := 260.0
var orbit_angle := 0.0
var orbit_radius := 26.0
var orbit_speed := 7.0
var seek_range := 140.0
var turn_rate := 6.0

var done := false
## Why it ended: hit something (pierce ran out), a wall, or its time.
var hit_enemy := false
var hit_wall := false
var returning := false
var travelled := 0.0
var age := 0.0
var sprite: Sprite2D
## Enemy uid -> world time it may be hit again (INF: never). Several missiles
## can share one (share_hits()): a vortex's knives cut each enemy in turn.
var _hits: Dictionary = {}
var _found := PackedInt32Array()
var _target_uid := -1
var _target_hint := -1
var _seek_in := 0.0


## A missile of `look` (a ProjectileSim.Look cell) at `at`, drawn in the
## world's entity layer.
static func create(p_hero: Hero, look: int, at: Vector2, p_mode: Mode = Mode.STRAIGHT) -> HeroMissile:
	var m := HeroMissile.new()
	m.hero = p_hero
	m.mode = p_mode
	m.pos = at
	m.sprite = Sprite2D.new()
	m.sprite.texture = FX_ATLAS
	m.sprite.region_enabled = true
	m.sprite.region_rect = Rect2((look % ProjectileSim.ATLAS_COLUMNS) * CELL, (look / ProjectileSim.ATLAS_COLUMNS) * CELL,
		CELL, CELL)
	m.sprite.position = at.round()
	p_hero.world.entities.add_child(m.sprite)
	return m


func tick(dt: float) -> void:
	if done:
		return
	var w := hero.world
	age += dt
	life -= dt
	match mode:
		Mode.STRAIGHT:
			_fly(w, dt)
		Mode.RETURN:
			if returning:
				var home := hero.body_position()
				var to := home - pos
				if to.length() <= CATCH_DISTANCE + return_speed * dt:
					pos = home
					done = true
				else:
					vel = to.normalized() * return_speed
					pos += vel * dt  # comes back over walls: it returns to the hand
			else:
				_fly(w, dt)
				if travelled >= reach or hit_wall:
					hit_wall = false
					returning = true
					_hits.clear()  # everything can be hit again on the way back
		Mode.ORBIT:
			orbit_angle += orbit_speed * dt
			var r := orbit_radius * minf(1.0, age / ORBIT_SPREAD_TIME)
			var was := pos
			pos = hero.body_position() + Vector2.from_angle(orbit_angle) * r
			vel = (pos - was) / maxf(dt, 0.0001)
		Mode.HOMING:
			_seek(w, dt)
			_fly(w, dt)
	if (damage > 0.0 or detonate) and not done and age >= arm_time:
		_hit_enemies(w)
	if life <= 0.0:
		done = true
	_draw_sprite(dt)


## The way it's flying (a unit vector), or right when it's still.
func heading() -> Vector2:
	return vel.normalized() if vel != Vector2.ZERO else Vector2.RIGHT


## Missiles given the same dictionary share their hit memory.
func share_hits(memory: Dictionary) -> void:
	_hits = memory


func free_sprite() -> void:
	if is_instance_valid(sprite):
		sprite.queue_free()
	sprite = null


func _fly(w: World, dt: float) -> void:
	var step := vel * dt
	var next := pos + step
	if stop_at_walls:
		var cell := w.grid.cell_of(next)
		if w.grid.is_shot_solid(cell.x, cell.y):
			hit_wall = true
			if mode != Mode.RETURN:
				done = true
			return
	pos = next
	travelled += step.length()


## Turns toward the nearest enemy (looked up again every SEEK_INTERVAL).
func _seek(w: World, dt: float) -> void:
	var horde := w.horde
	_seek_in -= dt
	var target := horde.index_of_uid(_target_uid, _target_hint) if _target_uid != -1 else -1
	if target != -1 and not horde.is_alive(target):
		target = -1
	if target == -1 or _seek_in <= 0.0:
		_seek_in = SEEK_INTERVAL
		target = horde.nearest(pos, seek_range, false)
		_target_uid = horde.uid[target] if target != -1 else -1
	_target_hint = target
	if target == -1:
		return
	var desired := (horde.body_center(target) - pos).angle()
	var now := vel.angle()
	var turn := clampf(angle_difference(now, desired), -turn_rate * dt, turn_rate * dt)
	vel = vel.rotated(turn)


func _hit_enemies(w: World) -> void:
	var horde := w.horde
	horde.query_bodies(pos, radius, _found)
	if detonate:
		for j in _found:
			if not horde.is_object(j):
				hit_enemy = true
				done = true
				return
		return
	var hits := 0
	var now := w.elapsed
	for j in _found:
		var id := horde.uid[j]
		if now < float(_hits.get(id, -INF)):
			continue
		_hits[id] = now + rehit if rehit > 0.0 else INF
		var push := heading() * knockback
		if mode == Mode.ORBIT:
			push = (horde.pos[j] - hero.position).normalized() * knockback  # flung outward
		w.hit_enemy(j, damage, push, hero.slot, hero)
		if elemental:
			w.elements.on_attack_hit(hero, j, damage)
		hits += 1
		if pierce >= 0:
			pierce -= 1
			if pierce < 0:
				hit_enemy = true
				done = true
				break
	if hits > 0:
		hero.on_hits(hits)


func _draw_sprite(dt: float) -> void:
	if not is_instance_valid(sprite):
		return
	sprite.position = pos.round()
	if spin != 0.0:
		sprite.rotation += spin * dt
	elif vel != Vector2.ZERO:
		sprite.rotation = vel.angle()
