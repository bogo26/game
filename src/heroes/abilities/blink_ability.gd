class_name BlinkAbility
extends Ability
## Instant short-range teleport toward the aim direction (stops at walls).

@export var distance := 80.0
@export var iframes := 0.15
@export var arrival_damage := 0.0
@export var arrival_radius := 24.0
@export var color := Color(0.7, 0.5, 1.0)


func _activate(aim: Vector2) -> void:
	var w := world()
	var from := hero.position
	var to := w.grid.sweep_until_blocked(from, from + aim * distance * (1.0 + mod(&"distance_pct")), Hero.RADIUS)
	w.fx.ring(from + Vector2(0, -6), 12.0, color, 0.25)
	w.fx.line(from + Vector2(0, -6), to + Vector2(0, -6), Color(color, 0.5), 0.15)
	hero.teleport(to, iframes + mod(&"iframes"))
	w.fx.ring(to + Vector2(0, -6), 14.0, color, 0.3)
	var dmg := arrival_damage + mod(&"arrival_damage")
	if dmg > 0.0:
		hero.on_hits(w.damage_enemies_in_circle(to, arrival_radius, scaled_damage(dmg), 80.0, hero.slot))


func sound() -> StringName:
	return &"blink"
