class_name FrozenOrbAbility
extends AreaBurstAbility
## Mage legendary (Frost Nova): an orb of ice hurled toward the aim. It
## sprays slowing shards in a turning spiral as it drifts, then bursts into
## the Frost Nova where it stops (a wall stops it early).

@export var orb_speed := 90.0
@export var orb_time := 1.4
@export var shard_interval := 0.07
## Degrees the spiral turns between volleys.
@export var shard_turn := 40.0
@export var shard_damage := 4.0
@export var shard_speed := 170.0
@export var shard_lifetime := 0.4
@export var shard_slow := 1.5

const FROST := Color(0.7, 0.9, 1.0)

var _orb: HeroMissile
var _shard_in := 0.0
var _spiral := 0.0


func _activate(aim: Vector2) -> void:
	if _orb:
		_burst_orb()  # still out (short cooldowns): it bursts now
	_orb = HeroMissile.create(hero, ProjectileSim.Look.ICE_ORB, hero.body_position() + aim * 4.0)
	_orb.vel = aim * orb_speed
	_orb.life = orb_time
	_orb.spin = 5.0
	_shard_in = 0.0
	_spiral = aim.angle()


func _tick_active(delta: float) -> void:
	super(delta)
	if _orb == null:
		return
	_orb.tick(delta)
	if _orb.done:
		_burst_orb()
		return
	_shard_in -= delta
	while _shard_in <= 0.0:
		_shard_in += shard_interval
		_spray()
	if randf() < 0.3:
		world().particles.burst(_orb.pos, 1, FROST, 20.0, 0.4, 2)


## Two shards from opposite sides of the orb; the next volley turns on.
func _spray() -> void:
	var sim := world().projectiles
	_spiral += deg_to_rad(shard_turn)
	for side in 2:
		var dir := Vector2.from_angle(_spiral + PI * side)
		var dmg := scaled_damage(shard_damage)
		var crit := hero.roll_crit()
		if crit:
			dmg *= hero.crit_mult
		var i := sim.spawn(_orb.pos + dir * 3.0, dir * shard_speed, dmg, 3.0, shard_lifetime,
			ProjectileSim.Team.PLAYER, hero.slot, ProjectileSim.Look.ICE_SHARD, 0, 20.0)
		if i < 0:
			return
		sim.set_effect(i, ProjectileSim.Effect.SLOW, shard_slow)
		if crit:
			sim.set_crit(i)


## The Frost Nova, on the ground under where the orb stopped.
func _burst_orb() -> void:
	var p := _orb.pos + Vector2(0, 6)
	_orb.free_sprite()
	_orb = null
	_land(p)
	world().particles.burst(p + Vector2(0, -6), 14, Color(0.85, 0.95, 1.0), 110.0, 0.4, 2)
	Audio.play(&"freeze")


func is_active() -> bool:
	return _orb != null or super()


func cancel() -> void:
	if _orb:
		_orb.free_sprite()
		_orb = null


func sound() -> StringName:
	return &"cast"
