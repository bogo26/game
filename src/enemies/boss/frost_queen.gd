class_name FrostQueen
extends Boss
## The Frost Queen, a final boss (see Boss for what every boss shares): a
## gaunt queen of ice gliding over the floor of her frozen court, keeping her
## distance. Her frost chills: heroes it hits walk slower for a moment.
##   phase 1 (100-60%): ice lances (an aim line to every hero, then a lance
##                      down each), frost novas (a ring of frost rolls out to
##                      the circle she shows: dash through it or be outside)
##                      and icicle hail (icicles crash down around the heroes)
##   phase 2 (60-25%):  adds the glacial beam (a freezing beam sweeping the
##                      wedge she shows) and calls frost wraiths
##   phase 3 (<25%):    enraged: faster, lances in threes, and blizzards -
##                      a wind pushing everyone one way with ice shards on it
## Every attack is announced: aim lines (locked when the wind-up starts), the
## nova's reach, each icicle's circle, the beam's wedge and where it starts,
## the blizzard's callout, spawn portals. Backed into a wall with a hero on
## her, she steps through the ice to the far side of them (a frost ring
## shows where first).

enum Phase { ONE, TWO, THREE }
enum Action { GLIDE, WINDUP, BEAM, STEP }
enum Attack { LANCES, NOVA, HAIL, BEAM, SUMMON, BLIZZARD }

## 4 frames: glide0, glide1, wind-up (staff raised), cast.
const SPRITE := preload("res://assets/sprites/enemies/frost_queen.png")
const BODY_RADIUS := 11.0
const SPEEDS: Array[float] = [26.0, 30.0, 36.0]
const ATTACK_GAPS: Array[float] = [2.2, 1.8, 1.4]
const PHASE_TWO_AT := 0.6
const PHASE_THREE_AT := 0.25
## She keeps about this far from the nearest hero.
const KEEP_NEAR := 80.0
const KEEP_FAR := 130.0
## Unable to back away for STUCK_TIME, she fades out for STEP_TIME and steps
## to a spot STEP_REACH from the hero on her.
const STUCK_TIME := 0.8
const STEP_TIME := 0.5
const STEP_REACH := 150.0
## Her staff's crystal: lances leave from here.
const MUZZLE := Vector2(0, -34)
## Ice lances down a line to every hero (three a hero in phase 3).
const LANCE_WINDUP := 0.75
const LANCE_SPEED := 240.0
const LANCE_DAMAGE := 15.0
const LANCE_REACH := 220.0
const LANCE_SPREAD := 0.12
## Frost nova: a ring NOVA_WIDTH thick rolling out at NOVA_SPEED to NOVA_RADIUS.
const NOVA_WINDUP := 0.9
const NOVA_RADIUS := 170.0
const NOVA_WIDTH := 10.0
const NOVA_SPEED := 160.0
const NOVA_DAMAGE := 18.0
const NOVA_CHILL := 2.0
## Icicle hail: an icicle every HAIL_EVERY for HAIL_TIME near a hero, crashing
## down ICICLE_FALL after its circle shows.
const HAIL_WINDUP := 0.5
const HAIL_TIME := 2.4
const HAIL_EVERY := 0.16
const ICICLE_FALL := 0.8
const ICICLE_RADIUS := 14.0
const ICICLE_DAMAGE := 14.0
const ICICLE_CHILL := 1.0
const ICICLE_SCATTER := 50.0
## Glacial beam: sweeps BEAM_SWEEP radians across the nearest hero in
## BEAM_TIME, BEAM_LENGTH long, hitting heroes within BEAM_HALF of it.
const BEAM_WINDUP := 1.0
const BEAM_SWEEP := 2.0
const BEAM_TIME := 1.6
const BEAM_LENGTH := 190.0
const BEAM_HALF := 5.0
const BEAM_DAMAGE := 20.0
const BEAM_CHILL := 1.5
## Her call: SUMMON_COUNT adds, SUMMON_WRAITHS of them frost wraiths.
const SUMMON_COUNT := 6
const SUMMON_WRAITHS := 3
## Blizzard: for BLIZZARD_TIME a wind pushes heroes WIND_PUSH px/s one way,
## with an ice shard riding it every SHARD_EVERY.
const BLIZZARD_WINDUP := 0.8
const BLIZZARD_TIME := 5.0
const WIND_PUSH := 34.0
const SHARD_EVERY := 0.1
const SHARD_SPEED := 120.0
const SHARD_DAMAGE := 10.0
const ICE := Color(0.72, 0.92, 1.0)

