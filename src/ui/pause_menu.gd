class_name PauseMenu
extends CanvasLayer
## Pause overlay (Resume / Quit to menu). Any keyboard, gamepad or mouse can
## navigate it; Start / Esc / B closes it again.

signal quit_requested

var _opened_this_frame := false
## Process frame the menu last closed on (so the same press can't reopen it).
var closed_at_frame := -1

@onready var resume_button: Button = %ResumeButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	%ResumeButton.pressed.connect(close)
	%QuitButton.pressed.connect(func() -> void: quit_requested.emit())
	%MusicSlider.value = Audio.get_bus_volume(&"Music")
	%SoundSlider.value = Audio.get_bus_volume(&"SFX")
	%MusicSlider.value_changed.connect(func(v: float) -> void: Audio.set_bus_volume(&"Music", v))
	%SoundSlider.value_changed.connect(func(v: float) -> void:
		Audio.set_bus_volume(&"SFX", v)
		Audio.play(&"ui_move"))
	%FullscreenButton.toggled.connect(func(on: bool) -> void:
		get_window().mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED)


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
	resume_button.grab_focus.call_deferred()


func close() -> void:
	visible = false
	closed_at_frame = Engine.get_process_frames()
	InputRouter.swallow_presses()
	get_tree().paused = InputRouter.has_disconnected_player()


func _process(_delta: float) -> void:
	if not visible or _opened_this_frame:
		_opened_this_frame = false
		return
	for slot in InputRouter.assigned_slots():
		if InputRouter.get_player(slot).just_pressed(PlayerInput.Action.PAUSE):
			close()
			return


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
