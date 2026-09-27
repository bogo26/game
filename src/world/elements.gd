class_name Elements
extends RefCounted
## Elemental attack upgrades. A hero's tier in each element (0-3) is a mod on
## its attack ability ("fire", "ice", "poison", "lightning"), taken as three
## upgrades in a row. Every enemy the attack hits (projectile or swing) goes
## through on_attack_hit():
##   Fire       I  burns                 II  hotter, longer, spreads to enemies it touches
##                                      III burning enemies explode when they die (Inferno)
##   Ice        I  chills (slows)        II  every 3rd chill freezes solid
##                                      III frozen enemies take double damage and shatter (Shatter)
##   Poison     I  stacking poison that also slows       II  more stacks, lasts longer
##                                      III poisoned enemies burst into toxic clouds (Plague)
##   Lightning  I  zaps the nearest enemy and staggers    II  chains through 3, stuns
##                                      III every 5th hit calls down a thunderbolt (Thunderstrike)
## The World calls tick() every frame: spreading fire, death effects, particles.

enum Element { FIRE, ICE, POISON, LIGHTNING }

const MOD_KEYS: Array[StringName] = [&"fire", &"ice", &"poison", &"lightning"]
const NAMES: Array[String] = ["Fire", "Ice", "Poison", "Lightning"]
const COLORS: Array[Color] = [
	Color(1.0, 0.55, 0.2), Color(0.6, 0.88, 1.0), Color(0.55, 0.95, 0.35), Color(1.0, 0.95, 0.45)]

# Fire. Burn damage per second as a share of the hit that lit it.
const BURN_SHARE: Array[float] = [0.0, 0.5, 0.8, 0.8]
const BURN_TIME: Array[float] = [0.0, 3.0, 4.0, 4.0]
## Burning enemies (tier II+) set fire to one enemy touching them per
## interval. The checks are spread evenly over the frames in between.
const SPREAD_INTERVAL := 0.4
const SPREAD_REACH := 6.0
const INFERNO_RADIUS := 38.0
## Explosion damage, as a multiple of the burn's damage per second.
const INFERNO_DAMAGE := 3.0
const INFERNO_KNOCKBACK := 110.0
# Ice.
const CHILL_TIME := 2.5
const FREEZE_HITS := 3
const FREEZE_TIME := 1.5
## Extra damage a tier III attack deals to a frozen enemy (x the hit).
const SHATTER_BONUS := 1.0
const SHATTER_RADIUS := 36.0
## Shatter nova damage (x the hit that froze it); it also chills twice.
const SHATTER_DAMAGE := 0.8
# Poison. Damage per second per stack as a share of the hit.
const POISON_SHARE := 0.25
const POISON_TIME: Array[float] = [0.0, 4.0, 6.0, 6.0]
const POISON_STACKS: Array[int] = [0, 4, 8, 8]
const PLAGUE_RADIUS := 30.0
const PLAGUE_TIME := 2.5
const MAX_CLOUDS := 10
# Lightning.
const ZAP_RANGE := 56.0
const ZAP_SHARE: Array[float] = [0.0, 0.5, 0.6, 0.6]
const ZAP_CHAIN: Array[int] = [0, 1, 3, 3]
## The "mini-bash": zapped enemies (and the one struck) are shoved and staggered.
const ZAP_PUSH := 70.0
const ZAP_STUN: Array[float] = [0.0, 0.12, 0.25, 0.25]
## Enemy hits per hero per frame that start a zap chain (wide swings hit many).
const ZAP_STARTS_PER_FRAME := 4
const STRIKE_EVERY := 5
const STRIKE_COOLDOWN := 0.3
const STRIKE_DAMAGE := 3.0
const STRIKE_STUN := 0.8
const STRIKE_CHAIN := 6
const PARTICLE_INTERVAL := 0.12
const MAX_STATUS_PARTICLES := 30
## Death effects played per frame; the rest wait (chains ripple outward).
const DEATH_FX_PER_FRAME := 6
## Lightning bolts drawn per frame (damage always applies).
const BOLTS_PER_FRAME := 24

var world: World
var horde: HordeSim
var _hits := PackedInt32Array()
var _chain := PackedInt32Array()
var _spread_budget := 0.0
var _spread_cursor := 0
var _bolts := 0
var _particles_in := 0.0
var _zap_starts: Dictionary = {}    # slot -> chain starts this frame
var _strike_count: Dictionary = {}  # slot -> hits toward the next thunderbolt
var _strike_ready_at: Dictionary = {}  # slot -> time the next bolt may fall
var _time := 0.0


func _init(p_world: World) -> void:
	world = p_world
	horde = p_world.horde


