class_name Hud
extends CanvasLayer
## In-game HUD:
## - top centre: team XP bar, level, and the current objective
## - corners: one panel per player (P1 top-left, P2 top-right, P3 bottom-left,
##   P4 bottom-right) with portrait, HP, special/movement cooldowns and the
##   ultimate meter; empty slots show a join prompt in drop-in mode
## - an arrow at the screen edge pointing at an off-screen objective
## - boss HP bar during the boss fight, and the controller-disconnected notice

const BAR_SIZE := Vector2(160, 4)
const PANEL_SIZE := Vector2(112, 28)
const EDGE := 4.0
const HERO_SHEET := "res://assets/sprites/heroes/%s.png"

var world: World
var _level := 1
var _xp := 0
var _needed := 1
var _flash := 0.0
var _time := 0.0
var _canvas: Control
var _level_label: Label
var _objective_label: Label
var _center_label: Label
var _boss_label: Label
var _slot_labels: Array[Label] = []
var _portraits: Dictionary = {}  # hero_id -> Texture2D


func setup(p_world: World) -> void:
	world = p_world


func _ready() -> void:
	layer = 10
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	_level_label = _label(Color("ffe07a"))
	_objective_label = _label(Color(0.92, 0.92, 0.96))
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label = _label(Color.WHITE, 16)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label = _label(Color("ff8a70"))
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for i in InputRouter.MAX_PLAYERS:
		_slot_labels.append(_label(GameState.player_color(i)))
	Events.xp_changed.connect(_on_xp_changed)
	Events.team_level_up.connect(func(_l: int) -> void: _flash = 0.6)
	_on_xp_changed(GameState.xp, GameState.xp_to_next(), GameState.team_level)


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	var view := _canvas.get_viewport_rect().size
	var bar_x := floorf((view.x - BAR_SIZE.x) * 0.5)
	_level_label.text = "LV %d" % _level
	_level_label.position = Vector2(bar_x - _level_label.get_minimum_size().x - 4, 1)
	if world:
		_objective_label.text = world.director.objective
	_objective_label.position = Vector2(0, 11)
	_objective_label.size = Vector2(view.x, 10)
	_update_slot_labels(view)
	_update_center_message(view)
	_update_boss_label(view)
	_canvas.queue_redraw()


func _on_xp_changed(current: int, needed: int, level: int) -> void:
	_xp = current
	_needed = maxi(needed, 1)
	_level = level


# --- labels ----------------------------------------------------------------------------------

func _panel_origin(slot: int, view: Vector2) -> Vector2:
	var right := slot % 2 == 1
	var bottom := slot >= 2
	return Vector2(
		view.x - PANEL_SIZE.x - EDGE if right else EDGE,
		view.y - PANEL_SIZE.y - EDGE if bottom else EDGE)


func _update_slot_labels(view: Vector2) -> void:
	for i in _slot_labels.size():
		var label := _slot_labels[i]
		var hero := world.hero_for_slot(i) if world else null
		var origin := _panel_origin(i, view)
		if hero:
			label.text = "P%d %s" % [i + 1, hero.data.display_name.to_upper()]
			if hero.is_downed():
				label.text += "  DOWN!"
			label.position = origin + Vector2(20, 0)
		elif world and world.allow_drop_in and not InputRouter.get_player(i).is_assigned():
			label.text = "P%d  ENTER / (A) to join" % (i + 1)
			label.position = origin + Vector2(0, PANEL_SIZE.y - 10 if i >= 2 else 0)
		else:
			label.text = ""


func _update_center_message(view: Vector2) -> void:
	var lost := PackedStringArray()
	for i in InputRouter.MAX_PLAYERS:
		var p := InputRouter.get_player(i)
		if p.is_assigned() and not p.connected:
			lost.append("P%d" % (i + 1))
	_center_label.text = "" if lost.is_empty() else \
		"%s controller disconnected\nreconnect it, or press A on another controller" % ", ".join(lost)
	_center_label.position = Vector2(0, view.y * 0.5 - 20)
	_center_label.size = Vector2(view.x, 40)


func _update_boss_label(view: Vector2) -> void:
	var boss := world.boss if world else null
	_boss_label.text = "DEMON LORD" if boss and is_instance_valid(boss) else ""
	_boss_label.position = Vector2(0, view.y - 22)
	_boss_label.size = Vector2(view.x, 10)


# --- drawing ---------------------------------------------------------------------------------

func _draw_hud() -> void:
	var view := _canvas.get_viewport_rect().size
	# Team XP bar.
	var bar_pos := Vector2(floorf((view.x - BAR_SIZE.x) * 0.5), 4)
	_canvas.draw_rect(Rect2(bar_pos, BAR_SIZE + Vector2(2, 2)), Color(0, 0, 0, 0.75))
	var fill := BAR_SIZE.x * clampf(float(_xp) / float(_needed), 0.0, 1.0)
	_canvas.draw_rect(Rect2(bar_pos + Vector2(1, 1), Vector2(fill, BAR_SIZE.y)),
		Color("5ab0f0").lerp(Color.WHITE, _flash / 0.6))
	if world == null:
		return
	for hero in world.heroes:
		_draw_player_panel(hero, _panel_origin(hero.slot, view))
	_draw_objective_arrow(view)
	_draw_boss_bar(view)


