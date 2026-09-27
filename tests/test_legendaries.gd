extends "res://tests/test_case.gd"
## Legendary upgrades, the mini boss's reward: every hero has three, each
## turning a different ability into a new form. Beating a mini boss (never the
## final boss) opens a round offering each player their hero's three; the
## form keeps what the ability had, lasts the run, and no ultimate form
## charges itself. (What each form does: tests/test_forms.gd.)

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0
const HEROES: Array[StringName] = [&"knight", &"ranger", &"mage", &"cleric", &"berserker", &"rogue",
	&"engineer", &"necromancer"]
const ROOM := """
##############################
#............................#
#............................#
#............................#
#....P.......................#
#............................#
#............................#
#............................#
##############################
"""
## Where the pack stands, from the hero: in reach of every ultimate aimed
## right (the Tesla Grid's link to the Engineer included).
const PACK: Array[Vector2] = [Vector2(10, -4), Vector2(12, 5), Vector2(26, 0), Vector2(30, -8), Vector2(30, 8),
	Vector2(36, 0), Vector2(40, -8), Vector2(40, 8)]


func _make_world(hero_id: StringName) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = hero_id
	var data := LevelData.new()
	data.display_name = "Legendary test"
	data.layout = ROOM
	data.corridor_spawn_rate = 0.0
	data.arena_quotas = PackedInt32Array([0, 0, 0])
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.spawn_enemies = false
	world.level_ups_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.bots = null
	world.heroes[0].god_mode = true
	world.heroes[0].input.uses_mouse = false
	world.heroes[0].input.aim = Vector2.RIGHT
	return world


## A run level (the mini or final boss's) with bot heroes in god mode.
func _run_world(data: LevelData, heroes: Array[StringName]) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	for i in heroes.size():
		InputRouter.assign(i, PlayerInput.DEVICE_BOT)
		GameState.slots[i].hero_id = heroes[i]
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.run_mode = true
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.level_up_delay = 0.0
	for hero in world.heroes:
		hero.god_mode = true
	return world


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	(Engine.get_main_loop() as SceneTree).paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


func _legendaries(hero_id: StringName) -> Array[UpgradeData]:
	var out: Array[UpgradeData] = []
	for u in UpgradePool.shared_library().upgrades:
		if u.is_legendary() and u.hero_id == hero_id:
			out.append(u)
	return out


func _all_legendaries() -> Array[UpgradeData]:
	var out: Array[UpgradeData] = []
	for hero_id in HEROES:
		out.append_array(_legendaries(hero_id))
	return out


## Whether `script` is `base` or extends it.
func _extends(script: Script, base: Script) -> bool:
	while script != null:
		if script == base:
			return true
		script = script.get_base_script()
	return false


## A brute at `p` (returns its uid).
func _enemy(world: World, p: Vector2, hp: float = 1e6) -> int:
	var horde := world.horde
	var i := horde.spawn(horde.type_index(&"brute"), p)
	horde.hp[i] = hp
	horde.update(0.0, PackedVector2Array())
	return horde.uid[i]


## World frames with every enemy held in place (only hits and pulls move it).
func _hold(world: World, seconds: float, signal_attacks: bool = false) -> void:
	for f in int(seconds / DT):
		for i in world.horde.count:
			world.horde.stun[i] = maxf(world.horde.stun[i], 1.0)
		if signal_attacks and f % 12 == 0:
			world.heroes[0].attack_performed.emit(Vector2.RIGHT)
		world._process(DT)


# --- the cards -----------------------------------------------------------------------------

func test_every_hero_has_three_legendaries_on_three_abilities() -> void:
	for hero_id in HEROES:
		var cards := _legendaries(hero_id)
		assert_eq(cards.size(), 3, "%s has three legendaries" % hero_id)
		var data := load(Hero.HERO_DATA_PATH % hero_id) as HeroData
		var slots := {}
		for u in cards:
			assert_true(UpgradePool.validate(u).is_empty(), ", ".join(UpgradePool.validate(u)))
			assert_eq(u.rarity, UpgradeData.Rarity.LEGENDARY, u.id)
			assert_eq(u.max_stacks, 1, u.id)
			assert_true(u.description.length() <= 88, "%s: card text fits a 4-player card" % u.id)
			slots[u.form_slot] = true
			var base: Ability = data.abilities()[u.form_slot]
			var form := load(u.form_path()) as Ability
			assert_true(form != null, "%s: the form loads" % u.id)
			if form == null:
				continue
			assert_true(_extends(form.get_script(), base.get_script()),
				"%s: the form extends the ability it replaces, so that ability's upgrades still work" % u.id)
			assert_true(form.display_name != base.display_name, "%s: the ability gets a new name" % u.id)
			assert_true(form.description != "", u.id)
		assert_eq(slots.size(), 3, "%s: each legendary transforms a different ability" % hero_id)


