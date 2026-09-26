class_name PlayerInput
extends RefCounted
## Per-player input snapshot, refreshed once per frame by the InputRouter
## autoload. Gameplay and UI read move/aim vectors and action states from
## here and never touch `Input` directly, so devices can't leak between players.

enum Action {
	ATTACK,
	SPECIAL,
	MOVEMENT,
	ULTIMATE,
	PAUSE,
	UI_ACCEPT,
	UI_BACK,
	UI_UP,
	UI_DOWN,
	UI_LEFT,
	UI_RIGHT,
	MAP,
}
const ACTION_COUNT := 12

const DEVICE_NONE := -2
const DEVICE_KEYBOARD := -1
## Driven by code (stress test bots, demos) instead of hardware.
const DEVICE_BOT := -3

const MOVE_DEADZONE := 0.2
const AIM_DEADZONE := 0.3
const TRIGGER_THRESHOLD := 0.5
const UI_STICK_THRESHOLD := 0.5
const UI_REPEAT_DELAY := 0.35
const UI_REPEAT_INTERVAL := 0.1
## After the right stick is released for this long, aim follows movement.
const AIM_FOLLOW_MOVE_DELAY := 0.5

var slot: int
var device: int = DEVICE_NONE
## False while an assigned gamepad is unplugged.
var connected := true

## Movement intent, length 0..1.
var move := Vector2.ZERO
## Last valid aim direction (unit vector). For keyboard+mouse players the hero
## computes aim from the mouse cursor instead (see `uses_mouse`).
var aim := Vector2.RIGHT
## True while the right stick is deflected (or for mouse players, always).
var aim_active := false
var uses_mouse := false

## Enter pressed while Alt is held is the fullscreen shortcut, not "accept":
## it stays ignored until released (see update_enter_latch()).
static var _enter_latched := false

var _down := PackedByteArray()
var _prev := PackedByteArray()
var _repeat_timer := PackedFloat32Array()
var _repeat_fired := PackedByteArray()
var _aim_idle_time := 0.0


func _init(p_slot: int) -> void:
	slot = p_slot
	_down.resize(ACTION_COUNT)
	_prev.resize(ACTION_COUNT)
	_repeat_timer.resize(ACTION_COUNT)
	_repeat_timer.fill(-1.0)
	_repeat_fired.resize(ACTION_COUNT)


func is_assigned() -> bool:
	return device != DEVICE_NONE


func is_bot() -> bool:
	return device == DEVICE_BOT


func is_down(action: Action) -> bool:
	return _down[action] != 0


func just_pressed(action: Action) -> bool:
	return _down[action] != 0 and _prev[action] == 0


func just_released(action: Action) -> bool:
	return _down[action] == 0 and _prev[action] != 0


## Menu-style press: fires on the initial press and then auto-repeats while held.
func ui_pressed(action: Action) -> bool:
	return just_pressed(action) or _repeat_fired[action] != 0


## For bots/tests: set an action's held state for the current frame.
func set_action(action: Action, down: bool) -> void:
	_down[action] = 1 if down else 0


## Marks every held action as already seen, so nothing counts as just pressed.
func consume_presses() -> void:
	for i in ACTION_COUNT:
		_prev[i] = _down[i]
		_repeat_fired[i] = 0


func clear() -> void:
	move = Vector2.ZERO
	aim_active = false
	for i in ACTION_COUNT:
		_down[i] = 0
		_prev[i] = 0
		_repeat_timer[i] = -1.0
		_repeat_fired[i] = 0


## Called once per frame by the InputRouter, before any player is polled.
static func update_enter_latch() -> void:
	if not (Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER)):
		_enter_latched = false
	elif Input.is_physical_key_pressed(KEY_ALT):
		_enter_latched = true


## Enter (or keypad Enter) held, unless it's part of Alt+Enter.
static func enter_down() -> bool:
	return not _enter_latched and \
		(Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER))


func rumble(weak: float, strong: float, duration: float) -> void:
	if device >= 0 and connected:
		Input.start_joy_vibration(device, weak, strong, duration)


## Called once per frame by InputRouter before any gameplay reads.
func poll(delta: float) -> void:
	for i in ACTION_COUNT:
		_prev[i] = _down[i]
	if device == DEVICE_NONE or device == DEVICE_BOT:
		# Bots write their own state after this; keep last values for them.
		_update_repeats(delta)
		return
	if not connected:
		clear()
		return
	if device == DEVICE_KEYBOARD:
		_read_keyboard_mouse()
	else:
		_read_joypad(device, delta)
	_update_repeats(delta)


