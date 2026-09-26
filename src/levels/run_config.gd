class_name RunConfig
extends Resource
## The sequence of levels in a run (src/levels/run_config.tres). Each level
## may have a second layout; every run picks one per level and randomly
## mirrors it (the boss level only left-right), so the run isn't memorised.

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


static func load_default() -> RunConfig:
	return load(PATH) as RunConfig
