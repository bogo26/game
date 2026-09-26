extends "res://tests/test_case.gd"
## Shots collide with what's drawn: an enemy's whole body (a hurtbox standing
## on its feet) rather than a circle around the feet, and the middle of a
## hero's body. The hurtbox sizes are checked against the sprites.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0
const HORDE_ATLAS_PATH := "res://assets/sprites/enemies/horde_atlas.png"
## Each boss's sheet is named after its enemy id (see Boss for the frame layout).
const BOSS_SPRITE_PATH := "res://assets/sprites/enemies/%s.png"
## A hurtbox must cover this share of every frame's opaque pixels...
const MIN_COVERAGE := 0.85
## ...and may stick out past the sprite by at most this many pixels.
const MAX_OVERHANG := 2.0


func _open_grid(w: int, h: int) -> LevelGrid:
	var g := LevelGrid.new(w, h)
	for x in w:
		g.set_solid(x, 0, true)
		g.set_solid(x, h - 1, true)
	for y in h:
		g.set_solid(0, y, true)
		g.set_solid(w - 1, y, true)
	return g


func _type(id: StringName, radius: float, hurt_size: Vector2) -> EnemyData:
	var d := EnemyData.new()
	d.id = id
	d.max_hp = 100.0
	d.radius = radius
	d.hurt_size = hurt_size
	return d


func _horde(types: Array[EnemyData]) -> HordeSim:
	var g := _open_grid(40, 30)
	var flow := FlowField.new()
	flow.setup(g)
	var h := HordeSim.new()
	h.setup(g, flow, types)
	return h


## Fires a 5-damage player shot (radius 3) from `from` along `velocity` and
## lets it fly until it hits something or leaves.
func _shoot(h: HordeSim, from: Vector2, velocity: Vector2) -> void:
	var shots := ProjectileSim.new()
	shots.spawn(from, velocity, 5.0, 3.0, 1.5, ProjectileSim.Team.PLAYER, 0, ProjectileSim.Look.ARROW)
	for frame in 90:
		shots.update(DT, h, h.grid, PackedVector2Array(), PackedByteArray(), 5.0)
		if shots.count == 0:
			return


func _small_horde() -> HordeSim:
	var h := _horde([_type(&"small", 5.0, Vector2(14, 15))])
	h.spawn(0, Vector2(200, 200))  # body: x 193..207, y 185..200
	h.update(0.0, PackedVector2Array())
	return h


# --- enemies ---------------------------------------------------------------------------

func test_shot_through_the_head_hits() -> void:
	var h := _small_horde()
	_shoot(h, Vector2(40, 188), Vector2(300, 0))  # 12 px above the feet
	assert_near(h.hp[0], 95.0, 0.001, "head shot connects")
	assert_eq(h.hit_pos.size(), 1)
	var at := h.hit_pos[0]
	assert_near(at.y, 188.0, 0.001, "spark at the height the shot flew")
	assert_true(at.x >= 193.0 and at.x <= 196.0, "spark on the body's near edge (x=%.1f)" % at.x)


func test_shot_just_over_the_head_misses() -> void:
	var h := _small_horde()
	_shoot(h, Vector2(40, 181), Vector2(300, 0))  # top of the head is at 185, shot radius 3
	assert_near(h.hp[0], 100.0, 0.001)


func test_shot_under_the_feet_misses() -> void:
	# Nothing is drawn below the feet; the old feet circle still counted this.
	var h := _small_horde()
	_shoot(h, Vector2(40, 204), Vector2(300, 0))
	assert_near(h.hp[0], 100.0, 0.001)


func test_shot_from_above_hits_the_head_first() -> void:
	var h := _small_horde()
	_shoot(h, Vector2(200, 100), Vector2(0, 300))
	assert_near(h.hp[0], 95.0, 0.001)
	assert_true(h.hit_pos[0].y <= 186.0, "hit at the top of the head (y=%.1f)" % h.hit_pos[0].y)


func test_tall_bodies_are_hit_high_up() -> void:
	var types: Array[EnemyData] = [_type(&"small", 5.0, Vector2(14, 15)), _type(&"big", 14.0, Vector2(42, 52))]
	var h := _horde(types)
	h.spawn(0, Vector2(120, 200))
	assert_near(h.hurt_max_height, 15.0, 0.001, "only small bodies so far")
	h.spawn(1, Vector2(300, 200))
	assert_near(h.hurt_max_height, 52.0, 0.001, "search reaches a big body's head")
	assert_near(h.hurt_max_half_width, 21.0, 0.001)
	h.update(0.0, PackedVector2Array())
	_shoot(h, Vector2(40, 155), Vector2(300, 0))  # 45 px above both enemies' feet
	assert_near(h.hp[0], 100.0, 0.001, "flies over the small one")
	assert_near(h.hp[1], 95.0, 0.001, "hits the big one's head")
	h.damage(1, 1000.0, Vector2.ZERO, 0)
	h.update(0.0, PackedVector2Array())
	assert_near(h.hurt_max_height, 15.0, 0.001, "search shrinks back once the big one is gone")
	assert_near(h.hurt_max_half_width, 7.0, 0.001)


