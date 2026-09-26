class_name PauseMenu
extends CanvasLayer
## Pause overlay (Resume, Options, Quit to menu). Any keyboard, gamepad or
## mouse can navigate it; Start / Esc / B closes it again. Quitting takes a
## second press, so a run isn't thrown away by accident.

signal quit_requested
## The menu closed and play resumes.
signal closed

const QUIT_TEXT := "Quit to menu"
const QUIT_CONFIRM_TEXT := "Press again to quit"
## How long the second press is accepted.
const QUIT_CONFIRM_TIME := 3.0

var _opened_this_frame := false
var _quit_armed := 0.0
var _options: OptionsMenu
## The Esc / B that closes the options must not also close the pause menu.
var _ignore_pause_until := -1
## Process frame the menu last closed on (so the same press can't reopen it).
var closed_at_frame := -1

@onready var resume_button: Button = %ResumeButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	%ResumeButton.pressed.connect(close)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%QuitButton.focus_exited.connect(_disarm_quit)
	%OptionsButton.pressed.connect(_open_options)
	UiSounds.attach(self)
	_options = OptionsMenu.new()
	add_child(_options)
	_options.closed.connect(_on_options_closed)


func is_open() -> bool:
	return visible


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	_opened_this_frame = true
	get_tree().paused = true
	UiSounds.focus_quietly(resume_button)


func close() -> void:
	visible = false
	_disarm_quit()
	_options.close()
	%Box.visible = true
	closed_at_frame = Engine.get_process_frames()
	InputRouter.swallow_presses()
	get_tree().paused = InputRouter.has_disconnected_player()
	closed.emit()


func _open_options() -> void:
	%Box.visible = false
	_options.open()


func _on_options_closed() -> void:
	if not visible:
		return
	%Box.visible = true
	_ignore_pause_until = Engine.get_process_frames() + 1
	UiSounds.focus_quietly(%OptionsButton)


func _on_quit_pressed() -> void:
	if _quit_armed > 0.0:
		_disarm_quit()
		quit_requested.emit()
		return
	_quit_armed = QUIT_CONFIRM_TIME
	%QuitButton.text = QUIT_CONFIRM_TEXT


func _disarm_quit() -> void:
	_quit_armed = 0.0
	%QuitButton.text = QUIT_TEXT


func _process(delta: float) -> void:
	if not visible or _opened_this_frame:
		_opened_this_frame = false
		return
	if _options.is_open() or Engine.get_process_frames() <= _ignore_pause_until:
		return
	if _quit_armed > 0.0:
		_quit_armed -= delta
		if _quit_armed <= 0.0:
			_disarm_quit()
	for slot in InputRouter.assigned_slots():
		if InputRouter.get_player(slot).just_pressed(PlayerInput.Action.PAUSE):
			close()
			return


func _unhandled_input(event: InputEvent) -> void:
	if visible and not _options.is_open() and event.is_action_pressed(&"ui_cancel") \
			and Engine.get_process_frames() > _ignore_pause_until:
		close()
		get_viewport().set_input_as_handled()
