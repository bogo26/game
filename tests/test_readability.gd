extends "res://tests/test_case.gd"
## Readability: enemies that appear on screen come through a spawn portal,
## off-screen spawns keep away from heroes, ranged enemies wind up (and never
## fire from off screen), exploder fuses are announced, and heroes get their
## player-colour outline.

const WORLD_SCENE := "res://src/world/world.tscn"
const DT := 1.0 / 60.0

## An arena (room 1) next to the spawn.
const ARENA := """
##################
#P...D11111111111#
#....D11111111111#
#....D11111111111#
#....D11111111111#
##################
"""

## A big open hall for off-screen spawns.
const HALL := """
##############################################################
#P...........................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
#............................................................#
##############################################################
"""


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _data(layout: String, quotas: PackedInt32Array = PackedInt32Array([0, 0, 0])) -> LevelData:
	var d := LevelData.new()
	d.display_name = "Readability test"
	d.layout = layout
	d.corridor_spawn_rate = 0.0
	d.arena_quotas = quotas
	return d


func _make_world(data: LevelData) -> World:
	InputRouter.unassign_all()
	GameState.clear_players()
	GameState.reset_run()
	InputRouter.assign(0, PlayerInput.DEVICE_BOT)
	GameState.slots[0].hero_id = &"knight"
	var world: World = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.level_data = data
	world.spawn_enemies = false
	world.level_ups_enabled = false
	_tree().root.add_child(world)
	world.bots = null
	return world


func _teardown(world: World) -> void:
	world.get_parent().remove_child(world)
	world.free()
	_tree().paused = false
	InputRouter.unassign_all()
	GameState.clear_players()


func _open_grid(w: int, h: int) -> LevelGrid:
	var g := LevelGrid.new(w, h)
	for x in w:
		g.set_solid(x, 0, true)
		g.set_solid(x, h - 1, true)
	for y in h:
		g.set_solid(0, y, true)
		g.set_solid(w - 1, y, true)
	return g


func _enemy(behavior: EnemyData.Behavior) -> EnemyData:
	var d := EnemyData.new()
	d.id = &"test"
	d.max_hp = 10.0
	d.speed = 40.0
	d.radius = 5.0
	d.behavior = behavior
	d.attack_range = 100.0
	d.attack_cooldown = 2.0
	d.projectile_speed = 100.0
	d.explosion_radius = 30.0
	d.fuse_time = 0.5
	return d


func _horde(behavior: EnemyData.Behavior, target: PackedVector2Array) -> HordeSim:
	var g := _open_grid(30, 10)
	var flow := FlowField.new()
	flow.setup(g)
	flow.compute_now(target)
	var types: Array[EnemyData] = [_enemy(behavior)]
	var h := HordeSim.new()
	h.setup(g, flow, types)
	h.projectiles = ProjectileSim.new()
	return h


# --- spawn portals ---------------------------------------------------------------------------

func test_arena_enemies_step_out_of_portals() -> void:
	var world := _make_world(_data(ARENA, PackedInt32Array([6])))
	var spawner := world.spawner
	spawner.enabled = true
	var portals := [0]
	spawner.portal_opened.connect(func(_p: Vector2, _s: float) -> void: portals[0] += 1)
	var director := world.director
	director._activate(director.room_by_id(1), world.heroes[0])
	var view := world.camera.visible_rect()
	spawner.tick(0.5, view, world.hero_positions)  # budget for the whole first wave
	assert_eq(portals[0], 3, "a portal opens for every spawn of the first wave (3 of 6)")
	assert_eq(world.horde.enemy_count(), 0, "nobody has stepped out yet")
	assert_eq(director.enemies_left(), 6, "enemies in portals (and the next wave) still count")
	director._check_timer = 0.0
	director._tick_active_room(DT)
	assert_eq(director.room_by_id(1).state, LevelDirector.RoomState.ACTIVE,
		"the arena doesn't clear while enemies are still in portals")
	for f in int(SpawnDirector.PORTAL_TIME / DT) + 2:
		spawner.tick(DT, view, world.hero_positions)
	assert_eq(world.horde.enemy_count(), 3, "after the portal time they're all out")
	assert_eq(spawner.pending_count(), 0)
	_teardown(world)


