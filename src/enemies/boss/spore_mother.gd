class_name SporeMother
extends Boss
## The Spore Mother, a final boss (see Boss for what every boss shares): a
## towering fungus rooted in the heart of the rot. She never moves; she fights
## through the ground and the air.
##   pods:              spore pods sprout around the cavern, tied to her by
##                      glowing threads, and shield her while any stands (she
##                      shrugs off SHIELD of every hit; the HUD says SHIELDED
##                      and the objective points at the pods) - burst them
##   phase 1 (100-60%): root eruptions (roots burst up along a band toward
##                      every hero) and spore rain (spore bombs across the
##                      cavern that leave clouds)
##   phase 2 (60-25%):  the pods grow back; adds spore spirals (arms of
##                      spores wheeling out of her) and calls puffballs
##   phase 3 (<25%):    enraged: faster, more roots, and fairy rings - rings
##                      of mushrooms around her erupt, then the rings between
##                      them (stand in one, then step into the other)
## Every attack is announced: each root band, each bomb's landing circle, the
## spiral's turning ring of dots, each fairy ring, spawn portals.

enum Phase { ONE, TWO, THREE }
enum Action { IDLE, WINDUP, SPIRAL }
enum Attack { ROOTS, RAIN, SPIRAL, CALL, RINGS }

## 4 frames of 96x96: idle0, idle1, wind-up (cap swelling), release.
const SPRITE := preload("res://assets/sprites/enemies/spore_mother.png")
const POD := &"spore_pod"
const ATTACK_GAPS: Array[float] = [2.3, 1.9, 1.4]
const FIRST_ATTACK := 2.5
## Phase changes below these shares of HP.
const PHASE_TWO_AT := 0.6
const PHASE_THREE_AT := 0.25
## Spore pods: PODS[phase] sprout between POD_NEAR and POD_FAR from her as
## phases 1 and 2 begin; while any stands she shrugs off SHIELD of every hit.
const PODS: Array[int] = [3, 4, 0]
const POD_NEAR := 96.0
const POD_FAR := 150.0
const SHIELD := 0.8
const SHIELD_BAR := Color("9a7ab0")
## Roots burst up along a band from her edge toward every hero (and, from
## phase 2, EXTRA_ROOTS more): ROOT_LENGTH long, hitting heroes whose feet
## are within ROOT_HALF of its middle.
const ROOTS_WINDUP := 0.9
const ROOT_START := 18.0
const ROOT_LENGTH := 230.0
const ROOT_HALF := 11.0
const ROOT_DAMAGE := 22.0
const EXTRA_ROOTS: Array[int] = [0, 2, 3]
## Spore rain: RAIN_PER_HERO bombs at and around every hero and RAIN_LOOSE
## more anywhere within RAIN_REACH, landing RAIN_FLIGHT seconds later.
const RAIN_WINDUP := 0.6
const RAIN_PER_HERO := 2
const RAIN_LOOSE := 3
const RAIN_REACH := 200.0
const RAIN_RADIUS := 24.0
const RAIN_DAMAGE := 16.0
const RAIN_FLIGHT := Vector2(0.9, 1.5)
## Spore spiral: SPIRAL_ARMS arms of spores wheeling out of her for
## SPIRAL_TIME, a shot per arm every SPIRAL_EVERY.
const SPIRAL_WINDUP := 0.7
const SPIRAL_TIME := 2.4
const SPIRAL_EVERY := 0.12
const SPIRAL_TURN := 1.5
const SPIRAL_ARMS: Array[int] = [3, 3, 4]
const SPIRAL_SPEED := 72.0
const SPIRAL_DAMAGE := 10.0
## Her call: CALL_COUNT adds, CALL_PUFFBALLS of them puffballs (the rest swarmers).
const CALL_COUNT := 6
const CALL_PUFFBALLS := 3
## Fairy rings: RINGS rings RING_WIDTH wide from RING_INNER out; every other
## one erupts, then the ones between them.
const RINGS_WINDUP := 1.1
const RINGS_SECOND := 0.9
const RING_INNER := 24.0
const RING_WIDTH := 32.0
const RINGS := 7
const RING_DAMAGE := 24.0
## Spores leave from the cap (above the feet).
const MOUTH := Vector2(0, -52)
const THREAD := Color(0.95, 0.5, 0.9)
const ROOT_COLOR := Color(0.62, 0.42, 0.56)

