extends Control
## Character select. Up to 4 players join with their own device (A / Enter),
## browse the roster with left/right, and ready up with A / Enter; B / Esc
## un-readies or leaves. Once every joined player is ready, any of them starts
## the run with A / Enter (or Start on a gamepad) - there is no timer.
## With nobody joined, B / Esc returns to the main menu.

const ROSTER: Array[StringName] = [
	&"knight", &"ranger", &"mage", &"cleric", &"berserker", &"rogue", &"engineer", &"necromancer",
]
const HERO_DATA := "res://src/heroes/data/%s.tres"
const HERO_SHEET := "res://assets/sprites/heroes/%s.png"
const GAME_SCENE := "res://src/main/game.tscn"
const MAIN_MENU := "res://src/ui/main_menu.tscn"
const MARGIN := 6.0
const TITLE_HEIGHT := 22.0
## The four ability slots' buttons, in order.
const SLOT_ACTIONS: Array[PlayerInput.Action] = [PlayerInput.Action.ATTACK, PlayerInput.Action.SPECIAL,
	PlayerInput.Action.MOVEMENT, PlayerInput.Action.ULTIMATE]
## Damage rating (1-5 pips) and how hard each hero is to play well.
const HERO_TRAITS := {
	&"knight": [3, "Easy"], &"ranger": [4, "Easy"], &"mage": [4, "Medium"], &"cleric": [2, "Medium"],
	&"berserker": [4, "Easy"], &"rogue": [4, "Hard"], &"engineer": [5, "Medium"], &"necromancer": [4, "Hard"],
}
const DIFFICULTY_COLORS := {"Easy": Color(0.45, 0.95, 0.5), "Medium": Color(1.0, 0.85, 0.35), "Hard": Color(1.0, 0.45, 0.4)}
const PIP_ON := Color(0.95, 0.9, 0.7)
const PIP_OFF := Color(0.3, 0.3, 0.38)


class SlotView:
	var panel: Panel
	var header: Label
	var portrait: TextureRect
	var name_label: Label
	var role_label: Label
	var arrows: Label
	var pips: Control
	var difficulty: Label
	var abilities: Array[Label] = []
	var hint: Label


var _choice: Array[int] = [0, 1, 2, 3]
var _is_ready: Array[bool] = [false, false, false, false]
var _views: Array[SlotView] = []
## Scene started when the players begin the run (tests clear it).
var game_scene := GAME_SCENE
var started := false
## Scene "back" goes to with nobody joined (tests clear it), and whether it happened.
var menu_scene := MAIN_MENU
var went_back := false
var _title: Label
var _footer: Label
var _back_prev: Dictionary = {}
var _hero_cache: Dictionary = {}
var _time := 0.0