var phase: Phase = Phase.ONE
var action: Action = Action.GLIDE
var pending_attack: Attack = Attack.LANCES

var _attack_timer := 2.0
var _action_time := 0.0
var _lance_dirs: Array[Vector2] = []
## Novas rolling out: [centre, seconds since, heroes hit (slot -> true)].
var _novas: Array[Array] = []
## Icicles about to land: [spot, seconds left].
var _icicles: Array[Array] = []
var _hail_left := 0.0
var _hail_next := 0.0
var _beam_from := 0.0
var _beam_turn := 1.0
var _blizzard_left := 0.0
var _wind := Vector2.RIGHT
var _shard_next := 0.0
var _shatter_sound := 0.0
var _cast := 0.0
var _stuck := 0.0
var _step_to := Vector2.ZERO


func _init() -> void:
	body_type = &"frost_queen"
	display_name = "Frost Queen"


func _sprite_texture() -> Texture2D:
	return SPRITE


func is_winding_up() -> bool:
	return action == Action.WINDUP


func status_text() -> String:
	return "BLIZZARD" if _blizzard_left > 0.0 else ""


func _think(p: Vector2, dt: float) -> Vector2:
	_update_phase(p)
	_cast = maxf(0.0, _cast - dt)
	var target := _nearest_hero(p)
	match action:
		Action.GLIDE:
			if target.is_finite():
				p = _glide(p, target, dt)
			_attack_timer -= dt
			if action == Action.GLIDE and _attack_timer <= 0.0 and target.is_finite():
				_begin_attack(p, target)
		Action.WINDUP:
			_action_time -= dt
			if _action_time <= 0.0:
				_execute_attack(p)
		Action.BEAM:
			_sweep(p, dt)
		Action.STEP:
			_action_time -= dt
			if _action_time <= 0.0:
				p = _arrive(p)
	_update_novas(dt)
	_update_hail(dt)
	_update_blizzard(dt)
	return p


func _frame() -> int:
	if action == Action.WINDUP:
		return 2
	if action == Action.BEAM or action == Action.STEP or _cast > 0.0:
		return 3
	return super()


func _tint() -> Color:
	var tint := Color(0.85, 1.0, 1.3) if phase == Phase.THREE else Color.WHITE
	if action == Action.STEP:
		tint.a = clampf(_action_time / STEP_TIME, 0.0, 1.0)  # fading into the ice
	return tint


func is_stepping() -> bool:
	return action == Action.STEP


## Keeps her distance: away from a hero who comes close, after one who strays far.
func _glide(p: Vector2, target: Vector2, dt: float) -> Vector2:
	var to := target - p
	var d := to.length()
	sprite.flip_h = to.x < 0.0
	var dir := Vector2.ZERO
	if d < KEEP_NEAR:
		dir = -to / maxf(d, 0.001)
	elif d > KEEP_FAR:
		dir = to / d
	if dir == Vector2.ZERO:
		_stuck = 0.0
		return p
	var step := SPEEDS[phase] * dt
	var next := world.grid.move_and_slide(p, dir * step, BODY_RADIUS)
	if d < KEEP_NEAR and next.distance_to(p) < step * 0.3:
		_stuck += dt  # backed into a wall
		if _stuck >= STUCK_TIME:
			_begin_step(next, target)
	else:
		_stuck = maxf(0.0, _stuck - dt)
	return next


