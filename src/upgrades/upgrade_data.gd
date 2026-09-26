class_name UpgradeData
extends Resource
## One upgrade card. Effects are short text rules so they stay easy to author
## in the inspector or the generator:
##   "stat <name> flat <amount>"         e.g. "stat max_hp flat 20"
##   "stat <name> pct <amount>"          e.g. "stat damage pct 0.1"
##   "ability <slot|all> <mod> <amount>" e.g. "ability attack pierce 1"
## Slots: attack, special, movement, ultimate, all. Mod keys are read by the
## abilities through Ability.mod() (count, pierce, area_pct, cooldown_pct, ...).

enum Rarity { COMMON, RARE, EPIC }

const RARITY_WEIGHTS: Array[float] = [10.0, 4.0, 1.2]
const RARITY_COLORS: Array[Color] = [Color("c8c8d0"), Color("5aa8f0"), Color("c070f0")]
const RARITY_NAMES: Array[String] = ["Common", "Rare", "Epic"]

@export var id: StringName = &""
@export var display_name := ""
@export_multiline var description := ""
@export var rarity: Rarity = Rarity.COMMON
@export var max_stacks := 5
## Empty: any hero. Otherwise only offered to this hero.
@export var hero_id: StringName = &""
@export var effects := PackedStringArray()


func weight() -> float:
	var w := RARITY_WEIGHTS[rarity]
	return w * (1.6 if hero_id != &"" else 1.0)
