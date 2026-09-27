class_name MireSerpent
extends Boss
## The Mire Serpent, a mini boss (see Boss for what every boss shares): a
## great serpent in the flooded cistern that hides in the murk and strikes
## from below. It dives out of reach (the HUD says SUBMERGED: nothing can hit
## it) and hunts the nearest hero as a fin and a wake - slower than a hero
## walking, faster than one wading - then stops, and bursts up where the
## circle fills. Surfaced, it spits fans of water at the nearest hero and
## lunges its head down a band at anyone close, then dives again.
##   phase 2 (<50%): faster hunts that burst up twice in a row, wider fans,
##                   and eels (its brood) around every burst - a crowd of
##                   them as it enrages
## Every attack is announced: the burst's circle, the fan's aim lines (locked
## when the wind-up starts), the lunge's band, spawn portals.

enum Phase { ONE, TWO }
enum Action { SURFACED, WINDUP, DIVE, HUNT, RISE }
enum Attack { SPIT, LUNGE }

## 4 frames: sway0, sway1, wind-up (reared back), strike.
const SPRITE := preload("res://assets/sprites/enemies/mire_serpent.png")
## Its fin cutting through the murk while it's under: 2 frames, the surface
## (the fin's base) FIN_BASE px above a frame's bottom.
const FIN := preload("res://assets/sprites/enemies/mire_serpent_fin.png")
const FIN_BASE := 4.0
const BODY_RADIUS := 12.0
## Enraged (phase 2) below this share of HP.
const ENRAGE_AT := 0.5
## Surfaced for SURFACE_TIME, attacking every ATTACK_GAPS; then it dives
## (DIVE_TIME: still in reach while it sinks), hunts for HUNT_TIME at
## HUNT_SPEEDS and rises: the circle fills for RISE_TIME and it bursts up,
## hitting RISE_RADIUS around it.
const SURFACE_TIME: Array[float] = [5.0, 3.6]
const ATTACK_GAPS: Array[float] = [1.5, 1.1]
const FIRST_ATTACK := 0.8
const DIVE_TIME := 0.45
const HUNT_TIME: Array[float] = [2.4, 1.8]
const HUNT_SPEEDS: Array[float] = [62.0, 74.0]
const RISE_TIME := 0.7
const RISE_RADIUS := 32.0
const RISE_DAMAGE := 24.0
## Bursts a dive; between two, it stays up BREATH seconds, then hunts QUICK_HUNT.
const BURSTS: Array[int] = [1, 2]
const BREATH := 0.6
const QUICK_HUNT := 1.0
## Enraged, BROOD eels come up with every burst, ENRAGE_BROOD as it enrages.
const BROOD := 2
const ENRAGE_BROOD := 5
## Spit: FAN_SHOTS water shots spread over +-FAN_SPREAD at the nearest hero.
const SPIT_WINDUP := 0.6
const FAN_SHOTS: Array[int] = [3, 5]
const FAN_SPREAD := 0.35
const SPIT_SPEED := 125.0
const SPIT_DAMAGE := 12.0
## Lunge: its head strikes down a band LUNGE_LENGTH long, hitting heroes
## whose feet are within LUNGE_HALF of its middle.
const LUNGE_WINDUP := 0.55
const LUNGE_LENGTH := 84.0
const LUNGE_HALF := 12.0
const LUNGE_DAMAGE := 26.0
const STRIKE_TIME := 0.3
## Its mouth, where shots leave (above the feet).
const MOUTH := Vector2(0, -38)
const WAKE_EVERY := 0.18
const SPRAY := Color(0.7, 0.9, 0.95)
const MURK := Color(0.3, 0.55, 0.45)

var phase: Phase = Phase.ONE
var action: Action = Action.SURFACED
var pending_attack: Attack = Attack.SPIT

var _attack_timer := 1.2
var _surface_left := 3.0
var _action_time := 0.0
var _bursts_left := 0
var _quick := false
var _prey := -1
var _aim := Vector2.DOWN
var _wake := 0.0
var _strike := 0.0
var _fin: Sprite2D


func _init() -> void:
	body_type = &"mire_serpent"
	display_name = "Mire Serpent"


func _ready() -> void:
	super()
	_fin = Sprite2D.new()
	_fin.texture = FIN
	_fin.hframes = 2
	_fin.offset = Vector2(0, FIN_BASE - FIN.get_height() * 0.5)
	_fin.visible = false
	add_child(_fin)


