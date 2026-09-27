class_name UpgradeData
extends Resource
## One upgrade card. Effects are short text rules so they stay easy to author
## in the inspector or the generator:
##   "stat <name> flat <amount>"         e.g. "stat max_hp flat 20"
##   "stat <name> pct <amount>"          e.g. "stat damage pct 0.1"
##   "ability <slot|all> <mod> <amount>" e.g. "ability attack pierce 1"
## Slots: attack, special, movement, ultimate, all. Mod keys are read by the
## abilities through Ability.mod() (count, pierce, area_pct, cooldown_pct, ...).
## Elemental upgrades come in chains of three tiers ("ability attack fire 1"
## each); a tier is only offered once the one it `requires` was taken.
## Legendaries (the mini boss's reward, never in ordinary offers) turn one of
## a hero's abilities into a new form: `form_slot` says which, and the form is
## the ability template at form_path() (see tools/gen_hero_data.py).

enum Rarity { COMMON, RARE, EPIC, LEGENDARY }

const RARITY_WEIGHTS: Array[float] = [10.0, 4.0, 1.2, 0.0]
const RARITY_COLORS: Array[Color] = [Color("c8c8d0"), Color("5aa8f0"), Color("c070f0"), Color("ffae3c")]
const RARITY_NAMES: Array[String] = ["Common", "Rare", "Epic", "Legendary"]
const FORM_PATH := "res://src/heroes/data/forms/%s.tres"

@export var id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""
@export var rarity: Rarity = Rarity.COMMON
@export var max_stacks := 5
## Empty: any hero. Otherwise only offered to this hero.
@export var hero_id: StringName = &""
@export var effects := PackedStringArray()
## Only offered after this upgrade was taken (the previous tier of a chain).
@export var requires: StringName = &""
## Elemental chains: the element's mod key (fire, ice, poison, lightning) and
## this card's tier (1-3), for the card's look.
@export var element: StringName = &""
@export var tier := 0
## Extra offer weight (next tiers of a chain the hero already started).
@export var weight_bonus := 1.0
## Only useful with teammates (e.g. faster revives): never offered solo.
@export var team_only := false
## Legendaries: the ability slot (Ability.Slot) this card transforms; -1 otherwise.
@export var form_slot := -1


func is_legendary() -> bool:
	return form_slot >= 0


## The ability template a legendary turns its slot into.
func form_path() -> String:
	return FORM_PATH % id


func weight() -> float:
	var w := RARITY_WEIGHTS[rarity] * weight_bonus
	return w * (1.6 if hero_id != &"" else 1.0)
