extends "res://tests/test_case.gd"
## Options: settings save and load, and every hook follows its setting
## (screen shake, damage numbers, reduced flashing, player colours, aim
## assist), plus the options screen stepping through values.

const WORLD_SCENE := "res://src/world/world.tscn"
const TEMP := "user://test_options.cfg"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _done() -> void:
	Settings.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP))


func test_settings_round_trip() -> void:
	Settings.path = TEMP
	Settings.set_value(&"music_volume", 0.4)
	Settings.set_value(&"screen_shake", Settings.Shake.LOW)
	Settings.set_value(&"aim_assist", Settings.AimAssist.HIGH)
	Settings.set_value(&"reduce_flashing", true)
	Settings.seen_tips[&"revive"] = true
	Settings.save_settings()
	Settings.reset()
	assert_eq(Settings.screen_shake, Settings.Shake.FULL, "reset to defaults")
	Settings.load_settings()
	assert_near(Settings.music_volume, 0.4, 0.001)
	assert_eq(Settings.screen_shake, Settings.Shake.LOW)
	assert_eq(Settings.aim_assist, Settings.AimAssist.HIGH)
	assert_true(Settings.reduce_flashing)
	assert_true(Settings.seen_tips.has(&"revive"))
	_done()


func test_screen_shake_setting() -> void:
	var camera := SharedCamera.new()
	camera.add_shake(4.0)
	assert_near(camera._shake, 4.0, 0.001, "full")
	camera._shake = 0.0
	Settings.screen_shake = Settings.Shake.LOW
	camera.add_shake(4.0)
	assert_near(camera._shake, 2.0, 0.001, "low halves it")
	camera._shake = 0.0
	Settings.screen_shake = Settings.Shake.OFF
	camera.add_shake(4.0)
	assert_eq(camera._shake, 0.0, "off")
	camera.free()
	_done()


func test_damage_numbers_setting() -> void:
	var numbers := DamageNumbers.new()
	Settings.damage_numbers = Settings.Numbers.CRITS
	numbers.add(Vector2.ZERO, 20.0, Color.WHITE)
	numbers.add_crit(Vector2.ZERO, 30.0)
	assert_eq(numbers.count(), 1, "crits only")
	Settings.damage_numbers = Settings.Numbers.OFF
	numbers.add_crit(Vector2.ZERO, 30.0)
	numbers.add_hero_damage(Vector2.ZERO, 5.0, false)
	numbers.add_text(Vector2.ZERO, "TREASURE!", Color.WHITE)
	assert_eq(numbers.count(), 2, "off: only words like TREASURE! still show")
	numbers.free()
	_done()


func test_colour_blind_palette() -> void:
	var default_p1 := GameState.player_color(0)
	Settings.palette = Settings.Palette.COLORBLIND
	assert_eq(GameState.player_color(0), GameState.COLORBLIND_COLORS[0])
	assert_true(GameState.player_color(0) != default_p1)
	_done()


func _world() -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = &"ranger"
	var data := LevelData.new()
	data.display_name = "Options test"
	data.layout = """
##################
#P...............#
#................#
#................#
#................#
##################
"""
	data.corridor_spawn_rate = 0.0
	data.arena_quotas = PackedInt32Array([0, 0, 0])
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.spawn_enemies = false
	world.level_ups_enabled = false
	_tree().root.add_child(world)
	world.bots = null
	return world


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	InputRouter.unassign_all()
	GameState.clear_players()


func test_aim_assist_locks_onto_enemies_in_its_cone() -> void:
	var world := _world()
	var hero := world.heroes[0]
	hero.position = LevelGrid.cell_center(Vector2i(3, 3))
	var t := world.horde.type_index(&"swarmer")
	var near_12 := hero.body_position() + Vector2.RIGHT.rotated(deg_to_rad(12.0)) * 80.0 + Vector2(0, 6)
	world.horde.spawn(t, near_12)
	world.horde.hash.rebuild(world.horde.pos, world.horde.count)
	var aim := Vector2.RIGHT
	assert_eq(hero.assisted_aim(aim, 0.0), aim, "off: untouched")
	assert_eq(hero.assisted_aim(aim, deg_to_rad(10.0)), aim, "low (10 degrees) doesn't reach 12")
	var assisted := hero.assisted_aim(aim, deg_to_rad(20.0))
	assert_near(rad_to_deg(aim.angle_to(assisted)), 12.0, 3.0, "high snaps onto it")
	_teardown(world)
	_done()


func test_reduce_flashing_softens_hit_flashes() -> void:
	var world := _world()
	var hero := world.heroes[0]
	hero.invulnerable_time = 0.0
	hero.take_hit(1.0)
	hero._update_visuals(0.01)
	var full := hero.sprite.modulate
	Settings.reduce_flashing = true
	hero._hurt_flash = 0.12
	hero._update_visuals(0.01)
	assert_true(hero.sprite.modulate.r < full.r, "a gentler hurt flash")
	hero._hurt_flash = 0.0
	hero.invulnerable_time = 0.4
	hero._update_visuals(0.01)
	var a := hero.sprite.modulate.a
	hero.invulnerable_time = 0.37
	hero._update_visuals(0.01)
	assert_eq(hero.sprite.modulate.a, a, "no blinking")
	_teardown(world)
	_done()


func test_options_screen_steps_through_values() -> void:
	Settings.path = TEMP
	var menu := OptionsMenu.new()
	_tree().root.add_child(menu)
	menu.open()
	menu.change(&"screen_shake", 1)
	assert_eq(Settings.screen_shake, Settings.Shake.OFF, "Full wraps around to Off")
	menu.change(&"music_volume", -1, false)
	assert_near(Settings.music_volume, 0.9, 0.001, "volume steps by 10%")
	menu.change(&"master_volume", 1, false)
	assert_near(Settings.master_volume, 1.0, 0.001, "a press on a full volume doesn't wrap to mute")
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(TEMP), OK, "saved at once")
	assert_near(float(cfg.get_value("audio", "Music")), 0.9, 0.001)
	menu.close()
	menu.get_parent().remove_child(menu)
	menu.free()
	_done()
