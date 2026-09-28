class_name Hud
extends CanvasLayer
## In-game HUD:
## - top centre: team XP bar, level (with "+2" when pick rounds are waiting
##   for an arena fight to end), team lives, and the current objective
## - big callouts in the middle (WAVE 2/3, SECOND WIND!)
## - corners: one panel per player (P1 top-left, P2 top-right, P3 bottom-left,
##   P4 bottom-right) with portrait, HP, special/movement cooldowns and the
##   ultimate meter; empty slots show a join prompt in drop-in mode
## - an arrow at the screen edge pointing at an off-screen objective
## - the boss's name (and state: "SHIELDED", "SUBMERGED") and HP bar during a
##   boss fight, and the controller-disconnected notice
## - the minimap while a player holds MAP (plus a hint at the start of a level)
## - by the team hearts, the keep-moving clock: the time left to reach the
##   next objective, then how restless the horde has grown (see
##   LevelDirector.RESTLESS_AFTER)

const BAR_SIZE := Vector2(160, 4)
const PANEL_SIZE := Vector2(112, 28)
const EDGE := 4.0
const HERO_SHEET := "res://assets/sprites/heroes/%s.png"
const MAP_HINT_TIME := 8.0
const CAPTIONS: Array[String] = ["SPC", "MOV", "ULT"]
## A player's panel flashes this long when they get hit.
const HURT_FLASH := 0.3
const CALLOUT_TIME := 1.6
const HEART_COLOR := Color(0.95, 0.3, 0.35)
## The controls card (a player's four buttons) shows this long at the start of
## a run, or until they've used their attack, special and movement ability.
const CONTROLS_CARD_TIME := 20.0
const CARD_SIZE := Vector2(112, 42)
const CARD_ACTIONS: Array[PlayerInput.Action] = [PlayerInput.Action.ATTACK, PlayerInput.Action.SPECIAL,
	PlayerInput.Action.MOVEMENT, PlayerInput.Action.ULTIMATE]
const TIP_TIME := 6.0
## The objective arrow: its tip reaches this far ahead of its middle (pulsing
## a quarter either way), its base sits this far behind, this wide either side.
const ARROW_TIP := 9.0
const ARROW_BACK := 5.0
const ARROW_HALF_WIDTH := 6.0
## The keep-moving clock: grey, then gold and blinking for its last
## CLOCK_HURRY seconds; red once the horde is restless.
const CLOCK_COLOR := Color(0.72, 0.72, 0.78)
const CLOCK_HURRY := 10.0
const CLOCK_HURRY_COLOR := Color("ffe07a")
const RESTLESS_COLOR := Color(1.0, 0.45, 0.3)

var world: World
var minimap: Minimap
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
var _hint_label: Label
var _blessing_label: Label
var _hint_left := MAP_HINT_TIME
var _slot_labels: Array[Label] = []
var _hurt_flash := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _callout_label: Label
var _callout_left := 0.0
var _held_label: Label
var _clock_label: Label
var _card_time := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _tip_label: Label
var _tip_left := 0.0
var _portraits: Dictionary = {}  # hero_id -> Texture2D


func setup(p_world: World) -> void:
	world = p_world
	if minimap:
		minimap.setup(world)


func _ready() -> void:
	layer = 10
	# Keeps updating while the level is paused (e.g. the controller-disconnected notice).
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_hint_label = _label(Color(0.75, 0.75, 0.82))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blessing_label = _label(Color.WHITE)
	_blessing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout_label = _label(Color("ffe07a"), 16)
	_callout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_held_label = _label(Color("ffe07a"))
	_clock_label = _label(CLOCK_COLOR)
	_tip_label = _label(Color(0.7, 0.95, 1.0))
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Events.hero_spawned.connect(_on_hero_spawned)
	for i in InputRouter.MAX_PLAYERS:
		_slot_labels.append(_label(GameState.player_color(i)))
	minimap = Minimap.new()
	add_child(minimap)
	if world:
		minimap.setup(world)
	Events.xp_changed.connect(_on_xp_changed)
	Events.team_level_up.connect(func(_l: int) -> void: _flash = 0.6)
	Events.hero_damaged.connect(_on_hero_damaged)
	_on_xp_changed(GameState.xp, GameState.xp_to_next(), GameState.team_level)


