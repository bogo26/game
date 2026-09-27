class_name Elites
extends RefCounted
## Elite enemies: from level 2 on, about 1 in 40 walking enemies arrives as
## an elite - drawn half again as big, with a glowing outline in its
## trait's colour, six times the HP, a quarter more damage, half the knockback
## - and one trait:
##   Swift      +60% speed
##   Volatile   blows up 0.6 s after it dies (telegraphed), hurting heroes
##   Splitting  breaks into three ordinary enemies of its kind
## Each elite drops a big XP gem and sometimes a heart. Elites are separate
## enemy types (made here from the base ones), so HordeSim needs nothing new
## per enemy.

enum Trait { NONE, SWIFT, VOLATILE, SPLITTING }

const NAMES: Array[String] = ["", "Swift", "Volatile", "Splitting"]
## Outline colours, shared with atlas_instance.gdshader.
const COLORS: Array[Color] = [Color.WHITE, Color(0.45, 0.95, 1.0), Color(1.0, 0.55, 0.15), Color(0.6, 1.0, 0.35)]
## Kinds that come in elite versions: every walking kind but the revenant
## (it already comes back once).
const BASES: Array[StringName] = [&"swarmer", &"brute", &"spitter", &"exploder", &"bat", &"drowned",
	&"bone_archer", &"sporecap", &"frost_boar", &"salamander", &"imp", &"sporeling", &"eel", &"puffball",
	&"frost_wraith"]

const CHANCE := 1.0 / 40.0
const MAX_ALIVE := 4
const HP_MULT := 6.0
const DAMAGE_MULT := 1.25
const KNOCKBACK_MULT := 0.5
const SCALE := 1.5
const SWIFT_SPEED := 1.6
const XP := 10
const HEART_CHANCE := 0.3
const VOLATILE_DELAY := 0.6
const VOLATILE_RADIUS := 36.0
const VOLATILE_DAMAGE := 25.0
const SPLIT_COUNT := 3


## An elite version of `base` with `elite_trait`.
static func make(base: EnemyData, elite_trait: Trait) -> EnemyData:
	var e := base.duplicate() as EnemyData
	e.id = StringName("%s_%s" % [base.id, NAMES[elite_trait].to_lower()])
	e.base_id = base.id
	e.elite_trait = elite_trait
	e.max_hp = base.max_hp * HP_MULT
	e.contact_damage = base.contact_damage * DAMAGE_MULT
	e.projectile_damage = base.projectile_damage * DAMAGE_MULT
	e.explosion_damage = base.explosion_damage * DAMAGE_MULT
	e.cloud_damage = base.cloud_damage * DAMAGE_MULT
	e.knockback_taken = base.knockback_taken * KNOCKBACK_MULT
	e.radius = base.radius * 1.3
	e.hurt_size = base.hurt_size * SCALE
	e.draw_scale = SCALE
	e.xp = XP
	if elite_trait == Trait.SWIFT:
		e.speed = base.speed * SWIFT_SPEED
	return e


## Every elite version of the kinds in `types` that come as elites.
static func variants(types: Array[EnemyData]) -> Array[EnemyData]:
	var out: Array[EnemyData] = []
	for data in types:
		if data.id in BASES:
			for elite_trait: int in [Trait.SWIFT, Trait.VOLATILE, Trait.SPLITTING]:
				out.append(make(data, elite_trait as Trait))
	return out