func test_ordinary_offers_never_include_legendaries() -> void:
	var pool := UpgradePool.new(null, 5)
	for hero_id in HEROES:
		for round in 60:
			for u in pool.roll_offers(hero_id, {}):
				assert_false(u.is_legendary(), "%s offered in an ordinary round" % u.id)


func test_the_legendary_round_offers_the_heros_own_three() -> void:
	var pool := UpgradePool.new(null, 5)
	var ids := func(cards: Array[UpgradeData]) -> Array[StringName]:
		var out: Array[StringName] = []
		for u in cards:
			out.append(u.id)
		return out
	assert_eq(ids.call(pool.legendary_offers(&"mage", {})),
		[&"mage_frozen_orb", &"mage_chronoshift", &"mage_singularity"] as Array[StringName], "in slot order")
	assert_eq(ids.call(pool.legendary_offers(&"mage", {&"mage_chronoshift": 1})),
		[&"mage_frozen_orb", &"mage_singularity"] as Array[StringName], "a transformed ability isn't offered again")
	assert_eq(LevelUpScreen.round_title(GameState.LEGENDARY_ROUND), "LEGENDARY!  TRANSFORM AN ABILITY")
	GameState.reset_run()
	GameState.add_xp(GameState.xp_to_next())
	GameState.add_legendary_pick()
	assert_eq(GameState.next_round(), GameState.LEGENDARY_ROUND, "shown before anything else")
	GameState.reset_run()


# --- the round after the mini boss -------------------------------------------------------------

func test_every_mini_boss_gives_a_legendary_round() -> void:
	var run := RunConfig.load_default()
	for data: LevelData in run.choices(3):
		var world := _run_world(data, [&"knight", &"cleric"])
		var room: LevelDirector.Room = world.director.rooms[0]
		for hero in world.heroes:
			hero.position = world.grid.nearest_open(room.center + Vector2(0, 60))
		for f in 2:
			world._process(DT)
		assert_true(world.boss != null, "%s: the boss woke up" % data.display_name)
		world.horde.damage(world.horde.index_of_uid(world.boss.uid), 1e9, Vector2.ZERO, 0)
		var frames := 0
		while not world.level_up.is_open() and frames < 600:
			world._process(DT)
			frames += 1
		assert_true(world.level_up.is_open(), "%s: the pick screen opened" % data.display_name)
		assert_true(frames * DT >= World.LEGENDARY_DELAY, "after the boss's death had its moment")
		assert_eq(world.level_up._title.text, "LEGENDARY!  TRANSFORM AN ABILITY")
		for pk: LevelUpScreen.Picker in world.level_up._pickers:
			assert_eq(pk.offers, _legendaries(pk.hero.hero_id), "%s gets its own three" % pk.hero.hero_id)
		var t := 0.0
		while world.level_up.is_open() and t < 8.0:
			InputRouter._process(DT)
			world.level_up._process(DT)
			t += DT
		assert_false(world.level_up.is_open(), "the bots picked and play resumed")
		for hero in world.heroes:
			var taken := GameState.slots[hero.slot].upgrades.filter(
				func(id: StringName) -> bool: return UpgradePool.shared_library().find(id).is_legendary())
			assert_eq(taken.size(), 1, "%s took one legendary" % hero.hero_id)
			var u := UpgradePool.shared_library().find(taken[0])
			var form := load(u.form_path()) as Ability
			assert_eq(hero.abilities[u.form_slot].display_name, form.display_name, "%s: its ability transformed" % hero.hero_id)
		_teardown(world)


