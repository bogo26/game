class_name EnemyData
extends Resource
## Stats and visuals for one enemy kind. HordeSim copies these into packed
## per-type arrays at setup, so changing a resource at runtime has no effect.

enum Behavior {
	CHASER,    ## walks straight at the nearest hero along the flow field
	RANGED,    ## keeps distance and fires projectiles when in line of sight
	EXPLODER,  ## rushes in, stops to telegraph, then explodes
}

@export var id: StringName = &"swarmer"
@export var max_hp := 10.0
@export var speed := 45.0
@export var radius := 5.0
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

@export_group("Visuals")
## Row in assets/sprites/enemies/horde_atlas.png (8 cells per row).
@export var atlas_row := 0
@export var walk_frames := 4
@export var anim_fps := 8.0
