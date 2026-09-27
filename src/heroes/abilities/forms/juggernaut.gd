class_name JuggernautAbility
extends DashAbility
## Knight legendary (Shield Charge): the charge scoops up everything in its
## path and carries it along on the shield, then slams it all down in a
## shockwave: harder the more it carried, and harder still when a wall
## stopped it. Anything carried off a chasm's edge goes over it.

@export var max_carried := 10
@export var carry_offset := 12.0
@export var crash_radius := 34.0
@export var crash_damage := 14.0
@export var crash_per_enemy := 3.0
@export var crash_stun := 0.6
@export var crash_knockback := 180.0
## Stopped short by a wall: the crash hits this much harder and stuns longer.
@export var wall_bonus := 1.5
@export var wall_stun := 0.5

const DEBRIS := Color(0.72, 0.66, 0.58)
## A charge that got less than this share of its way was stopped by a wall.
const WALL_SHARE := 0.7

var _carried := PackedInt32Array()  # enemy uids, in the order they were picked up
var _hints := PackedInt32Array()
var _start := Vector2.ZERO
var _expected := 0.0


func _activate(aim: Vector2) -> void:
	_start = hero.position
	_expected = distance * (1.0 + mod(&"distance_pct"))
	_carried.clear()
	_hints.clear()
	super(aim)


## Everything the shield touches is picked up (not bosses, props or nests).
func _hit_passed() -> void:
	var w := world()
	var horde := w.horde
	horde.query_circle(hero.position + _dash_dir * 4.0, hit_radius, _scratch)
	for j in _scratch:
		var id := horde.uid[j]
		if _hit_uids.has(id):
			continue
		_hit_uids[id] = true
		if damage > 0.0:
			w.hit_enemy(j, scaled_damage(damage), Vector2.ZERO, hero.slot, hero)
		if horde.is_mobile(j) and horde.hp[j] > 0.0 and _carried.size() < max_carried:
			_carried.append(id)
			_hints.append(j)
	_carry()


## Carried enemies ride in rows on the shield, just ahead of the Knight.
func _carry() -> void:
	var w := world()
	var horde := w.horde
	var side := _dash_dir.orthogonal()
	var k := 0
	while k < _carried.size():
		var j := horde.index_of_uid(_carried[k], _hints[k])
		if j == -1 or horde.hp[j] <= 0.0 or horde.is_falling(j):
			_carried.remove_at(k)
			_hints.remove_at(k)
			continue
		_hints[k] = j
		var spot := hero.position + _dash_dir * (carry_offset + 6.0 * (k / 5)) + side * (float(k % 5) - 2.0) * 4.0
		if w.grid.terrain_at(spot) == LevelGrid.Terrain.CHASM:
			horde.push(j, _dash_dir * 200.0, hero.slot)  # over the edge it goes
			_carried.remove_at(k)
			_hints.remove_at(k)
			continue
		if not w.grid.is_solid_at(spot):
			horde.relocate(j, spot)
		k += 1


func _finish_dash() -> void:
	var w := world()
	_carry()
	var carried := _carried.size()
	var walled := hero.position.distance_to(_start) < _expected * WALL_SHARE
	var dmg := scaled_damage(crash_damage + crash_per_enemy * carried + mod(&"end_burst"))
	var stun := crash_stun + mod(&"stun_time")
	if walled:
		dmg *= wall_bonus
		stun += wall_stun
	var r := crash_radius * area_scale()
	var center := hero.position + _dash_dir * 6.0
	hero.on_hits(w.damage_enemies_in_circle(center, r, dmg, crash_knockback, hero.slot, stun))
	w.fx.disc(center, r, Color(color, 0.45), 0.2)
	w.fx.ring(center, r * 1.15, color, 0.3)
	w.particles.burst(center, 12 + carried * 2, DEBRIS, 120.0, 0.45, 3, Vector2.UP, PI * 1.5, 160.0)
	w.shake(5.0 if walled else 3.0 + carried * 0.2)
	Audio.play(&"slam", 0.0, 0.85 if walled else 1.0)
	if walled:
		Audio.play(&"break", -2.0, 0.7)
	_carried.clear()
	_hints.clear()


func cancel() -> void:
	super()
	_carried.clear()
	_hints.clear()
