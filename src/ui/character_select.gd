extends Control
## Character select. Up to 4 players join with their own device (A / Enter),
## browse the roster with left/right, and ready up with A / Enter; B / Esc
## un-readies or leaves. The run starts once every joined player is ready.
## With nobody joined, B / Esc returns to the main menu.

const ROSTER: Array[StringName] = [
	&"knight", &"ranger", &"mage", &"cleric", &"berserker", &"rogue", &"engineer", &"necromancer",
]
const HERO_DATA := "res://src/heroes/data/%s.tres"
const HERO_SHEET := "res://assets/sprites/heroes/%s.png"
const GAME_SCENE := "res://src/main/game.tscn"
const MAIN_MENU := "res://src/ui/main_menu.tscn"
const START_DELAY := 1.5
const MARGIN := 6.0
const TITLE_HEIGHT := 22.0
const SLOT_TAGS: Array[String] = ["ATK", "SPC", "MOV", "ULT"]


class SlotView:
	var panel: Panel
	var header: Label
	var portrait: TextureRect
	var name_label: Label
	var role_label: Label
	var arrows: Label
	var abilities: Array[Label] = []
	var hint: Label


var _choice: Array[int] = [0, 1, 2, 3]
var _is_ready: Array[bool] = [false, false, false, false]
var _views: Array[SlotView] = []
var _countdown := -1.0
var _title: Label
var _footer: Label
var _back_prev: Dictionary = {}
var _hero_cache: Dictionary = {}


func _ready() -> void:
	get_tree().paused = false
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
	_update_countdown(delta)


func _on_join_requested(device: int) -> void:
	var slot := InputRouter.free_slot()
	if slot == -1:
		return
	InputRouter.assign(slot, device)
	_is_ready[slot] = false
	if not _is_available(ROSTER[_choice[slot]]):
		_choice[slot] = 0
	_refresh(slot)


func _handle_player(slot: int, p: PlayerInput) -> void:
	if _is_ready[slot]:
		if p.just_pressed(PlayerInput.Action.UI_BACK):
			_is_ready[slot] = false
			_refresh(slot)
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
		InputRouter.unassign(slot)
		changed = true
	if changed:
		_refresh(slot)


## Esc / B on a device nobody uses goes back to the menu when no one joined.
func _handle_unassigned_back() -> void:
	var devices: Array[int] = [PlayerInput.DEVICE_KEYBOARD]
	devices.append_array(Input.get_connected_joypads())
	for d in devices:
		var down := Input.is_physical_key_pressed(KEY_ESCAPE) if d == PlayerInput.DEVICE_KEYBOARD \
			else (Input.is_joy_button_pressed(d, JOY_BUTTON_B) or Input.is_joy_button_pressed(d, JOY_BUTTON_BACK))
		var was: bool = _back_prev.get(d, false)
		_back_prev[d] = down
		if down and not was and InputRouter.slot_of_device(d) == -1 and InputRouter.assigned_slots().is_empty():
			get_tree().change_scene_to_file(MAIN_MENU)


func _update_countdown(delta: float) -> void:
	var joined := InputRouter.assigned_slots()
	var all_ready := not joined.is_empty()
	for slot in joined:
		all_ready = all_ready and _is_ready[slot]
	if not all_ready:
		_countdown = -1.0
		_footer.text = "Press ENTER / (A) to join  -  up to 4 players" if joined.size() < 4 else "Waiting for everyone to ready up"
		return
	if _countdown < 0.0:
		_countdown = START_DELAY
	_countdown -= delta
	_footer.text = "Starting in %d..." % ceili(maxf(_countdown, 0.0))
	if _countdown <= 0.0:
		_start_run(joined)


func _start_run(joined: Array[int]) -> void:
	set_process(false)
	GameState.reset_run()
	for slot in joined:
		GameState.slots[slot].hero_id = ROSTER[_choice[slot]]
	GameState.level_index = 0
	get_tree().change_scene_to_file(GAME_SCENE)


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
		var y := 46.0
		for line in v.abilities:
			line.position = Vector2(64, y)
			line.custom_minimum_size = Vector2(text_w, 0)
			line.size = Vector2(text_w, 0)
			y += 20.0
		v.hint.position = Vector2(8, h - 12)


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
	for child in [v.portrait, v.name_label, v.role_label, v.arrows]:
		(child as CanvasItem).visible = joined
	for line in v.abilities:
		line.visible = joined
	if not joined:
		v.header.text = "P%d" % (slot + 1)
		v.hint.text = "Press ENTER / (A) to join"
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
	v.role_label.text = "%s   HP %d" % [data.role, int(data.max_hp)]
	var abilities := data.abilities()
	for i in 4:
		var a := abilities[i]
		v.abilities[i].text = "%s %s: %s" % [SLOT_TAGS[i], a.display_name, a.description]
	if _is_ready[slot]:
		v.hint.text = "READY!   ESC / (B) to change"
	elif p.uses_mouse or p.device == PlayerInput.DEVICE_KEYBOARD:
		v.hint.text = "A/D browse   ENTER ready   ESC leave"
	else:
		v.hint.text = "< > browse   (A) ready   (B) leave"


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
