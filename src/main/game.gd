extends Node
## Plays a run: builds a World for the current level of the RunConfig, shows
## level banners, advances to the next level when the team reaches the exit,
## and ends the run on a team wipe (defeat) or the boss's death (victory).

const WORLD_SCENE := "res://src/world/world.tscn"
const END_SCENE := "res://src/ui/end_screen.tscn"
const BANNER_TIME := 2.2
const END_DELAY := 2.8

var run: RunConfig
var world: World
var _ending := false
var _banner_time := 0.0

@onready var banner: Label = %Banner
@onready var banner_sub: Label = %BannerSub


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	run = RunConfig.load_default()
	var bot_arg := false
	for arg in OS.get_cmdline_user_args():
		bot_arg = bot_arg or arg.begins_with("--bots=")
	if InputRouter.assigned_slots().is_empty() and not bot_arg:
		# Launched directly (editor F6): play solo with the keyboard.
		InputRouter.assign(0, PlayerInput.DEVICE_KEYBOARD)
		GameState.slots[0].hero_id = &"knight"
		GameState.reset_run()
	if not GameState.run_active:
		GameState.reset_run()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):  # debug: jump to a level (1-based)
			GameState.level_index = arg.get_slice("=", 1).to_int() - 1
	GameState.level_index = clampi(GameState.level_index, 0, run.levels.size() - 1)
	_load_level()


func _process(delta: float) -> void:
	if _banner_time > 0.0:
		_banner_time -= delta
		var alpha := clampf(_banner_time / 0.5, 0.0, 1.0)
		banner.modulate.a = alpha
		banner_sub.modulate.a = alpha


func _load_level() -> void:
	if world:
		remove_child(world)
		world.queue_free()
	# Never carry a pause into the new level (only an unplugged pad keeps it).
	get_tree().paused = InputRouter.has_disconnected_player()
	var data := run.levels[GameState.level_index]
	GameState.team_lives = GameState.LIVES_PER_LEVEL
	world = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.run_mode = true
	world.level_up_delay = BANNER_TIME  # pick rounds wait for the level banner
	add_child(world)
	move_child(world, 0)
	world.level_completed.connect(_on_level_completed)
	world.team_wiped.connect(_on_team_wiped)
	world.boss_defeated.connect(_on_boss_defeated)
	world.quit_requested.connect(_quit_to_menu)
	# The boss track starts when the throne room's fight does (LevelDirector).
	Audio.play_music(&"dungeon")
	var title := "FINAL LEVEL" if data.is_boss_level else "LEVEL %d" % (GameState.level_index + 1)
	_show_banner(title, data.display_name)


func _show_banner(title: String, subtitle: String) -> void:
	banner.text = title
	banner_sub.text = subtitle
	banner.modulate.a = 1.0
	banner_sub.modulate.a = 1.0
	_banner_time = BANNER_TIME


## What the team keeps going into the next level: ultimate charge, and the XP
## in gems nobody picked up.
func _carry_over() -> void:
	for hero in world.heroes:
		GameState.slots[hero.slot].ult_charge = hero.ult_charge
	GameState.add_xp(world.pickups.total_xp())
	world.pickups.clear()


func _bank_level_stats() -> void:
	GameState.run_kills += world.kills
	GameState.run_time += world.elapsed


func _on_level_completed() -> void:
	if _ending:
		return
	# Rounds earned from here on open after the next level's banner.
	world.level_ups_enabled = false
	_carry_over()
	_bank_level_stats()
	GameState.levels_cleared += 1
	_show_banner("LEVEL CLEAR!", "")
	Audio.play(&"clear")
	world.set_process(false)
	await get_tree().create_timer(1.6).timeout
	GameState.level_index += 1
	if GameState.level_index >= run.levels.size():
		_end(true)
	else:
		_load_level()


func _on_team_wiped() -> void:
	if _ending:
		return
	_ending = true
	_stop_interruptions()
	_bank_level_stats()
	_show_banner("DEFEAT", "Your party has fallen")
	Audio.stop_music()
	Audio.play(&"defeat")
	_banner_time = END_DELAY
	await get_tree().create_timer(END_DELAY).timeout
	_end(false)


func _on_boss_defeated() -> void:
	if _ending:
		return
	_ending = true
	_stop_interruptions()
	_bank_level_stats()
	GameState.levels_cleared += 1
	_show_banner("VICTORY!", "The Demon Lord is slain")
	Audio.stop_music()
	# After the boss's death cry.
	get_tree().create_timer(0.7).timeout.connect(Audio.play.bind(&"victory"))
	_banner_time = END_DELAY
	await get_tree().create_timer(END_DELAY).timeout
	_end(true)


## The run is over: no pick screens or pause menu under the final banner.
func _stop_interruptions() -> void:
	world.level_ups_enabled = false
	world.pause_enabled = false


func _end(victory: bool) -> void:
	GameState.last_run_victory = victory
	GameState.run_active = false
	get_tree().paused = false
	get_tree().change_scene_to_file(END_SCENE)


func _quit_to_menu() -> void:
	GameState.run_active = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")
