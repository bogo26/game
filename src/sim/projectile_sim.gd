class_name ProjectileSim
extends RefCounted
## All projectiles (player and enemy) as packed arrays. Player projectiles
## hit enemies through the horde's spatial hash; enemy projectiles hit heroes.
## Walls stop or bounce them; `pierce` lets one projectile hit several enemies.
## Shots fly where they're drawn, so they collide with what's drawn: enemy
## hurtboxes (the whole body, not the feet) and the middle of heroes' bodies.

const CAPACITY := 1024
const ATLAS_COLUMNS := 8

enum Team { PLAYER, ENEMY }
## Shader tint code for enemy shots (they throb; see atlas_instance.gdshader).
const HOSTILE_TINT := 6.0
## Cell indices in assets/sprites/fx/fx_atlas.png: row 0, then row 3: the
## bone archers' shard and the legendary forms' shots.
enum Look { ARROW, BOLT, ORB, SPIT, KNIFE, RIVET, SOUL, FIRE, SHARD = 24, CRESCENT, AXE, ICE_SHARD, FLAME, PRISM,
	HEAVY_ARROW, ICE_ORB }

## Optional on-hit effects applied to enemies.
enum Effect { NONE, SLOW, STUN, BURN }
## BURN sets the enemy on fire for this share of the hit per second.
const BURN_SHARE := 0.5

## Trait bits (set_traits). RICOCHET: after a hit the shot turns toward the
## nearest enemy ahead of it (Ricochet). REAP: kills it makes are logged in
## `reaped` (Haunt).
const TRAIT_RICOCHET := 1
const TRAIT_REAP := 2
const RICOCHET_RANGE := 80.0
## "Ahead": within about 100 degrees of the way the shot was flying.
const RICOCHET_AHEAD := -0.17
## A shot that turns has at least this long left to get there.
const RICOCHET_LIFE := 0.35
## Prism: a shot with splits left forks in three at a wall bounce, each fork
## with this share of its damage and a little more time.
const SPLIT_ANGLE := deg_to_rad(25.0)
const SPLIT_DAMAGE := 0.7
const SPLIT_LIFE := 0.3

var count := 0
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var life := PackedFloat32Array()
var damage := PackedFloat32Array()
var radius := PackedFloat32Array()
var knockback := PackedFloat32Array()
var pierce := PackedInt32Array()
var bounces := PackedInt32Array()
var team := PackedInt32Array()
var owner := PackedInt32Array()
var look := PackedInt32Array()
var last_hit := PackedInt32Array()     # uid of the last enemy hit (pierce)
var effect := PackedInt32Array()
var effect_time := PackedFloat32Array()
var splash := PackedFloat32Array()     # > 0: area damage on impact
var crit := PackedByteArray()          # 1: rolled a crit at spawn (glows, hits show as crits)
var elemental := PackedByteArray()     # 1: a hero's attack carrying its elements (see Elements)
var traits := PackedByteArray()        # TRAIT_* bits
var splits := PackedByteArray()        # forks left (Prism)

## Splash impacts this frame (for FX): position + radius pairs.
var impacts := PackedVector2Array()
var impact_radius := PackedFloat32Array()
var _scratch := PackedInt32Array()

## Heroes hit by enemy projectiles this frame: [hero index, damage] pairs.
var hero_hits := PackedFloat32Array()
## Enemies hit by elemental shots this frame: [enemy index, owner slot]
## pairs, and each hit's damage. The World applies the elements.
var element_hits := PackedInt32Array()
var element_hit_damage := PackedFloat32Array()
## Ricochets this frame (for FX): from / to pairs.
var ricochets := PackedVector2Array()
## Kills by REAP shots this frame: where, and whose shot (read before the next update).
var reaped := PackedVector2Array()
var reaped_owner := PackedInt32Array()
## Prism forks waiting for the end of update(): a copy of the bounced shot
## (see _fork_record()).
var _forks: Array[Array] = []


func _init() -> void:
	pos.resize(CAPACITY)
	vel.resize(CAPACITY)
	life.resize(CAPACITY)
	damage.resize(CAPACITY)
	radius.resize(CAPACITY)
	knockback.resize(CAPACITY)
	pierce.resize(CAPACITY)
	bounces.resize(CAPACITY)
	team.resize(CAPACITY)
	owner.resize(CAPACITY)
	look.resize(CAPACITY)
	last_hit.resize(CAPACITY)
	effect.resize(CAPACITY)
	effect_time.resize(CAPACITY)
	splash.resize(CAPACITY)
	crit.resize(CAPACITY)
	elemental.resize(CAPACITY)
	traits.resize(CAPACITY)
	splits.resize(CAPACITY)


