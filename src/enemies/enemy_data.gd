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
}
## What a breakable object does when destroyed.
enum OnDeath {
	NONE,
	EXPLODE,  ## blasts enemies (and other objects) in explosion_radius
	LOOT,     ## scatters loot_xp worth of XP gems, sometimes a heart
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

@export_group("Ranged / exploder")
@export var attack_range := 110.0
@export var attack_cooldown := 2.2
@export var projectile_damage := 8.0
@export var projectile_speed := 120.0
@export var explosion_radius := 28.0
@export var explosion_damage := 22.0
@export var fuse_time := 0.7

@export_group("Breakables")
@export var on_death := OnDeath.NONE
@export var loot_xp := 0

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
	return behavior == Behavior.BOSS or behavior == Behavior.OBJECT or behavior == Behavior.NEST
