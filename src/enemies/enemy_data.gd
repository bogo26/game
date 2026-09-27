class_name EnemyData
extends Resource
## Stats and visuals for one enemy kind. HordeSim copies these into packed
## per-type arrays at setup, so changing a resource at runtime has no effect.

enum Behavior {
	CHASER,    ## walks straight at the nearest hero along the flow field
	RANGED,    ## keeps distance and fires projectiles when in line of sight
	EXPLODER,  ## rushes in, stops to telegraph, then explodes
	BOSS,      ## body only: a boss controller node moves it and drives attacks
	OBJECT,    ## breakable scenery (barrels, urns): not an enemy, never moves
	NEST,      ## stationary spawner the LevelDirector wakes up; counts as an enemy
	CHARGER,   ## lines up on a hero, winds up (a warning band), then charges in a straight line
	BLINKER,   ## walks, and every so often blinks to a hero's side through a small portal
	PILE,      ## a heap of bones: gets back up as what it was unless it's smashed first
}
## What it does when destroyed.
enum OnDeath {
	NONE,
	EXPLODE,  ## blasts enemies (and other objects) in explosion_radius
	LOOT,     ## scatters loot_xp worth of XP gems, sometimes a heart
	SPORES,   ## leaves a spore cloud (explosion_radius, cloud_time) that hurts heroes inside
	BONES,    ## collapses into a bone pile that gets back up unless it's smashed
}
## What a RANGED enemy fires.
enum Shot {
	SPIT,   ## a shot at the nearest hero when the wind-up ends
	AIMED,  ## aims when the wind-up starts, shows it as a line, and the shot flies along it
	LOB,    ## lobs a bomb where the hero stands; it bursts (explosion_radius, explosion_damage)
}

@export var id: StringName = &"swarmer"
@export var max_hp := 10.0
@export var speed := 45.0
## Footprint circle at the feet: walls, crowding and contact damage.
@export var radius := 5.0
## What shots can hit: a box (width, height) standing on the feet, centred on
## them. Size it to the drawn body (tests/test_hurtboxes.gd checks it against
## the art), so a shot that visibly crosses the head or body connects.
@export var hurt_size := Vector2(14, 15)
@export var contact_damage := 8.0
@export var xp := 1
## Multiplier on knockback received (big enemies < 1).
@export var knockback_taken := 1.0
@export var behavior := Behavior.CHASER
@export var on_death := OnDeath.NONE

@export_group("Movement")
## Flies: water doesn't slow it and it never goes over a chasm's edge.
@export var flying := false
## > 0: swims, moving this many times its speed through water instead of wading.
@export var swim_speed := 0.0
## Flutters from side to side as it goes (a share of its speed).
@export var weave := 0.0
## Spawns in packs of this many.
@export var pack := 1

@export_group("Ranged / exploder")
@export var attack_range := 110.0
@export var attack_cooldown := 2.2
## Seconds it stands still and glows before a shot, a charge or a blink.
@export var windup_time := 0.4
@export var shot := Shot.SPIT
@export var projectile_damage := 8.0
@export var projectile_speed := 120.0
@export var explosion_radius := 28.0
@export var explosion_damage := 22.0
@export var fuse_time := 0.7

@export_group("Charger")
@export var charge_speed := 190.0
@export var charge_time := 0.9

@export_group("Breakables and remains")
@export var loot_xp := 0
## SPORES: how long the cloud lasts (it hurts for explosion_damage a tick).
@export var cloud_time := 4.0
## PILE: seconds until it gets back up.
@export var reform_time := 4.0

@export_group("Visuals")
## Row in assets/sprites/enemies/horde_atlas.png (8 cells per row).
@export var atlas_row := 0
@export var walk_frames := 4
@export var anim_fps := 8.0
## Drawn this much bigger (elites).
@export var draw_scale := 1.0

@export_group("Elite")
## Elites.Trait (0 = an ordinary enemy) and the kind it's an elite of.
@export var elite_trait := 0
@export var base_id: StringName = &""


## Doesn't walk on its own: moved by a controller (boss) or fixed in place.
func is_static() -> bool:
	return behavior == Behavior.BOSS or behavior == Behavior.OBJECT or behavior == Behavior.NEST \
		or behavior == Behavior.PILE


## Speed factor in water: flyers don't notice it, swimmers speed up, the rest wade.
func water_speed() -> float:
	if flying:
		return 1.0
	return swim_speed if swim_speed > 0.0 else LevelGrid.WATER_SPEED