func _process(delta: float) -> void:
	_time += delta
	_flash = maxf(0.0, _flash - delta)
	for k in _hurt_flash.size():
		_hurt_flash[k] = maxf(0.0, _hurt_flash[k] - delta)
	var view := _canvas.get_viewport_rect().size
	var bar_x := floorf((view.x - BAR_SIZE.x) * 0.5)
	_level_label.text = "LV %d" % _level
	_level_label.position = Vector2(bar_x - _level_label.get_minimum_size().x - 4, 1)
	if world:
		_objective_label.text = world.director.objective
	_objective_label.position = Vector2(0, 11)
	_objective_label.size = Vector2(view.x, 10)
	_hint_left = maxf(0.0, _hint_left - delta)
	if minimap.is_requested():
		_hint_left = 0.0  # they found it
	if _hint_left > 0.0:
		_hint_label.text = "Hold %s for the map" % _glyphs_for(PlayerInput.Action.MAP)
	_hint_label.position = Vector2(0, 21)
	_hint_label.size = Vector2(view.x, 10)
	_hint_label.modulate.a = clampf(_hint_left, 0.0, 1.0)
	_update_blessing_label(view)
	_update_slot_labels(view)
	_update_callout(view, delta)
	_update_held_label(bar_x)
	_update_clock_label(bar_x)
	_update_tip(view, delta)
	_update_cards(delta)
	_update_center_message(view)
	_update_boss_label(view)
	_canvas.queue_redraw()


## A one-line tip under the objective for a few seconds (see World.tip()).
func show_tip(text: String) -> void:
	_tip_label.text = text
	_tip_left = TIP_TIME


## Shows a hero's controls card when they arrive in the first level of a run
## (or the test room).
func _on_hero_spawned(slot: int) -> void:
	if world and Settings.tips and (not world.run_mode or GameState.level_index == 0):
		_card_time[slot % _card_time.size()] = CONTROLS_CARD_TIME


## A big message in the middle of the screen for a moment.
## Player colours changed (colour-blind palette).
func refresh_colors() -> void:
	for i in _slot_labels.size():
		_slot_labels[i].label_settings.font_color = GameState.player_color(i)


func callout(text: String, color: Color = Color("ffe07a")) -> void:
	_callout_label.text = text
	_callout_label.label_settings.font_color = color
	_callout_left = CALLOUT_TIME


## The button for `action` on every joined player's device ("[TAB] / (Back)").
func _glyphs_for(action: PlayerInput.Action) -> String:
	var parts := PackedStringArray()
	for slot in InputRouter.assigned_slots():
		var p := InputRouter.get_player(slot)
		if p.is_bot():
			continue
		var g := p.glyph(action)
		if not parts.has(g):
			parts.append(g)
	if parts.is_empty():
		parts = PackedStringArray(["[TAB]" if action == PlayerInput.Action.MAP else "?",
			PlayerInput.device_glyph(0, action)])
	return " / ".join(parts)


static func _join_glyphs() -> String:
	return "[ENTER] / %s" % PlayerInput.device_glyph(0, PlayerInput.Action.UI_ACCEPT)


func _on_hero_damaged(slot: int, _amount: float) -> void:
	if slot >= 0 and slot < _hurt_flash.size():
		_hurt_flash[slot] = HURT_FLASH


func _exit_tree() -> void:
	Events.disconnect_all(self)


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
			label.position = origin + Vector2(20, 0)
		elif world and world.allow_drop_in and not InputRouter.get_player(i).is_assigned():
			label.text = "P%d  %s to join" % [i + 1, _join_glyphs()]
			label.position = origin + Vector2(0, PANEL_SIZE.y - 10 if i >= 2 else 0)
		else:
			label.text = ""


func _update_tip(view: Vector2, delta: float) -> void:
	_tip_left = maxf(0.0, _tip_left - delta)
	_tip_label.visible = _tip_left > 0.0
	_tip_label.position = Vector2(0, 41)
	_tip_label.size = Vector2(view.x, 10)
	_tip_label.modulate.a = clampf(_tip_left / 0.5, 0.0, 1.0)


func _update_cards(delta: float) -> void:
	if world == null:
		return
	for hero in world.heroes:
		var k := hero.slot % _card_time.size()
		if _card_time[k] <= 0.0:
			continue
		var used := hero.used_abilities
		if used[0] != 0 and used[1] != 0 and used[2] != 0:
			_card_time[k] = minf(_card_time[k], 0.6)  # they've got it: fade out
		_card_time[k] = maxf(0.0, _card_time[k] - delta)


func _update_callout(view: Vector2, delta: float) -> void:
	_callout_left = maxf(0.0, _callout_left - delta)
	_callout_label.visible = _callout_left > 0.0
	_callout_label.position = Vector2(0, roundf(view.y * 0.28))
	_callout_label.size = Vector2(view.x, 20)
	_callout_label.modulate.a = clampf(_callout_left / 0.4, 0.0, 1.0)


