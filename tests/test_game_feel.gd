extends "res://tests/test_case.gd"
## Game feel: low-HP warnings, ability ready / denied cues, the ultimate
## announcing itself once per charge, hitstop, hero damage numbers that the
## horde can't push out, and key sounds with voices of their own.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0
const ROOM := """
##############
#P...........#
#............#
#............#
##############
"""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _make_world(hero_id: StringName = &"knight") -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = hero_id
	var data := LevelData.new()
	data.display_name = "Feel test"
	data.layout = ROOM
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


## Counts emissions of an Events signal while `body` runs.
func _count(sig: Signal, body: Callable) -> int:
	var hits := [0]
	var counter := func(_a: Variant = null, _b: Variant = null) -> void: hits[0] += 1
	sig.connect(counter)
	body.call()
	sig.disconnect(counter)
	return hits[0]


## One fresh press of `action` (released before and after).
func _press(hero: Hero, action: PlayerInput.Action) -> void:
	hero.input.set_action(action, false)
	hero.input.consume_presses()
	hero.input.set_action(action, true)
	hero.tick(DT)
	hero.input.set_action(action, false)
	hero.input.consume_presses()


func test_low_hp_warns_once_per_crossing() -> void:
	var world := _make_world()
	var hero := world.heroes[0]
	var n := _count(Events.hero_low_hp, func() -> void:
		hero.take_hit(hero.max_hp * 0.75)  # to ~25%
		hero.invulnerable_time = 0.0
		hero.take_hit(2.0)                 # still low: no second warning
		hero.tick(DT))
	assert_eq(n, 1, "warned when crossing into low HP")
	assert_true(hero.is_low_hp())
	hero.heal(hero.max_hp)
	hero.tick(DT)
	assert_false(hero.is_low_hp(), "healed out of it")
	hero.invulnerable_time = 0.0
	n = _count(Events.hero_low_hp, func() -> void: hero.take_hit(hero.max_hp * 0.8))
	assert_eq(n, 1, "warns again on the next crossing")
	hero.go_down()
	assert_false(hero.is_low_hp(), "downed heroes aren't 'low'")
	_teardown(world)


func test_ultimate_announces_once_per_charge() -> void:
	var world := _make_world()
	var hero := world.heroes[0]
	hero.ult_charge = 0.99
	var n := _count(Events.ult_ready, func() -> void:
		hero.add_ult_charge(1000.0)
		for f in 10:
			hero.tick(DT))
	assert_eq(n, 1, "one announcement when it fills")
	_press(hero, PlayerInput.Action.ULTIMATE)
	assert_true(hero.ult_charge < 0.01, "ultimate used")
	n = _count(Events.ult_ready, func() -> void:
		hero.add_ult_charge(100000.0)
		hero.tick(DT))
	assert_eq(n, 1, "and again for the next charge")
	_teardown(world)


func test_presses_that_do_nothing_are_answered() -> void:
	var world := _make_world()
	var hero := world.heroes[0]
	hero.ult_charge = 0.0
	var denied := _count(Events.ability_denied, func() -> void:
		_press(hero, PlayerInput.Action.ULTIMATE))
	assert_eq(denied, 1, "ultimate without charge")
	assert_true(hero.denied_time[Ability.Slot.ULTIMATE] > 0.0, "its HUD bar flashes")
	_press(hero, PlayerInput.Action.SPECIAL)  # used: now on cooldown
	denied = _count(Events.ability_denied, func() -> void:
		_press(hero, PlayerInput.Action.SPECIAL))
	assert_eq(denied, 1, "special on cooldown")
	var ready := _count(Events.ability_ready, func() -> void:
		for f in int(hero.special().effective_cooldown() / DT) + 5:
			hero.tick(DT))
	assert_true(ready >= 1, "coming back off cooldown is announced")
	assert_true(hero.ready_flash[Ability.Slot.SPECIAL] > 0.0, "and its HUD bar flashes")
	_teardown(world)


func test_hitstop_freezes_then_slows_the_world() -> void:
	var world := _make_world()
	world._process(DT)
	var before := world.elapsed
	world.hitstop(0.1, 0.5)
	world._process(DT)
	assert_eq(world.elapsed, before, "frozen")
	assert_true(world.is_frozen())
	for f in 8:
		world._process(DT)
	assert_false(world.is_frozen(), "the freeze is short")
	before = world.elapsed
	world._process(DT)
	assert_near(world.elapsed - before, DT * World.SLOWMO_SCALE, 0.0001, "then slow motion")
	for f in 40:
		world._process(DT)
	before = world.elapsed
	world._process(DT)
	assert_near(world.elapsed - before, DT, 0.0001, "then full speed")
	_teardown(world)


func test_hero_damage_numbers_survive_a_crowd() -> void:
	var numbers := DamageNumbers.new()
	for k in DamageNumbers.MAX_NUMBERS:
		numbers.add(Vector2(k, 0), 15.0, Color.WHITE)
	numbers.add_hero_damage(Vector2.ZERO, 12.0, false)
	for k in DamageNumbers.MAX_NUMBERS * 2:
		numbers.add(Vector2(k, 0), 15.0, Color.WHITE)
	assert_true(numbers._color.has(DamageNumbers.HURT_COLOR), "the hero's number is still up")
	numbers.free()


func test_key_sounds_have_their_own_voices() -> void:
	var reserved_from := Audio.VOICES - Audio.PRIORITY_VOICES
	for k in 60:
		var voice := Audio.pick_voice(&"hit")
		assert_true(Audio._voices.find(voice) < reserved_from, "hit spam stays out of the reserved voices")
	for sound: StringName in [&"down", &"heartbeat", &"help", &"windup"]:
		assert_true(Audio._voices.find(Audio.pick_voice(sound)) >= reserved_from, "%s gets a reserved voice" % sound)