var phase: Phase = Phase.ONE
var action: Action = Action.IDLE
var pending_attack: Attack = Attack.ROOTS
## Pods standing (uids).
var pods := PackedInt32Array()

var _attack_timer := FIRST_ATTACK
var _action_time := 0.0
var _started := false
var _bands: Array[PackedVector2Array] = []
var _ring_wave := 0
var _spiral_angle := 0.0
var _spiral_turn := 1.0
var _spiral_emit := 0.0
var _spit_sound := 0.0
var _release := 0.0


func _init() -> void:
	body_type = &"spore_mother"
	display_name = "Spore Mother"


func _sprite_texture() -> Texture2D:
	return SPRITE


func is_winding_up() -> bool:
	return action == Action.WINDUP


func is_shielded() -> bool:
	return not pods.is_empty()


func status_text() -> String:
	return "SHIELDED" if is_shielded() else ""


func bar_color() -> Color:
	return SHIELD_BAR if is_shielded() else BAR_COLOR


func objective_hint() -> String:
	if not is_shielded():
		return ""
	return "Burst the spore pods!  %d left" % pods.size()


## While she's shielded: the pod nearest the team.
func objective_point() -> Vector2:
	var best := position
	var best_d := INF
	var from := world.camera.global_position
	for q in pod_positions():
		if q.distance_squared_to(from) < best_d:
			best_d = q.distance_squared_to(from)
			best = q
	return best


func pod_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for id in pods:
		var i := world.horde.index_of_uid(id)
		if i >= 0:
			out.append(world.horde.pos[i])
	return out


func _think(p: Vector2, dt: float) -> Vector2:
	if not _started:
		_started = true
		sprout_pods(PODS[Phase.ONE])
	_update_phase()
	_update_pods(dt)
	_release = maxf(0.0, _release - dt)
	match action:
		Action.IDLE:
			_attack_timer -= dt
			if _attack_timer <= 0.0 and _nearest_hero(p).is_finite():
				_begin_attack(p)
		Action.WINDUP:
			_action_time -= dt
			if _action_time <= 0.0:
				_execute_attack(p)
		Action.SPIRAL:
			_spiral(p, dt)
	queue_redraw()
	return p  # rooted to the spot


func _frame() -> int:
	if action == Action.WINDUP:
		return 2
	if action == Action.SPIRAL or _release > 0.0:
		return 3
	return int(_anim * 2.5) % 2


func _tint() -> Color:
	if is_shielded():
		return Color(0.85, 0.8, 1.05)
	return Color(1.2, 0.9, 1.0) if phase == Phase.THREE else Color.WHITE


func _update_phase() -> void:
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
	sprout_pods(PODS[phase])
	_summon_mix(_crowd(CALL_COUNT + 2 * phase, &"puffball", CALL_PUFFBALLS + phase), 60.0)


## Pods sprout around the cavern (never on top of a hero); she's shielded
## until they're burst.
func sprout_pods(count: int) -> void:
	var horde := world.horde
	var type := horde.type_index(POD)
	var offset := _rng.randf() * TAU
	for k in count:
		var spot := Vector2.INF
		for attempt in 6:
			var angle := offset + TAU * (k + _rng.randf_range(-0.2, 0.2)) / count
			var q := _spot_in_room(position + Vector2.from_angle(angle) * _rng.randf_range(POD_NEAR, POD_FAR), Vector2.INF)
			if q.is_finite() and _clear_of_heroes(q):
				spot = q
				break
		if not spot.is_finite():
			continue
		var i := horde.spawn(type, spot, world.spawner.unique_hp_multiplier())
		if i < 0:
			continue
		horde.action[i] = 0.0
		pods.append(horde.uid[i])
		world.fx.ring(spot, 16.0, THREAD, 0.5)
		world.particles.burst(spot - Vector2(0, 6), 12, World.SPORE_COLOR, 70.0, 0.6, 2, Vector2.UP, PI, 60.0)
	if count > 0:
		Audio.play(&"sprout")


func _clear_of_heroes(q: Vector2) -> bool:
	for hero in world.heroes:
		if hero.position.distance_to(q) < 24.0:
			return false
	return true


