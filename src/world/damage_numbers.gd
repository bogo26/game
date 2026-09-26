class_name DamageNumbers
extends Node2D
## Floating damage numbers drawn by one node (no Label per number). Only
## notable hits get a number and at most MAX_NUMBERS float at once, so a
## 300-enemy fight stays readable.

const MAX_NUMBERS := 40
const LIFETIME := 0.7
const RISE := 18.0
const CRIT_COLOR := Color(1.0, 0.72, 0.15)

var _pos := PackedVector2Array()
var _text := PackedStringArray()
var _color := PackedColorArray()
var _size := PackedInt32Array()
var _age := PackedFloat32Array()
var _crit := PackedByteArray()
var _font: Font = preload("res://assets/fonts/pixel5x8.fnt")


func _ready() -> void:
	z_index = 5


## `big` numbers use the 2x font (huge hits).
func add(p: Vector2, amount: float, color: Color, big: bool = false) -> void:
	_push(p, str(int(round(amount))), color, 16 if big else 8, false)


## Critical hit: gold, 2x font, "!" - always shown, and never pushed out by
## ordinary numbers.
func add_crit(p: Vector2, amount: float) -> void:
	_push(p, "%d!" % int(round(amount)), CRIT_COLOR, 16, true)


## A word that floats up like a number (TREASURE!, FURY...): big, and
## never pushed out.
func add_text(p: Vector2, text: String, color: Color) -> void:
	_push(p, text, color, 16, true)


func count() -> int:
	return _age.size()


func crit_count() -> int:
	var n := 0
	for c in _crit:
		n += c
	return n


func _push(p: Vector2, text: String, color: Color, size: int, crit: bool) -> void:
	if _pos.size() >= MAX_NUMBERS:
		var victim := 0
		for i in _crit.size():  # evict the oldest ordinary number first
			if _crit[i] == 0:
				victim = i
				break
		if _crit[victim] != 0 and not crit:
			return  # full of crits: skip this ordinary number
		_remove(victim)
	# Jitter so simultaneous hits on the same spot don't stack exactly.
	_pos.append(p + Vector2(randf_range(-6, 6), -10.0 + randf_range(-6.0, 2.0) if crit else -10.0))
	_text.append(text)
	_color.append(color)
	_size.append(size)
	_age.append(0.0)
	_crit.append(1 if crit else 0)


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
	_crit.remove_at(i)


func _draw() -> void:
	for i in _age.size():
		var t := _age[i] / LIFETIME
		var rise := RISE * (1.4 if _crit[i] != 0 else 1.0)
		var p := (_pos[i] - Vector2(0, rise * sqrt(t))).round()
		var c := _color[i]
		c.a = 1.0 - maxf(0.0, t - 0.6) / 0.4
		var width := _font.get_string_size(_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _size[i]).x
		var at := p - Vector2(roundf(width * 0.5), 0)
		draw_string_outline(_font, at, _text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _size[i], 2, Color(0, 0, 0, c.a))
		draw_string(_font, at, _text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, _size[i], c)
