class_name ShadowClonesAbility
extends Ability
## Rogue ultimate: shadow clones orbit the hero for a while and repeat every
## attack from their own positions (a melee cone toward the same aim).

@export var duration := 6.0
@export var clone_count := 3
@export var orbit_radius := 22.0
@export var damage_fraction := 0.8
@export var reach := 22.0
@export var arc_degrees := 80.0
@export var damage := 7.0

var _time_left := 0.0
var _ghosts: Array[Sprite2D] = []
var _angle := 0.0


func bind(p_hero: Hero, p_slot: Slot) -> void:
	super(p_hero, p_slot)
	hero.attack_performed.connect(_on_attack)


func _activate(_aim: Vector2) -> void:
	_time_left = duration + mod(&"duration")
	_clear_ghosts()
	for i in clone_count + int(mod(&"count")):
		var ghost := Sprite2D.new()
		ghost.texture = hero.sprite.texture
		ghost.hframes = hero.sprite.hframes
		ghost.modulate = Color(0.25, 0.15, 0.45, 0.75)
		world().entities.add_child(ghost)
		_ghosts.append(ghost)


func is_active() -> bool:
	return _time_left > 0.0


func cancel() -> void:
	_time_left = 0.0
	_clear_ghosts()


func _tick_active(delta: float) -> void:
	if _time_left <= 0.0:
		return
	_time_left -= delta
	_angle += delta * 3.0
	for i in _ghosts.size():
		var ghost := _ghosts[i]
		ghost.position = (_ghost_position(i) + Hero.SPRITE_FEET_OFFSET).round()
		ghost.frame = hero.sprite.frame
		ghost.flip_h = hero.sprite.flip_h
	if _time_left <= 0.0:
		_clear_ghosts()


func _ghost_position(i: int) -> Vector2:
	return hero.position + Vector2.from_angle(_angle + TAU * i / maxf(1.0, _ghosts.size())) * orbit_radius


func _on_attack(aim: Vector2) -> void:
	if not is_active():
		return
	var w := world()
	var arc := deg_to_rad(arc_degrees)
	for i in _ghosts.size():
		var p := _ghost_position(i) + Vector2(0, -4)
		hero.on_hits(w.damage_enemies_in_arc(p, aim, reach, arc * 0.5,
			scaled_damage(damage * damage_fraction), 30.0, hero.slot))
		w.fx.slash(p + aim * 3.0, reach * 0.8, aim.angle(), arc, Color(0.6, 0.4, 1.0, 0.8), 0.1)


func _clear_ghosts() -> void:
	for ghost in _ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_ghosts.clear()