## Element tiers from the attack ability's mods, as [fire, ice, poison, lightning].
static func tiers_of(attack: Ability) -> PackedInt32Array:
	var out := PackedInt32Array()
	for key in MOD_KEYS:
		out.append(clampi(int(attack.mod(key)), 0, 3))
	return out


## One enemy hit by `hero`'s attack for `damage` (enemy index `j`, valid until
## the horde's next update). Applies every element the hero has.
func on_attack_hit(hero: Hero, j: int, damage: float) -> void:
	if j < 0 or j >= horde.count or damage <= 0.0:
		return
	var tiers := hero.elements
	var slot := hero.slot
	var ice := tiers[Element.ICE]
	if ice >= 3 and horde.is_frozen(j) and horde.hp[j] > 0.0:
		# Shatter: frozen enemies take the hit twice.
		world.hit_enemy(j, damage * SHATTER_BONUS, Vector2.ZERO, slot, hero)
		world.particles.burst(horde.body_center(j), 4, COLORS[Element.ICE], 70.0, 0.3, 1)
	var fire := tiers[Element.FIRE]
	if fire > 0:
		var flags := (HordeSim.FLAG_WILDFIRE if fire >= 2 else 0) | (HordeSim.FLAG_INFERNO if fire >= 3 else 0)
		horde.ignite(j, damage * BURN_SHARE[fire], BURN_TIME[fire], slot, flags)
	if ice > 0:
		var froze := horde.add_chill(j, CHILL_TIME, FREEZE_HITS if ice >= 2 else 0, FREEZE_TIME, damage, slot,
			HordeSim.FLAG_SHATTER if ice >= 3 else 0)
		if froze:
			world.fx.ring(horde.body_center(j), 10.0, COLORS[Element.ICE], 0.25)
			Audio.play(&"freeze")
	var poison := tiers[Element.POISON]
	if poison > 0:
		horde.add_poison(j, damage * POISON_SHARE, POISON_TIME[poison], POISON_STACKS[poison], slot,
			HordeSim.FLAG_PLAGUE if poison >= 3 else 0)
	var lightning := tiers[Element.LIGHTNING]
	if lightning > 0:
		_lightning(hero, j, damage, lightning)


## Projectile attacks: the ProjectileSim logs which enemies its elemental
## shots hit during the frame.
func process_projectile_hits(shots: ProjectileSim) -> void:
	var hits := shots.element_hits
	for k in range(0, hits.size(), 2):
		var hero := world.hero_for_slot(hits[k + 1])
		if hero:
			on_attack_hit(hero, hits[k], shots.element_hit_damage[k / 2])


func tick(dt: float) -> void:
	_time += dt
	_zap_starts.clear()
	_bolts = 0
	_spread_fire(dt)
	_play_death_fx()
	_particles_in -= dt
	if _particles_in <= 0.0:
		_particles_in = PARTICLE_INTERVAL
		_status_particles()


# --- lightning ------------------------------------------------------------------------------

func _lightning(hero: Hero, j: int, damage: float, tier: int) -> void:
	var slot := hero.slot
	_bash(j, horde.body_center(j) - hero.position, tier)
	if tier >= 3:
		var hits := int(_strike_count.get(slot, 0)) + 1
		if hits >= STRIKE_EVERY and _time >= float(_strike_ready_at.get(slot, -1.0)):
			_strike_count[slot] = 0
			_strike_ready_at[slot] = _time + STRIKE_COOLDOWN
			_thunderbolt(hero, j, damage)
			_zap_chain(hero, j, STRIKE_CHAIN, damage * ZAP_SHARE[tier], tier)
			return
		_strike_count[slot] = hits
	var starts := int(_zap_starts.get(slot, 0))
	if starts >= ZAP_STARTS_PER_FRAME:
		return  # a wide swing: only the first few hits start a chain
	_zap_starts[slot] = starts + 1
	_zap_chain(hero, j, ZAP_CHAIN[tier], damage * ZAP_SHARE[tier], tier)


## Jumps from enemy `j` to the nearest enemy not yet zapped, `chain` times.
func _zap_chain(hero: Hero, j: int, chain: int, damage: float, tier: int) -> void:
	_chain.clear()
	_chain.append(horde.uid[j])
	var at := horde.pos[j]
	var from := horde.body_center(j)
	for jump in chain:
		horde.query_circle(at, ZAP_RANGE, _hits)
		var best := -1
		var best_d := INF
		for k in _hits:
			if horde.is_object(k) or _chain.has(horde.uid[k]):
				continue
			var d := at.distance_squared_to(horde.pos[k])
			if d < best_d:
				best_d = d
				best = k
		if best == -1:
			break
		var to := horde.body_center(best)
		_bolts += 1
		if _bolts <= BOLTS_PER_FRAME:
			world.fx.bolt(from, to, COLORS[Element.LIGHTNING])
		world.hit_enemy(best, damage, (to - from).normalized() * ZAP_PUSH, hero.slot, hero)
		_bash(best, to - from, tier)
		_chain.append(horde.uid[best])
		at = horde.pos[best]
		from = to
	if _chain.size() > 1:
		Audio.play(&"zap")


