class_name PickupSim
extends RefCounted
## XP gems and hearts as packed arrays. Items sit still until a hero comes
## within pickup range, then home in and are collected on contact. When full,
## new drops merge into existing gems so XP is never lost. Hearts only go to a
## hurt hero (the most hurt one in range). vacuum() pulls every gem on the
## level to the team (arena cleared, exit open).

const CAPACITY := 600
const FX_ROW := 8  # pickups are row 1 of the fx atlas (8 columns)
const COLLECT_DISTANCE := 6.0
const HOMING_ACCEL := 900.0
const HOMING_MAX_SPEED := 420.0
## Vacuumed gems start this fast.
const VACUUM_SPEED := 160.0

enum Kind { XP, HEART }
## Look: 0 small gem, 1 medium, 2 large, 3 heart.

var count := 0
var pos := PackedVector2Array()
var value := PackedInt32Array()
var kind := PackedInt32Array()
var target := PackedInt32Array()   # hero index homing toward, -1 = idle
var speed := PackedFloat32Array()
var age := PackedFloat32Array()

## Collected this frame: [hero index, kind, value] triples.
var collected := PackedInt32Array()

var _merge_cursor := 0


func _init() -> void:
	pos.resize(CAPACITY)
	value.resize(CAPACITY)
	kind.resize(CAPACITY)
	target.resize(CAPACITY)
	speed.resize(CAPACITY)
	age.resize(CAPACITY)


func spawn(p: Vector2, p_kind: Kind, p_value: int) -> void:
	if count >= CAPACITY:
		if p_kind == Kind.XP:
			# Merge into an existing gem (round-robin) instead of dropping XP.
			for attempt in CAPACITY:
				_merge_cursor = (_merge_cursor + 1) % count
				if kind[_merge_cursor] == Kind.XP:
					value[_merge_cursor] += p_value
					return
		return
	var i := count
	count += 1
	pos[i] = p
	value[i] = p_value
	kind[i] = p_kind
	target[i] = -1
	speed[i] = 0.0
	age[i] = 0.0


func clear() -> void:
	count = 0


static func look_of(p_kind: int, p_value: int) -> int:
	if p_kind == Kind.HEART:
		return 3
	if p_value >= 10:
		return 2
	if p_value >= 3:
		return 1
	return 0


## Sends every XP gem flying to the nearest active hero.
func vacuum(hero_positions: PackedVector2Array, hero_active: PackedByteArray) -> void:
	for i in count:
		if kind[i] != Kind.XP:
			continue
		var best := -1
		var best_d := INF
		for h in hero_positions.size():
			if hero_active[h] != 0:
				var d := pos[i].distance_squared_to(hero_positions[h])
				if d < best_d:
					best_d = d
					best = h
		if best >= 0:
			target[i] = best
			speed[i] = maxf(speed[i], VACUUM_SPEED)


## XP in gems still lying around (banked when a level ends).
func total_xp() -> int:
	var total := 0
	for i in count:
		if kind[i] == Kind.XP:
			total += value[i]
	return total


## `hero_positions` / `hero_radii` (pickup range) / `hero_active` per hero;
## `hero_need`: the share of HP each hero is missing (hearts go to the most
## hurt hero in range, and never to one at full HP).
func update(dt: float, hero_positions: PackedVector2Array, hero_ranges: PackedFloat32Array,
		hero_active: PackedByteArray, hero_need: PackedFloat32Array = PackedFloat32Array()) -> void:
	collected.clear()
	var P := pos
	var hero_count := hero_positions.size()
	var i := 0
	while i < count:
		age[i] += dt
		var p := P[i]
		var tgt := target[i]
		if tgt >= hero_count or (tgt >= 0 and hero_active[tgt] == 0):
			tgt = -1
			target[i] = -1
			speed[i] = 0.0
		if tgt == -1:
			var heart := kind[i] == Kind.HEART and not hero_need.is_empty()
			var most_need := 0.0
			for h in hero_count:
				if hero_active[h] != 0:
					var range_px := hero_ranges[h]
					if p.distance_squared_to(hero_positions[h]) <= range_px * range_px:
						if not heart:
							tgt = h
							break
						if hero_need[h] > most_need:
							most_need = hero_need[h]
							tgt = h
			target[i] = tgt
		if tgt >= 0:
			var to := hero_positions[tgt] - p
			var dist := to.length()
			if dist <= COLLECT_DISTANCE:
				collected.append(tgt)
				collected.append(kind[i])
				collected.append(value[i])
				_remove_at(i, P)
				continue
			var s := minf(speed[i] + HOMING_ACCEL * dt, HOMING_MAX_SPEED)
			speed[i] = s
			P[i] = p + to / dist * minf(s * dt, dist)
		i += 1
	pos = P


func _remove_at(i: int, P: PackedVector2Array) -> void:
	var last := count - 1
	if i != last:
		P[i] = P[last]
		value[i] = value[last]
		kind[i] = kind[last]
		target[i] = target[last]
		speed[i] = speed[last]
		age[i] = age[last]
	count = last


## Gems go to `layer`; hearts go to `heart_layer` when given (drawn above the
## horde, so a crowd can't hide them).
func render(layer: InstanceLayer, heart_layer: InstanceLayer = null) -> void:
	var buf := layer.buffer
	var cap := layer.capacity
	var hbuf := heart_layer.buffer if heart_layer else PackedFloat32Array()
	var hcap := heart_layer.capacity if heart_layer else 0
	var w := 0
	var hw := 0
	for i in count:
		var p := pos[i]
		var bob := roundf(sin(age[i] * 5.0 + float(i)) * 1.0) if target[i] == -1 else 0.0
		var cell := float(FX_ROW + look_of(kind[i], value[i]))
		if heart_layer and kind[i] == Kind.HEART:
			if hw < hcap:
				var ho := hw * InstanceLayer.STRIDE
				hbuf[ho + 3] = roundf(p.x)
				hbuf[ho + 7] = roundf(p.y) + bob
				hbuf[ho + 8] = cell
				hw += 1
			continue
		if w >= cap:
			continue
		var o := w * InstanceLayer.STRIDE
		buf[o + 3] = roundf(p.x)
		buf[o + 7] = roundf(p.y) + bob
		buf[o + 8] = cell
		w += 1
	layer.buffer = buf
	layer.commit(w)
	if heart_layer:
		heart_layer.buffer = hbuf
		heart_layer.commit(hw)
