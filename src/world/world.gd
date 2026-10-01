class_name World
extends Node2D
## Gameplay root. Owns the level, heroes and the data-oriented sims, and ticks
## everything in a fixed order each frame (no per-node _process ordering):
##   input (InputRouter autoload) → bots → heroes (+abilities) → leash
##   → revives → flow field → spawner → heroes' AoEs (dangers) → horde → blasts/contact damage
##   → projectiles → zones → kills/drops → ult charge → pickups → camera → render
## Also exposes the combat helpers abilities use (damage_enemies_in_*, heal,
## revive, zones, fx, shake). Timings go to PerfMonitor (F3).

signal team_wiped
signal level_completed
signal boss_defeated
## A wipe spent a team life: everyone got back up.
signal second_wind
## The pause menu's "Quit to menu" in a run (the Game handles it).
signal quit_requested

## Loaded at runtime: preloading would create a load cycle (hero.gd types World).
const HERO_SCENE_PATH := "res://src/heroes/hero.tscn"
const DEFAULT_HEROES: Array[StringName] = [&"knight", &"ranger", &"mage", &"cleric"]
const ENEMY_TYPES: Array[String] = [
	"res://src/enemies/data/swarmer.tres",
	"res://src/enemies/data/brute.tres",
	"res://src/enemies/data/spitter.tres",
	"res://src/enemies/data/exploder.tres",
	"res://src/enemies/data/boss_demon.tres",
	"res://src/enemies/data/barrel.tres",
	"res://src/enemies/data/urn.tres",
	"res://src/enemies/data/nest.tres",
	"res://src/enemies/data/bone_colossus.tres",
	# Each level's own enemy (see docs/DESIGN.md, Enemies):
	"res://src/enemies/data/bat.tres",
	"res://src/enemies/data/drowned.tres",
	"res://src/enemies/data/bone_archer.tres",
	"res://src/enemies/data/revenant.tres",
	"res://src/enemies/data/bone_pile.tres",
	"res://src/enemies/data/sporecap.tres",
	"res://src/enemies/data/frost_boar.tres",
	"res://src/enemies/data/salamander.tres",
	"res://src/enemies/data/imp.tres",
	# The other bosses (a run meets one mini boss and one final boss), each
	# with the servant that's its level's own enemy, and the Spore Mother's pods:
	"res://src/enemies/data/toadstool_tyrant.tres",
	"res://src/enemies/data/sporeling.tres",
	"res://src/enemies/data/mire_serpent.tres",
	"res://src/enemies/data/eel.tres",
	"res://src/enemies/data/spore_mother.tres",
	"res://src/enemies/data/spore_pod.tres",
	"res://src/enemies/data/puffball.tres",
	"res://src/enemies/data/frost_queen.tres",
	"res://src/enemies/data/frost_wraith.tres",
]
const HORDE_ATLAS := preload("res://assets/sprites/enemies/horde_atlas.png")
const FX_ATLAS := preload("res://assets/sprites/fx/fx_atlas.png")
const MAX_DELTA := 1.0 / 30.0
const SPAWN_OFFSETS: Array[Vector2] = [Vector2(-12, -8), Vector2(12, -8), Vector2(-12, 8), Vector2(12, 8)]
const HEART_DROP_CHANCE := 0.004
## Particle colour per enemy id (death puffs, hit sparks).
const ENEMY_COLORS := {
	&"swarmer": Color(0.42, 0.75, 0.3), &"brute": Color(0.6, 0.45, 0.68), &"spitter": Color(0.68, 0.35, 0.85),
	&"exploder": Color(1.0, 0.55, 0.2), &"boss_demon": Color(0.9, 0.25, 0.2),
	&"barrel": Color(0.75, 0.3, 0.2), &"urn": Color(0.69, 0.48, 0.29), &"nest": Color(0.55, 0.2, 0.35),
	&"bone_colossus": Color(0.9, 0.86, 0.72), &"bat": Color(0.5, 0.38, 0.6), &"drowned": Color(0.36, 0.62, 0.6),
	&"bone_archer": Color(0.9, 0.88, 0.78), &"revenant": Color(0.82, 0.84, 0.8), &"bone_pile": Color(0.86, 0.82, 0.7),
	&"sporecap": Color(0.92, 0.4, 0.66), &"frost_boar": Color(0.7, 0.85, 1.0), &"salamander": Color(1.0, 0.5, 0.18),
	&"imp": Color(0.88, 0.22, 0.3), &"toadstool_tyrant": Color(0.86, 0.3, 0.26), &"sporeling": Color(0.95, 0.55, 0.45),
	&"mire_serpent": Color(0.34, 0.58, 0.46), &"eel": Color(0.4, 0.55, 0.34), &"spore_mother": Color(0.78, 0.42, 0.78),
	&"spore_pod": Color(0.84, 0.46, 0.78), &"puffball": Color(0.9, 0.86, 0.78), &"frost_queen": Color(0.72, 0.88, 1.0),
	&"frost_wraith": Color(0.66, 0.84, 1.0),
}
const MAX_SPARKS_PER_FRAME := 40
const MAX_RICOCHET_STREAKS := 24
const RICOCHET_COLOR := Color(0.6, 1.0, 0.55, 0.7)
const MAX_PUFFS_PER_FRAME := 30
const NUMBER_THRESHOLD := 12.0
const CRIT_COLOR := Color(1.0, 0.72, 0.15)
const REVIVE_DECAY := 0.5
## Hits taking at least this share of a hero's max HP shake the screen.
const BIG_HIT_SHARE := 0.15
## Hurt sound pitch per player, so you can tell who got hit.
const HURT_PITCH: Array[float] = [1.0, 1.15, 0.88, 1.3]
## World time runs at this speed during a slow-motion moment.
const SLOWMO_SCALE := 0.35
## Heroes can't be hurt for this long when a level starts or they drop in...
const SPAWN_PROTECTION := 1.5
## ...or when play resumes after picking upgrades or the pause menu.
const RESUME_GRACE := 0.75
## Pick rounds held during an arena fight open this long after it's cleared
## (the vacuumed XP lands first).
const PICKS_AFTER_CLEAR := 1.0
## The legendary round opens this long after the mini boss dies (game time,
## so after its death slow motion).
const LEGENDARY_DELAY := 1.6
## Second Wind: everyone back up at this share of HP, enemies around each hero
## shoved away and stunned, enemy shots on screen gone.
const SECOND_WIND_HP := 0.5
const SECOND_WIND_RADIUS := 100.0
const SECOND_WIND_PUSH := 260.0
const SECOND_WIND_STUN := 1.0
## Chests and shrines show what they do (and give a tip) this close.
const NOTICE_RANGE := 48.0
## Test rooms: seconds after a team wipe before everyone gets back up.
const TEST_ROOM_WIPE_RESET := 3.0
## Barrels, urns and nests stand this far below their tile's centre.
const PROP_FEET := Vector2(0, 5)
## Delay before a barrel goes off, so chains ripple instead of popping at once.
const BLAST_DELAY := 0.05
const BARREL_KNOCKBACK := 220.0
const URN_GEMS := 3
const URN_HEART_CHANCE := 0.15
## Shrine blessings last this long; Wrath hits everything on screen.
const BLESSING_TIME := 30.0
const WRATH_DAMAGE := 60.0
## A revenant collapses into one of these (EnemyData.OnDeath.BONES).
const BONE_PILE := &"bone_pile"
## Enemy hazards on the ground: sporecaps' spore clouds, and what lobbed
## bombs leave behind (for this long, a share of the blast a hit): burning
## slag (salamanders) or a spore cloud (the mushroom bosses).
const SPORE_COLOR := Color(1.0, 0.36, 0.72)
const SLAG_COLOR := Color(1.0, 0.45, 0.18)
const SLAG_TIME := 1.5
const SLAG_DAMAGE_SHARE := 0.35
const SPORE_LOB_TIME := 3.0
const SPORE_LOB_SHARE := 0.4
## How high a lobbed bomb flies.
const LOB_HEIGHT := 26.0

@export var level_data: LevelData
## Test rooms let players join mid-game by pressing A / Enter.
@export var allow_drop_in := true
## Bot players to add at start (also settable with --bots=N).
@export var bot_count := 0
@export var spawn_enemies := true
## Test rooms revive a wiped team automatically instead of ending the run.
@export var auto_revive_on_wipe := true
## Off for the stress test (the pick screen pauses the game). The Game turns
## it off once a level is won or lost; unresolved rounds carry over.
@export var level_ups_enabled := true
## Seconds before pick rounds may open (the Game's level banner is showing).
var level_up_delay := 0.0
## The Game turns this off while its end-of-run banners show.
var pause_enabled := true
## Part of a run (vs. the sandbox test room): no drop-in, wipes end the run,
## reaching the exit completes the level.
@export var run_mode := false
## Endless Waves (with run_mode): a WaveDirector runs the level instead of a
## LevelDirector.
@export var wave_mode := false

