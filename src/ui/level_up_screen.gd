class_name LevelUpScreen
extends CanvasLayer
## Pauses the game on a team level-up and lets every player pick one of three
## upgrade cards at the same time, each in their own screen area with their
## own controller (left/right + A, or arrows/WASD + Enter, or mouse).
## Queued rounds (GameState.pending_rounds) resolve one at a time; panels sit
## in their player's HUD corner when 3-4 people play.

signal closed

const CARD_COUNT := 3
const BOT_PICK_DELAY := 0.6
## Human input is ignored briefly when cards appear, so a button mashed for
## combat (A is also dash) can't pick a card by accident.
const INPUT_GRACE := 0.35
const MARGIN := 6.0
const TITLE_HEIGHT := 20.0
## Once everyone has picked, the result stays up this long (so the last
## player sees "PICKED!" too) before the next round or the game resumes.
const ROUND_END_DELAY := 0.3


class Picker:
	var hero: Hero
	var offers: Array[UpgradeData] = []
	var selected := 0
	var picked := false
	var chosen: UpgradeData
	var bot_timer := 0.0
	var grace := INPUT_GRACE
	var panel: Panel
	var cards: Array[Panel] = []
	var status: Label


var pool: UpgradePool
## Whether another queued round may follow the one just finished (the World
## holds level rounds back during arena fights). Default: always.
var may_continue: Callable = func() -> bool: return true
var _heroes: Array[Hero] = []
var _pickers: Array[Picker] = []
var _root: Control
var _title: Label
var _open := false
var _round_end_left := -1.0


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_title = _label("", 16, Color("ffe07a"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_title)


func is_open() -> bool:
	return _open


func open(heroes: Array[Hero], p_pool: UpgradePool) -> void:
	_heroes = heroes
	pool = p_pool
	_open = true
	visible = true
	_start_round()


func close() -> void:
	_open = false
	visible = false
	_clear_panels()
	closed.emit()


func _process(delta: float) -> void:
	if not _open:
		return
	var all_done := true
	for pk in _pickers:
		if not pk.picked:
			_handle_input(pk, delta)
		if not pk.picked:
			all_done = false
	if not all_done:
		return
	if _round_end_left < 0.0:
		_round_end_left = ROUND_END_DELAY
		for pk in _pickers:
			_refresh(pk)  # everyone done: drop the "waiting..."
	_round_end_left -= delta
	if _round_end_left > 0.0:
		return
	_round_end_left = -1.0
	GameState.pop_round()
	if GameState.pending_level_ups > 0 and may_continue.call():
		_start_round()
	else:
		close()


## Title for a pick round (see GameState.pending_rounds).
static func round_title(pick_round: int) -> String:
	match pick_round:
		GameState.TREASURE_ROUND:
			return "TREASURE!  PICK AN UPGRADE"
		GameState.BONUS_ROUND:
			return "BONUS!  PICK AN UPGRADE"
	return "LEVEL %d!  PICK AN UPGRADE" % pick_round


func _start_round() -> void:
	_clear_panels()
	var view := _root.get_viewport_rect().size
	_title.text = round_title(GameState.next_round())
	_title.position = Vector2(0, 2)
	_title.size = Vector2(view.x, TITLE_HEIGHT)
	var rects := _layout(_heroes, view)
	for i in _heroes.size():
		var pk := Picker.new()
		pk.hero = _heroes[i]
		pk.offers = pool.roll_offers(pk.hero.hero_id, pk.hero.upgrade_stacks, CARD_COUNT, _heroes.size() == 1)
		pk.picked = pk.offers.is_empty()
		_build_panel(pk, rects[i])
		_pickers.append(pk)
		_refresh(pk)


func is_round_finished() -> bool:
	return _round_end_left >= 0.0


func _handle_input(pk: Picker, delta: float) -> void:
	var input := pk.hero.input
	var n := pk.offers.size()
	if input.is_bot() or not input.is_assigned():
		pk.bot_timer += delta
		if pk.bot_timer >= BOT_PICK_DELAY:
			_confirm(pk, randi() % n)
		return
	if pk.grace > 0.0:
		pk.grace -= delta
		return
	if input.ui_pressed(PlayerInput.Action.UI_LEFT):
		pk.selected = (pk.selected - 1 + n) % n
		_refresh(pk)
		Audio.play(&"ui_move")
	elif input.ui_pressed(PlayerInput.Action.UI_RIGHT):
		pk.selected = (pk.selected + 1) % n
		_refresh(pk)
		Audio.play(&"ui_move")
	if input.just_pressed(PlayerInput.Action.UI_ACCEPT):
		_confirm(pk, pk.selected)


func _confirm(pk: Picker, index: int) -> void:
	if pk.picked or index < 0 or index >= pk.offers.size():
		return
	pk.picked = true
	pk.selected = index
	pk.chosen = pk.offers[index]
	pk.hero.apply_upgrade(pk.chosen)
	pk.hero.input.rumble(0.2, 0.3, 0.1)
	Audio.play(&"ui_confirm")
	_refresh(pk)


# --- layout / widgets -------------------------------------------------------------------------

## One panel per hero: centred for 1 player, halves for 2 (in slot order),
## and each player's HUD corner (by slot) for 3-4.
func _layout(heroes: Array[Hero], view: Vector2) -> Array[Rect2]:
	var top := TITLE_HEIGHT + 2.0
	var full := Rect2(MARGIN, top, view.x - MARGIN * 2.0, view.y - top - MARGIN)
	var out: Array[Rect2] = []
	match heroes.size():
		1:
			var w := minf(360.0, full.size.x)
			var h := minf(170.0, full.size.y)
			out.append(Rect2(full.get_center() - Vector2(w, h) * 0.5, Vector2(w, h)))
		2:
			var w := (full.size.x - MARGIN) * 0.5
			var h := minf(180.0, full.size.y)
			var y := full.position.y + (full.size.y - h) * 0.5
			var first_left := heroes[0].slot < heroes[1].slot
			out.append(Rect2(full.position.x + (0.0 if first_left else w + MARGIN), y, w, h))
			out.append(Rect2(full.position.x + (w + MARGIN if first_left else 0.0), y, w, h))
		_:
			var w := (full.size.x - MARGIN) * 0.5
			var h := (full.size.y - MARGIN) * 0.5
			for hero in heroes:
				var col := hero.slot % 2
				var row := (hero.slot / 2) % 2
				out.append(Rect2(full.position.x + col * (w + MARGIN), full.position.y + row * (h + MARGIN), w, h))
	return out


func _build_panel(pk: Picker, rect: Rect2) -> void:
	var color := pk.hero.color
	pk.panel = Panel.new()
	pk.panel.position = rect.position
	pk.panel.size = rect.size
	pk.panel.add_theme_stylebox_override("panel", _box(Color(0.07, 0.06, 0.1, 0.94), color, 1))
	_root.add_child(pk.panel)
	var header := _label("P%d  %s" % [pk.hero.slot + 1, pk.hero.data.display_name.to_upper()], 8, color)
	header.position = Vector2(6, 3)
	pk.panel.add_child(header)
	pk.status = _label("", 8, Color(0.75, 0.75, 0.8))
	pk.status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pk.status.position = Vector2(rect.size.x * 0.5, 3)
	pk.status.size = Vector2(rect.size.x * 0.5 - 6, 10)
	pk.panel.add_child(pk.status)
	if pk.offers.is_empty():
		var maxed := _label("Everything maxed out!", 8, Color.WHITE)
		maxed.position = Vector2(6, rect.size.y * 0.5)
		pk.panel.add_child(maxed)
		return
	var gap := 5.0
	var card_w := floorf((rect.size.x - 12.0 - gap * (CARD_COUNT - 1)) / CARD_COUNT)
	var card_h := rect.size.y - 22.0
	for i in pk.offers.size():
		var card := _build_card(pk.offers[i], pk.hero, Vector2(card_w, card_h))
		card.position = Vector2(6 + i * (card_w + gap), 16)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(_on_card_input.bind(pk, i))
		card.mouse_entered.connect(_on_card_hover.bind(pk, i))
		pk.panel.add_child(card)
		pk.cards.append(card)


func _build_card(upgrade: UpgradeData, hero: Hero, size: Vector2) -> Panel:
	var card := Panel.new()
	card.size = size
	var rarity_color := UpgradeData.RARITY_COLORS[upgrade.rarity]
	var element := Elements.MOD_KEYS.find(upgrade.element)
	if element != -1:
		rarity_color = Elements.COLORS[element]
	var inner_w := size.x - 8.0
	var name_label := _wrapped_label(upgrade.display_name, Color.WHITE, inner_w)
	name_label.position = Vector2(4, 6)
	card.add_child(name_label)
	var tag := UpgradeData.RARITY_NAMES[upgrade.rarity]
	if upgrade.hero_id != &"":
		tag = hero.data.display_name
	if element != -1:
		tag = "%s %s" % [Elements.NAMES[element], ["", "I", "II", "III"][clampi(upgrade.tier, 0, 3)]]
	var rarity := _label(tag.to_upper(), 8, rarity_color)
	rarity.position = Vector2(4, 30)
	card.add_child(rarity)
	var desc := _wrapped_label(upgrade.description, Color(0.78, 0.78, 0.84), inner_w)
	desc.position = Vector2(4, 42)
	card.add_child(desc)
	var taken := int(hero.upgrade_stacks.get(upgrade.id, 0))
	var counter := "%d/%d" % [taken + 1, upgrade.max_stacks]
	if element != -1:
		counter = "TIER %d/3" % upgrade.tier
	var stacks := _label(counter, 8, Color(0.55, 0.55, 0.62))
	stacks.position = Vector2(4, size.y - 13)
	card.add_child(stacks)
	card.set_meta("rarity_color", rarity_color)
	return card


func _refresh(pk: Picker) -> void:
	for i in pk.cards.size():
		var card := pk.cards[i]
		var rarity_color: Color = card.get_meta("rarity_color")
		var is_selected := i == pk.selected
		var bg := Color(0.13, 0.12, 0.18) if is_selected else Color(0.09, 0.085, 0.13)
		var border := pk.hero.color if is_selected else rarity_color.darkened(0.3)
		if pk.picked and not is_selected:
			card.modulate = Color(1, 1, 1, 0.35)
		else:
			card.modulate = Color.WHITE
		card.add_theme_stylebox_override("panel", _box(bg, border, 2 if is_selected else 1))
		card.position.y = 13.0 if is_selected and not pk.picked else 16.0
	if pk.picked:
		pk.status.text = "" if pk.chosen == null else ("PICKED!" if _round_end_left >= 0.0 else "PICKED! waiting...")
	elif pk.hero.input.uses_mouse:
		pk.status.text = "A/D choose, ENTER or click"
	else:
		pk.status.text = "< > choose, (A) pick"


func _on_card_input(event: InputEvent, pk: Picker, index: int) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_LEFT \
			and pk.hero.input.uses_mouse and not pk.picked and pk.grace <= 0.0:
		_confirm(pk, index)


func _on_card_hover(pk: Picker, index: int) -> void:
	if pk.hero.input.uses_mouse and not pk.picked:
		pk.selected = index
		_refresh(pk)


func _clear_panels() -> void:
	for pk in _pickers:
		if is_instance_valid(pk.panel):
			pk.panel.queue_free()
	_pickers.clear()


static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	var settings := LabelSettings.new()
	settings.font_size = size
	settings.font_color = color
	settings.line_spacing = 1
	label.label_settings = settings
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


static func _wrapped_label(text: String, color: Color, width: float) -> Label:
	var label := _label(text, 8, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(width, 0)
	label.size = Vector2(width, 0)
	return label


static func _box(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.anti_aliasing = false
	return box
