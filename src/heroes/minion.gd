class_name Minion
extends Node2D
## Player-owned helpers, ticked by the World:
##   SKELETON  walks to the nearest enemy and hits it, follows its owner otherwise;
##             enemies hurt it on contact (they don't chase it)
##   TURRET    stationary, shoots rivets at the nearest enemy
##   TESLA     stationary, chain lightning that jumps between nearby enemies
##             (with `grid` it only powers the Engineer's Tesla Grid links)
##   MORTAR    stationary, lobs shells at the densest pack in range (Mortar)
##   GOLEM     a big skeleton that slams everything around it (Bone Golem)
##   DECOY     stands still until it breaks or its time is up, then lays
##             `burst_zone` (the Ranger's Decoy)
## Lures (decoys, the golem) draw the horde as if they were heroes: the World
## adds them to the horde's targets. Damage is credited to the owner's slot
## (ultimate charge, lifesteal); what skeletons and tesla towers an ultimate
## summoned hit doesn't charge it.

enum Kind { SKELETON, TURRET, TESLA, MORTAR, GOLEM, DECOY }

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
## Mortars: shells fly this long, arc this high, never land closer than
## MORTAR_MIN_RANGE, and look at up to MORTAR_CANDIDATES enemies for the
## densest pack (counting neighbours within MORTAR_PACK_RADIUS).
const MORTAR_FLIGHT := 0.8
const MORTAR_ARC := 30.0
const MORTAR_MIN_RANGE := 40.0
const MORTAR_CANDIDATES := 12
const MORTAR_PACK_RADIUS := 24.0
const MORTAR_BLAST := 26.0
const MORTAR_KNOCKBACK := 120.0
const MORTAR_STUN := 0.2
## Golem: walks slower, slams in a circle (scaled with its size).
const GOLEM_SPEED := 55.0
const GOLEM_SLAM := 20.0
const GOLEM_KNOCKBACK := 100.0
const GOLEM_STUN := 0.3
const GOLEM_TINT := Color(0.85, 1.05, 0.9)

var kind: Kind = Kind.SKELETON
var owner_hero: Hero
var world: World
var max_hp := 30.0
var hp := 30.0
var damage := 8.0
var attack_interval := 0.6
var attack_range := 140.0
var lifetime := 20.0
## Summoned by an ultimate (set by World.add_minion).
var ultimate := false
## The horde goes after it as if it were a hero (decoys, the golem).
var lure := false
## Tesla Grid: the tower powers links instead of chaining on its own.
var grid := false
## The summoning ability's area multiplier (mortar blasts, golem slams).
var area := 1.0
## Drawn (and slams) this much bigger: the golem grows with every corpse.
var scale_factor := 1.0
## DECOY: laid where it stood when it breaks or runs out.
var burst_zone: EffectZone

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
var _pack := PackedInt32Array()
## Mortar shells in flight: [landing spot, seconds left].
var _shells: Array[Array] = []


static func create(p_kind: Kind, owner: Hero, at: Vector2) -> Minion:
	var m := Minion.new()
	m.kind = p_kind
	m.owner_hero = owner
	m.world = owner.world
	m.position = at
	return m


func _ready() -> void:
	if kind == Kind.SKELETON or kind == Kind.GOLEM:
		_sprite = Sprite2D.new()
		_sprite.texture = HORDE_ATLAS
		_sprite.region_enabled = true
		_sprite.region_rect = Rect2(0, SKELETON_ROW * 32, 32, 32)
		_sprite.offset = Vector2(0, -8)
		add_child(_sprite)
	_retarget_in = randf() * RETARGET_INTERVAL


func is_expired() -> bool:
	return _expired


## It lasts `seconds` more from now (a golem fed again).
func renew(seconds: float) -> void:
	lifetime = _age + seconds


func expire() -> void:
	if _expired:
		return
	_expired = true
	world.fx.disc(position + Vector2(0, -6), 6.0 * scale_factor, Color(0.7, 0.7, 0.9, 0.5), 0.25)
	if kind == Kind.DECOY and burst_zone and is_instance_valid(owner_hero):
		_decoy_burst()


func tick(dt: float) -> void:
	_age += dt
	if _age >= lifetime or hp <= 0.0 or not is_instance_valid(owner_hero):
		expire()
		return
	_attack_cd -= dt
	_retarget_in -= dt
	_hurt_cd -= dt
	_flash = maxf(0.0, _flash - dt)
	match kind:
		Kind.SKELETON, Kind.GOLEM:
			_validate_target()
			_tick_walker(dt)
		Kind.TURRET:
			_validate_target()
			_tick_turret()
		Kind.TESLA:
			_validate_target()
			_tick_tesla()
		Kind.MORTAR:
			_tick_mortar(dt)
		Kind.DECOY:
			_check_contact()
	queue_redraw()


