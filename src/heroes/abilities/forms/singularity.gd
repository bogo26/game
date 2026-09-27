class_name SingularityAbility
extends AreaBurstAbility
## Mage legendary (Meteor): a black hole opens at the aim point. It drags
## every enemy nearby into its core, where they're ground down, then
## collapses in the Meteor's blast. Bosses, props and nests don't budge
## (bosses still take the damage).

@export var hole_time := 3.0
@export var pull_radius := 110.0
## Pull speed in px/s at the rim; half again as fast at the core.
@export var pull_speed := 100.0
## Share of the pull turned sideways, so they spiral in.
@export var swirl := 0.6
@export var core_radius := 28.0
@export var grind_damage := 6.0
@export var grind_interval := 0.25

const VOID_COLOR := Color(0.62, 0.35, 1.0)

var _center := Vector2.ZERO
var _left := 0.0
var _grind_in := 0.0
var _debris_in := 0.0
var _found := PackedInt32Array()


func _activate(aim: Vector2) -> void:
	if _left > 0.0:
		_collapse()
	var w := world()
	_center = w.grid.sweep_until_blocked(hero.position, hero.position + aim * distance, 2.0)
	_left = hole_time + mod(&"duration")
	_grind_in = grind_interval
	w.fx.portal(_center + Vector2(0, -4), 18.0, VOID_COLOR, _left)
	# Its reach, faint on the ground (not a filling telegraph: in P1's red that
	# would read as an enemy's warning).
	w.ground_fx.zone(_center, pull_radius * area_scale(), Color(VOID_COLOR, 0.5), _left)
	w.fx.implode(_center, pull_radius * area_scale(), VOID_COLOR, 0.4)
	Audio.play(&"portal", -2.0, 0.7)


func _tick_active(delta: float) -> void:
	super(delta)
	if _left <= 0.0:
		return
	_left -= delta
	var w := world()
	var horde := w.horde
	var reach := pull_radius * area_scale()
	horde.query_circle(_center, reach, _found)
	for j in _found:
		if not horde.is_mobile(j):
			continue
		var to := _center - horde.pos[j]
		var d := to.length()
		if d < 3.0:
			continue
		var dir := to / d
		var speed := pull_speed * (1.5 - 0.5 * minf(d / reach, 1.0))
		var next := horde.pos[j] + (dir + dir.orthogonal() * swirl).normalized() * speed * delta
		if not w.grid.is_solid_at(next):
			horde.relocate(j, next)
	_grind_in -= delta
	if _grind_in <= 0.0:
		_grind_in += grind_interval
		hero.on_hits(w.damage_enemies_in_circle(_center, core_radius, scaled_damage(grind_damage), 0.0, hero.slot))
	_debris_in -= delta
	if _debris_in <= 0.0:
		_debris_in = 0.06
		var a := randf() * TAU
		var rim := Vector2.from_angle(a)
		w.particles.burst(_center + rim * reach, 1, VOID_COLOR.lightened(0.3), reach * 1.6, 0.55, 2,
			-rim.rotated(0.5), 0.2, 0.0, 1.0)
	if _left <= 0.0:
		_collapse()


## The Meteor's blast where the hole was.
func _collapse() -> void:
	_left = 0.0
	_land(_center)
	var w := world()
	w.fx.disc(_center, core_radius, Color(1, 1, 1, 0.6 * Settings.flash_scale()), 0.15)
	w.particles.burst(_center + Vector2(0, -6), 24, VOID_COLOR.lightened(0.4), 160.0, 0.5, 3)
	w.shake(5.0)
	Audio.play(&"explosion")


func is_active() -> bool:
	return _left > 0.0 or super()


## Going down makes it collapse at once (still the ultimate's blast).
func cancel() -> void:
	if _left <= 0.0:
		return
	var horde := world().horde
	horde.ult_hits = slot == Slot.ULTIMATE
	_collapse()
	horde.ult_hits = false


func sound() -> StringName:
	return &"cast"