## Forgets burst pods, pulses the others, and shields her while any stands.
func _update_pods(dt: float) -> void:
	var horde := world.horde
	var k := 0
	while k < pods.size():
		var i := horde.index_of_uid(pods[k])
		if i == -1 or horde.hp[i] <= 0.0:
			pods.remove_at(k)
			continue
		# A throb now and then (the pose NestAtlas frames 4-5 show).
		var left := horde.action[i] - dt
		if left <= -1.6:
			left = 0.4
		horde.action[i] = left
		k += 1
	horde.guard[_index] = SHIELD if is_shielded() else 0.0


func _draw() -> void:
	# Threads from every pod to her: what shields her.
	for q in pod_positions():
		var a := Vector2(0, -20)
		var b := q - position + Vector2(0, -6)
		var pulse := 0.45 + 0.35 * sin(_anim * 5.0 + b.x * 0.05)
		var side := (b - a).orthogonal().normalized()
		var points := PackedVector2Array()
		for s in 9:
			var t := s / 8.0
			points.append((a.lerp(b, t) + side * sin(t * PI * 3.0 + _anim * 4.0) * 3.0).round())
		draw_polyline(points, Color(THREAD, pulse), -1.0, false)


func _begin_attack(p: Vector2) -> void:
	var options: Array[Attack] = [Attack.ROOTS, Attack.RAIN]
	if phase >= Phase.TWO:
		options.append_array([Attack.SPIRAL, Attack.SPIRAL, Attack.CALL])
	if phase == Phase.THREE:
		options.append_array([Attack.RINGS, Attack.RINGS, Attack.ROOTS])
	wind_up(options[_rng.randi_range(0, options.size() - 1)], p)


## Starts `attack`'s wind-up and draws its warning.
func wind_up(attack: Attack, p: Vector2) -> void:
	pending_attack = attack
	action = Action.WINDUP
	var warn := world.warn_fx
	var danger := FxLayer.DANGER
	match attack:
		Attack.ROOTS:
			_action_time = ROOTS_WINDUP
			_bands.clear()
			var dirs: Array[Vector2] = []
			for q in _hero_spots():
				dirs.append((q - p).normalized() if q.distance_to(p) > 1.0 else Vector2.DOWN)
			var offset := _rng.randf() * TAU
			for k in EXTRA_ROOTS[phase]:
				dirs.append(Vector2.from_angle(offset + TAU * k / EXTRA_ROOTS[phase]))
			for d in dirs:
				var a := p + d * ROOT_START
				var band := PackedVector2Array([a, world.grid.shot_reach(a, p + d * ROOT_LENGTH)])
				_bands.append(band)
				warn.warn_band(band[0], band[1], (ROOT_HALF + Hero.RADIUS) * 2.0, danger, _action_time)
		Attack.RAIN:
			_action_time = RAIN_WINDUP
		Attack.SPIRAL:
			_action_time = SPIRAL_WINDUP
			world.fx.dot_ring(p + MOUTH, 40.0, 12, danger, _action_time)
		Attack.CALL:
			_action_time = RAIN_WINDUP
			_summon_mix(_crowd(CALL_COUNT, &"puffball", CALL_PUFFBALLS), 60.0)  # out as the wind-up ends
		Attack.RINGS:
			_action_time = RINGS_WINDUP
			_ring_wave = 0
			_warn_rings(p, 0, _action_time)
	Audio.play(&"windup")


func _execute_attack(p: Vector2) -> void:
	_release = 0.35
	match pending_attack:
		Attack.ROOTS:
			for band in _bands:
				_hit_band(band[0], band[1], ROOT_HALF, ROOT_DAMAGE)
				_roots_along(band[0], band[1])
			world.shake(3.0)
			Audio.play(&"roots")
		Attack.RAIN:
			for q in _rain_spots(p):
				world.lob(p + MOUTH, q, RAIN_RADIUS, RAIN_DAMAGE * world.horde.damage_mult, &"spores",
					_rng.randf_range(RAIN_FLIGHT.x, RAIN_FLIGHT.y))
			Audio.play(&"lob")
		Attack.SPIRAL:
			action = Action.SPIRAL
			_action_time = SPIRAL_TIME
			_spiral_angle = _rng.randf() * TAU
			_spiral_turn = 1.0 if _rng.randf() < 0.5 else -1.0
			_spiral_emit = 0.0
			return
		Attack.CALL:
			pass  # called when the wind-up started
		Attack.RINGS:
			_erupt_rings(p, _ring_wave)
			if _ring_wave == 0:
				# Now the rings between them.
				_ring_wave = 1
				_action_time = RINGS_SECOND
				_warn_rings(p, 1, _action_time)
				return
	_end_action()