var grid: LevelGrid
var heroes: Array[Hero] = []
var minions: Array[Minion] = []
var zones: Array[EffectZone] = []
var bots: BotDriver
var flow := FlowField.new()
var horde := HordeSim.new()
var projectiles := ProjectileSim.new()
var pickups := PickupSim.new()
var spawner := SpawnDirector.new()
var particles := FxSim.new()
var upgrade_pool := UpgradePool.new()
var director := LevelDirector.new()
## Elemental attack upgrades (fire, ice, poison, lightning).
var elements: Elements
## Tiles the team has seen (minimap).
var reveal := MapReveal.new()
var spikes := SpikeTraps.new()
var boss: Boss
## Run statistics for this level.
var kills := 0
var elapsed := 0.0

## Per-frame hero snapshots handed to the sims. `hero_positions` has every
## hero (camera, leash); `target_positions` only those enemies should chase.
var hero_positions := PackedVector2Array()
var target_positions := PackedVector2Array()
var _hero_bodies := PackedVector2Array()
var _hero_targetable := PackedByteArray()
var _hero_ranges := PackedFloat32Array()
var _hero_active := PackedByteArray()
var _hero_need := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
## XP a restless horde's kills still owe: fractions of a gem (see _faded_xp).
var _xp_owed := 0.0
var _scratch := PackedInt32Array()
var _wiped := false
var _wipe_timer := 0.0
var _menu_was_down := true  # the press that opened the test room doesn't count
## Hitstop: seconds the world stays frozen, then seconds in slow motion.
var _freeze_left := 0.0
var _slowmo_left := 0.0
## Chests and shrines.
var interactables: Array[Interactable] = []
## The team's current shrine blessing (for the HUD); heroes hold the buffs.
var blessing_name := ""
var blessing_left := 0.0
var blessing_color := Color.WHITE
## Barrel blasts waiting to go off: [position, radius, damage, slot, delay,
## set off by an ultimate].
var _pending_blasts: Array[Array] = []
## Volatile elites that died: [position, seconds until they blow].
var _volatile_blasts: Array[Array] = []
## Exploders with a lit fuse (uids) and where they were last seen in the horde.
var _lit_fuses := PackedInt32Array()
var _lit_hints := PackedInt32Array()
## Enemy hazards on the ground: [position, radius, seconds left, damage a hit, colour].
var _hazards: Array[Array] = []
## Lobbed bombs in the air: [landing spot, seconds left, blast radius, damage,
## what it leaves (&"slag" or &"spores")].
var _lobs: Array[Array] = []
## Aimed shooters and chargers winding up (uids), and where they were last seen.
var _aimers := PackedInt32Array()
var _aimer_hints := PackedInt32Array()
var _bone_pile_type := -1
## Recent enemy deaths (Raise Dead): positions and times.
var _corpse_pos := PackedVector2Array()
var _corpse_time := PackedFloat32Array()
const CORPSE_MEMORY := 5.0
const MAX_CORPSES := 96

@onready var level: Level = $Level
@onready var ground_fx: FxLayer = $GroundFx
## Above the horde: telegraphs, fuses and spawn portals (never hidden by enemies).
@onready var warn_fx: FxLayer = $WarnFx
@onready var heart_layer: InstanceLayer = $HeartLayer
@onready var hero_overlay: HeroOverlay = $HeroOverlay
@onready var props_root: Node2D = $Props
@onready var entities: Node2D = $Entities
@onready var fx: FxLayer = $Fx
@onready var camera: SharedCamera = $Camera
@onready var pickup_layer: InstanceLayer = $PickupLayer
@onready var horde_layer: InstanceLayer = $HordeLayer
@onready var projectile_layer: InstanceLayer = $ProjectileLayer
@onready var particle_layer: InstanceLayer = $ParticleLayer
@onready var numbers: DamageNumbers = $DamageNumbers
@onready var level_up: LevelUpScreen = $LevelUp
@onready var hud: Hud = $Hud
@onready var pause_menu: PauseMenu = $PauseMenu


func _ready() -> void:
	# Explicit: in a run the World lives under the Game node, which processes
	# always (banners, timers). Inheriting that would keep the level running
	# while players pick upgrades or the pause menu is open.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	if not GameState.run_active:
		GameState.reset_run()
	level_up.closed.connect(_on_level_up_closed)
	level_up.may_continue = can_open_pick_round
	pause_menu.closed.connect(_grant_grace.bind(RESUME_GRACE))
	hud.setup(self)
	pause_menu.quit_requested.connect(_on_quit_requested)
	level.build(level_data)
	grid = level.grid
	camera.setup(grid.size_px())
	camera.snap_to(level.player_spawns[0])
	reveal.setup(grid.width, grid.height)
	spikes.setup(level.spike_cells, grid)
	for g in spikes.group_cells.size():
		level.set_spikes(spikes.group_cells[g], spikes.group_state[g])

	var enemy_types: Array[EnemyData] = []
	for path in ENEMY_TYPES:
		enemy_types.append(load(path) as EnemyData)
	enemy_types.append_array(Elites.variants(enemy_types))
	flow.setup(grid)
	horde.setup(grid, flow, enemy_types)
	horde.projectiles = projectiles
	_bone_pile_type = horde.type_index(BONE_PILE)
	elements = Elements.new(self)
	spawner.setup(horde, grid, flow, level.enemy_spawn_hints)
	spawner.enabled = spawn_enemies
	if run_mode:
		allow_drop_in = false
		auto_revive_on_wipe = false
	horde_layer.setup(HORDE_ATLAS, HordeSim.SPRITE_CELL, HordeSim.SPRITE_FEET, HordeSim.CAPACITY)
	projectile_layer.setup(FX_ATLAS, Vector2i(16, 16), Vector2(8, 8), ProjectileSim.CAPACITY)
	pickup_layer.setup(FX_ATLAS, Vector2i(16, 16), Vector2(8, 11), PickupSim.CAPACITY)
	heart_layer.setup(FX_ATLAS, Vector2i(16, 16), Vector2(8, 11), 128)
	hero_overlay.world = self
	spawner.portal_opened.connect(_on_portal_opened)
	particle_layer.setup(FX_ATLAS, Vector2i(16, 16), Vector2(8, 8), FxSim.CAPACITY, true)
	Events.team_level_up.connect(_on_team_level_up)
	Events.hero_damaged.connect(_on_hero_damaged)
	Events.hero_downed.connect(func(_s: int) -> void: Audio.play(&"down"))
	Events.hero_downed.connect(_on_hero_downed_tip)
	Events.hero_revived.connect(func(_s: int) -> void: Audio.play(&"revive"))
	Events.hero_low_hp.connect(_on_hero_low_hp)
	Settings.changed.connect(_on_settings_changed)
	Events.ult_ready.connect(_on_ult_ready)
	Events.ability_ready.connect(_on_ability_ready)
	Events.ability_denied.connect(_on_ability_denied)
	if not run_mode:
		Audio.play_music(&"dungeon")

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--heroes="):  # debug: pick heroes for bots / drop-ins
			var ids := arg.get_slice("=", 1).split(",")
			for i in mini(ids.size(), GameState.MAX_PLAYERS):
				GameState.slots[i].hero_id = StringName(ids[i])
	var bots_wanted := maxi(bot_count, _cmdline_int("--bots=", 0))
	if bots_wanted > 0:
		BotDriver.add_bots(bots_wanted)
		bots = BotDriver.new(self)
		bots.fire_rate = float(_cmdline_int("--bot-fire=", 0))
		bots.use_abilities = bots.fire_rate <= 0.0
	for slot in InputRouter.assigned_slots():
		if GameState.slots[slot].hero_id == &"":
			GameState.slots[slot].hero_id = DEFAULT_HEROES[slot]
		spawn_hero(slot)
	if allow_drop_in:
		InputRouter.join_requested.connect(_on_join_requested)
	Events.player_device_lost.connect(_on_device_changed)
	Events.player_device_restored.connect(_on_device_changed)
	_snapshot_heroes()
	if wave_mode:
		director = WaveDirector.new()
	director.setup(self)
	_spawn_props()
	flow.compute_now(target_positions)
	if not run_mode:
		director.exit_open = false  # the sandbox never ends
		director.objective = "Test room: endless horde  (Start/Esc: menu)"
		director.objective_target = Vector2.INF
	director.level_completed.connect(level_completed.emit)
	director.boss_defeated.connect(boss_defeated.emit)
	director.mini_boss_defeated.connect(_on_mini_boss_defeated)
	director.arena_cleared.connect(_on_arena_cleared)
	director.wave_started.connect(_on_wave_started)
	director.restless_changed.connect(_on_restless_changed)
	if not GameState.debug_picks_given:
		GameState.debug_picks_given = true
		GameState.pending_level_ups += _cmdline_int("--debug-levelups=", 0)


