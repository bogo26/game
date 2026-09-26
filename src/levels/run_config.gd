class_name RunConfig
extends Resource
## The sequence of levels in a run (src/levels/run_config.tres): levels 1-3,
## the mini boss, levels 4-6 and the final boss. Each level may have a second
## layout; every run picks one per level and randomly mirrors it (boss levels
## only left-right), so the run isn't memorised.

const PATH := "res://src/levels/run_config.tres"

@export var levels: Array[LevelData] = []
## Second layouts: alternates[i] can stand in for levels[i] (null = none).
@export var alternates: Array[LevelData] = []


## Every layout a run can use (tests check them all).
func all_layouts() -> Array[LevelData]:
	var out: Array[LevelData] = []
	out.append_array(levels)
	for data in alternates:
		if data:
			out.append(data)
	return out


## The layout for level `index` of a run seeded with `seed_value`: which
## layout and how it's mirrored come from the seed, so a run is repeatable.
func layout_for(index: int, seed_value: int) -> LevelData:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value * 7919 + index)
	var data := levels[index]
	if index < alternates.size() and alternates[index] and rng.randf() < 0.5:
		data = alternates[index]
	var flip_h := rng.randf() < 0.5
	var flip_v := rng.randf() < 0.5 and not data.is_boss_level
	return data.mirrored(flip_h, flip_v)


## The banner title for level `index`: regular levels count on their own
## ("LEVEL 4" comes after the mini boss), boss levels say which boss it is.
func title(index: int) -> String:
	var data := levels[index]
	if data.is_boss_level:
		return "FINAL BOSS" if data.is_final_boss else "MINI BOSS"
	return "LEVEL %d" % level_number(index)


## 1-based number of the regular level at `index`, not counting boss levels.
func level_number(index: int) -> int:
	var n := 0
	for k in mini(index + 1, levels.size()):
		if not levels[k].is_boss_level:
			n += 1
	return n


static func load_default() -> RunConfig:
	return load(PATH) as RunConfig
