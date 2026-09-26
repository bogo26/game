class_name BoneColossus
extends Boss
## The Bone Colossus, the mini boss that guards the Ossuary halfway through
## the run (see Boss for what every boss shares). A lumbering heap of bones
## with a club that fights up close and from below:
##   phase 1 (100-50%): walks at the nearest hero; club sweeps (a wide wedge
##                      in front of it, only when someone is in reach) and
##                      grave spikes (bone spikes burst under every hero)
##   phase 2 (<50%):    enraged: faster, more spikes around each hero, and it
##                      leaps onto the hero furthest away (bone shards burst
##                      from the landing) and raises the dead (swarmers)
## Every attack is announced during its wind-up (it glows and growls), drawn
## above the horde: the sweep's exact wedge, a filling circle wherever spikes
## will burst, the landing circle of a leap, and spawn portals for the dead.

enum Phase { ONE, TWO }
enum Action { WALK, WINDUP, LEAP }
enum Attack { SWEEP, SPIKES, LEAP, RAISE }

## 4 frames: walk0, walk1, windup (club raised), leap.
const SPRITE := preload("res://assets/sprites/enemies/bone_colossus.png")
const BODY_RADIUS := 12.0
const SPEEDS: Array[float] = [20.0, 30.0]
const ATTACK_GAPS: Array[float] = [2.2, 1.6]
## Enraged (phase 2) below this share of HP.
const ENRAGE_AT := 0.5
const WINDUP_TIME := 0.6
## The club: a wedge SWEEP_ARC radians wide in front of it.
const SWEEP_RADIUS := 58.0
const SWEEP_ARC := 2.6
const SWEEP_DAMAGE := 24.0
const SWEEP_WINDUP := 0.8
## Grave spikes: a circle under every hero, and EXTRA_SPIKES more around
## each one when enraged.
const SPIKE_RADIUS := 22.0
const SPIKE_DAMAGE := 20.0
const SPIKE_WINDUP := 1.0
const EXTRA_SPIKES := 2
const LEAP_RADIUS := 44.0
const LEAP_DAMAGE := 26.0
const LEAP_WINDUP := 0.8
## Seconds in the air, and how high the sprite hops.
const LEAP_TIME := 0.45
const LEAP_HEIGHT := 22.0
const SHARD_COUNT := 12
const SHARD_DAMAGE := 10.0
const SHARD_SPEED := 90.0
const RAISE_COUNT := 6
const BONE_COLOR := Color(0.9, 0.86, 0.72)

var phase: Phase = Phase.ONE
var action: Action = Action.WALK
var pending_attack: Attack = Attack.SWEEP

var _attack_timer := 2.0
var _action_time := 0.0
var _sweep_dir := Vector2.DOWN
var _spike_spots := PackedVector2Array()
var _leap_from := Vector2.ZERO
var _leap_to := Vector2.ZERO
var _leap_t := 0.0


func _init() -> void:
	body_type = &"bone_colossus"
	display_name = "Bone Colossus"


func _sprite_texture() -> Texture2D:
	return SPRITE


func is_winding_up() -> bool:
	return action == Action.WINDUP


func is_airborne() -> bool:
	return action == Action.LEAP


func _think(p: Vector2, dt: float) -> Vector2:
	_update_phase()
	var target := _nearest_hero(p)
	match action:
		Action.WALK:
			if target.is_finite():
				var to := target - p
				if to.length() > 20.0:
					p = world.grid.move_and_slide(p, to.normalized() * SPEEDS[phase] * dt, BODY_RADIUS)
				sprite.flip_h = to.x < 0.0
			_attack_timer -= dt
			if _attack_timer <= 0.0 and target.is_finite():
				_begin_attack(p, target)
		Action.WINDUP:
			_action_time -= dt
			if _action_time <= 0.0:
				_execute_attack(p)
		Action.LEAP:
			_leap_t = minf(1.0, _leap_t + dt / LEAP_TIME)
			p = _leap_from.lerp(_leap_to, _leap_t)
			sprite.position.y = roundf(-sin(_leap_t * PI) * LEAP_HEIGHT)
			if _leap_t >= 1.0:
				_land(p)
	return p


func _frame() -> int:
	if action == Action.WINDUP:
		return 2
	if action == Action.LEAP:
		return 3
	return super()


func _tint() -> Color:
	return Color(1.15, 0.95, 0.8) if phase == Phase.TWO else Color.WHITE


func _update_phase() -> void:
	if phase == Phase.ONE and hp_ratio() < ENRAGE_AT:
		phase = Phase.TWO
		_announce_phase()
		_summon(&"swarmer", RAISE_COUNT + 2)


func _begin_attack(p: Vector2, target: Vector2) -> void:
	var options: Array[Attack] = [Attack.SPIKES]
	if p.distance_to(target) <= SWEEP_RADIUS + Hero.RADIUS + 12.0:
		options.append_array([Attack.SWEEP, Attack.SWEEP])  # someone's in reach of the club
	if phase == Phase.TWO:
		options.append_array([Attack.LEAP, Attack.LEAP, Attack.RAISE])
	wind_up(options[_rng.randi_range(0, options.size() - 1)], p, target)


