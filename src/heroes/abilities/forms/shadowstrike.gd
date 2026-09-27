class_name ShadowstrikeAbility
extends DashAbility
## Rogue legendary (Shadow Step): the Rogue vanishes and reappears behind the
## enemy nearest the aim, stabbing it for a guaranteed critical hit and
## marking every enemy around it. With nobody in reach it's a Shadow Step.

@export var strike_range := 110.0
@export var strike_damage := 24.0
@export var mark_radius := 30.0
## How far past the target (beyond its body) the Rogue appears.
@export var behind := 9.0

const SHADOW := Color(0.35, 0.2, 0.55)
const STAB := Color(0.85, 0.75, 1.0)


func _activate(aim: Vector2) -> void:
	var target := _target(aim)
	if target == -1:
		super(aim)
		return
	var w := world()
	var horde := w.horde
	var from := hero.position
	var at := horde.pos[target]
	var through := (at - from).normalized() if at.distance_squared_to(from) > 1.0 else aim
	var spot := w.grid.nearest_open(at + through * (behind + horde.t_radius[horde.type[target]]))
	if not w.grid.line_of_sight(at, spot):
		spot = w.grid.nearest_open(at)
	_puff(from)
	hero.teleport(spot, iframes + mod(&"iframes"))
	_puff(spot)
	w.fx.line(from + Vector2(0, -6), spot + Vector2(0, -6), Color(SHADOW, 0.6), 0.2)
	horde.apply_mark(target, mark_time)  # marked: the stab can't miss the crit
	w.hit_enemy(target, scaled_damage(strike_damage), through * 40.0, hero.slot, hero)
	w.fx.slash(at + Vector2(0, -6), 10.0, (-through).angle(), 1.4, STAB, 0.15)
	horde.query_circle(at, mark_radius * area_scale(), _scratch)
	for j in _scratch:
		if not horde.is_object(j):
			horde.apply_mark(j, mark_time)
	hero.on_hits(1)
	Audio.play(&"slash", 0.0, 1.2)


## The enemy nearest a point half way along the aim, within reach and in
## sight, or -1.
func _target(aim: Vector2) -> int:
	var w := world()
	var horde := w.horde
	var reach := strike_range * (1.0 + mod(&"distance_pct"))
	var probe := hero.position + aim * reach * 0.5
	horde.query_circle(hero.position, reach, _scratch)
	var best := -1
	var best_d2 := INF
	for j in _scratch:
		if horde.is_object(j) or not w.grid.line_of_sight(hero.position, horde.pos[j]):
			continue
		var d2 := probe.distance_squared_to(horde.pos[j])
		if d2 < best_d2:
			best_d2 = d2
			best = j
	return best


func _puff(p: Vector2) -> void:
	world().particles.burst(p + Vector2(0, -6), 10, SHADOW, 50.0, 0.4, 3, Vector2.UP, PI, -20.0)
	world().fx.disc(p + Vector2(0, -6), 8.0, Color(SHADOW, 0.6), 0.2)


func sound() -> StringName:
	return &"blink"
