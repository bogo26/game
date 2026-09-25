class_name Hud
extends CanvasLayer
## In-game HUD. Milestone 5: team XP bar + level at the top centre.
## (Per-player panels and objectives arrive with the full HUD in milestone 6.)

const BAR_SIZE := Vector2(160, 4)

var _level := 1
var _xp := 0
var _needed := 1
var _flash := 0.0
var _root: Control
var _bar: Control
var _label: Label


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_root.add_child(_bar)
	_label = Label.new()
	var settings := LabelSettings.new()
	settings.font_size = 8
	settings.font_color = Color("ffe07a")
	settings.shadow_color = Color(0, 0, 0, 0.8)
	settings.shadow_offset = Vector2(1, 1)
	_label.label_settings = settings
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_label)
	Events.xp_changed.connect(_on_xp_changed)
	Events.team_level_up.connect(_on_level_up)
	_on_xp_changed(GameState.xp, GameState.xp_to_next(), GameState.team_level)


func _process(delta: float) -> void:
	var view := _root.get_viewport_rect().size
	_bar.position = Vector2(floorf((view.x - BAR_SIZE.x) * 0.5), 4)
	_bar.size = BAR_SIZE + Vector2(2, 2)
	_label.text = "LV %d" % _level
	_label.position = Vector2(_bar.position.x - _label.get_minimum_size().x - 4, 1)
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	_bar.queue_redraw()


func _on_xp_changed(current: int, needed: int, level: int) -> void:
	_xp = current
	_needed = maxi(needed, 1)
	_level = level


func _on_level_up(_level_reached: int) -> void:
	_flash = 0.6


func _draw_bar() -> void:
	_bar.draw_rect(Rect2(Vector2.ZERO, BAR_SIZE + Vector2(2, 2)), Color(0, 0, 0, 0.75))
	var fill := BAR_SIZE.x * clampf(float(_xp) / float(_needed), 0.0, 1.0)
	var color := Color("5ab0f0").lerp(Color.WHITE, _flash / 0.6)
	_bar.draw_rect(Rect2(Vector2(1, 1), Vector2(fill, BAR_SIZE.y)), color)
