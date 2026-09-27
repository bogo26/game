class_name ChronoshiftAbility
extends BlinkAbility
## Mage legendary (Blink): the blink leaves an echo where the Mage stood. A
## moment later the Mage snaps back to it, undoing part of the damage taken
## in between (Blink Nova blasts both ends).

@export var echo_time := 2.5
## Share of the HP lost since the blink that the snap back restores.
@export var undo_share := 0.5
@export var return_iframes := 0.3

const HEAL_COLOR := Color(0.55, 1.0, 0.6)

var _echo_left := 0.0
var _echo_pos := Vector2.ZERO
var _echo_hp := 0.0
var _ghost: Sprite2D


func _activate(aim: Vector2) -> void:
	var from := hero.position
	var hp_before := hero.hp
	super(aim)
	_clear_echo()
	_echo_pos = from
	_echo_hp = hp_before
	_echo_left = echo_time
	var w := world()
	_ghost = Sprite2D.new()
	_ghost.texture = hero.sprite.texture
	_ghost.hframes = hero.sprite.hframes
	_ghost.frame = hero.sprite.frame
	_ghost.flip_h = hero.sprite.flip_h
	_ghost.modulate = Color(0.75, 0.55, 1.0, 0.55)
	_ghost.position = (from + Hero.SPRITE_FEET_OFFSET).round()
	w.entities.add_child(_ghost)
	w.warn_fx.telegraph(from, 10.0, color, echo_time, true)  # the clock runs down around the echo


func _tick_active(delta: float) -> void:
	if _echo_left <= 0.0:
		return
	_echo_left -= delta
	if is_instance_valid(_ghost):
		_ghost.modulate.a = 0.4 + 0.2 * sin(_echo_left * 12.0)
	if _echo_left <= 0.0:
		_snap_back()


func _snap_back() -> void:
	var w := world()
	var to := w.grid.nearest_open(_echo_pos)
	var from := hero.position
	w.fx.line(from + Vector2(0, -6), to + Vector2(0, -6), Color(color, 0.7), 0.2)
	w.fx.ring(from + Vector2(0, -6), 12.0, color, 0.25)
	hero.teleport(to, return_iframes)
	w.fx.implode(to + Vector2(0, -6), 18.0, color, 0.25)
	var restored := maxf(0.0, _echo_hp - hero.hp) * undo_share
	if restored >= 1.0:
		hero.heal(restored)
		w.numbers.add_text(to + Vector2(0, -16), "+%d" % roundi(restored), HEAL_COLOR)
	var dmg := arrival_damage + mod(&"arrival_damage")
	if dmg > 0.0:
		hero.on_hits(w.damage_enemies_in_circle(to, arrival_radius, scaled_damage(dmg), 80.0, hero.slot))
	Audio.play(&"blink", 0.0, 0.8)
	_clear_echo()


func _clear_echo() -> void:
	_echo_left = 0.0
	if is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null


func is_active() -> bool:
	return _echo_left > 0.0


func cancel() -> void:
	_clear_echo()