## Returns the projectile index, or -1 when full.
func spawn(p: Vector2, v: Vector2, dmg: float, r: float, lifetime: float, p_team: Team,
		p_owner: int, p_look: Look, p_pierce: int = 0, kb: float = 40.0, p_bounces: int = 0) -> int:
	if count >= CAPACITY:
		return -1
	var i := count
	count += 1
	pos[i] = p
	vel[i] = v
	life[i] = lifetime
	damage[i] = dmg
	radius[i] = r
	knockback[i] = kb
	pierce[i] = p_pierce
	bounces[i] = p_bounces
	team[i] = p_team
	owner[i] = p_owner
	look[i] = p_look
	last_hit[i] = 0
	effect[i] = Effect.NONE
	effect_time[i] = 0.0
	splash[i] = 0.0
	crit[i] = 0
	elemental[i] = 0
	traits[i] = 0
	splits[i] = 0
	return i


func set_effect(i: int, p_effect: Effect, seconds: float) -> void:
	effect[i] = p_effect
	effect_time[i] = seconds


func set_splash(i: int, radius_px: float) -> void:
	splash[i] = radius_px


## Marks a projectile whose damage already includes a crit.
func set_crit(i: int) -> void:
	crit[i] = 1


## Marks a hero's attack shot: its hits get logged for the owner's elements.
func set_elemental(i: int) -> void:
	elemental[i] = 1


func set_traits(i: int, bits: int) -> void:
	traits[i] = bits


## Prism: how many times the shot may fork at a wall bounce.
func set_splits(i: int, n: int) -> void:
	splits[i] = n


func clear() -> void:
	count = 0


## Removes every enemy shot inside `area` (a Second Wind clears the screen).
func clear_enemy_shots(area: Rect2) -> void:
	var P := pos
	var V := vel
	var L := life
	var i := 0
	while i < count:
		if team[i] == Team.ENEMY and area.has_point(P[i]):
			_remove_at(i, P, V, L)
		else:
			i += 1
	pos = P
	vel = V
	life = L


## Removes every enemy shot inside a circle (the Cleric's Bastion) and
## returns where they were.
func clear_enemy_shots_in_circle(center: Vector2, radius: float) -> PackedVector2Array:
	var gone := PackedVector2Array()
	var r2 := radius * radius
	var P := pos
	var V := vel
	var L := life
	var i := 0
	while i < count:
		if team[i] == Team.ENEMY and center.distance_squared_to(P[i]) <= r2:
			gone.append(P[i])
			_remove_at(i, P, V, L)
		else:
			i += 1
	pos = P
	vel = V
	life = L
	return gone


