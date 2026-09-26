extends Node2D
## Title screen: slow pan over a dungeon, the game title and a button list
## (Start Run / Test Room / Options / Quit). Any keyboard, gamepad or mouse can
## navigate.

const BACKGROUND_LEVEL := preload("res://src/levels/data/test_room.tres")
const CHARACTER_SELECT := "res://src/ui/character_select.tscn"
const TEST_ROOM := "res://src/world/world.tscn"

var _time := 0.0
var _pan_origin := Vector2.ZERO

@onready var level: Level = $Level
@onready var camera: Camera2D = $Camera
@onready var start_button: Button = %StartButton


func _ready() -> void:
	get_tree().paused = false
	Audio.play_music(&"menu")
	GameState.run_active = false
	InputRouter.unassign_all()
	GameState.clear_players()
	level.build(BACKGROUND_LEVEL)
	_pan_origin = level.player_spawns[0]
	camera.position = _pan_origin
	%StartButton.pressed.connect(_on_start)
	%TestRoomButton.pressed.connect(_on_test_room)
	%QuitButton.pressed.connect(func() -> void: get_tree().quit())
	var options := OptionsMenu.new()
	add_child(options)
	%OptionsButton.pressed.connect(func() -> void:
		$UI/Center.visible = false  # keeps focus inside the options
		options.open())
	options.closed.connect(func() -> void:
		$UI/Center.visible = true
		UiSounds.focus_quietly(%OptionsButton))
	UiSounds.attach($UI)
	UiSounds.focus_quietly(start_button)


func _process(delta: float) -> void:
	_time += delta
	camera.position = (_pan_origin + Vector2(sin(_time * 0.11) * 220.0, cos(_time * 0.07) * 90.0)).round()


func _on_start() -> void:
	get_tree().change_scene_to_file(CHARACTER_SELECT)


func _on_test_room() -> void:
	GameState.reset_run()
	GameState.run_active = false
	get_tree().change_scene_to_file(TEST_ROOM)