func _exit_tree() -> void:
	flow.finish()
	Events.disconnect_all(self)


func spawn_hero(slot: int) -> Hero:
	var hero: Hero = (load(HERO_SCENE_PATH) as PackedScene).instantiate()
	hero.setup(slot, GameState.slots[slot].hero_id, self)
	var anchor := level.player_spawns[slot % level.player_spawns.size()]
	if not heroes.is_empty():
		anchor = heroes[0].position  # drop-in joins next to the team
	hero.position = grid.nearest_open(anchor + SPAWN_OFFSETS[slot])
	entities.add_child(hero)
	heroes.append(hero)
	hero.invulnerable_time = SPAWN_PROTECTION
	_apply_debug_upgrades(hero)
	spawner.set_player_count(heroes.size())
	Events.hero_spawned.emit(slot)
	return hero


func hero_for_slot(slot: int) -> Hero:
	for hero in heroes:
		if hero.slot == slot:
			return hero
	return null


func _process(delta: float) -> void:
	var dt := minf(delta, MAX_DELTA)
	if _freeze_left > 0.0:
		_freeze_left -= delta  # hitstop: the whole world holds still
		return
	if _slowmo_left > 0.0:
		_slowmo_left -= delta
		dt *= SLOWMO_SCALE
	var t_start := Time.get_ticks_usec()

	if bots:
		bots.tick(dt)
	for hero in heroes:
		hero.tick(dt)
	var t_minions := Time.get_ticks_usec()
	_tick_minions(dt)
	PerfMonitor.record(&"minions", Time.get_ticks_usec() - t_minions)
	_apply_leash()
	_update_revives(dt)
	_check_interactables()
	blessing_left = maxf(0.0, blessing_left - dt)
	_snapshot_heroes()
	var t_heroes := Time.get_ticks_usec()

	elapsed += dt
	flow.tick(dt, target_positions)
	director.tick(dt)
	spawner.tick(dt, camera.visible_rect(), hero_positions)
	horde.view_rect = camera.visible_rect()
	_collect_dangers()
	horde.update(dt, target_positions)
	_play_horde_events()
	_update_spikes(dt)
	_apply_blasts()
	_update_warnings()
	_apply_contact_damage()
	var t_horde := Time.get_ticks_usec()

	projectiles.update(dt, horde, grid, _hero_bodies, _hero_targetable, Hero.HURT_RADIUS)
	var t_elements := Time.get_ticks_usec()
	elements.process_projectile_hits(projectiles)
	var elements_usec := Time.get_ticks_usec() - t_elements
	_apply_projectile_hits()
	_update_zones(dt)
	_update_barrel_blasts(dt)
	_update_volatile_blasts(dt)
	_update_lobs(dt)
	_update_hazards(dt)
	var t_projectiles := Time.get_ticks_usec()

	_emit_hit_effects()
	_process_kills()
	t_elements = Time.get_ticks_usec()
	elements.tick(dt)
	PerfMonitor.record(&"elements", elements_usec + Time.get_ticks_usec() - t_elements)
	_apply_ult_charge()
	pickups.update(dt, hero_positions, _hero_ranges, _hero_active, _hero_need)
	_apply_pickups()
	_check_wipe(dt)
	camera.follow(hero_positions, dt)
	reveal.tick(dt, camera.visible_rect())
	level_up_delay = maxf(0.0, level_up_delay - dt)
	if level_ups_enabled and level_up_delay <= 0.0 and can_open_pick_round() \
			and not level_up.is_open() and not heroes.is_empty():
		level_up.open(heroes, upgrade_pool)
		get_tree().paused = true
	elif pause_enabled and not level_up.is_open() and Engine.get_process_frames() > pause_menu.closed_at_frame + 1:
		for hero in heroes:
			if hero.input.just_pressed(PlayerInput.Action.PAUSE):
				pause_menu.open()
				break
		if heroes.is_empty() and not run_mode and _menu_pressed():
			_on_quit_requested()  # empty test room: Esc / Start / B goes back to the menu
	var t_sim_end := Time.get_ticks_usec()

	horde.flash_strength = Settings.flash_scale()
	horde.render(horde_layer)
	projectiles.render(projectile_layer)
	pickups.render(pickup_layer, heart_layer)
	var t_fx := Time.get_ticks_usec()
	for hero in heroes:
		if hero.is_dashing() and randf() < 0.6:
			particles.burst(hero.position, 1, Color(0.8, 0.8, 0.85, 0.7), 20.0, 0.3, 1)
	particles.update(dt)
	particles.render(particle_layer)
	numbers.tick(dt)
	ground_fx.tick(dt)
	warn_fx.tick(dt)
	fx.tick(dt)
	var t_end := Time.get_ticks_usec()
	PerfMonitor.record(&"fx", t_end - t_fx)

	PerfMonitor.record(&"heroes", t_heroes - t_start)
	PerfMonitor.record(&"horde", t_horde - t_heroes)
	PerfMonitor.record(&"proj", t_projectiles - t_horde)
	PerfMonitor.record(&"render", t_end - t_sim_end)
	PerfMonitor.record(&"sim", t_end - t_start)
	PerfMonitor.set_counter(&"enemies", horde.alive_count())
	PerfMonitor.set_counter(&"projectiles", projectiles.count)
	PerfMonitor.set_counter(&"gems", pickups.count)
	PerfMonitor.set_counter(&"minions", minions.size())
	PerfMonitor.set_counter(&"dangers", horde.danger_pos.size())


# --- combat helpers for abilities -------------------------------------------------------------

## Damages enemies overlapping a circle, knocking them away from the centre.
## Returns how many were hit.
func damage_enemies_in_circle(center: Vector2, radius: float, damage: float, knockback: float,
		source_slot: int, stun_time: float = 0.0, slow_time: float = 0.0) -> int:
	horde.query_circle(center, radius, _scratch)
	return _damage_scratch(center, damage, knockback, source_slot, stun_time, slow_time)


## Damages enemies in a cone (melee swings). `elemental`: the hero whose
## attack this is, so each enemy hit also gets that hero's elements.
func damage_enemies_in_arc(center: Vector2, dir: Vector2, radius: float, half_angle: float,
		damage: float, knockback: float, source_slot: int, stun_time: float = 0.0,
		elemental: Hero = null) -> int:
	horde.query_arc(center, dir, radius, half_angle, _scratch)
	return _damage_scratch(center, damage, knockback, source_slot, stun_time, 0.0, elemental)


## Damages every enemy inside a rectangle (screen-wide ultimates).
func damage_enemies_in_rect(rect: Rect2, damage: float, knock_from: Vector2, knockback: float,
		source_slot: int, stun_time: float = 0.0, slow_time: float = 0.0) -> int:
	_scratch.clear()
	for i in horde.count:
		if horde.hp[i] > 0.0 and rect.has_point(horde.pos[i]):
			_scratch.append(i)
	return _damage_scratch(knock_from, damage, knockback, source_slot, stun_time, slow_time)


## Deals one hit to enemy `j` from a player slot: rolls that hero's crit
## (always a crit on marked enemies) and logs it for feedback. Returns true
## on a kill.
func hit_enemy(j: int, damage: float, push: Vector2, source_slot: int, source: Hero = null) -> bool:
	if source == null and source_slot >= 0:
		source = hero_for_slot(source_slot)
	var crit := false
	if source:
		crit = horde.mark[j] > 0.0 or source.roll_crit()
		if crit:
			damage *= source.crit_mult
	return horde.damage(j, damage, push, source_slot, crit)


func _damage_scratch(center: Vector2, damage: float, knockback: float, source_slot: int,
		stun_time: float, slow_time: float, elemental: Hero = null) -> int:
	var hits := 0
	var source := hero_for_slot(source_slot) if source_slot >= 0 else null
	for j in _scratch:
		var push := Vector2.ZERO
		if knockback != 0.0:
			var away := horde.pos[j] - center
			push = away.normalized() * knockback if away.length_squared() > 0.01 else Vector2.UP * knockback
		if damage > 0.0:
			hit_enemy(j, damage, push, source_slot, source)
			if elemental:
				elements.on_attack_hit(elemental, j, damage)
		elif push != Vector2.ZERO:
			horde.push(j, push, source_slot)
		if stun_time > 0.0:
			horde.apply_stun(j, stun_time)
		if slow_time > 0.0:
			horde.apply_slow(j, slow_time)
		hits += 1
	return hits


## Heals living heroes within `radius` by a fraction of their max HP.
func heal_heroes(center: Vector2, radius: float, fraction: float) -> void:
	for hero in heroes:
		if not hero.is_downed() and (radius == INF or hero.position.distance_to(center) <= radius):
			hero.heal(hero.max_hp * fraction)
			fx.disc(hero.position + Vector2(0, -6), 8.0, Color(0.5, 1.0, 0.5, 0.6), 0.3)