## Enemy shots hit heroes within `hero_radius` of `hero_bodies` (the middle
## of each hero's sprite, not the feet) whose `hero_targetable` flag is set.
func update(dt: float, horde: HordeSim, grid: LevelGrid, hero_bodies: PackedVector2Array,
		hero_targetable: PackedByteArray, hero_radius: float) -> void:
	hero_hits.clear()
	element_hits.clear()
	element_hit_damage.clear()
	impacts.clear()
	impact_radius.clear()
	ricochets.clear()
	reaped.clear()
	reaped_owner.clear()
	var P := pos
	var V := vel
	var L := life
	var solid := grid.shot_solid  # chasms don't stop shots
	var gw := grid.width
	var gh := grid.height
	var inv_tile := LevelGrid.INV_TILE
	var hpos := horde.pos
	var hhp := horde.hp
	var hfall := horde.fall
	var hhidden := horde.hidden
	var htype := horde.type
	var huid := horde.uid
	var hurt_half := horde.t_hurt_half_width
	var hurt_height := horde.t_hurt_height
	var head := horde.hash.head
	var nxt := horde.hash.next
	var hcols := horde.hash.cols
	var hrows := horde.hash.rows
	var hinv := horde.hash.inv_cell
	var reach_side := horde.hurt_max_half_width
	var reach_down := horde.hurt_max_height
	var hero_count := hero_bodies.size()

	var i := 0
	while i < count:
		var p := P[i]
		var v := V[i]
		var dead := false
		var np := p + v * dt
		# Walls: bounce (reflect on the blocked axis) or die.
		var cx := int(np.x * inv_tile)
		var cy := int(np.y * inv_tile)
		if np.x < 0.0 or np.y < 0.0 or cx >= gw or cy >= gh or solid[cy * gw + cx] != 0:
			if bounces[i] > 0:
				bounces[i] -= 1
				var blocked_x := solid[int(p.y * inv_tile) * gw + cx] != 0 if cx >= 0 and cx < gw else true
				if blocked_x:
					v.x = -v.x
				else:
					v.y = -v.y
				V[i] = v
				np = p
				if splits[i] > 0:
					splits[i] -= 1
					damage[i] *= SPLIT_DAMAGE
					L[i] += SPLIT_LIFE
					_forks.append(_fork_record(i, p, v, L[i]))
			else:
				dead = true
		if not dead:
			P[i] = np
			var r := radius[i]
			if team[i] == Team.PLAYER:
				# The hash holds feet and bodies stand on them, so a body the shot
				# can touch has its feet between just above the shot and the
				# tallest body's height below it.
				var x0 := clampi(int((np.x - r - reach_side) * hinv), 0, hcols - 1)
				var x1 := clampi(int((np.x + r + reach_side) * hinv), 0, hcols - 1)
				var y0 := clampi(int((np.y - r) * hinv), 0, hrows - 1)
				var y1 := clampi(int((np.y + r + reach_down) * hinv), 0, hrows - 1)
				var r2 := r * r
				var hit_done := false
				for qy in range(y0, y1 + 1):
					if hit_done:
						break
					for qx in range(x0, x1 + 1):
						if hit_done:
							break
						var j := head[qy * hcols + qx]
						while j != -1:
							if hhp[j] > 0.0 and huid[j] != last_hit[i] and hfall[j] <= 0.0 and hhidden[j] == 0:
								# Closest point of the body box to the shot.
								var f := hpos[j]
								var t := htype[j]
								var bx := clampf(np.x, f.x - hurt_half[t], f.x + hurt_half[t])
								var by := clampf(np.y, f.y - hurt_height[t], f.y)
								var dx := np.x - bx
								var dy := np.y - by
								if dx * dx + dy * dy <= r2:
									_hit_enemy(i, j, horde, v, Vector2(bx, by))
									hhp = horde.hp  # damage() wrote to hp (copy-on-write)
									if pierce[i] < 0:
										dead = true
										hit_done = true
										break
									if traits[i] & TRAIT_RICOCHET:
										var turned := _ricochet(i, np, v, horde)
										if turned != v:
											v = turned
											V[i] = v
											L[i] = maxf(L[i], RICOCHET_LIFE)
										hit_done = true  # one hit a frame, then fly on
										break
							j = nxt[j]
			else:
				for h in hero_count:
					if hero_targetable[h] != 0:
						var rr := r + hero_radius
						if np.distance_squared_to(hero_bodies[h]) <= rr * rr:
							hero_hits.append(float(h))
							hero_hits.append(damage[i])
							dead = true
							break
		if not dead:
			var remaining := L[i] - dt
			L[i] = remaining
			dead = remaining <= 0.0
		if dead:
			_remove_at(i, P, V, L)
		else:
			i += 1
	pos = P
	vel = V
	life = L
	if not _forks.is_empty():
		_spawn_forks()


## A ricochet: the velocity toward the nearest living enemy ahead of the shot
## within RICOCHET_RANGE (not the one just hit), or `v` when there is none.
func _ricochet(i: int, p: Vector2, v: Vector2, horde: HordeSim) -> Vector2:
	var speed := v.length()
	if speed <= 0.0:
		return v
	horde.query_circle(p, RICOCHET_RANGE, _scratch)
	var heading := v / speed
	var best := Vector2.INF
	var best_d2 := INF
	for k in _scratch:
		if horde.uid[k] == last_hit[i] or horde.is_object(k):
			continue
		var to := horde.body_center(k) - p
		var d2 := to.length_squared()
		if d2 < 1.0 or d2 >= best_d2 or heading.dot(to / sqrt(d2)) < RICOCHET_AHEAD:
			continue
		best_d2 = d2
		best = to
	if not best.is_finite():
		return v
	ricochets.append(p)
	ricochets.append(p + best)
	return best.normalized() * speed