func test_the_final_boss_gives_none() -> void:
	var run := RunConfig.load_default()
	var data: LevelData = run.choices(7)[0]
	var world := _run_world(data, [&"knight"])
	world.level_ups_enabled = false
	var room: LevelDirector.Room = world.director.rooms[0]
	world.heroes[0].position = world.grid.nearest_open(room.center + Vector2(0, 60))
	for f in 2:
		world._process(DT)
	assert_true(world.boss != null, "the final boss woke up")
	world.horde.damage(world.horde.index_of_uid(world.boss.uid), 1e9, Vector2.ZERO, 0)
	for f in 120:
		world._process(DT)
	assert_false(GameState.LEGENDARY_ROUND in GameState.pending_rounds, "the run is won, no legendary")
	_teardown(world)


# --- taking one ------------------------------------------------------------------------------

func test_the_form_keeps_what_the_ability_had() -> void:
	var world := _make_world(&"knight")
	var hero := world.heroes[0]
	var library := UpgradePool.shared_library()
	hero.apply_upgrade(library.find(&"knight_wide_slash"))
	hero.apply_upgrade(library.find(&"fire_1"))
	hero.attack().cooldown_left = 0.3
	hero.apply_upgrade(library.find(&"knight_crescent_wave"))
	assert_true(hero.attack() is CrescentWaveAbility, "the attack is the new form")
	assert_eq(hero.attack().display_name, "Crescent Wave")
	assert_near(hero.attack().mod(&"arc_deg"), 30.0, 0.001, "Wide Slash still widens the swing")
	assert_near(hero.attack().cooldown_left, 0.3, 0.001, "and the cooldown carries on")
	assert_eq(hero.elements, PackedInt32Array([1, 0, 0, 0]), "the attack keeps its element")
	assert_true(hero.attack().hero == hero and hero.attack().slot == Ability.Slot.ATTACK, "bound to the hero")
	var controls := PauseMenu.controls_lines(hero).map(func(line: Array) -> String: return String(line[0]))
	assert_true(controls.any(func(text: String) -> bool: return text.ends_with("Crescent Wave")),
		"the Controls page names the new form")
	assert_eq(String(PauseMenu.build_lines(hero)[1][0]), "Crescent Wave", "the Builds page lists it first")
	var wide_volley := library.find(&"ranger_wide_volley")
	_teardown(world)
	world = _make_world(&"ranger")
	hero = world.heroes[0]
	assert_true(LevelUpScreen.card_text(wide_volley, hero).begins_with("Fan Volley:"))
	hero.apply_upgrade(library.find(&"ranger_cluster_arrow"))
	assert_true(LevelUpScreen.card_text(wide_volley, hero).begins_with("Cluster Arrow:"),
		"hero cards name the ability's new form")
	_teardown(world)


func test_a_replaced_ability_lets_go() -> void:
	var world := _make_world(&"rogue")
	var hero := world.heroes[0]
	hero.ult_charge = 1.0
	assert_true(hero.ultimate().try_activate(Vector2.RIGHT), "the clones are out")
	var clones := hero.ultimate() as ShadowClonesAbility
	assert_true(clones.is_active())
	hero.apply_upgrade(UpgradePool.shared_library().find(&"rogue_shadow_hunt"))
	assert_false(clones.is_active(), "the old clones are gone")
	assert_eq(hero.attack_performed.get_connections().size(), 1, "only the new form listens to the attack")
	assert_true(hero.ultimate() is ShadowHuntAbility)
	_teardown(world)


func test_a_legendary_lasts_the_whole_run() -> void:
	var world := _make_world(&"mage")
	world.heroes[0].apply_upgrade(UpgradePool.shared_library().find(&"mage_frozen_orb"))
	var data := world.level_data
	world.get_parent().remove_child(world)
	world.free()
	var next: World = (load(WORLD_SCENE) as PackedScene).instantiate()  # the next level
	next.level_data = data
	next.spawn_enemies = false
	(Engine.get_main_loop() as SceneTree).root.add_child(next)
	assert_true(next.heroes[0].special() is FrozenOrbAbility, "re-applied when the level builds the hero")
	_teardown(next)


# --- the ultimate charge rule -----------------------------------------------------------------

