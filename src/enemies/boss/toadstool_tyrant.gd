class_name ToadstoolTyrant
extends Boss
## The Toadstool Tyrant, a mini boss (see Boss for what every boss shares): a
## giant red-capped toadstool that waddles after the nearest hero and fights
## with its bulk and its spores:
##   phase 1 (100-50%): bounces (three hops in a row, each onto whoever is
##                      nearest, landing with a thump) and spore bursts (it
##                      squats and puffs a ring of spore clouds around itself)
##   phase 2 (<50%):    enraged: faster, four hops a bounce, lobs spore bombs
##                      at every hero, and sprouts sporelings (its hopping
##                      spawn) - a crowd of them as it enrages
## Every attack is announced: each hop's landing circle while it squats, the
## cloud spots before a burst, each bomb's landing circle, spawn portals.

enum Phase { ONE, TWO }
enum Action { WALK, WINDUP, SQUAT, HOP }
enum Attack { BOUNCE, BURST, LOB, SPROUT }

## 4 frames: walk0, walk1, squat (wind-up), airborne.
const SPRITE := preload("res://assets/sprites/enemies/toadstool_tyrant.png")
const BODY_RADIUS := 12.0
const SPEEDS: Array[float] = [24.0, 32.0]
const ATTACK_GAPS: Array[float] = [2.0, 1.5]
## Enraged (phase 2) below this share of HP.
const ENRAGE_AT := 0.5
const WINDUP_TIME := 0.6
## A bounce is HOPS hops, each onto the hero nearest when it squats (at most
## HOP_REACH away): the first squat lasts BOUNCE_WINDUP, the others HOP_SQUAT,
## then HOP_TIME in the air and a landing that hits HOP_RADIUS around it.
const HOPS: Array[int] = [3, 4]
const BOUNCE_WINDUP := 0.7
const HOP_SQUAT := 0.4
const HOP_TIME := 0.5
const HOP_HEIGHT := 26.0
const HOP_REACH := 120.0
const HOP_RADIUS := 32.0
const HOP_DAMAGE := 22.0
## A spore burst: a cloud under it and BURST_CLOUDS more in a ring
## BURST_RING out, each BURST_CLOUD across, hurting BURST_DAMAGE a hit for
## CLOUD_TIME. It puffs one when heroes crowd it.
const BURST_WINDUP := 0.9
const BURST_CLOUDS: Array[int] = [6, 8]
const BURST_RING := 44.0
const BURST_CLOUD := 20.0
const BURST_DAMAGE := 7.0
const CLOUD_TIME := 5.0
const CROWDED := 64.0
## Spore bombs: one at every hero, and LOB_EXTRA more around them.
const LOB_WINDUP := 0.6
const LOB_RADIUS := 24.0
const LOB_DAMAGE := 16.0
const LOB_FLIGHT := 1.0
const LOB_EXTRA := 2
## Its spawn: SPROUT_COUNT sporelings a sprout, ENRAGE_SPROUT as it enrages.
const SPROUT_COUNT := 5
const ENRAGE_SPROUT := 7
const MOUTH := Vector2(0, -30)
const CAP_COLOR := Color(0.9, 0.24, 0.2)

var phase: Phase = Phase.ONE
var action: Action = Action.WALK
var pending_attack: Attack = Attack.BOUNCE

var _attack_timer := 2.0
var _action_time := 0.0
var _hops_left := 0
var _leap_from := Vector2.ZERO
var _leap_to := Vector2.ZERO
var _leap_t := 0.0
var _burst_spots := PackedVector2Array()


func _init() -> void:
	body_type = &"toadstool_tyrant"
	display_name = "Toadstool Tyrant"


func _sprite_texture() -> Texture2D:
	return SPRITE


func is_winding_up() -> bool:
	return action == Action.WINDUP or action == Action.SQUAT


func is_airborne() -> bool:
	return action == Action.HOP


## Where the hop it's squatting for (or flying) will land.
func landing() -> Vector2:
	return _leap_to


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
		Action.SQUAT:
			_action_time -= dt
			if _action_time <= 0.0:
				action = Action.HOP
				_leap_from = p
				_leap_t = 0.0
				# Airborne: a stunned body deals no contact damage.
				world.horde.stun[_index] = HOP_TIME + 1.0
				Audio.play(&"boing")
		Action.HOP:
			_leap_t = minf(1.0, _leap_t + dt / HOP_TIME)
			p = _leap_from.lerp(_leap_to, _leap_t)
			sprite.position.y = roundf(-sin(_leap_t * PI) * HOP_HEIGHT)
			if _leap_t >= 1.0:
				_land(p)
	return p


func _frame() -> int:
	if action == Action.WINDUP or action == Action.SQUAT:
		return 2
	if action == Action.HOP:
		return 3
	return super()


func _tint() -> Color:
	return Color(1.15, 0.92, 0.9) if phase == Phase.TWO else Color.WHITE


