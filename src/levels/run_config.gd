class_name RunConfig
extends Resource
## The sequence of levels in a run (src/levels/run_config.tres).

const PATH := "res://src/levels/run_config.tres"

@export var levels: Array[LevelData] = []


static func load_default() -> RunConfig:
	return load(PATH) as RunConfig
