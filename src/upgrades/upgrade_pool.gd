class_name UpgradePool
extends RefCounted
## Rolls level-up offers and applies upgrades to heroes.

const LIBRARY_PATH := "res://src/upgrades/data/upgrade_library.tres"
const SLOT_NAMES := {&"attack": 0, &"special": 1, &"movement": 2, &"ultimate": 3}
## Every stat and ability mod key the game reads (used to validate the library).
const KNOWN_STATS: Array[StringName] = [
	Stats.MAX_HP, Stats.ARMOR, Stats.MOVE_SPEED, Stats.DAMAGE, Stats.ATTACK_SPEED,
	Stats.CRIT_CHANCE, Stats.CRIT_DAMAGE, Stats.PICKUP_RANGE, Stats.REGEN, Stats.ULT_CHARGE,
	Stats.LIFE_ON_KILL, Stats.REVIVE_SPEED,
]
const KNOWN_ABILITY_MODS: Array[StringName] = [
	&"damage_pct", &"cooldown_pct", &"area_pct", &"count", &"spread_deg", &"speed_pct",
	&"pierce", &"bounces", &"effect_time", &"arc_deg", &"stun_time", &"slow_time",
	&"distance_pct", &"iframes", &"end_burst", &"heal_allies", &"arrival_damage",
	&"duration", &"zone_damage", &"heal_pct", &"buff_damage", &"lifesteal", &"minion_hp_pct",
	&"max_active",
]

static var _shared_library: UpgradeLibrary

var library: UpgradeLibrary
var _rng := RandomNumberGenerator.new()


static func shared_library() -> UpgradeLibrary:
	if _shared_library == null:
		_shared_library = load(LIBRARY_PATH) as UpgradeLibrary
	return _shared_library


func _init(p_library: UpgradeLibrary = null, seed_value: int = -1) -> void:
	library = p_library if p_library != null else shared_library()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Up to `count` different upgrades this hero can still take, weighted by rarity.
func roll_offers(hero_id: StringName, stacks: Dictionary, count: int = 3) -> Array[UpgradeData]:
	var candidates: Array[UpgradeData] = []
	for u in library.upgrades:
		if u.hero_id != &"" and u.hero_id != hero_id:
			continue
		if int(stacks.get(u.id, 0)) >= u.max_stacks:
			continue
		candidates.append(u)
	var offers: Array[UpgradeData] = []
	while offers.size() < count and not candidates.is_empty():
		var total := 0.0
		for u in candidates:
			total += u.weight()
		var roll := _rng.randf() * total
		var picked := candidates.size() - 1
		for i in candidates.size():
			roll -= candidates[i].weight()
			if roll <= 0.0:
				picked = i
				break
		offers.append(candidates[picked])
		candidates.remove_at(picked)
	return offers


## Applies an upgrade's effects to a Stats object and ability list.
## Returns false (and applies nothing) if an effect line is malformed.
static func apply_effects(upgrade: UpgradeData, stats: Stats, abilities: Array[Ability]) -> bool:
	var parsed: Array = []
	for line in upgrade.effects:
		var parts := line.split(" ", false)
		if parts.size() != 4:
			push_error("upgrade %s: bad effect '%s'" % [upgrade.id, line])
			return false
		parsed.append(parts)
	for parts: PackedStringArray in parsed:
		var amount := parts[3].to_float()
		match parts[0]:
			"stat":
				if parts[2] == "pct":
					stats.add_pct(StringName(parts[1]), amount)
				else:
					stats.add_flat(StringName(parts[1]), amount)
			"ability":
				var key := StringName(parts[2])
				if parts[1] == "all":
					for ability in abilities:
						ability.add_mod(key, amount)
				elif SLOT_NAMES.has(StringName(parts[1])):
					abilities[SLOT_NAMES[StringName(parts[1])]].add_mod(key, amount)
				else:
					push_error("upgrade %s: unknown slot '%s'" % [upgrade.id, parts[1]])
			_:
				push_error("upgrade %s: unknown effect '%s'" % [upgrade.id, parts[0]])
	return true


## Returns a list of problems with an upgrade's effect lines (empty = valid).
static func validate(upgrade: UpgradeData) -> PackedStringArray:
	var problems := PackedStringArray()
	if upgrade.effects.is_empty():
		problems.append("%s: no effects" % upgrade.id)
	for line in upgrade.effects:
		var parts := line.split(" ", false)
		if parts.size() != 4 or not parts[3].is_valid_float():
			problems.append("%s: malformed '%s'" % [upgrade.id, line])
			continue
		match parts[0]:
			"stat":
				if StringName(parts[1]) not in KNOWN_STATS:
					problems.append("%s: unknown stat '%s'" % [upgrade.id, parts[1]])
				if parts[2] not in ["flat", "pct"]:
					problems.append("%s: unknown op '%s'" % [upgrade.id, parts[2]])
			"ability":
				if parts[1] != "all" and not SLOT_NAMES.has(StringName(parts[1])):
					problems.append("%s: unknown slot '%s'" % [upgrade.id, parts[1]])
				if StringName(parts[2]) not in KNOWN_ABILITY_MODS:
					problems.append("%s: unknown mod '%s'" % [upgrade.id, parts[2]])
			_:
				problems.append("%s: unknown effect '%s'" % [upgrade.id, parts[0]])
	return problems
