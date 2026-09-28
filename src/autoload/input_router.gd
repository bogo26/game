extends Node
## Owns the 4 PlayerInput slots and the device→slot mapping.
## Polls every device once per frame (before anything else runs) and reports
## "join" presses from devices that don't belong to a player yet.

signal join_requested(device: int)

const MAX_PLAYERS := 4

var players: Array[PlayerInput] = []

var _join_prev: Dictionary = {}  # device id -> bool (join button held last frame)
var _swallow_presses := false


func _init() -> void:
	# Built in _init so the slots exist even before _ready (headless tests).
	for i in MAX_PLAYERS:
		players.append(PlayerInput.new(i))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_extend_ui_actions()


## Menus use Godot's built-in ui_* actions (focus navigation for any device).
## Add WASD and the left stick to them; gameplay never reads the InputMap.
static func _extend_ui_actions() -> void:
	var extra := {
		&"ui_up": [KEY_W, JOY_AXIS_LEFT_Y, -1.0],
		&"ui_down": [KEY_S, JOY_AXIS_LEFT_Y, 1.0],
		&"ui_left": [KEY_A, JOY_AXIS_LEFT_X, -1.0],
		&"ui_right": [KEY_D, JOY_AXIS_LEFT_X, 1.0],
	}
	for action: StringName in extra:
		if not InputMap.has_action(action):
			continue
		var key := InputEventKey.new()
		key.physical_keycode = extra[action][0]
		InputMap.action_add_event(action, key)
		var stick := InputEventJoypadMotion.new()
		stick.device = -1
		stick.axis = extra[action][1]
		stick.axis_value = extra[action][2]
		InputMap.action_add_event(action, stick)

	if InputMap.has_action(&"ui_accept"):
		var btn_a := InputEventJoypadButton.new()
		btn_a.device = -1
		btn_a.button_index = JOY_BUTTON_A
		InputMap.action_add_event(&"ui_accept", btn_a)
	
	if InputMap.has_action(&"ui_cancel"):
		var btn_b := InputEventJoypadButton.new()
		btn_b.device = -1
		btn_b.button_index = JOY_BUTTON_B
		InputMap.action_add_event(&"ui_cancel", btn_b)


func _process(delta: float) -> void:
	PlayerInput.update_enter_latch()
	for p in players:
		p.poll(delta)
		if _swallow_presses:
			p.consume_presses()
	_swallow_presses = false
	_poll_join_requests()


## Hides this frame's new presses from gameplay (e.g. the A press that closed
## a menu shouldn't also dash).
func swallow_presses() -> void:
	_swallow_presses = true


func get_player(slot: int) -> PlayerInput:
	return players[slot]


func assign(slot: int, device: int) -> void:
	var p := players[slot]
	p.clear()
	p.device = device
	p.connected = true
	_treat_held_as_old(p)
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
			players[lost].clear()
			players[lost].device = d
			players[lost].connected = true
			_treat_held_as_old(players[lost])
			Events.player_device_restored.emit(lost)
		else:
			join_requested.emit(d)


## The button a player joins with is usually still held on the next frame.
## Record the device's current state as "already held" so it doesn't also
## count as a fresh press (e.g. A = join would otherwise also ready up / dash).
static func _treat_held_as_old(p: PlayerInput) -> void:
	p.poll(0.0)
	p.consume_presses()


func _join_button_down(device: int) -> bool:
	if device == PlayerInput.DEVICE_KEYBOARD:
		return PlayerInput.enter_down() or Input.is_physical_key_pressed(KEY_SPACE)
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