func test_no_ultimate_form_charges_itself() -> void:
	for u in _all_legendaries():
		if u.form_slot != Ability.Slot.ULTIMATE:
			continue
		var world := _make_world(u.hero_id)
		var hero := world.heroes[0]
		hero.apply_upgrade(u)
		for offset in PACK:
			_enemy(world, hero.position + offset)
		var t0 := world.elapsed
		hero.ult_charge = 1.0
		hero.input.set_action(PlayerInput.Action.ULTIMATE, true)
		world._process(DT)
		hero.input.set_action(PlayerInput.Action.ULTIMATE, false)
		hero.input.consume_presses()
		assert_eq(hero.used_abilities[Ability.Slot.ULTIMATE], 1, "%s used its ultimate" % u.id)
		_hold(world, 11.0, true)
		if u.id != &"necro_lich_form":  # the Lich only raises what dies (nothing here)
			assert_true(GameState.slots[0].damage_dealt > 0.0, "%s: the ultimate hit the pack" % u.id)
		var passive := Hero.ULT_PASSIVE_PER_SECOND * hero.ult_charge_mult * (world.elapsed - t0)
		assert_near(hero.ult_charge, passive, 0.001,
			"%s: only the passive trickle charged it (dealt %.0f)" % [u.id, GameState.slots[0].damage_dealt])
		_teardown(world)


func test_the_lichs_skeletons_dont_charge_it_either() -> void:
	var world := _make_world(&"necromancer")
	var hero := world.heroes[0]
	hero.apply_upgrade(UpgradePool.shared_library().find(&"necro_lich_form"))
	hero.ult_charge = 1.0
	assert_true(hero.ultimate().try_activate(Vector2.RIGHT))
	for k in 3:  # three die near the Lich...
		var p := hero.position + Vector2(20 + k * 6, 0)
		world.horde.damage(world.horde.index_of_uid(_enemy(world, p, 5.0)), 100.0, Vector2.ZERO, hero.slot)
	world._process(DT)  # (the kills themselves charge it, as any kill would)
	hero.ult_charge = 0.0
	for offset in PACK:  # ...and rise to fight this pack
		_enemy(world, hero.position + offset)
	var t0 := world.elapsed
	_hold(world, 4.0)
	var raised := world.minions.filter(func(m: Minion) -> bool: return m.kind == Minion.Kind.SKELETON)
	assert_eq(raised.size(), 3, "every kill rose")
	assert_true(raised.all(func(m: Minion) -> bool: return m.ultimate), "as the ultimate's")
	assert_true(GameState.slots[0].damage_dealt > 0.0, "the risen fought")
	assert_near(hero.ult_charge, Hero.ULT_PASSIVE_PER_SECOND * hero.ult_charge_mult * (world.elapsed - t0), 0.001,
		"only the passive trickle charged it")
	_teardown(world)


# --- every form, played -------------------------------------------------------------------------

func test_every_legendary_plays_without_errors() -> void:
	for u in _all_legendaries():
		var world := _make_world(u.hero_id)
		var hero := world.heroes[0]
		var input := hero.input
		hero.apply_upgrade(u)
		var used := PackedByteArray([0, 0, 0, 0])
		for f in int(6.0 / DT):
			if f % 60 == 0 and world.horde.enemy_count() < 10:
				for k in 10:
					var at := hero.position + Vector2.from_angle(TAU * k / 10.0) * (30.0 + 10.0 * (k % 3))
					_enemy(world, world.grid.nearest_open(at), 40.0)
			InputRouter._process(DT)  # (last frame's buttons become "held before")
			var target := world.horde.nearest(hero.position, 200.0, false)
			input.aim = (world.horde.pos[target] - hero.position).normalized() if target != -1 else Vector2.RIGHT
			input.move = Vector2.from_angle(f * 0.05) * 0.5
			hero.ult_charge = 1.0
			for k in 4:
				hero.abilities[k].cooldown_left = minf(hero.abilities[k].cooldown_left, 0.4)
			input.set_action(PlayerInput.Action.ATTACK, true)
			input.set_action(PlayerInput.Action.SPECIAL, f % 30 == 0)
			input.set_action(PlayerInput.Action.MOVEMENT, f % 50 == 0)
			input.set_action(PlayerInput.Action.ULTIMATE, f % 120 == 0)
			world._process(DT)
			for k in 4:
				used[k] = used[k] | hero.used_abilities[k]
		assert_eq(used[u.form_slot], 1, "%s: the form was used" % u.id)
		assert_true(GameState.slots[0].damage_dealt > 0.0, "%s: the hero fought" % u.id)
		_teardown(world)
