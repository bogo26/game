extends "res://tests/test_case.gd"


func test_stats_math() -> void:
	var s := Stats.new()
	s.set_base(Stats.MAX_HP, 100.0)
	s.add_flat(Stats.MAX_HP, 20.0)
	s.add_pct(Stats.MAX_HP, 0.1)
	assert_near(s.get_value(Stats.MAX_HP), 132.0)
	s.add_pct(Stats.MAX_HP, -2.0)
	assert_near(s.get_value(Stats.MAX_HP), 0.0, 0.0001, "percent can't go below zero")
	assert_near(s.get_value(&"unknown"), 0.0)


func test_every_library_upgrade_is_valid() -> void:
	var library := UpgradePool.shared_library()
	assert_true(library.upgrades.size() >= 30, "library has %d upgrades" % library.upgrades.size())
	var ids := {}
	for u in library.upgrades:
		assert_false(ids.has(u.id), "duplicate id %s" % u.id)
		ids[u.id] = true
		var problems := UpgradePool.validate(u)
		assert_true(problems.is_empty(), ", ".join(problems))
		assert_true(u.max_stacks >= 1)
		if u.hero_id != &"":
			assert_true(ResourceLoader.exists("res://src/heroes/data/%s.tres" % u.hero_id),
				"%s targets a real hero" % u.id)


func test_each_hero_has_its_own_upgrades() -> void:
	var counts := {}
	for u in UpgradePool.shared_library().upgrades:
		if u.hero_id != &"":
			counts[u.hero_id] = int(counts.get(u.hero_id, 0)) + 1
	for hero_id: StringName in [&"knight", &"ranger", &"mage", &"cleric"]:
		assert_true(int(counts.get(hero_id, 0)) >= 4, "%s has hero-specific upgrades" % hero_id)


func test_offers_respect_hero_and_stacks() -> void:
	var pool := UpgradePool.new(null, 42)
	var stacks := {}
	for u in pool.library.upgrades:
		if u.id != &"sharpened" and u.hero_id == &"":
			stacks[u.id] = u.max_stacks  # everything generic maxed except one
	for round in 50:
		var offers := pool.roll_offers(&"ranger", stacks, 3)
		assert_true(offers.size() <= 3)
		var seen := {}
		for u in offers:
			assert_false(seen.has(u.id), "no duplicate cards in one offer")
			seen[u.id] = true
			assert_true(u.hero_id == &"" or u.hero_id == &"ranger", "no other hero's cards (%s)" % u.id)
			assert_true(int(stacks.get(u.id, 0)) < u.max_stacks, "no maxed cards (%s)" % u.id)


func test_apply_effects_stats_and_ability_mods() -> void:
	var stats := Stats.new()
	stats.set_base(Stats.DAMAGE, 1.0)
	var a := ProjectileAbility.new()
	var b := MeleeArcAbility.new()
	var c := DashAbility.new()
	var d := ChannelAbility.new()
	var abilities: Array[Ability] = [a, b, c, d]
	var u := UpgradeData.new()
	u.id = &"test"
	u.effects = PackedStringArray(["stat damage pct 0.5", "ability attack pierce 2", "ability all area_pct 0.1"])
	assert_true(UpgradePool.apply_effects(u, stats, abilities))
	assert_near(stats.get_value(Stats.DAMAGE), 1.5)
	assert_near(a.mod(&"pierce"), 2.0)
	assert_near(b.mod(&"pierce"), 0.0, 0.0001, "slot-specific mod only hits its slot")
	for ability in abilities:
		assert_near(ability.mod(&"area_pct"), 0.1)


func test_malformed_upgrade_applies_nothing() -> void:
	expected_errors = 1
	var stats := Stats.new()
	stats.set_base(Stats.DAMAGE, 1.0)
	var abilities: Array[Ability] = [ProjectileAbility.new()]
	var u := UpgradeData.new()
	u.id = &"broken"
	u.effects = PackedStringArray(["stat damage pct 0.5", "oops"])
	assert_false(UpgradePool.apply_effects(u, stats, abilities))
	assert_near(stats.get_value(Stats.DAMAGE), 1.0, 0.0001, "no partial application")
	assert_false(UpgradePool.validate(u).is_empty())
