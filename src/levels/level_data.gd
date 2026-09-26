class_name LevelData
extends Resource
## A level's layout and settings. Layout legend (one character per 16px tile):
##   #  wall            (space) void / outside
##   .  floor           P  player spawn (floor)
##   X  exit portal     S  enemy spawn hint (floor)
##   D  door (floor until an arena room locks it)
##   1-9 arena room floor (room id); doors touching a room belong to it
##   B  boss spawn point (floor)

@export var display_name := "Level"
@export_multiline var layout := ""

@export_group("Difficulty")
## Relative spawn weights by enemy id (swarmer, brute, spitter, exploder).
@export var enemy_weights: Dictionary = {&"swarmer": 1.0}
## Multiplies enemy HP on top of the player-count scaling.
@export var hp_multiplier := 1.0
## Corridor pressure: fraction of the player-count alive cap outside arenas.
@export var corridor_cap_fraction := 0.45
@export var corridor_spawn_rate := 18.0
## Kills needed to clear each arena room (index = room id - 1), for one
## player; scaled up with more players.
@export var arena_quotas := PackedInt32Array([50])
@export var arena_spawn_rate := 28.0

@export_group("Look")
@export var tint := Color.WHITE

@export_group("Boss")
@export var is_boss_level := false