## The mini-bash: a shove away from the source and a short stagger.
func _bash(j: int, direction: Vector2, tier: int) -> void:
	if direction != Vector2.ZERO:
		horde.push(j, direction.normalized() * ZAP_PUSH * 0.5, -1)
	horde.apply_stun(j, ZAP_STUN[tier])


func _thunderbolt(hero: Hero, j: int, damage: float) -> void:
	var p := horde.body_center(j)
	world.fx.bolt(p + Vector2(randf_range(-10.0, 10.0), -90.0), p, Color(1.0, 1.0, 0.85), 0.18)
	world.fx.disc(horde.pos[j], 12.0, Color(1.0, 0.95, 0.6, 0.6), 0.2)
	world.hit_enemy(j, damage * STRIKE_DAMAGE, Vector2.ZERO, hero.slot, hero)
	horde.apply_stun(j, STRIKE_STUN)
	world.particles.burst(p, 10, COLORS[Element.LIGHTNING], 110.0, 0.35, 2)
	world.shake(2.0)
	Audio.play(&"thunder")


# --- fire spreading and death effects ------------------------------------------------------------

## Wildfire: every SPREAD_INTERVAL each burning enemy sets one enemy
## touching it alight. A cursor walks the horde so each frame checks its share.
func _spread_fire(dt: float) -> void:
	var n := horde.count
	if n == 0:
		return
	_spread_budget += n * dt / SPREAD_INTERVAL
	var scan := mini(int(_spread_budget), n)
	_spread_budget -= scan
	var burning := horde.burn
	var flags := horde.status_flags
	for step in scan:
		_spread_cursor = (_spread_cursor + 1) % n
		var i := _spread_cursor
		if burning[i] <= 0.0 or not (flags[i] & HordeSim.FLAG_WILDFIRE) or horde.hp[i] <= 0.0:
			continue
		horde.query_circle(horde.pos[i], horde.t_radius[horde.type[i]] + SPREAD_REACH, _hits)
		for k in _hits:
			if k != i and burning[k] <= 0.0 and horde.can_take_status(k):
				horde.ult_hits = horde.status_ult[i] != 0  # an ultimate's fire stays the ultimate's
				horde.ignite(k, horde.burn_dps[i], BURN_TIME[2], horde.last_slot[i],
					flags[i] & (HordeSim.FLAG_WILDFIRE | HordeSim.FLAG_INFERNO))
				horde.ult_hits = false
				burning = horde.burn  # ignite() wrote to it (copy-on-write)
				break


func _play_death_fx() -> void:
	var n := mini(horde.death_fx_pos.size(), DEATH_FX_PER_FRAME)
	if n == 0:
		return
	# Take this frame's share first: the blasts below can kill more enemies
	# and log more effects, which play in later frames (chains ripple outward).
	var positions := horde.death_fx_pos.slice(0, n)
	var kinds := horde.death_fx_kind.slice(0, n)
	var powers := horde.death_fx_power.slice(0, n)
	var slots := horde.death_fx_slot.slice(0, n)
	var ults := horde.death_fx_ult.slice(0, n)
	horde.drop_death_fx(n)
	for k in n:
		# From a status an ultimate applied: the blast (or cloud) is the ultimate's.
		horde.ult_hits = ults[k] != 0
		match kinds[k]:
			HordeSim.DeathFx.INFERNO:
				_inferno(positions[k], powers[k], slots[k])
			HordeSim.DeathFx.SHATTER:
				_shatter(positions[k], powers[k], slots[k])
			HordeSim.DeathFx.PLAGUE:
				_plague(positions[k], powers[k], slots[k])
	horde.ult_hits = false


