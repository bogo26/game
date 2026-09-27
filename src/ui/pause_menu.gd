class_name PauseMenu
extends CanvasLayer
## Pause overlay (Resume, Controls, Builds, Options, Quit to menu). Any
## keyboard, gamepad or mouse can navigate it; Start / Esc / B closes it
## again. Quitting takes a second press, so a run isn't thrown away by accident.
## Controls lists every player's buttons; Builds every player's upgrades.

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
var _page: InfoPage
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
	%ControlsButton.pressed.connect(_open_page.bind(true))
	%BuildsButton.pressed.connect(_open_page.bind(false))
	UiSounds.attach(self)
	_options = OptionsMenu.new()
	add_child(_options)
	_options.closed.connect(_on_options_closed.bind(%OptionsButton))
	_page = InfoPage.new()
	add_child(_page)


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
	_page.close()
	%Box.visible = true
	closed_at_frame = Engine.get_process_frames()
	InputRouter.swallow_presses()
	get_tree().paused = InputRouter.has_disconnected_player()
	closed.emit()


func _open_options() -> void:
	%Box.visible = false
	_options.open()


func _on_options_closed(from: Button) -> void:
	if not visible:
		return
	%Box.visible = true
	_ignore_pause_until = Engine.get_process_frames() + 1
	UiSounds.focus_quietly(from)


func _open_page(controls: bool) -> void:
	var world := get_parent() as World
	if world == null:
		return
	var columns := []
	for hero in world.heroes:
		columns.append(controls_lines(hero) if controls else build_lines(hero))
	%Box.visible = false
	_page.closed.connect(_on_options_closed.bind(%ControlsButton if controls else %BuildsButton), CONNECT_ONE_SHOT)
	_page.open("CONTROLS" if controls else "BUILDS", columns)


## A hero's buttons and what they do.
static func controls_lines(hero: Hero) -> Array:
	var grey := Color(0.6, 0.6, 0.68)
	var lines := [["P%d  %s" % [hero.slot + 1, hero.data.display_name.to_upper()], hero.color],
		[hero.data.description, Color(0.8, 0.8, 0.85)]]
	var actions: Array[PlayerInput.Action] = [PlayerInput.Action.ATTACK, PlayerInput.Action.SPECIAL,
		PlayerInput.Action.MOVEMENT, PlayerInput.Action.ULTIMATE]
	for k in 4:
		var a := hero.abilities[k]
		lines.append(["%s  %s" % [hero.input.glyph(actions[k]), a.display_name], Color.WHITE])
		lines.append([a.description, grey])
	lines.append([hero.input.glyph(PlayerInput.Action.MAP) + "  Map (hold)", grey])
	lines.append([hero.input.glyph(PlayerInput.Action.PAUSE) + "  Pause", grey])
	return lines


## A hero's upgrades: elements at their highest tier, then the rest with stacks.
static func build_lines(hero: Hero) -> Array:
	var lines := [["P%d  %s" % [hero.slot + 1, hero.data.display_name.to_upper()], hero.color]]
	var library := UpgradePool.shared_library()
	var elements: Dictionary = {}
	var others := []
	for id: StringName in hero.upgrade_stacks:
		var u := library.find(id)
		if u == null:
			continue
		if u.is_legendary():  # first: it changed how the hero plays
			lines.insert(1, [u.display_name, UpgradeData.RARITY_COLORS[UpgradeData.Rarity.LEGENDARY]])
			continue
		var element := Elements.MOD_KEYS.find(u.element)
		if element != -1:
			if u.tier > int(elements.get(element, [0])[0]):
				elements[element] = [u.tier, u.display_name]
			continue
		var n := int(hero.upgrade_stacks[id])
		var color := hero.color.lightened(0.3) if u.hero_id != &"" else UpgradeData.RARITY_COLORS[u.rarity]
		others.append([u.display_name + ("  x%d" % n if n > 1 else ""), color])
	for element: int in elements:
		var tier: int = elements[element][0]
		lines.append(["%s %s  %s" % [Elements.NAMES[element], ["", "I", "II", "III"][tier], elements[element][1]],
			Elements.COLORS[element]])
	others.sort_custom(func(a: Array, b: Array) -> bool: return String(a[0]) < String(b[0]))
	lines.append_array(others)
	if lines.size() == 1:
		lines.append(["No upgrades yet", Color(0.6, 0.6, 0.68)])
	return lines


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
	if _options.is_open() or _page.is_open() or Engine.get_process_frames() <= _ignore_pause_until:
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
	if visible and not _options.is_open() and not _page.is_open() and event.is_action_pressed(&"ui_cancel") \
			and Engine.get_process_frames() > _ignore_pause_until:
		close()
		get_viewport().set_input_as_handled()