## Picks where to step (the far side of the hero on her, inside the room)
## and starts fading out; a frost ring shows where she'll appear.
func _begin_step(p: Vector2, target: Vector2) -> void:
	_stuck = 0.0
	var away := (target - p).angle()
	for k in 7:
		var angle := away + (k + 1) / 2 * 0.45 * (1.0 if k % 2 == 0 else -1.0)
		var q := _spot_in_room(target + Vector2.from_angle(angle) * STEP_REACH, Vector2.INF)
		if q.is_finite() and world.grid.line_of_sight(target, q):
			_step_to = q
			action = Action.STEP
			_action_time = STEP_TIME
			world.warn_fx.portal(q, 10.0, ICE, STEP_TIME)
			world.particles.burst(p - Vector2(0, 20), 10, ICE, 60.0, 0.4, 2)
			Audio.play(&"blink")
			return


func _arrive(p: Vector2) -> Vector2:
	world.particles.burst(p - Vector2(0, 20), 8, ICE, 50.0, 0.35, 2)
	world.particles.burst(_step_to - Vector2(0, 20), 14, ICE, 80.0, 0.45, 2)
	world.fx.ring(_step_to, 18.0, ICE, 0.35)
	action = Action.GLIDE
	return _step_to


func _update_phase(p: Vector2) -> void:
	var ratio := hp_ratio()
	var next := Phase.ONE
	if ratio < PHASE_THREE_AT:
		next = Phase.THREE
	elif ratio < PHASE_TWO_AT:
		next = Phase.TWO
	if next <= phase:
		return
	phase = next
	_announce_phase()
	if phase == Phase.TWO:
		_summon_mix(_crowd(SUMMON_COUNT, &"frost_wraith", SUMMON_WRAITHS), 48.0)
	else:
		_start_blizzard(p)


func _begin_attack(p: Vector2, target: Vector2) -> void:
	var options: Array[Attack] = [Attack.LANCES, Attack.LANCES, Attack.NOVA, Attack.HAIL]
	if phase >= Phase.TWO:
		options.append_array([Attack.BEAM, Attack.BEAM, Attack.SUMMON])
	if phase == Phase.THREE and _blizzard_left <= 0.0:
		options.append(Attack.BLIZZARD)
	wind_up(options[_rng.randi_range(0, options.size() - 1)], p, target)


## Starts `attack`'s wind-up and draws its warning.
func wind_up(attack: Attack, p: Vector2, target: Vector2) -> void:
	pending_attack = attack
	action = Action.WINDUP
	var warn := world.warn_fx
	var danger := FxLayer.DANGER
	match attack:
		Attack.LANCES:
			_action_time = LANCE_WINDUP
			_lance_dirs.clear()
			var spread: Array[float] = [0.0]
			if phase == Phase.THREE:
				spread = [-LANCE_SPREAD, 0.0, LANCE_SPREAD]
			for q in _hero_spots():
				var aim := (q + Hero.SPRITE_FEET_OFFSET - (p + MUZZLE)).normalized()
				for a in spread:
					_lance_dirs.append(aim.rotated(a))
			var from := p + MUZZLE
			for d in _lance_dirs:
				warn.warn_line(from + d * 8.0, world.grid.shot_reach(from, from + d * LANCE_REACH), danger,
					_action_time, 1.0)
		Attack.NOVA:
			_action_time = NOVA_WINDUP
			warn.telegraph(p, NOVA_RADIUS + Hero.RADIUS, danger, _action_time)
		Attack.HAIL:
			_action_time = HAIL_WINDUP
		Attack.BEAM:
			_action_time = BEAM_WINDUP
			var mid := (target - p).angle() if target.is_finite() and target != p else PI * 0.5
			_beam_turn = 1.0 if _rng.randf() < 0.5 else -1.0
			_beam_from = mid - _beam_turn * BEAM_SWEEP * 0.5
			warn.warn_arc(p, BEAM_LENGTH, mid, BEAM_SWEEP, danger, _action_time + BEAM_TIME)
			warn.warn_band(p, beam_end(p, _beam_from), (BEAM_HALF + Hero.RADIUS) * 2.0, danger, _action_time)
			sprite.flip_h = cos(mid) < 0.0
		Attack.SUMMON:
			_action_time = HAIL_WINDUP
			_summon_mix(_crowd(SUMMON_COUNT, &"frost_wraith", SUMMON_WRAITHS), 48.0)  # out as the wind-up ends
		Attack.BLIZZARD:
			_action_time = BLIZZARD_WINDUP
	Audio.play(&"windup")


