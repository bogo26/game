extends "res://tests/test_case.gd"
## Character select with simulated keyboard input: joining doesn't ready you
## up, browsing works, and the run only starts on an explicit press once
## everyone is ready - never on a timer.

const SELECT_SCENE := "res://src/ui/character_select.tscn"
const DT := 1.0 / 60.0

var _held: Array[Key] = []


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	if pressed:
		_held.append(code)
	else:
		_held.erase(code)


func _frame(select: Node, count: int = 1) -> void:
	for i in count:
		InputRouter._process(DT)
		select._process(DT)


func _tap(select: Node, code: Key) -> void:
	_key(code, true)
	_frame(select)
	_key(code, false)
	_frame(select)


func _open() -> Node:
	InputRouter.unassign_all()
	GameState.clear_players()
	InputRouter._process(DT)  # let the router see a frame with nothing held
	var select: Node = (load(SELECT_SCENE) as PackedScene).instantiate()
	select.set("game_scene", "")  # don't actually load the game
	(Engine.get_main_loop() as SceneTree).root.add_child(select)
	return select


func _close(select: Node) -> void:
	for code in _held.duplicate():
		_key(code, false)
	InputRouter._process(DT)  # register the releases before the next test
	select.get_parent().remove_child(select)
	select.free()
	InputRouter.unassign_all()
	GameState.clear_players()


func test_join_press_does_not_ready_you_up() -> void:
	var select := _open()
	_key(KEY_ENTER, true)  # join...
	_frame(select, 5)      # ...and keep holding Enter for a few frames
	assert_true(InputRouter.get_player(0).is_assigned(), "keyboard joined as P1")
	assert_false(select.get("_is_ready")[0], "holding the join button doesn't also ready up")
	_close(select)


func test_browse_ready_and_start_only_on_input() -> void:
	var select := _open()
	_tap(select, KEY_ENTER)  # join
	var roster: Array[StringName] = select.get("ROSTER")
	var first: int = select.get("_choice")[0]
	_tap(select, KEY_D)
	_tap(select, KEY_RIGHT)
	var choice: int = select.get("_choice")[0]
	assert_eq(choice, (first + 2) % roster.size(), "browsed two heroes to the right")
	_tap(select, KEY_A)
	assert_eq(select.get("_choice")[0], (first + 1) % roster.size(), "and one back")
	_tap(select, KEY_ENTER)  # ready
	assert_true(select.get("_is_ready")[0], "Enter readies up")
	_frame(select, 600)  # 10 seconds: nothing may start by itself
	assert_false(select.get("started"), "no timer starts the run")
	_tap(select, KEY_ESCAPE)
	assert_false(select.get("_is_ready")[0], "Esc un-readies")
	_tap(select, KEY_A)  # can browse again after un-readying
	_tap(select, KEY_ENTER)  # ready
	_tap(select, KEY_ENTER)  # start
	assert_true(select.get("started"), "a press after everyone is ready starts the run")
	assert_eq(GameState.slots[0].hero_id, roster[first], "with the chosen hero")
	_close(select)


func test_run_waits_for_every_player() -> void:
	var select := _open()
	_tap(select, KEY_ENTER)  # keyboard joins as P1
	InputRouter.assign(1, PlayerInput.DEVICE_BOT)  # a second (idle) player
	_frame(select)
	_tap(select, KEY_ENTER)  # P1 ready
	_tap(select, KEY_ENTER)  # P1 tries to start
	assert_false(select.get("started"), "can't start while P2 isn't ready")
	_close(select)


func test_join_button_does_not_dash_in_the_test_room() -> void:
	InputRouter.unassign_all()
	_key(KEY_SPACE, true)  # Space joins... and is also the keyboard dash
	InputRouter.assign(0, PlayerInput.DEVICE_KEYBOARD)
	InputRouter._process(DT)
	assert_false(InputRouter.get_player(0).just_pressed(PlayerInput.Action.MOVEMENT),
		"the held join key isn't a fresh dash press")
	_key(KEY_SPACE, false)
	InputRouter._process(DT)
	_key(KEY_SPACE, true)
	InputRouter._process(DT)
	assert_true(InputRouter.get_player(0).just_pressed(PlayerInput.Action.MOVEMENT), "a new press dashes")
	_key(KEY_SPACE, false)
	InputRouter.unassign_all()
