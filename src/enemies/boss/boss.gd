class_name Boss
extends Node2D
## What every boss shares. Its body (HP, hurtbox, contact damage) is a
## HordeSim entry of its own enemy type, so every hero ability hits it like
## any enemy; the boss node moves that entry (_think(), per boss), draws the
## sprite and runs its attack patterns. While an attack winds up
## (is_winding_up()) the sprite throbs hot pink - a flash that hit flashes
## can't wash out - and each boss draws that attack's warning above the horde.
## A run meets one mini boss (BoneColossus, ToadstoolTyrant or MireSerpent)
## and one final boss (BossDemon, SporeMother or FrostQueen): see RunConfig.

signal defeated

const FLASH_SHADER := preload("res://assets/shaders/sprite_flash.gdshader")
## Boss sheets are a row of square frames as tall as the sheet (walk0, walk1,
## wind-up, action), drawn with the feet (the node's position) FEET_MARGIN px
## above a frame's bottom edge: a 64 px frame has its feet at (32, 58).
const FEET_MARGIN := 6
const BAR_COLOR := Color("e0402a")

## Each boss sets these in its _init(): its EnemyData id (the body), and the
## name on the HUD's boss bar and in the objective ("Defeat the Demon Lord!").
var body_type: StringName = &""
var display_name := "Boss"
var world: World
var uid := -1
var max_hp := 1.0

var _index := -1
var _anim := 0.0
var _add_hp_multiplier := 1.0
var _rng := RandomNumberGenerator.new()
var _dead := false

@onready var sprite: Sprite2D = $Sprite


## `add_hp_multiplier` scales the adds the boss summons.
func setup(p_world: World, spawn_position: Vector2, hp_multiplier: float, add_hp_multiplier: float) -> void:
	world = p_world
	position = spawn_position
	_add_hp_multiplier = add_hp_multiplier
	_index = world.horde.spawn(world.horde.type_index(body_type), spawn_position, hp_multiplier)
	uid = world.horde.uid[_index]
	max_hp = world.horde.hp[_index]
	_rng.randomize()


func _ready() -> void:
	var sheet := _sprite_texture()
	sprite.texture = sheet
	sprite.hframes = frame_count(sheet.get_width(), sheet.get_height())
	sprite.offset = sprite_offset(sheet.get_height())
	var mat := ShaderMaterial.new()
	mat.shader = FLASH_SHADER
	sprite.material = mat


## Frames in a sheet `w` x `h` px (a row of squares).
static func frame_count(w: int, h: int) -> int:
	return maxi(1, w / maxi(h, 1))


## Where a frame of a sheet `h` px tall is drawn from the feet.
static func sprite_offset(h: int) -> Vector2:
	return Vector2(0.0, FEET_MARGIN - h * 0.5)


func hp_ratio() -> float:
	if _index < 0 or _dead:
		return 0.0
	return clampf(world.horde.hp[_index] / max_hp, 0.0, 1.0)


func tick(dt: float) -> void:
	if _dead:
		return
	var horde := world.horde
	_index = horde.index_of_uid(uid, _index)
	if _index == -1 or horde.hp[_index] <= 0.0:
		_die()
		return
	_anim += dt
	var p := _think(horde.pos[_index], dt)
	horde.pos[_index] = p
	position = p.round()
	_update_sprite()


# --- per boss -------------------------------------------------------------------------------

## The sprite sheet: square frames (walk0, walk1, wind-up, action, ...).
func _sprite_texture() -> Texture2D:
	return null


## Moves and attacks for one frame; returns the body's new position.
func _think(p: Vector2, _dt: float) -> Vector2:
	return p


## The frame to show (see _sprite_texture()).
func _frame() -> int:
	return int(_anim * 4.0) % 2


## The sprite's tint when it isn't winding up (e.g. enraged).
func _tint() -> Color:
	return Color.WHITE


## An attack is winding up: the sprite throbs hot pink.
func is_winding_up() -> bool:
	return false


## A word the HUD adds to the boss's name ("SHIELDED", "SUBMERGED"), or "".
func status_text() -> String:
	return ""


## The boss bar's colour (a shielded boss's bar turns).
func bar_color() -> Color:
	return BAR_COLOR


## What the objective says during the fight ("" = "Defeat the <name>!").
func objective_hint() -> String:
	return ""


## Where the objective arrow points during the fight (and bots head).
func objective_point() -> Vector2:
	return position


# --- shared helpers -------------------------------------------------------------------------

