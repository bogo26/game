class_name ReboundAbility
extends DashAbility
## Berserker legendary (Leap Slam): each landing bounces the Berserker into
## another leap onto the nearest enemy that isn't already underfoot: slams in
## a row, each one wider and harder than the last. With nobody in range the
## chain ends.

@export var hops := 3
@export var hop_range := 110.0
@export var hop_distance := 90.0
@export var hop_duration := 0.28
@export var area_growth := 1.2
@export var power_growth := 1.25
## Enemies closer than this were just slammed: the next hop looks past them.
@export var min_hop := 24.0

var _hop := 0


func _activate(aim: Vector2) -> void:
	_hop = 0
	super(aim)


func _finish_dash() -> void:
	_land_leap(pow(area_growth, _hop), pow(power_growth, _hop))
	_hop += 1
	if _hop >= hops:
		return
	var horde := world().horde
	var target := _next_target()
	if target == -1:
		return
	var to := horde.pos[target] - hero.position
	var dir := to.normalized() if to.length_squared() > 1.0 else hero.aim_dir
	hero.start_dash(dir, clampf(to.length(), 12.0, hop_distance), hop_duration, hop_duration + 0.1)
	_dash_dir = dir
	_leg_time = hop_duration
	_active = true
	_hit_uids.clear()


## The nearest enemy within hop_range that isn't underfoot, or -1.
func _next_target() -> int:
	var horde := world().horde
	horde.query_circle(hero.position, hop_range, _scratch)
	var best := -1
	var best_d2 := INF
	for j in _scratch:
		if horde.is_object(j):
			continue
		var d2 := hero.position.distance_squared_to(horde.pos[j])
		if d2 >= min_hop * min_hop and d2 < best_d2:
			best_d2 = d2
			best = j
	return best