func _execute_attack(p: Vector2) -> void:
	_cast = 0.3
	match pending_attack:
		Attack.LANCES:
			for d in _lance_dirs:
				_shoot(p + MUZZLE, d * LANCE_SPEED, LANCE_DAMAGE, ProjectileSim.Look.SHARD)
			Audio.play(&"freeze")
		Attack.NOVA:
			_novas.append([p, 0.0, {}])
			world.fx.nova(p, NOVA_RADIUS, NOVA_WIDTH, ICE, NOVA_RADIUS / NOVA_SPEED)
			world.shake(2.0)
			Audio.play(&"nova")
		Attack.HAIL:
			_hail_left = HAIL_TIME
			_hail_next = 0.0
		Attack.BEAM:
			action = Action.BEAM
			_action_time = BEAM_TIME
			Audio.play(&"beam")
			return
		Attack.SUMMON:
			pass  # called when the wind-up started
		Attack.BLIZZARD:
			_start_blizzard(p)
	_end_action()


## Where the beam from `p` at `angle` ends (walls stop it).
func beam_end(p: Vector2, angle: float) -> Vector2:
	return world.grid.shot_reach(p, p + Vector2.from_angle(angle) * BEAM_LENGTH)


## The beam's angle `elapsed` seconds into its sweep.
func beam_angle(elapsed: float) -> float:
	return _beam_from + _beam_turn * BEAM_SWEEP * clampf(elapsed / BEAM_TIME, 0.0, 1.0)


func _sweep(p: Vector2, dt: float) -> void:
	_action_time -= dt
	var end := beam_end(p, beam_angle(BEAM_TIME - _action_time))
	for hero in _hit_band(p, end, BEAM_HALF, BEAM_DAMAGE):
		hero.chill(BEAM_CHILL)
	world.fx.beam(p + Vector2(0, -6), end + Vector2(0, -6), 8.0, ICE, 0.1)
	if _rng.randf() < 0.5:
		world.particles.burst(end, 2, ICE, 50.0, 0.4, 2)
	if _action_time <= 0.0:
		_end_action()


## Novas roll outwards; each hits a hero once, as its ring passes over them
## (a dash's invulnerability gets through it).
func _update_novas(dt: float) -> void:
	var k := 0
	while k < _novas.size():
		var nova := _novas[k]
		nova[1] = float(nova[1]) + dt
		var r := float(nova[1]) * NOVA_SPEED
		if r > NOVA_RADIUS + NOVA_WIDTH:
			_novas.remove_at(k)
			continue
		var center: Vector2 = nova[0]
		var hit: Dictionary = nova[2]
		for hero in world.heroes:
			if hit.has(hero.slot):
				continue
			var d := hero.position.distance_to(center)
			if d <= NOVA_RADIUS + Hero.RADIUS and absf(d - r) <= NOVA_WIDTH * 0.5 + Hero.RADIUS \
					and world.grid.line_of_sight(center, hero.position) \
					and hero.take_hit(NOVA_DAMAGE * world.horde.damage_mult):
				hit[hero.slot] = true
				hero.chill(NOVA_CHILL)
		k += 1


