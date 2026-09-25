class_name SummonAbility
extends Ability
## Summons minions: skeleton warriors (optionally raised from fresh corpses),
## auto-firing turrets, or a tesla tower. Oldest minions of this ability are
## replaced when `max_active` is reached.

@export var kind: Minion.Kind = Minion.Kind.SKELETON
@export var count := 1
@export var max_active := 8
@export var lifetime := 20.0
## Raise Dead: spawn on recent enemy deaths near the hero (falls back to
## spawning around the hero when there are none).
@export var use_corpses := false
@export var corpse_radius := 140.0
@export var spawn_radius := 18.0
@export_group("Minion stats")
@export var minion_hp := 30.0
@export var minion_damage := 8.0
@export var attack_interval := 0.6
@export var attack_range := 140.0

var _active: Array[Minion] = []


func _activate(aim: Vector2) -> void:
	var w := world()
	var alive: Array[Minion] = []
	for m in _active:
		if is_instance_valid(m) and not m.is_expired():
			alive.append(m)
	_active = alive
	var n := count + int(mod(&"count"))
	var spots: Array[Vector2] = []
	if use_corpses:
		spots.assign(w.recent_corpses(hero.position, corpse_radius, n))
	while spots.size() < n:
		var angle := TAU * float(spots.size()) / float(n) + aim.angle()
		spots.append(hero.position + Vector2.from_angle(angle) * spawn_radius)
	for spot in spots:
		while _active.size() >= max_active + int(mod(&"max_active")):
			var oldest: Minion = _active.pop_front()
			if is_instance_valid(oldest):
				oldest.expire()
		var minion := Minion.create(kind, hero, w.grid.nearest_open(spot))
		minion.max_hp = minion_hp * (1.0 + mod(&"minion_hp_pct"))
		minion.hp = minion.max_hp
		minion.damage = minion_damage * (1.0 + mod(&"damage_pct"))
		minion.attack_interval = attack_interval
		minion.attack_range = attack_range * area_scale()
		minion.lifetime = lifetime + mod(&"duration")
		w.add_minion(minion)
		_active.append(minion)
		w.fx.ring(minion.position, 10.0, hero.color, 0.35)
