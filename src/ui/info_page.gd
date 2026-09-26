class_name InfoPage
extends CanvasLayer
## A read-only page over the pause menu (Controls, Builds): a title and one
## column per player of coloured lines. B / Esc or "Back" closes it.

signal closed

const MARGIN := 12.0

var _title: Label
var _columns: HBoxContainer
var _back: Button
var _opened_at := 0


func _ready() -> void:
	layer = 76
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = MARGIN
	root.offset_right = -MARGIN
	root.offset_top = 8.0
	root.offset_bottom = -8.0
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", Color("ffe07a"))
	_title.add_theme_font_size_override("font_size", 16)
	root.add_child(_title)
	_columns = HBoxContainer.new()
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 10)
	root.add_child(_columns)
	_back = Button.new()
	_back.text = "Back"
	_back.custom_minimum_size = Vector2(120, 0)
	_back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_back.pressed.connect(close)
	root.add_child(_back)
	UiSounds.attach(_back)


## `columns`: one Array per column of [text, Color] lines.
func open(title: String, columns: Array) -> void:
	_title.text = title
	for child in _columns.get_children():
		child.queue_free()
	for column: Array in columns:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 1)
		for line: Array in column:
			var label := Label.new()
			label.text = line[0]
			label.add_theme_color_override("font_color", line[1])
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.custom_minimum_size = Vector2(60, 0)
			box.add_child(label)
		_columns.add_child(box)
	visible = true
	_opened_at = Engine.get_process_frames()
	UiSounds.focus_quietly(_back)


func is_open() -> bool:
	return visible


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
