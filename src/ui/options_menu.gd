class_name OptionsMenu
extends CanvasLayer
## Settings screen, opened from the main menu and the pause menu. One row
## per setting; any keyboard, gamepad or mouse can drive it (Godot focus):
## up/down picks a row, left/right (or click / right-click) changes it,
## B / Esc or "Back" closes it. Changes apply and save at once (Settings).

signal closed

const WIDTH := 300.0
const ROW_HEIGHT := 13.0
const VOLUME_STEPS := 10


class Row:
	var key: StringName
	var values: Array = []
	var names: PackedStringArray = []
	## Choices cycle around; volumes stop at 0% and 100% instead (a press on
	## a full volume mustn't mute the game).
	var wraps := true
	var button: Button
	var value_label: Label


var _rows: Array[Row] = []
var _box: VBoxContainer
var _back: Button
var _opened_at := 0


func _ready() -> void:
	layer = 75  # above the pause menu (70) and the Game's banners (60)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(WIDTH, 0)
	_box.add_theme_constant_override("separation", 2)
	center.add_child(_box)
	var title := Label.new()
	title.text = "OPTIONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("ffe07a"))
	title.add_theme_font_size_override("font_size", 16)
	_box.add_child(title)
	var volumes := []
	var volume_names := PackedStringArray()
	for k in VOLUME_STEPS + 1:
		volumes.append(float(k) / VOLUME_STEPS)
		volume_names.append("%d%%" % (k * 100 / VOLUME_STEPS))
	var on_off := PackedStringArray(["Off", "On"])
	for volume: Array in [[&"master_volume", "Volume"], [&"music_volume", "Music"], [&"sfx_volume", "Sounds"]]:
		_add_row(volume[0], volume[1], volumes, volume_names).wraps = false
	_add_row(&"fullscreen", "Fullscreen (F11)", [false, true], on_off)
	_add_row(&"screen_shake", "Screen shake", [0, 1, 2], PackedStringArray(["Off", "Low", "Full"]))
	_add_row(&"damage_numbers", "Damage numbers", [0, 1, 2], PackedStringArray(["All", "Crits only", "Off"]))
	_add_row(&"reduce_flashing", "Reduce flashing", [false, true], on_off)
	_add_row(&"rumble", "Controller rumble", [false, true], on_off)
	_add_row(&"palette", "Player colours", [0, 1], PackedStringArray(["Default", "Colour-blind"]))
	_add_row(&"aim_assist", "Aim assist (gamepad)", [0, 1, 2], PackedStringArray(["Off", "Low", "High"]))
	_add_row(&"tips", "Tips", [false, true], on_off)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	_box.add_child(spacer)
	_back = Button.new()
	_back.text = "Back"
	_back.pressed.connect(close)
	_box.add_child(_back)
	UiSounds.attach(_box)


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_opened_at = Engine.get_process_frames()
	for row in _rows:
		_refresh(row)
	UiSounds.focus_quietly(_rows[0].button)


func close() -> void:
	if not visible:
		return
	visible = false
	InputRouter.swallow_presses()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel") and Engine.get_process_frames() > _opened_at:
		close()
		get_viewport().set_input_as_handled()


## Steps a row's value by `step` (wrapping) and applies it.
func change(key: StringName, step: int, sound: bool = true) -> void:
	for row in _rows:
		if row.key == key:
			var index := _index_of(row) + step
			if row.wraps:
				index = (index + row.values.size()) % row.values.size()
			else:
				index = clampi(index, 0, row.values.size() - 1)
			Settings.set_value(key, row.values[index])
			_refresh(row)
			if sound:
				Audio.play(&"ui_move")
			return


func _add_row(key: StringName, text: String, values: Array, names: PackedStringArray) -> Row:
	var row := Row.new()
	row.key = key
	row.values = values
	row.names = names
	row.button = Button.new()
	row.button.custom_minimum_size = Vector2(WIDTH, ROW_HEIGHT)
	row.button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.button.text = "  " + text
	row.value_label = Label.new()
	row.value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.value_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.value_label.offset_right = -8.0
	row.value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.button.add_child(row.value_label)
	row.button.pressed.connect(change.bind(key, 1, false))  # UiSounds plays the confirm
	row.button.gui_input.connect(_on_row_input.bind(row))
	_box.add_child(row.button)
	_rows.append(row)
	return row


func _on_row_input(event: InputEvent, row: Row) -> void:
	if event.is_action_pressed(&"ui_left", true):
		change(row.key, -1)
		row.button.accept_event()
	elif event.is_action_pressed(&"ui_right", true):
		change(row.key, 1)
		row.button.accept_event()
	var click := event as InputEventMouseButton
	if click and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT:
		change(row.key, -1)
		row.button.accept_event()


func _index_of(row: Row) -> int:
	var current: Variant = Settings.get(row.key)
	var best := 0
	var best_d := INF
	for k in row.values.size():
		var v: Variant = row.values[k]
		var d := absf(float(v) - float(current)) if v is float else (0.0 if v == current else 1.0)
		if d < best_d:
			best_d = d
			best = k
	return best


func _refresh(row: Row) -> void:
	row.value_label.text = "<  %s  >" % row.names[_index_of(row)]
