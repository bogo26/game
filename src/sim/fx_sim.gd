class_name FxSim
extends RefCounted
## Sprite particles (soft round blobs from row 2 of the fx atlas) as packed
## arrays, drawn through one coloured InstanceLayer: hit sparks, death puffs,
## explosion debris, dash dust, level-up bursts. Oldest particles are
## overwritten when full, so effects never cost more than CAPACITY.

const CAPACITY := 700
const FRAME_BASE := 16  # fx atlas row 2 (8 columns): sizes 1..8

var count := 0
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var life := PackedFloat32Array()
var max_life := PackedFloat32Array()
var size := PackedInt32Array()
var color := PackedColorArray()
var drag := PackedFloat32Array()
var gravity := PackedFloat32Array()

var _cursor := 0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	pos.resize(CAPACITY)
	vel.resize(CAPACITY)
	life.resize(CAPACITY)
	max_life.resize(CAPACITY)
	size.resize(CAPACITY)
	color.resize(CAPACITY)
	drag.resize(CAPACITY)
	gravity.resize(CAPACITY)


## Spawns `n` particles around `p`. `dir` + `spread` (radians) aim the burst;
## a zero dir sprays in every direction.
func burst(p: Vector2, n: int, c: Color, speed: float, lifetime: float, particle_size: int,
		dir: Vector2 = Vector2.ZERO, spread: float = TAU, p_gravity: float = 0.0, p_drag: float = 4.0) -> void:
	var base_angle := dir.angle() if dir != Vector2.ZERO else 0.0
	for k in n:
		var i := _alloc()
		var angle := base_angle + _rng.randf_range(-spread * 0.5, spread * 0.5)
		pos[i] = p
		vel[i] = Vector2.from_angle(angle) * speed * _rng.randf_range(0.4, 1.0)
		var l := lifetime * _rng.randf_range(0.6, 1.0)
		life[i] = l
		max_life[i] = l
		size[i] = clampi(particle_size + _rng.randi_range(-1, 0), 0, 7)
		color[i] = c
		drag[i] = p_drag
		gravity[i] = p_gravity


func clear() -> void:
	count = 0


func _alloc() -> int:
	if count < CAPACITY:
		count += 1
		return count - 1
	_cursor = (_cursor + 1) % CAPACITY
	return _cursor


func update(dt: float) -> void:
	var P := pos
	var V := vel
	var L := life
	var i := 0
	while i < count:
		var l := L[i] - dt
		if l <= 0.0:
			var last := count - 1
			P[i] = P[last]
			V[i] = V[last]
			L[i] = L[last]
			max_life[i] = max_life[last]
			size[i] = size[last]
			color[i] = color[last]
			drag[i] = drag[last]
			gravity[i] = gravity[last]
			count = last
			continue
		L[i] = l
		var v := V[i] * exp(-drag[i] * dt)
		v.y += gravity[i] * dt
		V[i] = v
		P[i] = P[i] + v * dt
		i += 1
	pos = P
	vel = V
	life = L


func render(layer: InstanceLayer) -> void:
	var buf := layer.buffer
	var stride := layer.stride
	var n := mini(count, layer.capacity)
	for i in n:
		var p := pos[i]
		var c := color[i]
		var t := life[i] / max_life[i]
		var o := i * stride
		buf[o + 3] = roundf(p.x)
		buf[o + 7] = roundf(p.y)
		buf[o + 8] = c.r
		buf[o + 9] = c.g
		buf[o + 10] = c.b
		buf[o + 11] = c.a * t
		buf[o + 12] = float(FRAME_BASE + maxi(0, size[i] - int((1.0 - t) * 2.0)))
	layer.buffer = buf
	layer.commit(n)
