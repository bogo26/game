class_name CrescentWaveAbility
extends MeleeArcAbility
## Knight legendary (Sword Slash): every combo finisher also sends a crescent
## of light flying on from the swing, cutting through a whole line (it carries
## the Knight's elements, like the swing).

@export var wave_speed := 230.0
@export var wave_lifetime := 0.55
@export var wave_radius := 7.0
@export var wave_knockback := 70.0

const WAVE_SPARKS := Color(1.0, 0.9, 0.55)


func _swing(aim: Vector2, heavy: bool) -> void:
	super(aim, heavy)
	if heavy:
		_launch_wave(aim)


func _launch_wave(aim: Vector2) -> void:
	var w := world()
	var dmg := scaled_damage(damage * combo_multiplier)
	var crit := hero.roll_crit()
	if crit:
		dmg *= hero.crit_mult
	# It leaves from the tip of the heavy swing.
	var origin := hero.position + Vector2(0, -4) + aim * reach * area_scale() * 1.3 * 0.7
	var i := w.projectiles.spawn(origin, aim * wave_speed, dmg, wave_radius * sqrt(area_scale()), wave_lifetime,
		ProjectileSim.Team.PLAYER, hero.slot, ProjectileSim.Look.CRESCENT, 99, wave_knockback)
	if i < 0:
		return
	if crit:
		w.projectiles.set_crit(i)
	if hero.has_elements():
		w.projectiles.set_elemental(i)
	w.particles.burst(origin, 6, WAVE_SPARKS, 60.0, 0.3, 2, aim, 0.8)
	Audio.play(&"shoot_magic", -6.0, 0.7)
