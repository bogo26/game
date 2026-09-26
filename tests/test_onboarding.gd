extends "res://tests/test_case.gd"
## Onboarding: button icons per controller family, one-time tips, the
## controls card, the pause menu's Controls / Builds pages, chests and shrines
## explaining themselves, and "Waiting for P2" at the exit.

const WORLD_SCENE := "res://src/world/world.tscn"
const FONT := preload("res://assets/fonts/pixel5x8.fnt")
const ROOM := """
####################
#P.........C.......#
#..................#
#.........A........#
#..................#
####################
"""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _make_world(hero_count: int = 1, layout: String = ROOM) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in hero_count:
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = &"knight"
	var data := LevelData.new()
	data.display_name = "Onboarding test"
	data.layout = layout
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
	_tree().paused = false
	InputRouter.unassign_all()
	GameState.clear_players()
	Settings.reset()


func test_controller_family_from_its_name() -> void:
	assert_eq(PlayerInput.pad_family("PS5 Controller"), PlayerInput.PadFamily.PLAYSTATION)
	assert_eq(PlayerInput.pad_family("DualSense Wireless Controller"), PlayerInput.PadFamily.PLAYSTATION)
	assert_eq(PlayerInput.pad_family("Nintendo Switch Pro Controller"), PlayerInput.PadFamily.NINTENDO)
	assert_eq(PlayerInput.pad_family("Xbox Wireless Controller"), PlayerInput.PadFamily.XBOX)
	assert_eq(PlayerInput.pad_family(""), PlayerInput.PadFamily.XBOX, "unknown pads get Xbox names")


func test_every_button_icon_is_in_the_font() -> void:
	for family: int in PlayerInput.PAD_GLYPHS:
		for action: int in PlayerInput.PAD_GLYPHS[family]:
			var glyph: String = PlayerInput.PAD_GLYPHS[family][action]
			assert_true(FONT.has_char(glyph.unicode_at(0)), "family %d action %d has an icon" % [family, action])
	for action: int in PlayerInput.KEY_GLYPHS:
		var text: String = PlayerInput.KEY_GLYPHS[action]
		assert_true(FONT.has_char(text.unicode_at(0)))
	var keyboard := PlayerInput.new(0)
	keyboard.device = PlayerInput.DEVICE_KEYBOARD
	assert_eq(keyboard.glyph(PlayerInput.Action.ULTIMATE), "[Q]")
	assert_eq(keyboard.glyph(PlayerInput.Action.ATTACK), "", "left mouse button icon")


func test_tips_show_once_and_are_remembered() -> void:
	var world := _make_world()
	world.tip(&"test_tip", "Hello")
	assert_eq(world.hud._tip_label.text, "Hello")
	assert_true(Settings.seen_tips.has(&"test_tip"), "remembered")
	world.hud._tip_label.text = ""
	world.tip(&"test_tip", "Hello")
	assert_eq(world.hud._tip_label.text, "", "never twice")
	Settings.tips = false
	world.tip(&"another_tip", "Hi")
	assert_eq(world.hud._tip_label.text, "", "none when tips are off")
	_teardown(world)


func test_controls_card_shows_until_the_buttons_are_used() -> void:
	var world := _make_world()
	var hero := world.heroes[0]
	assert_true(world.hud._card_time[0] > 0.0, "the card shows when the hero arrives")
	for k in 3:
		hero.used_abilities[k] = 1
	for f in 60:
		world.hud._update_cards(1.0 / 60.0)
	assert_eq(world.hud._card_time[0], 0.0, "gone once attack, special and movement were used")
	_teardown(world)


func test_chests_and_shrines_explain_themselves_up_close() -> void:
	var world := _make_world()
	var hero := world.heroes[0]
	var chest: Interactable
	for it in world.interactables:
		if it.kind == Interactable.Kind.CHEST:
			chest = it
	hero.position = chest.position + Vector2(40, 0)  # (away from the shrine)
	world._check_interactables()
	assert_true(chest.near, "close enough to read it")
	assert_false(chest.used, "not touched yet")
	assert_true(world.hud._tip_label.text.contains("chest"), "a tip explains it")
	_teardown(world)


func test_builds_and_controls_pages() -> void:
	var world := _make_world()
	var hero := world.heroes[0]
	var library := UpgradePool.shared_library()
	hero.apply_upgrade(library.find(&"sharpened"))
	hero.apply_upgrade(library.find(&"sharpened"))
	hero.apply_upgrade(library.find(&"fire_1"))
	hero.apply_upgrade(library.find(&"fire_2"))
	var texts := PackedStringArray()
	for line: Array in PauseMenu.build_lines(hero):
		texts.append(line[0])
	assert_true(texts.has("Sharpened  x2"), "stacks shown: %s" % [texts])
	assert_true(texts.has("Fire II  Wildfire"), "elements at their highest tier")
	assert_false(texts.has("Fire I  Ember Strikes"), "lower tiers folded in")
	var controls := PauseMenu.controls_lines(hero)
	assert_eq(controls[1][0], hero.data.description, "what the hero is about")
	assert_true(String(controls[2][0]).contains(hero.attack().display_name))
	assert_true(String(controls[2][0]).begins_with(hero.input.glyph(PlayerInput.Action.ATTACK)))
	_teardown(world)


func test_waiting_for_teammates_at_the_exit() -> void:
	var world := _make_world(2, """
################
#P............X#
#..............#
################
""")
	var director := world.director
	director.exit_open = true
	var exit := world.level.exit_center()
	world.heroes[0].position = exit
	world.heroes[1].position = LevelGrid.cell_center(Vector2i(2, 2))
	director._check_exit(1.0 / 60.0)
	assert_eq(director.objective, "Waiting for P2 at the exit")
	world.heroes[1].position = exit
	director._check_exit(1.0 / 60.0)
	assert_false(director.objective.begins_with("Waiting"), "everyone's in")
	_teardown(world)