func test_sparks_default_to_the_middle_of_the_body() -> void:
	var h := _small_horde()
	h.damage(0, 1.0, Vector2.ZERO, 0)
	assert_vec_near(h.hit_pos[0], Vector2(200, 192.5), 0.001, "melee and area hits spark mid-body")


# --- heroes ----------------------------------------------------------------------------

func _make_world() -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = &"knight"
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.allow_drop_in = false
	world.spawn_enemies = false
	world.level_ups_enabled = false
	(Engine.get_main_loop() as SceneTree).root.add_child(world)
	world.bots = null
	return world


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	(Engine.get_main_loop() as SceneTree).paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


## Hero 0's HP lost to one enemy shot flying right, `height` px above its feet.
func _spit_at(world: World, height: float) -> float:
	var hero := world.heroes[0]
	hero.invulnerable_time = 0.0
	var hp0 := hero.hp
	world.projectiles.spawn(hero.position + Vector2(-24, -height), Vector2(200, 0), 10.0, 3.0, 1.0,
		ProjectileSim.Team.ENEMY, -1, ProjectileSim.Look.SPIT)
	for frame in 30:
		world._process(DT)
	return hp0 - hero.hp


func test_enemy_shots_hit_hero_bodies_not_feet() -> void:
	var world := _make_world()
	assert_true(_spit_at(world, 12.0) > 0.0, "a spit through the head hurts")
	assert_near(_spit_at(world, -4.0), 0.0, 0.001, "a spit under the feet flies past")
	_teardown(world)


func test_hero_body_follows_the_sprite() -> void:
	var world := _make_world()
	var hero := world.heroes[0]
	assert_vec_near(hero.body_position(), hero.position + Hero.SPRITE_FEET_OFFSET, 0.001)
	hero.air_height = 10.0
	assert_vec_near(hero.body_position(), hero.position + Hero.SPRITE_FEET_OFFSET - Vector2(0, 10), 0.001,
		"mid-leap the body (and muzzle) is up in the air")
	hero.air_height = 0.0
	_teardown(world)


# --- hurtbox sizes vs. the art ---------------------------------------------------------

func _load_image(path: String) -> Image:
	# The source PNG (tests run from the project), not the imported texture:
	# headless runs have no GPU copy to read back.
	return Image.load_from_file(ProjectSettings.globalize_path(path))


## Checks one frame (a `cell` of `img` whose feet are at `feet`) against the
## hurtbox; returns false when the frame is empty.
func _check_frame(data: EnemyData, img: Image, cell: Rect2i, feet: Vector2, label: String) -> bool:
	var half := data.hurt_size.x * 0.5
	var height := data.hurt_size.y
	var total := 0
	var inside := 0
	var top := INF
	var widest := 0.0
	for y in cell.size.y:
		for x in cell.size.x:
			if img.get_pixel(cell.position.x + x, cell.position.y + y).a < 0.5:
				continue
			total += 1
			var px := x + 0.5 - feet.x
			var py := y + 0.5 - feet.y
			top = minf(top, py - 0.5)
			widest = maxf(widest, absf(px) + 0.5)
			if absf(px) <= half and py >= -height and py <= 0.0:
				inside += 1
	if total == 0:
		return false
	var coverage := float(inside) / total
	assert_true(coverage >= MIN_COVERAGE, "%s: hurtbox %s covers only %d%% of the sprite"
		% [label, data.hurt_size, roundi(coverage * 100.0)])
	assert_true(height <= -top + MAX_OVERHANG, "%s: hurtbox is taller than the sprite (%.0f > %.0f)"
		% [label, height, -top])
	assert_true(half <= widest + MAX_OVERHANG, "%s: hurtbox is wider than the sprite (%.0f > %.0f)"
		% [label, half, widest])
	return true


func test_hurtboxes_match_the_art() -> void:
	var atlas := _load_image(HORDE_ATLAS_PATH)
	assert_true(atlas != null, "sprite sheets load")
	if atlas == null:
		return
	for path in World.ENEMY_TYPES:
		var data := load(path) as EnemyData
		var frames := 0
		if data.behavior == EnemyData.Behavior.BOSS:
			var boss := _load_image(BOSS_SPRITE_PATH % data.id)
			assert_true(boss != null, "%s has a sprite sheet" % data.id)
			if boss == null:
				continue
			var size := Vector2i(boss.get_width() / Boss.FRAMES, boss.get_height())
			assert_eq(size, Vector2i(Boss.FRAME_SIZE, Boss.FRAME_SIZE), "%s frames" % data.id)
			var feet := Vector2(size) * 0.5 - Boss.SPRITE_OFFSET
			for f in Boss.FRAMES:
				if _check_frame(data, boss, Rect2i(Vector2i(f * size.x, 0), size), feet, "%s frame %d" % [data.id, f]):
					frames += 1
		else:
			var cell := HordeSim.SPRITE_CELL
			for col in HordeSim.ATLAS_COLUMNS:
				var rect := Rect2i(Vector2i(col * cell.x, data.atlas_row * cell.y), cell)
				if _check_frame(data, atlas, rect, HordeSim.SPRITE_FEET, "%s frame %d" % [data.id, col]):
					frames += 1
		assert_true(frames > 0, "%s has frames to check" % data.id)
