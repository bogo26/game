class_name TeslaGridAbility
extends SummonAbility
## Engineer legendary (Tesla Tower): the tower links itself to the Engineer
## and to every turret or mortar nearby with arcs of lightning. Enemies
## touching a link are shocked and stunned; the tower no longer zaps on its
## own. (Supercoil: the grid lasts longer and its links are thicker.)

@export var link_range := 200.0
@export var link_width := 6.0
@export var link_damage := 10.0
@export var link_interval := 0.2
@export var link_stun := 0.25

const LINK_COLOR := Color(0.6, 0.9, 1.0)
## Along a link, enemies are looked for every this many px.
const LINK_STEP := 8.0
const TOWER_TOP := Vector2(0, -16)
const TURRET_TOP := Vector2(0, -8)

var _tower: Minion
var _zap_in := 0.0
var _draw_in := 0.0
var _found := PackedInt32Array()
var _zapped: Dictionary = {}


func _activate(aim: Vector2) -> void:
	super(aim)
	_tower = _active.back() if not _active.is_empty() else null
	if _tower:
		_tower.grid = true
	_zap_in = 0.0
	_draw_in = 0.0


func _tick_active(delta: float) -> void:
	if _tower == null:
		return
	if not is_instance_valid(_tower) or _tower.is_expired():
		_tower = null
		return
	var w := world()
	var base := _tower.position
	var ends := _link_ends(base)
	_draw_in -= delta
	if _draw_in <= 0.0:
		_draw_in = 0.06
		for k in range(0, ends.size(), 2):
			w.fx.bolt(base + TOWER_TOP, ends[k], LINK_COLOR, 0.08)
	_zap_in -= delta
	if _zap_in > 0.0:
		return
	_zap_in += link_interval
	_zapped.clear()
	var horde := w.horde
	var width := link_width * area_scale()
	var dmg := scaled_damage(link_damage)
	var hits := 0
	for k in range(1, ends.size(), 2):
		# Links are drawn up high but catch what walks under them.
		var ground := ends[k]
		var steps := maxi(1, ceili(base.distance_to(ground) / LINK_STEP))
		for s in steps + 1:
			horde.query_circle(base.lerp(ground, float(s) / steps), width, _found)
			for j in _found:
				var id := horde.uid[j]
				if _zapped.has(id) or horde.is_object(j):
					continue
				_zapped[id] = true
				w.hit_enemy(j, dmg, Vector2.ZERO, hero.slot, hero)
				horde.apply_stun(j, link_stun)
				w.particles.burst(horde.body_center(j), 3, LINK_COLOR, 60.0, 0.2, 1)
				hits += 1
	if hits > 0:
		hero.on_hits(hits)
		Audio.play(&"tesla")


## Where each link ends, as (drawn end, ground under it) pairs: the Engineer
## and the Engineer's turrets and mortars within reach of the tower.
func _link_ends(base: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var reach := link_range * area_scale()
	if not hero.is_downed() and hero.position.distance_to(base) <= reach:
		out.append(hero.body_position())
		out.append(hero.position)
	for m in world().minions:
		if m.owner_hero == hero and not m.is_expired() and m.position.distance_to(base) <= reach \
				and (m.kind == Minion.Kind.TURRET or m.kind == Minion.Kind.MORTAR):
			out.append(m.position + TURRET_TOP)
			out.append(m.position)
	return out


func is_active() -> bool:
	return _tower != null