func _spiral(p: Vector2, dt: float) -> void:
	_action_time -= dt
	_spiral_angle += SPIRAL_TURN * _spiral_turn * dt
	_spiral_emit -= dt
	_spit_sound -= dt
	var arms := SPIRAL_ARMS[phase]
	while _spiral_emit <= 0.0:
		_spiral_emit += SPIRAL_EVERY
		for k in arms:
			_shoot(p + MOUTH, Vector2.from_angle(_spiral_angle + TAU * k / arms) * SPIRAL_SPEED, SPIRAL_DAMAGE,
				ProjectileSim.Look.SPIT)
		if _spit_sound <= 0.0:
			_spit_sound = 0.25
			Audio.play(&"spit")
	if _action_time <= 0.0:
		_end_action()


## Which fairy ring a spot `distance` px from her is in (-1: beyond them all).
static func ring_of(distance: float) -> int:
	if distance >= RING_INNER + RINGS * RING_WIDTH:
		return -1
	return maxi(0, int((distance - RING_INNER) / RING_WIDTH))


func _warn_rings(p: Vector2, wave: int, seconds: float) -> void:
	for k in range(wave, RINGS, 2):
		world.warn_fx.warn_ring(p, RING_INNER + (k + 0.5) * RING_WIDTH, RING_WIDTH, FxLayer.DANGER, seconds)


## Every other ring (`wave` 0: the first, the third...) erupts: heroes whose
## feet are in one (and whom she can see) are hit.
func _erupt_rings(p: Vector2, wave: int) -> void:
	for hero in world.heroes:
		var ring := ring_of(hero.position.distance_to(p))
		if ring >= 0 and ring % 2 == wave and world.grid.line_of_sight(p, hero.position):
			hero.take_hit(RING_DAMAGE * world.horde.damage_mult)
	for k in range(wave, RINGS, 2):
		var r := RING_INNER + (k + 0.5) * RING_WIDTH
		var n := int(TAU * r / 22.0)
		for m in n:
			var q := p + Vector2.from_angle(TAU * (m + 0.5 * (k % 2)) / n) * r
			if world.grid.is_solid_at(q):
				continue
			world.fx.line(q + Vector2(0, 3), q + Vector2(0, -7), ROOT_COLOR.lightened(0.3), 0.35)
			if m % 3 == 0:
				world.particles.burst(q, 2, World.SPORE_COLOR, 40.0, 0.5, 2, Vector2.UP, PI, 40.0)
	world.shake(3.5)
	Audio.play(&"roots")


## Roots bursting up along a band.
func _roots_along(a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var steps := maxi(1, int(length / 12.0))
	for s in steps + 1:
		var q := a.lerp(b, float(s) / steps) + Vector2(_rng.randf_range(-4, 4), 0)
		world.fx.line(q + Vector2(0, 3), q + Vector2(0, -9 - _rng.randi_range(0, 4)), ROOT_COLOR.lightened(0.25), 0.35)
		if s % 2 == 0:
			world.particles.burst(q, 2, ROOT_COLOR, 50.0, 0.4, 2, Vector2.UP, PI, 120.0)


## Where spore rain lands: on and around every hero, and anywhere around her.
func _rain_spots(p: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in _hero_spots():
		out.append(q)
		for k in RAIN_PER_HERO - 1:
			out.append(_spot_in_room(q + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(28.0, 50.0), q))
	for k in RAIN_LOOSE:
		var q := p + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(50.0, RAIN_REACH)
		if world.grid.line_of_sight(p, q):
			out.append(_spot_in_room(q, p))
	return out


func _end_action() -> void:
	action = Action.IDLE
	_attack_timer = ATTACK_GAPS[phase] * _rng.randf_range(0.8, 1.2)


func _die() -> void:
	# Her pods wither with her.
	var horde := world.horde
	for id in pods:
		var i := horde.index_of_uid(id)
		if i >= 0:
			horde.guard[i] = 0.0
			horde.damage(i, 1e9, Vector2.ZERO, -1)
	pods.clear()
	queue_redraw()
	super()
