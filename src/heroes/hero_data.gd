class_name HeroData
extends Resource
## A playable hero: base stats and the four ability slots. Ability resources
## are templates; every Hero duplicates them so two players can pick the same
## hero without sharing cooldowns.

@export var id: StringName = &"knight"
@export var display_name := "Knight"
@export var role := "Tank"
@export_multiline var description := ""
@export var max_hp := 100.0
@export var move_speed := 88.0
@export var armor := 0.0
@export var crit_chance := 0.05
## Damage the hero must deal to fill the ultimate meter once.
@export var ult_cost := 600.0

@export_group("Abilities")
@export var attack: Ability
@export var special: Ability
@export var movement: Ability
@export var ultimate: Ability


func abilities() -> Array[Ability]:
	return [attack, special, movement, ultimate]
