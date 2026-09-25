extends CanvasLayer
## Corner labels showing each player slot: who joined with which device, or a
## "press to join" prompt. Used by the drop-in test room.

const CORNER_MARGIN := Vector2(4, 3)

var _labels: Array[Label] = []
var _center: Label


func _ready() -> void:
	for i in InputRouter.MAX_PLAYERS:
		var label := Label.new()
		var settings := LabelSettings.new()
		settings.font_size = 8
		settings.font_color = GameState.player_color(i)
		settings.shadow_color = Color(0, 0, 0, 0.8)
		settings.shadow_offset = Vector2(1, 1)
		label.label_settings = settings
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		_labels.append(label)
	_center = Label.new()
	var center_settings := LabelSettings.new()
	center_settings.font_size = 16
	center_settings.outline_size = 4
	center_settings.outline_color = Color.BLACK
	_center.label_settings = center_settings
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	get_viewport().size_changed.connect(_layout)
	Events.player_joined.connect(_on_players_changed)
	Events.player_left.connect(_on_players_changed)
	Events.player_device_lost.connect(_on_players_changed)
	Events.player_device_restored.connect(_on_players_changed)
	Events.hero_spawned.connect(_on_players_changed)
	_refresh()


func _on_players_changed(_slot: int) -> void:
	_refresh()


func _refresh() -> void:
	var lost := PackedStringArray()
	for i in _labels.size():
		var p := InputRouter.get_player(i)
		if p.is_assigned() and not p.connected:
			lost.append("P%d" % (i + 1))
	_center.text = "" if lost.is_empty() else \
		"%s controller disconnected\nreconnect it, or press A on another controller" % ", ".join(lost)
	for i in _labels.size():
		var p := InputRouter.get_player(i)
		var text := ""
		if not p.is_assigned():
			text = "P%d  press ENTER / (A) to join" % (i + 1)
		elif not p.connected:
			text = "P%d  controller disconnected!" % (i + 1)
		else:
			text = "P%d  %s  -  %s" % [i + 1, String(GameState.slots[i].hero_id).capitalize(),
				InputRouter.device_name(p.device)]
		_labels[i].text = text
	_layout()


func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	_center.size = Vector2(size.x, 40)
	_center.position = Vector2(0, size.y * 0.5 - 20)
	for i in _labels.size():
		var label := _labels[i]
		label.size = label.get_minimum_size()
		var right := i % 2 == 1
		var bottom := i >= 2
		label.position = Vector2(
			size.x - label.size.x - CORNER_MARGIN.x if right else CORNER_MARGIN.x,
			size.y - label.size.y - CORNER_MARGIN.y if bottom else CORNER_MARGIN.y)