## "+2" after the level while pick rounds wait for the arena fight to end.
func _update_held_label(bar_x: float) -> void:
	var held := world != null and world.picks_held() and GameState.pending_level_ups > 0
	_held_label.visible = held
	if held:
		_held_label.text = "+%d" % GameState.pending_level_ups
		_held_label.position = Vector2(bar_x + BAR_SIZE.x + 6, 1)
		_held_label.modulate.a = 0.6 + 0.4 * sin(_time * 6.0)


## The keep-moving clock, right of the team hearts (hidden in fights, where
## it waits): "0:42", then "RESTLESS  XP 50%" once it has run out.
func _update_clock_label(bar_x: float) -> void:
	var director := world.director if world else null
	_clock_label.visible = director != null and director.clock_running()
	if not _clock_label.visible:
		return
	var hearts := maxi(GameState.team_lives, 1)
	_clock_label.position = Vector2(bar_x + BAR_SIZE.x + (30 if _held_label.visible else 8) + hearts * 8 + 3, 1)
	var settings := _clock_label.label_settings
	if director.restless_stage <= 0:
		var left := ceili(director.restless_in)
		_clock_label.text = "%d:%02d" % [left / 60, left % 60]
		var hurry := director.restless_in <= CLOCK_HURRY
		settings.font_color = CLOCK_HURRY_COLOR if hurry else CLOCK_COLOR
		_clock_label.modulate.a = 0.45 if hurry and int(director.restless_in * 4.0) % 2 == 1 else 1.0
	else:
		var share := director.drop_share()
		_clock_label.text = "RESTLESS  XP %d%%" % roundi(share * 100.0) if share > 0.0 else "RESTLESS  no XP"
		settings.font_color = RESTLESS_COLOR
		_clock_label.modulate.a = 0.75 + 0.25 * sin(_time * 6.0)


func _update_center_message(view: Vector2) -> void:
	var lost := PackedStringArray()
	for i in InputRouter.MAX_PLAYERS:
		var p := InputRouter.get_player(i)
		if p.is_assigned() and not p.connected:
			lost.append("P%d" % (i + 1))
	_center_label.text = "" if lost.is_empty() else \
		"%s controller disconnected\nreconnect it, or press %s on another controller" % [
			", ".join(lost), PlayerInput.device_glyph(0, PlayerInput.Action.UI_ACCEPT)]
	_center_label.position = Vector2(0, view.y * 0.5 - 20)
	_center_label.size = Vector2(view.x, 40)


func _update_blessing_label(view: Vector2) -> void:
	var left := world.blessing_left if world else 0.0
	_blessing_label.text = "" if left <= 0.0 else "%s  %ds" % [world.blessing_name, ceili(left)]
	_blessing_label.label_settings.font_color = world.blessing_color if world else Color.WHITE
	_blessing_label.position = Vector2(0, 31 if _hint_left > 0.0 else 21)
	_blessing_label.size = Vector2(view.x, 10)
	# Blink in the last few seconds.
	_blessing_label.visible = left > 5.0 or int(left * 4.0) % 2 == 0


func _update_boss_label(view: Vector2) -> void:
	var boss := world.boss if world else null
	var text := ""
	if boss and is_instance_valid(boss):
		text = boss.display_name.to_upper()
		var status := boss.status_text()
		if status != "":
			text += "  -  " + status
	_boss_label.text = text
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
	if world.run_mode:
		_draw_lives(bar_pos + Vector2(BAR_SIZE.x + (30 if _held_label.visible else 8), -2))
	for hero in world.heroes:
		_draw_player_panel(hero, _panel_origin(hero.slot, view))
		if _card_time[hero.slot % _card_time.size()] > 0.0:
			_draw_controls_card(hero, _panel_origin(hero.slot, view))
	_draw_objective_arrow(view)
	_draw_boss_bar(view)