func _sprite_texture() -> Texture2D:
	return SPRITE


func is_winding_up() -> bool:
	return action == Action.WINDUP


func is_submerged() -> bool:
	return action == Action.HUNT or action == Action.RISE


func status_text() -> String:
	return "SUBMERGED" if is_submerged() else ""


func _think(p: Vector2, dt: float) -> Vector2:
	_update_phase()
	_strike = maxf(0.0, _strike - dt)
	match action:
		Action.SURFACED:
			var target := _nearest_hero(p)
			if target.is_finite() and _strike <= 0.0:
				sprite.flip_h = target.x < p.x
			_surface_left -= dt
			_attack_timer -= dt
			if _surface_left <= 0.0:
				dive(_bursts_left > 0)
			elif _attack_timer <= 0.0 and target.is_finite():
				_begin_attack(p, target)
		Action.WINDUP:
			_action_time -= dt
			if _action_time <= 0.0:
				_execute_attack(p)
		Action.DIVE:
			_action_time -= dt
			sprite.position.y = roundf((1.0 - _action_time / DIVE_TIME) * 18.0)
			if _action_time <= 0.0:
				_hunt()
		Action.HUNT:
			var prey := _prey_position(p)
			if prey.is_finite():
				var to := prey - p
				var step := minf(HUNT_SPEEDS[phase] * dt, to.length())
				if step > 0.01:
					p = world.grid.move_and_slide(p, to.normalized() * step, BODY_RADIUS)
					_fin.flip_h = to.x < 0.0
			_leave_wake(p, dt)
			_action_time -= dt
			if _action_time <= 0.0:
				_rise(p)
		Action.RISE:
			_leave_wake(p, dt)
			_action_time -= dt
			if _action_time <= 0.0:
				_burst_up(p)
	_fin.visible = is_submerged()
	_fin.frame = int(_anim * 6.0) % 2
	sprite.visible = not _fin.visible
	return p


func _frame() -> int:
	if action == Action.WINDUP or action == Action.DIVE:
		return 2
	if _strike > 0.0:
		return 3
	return super()


func _tint() -> Color:
	var tint := Color(1.1, 1.0, 0.9) if phase == Phase.TWO else Color.WHITE
	if action == Action.DIVE:
		tint.a = clampf(_action_time / DIVE_TIME, 0.0, 1.0)  # sinking out of sight
	return tint


func _update_phase() -> void:
	if phase == Phase.ONE and hp_ratio() < ENRAGE_AT:
		phase = Phase.TWO
		_announce_phase()
		_summon(&"eel", ENRAGE_BROOD, 44.0)


func _begin_attack(p: Vector2, target: Vector2) -> void:
	var options: Array[Attack] = [Attack.SPIT]
	if p.distance_to(target) <= LUNGE_LENGTH + Hero.RADIUS:
		options.append_array([Attack.LUNGE, Attack.LUNGE])  # someone's in reach of its jaws
	wind_up(options[_rng.randi_range(0, options.size() - 1)], p, target)


## Starts `attack`'s wind-up (surfaced) and draws its warning.
func wind_up(attack: Attack, p: Vector2, target: Vector2) -> void:
	pending_attack = attack
	action = Action.WINDUP
	var danger := FxLayer.DANGER
	match attack:
		Attack.SPIT:
			_action_time = SPIT_WINDUP
			_aim = _aim_at(p, target)
			var n := FAN_SHOTS[phase]
			for k in n:
				var d := _aim.rotated(_fan_angle(k, n))
				world.warn_fx.warn_line(p + MOUTH + d * 10.0, p + MOUTH + d * 90.0, danger, _action_time, 1.0)
		Attack.LUNGE:
			_action_time = LUNGE_WINDUP
			_aim = (target - p).normalized() if target.is_finite() and target != p else Vector2.DOWN
			world.warn_fx.warn_band(p, lunge_end(p), (LUNGE_HALF + Hero.RADIUS) * 2.0, danger, _action_time)
	sprite.flip_h = _aim.x < 0.0
	Audio.play(&"windup")