## Icicles keep coming near the heroes while the hail lasts, and crash down
## where their circles showed.
func _update_hail(dt: float) -> void:
	_shatter_sound -= dt
	if _hail_left > 0.0:
		_hail_left -= dt
		_hail_next -= dt
		var spots := _hero_spots()
		while _hail_next <= 0.0 and not spots.is_empty():
			_hail_next += HAIL_EVERY
			var q := spots[_rng.randi_range(0, spots.size() - 1)]
			if _rng.randf() < 0.6:
				q = _spot_in_room(q + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(10.0, ICICLE_SCATTER), q)
			_icicles.append([q, ICICLE_FALL])
			world.warn_fx.telegraph(q, ICICLE_RADIUS + Hero.RADIUS, FxLayer.DANGER, ICICLE_FALL)
	var k := 0
	while k < _icicles.size():
		var icicle := _icicles[k]
		icicle[1] = float(icicle[1]) - dt
		if float(icicle[1]) > 0.0:
			k += 1
			continue
		_icicles.remove_at(k)
		var q: Vector2 = icicle[0]
		for hero in _hit_circle(q, ICICLE_RADIUS, ICICLE_DAMAGE):
			hero.chill(ICICLE_CHILL)
		world.fx.line(q + Vector2(0, -40), q, Color(ICE, 0.9), 0.12)
		world.fx.disc(q, ICICLE_RADIUS, Color(ICE, 0.45), 0.2)
		world.particles.burst(q - Vector2(0, 2), 8, ICE, 90.0, 0.35, 2, Vector2.UP, PI, 200.0)
		if _shatter_sound <= 0.0:
			_shatter_sound = 0.12
			Audio.play(&"shatter")


func _start_blizzard(_p: Vector2) -> void:
	_blizzard_left = BLIZZARD_TIME
	_wind = Vector2.from_angle(_rng.randi_range(0, 7) * TAU / 8.0)
	_shard_next = 0.4
	world.hud.callout("BLIZZARD!", ICE)
	Audio.play(&"blizzard")


## The wind pushes every standing hero; shards ride it in from the upwind
## wall (or the edge of the view) across the room.
func _update_blizzard(dt: float) -> void:
	if _blizzard_left <= 0.0:
		return
	_blizzard_left -= dt
	for hero in world.heroes:
		if not hero.is_downed():
			hero.position = world.grid.move_and_slide(hero.position, _wind * WIND_PUSH * dt, Hero.RADIUS)
	var view := world.camera.visible_rect()
	_shard_next -= dt
	while _shard_next <= 0.0:
		_shard_next += SHARD_EVERY
		var from := _upwind_point(view)
		if from.is_finite():
			_shoot(from, (_wind.rotated(_rng.randf_range(-0.15, 0.15))) * SHARD_SPEED, SHARD_DAMAGE,
				ProjectileSim.Look.SHARD)
	# Snow streaks across the view.
	for k in 3:
		var q := Vector2(_rng.randf_range(view.position.x, view.end.x), _rng.randf_range(view.position.y, view.end.y))
		world.particles.burst(q, 1, Color(1, 1, 1, 0.8), 150.0, 0.5, 1, _wind, 0.2, 0.0, 0.0)


## Where a shard enters: a random open spot in view traced back upwind to
## the wall (or the edge of the view); INF if no try found open floor.
func _upwind_point(view: Rect2) -> Vector2:
	var q := Vector2.INF
	for attempt in 4:
		q = Vector2(_rng.randf_range(view.position.x, view.end.x), _rng.randf_range(view.position.y, view.end.y))
		if not world.grid.is_solid_at(q):
			break
		q = Vector2.INF
	if not q.is_finite():
		return q
	var back := q - _wind * view.size.length()
	back = Vector2(clampf(back.x, view.position.x, view.end.x), clampf(back.y, view.position.y, view.end.y))
	return world.grid.shot_reach(q, back) + _wind * 4.0


func _end_action() -> void:
	action = Action.GLIDE
	_attack_timer = ATTACK_GAPS[phase] * _rng.randf_range(0.8, 1.2)
