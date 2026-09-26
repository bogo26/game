class_name Interactable
extends Node2D
## A treasure chest or shrine from the layout (C / A). The first living hero
## to walk up to it uses it; the World applies the effect:
##   chest  -> an extra upgrade pick for the whole team ("TREASURE!")
##   shrine -> a blessing for the whole team, shown by the colour of its orb
## Both block walking on their tile.

enum Kind { CHEST, SHRINE }
enum Blessing { FURY, HASTE, LIFE, WRATH }

const CHEST_SPRITE := preload("res://assets/sprites/props/chest.png")
const SHRINE_SPRITE := preload("res://assets/sprites/props/shrine.png")
## A hero's feet this close to the tile centre use it (touching the tile).
const TOUCH_RANGE := 17.0
const BLESSING_NAMES: Array[String] = ["FURY", "HASTE", "LIFE", "WRATH"]
const BLESSING_COLORS: Array[Color] = [
	Color(1.0, 0.4, 0.3), Color(0.4, 0.9, 1.0), Color(0.45, 1.0, 0.5), Color(1.0, 0.85, 0.3)]
const BLESSING_HINTS: Array[String] = [
	"+50% damage", "+30% speed", "full heal", "smite the horde"]

var kind := Kind.CHEST
var cell := Vector2i.ZERO
var blessing := Blessing.FURY
var used := false
var _sprite: Sprite2D
var _time := 0.0
var _font: Font = preload("res://assets/fonts/pixel5x8.fnt")


func setup(p_kind: Kind, p_cell: Vector2i, p_blessing: Blessing = Blessing.FURY) -> void:
	kind = p_kind
	cell = p_cell
	blessing = p_blessing
	position = LevelGrid.cell_center(cell)


func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = CHEST_SPRITE if kind == Kind.CHEST else SHRINE_SPRITE
	_sprite.hframes = 2
	_sprite.centered = true
	# Stand on the tile: sprite bottom a few pixels below the tile centre.
	var frame_h := _sprite.texture.get_height()
	_sprite.offset = Vector2(0, 5 - frame_h * 0.5)
	add_child(_sprite)
	_refresh()


func label() -> String:
	return "TREASURE" if kind == Kind.CHEST else BLESSING_NAMES[blessing]


func color() -> Color:
	return Color(1.0, 0.82, 0.3) if kind == Kind.CHEST else BLESSING_COLORS[blessing]


func use() -> void:
	used = true
	_refresh()


func _refresh() -> void:
	if _sprite == null:
		return
	_sprite.frame = 1 if used else 0
	_sprite.modulate = Color.WHITE if kind == Kind.CHEST or used else BLESSING_COLORS[blessing].lightened(0.2)
	queue_redraw()


func _process(delta: float) -> void:
	if used:
		return
	_time += delta
	# Unused shrines bob their orb a little; chests glint.
	if kind == Kind.SHRINE:
		_sprite.position.y = roundf(sin(_time * 3.0) * 1.0)
	queue_redraw()


func _draw() -> void:
	if used:
		return
	# A soft halo and the blessing's name, so players know what they'd get.
	var c := color()
	var pulse := 0.5 + 0.5 * sin(_time * 4.0)
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 9.0, Color(c, 0.12 + 0.1 * pulse), true, -1.0, false)
	draw_set_transform(Vector2.ZERO)
	if kind == Kind.SHRINE:
		var text := BLESSING_NAMES[blessing]
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
		draw_string(_font, Vector2(-roundf(width * 0.5), -22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, c)