func _execute_attack(p: Vector2) -> void:
	match pending_attack:
		Attack.SPIT:
			var n := FAN_SHOTS[phase]
			for k in n:
				_shoot(p + MOUTH, _aim.rotated(_fan_angle(k, n)) * SPIT_SPEED, SPIT_DAMAGE, ProjectileSim.Look.SPIT)
			Audio.play(&"spit")
		Attack.LUNGE:
			var end := lunge_end(p)
			_hit_band(p, end, LUNGE_HALF, LUNGE_DAMAGE)
			world.fx.beam(p + Vector2(0, -8), end + Vector2(0, -8), 10.0, MURK, 0.18)
			world.particles.burst(end, 8, SPRAY, 70.0, 0.35, 2)
			world.shake(2.0)
			_strike = STRIKE_TIME
			Audio.play(&"bite")
	action = Action.SURFACED
	_attack_timer = ATTACK_GAPS[phase] * _rng.randf_range(0.8, 1.2)


## Where a lunge from `p` along the locked aim ends (walls stop it).
func lunge_end(p: Vector2) -> Vector2:
	return world.grid.shot_reach(p, p + _aim * LUNGE_LENGTH)


## Sinks into the murk; `quick`: the second burst of an enraged dive.
func dive(quick: bool = false) -> void:
	action = Action.DIVE
	_action_time = DIVE_TIME
	_quick = quick
	if not quick:
		_bursts_left = BURSTS[phase]
	world.particles.burst(position - Vector2(0, 4), 14, SPRAY, 80.0, 0.5, 2, Vector2.UP, PI, 160.0)
	world.fx.ring(position, 22.0, SPRAY, 0.4)
	Audio.play(&"splash")


func _hunt() -> void:
	action = Action.HUNT
	_action_time = QUICK_HUNT if _quick else HUNT_TIME[phase]
	sprite.position.y = 0.0
	_set_hidden(true)
	_prey = _nearest_slot(position)


func _rise(p: Vector2) -> void:
	action = Action.RISE
	_action_time = RISE_TIME
	world.warn_fx.telegraph(p, RISE_RADIUS + Hero.RADIUS, FxLayer.DANGER, RISE_TIME)
	Audio.play(&"bubbles")


func _burst_up(p: Vector2) -> void:
	_set_hidden(false)
	_hit_circle(p, RISE_RADIUS, RISE_DAMAGE)
	world.fx.disc(p, RISE_RADIUS, Color(SPRAY, 0.45), 0.3)
	world.fx.ring(p, RISE_RADIUS * 1.15, SPRAY, 0.35)
	world.particles.burst(p - Vector2(0, 6), 26, SPRAY, 140.0, 0.6, 2, Vector2.UP, PI * 0.9, 220.0)
	world.shake(4.0)
	Audio.play(&"splash")
	_strike = STRIKE_TIME
	if phase == Phase.TWO:
		_summon(&"eel", BROOD, 30.0)
	_bursts_left -= 1
	action = Action.SURFACED
	if _bursts_left > 0:
		_surface_left = BREATH  # enraged: under again at once for another burst
		_attack_timer = BREATH + 1.0
	else:
		_surface_left = SURFACE_TIME[phase]
		_attack_timer = FIRST_ATTACK


## The hero it's hunting (or, once they're down, whoever is nearest).
func _prey_position(p: Vector2) -> Vector2:
	var hero := world.hero_for_slot(_prey)
	if hero and not hero.is_downed():
		return hero.position
	_prey = _nearest_slot(p)
	hero = world.hero_for_slot(_prey)
	return hero.position if hero else Vector2.INF


func _nearest_slot(p: Vector2) -> int:
	var best := -1
	var best_d := INF
	for hero in world.heroes:
		if not hero.is_downed() and hero.position.distance_squared_to(p) < best_d:
			best_d = hero.position.distance_squared_to(p)
			best = hero.slot
	return best


func _leave_wake(p: Vector2, dt: float) -> void:
	_wake -= dt
	if _wake > 0.0:
		return
	_wake = WAKE_EVERY
	world.ground_fx.ring(p, 11.0, Color(SPRAY, 0.7), 0.6)
	world.particles.burst(p, 2, MURK.lightened(0.3), 20.0, 0.4, 2, Vector2.UP, PI, 40.0)


## Aim from the mouth at the hero's body, so the middle shot flies straight at them.
func _aim_at(p: Vector2, target: Vector2) -> Vector2:
	if target.is_finite():
		var to := target + Hero.SPRITE_FEET_OFFSET - (p + MOUTH)
		if to.length_squared() > 1.0:
			return to.normalized()
	return Vector2.DOWN


func _fan_angle(k: int, count: int) -> float:
	return 0.0 if count <= 1 else lerpf(-FAN_SPREAD, FAN_SPREAD, float(k) / float(count - 1))
