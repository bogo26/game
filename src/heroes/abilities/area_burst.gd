class_name AreaBurstAbility
extends Ability
## Instant (or delayed, telegraphed) area effect around the hero, at the aim
## point, or over the whole screen: slams, novas, meteors, divine light.

enum Target { SELF, AIM_POINT, SCREEN }

@export var target: Target = Target.SELF
## For AIM_POINT: how far in front of the hero it lands.
@export var distance := 90.0
@export var radius := 48.0
@export var damage := 16.0
@export var knockback := 120.0
@export var stun_time := 0.0
@export var slow_time := 0.0
## Seconds between cast and impact (shows a telegraph).
@export var delay := 0.0
## Fraction of max HP restored to heroes in the area.
@export var heal_fraction := 0.0
@export var revive_allies := false
@export var color := Color.WHITE

var _pending_time := PackedFloat32Array()
var _pending_pos := PackedVector2Array()


func _activate(aim: Vector2) -> void:
	var p := hero.position
	if target == Target.AIM_POINT:
		p = world().grid.sweep_until_blocked(hero.position, hero.position + aim * distance, 2.0)
	if delay > 0.0:
		_pending_time.append(delay)
		_pending_pos.append(p)
		world().ground_fx.telegraph(p, _radius(), color, delay)
	else:
		_land(p)


func _tick_active(delta: float) -> void:
	var i := 0
	while i < _pending_time.size():
		_pending_time[i] -= delta
		if _pending_time[i] <= 0.0:
			var p := _pending_pos[i]
			_pending_time.remove_at(i)
			_pending_pos.remove_at(i)
			_land(p)
		else:
			i += 1


func is_active() -> bool:
	return not _pending_time.is_empty()


func cancel() -> void:
	# Already-cast meteors still land; nothing to cancel.
	pass


func _radius() -> float:
	return radius * area_scale()


func _land(p: Vector2) -> void:
	var w := world()
	var dmg := scaled_damage(damage)
	var stun := stun_time + mod(&"stun_time")
	var slow := slow_time + mod(&"slow_time")
	if target == Target.SCREEN:
		var view := w.camera.visible_rect()
		if damage > 0.0:
			w.damage_enemies_in_rect(view, dmg, view.get_center(), knockback, hero.slot, stun, slow)
		if heal_fraction > 0.0:
			w.heal_heroes(view.get_center(), INF, heal_fraction)
		w.fx.disc(view.get_center(), view.size.length() * 0.5, Color(color, 0.35), 0.35)
	else:
		var r := _radius()
		var hits := 0
		if damage > 0.0 or stun > 0.0 or slow > 0.0:
			hits = w.damage_enemies_in_circle(p, r, dmg, knockback, hero.slot, stun, slow)
		hero.on_hits(hits)
		if heal_fraction > 0.0:
			w.heal_heroes(p, r, heal_fraction)
		w.fx.disc(p, r, Color(color, 0.45), 0.2)
		w.fx.ring(p, r * 1.1, color, 0.3)
	if revive_allies:
		w.revive_all(0.5)
	w.shake(4.0 if radius >= 60.0 or target == Target.SCREEN else 2.0)