func _update_phase() -> void:
	if phase == Phase.ONE and hp_ratio() < ENRAGE_AT:
		phase = Phase.TWO
		_announce_phase()
		_summon(&"sporeling", ENRAGE_SPROUT, 40.0)


func _begin_attack(p: Vector2, target: Vector2) -> void:
	var options: Array[Attack] = [Attack.BOUNCE, Attack.BOUNCE, Attack.BURST]
	if p.distance_to(target) <= CROWDED:
		options.append(Attack.BURST)  # someone's up close: puff them away
	if phase == Phase.TWO:
		options.append_array([Attack.LOB, Attack.LOB, Attack.SPROUT])
	wind_up(options[_rng.randi_range(0, options.size() - 1)], p, target)


## Starts `attack`'s wind-up and draws its warning.
func wind_up(attack: Attack, p: Vector2, target: Vector2) -> void:
	pending_attack = attack
	action = Action.WINDUP
	_action_time = WINDUP_TIME
	var danger := FxLayer.DANGER
	match attack:
		Attack.BOUNCE:
			_hops_left = HOPS[phase]
			if not _squat(p, target, BOUNCE_WINDUP):
				_end_action()
				return
		Attack.BURST:
			_action_time = BURST_WINDUP
			_burst_spots = _cloud_spots(p)
			for q in _burst_spots:
				world.warn_fx.telegraph(q, BURST_CLOUD + Hero.RADIUS, danger, _action_time)
		Attack.LOB:
			_action_time = LOB_WINDUP
		Attack.SPROUT:
			_summon(&"sporeling", SPROUT_COUNT, 40.0)  # they step out as the wind-up ends
	Audio.play(&"windup")


## Squats for a hop onto the hero nearest `target`'s side; false if there's nobody to hop at.
func _squat(p: Vector2, target: Vector2, seconds: float) -> bool:
	if not target.is_finite():
		return false
	action = Action.SQUAT
	_action_time = seconds
	var to := (target - p).limit_length(HOP_REACH)
	_leap_to = _spot_in_room(p + to, p)
	sprite.flip_h = to.x < 0.0
	# Until it lands, not just until it jumps.
	world.warn_fx.telegraph(_leap_to, HOP_RADIUS + Hero.RADIUS, FxLayer.DANGER, seconds + HOP_TIME)
	return true


func _execute_attack(p: Vector2) -> void:
	match pending_attack:
		Attack.BURST:
			for q in _burst_spots:
				world.add_hazard(q, BURST_CLOUD, CLOUD_TIME, BURST_DAMAGE * world.horde.damage_mult, World.SPORE_COLOR)
			world.particles.burst(p + MOUTH, 30, World.SPORE_COLOR, 110.0, 0.9, 3, Vector2.ZERO, TAU, -10.0)
			world.shake(2.0)
			Audio.play(&"spores")
		Attack.LOB:
			for q in _lob_targets():
				world.lob(p + MOUTH, q, LOB_RADIUS, LOB_DAMAGE * world.horde.damage_mult, &"spores", LOB_FLIGHT)
			Audio.play(&"lob")
		Attack.SPROUT:
			pass  # sprouted when the wind-up started
	_end_action()


## A spore burst's clouds: one under it and a ring around it, inside its room.
func _cloud_spots(p: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array([p])
	var n := BURST_CLOUDS[phase]
	var offset := _rng.randf() * TAU
	for k in n:
		var q := p + Vector2.from_angle(offset + TAU * k / n) * BURST_RING
		if world.grid.line_of_sight(p, q):
			out.append(_spot_in_room(q, p))
	return out


## Where spore bombs land: on every hero, and a few more around them.
func _lob_targets() -> PackedVector2Array:
	var spots := _hero_spots()
	var out := PackedVector2Array(spots)
	for k in LOB_EXTRA:
		if spots.is_empty():
			break
		var q := spots[_rng.randi_range(0, spots.size() - 1)] + Vector2.from_angle(_rng.randf() * TAU) \
			* _rng.randf_range(30.0, 56.0)
		out.append(_spot_in_room(q, spots[0]))
	return out


func _land(p: Vector2) -> void:
	sprite.position.y = 0.0
	world.horde.stun[_index] = 0.0
	_hit_circle(p, HOP_RADIUS, HOP_DAMAGE)
	world.fx.disc(p, HOP_RADIUS, Color(CAP_COLOR, 0.35), 0.25)
	world.fx.ring(p, HOP_RADIUS * 1.1, Color(1, 0.85, 0.8), 0.3)
	world.particles.burst(p, 10, Color(0.7, 0.62, 0.5), 90.0, 0.4, 2, Vector2.UP, PI, 120.0)
	world.shake(3.0)
	Audio.play(&"thud")
	_hops_left -= 1
	if _hops_left > 0 and _squat(p, _nearest_hero(p), HOP_SQUAT):
		return
	_end_action()


func _end_action() -> void:
	action = Action.WALK
	_attack_timer = ATTACK_GAPS[phase] * _rng.randf_range(0.8, 1.2)
