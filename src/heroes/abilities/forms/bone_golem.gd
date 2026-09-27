class_name BoneGolemAbility
extends SummonAbility
## Necromancer legendary (Raise Dead): fresh corpses around the Necromancer
## are fused into one Bone Golem instead of skeletons. The horde goes after
## it, and it slams everything around it. Casting again while it stands
## feeds it more corpses: it heals, grows and stays longer. (Bone Horde feeds
## it more corpses a cast; Sturdy Bones toughens it.)

@export var golem_hp := 80.0
@export var hp_per_corpse := 20.0
@export var corpses := 6
@export var min_scale := 1.4
@export var max_scale := 2.0
@export var scale_per_corpse := 0.1
## A recast also heals it this share of its max HP.
@export var feed_heal := 0.25

const SOUL := Color(0.5, 1.0, 0.75)

var _golem: Minion
var _fed := 0


func _activate(aim: Vector2) -> void:
	var w := world()
	var bodies := w.recent_corpses(hero.position, corpse_radius, corpses + int(mod(&"count")))
	if not is_instance_valid(_golem) or _golem.is_expired():
		var at := hero.position + aim * spawn_radius
		if not bodies.is_empty():
			at = Vector2.ZERO
			for b in bodies:
				at += b
			at /= bodies.size()
		_fed = 0
		_golem = _summon(at)
		_golem.lure = true
		_golem.max_hp = golem_hp * (1.0 + mod(&"minion_hp_pct"))
		_golem.hp = _golem.max_hp
	else:
		_golem.hp = minf(_golem.max_hp, _golem.hp + _golem.max_hp * feed_heal)
	_feed(bodies)


func _feed(bodies: Array[Vector2]) -> void:
	var w := world()
	var top := _golem.position + Vector2(0, -12)
	for b in bodies:
		w.fx.line(b + Vector2(0, -4), top, Color(SOUL, 0.6), 0.3)
		w.particles.burst(b, 4, SOUL, 40.0, 0.4, 2, Vector2.UP, PI, -30.0)
	_fed += bodies.size()
	var extra := hp_per_corpse * bodies.size() * (1.0 + mod(&"minion_hp_pct"))
	_golem.max_hp += extra
	_golem.hp += extra
	_golem.scale_factor = clampf(min_scale + scale_per_corpse * _fed, min_scale, max_scale)
	_golem.renew(lifetime + mod(&"duration"))
	w.fx.ring(_golem.position, 14.0 * _golem.scale_factor, SOUL, 0.35)
	Audio.play(&"bones", 0.0, 0.7)
