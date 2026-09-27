class_name DecoyAbility
extends DashAbility
## Ranger legendary (Backflip): the flip leaves a straw decoy where the
## Ranger stood. The horde goes after it as if it were a hero until it breaks
## or its time is up, then it bursts into a wide patch of caltrops (the
## backflip's own caltrops, which it no longer drops).

@export var decoy_hp := 60.0
@export var decoy_time := 3.0
@export var caltrop_radius := 34.0

const FEATHERS := Color(0.95, 0.85, 0.45)

var _decoy: Minion


func _activate(aim: Vector2) -> void:
	var w := world()
	var at := hero.position
	super(aim)
	if is_instance_valid(_decoy) and not _decoy.is_expired():
		_decoy.expire()  # the old one bursts now
	var decoy := Minion.create(Minion.Kind.DECOY, hero, w.grid.nearest_open(at))
	decoy.max_hp = decoy_hp
	decoy.hp = decoy_hp
	decoy.lifetime = decoy_time + mod(&"duration")
	decoy.lure = true
	var zone := EffectZone.new()
	zone.radius = caltrop_radius * area_scale()
	zone.duration = start_zone_duration
	zone.interval = 0.4
	zone.damage = scaled_damage(start_zone_damage)
	zone.slow_time = start_zone_slow
	zone.owner_slot = hero.slot
	zone.color = Color(0.8, 0.8, 0.8)
	decoy.burst_zone = zone
	w.add_minion(decoy)
	_decoy = decoy
	w.particles.burst(at + Vector2(0, -8), 10, FEATHERS, 70.0, 0.5, 2, Vector2.UP, PI, 60.0)