func _validate_target() -> void:
	var horde := world.horde
	if _target >= 0 and (_target >= horde.count or horde.uid[_target] != _target_uid or horde.hp[_target] <= 0.0):
		_target = -1
	if _target == -1 and _retarget_in <= 0.0:
		_retarget_in = RETARGET_INTERVAL
		_target = horde.nearest(position, attack_range, false)
		_target_uid = horde.uid[_target] if _target >= 0 else -1


## Skeletons and the golem: walk to the target and hit it (the golem slams
## everything around it), or follow the owner.
func _tick_walker(dt: float) -> void:
	var horde := world.horde
	var golem := kind == Kind.GOLEM
	var reach := MELEE_REACH * scale_factor
	var move := Vector2.ZERO
	if _target >= 0:
		var to := horde.pos[_target] - position
		var dist := to.length()
		if dist > 0.01:
			_aim = to / dist
		if dist > reach:
			move = _aim
		elif _attack_cd <= 0.0:
			_attack_cd = attack_interval
			horde.ult_hits = ultimate
			if golem:
				_slam()
			else:
				world.hit_enemy(_target, damage, _aim * 40.0, owner_hero.slot, owner_hero)
				world.fx.slash(position + Vector2(0, -6) + _aim * 3.0, 9.0, _aim.angle(), 1.6, Color(0.9, 0.9, 0.8, 0.8), 0.1)
			horde.ult_hits = false
	else:
		var to_owner := owner_hero.position - position
		if to_owner.length() > FOLLOW_DISTANCE * scale_factor:
			move = to_owner.normalized()
	if move != Vector2.ZERO:
		var speed := GOLEM_SPEED if golem else SKELETON_SPEED
		position = world.grid.move_and_slide(position, move * speed * dt, SKELETON_RADIUS)
	_check_contact()
	var frame := int(_age * (5.0 if golem else 8.0)) % 4 if move != Vector2.ZERO else 0
	_sprite.region_rect = Rect2(frame * 32, SKELETON_ROW * 32, 32, 32)
	_sprite.flip_h = _aim.x < 0.0
	_sprite.scale = Vector2(scale_factor, scale_factor)
	var fade := clampf((lifetime - _age) / 1.5, 0.3, 1.0)
	var tint := GOLEM_TINT if golem else Color(0.85, 0.95, 1.0)
	_sprite.modulate = Color(2, 2, 2, fade) if _flash > 0.0 else Color(tint, fade)


## Enemies touching it hurt it (spaced out by its hurt i-frames).
func _check_contact() -> void:
	if _hurt_cd > 0.0:
		return
	var hit := world.horde.contact_damage_at(position, SKELETON_RADIUS * scale_factor)
	if hit > 0.0:
		hp -= hit
		_hurt_cd = HURT_IFRAMES
		_flash = 0.1
	else:
		_hurt_cd = CONTACT_CHECK_INTERVAL


## The golem's slam: everything around it, knocked back and dazed.
func _slam() -> void:
	var r := GOLEM_SLAM * scale_factor * area
	world.damage_enemies_in_circle(position, r, damage, GOLEM_KNOCKBACK, owner_hero.slot, GOLEM_STUN)
	world.fx.disc(position, r, Color(0.8, 0.95, 0.8, 0.35), 0.18)
	world.fx.ring(position, r * 1.1, Color(0.75, 1.0, 0.85), 0.25)
	world.particles.burst(position, 8, Color(0.75, 0.7, 0.6), 60.0, 0.35, 2, Vector2.UP, PI, 60.0)
	Audio.play(&"slam", -6.0, 0.8)


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
	if grid or _target < 0 or _attack_cd > 0.0:
		return
	_attack_cd = attack_interval
	var horde := world.horde
	var hit := {}
	var from := position + Vector2(0, -16)
	Audio.play(&"tesla")
	var current := _target
	horde.ult_hits = ultimate
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
	horde.ult_hits = false


## Mortars: shells land where their dashed ring said; a new one goes up at
## the densest pack in range whenever the tube is ready.
func _tick_mortar(dt: float) -> void:
	var k := 0
	while k < _shells.size():
		var shell := _shells[k]
		shell[1] = float(shell[1]) - dt
		if float(shell[1]) > 0.0:
			k += 1
			continue
		_shells.remove_at(k)
		_shell_lands(shell[0])
	if _attack_cd > 0.0:
		return
	var target := densest_pack()
	if not target.is_finite():
		_attack_cd = RETARGET_INTERVAL
		return
	_attack_cd = attack_interval
	_aim = (target - position).normalized()
	_shells.append([target, MORTAR_FLIGHT])
	var r := MORTAR_BLAST * area
	world.fx.lob(position + Vector2(0, -4), target, MORTAR_ARC, owner_hero.color.lightened(0.35), MORTAR_FLIGHT)
	world.warn_fx.telegraph(target, r, owner_hero.color, MORTAR_FLIGHT, true)  # dashed: a hero's own
	Audio.play(&"lob", -4.0, 0.8)