## A burning enemy died: it explodes and sets everything around it on fire.
func _inferno(p: Vector2, burn_dps: float, slot: int) -> void:
	var source := world.hero_for_slot(slot) if slot >= 0 else null
	horde.query_circle(p, INFERNO_RADIUS, _hits)
	var hits := _hits.duplicate()
	for j in hits:
		var away := horde.pos[j] - p
		var push := away.normalized() * INFERNO_KNOCKBACK if away.length_squared() > 0.01 else Vector2.ZERO
		world.hit_enemy(j, burn_dps * INFERNO_DAMAGE, push, slot, source)
		horde.ignite(j, burn_dps, BURN_TIME[3], slot, HordeSim.FLAG_WILDFIRE | HordeSim.FLAG_INFERNO)
	world.fx.disc(p + Vector2(0, -4), INFERNO_RADIUS * 0.8, Color(1.0, 0.5, 0.15, 0.55), 0.22)
	world.fx.ring(p, INFERNO_RADIUS, Color(1.0, 0.8, 0.3), 0.25)
	world.particles.burst(p + Vector2(0, -6), 12, COLORS[Element.FIRE], 120.0, 0.45, 3, Vector2.UP, PI * 1.4, -60.0)
	world.shake(1.5)
	Audio.play(&"explosion", -4.0, 1.25)


## A frozen enemy died: it shatters, hurting and chilling everything nearby
## twice (with Deep Freeze that's most of the way to frozen solid).
func _shatter(p: Vector2, power: float, slot: int) -> void:
	var source := world.hero_for_slot(slot) if slot >= 0 else null
	horde.query_circle(p, SHATTER_RADIUS, _hits)
	var hits := _hits.duplicate()
	for j in hits:
		world.hit_enemy(j, power * SHATTER_DAMAGE, Vector2.ZERO, slot, source)
		for twice in 2:
			if horde.add_chill(j, CHILL_TIME, FREEZE_HITS, FREEZE_TIME, power, slot, HordeSim.FLAG_SHATTER):
				world.fx.ring(horde.body_center(j), 10.0, COLORS[Element.ICE], 0.25)
	world.fx.ring(p, SHATTER_RADIUS, COLORS[Element.ICE], 0.3)
	world.particles.burst(p + Vector2(0, -6), 14, Color(0.85, 0.95, 1.0), 130.0, 0.4, 2, Vector2.ZERO, TAU, 60.0)
	Audio.play(&"shatter")


## A poisoned enemy died: it leaves a toxic cloud that poisons whoever walks
## through it (clouds spread the plague to their victims too).
func _plague(p: Vector2, dps_per_stack: float, slot: int) -> void:
	var clouds := 0
	for zone in world.zones:
		if zone.poison_dps > 0.0:
			clouds += 1
			if zone.position.distance_squared_to(p) < PLAGUE_RADIUS * PLAGUE_RADIUS * 0.5:
				zone.duration = zone.elapsed + PLAGUE_TIME  # top up a cloud that's already here
				return
	if clouds >= MAX_CLOUDS:
		return
	var zone := EffectZone.new()
	zone.position = p
	zone.radius = PLAGUE_RADIUS
	zone.duration = PLAGUE_TIME
	zone.interval = 0.5
	zone.poison_dps = dps_per_stack
	zone.owner_slot = slot
	zone.color = Color(COLORS[Element.POISON], 0.4)  # a haze: don't hide the fight
	world.add_zone(zone)
	Audio.play(&"plague")


## Toxic cloud tick: one poison stack on everything inside.
func poison_area(zone: EffectZone) -> void:
	horde.query_circle(zone.position, zone.radius, _hits)
	for j in _hits:
		horde.add_poison(j, zone.poison_dps, POISON_TIME[3], POISON_STACKS[3], zone.owner_slot,
			HordeSim.FLAG_PLAGUE)


## Flames, bubbles and frost sparkles on statused enemies near the screen.
func _status_particles() -> void:
	var view := world.camera.visible_rect().grow(16.0)
	var shown := 0
	for i in horde.count:
		if shown >= MAX_STATUS_PARTICLES:
			return
		if horde.status_time[i] <= 0.0 or horde.hp[i] <= 0.0 or not view.has_point(horde.pos[i]):
			continue
		var top := horde.pos[i] - Vector2(randf_range(-4.0, 4.0), horde.t_hurt_height[horde.type[i]] * randf_range(0.4, 0.9))
		if horde.burn[i] > 0.0:
			world.particles.burst(top, 1, Color(1.0, randf_range(0.45, 0.8), 0.2), 18.0, 0.4, 1, Vector2.UP, 0.8, -50.0)
			shown += 1
		elif horde.poison[i] > 0.0 and randf() < 0.6:
			world.particles.burst(top, 1, COLORS[Element.POISON], 10.0, 0.5, 1, Vector2.UP, 1.0, -20.0)
			shown += 1
		elif horde.frozen[i] > 0.0 and randf() < 0.4:
			world.particles.burst(top, 1, Color(0.9, 0.97, 1.0), 6.0, 0.35, 1)
			shown += 1