## Revives every downed hero; `credit_slot` (a Cleric's Divine Light) is
## credited with the revives.
func revive_all(hp_fraction: float, credit_slot: int = -1) -> void:
	for hero in heroes:
		if hero.is_downed():
			hero.revive(hp_fraction)
			fx.ring(hero.position, 20.0, Color(1, 1, 0.6), 0.5)
			if credit_slot >= 0 and credit_slot != hero.slot:
				GameState.slots[credit_slot].revives += 1


## A minion summoned while an ultimate works is part of it (see Ability).
func add_minion(minion: Minion) -> void:
	minion.ultimate = horde.ult_hits
	entities.add_child(minion)
	minions.append(minion)


## Up to `max_count` recent corpse positions near `center`; they're consumed.
func recent_corpses(center: Vector2, radius: float, max_count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var i := _corpse_pos.size() - 1
	while i >= 0 and out.size() < max_count:
		if elapsed - _corpse_time[i] <= CORPSE_MEMORY and _corpse_pos[i].distance_to(center) <= radius:
			out.append(_corpse_pos[i])
			_corpse_pos.remove_at(i)
			_corpse_time.remove_at(i)
		i -= 1
	return out


func _tick_minions(dt: float) -> void:
	var i := 0
	while i < minions.size():
		var m := minions[i]
		m.tick(dt)
		if m.is_expired():
			minions.remove_at(i)
			m.queue_free()
		else:
			i += 1


## A zone placed while an ultimate works is part of it too (Arrow Rain, or a
## plague cloud from poison the ultimate applied).
func add_zone(zone: EffectZone) -> void:
	zone.ultimate = horde.ult_hits
	zones.append(zone)
	ground_fx.zone(zone.position, zone.radius, zone.color, zone.duration)


## Whether something `hero`'s ultimate left is still at work: its zones (Arrow
## Rain) or minions (a tesla tower, the army of the dead). Its meter waits for
## them (Hero.ult_working). Toxic clouds don't count: plague goes on spreading.
func ultimate_at_work(hero: Hero) -> bool:
	for zone in zones:
		if zone.ultimate and zone.owner_slot == hero.slot and zone.poison_dps <= 0.0 and not zone.is_finished():
			return true
	for m in minions:
		if m.ultimate and m.owner_hero == hero and not m.is_expired():
			return true
	return false


func shake(strength: float) -> void:
	camera.add_shake(strength)


## Freezes the world for `freeze` seconds, then plays `slowmo` seconds in slow
## motion (big moments only: four players share the screen).
func hitstop(freeze: float, slowmo: float = 0.0) -> void:
	_freeze_left = maxf(_freeze_left, freeze)
	_slowmo_left = maxf(_slowmo_left, slowmo)


func is_frozen() -> bool:
	return _freeze_left > 0.0


# --- per-frame steps -----------------------------------------------------------------------------

func _snapshot_heroes() -> void:
	var n := heroes.size()
	hero_positions.resize(n)
	_hero_bodies.resize(n)
	_hero_targetable.resize(n)
	_hero_ranges.resize(n)
	_hero_active.resize(n)
	_hero_need.resize(n)
	target_positions.clear()
	for i in n:
		var hero := heroes[i]
		hero_positions[i] = hero.position
		_hero_bodies[i] = hero.body_position()
		_hero_targetable[i] = 1 if hero.is_targetable() else 0
		_hero_ranges[i] = hero.pickup_range
		_hero_active[i] = 0 if hero.is_downed() else 1
		_hero_need[i] = 1.0 - hero.hp / hero.max_hp if hero.max_hp > 0.0 else 0.0
		if not hero.is_downed():
			target_positions.append(hero.position)
	# Decoys and the bone golem draw the horde as if they were heroes.
	for m in minions:
		if m.lure and not m.is_expired():
			target_positions.append(m.position)


## The heroes' AoEs the horde steers clear of this frame (HordeSim.add_danger()):
## blasts about to land (Meteor, mortar shells), auras round a hero (Whirlwind,
## Blade Vortex) and lasting zones that do something to enemies (Arrow Rain,
## caltrops, fire trails, toxic clouds; not Sanctuary's healing). Zones go
## newest first, so past the cap it's the oldest that are left out. A downed
## hero's abilities are on hold until they're back up, blasts included.
func _collect_dangers() -> void:
	horde.clear_dangers()
	for hero in heroes:
		if not hero.is_downed():
			for ability in hero.abilities:
				ability.add_dangers(horde)
	for m in minions:
		m.add_dangers(horde)
	for k in range(zones.size() - 1, -1, -1):
		var zone := zones[k]
		if zone.harms_enemies():
			horde.add_danger(zone.position, zone.radius, zone.elapsed)


## Downed heroes are revived by living teammates standing next to them.
func _update_revives(dt: float) -> void:
	for hero in heroes:
		if not hero.is_downed():
			continue
		var speed := 0.0
		for other in heroes:
			if other != hero and not other.is_downed() \
					and other.position.distance_to(hero.position) <= Hero.REVIVE_RADIUS:
				speed = maxf(speed, other.revive_speed)
		if speed > 0.0:
			hero.add_revive_progress(dt * speed)
			if hero.is_downed():  # a rising tone while it fills
				Audio.play(&"revive_tick", -3.0, 0.8 + 0.7 * hero.revive_progress / Hero.REVIVE_TIME)
			else:  # back up: everyone who stood by gets the credit
				for other in heroes:
					if other != hero and not other.is_downed() \
							and other.position.distance_to(hero.position) <= Hero.REVIVE_RADIUS:
						GameState.slots[other.slot].revives += 1
		else:
			hero.revive_progress = maxf(0.0, hero.revive_progress - dt * REVIVE_DECAY)
			if _someone_standing():
				Audio.play(&"help")  # at most every few seconds (Audio intervals)


func _someone_standing() -> bool:
	for hero in heroes:
		if not hero.is_downed():
			return true
	return false


func _check_wipe(dt: float) -> void:
	if heroes.is_empty():
		return
	var all_down := true
	for hero in heroes:
		if not hero.is_downed():
			all_down = false
			break
	if all_down and not _wiped and run_mode and GameState.team_lives > 0:
		_second_wind()
		return
	if all_down and not _wiped:
		_wiped = true
		_wipe_timer = TEST_ROOM_WIPE_RESET
		Events.all_heroes_downed.emit()
		team_wiped.emit()
	elif not all_down:
		_wiped = false
	if _wiped and auto_revive_on_wipe:
		_wipe_timer -= dt
		if _wipe_timer <= 0.0:
			revive_all(0.6)
			_wiped = false


func _apply_contact_damage() -> void:
	for hero in heroes:
		if hero.is_targetable():
			var dmg := horde.contact_damage_at(hero.position, Hero.RADIUS)
			if dmg > 0.0:
				hero.take_hit(dmg)


## Barrels, urns and nests from the layout become (stationary) horde entries
## that block their tile until destroyed; chests and shrines are nodes.
func _spawn_props() -> void:
	for prop in level.props:
		if prop.kind in [&"chest", &"shrine"]:
			var it := Interactable.new()
			var blessing := _rng.randi_range(0, Interactable.Blessing.size() - 1) as Interactable.Blessing
			it.setup(Interactable.Kind.CHEST if prop.kind == &"chest" else Interactable.Kind.SHRINE, prop.cell, blessing)
			props_root.add_child(it)
			interactables.append(it)
			grid.set_blocker(prop.cell.x, prop.cell.y, true)
			continue
		var t := horde.type_index(prop.kind)
		if t < 0:
			continue
		var hp_scale := spawner.unique_hp_multiplier() if prop.kind == &"nest" else 1.0
		var i := horde.spawn(t, LevelGrid.cell_center(prop.cell) + PROP_FEET, hp_scale)
		if i < 0:
			continue
		grid.set_blocker(prop.cell.x, prop.cell.y, true)
		if prop.kind == &"nest":
			director.add_nest(horde.uid[i], prop.cell, prop.room)


## A living hero walking up to a chest or shrine uses it; coming close
## shows what it does.
func _check_interactables() -> void:
	for it in interactables:
		if it.used:
			continue
		var near := false
		for hero in heroes:
			if hero.is_downed():
				continue
			var d := hero.position.distance_to(it.position)
			near = near or d <= NOTICE_RANGE
			if d <= Interactable.TOUCH_RANGE:
				_use_interactable(it, hero)
				break
		it.near = near and not it.used
		if near:
			if it.kind == Interactable.Kind.CHEST:
				tip(&"chest", "A treasure chest: touch it for a bonus upgrade for everyone")
			else:
				tip(&"shrine", "A shrine: touch it to bless the whole team")


func _use_interactable(it: Interactable, hero: Hero) -> void:
	it.use()
	var p := it.position + Vector2(0, -10)
	var c := it.color()
	if it.kind == Interactable.Kind.CHEST:
		GameState.add_treasure_pick()  # the pick screen opens this frame
		Audio.play(&"chest")
		particles.burst(p, 30, c, 120.0, 0.8, 2, Vector2.UP, PI, 160.0)
		numbers.add_text(p - Vector2(0, 6), "TREASURE!", c)
		return
	Audio.play(&"shrine")
	numbers.add_text(p - Vector2(0, 6), Interactable.BLESSING_NAMES[it.blessing] + "!", c)
	fx.ring(it.position, 40.0, c, 0.5)
	for h in heroes:
		particles.burst(h.position + Vector2(0, -6), 16, c, 80.0, 0.7, 2, Vector2.UP, PI, -30.0)
	match it.blessing:
		Interactable.Blessing.FURY:
			for h in heroes:
				h.bless(&"damage_factor", 1.5, BLESSING_TIME)
		Interactable.Blessing.HASTE:
			for h in heroes:
				h.bless(&"move_speed_factor", 1.3, BLESSING_TIME)
				h.bless(&"attack_speed_factor", 1.3, BLESSING_TIME)
		Interactable.Blessing.LIFE:
			revive_all(1.0)
			heal_heroes(Vector2.ZERO, INF, 1.0)
		Interactable.Blessing.WRATH:
			var view := camera.visible_rect()
			var struck := 0
			for i in horde.count:
				if struck < 14 and horde.hp[i] > 0.0 and horde.is_mobile(i) and view.has_point(horde.pos[i]):
					var top := horde.pos[i] - Vector2(0, horde.t_hurt_height[horde.type[i]])
					fx.line(top - Vector2(_rng.randf_range(-6, 6), 60), top, c, 0.15)
					struck += 1
			damage_enemies_in_rect(view, WRATH_DAMAGE * spawner.effective_hp_multiplier(), view.get_center(),
				90.0, hero.slot)
			shake(5.0)
			Audio.play(&"explosion")
	if it.blessing in [Interactable.Blessing.FURY, Interactable.Blessing.HASTE]:
		blessing_name = Interactable.BLESSING_NAMES[it.blessing]
		blessing_left = BLESSING_TIME
		blessing_color = c


## A barrel or urn broke: free its tile, then blow up or scatter loot.
func _break_object(p: Vector2, t: int, killer: int, by_ult: bool) -> void:
	var cell := grid.cell_of(p)
	grid.set_blocker(cell.x, cell.y, false)
	var data := horde.types[t]
	particles.burst(p - Vector2(0, 6), 10, _enemy_color(t), 90.0, 0.5, 2, Vector2.UP, PI * 1.6, 120.0)
	match data.on_death:
		EnemyData.OnDeath.EXPLODE:
			_pending_blasts.append([p, data.explosion_radius,
				data.explosion_damage * spawner.effective_hp_multiplier(), killer, BLAST_DELAY, by_ult])
		EnemyData.OnDeath.LOOT:
			Audio.play(&"break")
			for g in URN_GEMS:
				var offset := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(3.0, 9.0)
				pickups.spawn(p + offset, PickupSim.Kind.XP, maxi(1, data.loot_xp / URN_GEMS))
			if _rng.randf() < URN_HEART_CHANCE:
				pickups.spawn(p + Vector2(0, 3), PickupSim.Kind.HEART, 1)


## An elite died: Volatile ones blow up a moment later, Splitting ones break
## into ordinary enemies of their kind.
func _elite_died(p: Vector2, t: int) -> void:
	match horde.t_elite[t]:
		Elites.Trait.VOLATILE:
			_volatile_blasts.append([p, Elites.VOLATILE_DELAY])
			warn_fx.telegraph(p, Elites.VOLATILE_RADIUS + Hero.RADIUS, FxLayer.DANGER, Elites.VOLATILE_DELAY)
			Audio.play(&"fuse")
		Elites.Trait.SPLITTING:
			var base := horde.t_base[t]
			for k in Elites.SPLIT_COUNT:
				var spot := grid.nearest_open(p + Vector2.from_angle(TAU * k / Elites.SPLIT_COUNT) * 10.0)
				horde.spawn(base, spot, spawner.effective_hp_multiplier())
			particles.burst(p - Vector2(0, 8), 16, _enemy_color(t), 110.0, 0.5, 3)


func _update_volatile_blasts(dt: float) -> void:
	var k := 0
	while k < _volatile_blasts.size():
		var blast := _volatile_blasts[k]
		blast[1] = float(blast[1]) - dt
		if float(blast[1]) > 0.0:
			k += 1
			continue
		_volatile_blasts.remove_at(k)
		var p: Vector2 = blast[0]
		var r := Elites.VOLATILE_RADIUS
		for hero in heroes:
			if hero.position.distance_to(p) <= r + Hero.RADIUS and grid.line_of_sight(p, hero.position):
				hero.take_hit(Elites.VOLATILE_DAMAGE * horde.damage_mult)
		fx.disc(p, r, Color(1.0, 0.55, 0.2, 0.7), 0.25)
		fx.ring(p, r * 1.15, Color(1.0, 0.9, 0.5), 0.3)
		particles.burst(p, 18, Color(1.0, 0.6, 0.2), 140.0, 0.5, 4, Vector2.ZERO, TAU, 0.0, 3.0)
		shake(2.5)
		Audio.play(&"explosion")


func _update_barrel_blasts(dt: float) -> void:
	var i := 0
	while i < _pending_blasts.size():
		var blast := _pending_blasts[i]
		blast[4] = float(blast[4]) - dt
		if float(blast[4]) > 0.0:
			i += 1
			continue
		_pending_blasts.remove_at(i)
		var p: Vector2 = blast[0]
		var r: float = blast[1]
		# Hurts enemies, nests and other barrels (chains), never heroes. One an
		# ultimate set off is the ultimate's too.
		horde.ult_hits = blast[5]
		damage_enemies_in_circle(p, r, blast[2], BARREL_KNOCKBACK, blast[3])
		horde.ult_hits = false
		fx.disc(p, r, Color(1.0, 0.6, 0.25, 0.65), 0.25)
		fx.ring(p, r * 1.1, Color(1.0, 0.9, 0.5), 0.3)
		particles.burst(p, 22, Color(1.0, 0.55, 0.2), 150.0, 0.55, 4, Vector2.ZERO, TAU, 0.0, 3.0)
		shake(3.0)
		Audio.play(&"explosion")


func _update_spikes(dt: float) -> void:
	if spikes.is_empty():
		return
	for change in spikes.tick(dt):
		var group := change.x
		level.set_spikes(spikes.group_cells[group], change.y)
		if change.y == SpikeTraps.State.UP:
			_stab(group)


## Spikes shoot up: everyone standing on that group's traps gets stabbed.
func _stab(group: int) -> void:
	for hero in heroes:
		if hero.is_targetable() and spikes.is_in_group(hero.position, group):
			hero.take_hit(SpikeTraps.HERO_DAMAGE * horde.damage_mult)
	var damage := SpikeTraps.ENEMY_DAMAGE * spawner.effective_hp_multiplier()
	for i in horde.count:
		if horde.hp[i] > 0.0 and horde.is_mobile(i) and spikes.is_in_group(horde.pos[i], group):
			horde.damage(i, damage, Vector2.ZERO, -1)
	var view := camera.visible_rect().grow(16.0)
	for cell: Vector2i in spikes.group_cells[group]:
		if view.has_point(LevelGrid.cell_center(cell)):
			Audio.play(&"spikes")
			break


func _apply_blasts() -> void:
	for k in horde.blast_pos.size():
		var p := horde.blast_pos[k]
		var r := horde.blast_radius[k]
		for hero in heroes:
			if hero.position.distance_to(p) <= r + Hero.RADIUS and grid.line_of_sight(p, hero.position):
				hero.take_hit(horde.blast_damage[k])
		fx.disc(p, r, Color(1.0, 0.55, 0.2, 0.7), 0.25)
		fx.ring(p, r * 1.15, Color(1.0, 0.9, 0.5), 0.3)
		particles.burst(p, 18, Color(1.0, 0.6, 0.2), 140.0, 0.5, 4, Vector2.ZERO, TAU, 0.0, 3.0)
		shake(2.5)
		Audio.play(&"explosion")
	horde.clear_blasts()


## Exploder fuses become filling circles that follow the fuse (and vanish if
## the exploder dies first); ranged enemies starting a shot glint.
func _update_warnings() -> void:
	if not horde.fuse_uids.is_empty():
		Audio.play(&"fuse")
		for id in horde.fuse_uids:
			_lit_fuses.append(id)
			_lit_hints.append(-1)
	for p in horde.windup_pos:
		particles.burst(p + Vector2(0, -9), 3, FxLayer.DANGER, 30.0, 0.25, 1)
	for id in horde.aim_uids:
		_aimers.append(id)
		_aimer_hints.append(-1)
	horde.clear_warning_logs()
	_update_aim_warnings()
	var live_pos := PackedVector2Array()
	var live_radius := PackedFloat32Array()
	var live_progress := PackedFloat32Array()
	var k := 0
	while k < _lit_fuses.size():
		var i := horde.index_of_uid(_lit_fuses[k], _lit_hints[k])
		if i == -1 or horde.hp[i] <= 0.0 or horde.state[i] != 1:
			_lit_fuses.remove_at(k)
			_lit_hints.remove_at(k)
			continue
		_lit_hints[k] = i
		var t := horde.type[i]
		live_pos.append(horde.pos[i])
		live_radius.append(horde.t_blast_radius[t] + Hero.RADIUS)
		live_progress.append(1.0 - horde.action[i] / maxf(horde.t_fuse[t], 0.001))
		k += 1
	warn_fx.set_live(live_pos, live_radius, live_progress)


## Bone archers show their aim as a line, and chargers the band they're about
## to charge down, while they wind up; both follow them and vanish if they die
## (or get stunned out of it).
func _update_aim_warnings() -> void:
	var from := PackedVector2Array()
	var to := PackedVector2Array()
	var width := PackedFloat32Array()
	var progress := PackedFloat32Array()
	var k := 0
	while k < _aimers.size():
		var i := horde.index_of_uid(_aimers[k], _aimer_hints[k])
		if i == -1 or horde.hp[i] <= 0.0 or horde.state[i] != 1:
			_aimers.remove_at(k)
			_aimer_hints.remove_at(k)
			continue
		_aimer_hints[k] = i
		var t := horde.type[i]
		var p := horde.pos[i]
		var dir := horde.aim[i]
		if horde.t_behavior[t] == EnemyData.Behavior.CHARGER:
			from.append(p)
			to.append(grid.shot_reach(p, p + dir * horde.t_charge_speed[t] * horde.t_charge_time[t]))
			width.append((horde.t_radius[t] + Hero.RADIUS) * 2.0)
		else:
			var muzzle := p + HordeSim.SHOT_ORIGIN
			from.append(muzzle + dir * 6.0)
			to.append(grid.shot_reach(muzzle, muzzle + dir * horde.t_range[t] * 1.6))
			width.append(1.0)
		progress.append(1.0 - horde.action[i] / maxf(horde.t_windup[t], 0.001))
		k += 1
	warn_fx.set_live_bands(from, to, width, progress)


## What the horde did this frame besides moving: bone piles getting back up,
## bombs lobbed, blinks, charges (and the walls they ended in), arrows loosed.
func _play_horde_events() -> void:
	var view := camera.visible_rect().grow(24.0)
	for k in horde.reform_pos.size():
		var p := horde.reform_pos[k]
		var t := horde.reform_type[k]
		horde.spawn(t, p, spawner.effective_hp_multiplier())
		particles.burst(p - Vector2(0, 6), 10, _enemy_color(t), 70.0, 0.4, 2, Vector2.UP, PI, 120.0)
		if view.has_point(p):
			Audio.play(&"rattle")
	for k in horde.lob_from.size():
		lob(horde.lob_from[k], horde.lob_to[k], horde.lob_radius[k], horde.lob_damage[k])
	if not horde.lob_from.is_empty():
		Audio.play(&"lob")
	for k in horde.blink_from.size():
		warn_fx.portal(horde.blink_to[k], 7.0, FxLayer.DANGER, horde.blink_time[k])
		particles.burst(horde.blink_from[k] - Vector2(0, 7), 6, ENEMY_COLORS[&"imp"], 40.0, 0.3, 2)
	if not horde.blink_from.is_empty():
		Audio.play(&"imp")
	for p in horde.blink_arrivals:
		particles.burst(p - Vector2(0, 7), 8, FxLayer.DANGER.lightened(0.3), 60.0, 0.3, 2)
	for p in horde.crash_pos:
		particles.burst(p, 10, Color(0.85, 0.9, 1.0), 80.0, 0.4, 2, Vector2.UP, PI, 100.0)
		if view.has_point(p):
			shake(1.5)
			Audio.play(&"thud")
	if horde.charges_started > 0:
		Audio.play(&"snort")
	if horde.arrows_fired > 0:
		Audio.play(&"bow")
	horde.clear_event_logs()


## A bomb lobbed from `from` to `to`, with its landing circle shown until it
## lands `flight` seconds later: a burst of `damage` in `radius`, then what
## it leaves (&"slag" burns for a moment, &"spores" hang in a cloud).
func lob(from: Vector2, to: Vector2, radius: float, damage: float, remains: StringName = &"slag",
		flight: float = HordeSim.LOB_TIME) -> void:
	_lobs.append([to, flight, radius, damage, remains])
	fx.lob(from, to, LOB_HEIGHT, FxLayer.DANGER, flight)
	warn_fx.telegraph(to, radius + Hero.RADIUS, FxLayer.DANGER, flight)


## Lobbed bombs land where their telegraph said: a burst that hurts heroes it
## reaches (walls stop it), then burning slag or a spore cloud.
func _update_lobs(dt: float) -> void:
	var k := 0
	while k < _lobs.size():
		var bomb := _lobs[k]
		bomb[1] = float(bomb[1]) - dt
		if float(bomb[1]) > 0.0:
			k += 1
			continue
		_lobs.remove_at(k)
		var p: Vector2 = bomb[0]
		var r: float = bomb[2]
		var damage: float = bomb[3]
		for hero in heroes:
			if hero.position.distance_to(p) <= r + Hero.RADIUS and grid.line_of_sight(p, hero.position):
				hero.take_hit(damage)
		if bomb[4] == &"spores":
			add_hazard(p, r * 0.9, SPORE_LOB_TIME, damage * SPORE_LOB_SHARE, SPORE_COLOR)
			fx.disc(p, r, Color(SPORE_COLOR, 0.6), 0.25)
			particles.burst(p - Vector2(0, 4), 14, SPORE_COLOR, 80.0, 0.8, 3, Vector2.UP, PI, -20.0)
			Audio.play(&"spores")
			continue
		add_hazard(p, r * 0.8, SLAG_TIME, damage * SLAG_DAMAGE_SHARE, SLAG_COLOR)
		fx.disc(p, r, Color(1.0, 0.5, 0.2, 0.7), 0.2)
		fx.ring(p, r * 1.1, Color(1.0, 0.85, 0.5), 0.25)
		particles.burst(p, 12, Color(1.0, 0.55, 0.2), 110.0, 0.45, 3, Vector2.ZERO, TAU, 0.0, 2.0)
		Audio.play(&"sizzle")


## An enemy hazard on the ground (spores, slag): heroes standing in it take
## `damage` a hit, spaced out by their invulnerability after each hit (walls
## keep it in).
func add_hazard(p: Vector2, radius: float, seconds: float, damage: float, color: Color) -> void:
	_hazards.append([p, radius, seconds, damage, color])
	ground_fx.zone(p, radius, color, seconds)


func _update_hazards(dt: float) -> void:
	var k := 0
	while k < _hazards.size():
		var hazard := _hazards[k]
		hazard[2] = float(hazard[2]) - dt
		if float(hazard[2]) <= 0.0:
			_hazards.remove_at(k)
			continue
		var p: Vector2 = hazard[0]
		var r: float = hazard[1]
		for hero in heroes:
			if hero.position.distance_to(p) <= r + Hero.RADIUS and grid.line_of_sight(p, hero.position):
				hero.take_hit(hazard[3])
		if _rng.randf() < 0.35:  # it drifts up in wisps
			var q := p + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * r
			particles.burst(q, 1, hazard[4], 14.0, 0.7, 2, Vector2.UP, 0.8, -20.0)
		k += 1


## A sporecap burst: a cloud that hurts heroes standing in it.
func _release_spores(p: Vector2, t: int) -> void:
	var data := horde.types[t]
	add_hazard(p, data.explosion_radius, data.cloud_time, data.cloud_damage * horde.damage_mult, SPORE_COLOR)
	particles.burst(p - Vector2(0, 6), 16, SPORE_COLOR, 70.0, 0.8, 3, Vector2.UP, PI, -20.0)
	Audio.play(&"spores")


## A revenant falls apart into a bone pile; unless it's smashed in time, it
## gets back up as the same enemy.
func _collapse(p: Vector2, t: int) -> void:
	if _bone_pile_type < 0:
		return
	var i := horde.spawn(_bone_pile_type, p, spawner.effective_hp_multiplier())
	if i < 0:
		return
	horde.action[i] = horde.types[_bone_pile_type].reform_time
	horde.state[i] = t
	Audio.play(&"bones")


func _on_portal_opened(p: Vector2, seconds: float) -> void:
	warn_fx.portal(p, 8.0, FxLayer.DANGER, seconds)
	if camera.visible_rect().grow(16.0).has_point(p):
		Audio.play(&"spawn")


func _apply_projectile_hits() -> void:
	var hits := projectiles.hero_hits
	for k in range(0, hits.size(), 2):
		var index := int(hits[k])
		if index < heroes.size():
			heroes[index].take_hit(hits[k + 1])
	for k in projectiles.impacts.size():
		fx.ring(projectiles.impacts[k], projectiles.impact_radius[k], Color(0.8, 0.6, 1.0), 0.2)
	# Ricochet: a streak where each arrow turns toward its next target.
	var turns := projectiles.ricochets
	for k in range(0, mini(turns.size(), MAX_RICOCHET_STREAKS * 2), 2):
		fx.line(turns[k], turns[k + 1], RICOCHET_COLOR, 0.12)


func _update_zones(dt: float) -> void:
	var i := 0
	while i < zones.size():
		var zone := zones[i]
		if zone.advance(dt):
			horde.ult_hits = zone.ultimate
			if zone.damage > 0.0 or zone.slow_time > 0.0 or zone.stun_time > 0.0:
				damage_enemies_in_circle(zone.position, zone.radius, zone.damage, zone.knockback,
					zone.owner_slot, zone.stun_time, zone.slow_time)
			if zone.poison_dps > 0.0:
				elements.poison_area(zone)
			horde.ult_hits = false
			if zone.heal > 0.0:
				for hero in heroes:
					if not hero.is_downed() and hero.position.distance_to(zone.position) <= zone.radius:
						hero.heal(zone.heal)
			if zone.tick_visual == "arrows":
				for n in 4:
					var p := zone.position + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * zone.radius
					fx.line(p + Vector2(-3, -14), p, Color(0.9, 0.85, 0.7), 0.08)
		if zone.is_finished():
			zones.remove_at(i)
		else:
			i += 1


func _enemy_color(type_index: int) -> Color:
	return ENEMY_COLORS.get(horde.types[horde.t_base[type_index]].id, Color(0.8, 0.8, 0.8))


func _emit_hit_effects() -> void:
	var n := horde.hit_pos.size()
	if n > 0:
		Audio.play(&"hit")
	if horde.shots_fired > 0:
		Audio.play(&"spit")
		horde.shots_fired = 0
	var crits := 0
	for k in n:
		if horde.t_behavior[horde.hit_type[k]] == EnemyData.Behavior.OBJECT:
			continue  # breaking it is feedback enough
		var p := horde.hit_pos[k]
		var amount := horde.hit_amount[k]
		if horde.hit_crit[k] != 0:
			# Crits always get a number, a gold star burst and a "tink".
			crits += 1
			numbers.add_crit(p, amount)
			if crits <= MAX_SPARKS_PER_FRAME / 2:
				particles.burst(p, 6, CRIT_COLOR, 130.0, 0.3, 2)
			continue
		if k < MAX_SPARKS_PER_FRAME:
			particles.burst(p, 2, Color(1, 0.95, 0.8), 70.0, 0.18, 1)
		if amount >= NUMBER_THRESHOLD:
			numbers.add(p, amount, Color(1, 1, 1), amount >= 40.0)
	if crits > 0:
		Audio.play(&"crit")
	horde.clear_hit_log()


func _on_hero_damaged(slot: int, amount: float) -> void:
	Audio.play(&"hurt", 0.0, HURT_PITCH[slot % HURT_PITCH.size()])
	GameState.slots[slot].damage_taken += amount
	var hero := hero_for_slot(slot)
	if hero:
		var big := amount >= hero.max_hp * BIG_HIT_SHARE
		particles.burst(hero.position + Vector2(0, -6), 10 if big else 6, Color(1, 0.25, 0.2), 70.0, 0.35, 2)
		numbers.add_hero_damage(hero.position + Vector2(0, -8), amount, big)
		if big:
			shake(2.0)


func _on_settings_changed(key: StringName) -> void:
	if key == &"palette":
		for hero in heroes:
			hero.color = GameState.player_color(hero.slot)
		hud.refresh_colors()


func _on_hero_low_hp(_slot: int) -> void:
	Audio.play(&"heartbeat")


func _on_ult_ready(slot: int) -> void:
	var hero := hero_for_slot(slot)
	if hero:
		tip(&"ult", "Ultimate ready! Press %s" % hero.input.glyph(PlayerInput.Action.ULTIMATE))
		Audio.play(&"ult_ready")
		numbers.add_text(hero.position + Vector2(0, -16), "ULT!", hero.color.lightened(0.25))
		particles.burst(hero.position + Vector2(0, -6), 14, hero.color.lightened(0.3), 70.0, 0.5, 2, Vector2.UP, PI, -30.0)


func _on_ability_ready(slot: int, ability_slot: int) -> void:
	var hero := hero_for_slot(slot)
	if hero == null or hero.is_downed():
		return
	# A quick ring in the player's colour; the special also ticks.
	var special := ability_slot == Ability.Slot.SPECIAL
	fx.ring(hero.position + Vector2(0, -6), 12.0 if special else 9.0, hero.color.lightened(0.3), 0.3)
	if special:
		Audio.play(&"ready")


func _on_ability_denied(_slot: int, _ability_slot: int) -> void:
	Audio.play(&"denied")


func _on_team_level_up(_level: int) -> void:
	Audio.play(&"level_up")
	if picks_held():
		if wave_mode:
			tip(&"held_wave", "Level up! Your upgrade picks wait until the wave is cleared")
		else:
			tip(&"held", "Level up! Your upgrade picks wait until the arena is cleared")
	for hero in heroes:
		particles.burst(hero.position + Vector2(0, -6), 24, Color(1, 0.88, 0.45), 90.0, 0.8, 3, Vector2.UP, PI, -40.0, 2.0)


func _process_kills() -> void:
	var n := horde.kill_pos.size()
	if n > 0:
		Audio.play(&"kill")
	if horde.falls > 0:
		Audio.play(&"fall")
		horde.falls = 0
	# A restless horde (LevelDirector.RESTLESS_AFTER) drops less and less.
	var share := director.drop_share()
	for k in n:
		var p := horde.kill_pos[k]
		var t := horde.kill_type[k]
		var killer := horde.kill_slot[k]
		var behavior := horde.t_behavior[t]
		if behavior == EnemyData.Behavior.OBJECT:
			_break_object(p, t, killer, horde.kill_ult[k] != 0)  # scenery: no kill, corpse or XP gem
			continue
		if behavior == EnemyData.Behavior.NEST:
			var cell := grid.cell_of(p)
			grid.set_blocker(cell.x, cell.y, false)
			particles.burst(p - Vector2(0, 7), 24, _enemy_color(t), 120.0, 0.7, 3, Vector2.UP, PI * 1.5, 160.0)
			shake(2.5)
			Audio.play(&"nest_break")
		var in_chasm := grid.terrain_at(p) == LevelGrid.Terrain.CHASM
		if k < MAX_PUFFS_PER_FRAME:
			var body := p - Vector2(0, horde.t_hurt_height[t] * 0.5)
			particles.burst(body, 6, _enemy_color(t), 60.0, 0.45, 3, Vector2.ZERO, TAU, 30.0)
		kills += 1
		if not in_chasm and horde.t_static[t] == 0:
			_corpse_pos.append(p)
			_corpse_time.append(elapsed)
			if _corpse_pos.size() > MAX_CORPSES:
				_corpse_pos.remove_at(0)
				_corpse_time.remove_at(0)
		director.on_enemy_killed()
		if killer >= 0:
			var hero := hero_for_slot(killer)
			if hero:
				hero.on_kill(p)
				GameState.slots[killer].kills += 1
		if killer != HordeSim.SELF_KILL:
			var drop := grid.nearest_open(p) if grid.is_solid_at(p) else p  # fell into a chasm
			if share >= 1.0:
				pickups.spawn(drop, PickupSim.Kind.XP, horde.t_xp[t])
			else:
				var xp := _faded_xp(horde.t_xp[t], share)
				if xp > 0:
					pickups.spawn(drop, PickupSim.Kind.XP, xp)
			var heart_chance := Elites.HEART_CHANCE if horde.t_elite[t] != 0 else HEART_DROP_CHANCE
			if _rng.randf() < heart_chance * share:
				pickups.spawn(drop + Vector2(4, 0), PickupSim.Kind.HEART, 1)
		if not in_chasm:
			match horde.types[t].on_death:
				EnemyData.OnDeath.SPORES:
					_release_spores(p, t)
				EnemyData.OnDeath.BONES:
					_collapse(p, t)
		if horde.t_elite[t] != 0:
			_elite_died(p, t)
		Events.enemy_killed.emit(p, t, killer)
	horde.clear_kill_log()


## A restless horde's XP drop: `xp` times `share`, carrying the fractions
## from kill to kill (at half share every other swarmer drops its gem).
func _faded_xp(xp: int, share: float) -> int:
	_xp_owed += xp * share
	var whole := int(_xp_owed)
	_xp_owed -= whole
	return whole


func _apply_ult_charge() -> void:
	var dealt := horde.damage_by_slot
	var by_ult := horde.ult_damage_by_slot
	var biggest := horde.biggest_hit_by_slot
	for hero in heroes:
		if hero.slot < dealt.size() and dealt[hero.slot] > 0.0:
			# Everything but what the ultimate dealt: it never charges itself.
			hero.add_ult_charge(dealt[hero.slot] - by_ult[hero.slot])
			hero.on_damage_dealt(dealt[hero.slot])
			var stats := GameState.slots[hero.slot]
			stats.damage_dealt += dealt[hero.slot]
			stats.biggest_hit = maxf(stats.biggest_hit, biggest[hero.slot])
	dealt.fill(0.0)
	horde.damage_by_slot = dealt
	by_ult.fill(0.0)
	horde.ult_damage_by_slot = by_ult
	biggest.fill(0.0)
	horde.biggest_hit_by_slot = biggest


func _apply_pickups() -> void:
	var c := pickups.collected
	for k in range(0, c.size(), 3):
		var hero_index := c[k]
		if c[k + 1] == PickupSim.Kind.HEART:
			if hero_index < heroes.size():
				var hero := heroes[hero_index]
				hero.heal(hero.max_hp * 0.25)
				Audio.play(&"heal")
		else:
			GameState.add_xp(c[k + 2])
			if hero_index < heroes.size() and k < 30:
				particles.burst(heroes[hero_index].position + Vector2(0, -6), 2, Color(0.45, 0.75, 1.0), 40.0, 0.25, 1)
			Audio.play(&"pickup", 0.0, 1.0 + minf(0.5, c[k + 2] * 0.02))


func _on_join_requested(device: int) -> void:
	if get_tree().paused:
		return  # no drop-ins while picking upgrades or paused
	var slot := InputRouter.free_slot()
	if slot == -1:
		return
	GameState.slots[slot].hero_id = DEFAULT_HEROES[slot]
	InputRouter.assign(slot, device)
	spawn_hero(slot)


## Pause while any player's controller is unplugged; resume once all are back.
func _on_device_changed(_slot: int) -> void:
	get_tree().paused = InputRouter.has_disconnected_player() or level_up.is_open()


func _on_level_up_closed() -> void:
	get_tree().paused = InputRouter.has_disconnected_player()
	_grant_grace(RESUME_GRACE)


## A moment of invulnerability for every living hero.
func _grant_grace(seconds: float) -> void:
	for hero in heroes:
		if not hero.is_downed():
			hero.invulnerable_time = maxf(hero.invulnerable_time, seconds)


## Pick rounds wait while an arena fight (or a wave) is on, except chests'
## treasure rounds; see LevelDirector.picks_held().
func picks_held() -> bool:
	return director.picks_held()


func can_open_pick_round() -> bool:
	if GameState.pending_level_ups <= 0:
		return false
	return not picks_held() or GameState.next_round() == GameState.TREASURE_ROUND


func _on_arena_cleared(_room_id: int) -> void:
	pickups.vacuum(hero_positions, _hero_active)
	level_up_delay = maxf(level_up_delay, PICKS_AFTER_CLEAR)
	if director.exit_open:
		tip(&"exit", "The exit is open: everyone into the portal!")


## A mini boss fell (in Endless Waves, any boss): its room opens, and so does
## the exit behind it, and every player picks a legendary - if this boss earns
## one (in Endless Waves only waves 10, 20 and 30 do: see
## LevelDirector.grants_legendary) and any hero still has one to take (with
## none left the round would open empty).
func _on_mini_boss_defeated(boss_name: String) -> void:
	hud.callout("%s SLAIN!" % boss_name.to_upper(), Color(1, 0.9, 0.5))
	if director.grants_legendary() and legendaries_left():
		GameState.add_legendary_pick()
	level_up_delay = maxf(level_up_delay, LEGENDARY_DELAY)


## Whether any hero still has a legendary to take (UpgradePool.legendary_offers).
func legendaries_left() -> bool:
	for hero in heroes:
		if not upgrade_pool.legendary_offers(hero.hero_id, hero.upgrade_stacks).is_empty():
			return true
	return false


func _on_wave_started(wave: int, waves: int) -> void:
	hud.callout("WAVE %d/%d" % [wave, waves], Color("ffe07a"))
	Audio.play(&"wave")
	if wave == 1:
		tip(&"arena", "The doors are sealed: beat every wave to open them")


## The team took too long to reach its next objective (see
## LevelDirector.RESTLESS_AFTER): the horde grows restless, and more so every
## few seconds; the HUD's clock shows how far drops have faded.
func _on_restless_changed(stage: int) -> void:
	if stage <= 0:
		return
	Audio.play(&"restless", 0.0 if stage == 1 else -6.0)
	if stage == 1:
		hud.callout("THE HORDE GROWS RESTLESS", Hud.RESTLESS_COLOR)
		tip(&"restless", "Too slow! Enemies drop less and grow stronger until you reach the next objective")
		shake(2.5)


## A one-time tip (see Settings.seen_tips); nothing if tips are off.
func tip(id: StringName, text: String) -> void:
	if not Settings.tips or Settings.seen_tips.has(id):
		return
	Settings.seen_tips[id] = true
	Settings.save_settings()
	hud.show_tip(text)


func _on_hero_downed_tip(slot: int) -> void:
	GameState.slots[slot].downs += 1
	if heroes.size() > 1 and _someone_standing():
		tip(&"revive", "P%d is down! Stand next to them to revive them" % (slot + 1))


## A wipe with a team life left: everyone gets back up.
func _second_wind() -> void:
	GameState.team_lives -= 1
	GameState.lives_used += 1
	revive_all(SECOND_WIND_HP)
	for hero in heroes:
		damage_enemies_in_circle(hero.position, SECOND_WIND_RADIUS, 0.0, SECOND_WIND_PUSH, -1, SECOND_WIND_STUN)
		fx.ring(hero.position, SECOND_WIND_RADIUS, Color(1, 0.95, 0.6), 0.6)
		particles.burst(hero.position + Vector2(0, -6), 24, Color(1, 0.9, 0.5), 110.0, 0.7, 3, Vector2.UP, PI, -40.0)
	projectiles.clear_enemy_shots(camera.visible_rect().grow(32.0))
	hud.callout("SECOND WIND!", Color(1, 0.9, 0.5))
	Audio.play(&"shrine")
	shake(4.0)
	second_wind.emit()


func _on_quit_requested() -> void:
	if run_mode:
		quit_requested.emit()
	else:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://src/ui/main_menu.tscn")


## Keeps the group within one screen: a hero can't move further from the
## others than the camera can show. Blocks the runner rather than dragging
## everyone else along.
func _apply_leash() -> void:
	if heroes.size() < 2:
		return
	var leash := camera.leash_size()
	for hero in heroes:
		var others := Rect2()
		var first := true
		for other in heroes:
			if other == hero:
				continue
			if first:
				others = Rect2(other.position, Vector2.ZERO)
				first = false
			else:
				others = others.expand(other.position)
		var min_p := others.end - leash
		var max_p := others.position + leash
		var clamped := Vector2(clampf(hero.position.x, min_p.x, max_p.x), clampf(hero.position.y, min_p.y, max_p.y))
		if clamped != hero.position:
			hero.position = grid.move_and_slide(hero.position, clamped - hero.position, Hero.RADIUS)


## Debug: --upgrades=fire_3,ice_1 gives every hero those upgrades (and the
## tiers they require) for this level; hero cards (legendaries included) only
## go to their own hero, so one list can hold several heroes' legendaries.
func _apply_debug_upgrades(hero: Hero) -> void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--upgrades="):
			continue
		var library := UpgradePool.shared_library()
		for id in arg.get_slice("=", 1).split(",", false):
			var chain: Array[UpgradeData] = []
			var upgrade := library.find(StringName(id))
			if upgrade and upgrade.hero_id != &"" and upgrade.hero_id != hero.hero_id:
				continue
			while upgrade:
				chain.push_front(upgrade)
				upgrade = library.find(upgrade.requires) if upgrade.requires != &"" else null
			for u in chain:
				if not hero.upgrade_stacks.has(u.id):
					hero.apply_upgrade(u, false)


## Esc on the keyboard, or Start / B on any gamepad, pressed this frame.
func _menu_pressed() -> bool:
	var down := Input.is_physical_key_pressed(KEY_ESCAPE)
	for d in Input.get_connected_joypads():
		down = down or Input.is_joy_button_pressed(d, JOY_BUTTON_START) or Input.is_joy_button_pressed(d, JOY_BUTTON_B)
	var pressed := down and not _menu_was_down
	_menu_was_down = down
	return pressed


static func _cmdline_int(prefix: String, default_value: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length()).to_int()
	return default_value