func _ready() -> void:
	get_tree().paused = false
	Audio.play_music(&"menu")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	InputRouter.unassign_all()
	GameState.clear_players()
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.035, 0.07)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_title = _label("CHOOSE YOUR HEROES", 16, Color("ffe07a"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	_footer = _label("", 8, Color(0.8, 0.8, 0.85))
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_footer)
	for i in InputRouter.MAX_PLAYERS:
		_views.append(_build_slot(i))
	InputRouter.join_requested.connect(_on_join_requested)
	get_viewport().size_changed.connect(_layout)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--debug-join="):  # screenshots: pre-join bot players
			for i in arg.get_slice("=", 1).to_int():
				_on_join_requested(PlayerInput.DEVICE_BOT)
				_choice[i] = [0, 5, 2, 3][i]
				_refresh(i)
	_layout()
	for i in InputRouter.MAX_PLAYERS:
		_refresh(i)


func _process(delta: float) -> void:
	for i in InputRouter.MAX_PLAYERS:
		var p := InputRouter.get_player(i)
		if p.is_assigned():
			_handle_player(i, p)
	_handle_unassigned_back()
	_update_footer()
	_animate_portraits(delta)


## Joined players' heroes run on the spot (run frames 2-5).
func _animate_portraits(delta: float) -> void:
	_time += delta
	var frame := 2 + int(_time * 8.0) % 4
	for v in _views:
		var atlas := v.portrait.texture as AtlasTexture
		if atlas and v.portrait.visible:
			atlas.region = Rect2(frame * 16, 0, 16, 16)


func _on_join_requested(device: int) -> void:
	var slot := InputRouter.free_slot()
	if slot == -1:
		return
	InputRouter.assign(slot, device)
	Audio.play(&"ui_confirm")
	_is_ready[slot] = false
	if not _is_available(ROSTER[_choice[slot]]):
		_choice[slot] = 0
	_refresh(slot)


func _handle_player(slot: int, p: PlayerInput) -> void:
	if started:
		return
	if _is_ready[slot]:
		if p.just_pressed(PlayerInput.Action.UI_BACK):
			_is_ready[slot] = false
			_refresh(slot)
			Audio.play(&"ui_move")
		elif _start_pressed(p) and _all_ready():
			_start_run(InputRouter.assigned_slots())
		return
	var changed := false
	if p.ui_pressed(PlayerInput.Action.UI_LEFT):
		_choice[slot] = (_choice[slot] - 1 + ROSTER.size()) % ROSTER.size()
		changed = true
	elif p.ui_pressed(PlayerInput.Action.UI_RIGHT):
		_choice[slot] = (_choice[slot] + 1) % ROSTER.size()
		changed = true
	if p.just_pressed(PlayerInput.Action.UI_ACCEPT) and _is_available(ROSTER[_choice[slot]]):
		_is_ready[slot] = true
		p.rumble(0.3, 0.4, 0.12)
		changed = true
	elif p.just_pressed(PlayerInput.Action.UI_BACK):
		# The same press must not also count as "back to the menu" below.
		_back_prev[p.device] = true
		InputRouter.unassign(slot)
		changed = true
	if changed:
		_refresh(slot)
		Audio.play(&"ui_confirm" if _is_ready[slot] else &"ui_move")


## Esc / B on a device nobody uses goes back to the menu when no one joined.
func _handle_unassigned_back() -> void:
	var devices: Array[int] = [PlayerInput.DEVICE_KEYBOARD]
	devices.append_array(Input.get_connected_joypads())
	for d in devices:
		var down := (Input.is_physical_key_pressed(KEY_ESCAPE) or Input.is_physical_key_pressed(KEY_BACKSPACE)) \
			if d == PlayerInput.DEVICE_KEYBOARD \
			else (Input.is_joy_button_pressed(d, JOY_BUTTON_B) or Input.is_joy_button_pressed(d, JOY_BUTTON_BACK))
		var was: bool = _back_prev.get(d, false)
		_back_prev[d] = down
		if down and not was and InputRouter.slot_of_device(d) == -1 and InputRouter.assigned_slots().is_empty():
			went_back = true
			if menu_scene != "":
				get_tree().change_scene_to_file(menu_scene)


func _all_ready() -> bool:
	var joined := InputRouter.assigned_slots()
	if joined.is_empty():
		return false
	for slot in joined:
		if not _is_ready[slot]:
			return false
	return true


## A / Enter, or Start on a gamepad (Esc is "back" for keyboard players).
static func _start_pressed(p: PlayerInput) -> bool:
	return p.just_pressed(PlayerInput.Action.UI_ACCEPT) \
		or (p.device >= 0 and p.just_pressed(PlayerInput.Action.PAUSE))


func _update_footer() -> void:
	var joined := InputRouter.assigned_slots()
	var join := _join_prompt()
	if joined.is_empty():
		_footer.text = "Press %s to join  -  up to 4 players  -  [ESC] / %s: back to menu" % [
			join, PlayerInput.device_glyph(0, PlayerInput.Action.UI_BACK)]
	elif _all_ready():
		_footer.text = "Everyone ready!  Press %s to begin" % join
	elif joined.size() < 4:
		_footer.text = "More players: press %s to join" % join
	else:
		_footer.text = "Waiting for everyone to ready up"


## "[ENTER] / (A)" with the join button of every kind of pad plugged in.
static func _join_prompt() -> String:
	var parts := PackedStringArray(["[ENTER]"])
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		pads = [0]
	for d in pads:
		var g := PlayerInput.device_glyph(d, PlayerInput.Action.UI_ACCEPT)
		if not parts.has(g):
			parts.append(g)
	return " / ".join(parts)


func _start_run(joined: Array[int]) -> void:
	started = true
	Audio.play(&"ui_confirm")
	GameState.reset_run()
	for slot in joined:
		GameState.slots[slot].hero_id = ROSTER[_choice[slot]]
	GameState.level_index = 0
	if game_scene != "":
		get_tree().change_scene_to_file(game_scene)


# --- widgets ---------------------------------------------------------------------------------

func _is_available(hero_id: StringName) -> bool:
	return ResourceLoader.exists(HERO_DATA % hero_id)


func _hero(hero_id: StringName) -> HeroData:
	if not _hero_cache.has(hero_id):
		_hero_cache[hero_id] = load(HERO_DATA % hero_id) if _is_available(hero_id) else null
	return _hero_cache[hero_id]


func _build_slot(slot: int) -> SlotView:
	var v := SlotView.new()
	var color := GameState.player_color(slot)
	v.panel = Panel.new()
	add_child(v.panel)
	v.header = _label("P%d" % (slot + 1), 8, color)
	v.header.position = Vector2(6, 4)
	v.panel.add_child(v.header)
	v.portrait = TextureRect.new()
	v.portrait.position = Vector2(8, 18)
	v.portrait.size = Vector2(48, 48)
	v.portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	v.portrait.stretch_mode = TextureRect.STRETCH_SCALE
	v.panel.add_child(v.portrait)
	v.arrows = _label("<          >", 8, Color(0.7, 0.7, 0.8))
	v.arrows.position = Vector2(8, 68)
	v.panel.add_child(v.arrows)
	v.name_label = _label("", 16, Color.WHITE)
	v.name_label.position = Vector2(64, 16)
	v.panel.add_child(v.name_label)
	v.role_label = _label("", 8, color)
	v.role_label.position = Vector2(64, 34)
	v.panel.add_child(v.role_label)
	v.pips = Control.new()
	v.pips.position = Vector2(8, 78)
	v.pips.size = Vector2(52, 28)
	v.pips.draw.connect(_draw_pips.bind(slot))
	v.panel.add_child(v.pips)
	v.difficulty = _label("", 8, Color.WHITE)
	v.difficulty.position = Vector2(8, 106)
	v.panel.add_child(v.difficulty)
	for i in 4:
		var line := _label("", 8, Color(0.82, 0.82, 0.88))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.panel.add_child(line)
		v.abilities.append(line)
	v.hint = _label("", 8, Color(0.75, 0.75, 0.8))
	v.panel.add_child(v.hint)
	return v


func _layout() -> void:
	var view := get_viewport_rect().size
	_title.position = Vector2(0, 3)
	_title.size = Vector2(view.x, 18)
	_footer.position = Vector2(0, view.y - 12)
	_footer.size = Vector2(view.x, 10)
	var top := TITLE_HEIGHT
	var w := (view.x - MARGIN * 3.0) * 0.5
	var h := (view.y - top - 14.0 - MARGIN) * 0.5
	for i in _views.size():
		var v := _views[i]
		v.panel.position = Vector2(MARGIN + (i % 2) * (w + MARGIN), top + (i / 2) * (h + MARGIN))
		v.panel.size = Vector2(w, h)
		var text_w := w - 72.0
		for line in v.abilities:
			line.custom_minimum_size = Vector2(text_w, 0)
			line.size = Vector2(text_w, 0)
		_stack_abilities(v)
		v.hint.position = Vector2(8, h - 12)


## Ability lines one under the other, by how many lines each wraps to.
func _stack_abilities(v: SlotView) -> void:
	var y := 46.0
	for line in v.abilities:
		line.position = Vector2(64, y)
		y += maxi(1, line.get_line_count()) * line.get_line_height() + 2.0


func _refresh(slot: int) -> void:
	var v := _views[slot]
	var p := InputRouter.get_player(slot)
	var color := GameState.player_color(slot)
	var joined := p.is_assigned()
	var bg := Color(0.08, 0.075, 0.12) if joined else Color(0.05, 0.05, 0.08)
	var border := color if joined else Color(0.25, 0.25, 0.32)
	if joined and _is_ready[slot]:
		bg = Color(color, 0.18).blend(Color(0.08, 0.075, 0.12, 0.9))
	v.panel.add_theme_stylebox_override("panel", _box(bg, border, 2 if _is_ready[slot] else 1))
	for child in [v.portrait, v.name_label, v.role_label, v.arrows, v.pips, v.difficulty]:
		(child as CanvasItem).visible = joined
	for line in v.abilities:
		line.visible = joined
	if not joined:
		v.header.text = "P%d" % (slot + 1)
		v.hint.text = "Press %s to join" % _join_prompt()
		return
	var hero_id := ROSTER[_choice[slot]]
	v.header.text = "P%d  %s   %d/%d" % [slot + 1, InputRouter.device_name(p.device), _choice[slot] + 1, ROSTER.size()]
	var sheet := load(HERO_SHEET % hero_id) as Texture2D
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = Rect2(0, 0, 16, 16)
	v.portrait.texture = atlas
	var data := _hero(hero_id)
	if data == null:
		v.portrait.modulate = Color(0.25, 0.25, 0.3)
		v.name_label.text = String(hero_id).to_upper()
		v.role_label.text = "Coming soon"
		for line in v.abilities:
			line.text = ""
		v.hint.text = "Not playable yet - choose another hero"
		return
	v.portrait.modulate = Color.WHITE
	v.name_label.text = data.display_name.to_upper()
	v.role_label.text = data.role
	var traits: Array = HERO_TRAITS.get(hero_id, [3, "Medium"])
	v.difficulty.text = traits[1]
	v.difficulty.label_settings.font_color = DIFFICULTY_COLORS.get(traits[1], Color.WHITE)
	v.pips.queue_redraw()
	var abilities := data.abilities()
	for i in 4:
		var a := abilities[i]
		v.abilities[i].text = "%s %s: %s" % [p.glyph(SLOT_ACTIONS[i]), a.display_name, a.description]
	_stack_abilities(v)
	var accept := p.glyph(PlayerInput.Action.UI_ACCEPT)
	var back := p.glyph(PlayerInput.Action.UI_BACK)
	if _is_ready[slot]:
		v.hint.text = "READY!  %s to change" % back
	elif p.uses_mouse or p.device == PlayerInput.DEVICE_KEYBOARD:
		v.hint.text = "A/D browse   %s ready   %s leave" % [accept, back]
	else:
		v.hint.text = "< > browse   %s ready   %s leave" % [accept, back]


## Toughness, damage and speed as 1-5 pips under the portrait.
func _draw_pips(slot: int) -> void:
	var v := _views[slot]
	var data := _hero(ROSTER[_choice[slot]])
	if data == null:
		return
	var toughness := clampi(1 + int((data.max_hp * (1.0 + data.armor * 0.15) - 75.0) / 20.0), 1, 5)
	var traits: Array = HERO_TRAITS.get(data.id, [3, "Medium"])
	var speed := clampi(roundi((data.move_speed - 80.0) / 5.0), 1, 5)
	var rows := [["HP", toughness], ["DMG", int(traits[0])], ["SPD", speed]]
	var font := v.pips.get_theme_default_font()
	for r in rows.size():
		var y := r * 9.0
		v.pips.draw_string(font, Vector2(0, y + 7), rows[r][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.62, 0.62, 0.7))
		for k in 5:
			v.pips.draw_rect(Rect2(22 + k * 6, y + 2, 4, 4), PIP_ON if k < int(rows[r][1]) else PIP_OFF)


static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	settings.line_spacing = 0
	label.label_settings = settings
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.anti_aliasing = false
	return box