## Starts `attack`'s wind-up and draws its warning.
func wind_up(attack: Attack, p: Vector2, target: Vector2) -> void:
	pending_attack = attack
	action = Action.WINDUP
	_action_time = WINDUP_TIME
	var warn := world.warn_fx
	var danger := FxLayer.DANGER
	match attack:
		Attack.SWEEP:
			_action_time = SWEEP_WINDUP
			_sweep_dir = (target - p).normalized() if target.is_finite() and target != p else Vector2.DOWN
			sprite.flip_h = _sweep_dir.x < 0.0
			warn.warn_arc(p, SWEEP_RADIUS, _sweep_dir.angle(), SWEEP_ARC, danger, _action_time)
		Attack.SPIKES:
			_action_time = SPIKE_WINDUP
			_spike_spots = _spike_targets()
			for q in _spike_spots:
				warn.telegraph(q, SPIKE_RADIUS, danger, _action_time)
		Attack.LEAP:
			_action_time = LEAP_WINDUP
			_leap_from = p
			_leap_to = world.grid.nearest_open(_furthest_hero(p, target))
			# Until it lands, not just until it jumps.
			warn.telegraph(_leap_to, LEAP_RADIUS, danger, _action_time + LEAP_TIME)
		Attack.RAISE:
			_summon(&"swarmer", RAISE_COUNT)  # the dead step out as the wind-up ends
	Audio.play(&"windup")


func _execute_attack(p: Vector2) -> void:
	match pending_attack:
		Attack.SWEEP:
			for hero in world.heroes:
				if in_sweep(p, hero.position) and world.grid.line_of_sight(p, hero.position):
					hero.take_hit(SWEEP_DAMAGE * world.horde.damage_mult)
			world.fx.slash(p + Vector2(0, -6), SWEEP_RADIUS, _sweep_dir.angle(), SWEEP_ARC, BONE_COLOR, 0.2)
			world.shake(3.0)
			Audio.play(&"slam")
		Attack.SPIKES:
			var hit := {}
			for q in _spike_spots:
				for hero in world.heroes:
					if not hit.has(hero.slot) and hero.position.distance_to(q) <= SPIKE_RADIUS + Hero.RADIUS:
						hit[hero.slot] = true
						hero.take_hit(SPIKE_DAMAGE * world.horde.damage_mult)
				for k in 5:  # a crown of bone spikes
					var base := q + Vector2.from_angle(TAU * k / 5.0 + 0.3) * SPIKE_RADIUS * 0.5
					world.fx.line(base, base + Vector2(0, -12), BONE_COLOR, 0.3)
				world.fx.disc(q, SPIKE_RADIUS, Color(BONE_COLOR, 0.45), 0.25)
			world.shake(2.5)
			Audio.play(&"spikes")
		Attack.LEAP:
			action = Action.LEAP
			_leap_t = 0.0
			# Airborne: a stunned body deals no contact damage (the horde never
			# ticks a boss's stun, and nothing else can stun a boss).
			world.horde.stun[_index] = LEAP_TIME + 1.0
			return
		Attack.RAISE:
			pass  # raised when the wind-up started
	_end_action()


## Is `q` inside the club's wedge (sweeping from `p` along the locked aim)?
func in_sweep(p: Vector2, q: Vector2) -> bool:
	var to := q - p
	if to.length() > SWEEP_RADIUS + Hero.RADIUS:
		return false
	return to.length() < BODY_RADIUS or absf(_sweep_dir.angle_to(to)) <= SWEEP_ARC * 0.5


## Where grave spikes burst: under every living hero, and when enraged a few
## more spots around each one (never through a wall into another room).
func _spike_targets() -> PackedVector2Array:
	var out := PackedVector2Array()
	for hero in world.heroes:
		if hero.is_downed():
			continue
		out.append(hero.position)
		if phase != Phase.TWO:
			continue
		var room := world.level.room_at_position(hero.position)
		for k in EXTRA_SPIKES:
			var offset := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(36.0, 60.0)
			var q := world.grid.nearest_open(hero.position + offset)
			if world.level.room_at_position(q) == room:
				out.append(q)
	return out


## The living hero furthest from `p` (it leaps onto whoever keeps away), or `fallback`.
func _furthest_hero(p: Vector2, fallback: Vector2) -> Vector2:
	var best := fallback
	var best_d := -1.0
	for hero in world.heroes:
		if hero.is_downed():
			continue
		var d := hero.position.distance_squared_to(p)
		if d > best_d:
			best_d = d
			best = hero.position
	return best


func _land(p: Vector2) -> void:
	sprite.position.y = 0.0
	world.horde.stun[_index] = 0.0
	for hero in world.heroes:
		if hero.position.distance_to(p) <= LEAP_RADIUS + Hero.RADIUS and world.grid.line_of_sight(p, hero.position):
			hero.take_hit(LEAP_DAMAGE * world.horde.damage_mult)
	world.fx.disc(p, LEAP_RADIUS, Color(BONE_COLOR, 0.5), 0.3)
	world.fx.ring(p, LEAP_RADIUS * 1.1, Color(1, 0.95, 0.8), 0.35)
	var offset := _rng.randf() * TAU
	for k in SHARD_COUNT:
		_shoot(p + Vector2(0, -10), Vector2.from_angle(offset + TAU * k / SHARD_COUNT) * SHARD_SPEED,
			SHARD_DAMAGE, ProjectileSim.Look.SPIT)
	world.shake(5.0)
	Audio.play(&"slam")
	_end_action()


func _end_action() -> void:
	action = Action.WALK
	_attack_timer = ATTACK_GAPS[phase] * _rng.randf_range(0.8, 1.2)
