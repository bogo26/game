class_name BloodbathAbility
extends BuffAbility
## Berserker legendary (Blood Frenzy): while the frenzy lasts, every enemy
## the Berserker kills bursts in a spray of blood that hurts the enemies
## around it and heals the Berserker. Kills by the spray burst too, so it
## chains through a pack.

@export var burst_radius := 28.0
@export var burst_damage := 12.0
@export var burst_heal := 2.0
@export var burst_knockback := 60.0
## At most this many bursts a frame (the rest wait, so chains ripple outward).
@export var bursts_per_frame := 6
@export var max_queued := 32

const BLOOD := Color(0.75, 0.05, 0.1)
const FRENZY_TINT := Color(1.3, 0.78, 0.78)

var _queue := PackedVector2Array()


func on_kill(at: Vector2) -> void:
	if is_active() and _queue.size() < max_queued:
		_queue.append(at)


func _tick_active(delta: float) -> void:
	super(delta)
	if _queue.is_empty():
		return
	var w := world()
	var r := burst_radius * area_scale()
	var n := mini(bursts_per_frame, _queue.size())
	for k in n:
		var p := _queue[k]
		hero.on_hits(w.damage_enemies_in_circle(p, r, scaled_damage(burst_damage), burst_knockback, hero.slot))
		hero.heal(burst_heal)
		w.fx.disc(p, r * 0.7, Color(BLOOD, 0.55), 0.2)
		w.fx.ring(p, r, Color(0.95, 0.2, 0.2), 0.25)
		w.particles.burst(p + Vector2(0, -4), 8, BLOOD, 90.0, 0.4, 2, Vector2.UP, PI * 1.2, 160.0)
	_queue = _queue.slice(n)
	Audio.play(&"explosion", -10.0, 0.7)


func sprite_modulate() -> Color:
	return FRENZY_TINT if is_active() else Color.WHITE


func cancel() -> void:
	super()
	_queue.clear()
