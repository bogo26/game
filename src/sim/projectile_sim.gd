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
## Frame indices in row 0 of assets/sprites/fx/fx_atlas.png.
enum Look { ARROW, BOLT, ORB, SPIT, KNIFE, RIVET, SOUL, FIRE }

## Optional on-hit effects applied to enemies.
enum Effect { NONE, SLOW, STUN }

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


func clear() -> void:
	count = 0


## Enemy shots hit heroes within `hero_radius` of `hero_bodies` (the middle
## of each hero's sprite, not the feet) whose `hero_targetable` flag is set.
func update(dt: float, horde: HordeSim, grid: LevelGrid, hero_bodies: PackedVector2Array,
		hero_targetable: PackedByteArray, hero_radius: float) -> void:
	hero_hits.clear()
	element_hits.clear()
	element_hit_damage.clear()
	impacts.clear()
	impact_radius.clear()
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
							if hhp[j] > 0.0 and huid[j] != last_hit[i] and hfall[j] <= 0.0:
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


## `at`: where the shot touched the body (sparks and numbers appear there).
func _hit_enemy(i: int, j: int, horde: HordeSim, v: Vector2, at: Vector2) -> void:
	var kb := v.normalized() * knockback[i] if v != Vector2.ZERO else Vector2.ZERO
	var is_crit := crit[i] != 0
	horde.damage(j, damage[i], kb, owner[i], is_crit, at)
	match effect[i]:
		Effect.SLOW:
			horde.apply_slow(j, effect_time[i])
		Effect.STUN:
			horde.apply_stun(j, effect_time[i])
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
