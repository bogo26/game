class_name LevelData
extends Resource
## A level's layout and settings. Layout legend (one character per 16px tile):
##   #  wall            (space) void / outside
##   .  floor           P  player spawn (floor)
##   X  exit portal     S  enemy spawn hint (floor)
##   D  door (floor until an arena room locks it)
##   1-9 arena room floor (room id): everything inside the room's walls
##      belongs to it; doors touching a room belong to it
##   B  boss spawn point (floor)
##   ~  water (slows walkers)      :  chasm (no walking; shots fly over)
##   ^  spike trap
##   b  explosive barrel   u  urn (loot)   N  enemy nest (spawner)
##   C  treasure chest     A  shrine (team blessing)

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
## Tile sheet: assets/tiles/tiles_<theme>.png (crypt, flooded, bones, ossuary,
## fungal, frost, forge, throne).
@export var theme: StringName = &"crypt"
@export var tint := Color.WHITE

@export_group("Boss")
## A boss level: its one arena room (the boss room, holding B) is a boss fight
## instead of waves. Beating a mini boss opens the level's exit portal (behind
## the boss room); beating the final boss wins the run, so its level has no exit.
@export var is_boss_level := false
@export var is_final_boss := false
## The boss waiting in the boss room (a scene whose root is a Boss).
@export_file("*.tscn") var boss_scene := "res://src/enemies/boss/boss_demon.tscn"
## What the objective calls the boss room before the fight: "Enter the <boss_room>".
@export var boss_room := "throne room"


## A copy with the layout flipped left-right and/or upside down (runs vary
## their levels this way). Everything in a layout is position-only, so a
## mirrored level plays the same, just the other way round.
func mirrored(flip_h: bool, flip_v: bool) -> LevelData:
	var copy := duplicate() as LevelData
	if not flip_h and not flip_v:
		return copy
	var rows := Level._parse_rows(layout)
	var width := 0
	for row in rows:
		width = maxi(width, row.length())
	var out := PackedStringArray()
	for row in rows:
		var padded := row + " ".repeat(width - row.length())
		out.append(padded.reverse() if flip_h else padded)
	if flip_v:
		out.reverse()
	copy.layout = "\n".join(out)
	return copy
