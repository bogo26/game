class_name UiSounds
extends RefCounted
## Navigation and confirm sounds for menus that use Godot's focus (main menu,
## pause menu, end screen). Focus set by code right after a menu opens stays
## silent.

const QUIET_MSEC := 150

static var _quiet_until := 0


## Hooks every button and slider under `root`.
static func attach(root: Node) -> void:
	for node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if control is BaseButton:
			control.focus_entered.connect(_on_focus)
			(control as BaseButton).pressed.connect(func() -> void: Audio.play(&"ui_confirm"))
		elif control is Range:
			control.focus_entered.connect(_on_focus)


## Gives `control` the focus without a sound (menus opening).
static func focus_quietly(control: Control) -> void:
	_quiet_until = Time.get_ticks_msec() + QUIET_MSEC
	control.grab_focus.call_deferred()


static func _on_focus() -> void:
	if Time.get_ticks_msec() >= _quiet_until:
		Audio.play(&"ui_move")