func test_nest_spawns_come_through_portals() -> void:
	var world := _make_world(_data("""
###########
#P.......N#
###########
"""))
	world.spawner.enabled = true
	world.director._tick_nests(3.0)  # past the nest's first timer
	assert_eq(world.horde.enemy_count(), 0, "nothing has stepped out yet")
	assert_eq(world.spawner.pending_count(), LevelDirector.NEST_BATCH, "its brood waits in portals")
	_teardown(world)


func test_off_screen_spawns_keep_away_from_heroes() -> void:
	var world := _make_world(_data(HALL))
	var hero := world.heroes[0]
	var view := Rect2(Vector2(160, 64), Vector2(320, 180))
	hero.position = view.position + Vector2(14, 90)  # hugging the left edge of the view
	var heroes := PackedVector2Array([hero.position])
	var found := 0
	for k in 300:
		var p := world.spawner.find_spawn_point(view, heroes)
		if not p.is_finite():
			continue
		found += 1
		assert_true(p.distance_to(hero.position) >= SpawnDirector.CORRIDOR_MIN_DISTANCE - 5.0,
			"spawned %.0f px from the hero" % p.distance_to(hero.position))
		assert_false(view.has_point(p), "never inside the view")
	assert_true(found > 100, "still finds spots (%d)" % found)
	_teardown(world)


# --- ranged wind-up and exploder fuses ------------------------------------------------------------

func test_ranged_enemies_wind_up_before_firing() -> void:
	var target := PackedVector2Array([LevelGrid.cell_center(Vector2i(20, 5))])
	var h := _horde(EnemyData.Behavior.RANGED, target)
	var i := h.spawn(0, LevelGrid.cell_center(Vector2i(15, 5)))
	h.action[i] = 0.0  # ready to shoot
	h.update(DT, target)
	assert_eq(h.state[i], 1, "winding up")
	assert_eq(h.windup_pos.size(), 1, "the wind-up is announced")
	var frames := 0
	while h.projectiles.count == 0 and frames < 120:
		h.update(DT, target)
		frames += 1
	assert_near(frames * DT, h.t_windup[0], 2.0 * DT, "the shot comes after the wind-up")
	assert_eq(h.state[i], 0)
	assert_eq(h.projectiles.team[0], ProjectileSim.Team.ENEMY)


func test_ranged_enemies_hold_fire_off_screen() -> void:
	var target := PackedVector2Array([LevelGrid.cell_center(Vector2i(20, 5))])
	var h := _horde(EnemyData.Behavior.RANGED, target)
	var i := h.spawn(0, LevelGrid.cell_center(Vector2i(15, 5)))
	h.action[i] = 0.0
	h.view_rect = Rect2(LevelGrid.cell_center(Vector2i(18, 0)), Vector2(200, 200))  # the hero's side only
	for f in 90:
		h.update(DT, target)
	assert_eq(h.state[i], 0, "no wind-up off screen")
	assert_eq(h.projectiles.count, 0, "and no shot")
	h.view_rect = Rect2(Vector2.ZERO, Vector2(480, 160))  # now it's in view
	for f in 50:
		h.update(DT, target)
	assert_eq(h.projectiles.count, 1, "fires once it's on screen")


func test_exploder_fuse_is_announced() -> void:
	var target := PackedVector2Array([Vector2(160, 80)])
	var h := _horde(EnemyData.Behavior.EXPLODER, target)
	var i := h.spawn(0, Vector2(150, 80))
	h.update(DT, target)
	assert_eq(h.state[i], 1, "fuse lit")
	assert_eq(h.fuse_uids, PackedInt32Array([h.uid[i]]), "logged for the World's warning circle")
	h.clear_warning_logs()
	assert_true(h.fuse_uids.is_empty())


func test_fuse_warning_follows_the_exploder() -> void:
	var world := _make_world(_data(HALL))
	var hero := world.heroes[0]
	var t := world.horde.type_index(&"exploder")
	var i := world.horde.spawn(t, hero.position + Vector2(12, 0))
	world.horde.update(DT, PackedVector2Array([hero.position]))
	world._update_warnings()
	assert_eq(world.warn_fx._live_pos.size(), 1, "a filling circle under the lit exploder")
	world.horde.damage(i, 100.0, Vector2.ZERO, 0)
	world.horde.update(DT, PackedVector2Array([hero.position]))
	world._update_warnings()
	assert_eq(world.warn_fx._live_pos.size(), 0, "gone with the exploder")
	_teardown(world)