## Where the most enemies stand together between MORTAR_MIN_RANGE and the
## mortar's range (a few candidates are compared), or INF.
func densest_pack() -> Vector2:
	var horde := world.horde
	horde.query_circle(position, attack_range, _scratch)
	var candidates := PackedInt32Array()
	for j in _scratch:
		if horde.is_object(j) or horde.pos[j].distance_squared_to(position) < MORTAR_MIN_RANGE * MORTAR_MIN_RANGE:
			continue
		candidates.append(j)
	if candidates.is_empty():
		return Vector2.INF
	var step := maxi(1, candidates.size() / MORTAR_CANDIDATES)
	var best := Vector2.INF
	var best_count := -1
	for c in range(0, candidates.size(), step):
		var p := horde.pos[candidates[c]]
		var n := horde.query_circle(p, MORTAR_PACK_RADIUS, _pack)
		if n > best_count:
			best_count = n
			best = p
	return best


func _shell_lands(p: Vector2) -> void:
	var r := MORTAR_BLAST * area
	world.horde.ult_hits = ultimate
	world.damage_enemies_in_circle(p, r, damage, MORTAR_KNOCKBACK, owner_hero.slot, MORTAR_STUN)
	world.horde.ult_hits = false
	world.fx.disc(p, r, Color(1.0, 0.65, 0.3, 0.5), 0.2)
	world.fx.ring(p, r * 1.1, Color(1.0, 0.85, 0.55), 0.25)
	world.particles.burst(p, 10, Color(0.75, 0.65, 0.55), 100.0, 0.4, 2, Vector2.UP, PI * 1.4, 120.0)
	world.shake(1.0)
	Audio.play(&"explosion", -8.0, 1.2)


## The decoy breaks: a pop that shoves the crowd around it back, and its
## caltrops.
func _decoy_burst() -> void:
	var zone := burst_zone
	zone.position = position
	world.add_zone(zone)
	world.damage_enemies_in_circle(position, zone.radius, 0.0, 90.0, owner_hero.slot)
	world.fx.ring(position, zone.radius, Color(0.95, 0.85, 0.5), 0.3)
	world.particles.burst(position + Vector2(0, -8), 14, Color(0.95, 0.85, 0.45), 90.0, 0.6, 2, Vector2.UP, PI, 80.0)
	Audio.play(&"break")


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
			var glow := 0.6 + 0.4 * sin(_age * (24.0 if grid else 12.0))
			draw_circle(Vector2(0, -18), 3.0, Color(0.6, 0.9, 1.0, glow * fade), true, -1.0, false)
			draw_rect(Rect2(-5, -4, 10, 4), Color(owner_hero.color, fade), false, 1.0)
		Kind.MORTAR:
			# A squat base and a short fat tube tilted toward its target.
			draw_rect(Rect2(-6, -4, 12, 4), Color(0.33, 0.35, 0.38, fade))
			draw_circle(Vector2(0, -5), 3.5, Color(0.45, 0.48, 0.5, fade), true, -1.0, false)
			var tip := (Vector2(0, -5) + Vector2(_aim.x * 3.0, -1.0).normalized() * 7.0).round()
			draw_line(Vector2(0, -5), tip, Color(0.62, 0.66, 0.7, fade), 4.0)
			draw_rect(Rect2(tip - Vector2(2, 1), Vector2(4, 2)), Color(0.2, 0.2, 0.22, fade))
			draw_rect(Rect2(-6, -4, 12, 4), Color(owner_hero.color, fade), false, 1.0)
		Kind.GOLEM:
			if hp < max_hp:
				var bw := 16.0 * scale_factor
				draw_rect(Rect2(-bw * 0.5 - 1, 3, bw + 2, 3), Color(0, 0, 0, 0.7))
				draw_rect(Rect2(-bw * 0.5, 4, bw * maxf(hp, 0.0) / max_hp, 1), Color(0.55, 1.0, 0.7))
		Kind.DECOY:
			# A straw scarecrow in its owner's colours, under a target ring.
			var pulse := 0.5 + 0.5 * sin(_age * 8.0)
			draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.5))
			draw_arc(Vector2.ZERO, 10.0 + pulse * 2.0, 0.0, TAU, 20, Color(owner_hero.color, 0.5 + 0.4 * pulse), 1.0, false)
			draw_set_transform(Vector2.ZERO)
			var straw := Color(0.9, 0.78, 0.4, fade)
			var flash := Color(2, 2, 2) if _flash > 0.0 else Color.WHITE
			draw_rect(Rect2(-1, -12, 2, 12), Color(0.5, 0.35, 0.2, fade) * flash)
			draw_rect(Rect2(-5, -10, 10, 2), Color(0.5, 0.35, 0.2, fade) * flash)
			draw_rect(Rect2(-3, -9, 6, 6), Color(owner_hero.color.darkened(0.2), fade) * flash)
			draw_circle(Vector2(0, -14), 3.0, straw * flash, true, -1.0, false)
			draw_rect(Rect2(-4, -18, 8, 2), Color(0.45, 0.3, 0.15, fade) * flash)
			draw_rect(Rect2(-2, -20, 4, 2), Color(0.45, 0.3, 0.15, fade) * flash)