func _draw_player_panel(hero: Hero, origin: Vector2) -> void:
	var c := hero.color
	_canvas.draw_rect(Rect2(origin, PANEL_SIZE), Color(0.03, 0.03, 0.06, 0.62))
	_canvas.draw_rect(Rect2(origin, PANEL_SIZE), Color(c, 0.8), false, 1.0)
	var portrait := _portrait(hero.hero_id)
	if portrait:
		var tint := Color(0.5, 0.5, 0.5) if hero.is_downed() else Color.WHITE
		_canvas.draw_texture_rect_region(portrait, Rect2(origin + Vector2(2, 6), Vector2(16, 16)),
			Rect2(0, 0, 16, 16), tint)
	var x := origin.x + 20
	var w := PANEL_SIZE.x - 24
	# HP
	var hp_ratio := hero.hp / hero.max_hp if hero.max_hp > 0.0 else 0.0
	var hp_color := Color(0.35, 0.9, 0.4) if hp_ratio > 0.3 else Color(1, 0.3, 0.3)
	if hero.is_downed():
		hp_ratio = hero.revive_progress / Hero.REVIVE_TIME
		hp_color = Color(0.9, 0.9, 0.5)
	_bar(Vector2(x, origin.y + 11), w, 3, hp_ratio, hp_color)
	# Special / movement cooldowns and the ultimate meter.
	var third := floorf((w - 4) / 3.0)
	_bar(Vector2(x, origin.y + 17), third, 2, 1.0 - hero.special().cooldown_ratio(), Color("f2c84a"))
	_bar(Vector2(x + third + 2, origin.y + 17), third, 2, 1.0 - hero.movement().cooldown_ratio(), Color("5ad8f0"))
	var ult_color := Color("c070f0")
	if hero.ult_charge >= 1.0:
		ult_color = ult_color.lerp(Color.WHITE, 0.5 + 0.5 * sin(_time * 10.0))
	_bar(Vector2(x + (third + 2) * 2, origin.y + 17), third, 2, hero.ult_charge, ult_color)
	_canvas.draw_string(_canvas.get_theme_default_font(), Vector2(x, origin.y + 27), "SPC  MOV  ULT",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.5, 0.5, 0.56))


func _bar(pos: Vector2, width: float, height: float, ratio: float, color: Color) -> void:
	_canvas.draw_rect(Rect2(pos - Vector2(1, 1), Vector2(width + 2, height + 2)), Color(0, 0, 0, 0.8))
	_canvas.draw_rect(Rect2(pos, Vector2(width * clampf(ratio, 0.0, 1.0), height)), color)


func _draw_objective_arrow(view: Vector2) -> void:
	var target := world.director.objective_target
	if not target.is_finite():
		return
	var cam := world.camera.global_position
	var rel := target - cam
	var half := view * 0.5 - Vector2(18, 24)
	if absf(rel.x) <= half.x and absf(rel.y) <= half.y:
		return
	var scale := minf(half.x / maxf(absf(rel.x), 0.001), half.y / maxf(absf(rel.y), 0.001))
	var pos := (view * 0.5 + rel * scale).round()
	var dir := rel.normalized()
	var side := dir.orthogonal()
	var pulse := 1.0 + 0.25 * sin(_time * 6.0)
	var tip := pos + dir * 6.0 * pulse
	var pts := PackedVector2Array([tip, pos - dir * 3.0 + side * 4.0, pos - dir * 3.0 - side * 4.0])
	_canvas.draw_colored_polygon(pts, Color("ffe07a"))
	_canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.8), 1.0)


func _draw_boss_bar(view: Vector2) -> void:
	var boss := world.boss
	if boss == null or not is_instance_valid(boss):
		return
	var w := minf(260.0, view.x - 80.0)
	var pos := Vector2(floorf((view.x - w) * 0.5), view.y - 12)
	_bar(pos, w, 4, boss.hp_ratio(), Color("e0402a"))


func _portrait(hero_id: StringName) -> Texture2D:
	if not _portraits.has(hero_id):
		_portraits[hero_id] = load(HERO_SHEET % hero_id)
	return _portraits[hero_id]


func _label(color: Color, size: int = 8) -> Label:
	var label := Label.new()
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	settings.shadow_color = Color(0, 0, 0, 0.85)
	settings.shadow_offset = Vector2(1, 1)
	if size > 8:
		settings.outline_size = 4
		settings.outline_color = Color.BLACK
	label.label_settings = settings
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label
