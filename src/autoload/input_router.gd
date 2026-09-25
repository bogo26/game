extends Node
## Owns the 4 PlayerInput slots and the device→slot mapping.
## Polls every device once per frame (before anything else runs) and reports
## "join" presses from devices that don't belong to a player yet.

signal join_requested(device: int)

const MAX_PLAYERS := 4

var players: Array[PlayerInput] = []

var _join_prev: Dictionary = {}  # device id -> bool (join button held last frame)


func _init() -> void:
	# Built in _init so the slots exist even before _ready (headless tests).
	for i in MAX_PLAYERS:
		players.append(PlayerInput.new(i))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _process(delta: float) -> void:
	for p in players:
		p.poll(delta)
	_poll_join_requests()


func get_player(slot: int) -> PlayerInput:
	return players[slot]


func assign(slot: int, device: int) -> void:
	var p := players[slot]
	p.clear()
	p.device = device
	p.connected = true
	Events.player_joined.emit(slot)


func unassign(slot: int) -> void:
	var p := players[slot]
	if not p.is_assigned():
		return
	p.clear()
	p.device = PlayerInput.DEVICE_NONE
	p.connected = true
	Events.player_left.emit(slot)


func unassign_all() -> void:
	for i in MAX_PLAYERS:
		unassign(i)


func slot_of_device(device: int) -> int:
	for p in players:
		if p.device == device:
			return p.slot
	return -1


func free_slot() -> int:
	for p in players:
		if not p.is_assigned():
			return p.slot
	return -1


func assigned_slots() -> Array[int]:
	var out: Array[int] = []
	for p in players:
		if p.is_assigned():
			out.append(p.slot)
	return out


func has_disconnected_player() -> bool:
	for p in players:
		if p.is_assigned() and not p.connected:
			return true
	return false


static func device_name(device: int) -> String:
	match device:
		PlayerInput.DEVICE_KEYBOARD:
			return "Keyboard + Mouse"
		PlayerInput.DEVICE_BOT:
			return "Bot"
		PlayerInput.DEVICE_NONE:
			return "-"
	var joy_name := Input.get_joy_name(device)
	return joy_name if joy_name != "" else "Gamepad %d" % (device + 1)


func _poll_join_requests() -> void:
	var devices: Array[int] = [PlayerInput.DEVICE_KEYBOARD]
	devices.append_array(Input.get_connected_joypads())
	for d in devices:
		var down := _join_button_down(d)
		var was: bool = _join_prev.get(d, false)
		_join_prev[d] = down
		if not down or was or slot_of_device(d) != -1:
			continue
		# A new device pressing "join" while someone's pad is unplugged takes
		# over that player instead of creating a new one.
		var lost := _first_disconnected_slot()
		if lost != -1:
			players[lost].device = d
			players[lost].connected = true
			players[lost].clear()
			Events.player_device_restored.emit(lost)
		else:
			join_requested.emit(d)


func _join_button_down(device: int) -> bool:
	if device == PlayerInput.DEVICE_KEYBOARD:
		return Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE)
	return Input.is_joy_button_pressed(device, JOY_BUTTON_A) or Input.is_joy_button_pressed(device, JOY_BUTTON_START)


func _first_disconnected_slot() -> int:
	for p in players:
		if p.is_assigned() and not p.connected:
			return p.slot
	return -1


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	var slot := slot_of_device(device)
	if slot == -1:
		return
	players[slot].connected = connected
	if connected:
		Events.player_device_restored.emit(slot)
	else:
		players[slot].clear()
		Events.player_device_lost.emit(slot)
