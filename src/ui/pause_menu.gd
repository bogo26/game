class_name PauseMenu
extends CanvasLayer
## Pause overlay (Resume, volumes, fullscreen, Quit to menu). Any keyboard,
## gamepad or mouse can navigate it; Start / Esc / B closes it again. Quitting
## takes a second press, so a run isn't thrown away by accident.

signal quit_requested
## The menu closed and play resumes.
signal closed

const QUIT_TEXT := "Quit to menu"
const QUIT_CONFIRM_TEXT := "Press again to quit"
## How long the second press is accepted.
const QUIT_CONFIRM_TIME := 3.0

var _opened_this_frame := false
var _quit_armed := 0.0
## Process frame the menu last closed on (so the same press can't reopen it).
var closed_at_frame := -1

@onready var resume_button: Button = %ResumeButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	%ResumeButton.pressed.connect(close)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%QuitButton.focus_exited.connect(_disarm_quit)
	%MusicSlider.value = Audio.get_bus_volume(&"Music")
	%SoundSlider.value = Audio.get_bus_volume(&"SFX")
	%MusicSlider.value_changed.connect(func(v: float) -> void: Audio.set_bus_volume(&"Music", v))
	%SoundSlider.value_changed.connect(func(v: float) -> void:
		Audio.set_bus_volume(&"SFX", v)
		Audio.play(&"ui_move"))
	%FullscreenButton.toggled.connect(func(on: bool) -> void:
		get_window().mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED)
	UiSounds.attach(self)


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
	%FullscreenButton.set_pressed_no_signal(get_window().mode == Window.MODE_FULLSCREEN)
	get_tree().paused = true
	UiSounds.focus_quietly(resume_button)


func close() -> void:
	visible = false
	_disarm_quit()
	closed_at_frame = Engine.get_process_frames()
	InputRouter.swallow_presses()
	get_tree().paused = InputRouter.has_disconnected_player()
	closed.emit()


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
	if _quit_armed > 0.0:
		_quit_armed -= delta
		if _quit_armed <= 0.0:
			_disarm_quit()
	for slot in InputRouter.assigned_slots():
		if InputRouter.get_player(slot).just_pressed(PlayerInput.Action.PAUSE):
			close()
			return


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
