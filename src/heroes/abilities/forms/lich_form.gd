class_name LichFormAbility
extends SummonAbility
## Necromancer legendary (Army of the Dead): instead of calling an army, the
## Necromancer becomes a Lich for a while: bigger, floating and ghostly green,
## taking less damage; Soul Bolts fire in threes, and every enemy the
## Necromancer (or a minion) kills rises as a skeleton, up to the army's cap
## (Endless Legion raises it, Sturdy Bones toughens them).

@export var duration := 10.0
@export var lich_scale := 1.3
@export var lich_damage_taken := 0.75
@export var extra_bolts := 2
@export var float_height := 4.0
## Raised skeletons stay this long after the form ends.
@export var linger := 2.0
@export var raise_per_frame := 3

const LICH_TINT := Color(0.75, 1.25, 0.95)
const AURA := Color(0.55, 1.0, 0.8)
const MAX_QUEUED := 16

var _left := 0.0
var _raise := PackedVector2Array()
var _aura_in := 0.0


func _activate(_aim: Vector2) -> void:
	_left = duration + mod(&"duration")
	_raise.clear()
	_prune()
	var w := world()
	w.fx.implode(hero.position + Vector2(0, -8), 40.0, AURA, 0.35)
	w.particles.burst(hero.position + Vector2(0, -8), 16, AURA, 80.0, 0.6, 2, Vector2.UP, PI, -40.0)


func on_kill(at: Vector2) -> void:
	if _left > 0.0 and _raise.size() < MAX_QUEUED:
		_raise.append(at)


func _tick_active(delta: float) -> void:
	if _left <= 0.0:
		return
	_left -= delta
	hero.air_height = float_height + sin(_left * 4.0) * 1.5
	var w := world()
	var n := mini(raise_per_frame, _raise.size())
	for k in n:
		var m := _summon(_raise[k])
		m.lifetime = _left + linger
		w.particles.burst(m.position, 6, AURA, 50.0, 0.5, 2, Vector2.UP, 0.8, -40.0)
	_raise = _raise.slice(n)
	if n > 0:
		Audio.play(&"bones", -6.0, 1.2)
	_aura_in -= delta
	if _aura_in <= 0.0:
		_aura_in = 0.4
		w.fx.ring(hero.position + Vector2(0, -6), 14.0, AURA, 0.4)
	if _left <= 0.0:
		_end()


func _end() -> void:
	_left = 0.0
	hero.air_height = 0.0
	_raise.clear()


func is_active() -> bool:
	return _left > 0.0


func cancel() -> void:
	if _left > 0.0:
		_end()


func sprite_scale() -> float:
	return lich_scale if _left > 0.0 else 1.0


func damage_taken_factor() -> float:
	return lich_damage_taken if _left > 0.0 else 1.0


func shot_bonus() -> float:
	return float(extra_bolts) if _left > 0.0 else 0.0


func sprite_modulate() -> Color:
	return LICH_TINT if _left > 0.0 else Color.WHITE