## What a fork copies from shot `i` as it bounces (removals later in the
## frame can move the shot to another index).
func _fork_record(i: int, p: Vector2, v: Vector2, remaining: float) -> Array:
	return [p, v, remaining, damage[i], radius[i], team[i], owner[i], look[i], pierce[i], knockback[i],
		bounces[i], effect[i], effect_time[i], splash[i], crit[i], elemental[i], traits[i], splits[i]]


## Prism forks queued during update(): two copies at ±SPLIT_ANGLE from the
## bounced shot, spawned after the loop (which works on copies of the
## position, velocity and life arrays).
func _spawn_forks() -> void:
	var forks := _forks
	_forks = []
	for f in forks:
		var v: Vector2 = f[1]
		for side: float in [-1.0, 1.0]:
			var k := spawn(f[0], v.rotated(SPLIT_ANGLE * side), f[3], f[4], f[2], f[5] as Team, f[6],
				f[7] as Look, f[8], f[9], f[10])
			if k < 0:
				return
			effect[k] = f[11]
			effect_time[k] = f[12]
			splash[k] = f[13]
			crit[k] = f[14]
			elemental[k] = f[15]
			traits[k] = f[16]
			splits[k] = f[17]


## `at`: where the shot touched the body (sparks and numbers appear there).
func _hit_enemy(i: int, j: int, horde: HordeSim, v: Vector2, at: Vector2) -> void:
	var kb := v.normalized() * knockback[i] if v != Vector2.ZERO else Vector2.ZERO
	var is_crit := crit[i] != 0
	var target_pos := horde.pos[j]
	if horde.damage(j, damage[i], kb, owner[i], is_crit, at) and traits[i] & TRAIT_REAP:
		reaped.append(target_pos)
		reaped_owner.append(owner[i])
	match effect[i]:
		Effect.SLOW:
			horde.apply_slow(j, effect_time[i])
		Effect.STUN:
			horde.apply_stun(j, effect_time[i])
		Effect.BURN:
			horde.ignite(j, damage[i] * BURN_SHARE, effect_time[i], owner[i])
	if elemental[i] != 0:
		element_hits.append(j)
		element_hits.append(owner[i])
		element_hit_damage.append(damage[i])
	last_hit[i] = horde.uid[j]
	pierce[i] -= 1
	var r := splash[i]
	if r > 0.0:
		var center := horde.pos[j]
		horde.query_circle(center, r, _scratch)
		var splash_damage := damage[i] * 0.6
		for k in _scratch:
			if k != j:
				horde.damage(k, splash_damage, (horde.pos[k] - center).normalized() * knockback[i] * 0.5, owner[i],
					is_crit)
		impacts.append(center)
		impact_radius.append(r)


func _remove_at(i: int, P: PackedVector2Array, V: PackedVector2Array, L: PackedFloat32Array) -> void:
	var last := count - 1
	if i != last:
		P[i] = P[last]
		V[i] = V[last]
		L[i] = L[last]
		damage[i] = damage[last]
		radius[i] = radius[last]
		knockback[i] = knockback[last]
		pierce[i] = pierce[last]
		bounces[i] = bounces[last]
		team[i] = team[last]
		owner[i] = owner[last]
		look[i] = look[last]
		last_hit[i] = last_hit[last]
		effect[i] = effect[last]
		effect_time[i] = effect_time[last]
		splash[i] = splash[last]
		crit[i] = crit[last]
		elemental[i] = elemental[last]
		traits[i] = traits[last]
		splits[i] = splits[last]
	count = last


func render(layer: InstanceLayer) -> void:
	var buf := layer.buffer
	var P := pos
	var V := vel
	var n := mini(count, layer.capacity)
	for i in n:
		var p := P[i]
		var v := V[i]
		var speed := v.length()
		var c := 1.0
		var s := 0.0
		if speed > 0.001:
			c = v.x / speed
			s = v.y / speed
		var o := i * InstanceLayer.STRIDE
		buf[o] = c
		buf[o + 1] = -s
		buf[o + 3] = roundf(p.x)
		buf[o + 4] = s
		buf[o + 5] = c
		buf[o + 7] = roundf(p.y)
		buf[o + 8] = float(look[i])
		buf[o + 9] = 0.45 if crit[i] != 0 else 0.0  # crit shots glow
		buf[o + 10] = HOSTILE_TINT if team[i] == Team.ENEMY else 0.0
	layer.buffer = buf
	layer.commit(n)