func _read_keyboard_mouse() -> void:
	var right := _key(KEY_D) or _key(KEY_RIGHT)
	var left := _key(KEY_A) or _key(KEY_LEFT)
	var down := _key(KEY_S) or _key(KEY_DOWN)
	var up := _key(KEY_W) or _key(KEY_UP)
	move = Vector2(float(right) - float(left), float(down) - float(up)).limit_length(1.0)
	uses_mouse = true
	aim_active = true
	_write(Action.ATTACK, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	_write(Action.SPECIAL, Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	_write(Action.MOVEMENT, _key(KEY_SPACE) or _key(KEY_SHIFT))
	_write(Action.ULTIMATE, _key(KEY_Q))
	_write(Action.PAUSE, _key(KEY_ESCAPE))
	_write(Action.MAP, _key(KEY_TAB) or _key(KEY_M))
	_write(Action.UI_ACCEPT, enter_down() or _key(KEY_SPACE))
	_write(Action.UI_BACK, _key(KEY_ESCAPE) or _key(KEY_BACKSPACE))
	_write(Action.UI_UP, up)
	_write(Action.UI_DOWN, down)
	_write(Action.UI_LEFT, left)
	_write(Action.UI_RIGHT, right)


func _read_joypad(d: int, delta: float) -> void:
	var left_stick := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
	var dpad := Vector2(
		float(_btn(d, JOY_BUTTON_DPAD_RIGHT)) - float(_btn(d, JOY_BUTTON_DPAD_LEFT)),
		float(_btn(d, JOY_BUTTON_DPAD_DOWN)) - float(_btn(d, JOY_BUTTON_DPAD_UP)))
	move = radial_deadzone(left_stick, MOVE_DEADZONE)
	if dpad != Vector2.ZERO:
		move = dpad.normalized()

	var right_stick := radial_deadzone(
		Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y)),
		AIM_DEADZONE)
	uses_mouse = false
	aim_active = right_stick != Vector2.ZERO
	if aim_active:
		aim = right_stick.normalized()
		_aim_idle_time = 0.0
	else:
		_aim_idle_time += delta
		if _aim_idle_time >= AIM_FOLLOW_MOVE_DELAY and move != Vector2.ZERO:
			aim = move.normalized()

	_write(Action.ATTACK, Input.get_joy_axis(d, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_THRESHOLD)
	_write(Action.SPECIAL, Input.get_joy_axis(d, JOY_AXIS_TRIGGER_LEFT) > TRIGGER_THRESHOLD)
	_write(Action.MOVEMENT, _btn(d, JOY_BUTTON_RIGHT_SHOULDER) or _btn(d, JOY_BUTTON_A))
	_write(Action.ULTIMATE, _btn(d, JOY_BUTTON_LEFT_SHOULDER) or _btn(d, JOY_BUTTON_Y))
	_write(Action.PAUSE, _btn(d, JOY_BUTTON_START))
	_write(Action.MAP, _btn(d, JOY_BUTTON_BACK))
	_write(Action.UI_ACCEPT, _btn(d, JOY_BUTTON_A))
	_write(Action.UI_BACK, _btn(d, JOY_BUTTON_B))
	_write(Action.UI_UP, dpad.y < 0.0 or left_stick.y < -UI_STICK_THRESHOLD)
	_write(Action.UI_DOWN, dpad.y > 0.0 or left_stick.y > UI_STICK_THRESHOLD)
	_write(Action.UI_LEFT, dpad.x < 0.0 or left_stick.x < -UI_STICK_THRESHOLD)
	_write(Action.UI_RIGHT, dpad.x > 0.0 or left_stick.x > UI_STICK_THRESHOLD)


func _update_repeats(delta: float) -> void:
	for a: int in [Action.UI_UP, Action.UI_DOWN, Action.UI_LEFT, Action.UI_RIGHT]:
		_repeat_fired[a] = 0
		if _down[a] == 0:
			_repeat_timer[a] = -1.0  # released: re-arm the initial delay
			continue
		if _repeat_timer[a] < 0.0:
			_repeat_timer[a] = UI_REPEAT_DELAY
			continue
		_repeat_timer[a] -= delta
		if _repeat_timer[a] <= 0.0:
			_repeat_timer[a] += UI_REPEAT_INTERVAL
			_repeat_fired[a] = 1


func _write(action: Action, down: bool) -> void:
	_down[action] = 1 if down else 0


static func _key(key: Key) -> bool:
	return Input.is_physical_key_pressed(key)


static func _btn(d: int, button: JoyButton) -> bool:
	return Input.is_joy_button_pressed(d, button)


## Radial deadzone with rescaling so output starts at 0 right past the edge.
static func radial_deadzone(v: Vector2, deadzone: float) -> Vector2:
	var length := v.length()
	if length <= deadzone:
		return Vector2.ZERO
	var scaled := minf(1.0, (length - deadzone) / (1.0 - deadzone))
	return v / length * scaled
