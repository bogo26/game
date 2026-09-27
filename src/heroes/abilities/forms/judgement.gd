class_name JudgementAbility
extends AreaBurstAbility
## Cleric legendary (Divine Light): it still revives and heals the whole
## team, and then, instead of smiting the whole screen at once, calls pillars
## of light down on the toughest enemies on screen one after another: bosses
## first.

@export var pillars := 12
@export var pillar_interval := 0.12
@export var pillar_damage := 90.0
@export var pillar_radius := 22.0
@export var pillar_stun := 0.6
@export var pillar_knockback := 60.0

const PILLAR_HEIGHT := 150.0

var _left := 0
var _next_in := 0.0
## Enemies already struck this cast (uid -> true): the next pillar picks another.
var _struck: Dictionary = {}


func _land(_p: Vector2) -> void:
	var w := world()
	var view := w.camera.visible_rect()
	if heal_fraction > 0.0:
		w.heal_heroes(view.get_center(), INF, heal_fraction)
	if revive_allies:
		w.revive_all(0.5, hero.slot)
	w.fx.disc(view.get_center(), view.size.length() * 0.5, Color(color, 0.25 * Settings.flash_scale()), 0.3)
	w.shake(2.0)
	_left = pillars + int(mod(&"count"))
	_next_in = 0.0
	_struck.clear()


func _tick_active(delta: float) -> void:
	super(delta)
	if _left <= 0:
		return
	_next_in -= delta
	while _next_in <= 0.0 and _left > 0:
		_next_in += pillar_interval
		_left -= 1
		_strike()


## The toughest enemy on screen not struck yet (else the toughest of all).
func _pick_target() -> int:
	var w := world()
	var horde := w.horde
	var view := w.camera.visible_rect()
	var best := -1
	var best_hp := -1.0
	var again := -1
	var again_hp := -1.0
	for i in horde.count:
		var hp := horde.hp[i]
		if hp <= 0.0 or horde.hidden[i] != 0 or horde.is_falling(i) or horde.is_object(i) \
				or not view.has_point(horde.pos[i]):
			continue
		if _struck.has(horde.uid[i]):
			if hp > again_hp:
				again_hp = hp
				again = i
		elif hp > best_hp:
			best_hp = hp
			best = i
	return best if best != -1 else again


func _strike() -> void:
	var j := _pick_target()
	if j == -1:
		return
	var w := world()
	var horde := w.horde
	_struck[horde.uid[j]] = true
	var at := horde.pos[j]
	var r := pillar_radius * area_scale()
	hero.on_hits(w.damage_enemies_in_circle(at, r, scaled_damage(pillar_damage), pillar_knockback, hero.slot,
		pillar_stun))
	w.fx.beam(at + Vector2(randf_range(-4.0, 4.0), -PILLAR_HEIGHT), at, 10.0, color, 0.3)
	w.fx.disc(at, r, Color(color, 0.5), 0.2)
	w.fx.ring(at, r * 1.2, Color(1, 1, 0.9), 0.3)
	w.particles.burst(at + Vector2(0, -6), 8, color, 90.0, 0.4, 2, Vector2.UP, PI, -30.0)
	Audio.play(&"thunder", -6.0, 1.3)


func is_active() -> bool:
	return _left > 0 or super()


func cancel() -> void:
	_left = 0