# --- heroes ------------------------------------------------------------------------------------

func test_heroes_get_a_player_colour_outline_and_tag() -> void:
	var world := _make_world(_data(HALL))
	var hero := world.heroes[0]
	var mat := hero.sprite.material as ShaderMaterial
	assert_true(mat != null, "outline material")
	assert_eq(mat.get_shader_parameter("outline_color"), hero.color)
	assert_true(hero.tag_time > 0.0, "the P1 tag shows at level start")
	hero.tick(Hero.TAG_TIME + 0.1)
	assert_eq(hero.tag_time, 0.0)
	hero.go_down()
	hero.revive(0.5)
	assert_true(hero.tag_time > 0.0, "and again after a revive")
	_teardown(world)


func test_every_boss_wind_up_draws_a_warning() -> void:
	var world := _make_world(_data(HALL))
	var boss: BossDemon = (load("res://src/enemies/boss/boss_demon.tscn") as PackedScene).instantiate()
	var at := Vector2(500, 200)
	boss.setup(world, at, 1.0, 1.0)
	world.entities.add_child(boss)
	var target := at + Vector2(120, 40)
	var expected := {
		BossDemon.Attack.FAN: [world.warn_fx, FxLayer.Kind.WARN_LINE],
		BossDemon.Attack.SLAM: [world.warn_fx, FxLayer.Kind.TELEGRAPH],
		BossDemon.Attack.CHARGE: [world.warn_fx, FxLayer.Kind.WARN_BAND],
		BossDemon.Attack.RING: [world.fx, FxLayer.Kind.DOT_RING],
	}
	for attack: int in expected:
		var layer: FxLayer = expected[attack][0]
		layer.clear()
		boss.wind_up(attack as BossDemon.Attack, at, target)
		assert_true(layer._kind.has(expected[attack][1]), "attack %d warns" % attack)
	world.warn_fx.clear()
	boss.wind_up(BossDemon.Attack.FAN, at, target)
	assert_eq(world.warn_fx._kind.count(FxLayer.Kind.WARN_LINE), 7, "one aim line per fireball")
	var pending := world.spawner.pending_count()
	boss.wind_up(BossDemon.Attack.SUMMON, at, target)
	assert_eq(world.spawner.pending_count(), pending + 8, "summoned adds wait in portals")
	boss.get_parent().remove_child(boss)
	boss.free()
	_teardown(world)


func test_every_colossus_wind_up_draws_a_warning() -> void:
	var world := _make_world(_data(HALL))
	var boss: BoneColossus = (load("res://src/enemies/boss/bone_colossus.tscn") as PackedScene).instantiate()
	var at := Vector2(500, 200)
	boss.setup(world, at, 1.0, 1.0)
	world.entities.add_child(boss)
	world.heroes[0].position = at + Vector2(40, 10)
	var target := world.heroes[0].position
	var expected := {
		BoneColossus.Attack.SWEEP: FxLayer.Kind.WARN_ARC,
		BoneColossus.Attack.SPIKES: FxLayer.Kind.TELEGRAPH,
		BoneColossus.Attack.LEAP: FxLayer.Kind.TELEGRAPH,
	}
	for attack: int in expected:
		world.warn_fx.clear()
		boss.wind_up(attack as BoneColossus.Attack, at, target)
		assert_true(world.warn_fx._kind.has(expected[attack]), "attack %d warns" % attack)
		assert_true(boss.is_winding_up(), "and the Colossus glows while it winds up")
	world.warn_fx.clear()
	boss.wind_up(BoneColossus.Attack.SPIKES, at, target)
	assert_eq(world.warn_fx._kind.count(FxLayer.Kind.TELEGRAPH), 1, "a circle under the one hero")
	var pending := world.spawner.pending_count()
	boss.wind_up(BoneColossus.Attack.RAISE, at, target)
	assert_eq(world.spawner.pending_count(), pending + BoneColossus.RAISE_COUNT, "the raised dead wait in portals")
	boss.get_parent().remove_child(boss)
	boss.free()
	_teardown(world)