func _draw_player_panel(hero: Hero, origin: Vector2) -> void:
	var c := hero.color
	var bg := Color(0.03, 0.03, 0.06, 0.62)
	var border := Color(c, 0.8)
	var hurt := _hurt_flash[hero.slot % _hurt_flash.size()] / HURT_FLASH
	if hero.is_low_hp():  # pulses red while low
		var pulse := 0.5 + 0.5 * sin(_time * 9.0)
		border = border.lerp(Hero.LOW_HP_COLOR, pulse)
		bg = bg.lerp(Color(0.35, 0.02, 0.04, 0.7), pulse * 0.6)
	if hurt > 0.0:  # just got hit
		border = border.lerp(Color(1, 0.85, 0.85), hurt)
		bg = bg.lerp(Color(0.6, 0.05, 0.05, 0.75), hurt)
	_canvas.draw_rect(Rect2(origin, PANEL_SIZE), bg)
	_canvas.draw_rect(Rect2(origin, PANEL_SIZE), border, false, 1.0)
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
	var ult_color := Color("c070f0")
	if hero.ult_charge >= 1.0:
		ult_color = ult_color.lerp(Color.WHITE, 0.5 + 0.5 * sin(_time * 10.0))
	var fills := [1.0 - hero.special().cooldown_ratio(), 1.0 - hero.movement().cooldown_ratio(), hero.ult_charge]
	var colors := [Color("f2c84a"), Color("5ad8f0"), ult_color]
	for k in 3:
		var ability_slot := k + 1  # special, movement, ultimate
		var bar_color: Color = colors[k]
		if hero.ready_flash[ability_slot] > 0.0:
			bar_color = Color.WHITE  # just came back
		var pos := Vector2(x + (third + 2) * k, origin.y + 17)
		if hero.denied_time[ability_slot] > 0.0:  # pressed while not ready
			_canvas.draw_rect(Rect2(pos - Vector2(2, 2), Vector2(third + 4, 6)), Color(1, 0.25, 0.25, 0.9))
		_bar(pos, third, 2, fills[k], bar_color)
	var font := _canvas.get_theme_default_font()
	if hero.is_downed():
		if int(_time * 3.0) % 2 == 0:  # blinks
			_canvas.draw_string(font, Vector2(x, origin.y + 27), "DOWN!  revive me",
				HORIZONTAL_ALIGNMENT_LEFT, w, 8, Color(1, 0.4, 0.35))
		return
	# Each caption centred under its own bar.
	for k in 3:
		_canvas.draw_string(font, Vector2(x + (third + 2) * k, origin.y + 27), CAPTIONS[k],
			HORIZONTAL_ALIGNMENT_CENTER, third, 8, Color(0.5, 0.5, 0.56))


## The player's four buttons and what they do, next to their panel.
func _draw_controls_card(hero: Hero, panel_origin: Vector2) -> void:
	var bottom := hero.slot >= 2
	var origin := panel_origin + Vector2(0, -CARD_SIZE.y - 2 if bottom else PANEL_SIZE.y + 2)
	var alpha := clampf(_card_time[hero.slot % _card_time.size()] / 0.6, 0.0, 1.0)
	_canvas.draw_rect(Rect2(origin, CARD_SIZE), Color(0.03, 0.03, 0.06, 0.75 * alpha))
	_canvas.draw_rect(Rect2(origin, CARD_SIZE), Color(hero.color, 0.6 * alpha), false, 1.0)
	var font := _canvas.get_theme_default_font()
	var abilities := hero.abilities
	for k in 4:
		var used := hero.used_abilities[k] != 0
		var text := "%s  %s" % [hero.input.glyph(CARD_ACTIONS[k]), abilities[k].display_name]
		var color := Color(0.55, 0.55, 0.6, alpha) if used else Color(1, 1, 1, alpha)
		_canvas.draw_string(font, origin + Vector2(4, 10 + k * 9), text, HORIZONTAL_ALIGNMENT_LEFT,
			CARD_SIZE.x - 8, 8, color)


## Team lives as little hearts (an empty one when there are none left).
func _draw_lives(at: Vector2) -> void:
	var lives := GameState.team_lives
	for k in maxi(lives, 1):
		_heart(at + Vector2(k * 8, 0), HEART_COLOR if lives > 0 else Color(0.35, 0.3, 0.35))


func _heart(at: Vector2, color: Color) -> void:
	var o := at.round()
	_canvas.draw_rect(Rect2(o + Vector2(0, 1), Vector2(2, 2)), color)
	_canvas.draw_rect(Rect2(o + Vector2(3, 1), Vector2(2, 2)), color)
	_canvas.draw_rect(Rect2(o + Vector2(0, 2), Vector2(5, 2)), color)
	_canvas.draw_rect(Rect2(o + Vector2(1, 4), Vector2(3, 1)), color)
	_canvas.draw_rect(Rect2(o + Vector2(2, 5), Vector2(1, 1)), color)


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
	var tip := pos + dir * ARROW_TIP * pulse
	var base := pos - dir * ARROW_BACK
	var pts := PackedVector2Array([tip, base + side * ARROW_HALF_WIDTH, base - side * ARROW_HALF_WIDTH])
	_canvas.draw_colored_polygon(pts, Color("ffe07a"))
	_canvas.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.8), 1.0)


func _draw_boss_bar(view: Vector2) -> void:
	var boss := world.boss
	if boss == null or not is_instance_valid(boss):
		return
	var w := minf(260.0, view.x - 80.0)
	var pos := Vector2(floorf((view.x - w) * 0.5), view.y - 12)
	_bar(pos, w, 4, boss.hp_ratio(), boss.bar_color())


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
