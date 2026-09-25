class_name LevelData
extends Resource
## A level's layout and settings. Layout legend (one character per 16px tile):
##   #  wall            (space) void / outside
##   .  floor           P  player spawn (floor)
##   X  exit portal     S  enemy spawn hint (floor)
##   D  door (floor until an arena room locks it)

@export var display_name := "Level"
@export_multiline var layout := ""
