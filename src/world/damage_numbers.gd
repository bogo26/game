class_name DamageNumbers
extends Node2D
## Floating damage numbers drawn by one node (no Label per number). Only
## notable hits get a number and at most MAX_NUMBERS float at once, so a
## 300-enemy fight stays readable.

const MAX_NUMBERS := 40
const LIFETIME := 0.7
const RISE := 18.0

var _pos := PackedVector2Array()
var _text := PackedStringArray()
var _color := PackedColorArray()
var _size := PackedInt32Array()
var _age := PackedFloat32Array()
var _font: Font = preload("res://assets/fonts/pixel5x8.fnt")


func _ready() -> void:
	z_index = 5


## `big` numbers use the 2x font (crits / huge hits).
func add(p: Vector2, amount: float, color: Color, big: bool = false) -> void:
	if _pos.size() >= MAX_NUMBERS:
		_remove(0)
	_pos.append(p + Vector2(randf_range(-4, 4), -10))
	_text.append(str(int(round(amount))))
	_color.append(color)
	_size.append(16 if big else 8)
	_age.append(0.0)


func tick(delta: float) -> void:
	var i := 0
	while i < _age.size():
		_age[i] += delta
		if _age[i] >= LIFETIME:
			_remove(i)
		else:
			i += 1
	queue_redraw()


func _remove(i: int) -> void:
	_pos.remove_at(i)
	_text.remove_at(i)
	_color.remove_at(i)
	_size.remove_at(i)
	_age.remove_at(i)


func _draw() -> void:
	for i in _age.size():
		var t := _age[i] / LIFETIME
		var p := (_pos[i] - Vector2(0, RISE * sqrt(t))).round()
		var c := _color[i]
		c.a = 1.0 - maxf(0.0, t - 0.6) / 0.4
		var width := _font.get_string_size(_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _size[i]).x
		var at := p - Vector2(roundf(width * 0.5), 0)
		draw_string_outline(_font, at, _text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _size[i], 2, Color(0, 0, 0, c.a))
		draw_string(_font, at, _text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _size[i], c)
