class_name TorchLights
extends Node2D
## Warm light around wall torches (and a dull glow over lava), drawn with
## additive blending above the floor and walls but under everything else.
## Flickers a little.

const GLOW := preload("res://assets/sprites/fx/glow.png")
const LAVA_GLOW_SIZE := 72.0

var _torches: Array[Vector2] = []
var _lava: Array[Vector2] = []
var _time := 0.0


func _ready() -> void:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


func setup(torches: Array[Vector2], lava: Array[Vector2]) -> void:
	_torches = torches.duplicate()
	_lava = lava.duplicate()
	queue_redraw()


func _process(delta: float) -> void:
	if _torches.is_empty() and _lava.is_empty():
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	var size := Vector2(Level.TORCH_GLOW_SIZE, Level.TORCH_GLOW_SIZE)
	for i in _torches.size():
		var color := Level.TORCH_GLOW_COLOR
		color.a *= 1.0 + 0.14 * sin(_time * 9.0 + i * 1.7) + 0.08 * sin(_time * 23.0 + i * 0.9)
		draw_texture_rect(GLOW, Rect2(_torches[i] - size * 0.5, size), false, color)
	var lava_size := Vector2(LAVA_GLOW_SIZE, LAVA_GLOW_SIZE)
	for i in _lava.size():
		var color := Level.LAVA_GLOW_COLOR
		color.a *= 1.0 + 0.25 * sin(_time * 2.0 + i * 0.7)
		draw_texture_rect(GLOW, Rect2(_lava[i] - lava_size * 0.5, lava_size), false, color)