## The living hero nearest to `p`, or Vector2.INF.
func _nearest_hero(p: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for hero in world.heroes:
		if hero.is_downed():
			continue
		var d := hero.position.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = hero.position
	return best


## Where every living hero stands.
func _hero_spots() -> PackedVector2Array:
	var out := PackedVector2Array()
	for hero in world.heroes:
		if not hero.is_downed():
			out.append(hero.position)
	return out


## Hits every hero within `radius` of `p` that it can reach (walls block it)
## for `damage` (times the difficulty); returns the heroes it hurt.
func _hit_circle(p: Vector2, radius: float, damage: float) -> Array[Hero]:
	var hurt: Array[Hero] = []
	for hero in world.heroes:
		if hero.position.distance_to(p) <= radius + Hero.RADIUS and world.grid.line_of_sight(p, hero.position) \
				and hero.take_hit(damage * world.horde.damage_mult):
			hurt.append(hero)
	return hurt


## Hits every hero whose feet are within `half_width` of the segment a-b.
func _hit_band(a: Vector2, b: Vector2, half_width: float, damage: float) -> Array[Hero]:
	var hurt: Array[Hero] = []
	for hero in world.heroes:
		if segment_distance(hero.position, a, b) <= half_width + Hero.RADIUS \
				and hero.take_hit(damage * world.horde.damage_mult):
			hurt.append(hero)
	return hurt


## Distance from `q` to the segment a-b.
static func segment_distance(q: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return q.distance_to(a + ab * t)


## A spot near `q` inside the boss's room (never through a wall into
## another room), or `fallback`.
func _spot_in_room(q: Vector2, fallback: Vector2) -> Vector2:
	var spot := world.grid.nearest_open(q)
	var room := world.level.room_at_position(position)
	if room != 0 and world.level.room_at_position(spot) != room:
		return fallback
	return spot


## Out of reach (under the ground or the water): nothing hits, finds or
## touches the body while hidden.
func _set_hidden(on: bool) -> void:
	world.horde.hidden[_index] = 1 if on else 0


func is_hidden() -> bool:
	return _index >= 0 and not _dead and world.horde.hidden[_index] != 0


## Adds of type `type_id` in a ring around the boss, each through a spawn portal.
func _summon(type_id: StringName, count: int, radius: float = 44.0) -> void:
	var types: Array[StringName] = []
	for k in count:
		types.append(type_id)
	_summon_mix(types, radius)


## Adds in a ring around the boss, one of each type in `types` in ring order,
## each through a spawn portal.
func _summon_mix(types: Array[StringName], radius: float = 44.0) -> void:
	var center := position
	var n := types.size()
	for k in n:
		var spot := world.grid.nearest_open(center + Vector2.from_angle(TAU * k / n) * radius)
		world.spawner.queue_spawn(world.horde.type_index(types[k]), spot, _add_hp_multiplier)


## `count` adds, `special` of them of type `special_id` spread out among
## swarmers (a boss's own servants in the crowd).
static func _crowd(count: int, special_id: StringName, special: int) -> Array[StringName]:
	var out: Array[StringName] = []
	var left := special
	for k in count:
		# Spread the special ones evenly around the ring.
		var due := left > 0 and k * special >= (special - left) * count
		out.append(special_id if due else &"swarmer")
		if due:
			left -= 1
	return out


## A new phase: a moment of hitstop, a shake, a ring and a roar.
func _announce_phase() -> void:
	world.hitstop(0.08)
	world.shake(5.0)
	world.fx.ring(position, 50.0, Color(1, 0.3, 0.2), 0.5)
	Audio.play(&"roar")


## A hostile shot (hot pink, like every enemy shot).
func _shoot(from: Vector2, velocity: Vector2, damage: float, look: ProjectileSim.Look) -> void:
	world.projectiles.spawn(from, velocity, damage * world.horde.damage_mult, 5.0, 4.0,
		ProjectileSim.Team.ENEMY, -1, look)


func _update_sprite() -> void:
	sprite.frame = _frame()
	var mat := sprite.material as ShaderMaterial
	if is_winding_up():
		# A hot pink throb that hit flashes can't wash out: an attack is coming.
		var pulse := 0.5 + 0.5 * sin(_anim * 30.0)
		mat.set_shader_parameter("flash_color", FxLayer.DANGER.lightened(0.35))
		mat.set_shader_parameter("flash_amount", (0.35 + 0.35 * pulse) * maxf(0.5, Settings.flash_scale()))
		sprite.modulate = Color.WHITE
		return
	var flash := world.horde.flash[_index] > 0.0
	mat.set_shader_parameter("flash_color", Color.WHITE)
	mat.set_shader_parameter("flash_amount", 0.75 * Settings.flash_scale() if flash else 0.0)
	sprite.modulate = _tint()


func _die() -> void:
	_dead = true
	world.hitstop(0.3, 0.6)
	world.shake(6.0)
	Audio.play(&"boss_death")
	for k in 6:
		world.fx.disc(position + Vector2(_rng.randf_range(-20, 20), _rng.randf_range(-30, 0)), 24.0,
			Color(1, 0.5, 0.2, 0.7), 0.5 + k * 0.1)
	world.fx.ring(position, 90.0, Color(1, 0.9, 0.5), 0.8)
	defeated.emit()
	queue_free()
