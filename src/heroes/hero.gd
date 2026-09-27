class_name Hero
extends Node2D
## A player's hero: twin-stick movement and aim, the four ability slots
## (attack, special, movement, ultimate), health, the downed/revive state and
## rendering. Heroes have no _process of their own; the World ticks them.

enum Frame { IDLE0, IDLE1, RUN0, RUN1, RUN2, RUN3, DASH, DOWNED }
enum State { ALIVE, DOWNED }

## Emitted when the attack ability fires (Shadow Clones mirror it).
signal attack_performed(aim: Vector2)

const RADIUS := 5.0
## Enemy shots hit within this distance of body_position(): a bit smaller than
## the drawn body, so shots that only graze the outline miss.
const HURT_RADIUS := 5.0
const HIT_IFRAMES := 0.5
const REVIVE_TIME := 3.0
const REVIVE_RADIUS := 20.0
const REVIVE_HP_FRACTION := 0.3
const REVIVE_IFRAMES := 2.0
const ULT_PASSIVE_PER_SECOND := 0.01
const SPRITE_FEET_OFFSET := Vector2(0, -6)
const RETICLE_DISTANCE := 22.0
const ACCELERATION := 14.0
const HERO_DATA_PATH := "res://src/heroes/data/%s.tres"
const OUTLINE_SHADER := preload("res://assets/shaders/hero_outline.gdshader")
## The "P1" tag shows this long at level start and after a revive.
const TAG_TIME := 3.0
## Ring shown while a shrine blessing lasts (not a player colour).
const BLESSING_RING := Color(1.0, 0.94, 0.66)
## At or below this share of max HP a hero is "low": outline and HUD pulse
## red, and a heartbeat plays as they cross it.
const LOW_HP_FRACTION := 0.3
const LOW_HP_COLOR := Color(1.0, 0.16, 0.2)
## How long the HUD flashes a bar after a press it couldn't act on / when an
## ability comes back.
const DENIED_TIME := 0.25
## Chilled (the Frost Queen's frost): walks this much slower, tinted icy.
const CHILL_SPEED := 0.6
const CHILL_TINT := Color(0.72, 0.9, 1.35)
const READY_FLASH_TIME := 0.3

var slot := 0
var hero_id: StringName = &"knight"
var data: HeroData
var color := Color.WHITE
var input: PlayerInput
var world: World

var state: State = State.ALIVE
## Shrine blessings: buff hook -> [factor, seconds left].
var blessings: Dictionary = {}
var stats := Stats.new()
## Upgrade id -> times taken this run.
var upgrade_stacks: Dictionary = {}
## Elemental attack tiers [fire, ice, poison, lightning] (0-3), from upgrades.
var elements := PackedInt32Array([0, 0, 0, 0])
var max_hp := 100.0
var hp := 100.0
var armor := 0.0
var move_speed := 88.0
var velocity := Vector2.ZERO
var aim_dir := Vector2.RIGHT
var invulnerable_time := 0.0
## 0..1; the ultimate is usable at 1.
var ult_charge := 0.0
var revive_progress := 0.0
## Seconds left chilled (slowed; see chill()).
var chill_time := 0.0
## Seconds left showing the "P1" tag (HeroOverlay).
var tag_time := TAG_TIME
## Seconds left of the gold shimmer that shows a fresh revive's invulnerability.
var revive_shield := 0.0
## Per ability slot: 1 once it has been used (the controls card fades).
var used_abilities := PackedByteArray([0, 0, 0, 0])
## Per ability slot: seconds left flashing "not ready" / "ready again" (HUD).
var denied_time := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var ready_flash := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
## XP gems within this distance home in on the hero.
var pickup_range := 28.0
## Ignores all damage (stress test, debug).
var god_mode := false

# Derived from `stats` by _refresh_stats().
var damage_mult := 1.0
var attack_speed_mult := 1.0
var crit_chance := 0.05
var crit_mult := 1.75
var regen := 0.0
var ult_charge_mult := 1.0
var life_on_kill := 0.0
var revive_speed := 1.0

## [attack, special, movement, ultimate], duplicated from the HeroData.
var abilities: Array[Ability] = []

var dash_time_left := 0.0
## Visual jump height in pixels (Leap Slam); the body stays on the ground.
var air_height := 0.0
var _dash_velocity := Vector2.ZERO
var _anim_time := 0.0
var _hurt_flash := 0.0
var _low_hp := false
var _ult_announced := false
## Special and movement were ready last frame (to notice them coming back).
var _was_ready := PackedByteArray([1, 1])
var _rng := RandomNumberGenerator.new()

@onready var sprite: Sprite2D = $Sprite


func setup(p_slot: int, p_hero_id: StringName, p_world: World) -> void:
	slot = p_slot
	hero_id = p_hero_id
	world = p_world
	input = InputRouter.get_player(slot)
	color = GameState.player_color(slot)
	data = load(HERO_DATA_PATH % hero_id) as HeroData
	stats.set_base(Stats.MAX_HP, data.max_hp)
	stats.set_base(Stats.ARMOR, data.armor)
	stats.set_base(Stats.MOVE_SPEED, data.move_speed)
	stats.set_base(Stats.DAMAGE, 1.0)
	stats.set_base(Stats.ATTACK_SPEED, 1.0)
	stats.set_base(Stats.CRIT_CHANCE, data.crit_chance)
	stats.set_base(Stats.CRIT_DAMAGE, 1.75)
	stats.set_base(Stats.PICKUP_RANGE, 28.0)
	stats.set_base(Stats.REGEN, 0.0)
	stats.set_base(Stats.ULT_CHARGE, 1.0)
	stats.set_base(Stats.LIFE_ON_KILL, 0.0)
	stats.set_base(Stats.REVIVE_SPEED, 1.0)
	abilities.clear()
	var templates := data.abilities()
	for i in templates.size():
		var ability := templates[i].duplicate(true) as Ability
		ability.bind(self, i as Ability.Slot)
		abilities.append(ability)
	_refresh_stats()
	hp = max_hp
	ult_charge = GameState.slots[slot].ult_charge  # carried over from the last level
	# Re-apply upgrades taken earlier in the run (levels rebuild heroes).
	var library := UpgradePool.shared_library()
	for id in GameState.slots[slot].upgrades:
		var upgrade := library.find(id)
		if upgrade:
			apply_upgrade(upgrade, false)
	hp = max_hp
	_rng.seed = hash(slot * 7919 + Time.get_ticks_usec())


func _ready() -> void:
	sprite.texture = load("res://assets/sprites/heroes/%s.png" % hero_id)
	sprite.hframes = Frame.size()
	sprite.position = SPRITE_FEET_OFFSET
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE_SHADER
	outline.set_shader_parameter("outline_color", color)
	sprite.material = outline


func attack() -> Ability:
	return abilities[Ability.Slot.ATTACK]


func special() -> Ability:
	return abilities[Ability.Slot.SPECIAL]


func movement() -> Ability:
	return abilities[Ability.Slot.MOVEMENT]


func ultimate() -> Ability:
	return abilities[Ability.Slot.ULTIMATE]


func is_downed() -> bool:
	return state == State.DOWNED


## Applies an upgrade card; `record` stores it in the run so later levels
## re-apply it.
func apply_upgrade(upgrade: UpgradeData, record: bool = true) -> void:
	if not UpgradePool.apply_effects(upgrade, stats, abilities):
		return
	upgrade_stacks[upgrade.id] = int(upgrade_stacks.get(upgrade.id, 0)) + 1
	_refresh_stats()
	if record:
		GameState.slots[slot].upgrades.append(upgrade.id)


func _refresh_stats() -> void:
	var old_max := max_hp
	max_hp = maxf(1.0, stats.get_value(Stats.MAX_HP))
	if max_hp > old_max and state == State.ALIVE:
		hp += max_hp - old_max
	hp = minf(hp, max_hp)
	armor = stats.get_value(Stats.ARMOR)
	move_speed = stats.get_value(Stats.MOVE_SPEED)
	damage_mult = stats.get_value(Stats.DAMAGE)
	attack_speed_mult = maxf(0.1, stats.get_value(Stats.ATTACK_SPEED))
	crit_chance = clampf(stats.get_value(Stats.CRIT_CHANCE), 0.0, 1.0)
	crit_mult = stats.get_value(Stats.CRIT_DAMAGE)
	pickup_range = stats.get_value(Stats.PICKUP_RANGE)
	regen = stats.get_value(Stats.REGEN)
	ult_charge_mult = stats.get_value(Stats.ULT_CHARGE)
	life_on_kill = stats.get_value(Stats.LIFE_ON_KILL)
	revive_speed = stats.get_value(Stats.REVIVE_SPEED)
	if not abilities.is_empty():
		elements = Elements.tiers_of(attack())


func is_dashing() -> bool:
	return dash_time_left > 0.0


## Whether the attack carries any element (fire, ice, poison, lightning).
func has_elements() -> bool:
	return elements[0] > 0 or elements[1] > 0 or elements[2] > 0 or elements[3] > 0


## Whether enemies and enemy projectiles can currently hurt this hero.
func is_targetable() -> bool:
	return state == State.ALIVE and invulnerable_time <= 0.0 and not god_mode


## Middle of the drawn body (`position` is the feet), following leaps and
## size buffs: shots leave from here and enemy shots aim at it.
func body_position() -> Vector2:
	return position + SPRITE_FEET_OFFSET * buff_product(&"sprite_scale") - Vector2(0, air_height)


func muzzle_position() -> Vector2:
	return body_position() + aim_dir * 5.0


# --- ticking -----------------------------------------------------------------------------

func tick(delta: float) -> void:
	invulnerable_time = maxf(0.0, invulnerable_time - delta)
	tag_time = maxf(0.0, tag_time - delta)
	revive_shield = maxf(0.0, revive_shield - delta)
	chill_time = maxf(0.0, chill_time - delta)
	for k in 4:
		denied_time[k] = maxf(0.0, denied_time[k] - delta)
		ready_flash[k] = maxf(0.0, ready_flash[k] - delta)
	_tick_blessings(delta)
	if state == State.DOWNED:
		velocity = Vector2.ZERO
		_update_visuals(delta)
		return
	_update_aim()
	for ability in abilities:
		ability.tick(delta)

	if dash_time_left > 0.0:
		dash_time_left -= delta
		position = world.grid.move_and_slide(position, _dash_velocity * delta, RADIUS)
	else:
		var target_velocity := input.move * move_speed * _speed_factor()
		velocity = velocity.lerp(target_velocity, 1.0 - exp(-ACCELERATION * delta))
		position = world.grid.move_and_slide(position, velocity * delta, RADIUS)

	var blocked := false
	for ability in abilities:
		if ability.blocks_other_abilities():
			blocked = true
	var a := attack()
	if not blocked:
		var wants_attack := input.is_down(PlayerInput.Action.ATTACK) if a.hold_to_repeat \
			else input.just_pressed(PlayerInput.Action.ATTACK)
		if wants_attack and a.try_activate(aim_dir):
			used_abilities[Ability.Slot.ATTACK] = 1
			attack_performed.emit(aim_dir)
	if input.just_pressed(PlayerInput.Action.SPECIAL):
		if blocked or not special().try_activate(aim_dir):
			_deny(Ability.Slot.SPECIAL)
		else:
			used_abilities[Ability.Slot.SPECIAL] = 1
	if input.just_pressed(PlayerInput.Action.ULTIMATE):
		if blocked or ult_charge < 1.0 or not ultimate().try_activate(aim_dir):
			_deny(Ability.Slot.ULTIMATE)
		else:
			used_abilities[Ability.Slot.ULTIMATE] = 1
			ult_charge = 0.0
			_ult_announced = false
			input.rumble(0.6, 0.9, 0.3)
	if input.just_pressed(PlayerInput.Action.MOVEMENT) and not is_dashing():
		if not movement().try_activate(aim_dir):
			_deny(Ability.Slot.MOVEMENT)
		else:
			used_abilities[Ability.Slot.MOVEMENT] = 1

	ult_charge = minf(1.0, ult_charge + ULT_PASSIVE_PER_SECOND * ult_charge_mult * delta)
	if regen > 0.0:
		heal(regen * delta)
	_check_readiness()
	_update_low_hp()
	_update_visuals(delta)


## A press that couldn't do anything: the HUD bar flashes and a soft blip plays.
func _deny(ability_slot: Ability.Slot) -> void:
	denied_time[ability_slot] = DENIED_TIME
	Events.ability_denied.emit(slot, ability_slot)


## Notices the special and movement coming off cooldown and the ultimate
## becoming usable (each announced once).
func _check_readiness() -> void:
	for k in 2:
		var ability_slot := Ability.Slot.SPECIAL if k == 0 else Ability.Slot.MOVEMENT
		var ready := abilities[ability_slot].can_activate()
		if ready and _was_ready[k] == 0:
			ready_flash[ability_slot] = READY_FLASH_TIME
			Events.ability_ready.emit(slot, ability_slot)
		_was_ready[k] = 1 if ready else 0
	if ult_charge >= 1.0 and not _ult_announced:
		_ult_announced = true
		input.rumble(0.2, 0.35, 0.15)
		Events.ult_ready.emit(slot)


func is_low_hp() -> bool:
	return _low_hp


func _update_low_hp() -> void:
	var low := state == State.ALIVE and hp <= max_hp * LOW_HP_FRACTION
	if low and not _low_hp:
		input.rumble(0.5, 0.25, 0.2)
		Events.hero_low_hp.emit(slot)
	_low_hp = low


func _speed_factor() -> float:
	var terrain := world.grid.speed_factor_at(position) if world and world.grid else 1.0
	var chilled := CHILL_SPEED if chill_time > 0.0 else 1.0
	return buff_product(&"move_speed_factor") * terrain * chilled


## Slows the hero for `seconds` (a longer chill replaces a shorter one).
func chill(seconds: float) -> void:
	if state == State.ALIVE:
		chill_time = maxf(chill_time, seconds)


## Product of a buff hook (e.g. &"damage_factor") over all four abilities,
## times any shrine blessing on that hook.
func buff_product(hook: StringName) -> float:
	var f := 1.0
	for ability in abilities:
		f *= float(ability.call(hook))
	if blessings.has(hook):
		f *= float(blessings[hook][0])
	return f


## Multiplies a buff hook by `factor` for `seconds` (replaces the same hook).
func bless(hook: StringName, factor: float, seconds: float) -> void:
	blessings[hook] = [factor, seconds]


func _tick_blessings(delta: float) -> void:
	for hook: StringName in blessings.keys():
		var left := float(blessings[hook][1]) - delta
		if left <= 0.0:
			blessings.erase(hook)
		else:
			blessings[hook][1] = left


func buff_sum(hook: StringName) -> float:
	var total := 0.0
	for ability in abilities:
		total += float(ability.call(hook))
	return total


func _update_aim() -> void:
	if input.uses_mouse:
		var to_mouse := get_global_mouse_position() - (global_position + SPRITE_FEET_OFFSET)
		if to_mouse.length_squared() > 4.0:
			aim_dir = to_mouse.normalized()
	else:
		aim_dir = assisted_aim(input.aim, Settings.aim_assist_angle())


## Gamepad aim assist: snaps `aim` onto the enemy within AIM_ASSIST_RANGE that
## is closest to it in angle, if that's within `cone` radians.
func assisted_aim(aim: Vector2, cone: float) -> Vector2:
	if cone <= 0.0 or world == null:
		return aim
	var horde := world.horde
	var found := PackedInt32Array()
	horde.query_circle(position, Settings.AIM_ASSIST_RANGE, found)
	var best := aim
	var best_angle := cone
	var from := body_position()
	for j in found:
		if horde.hp[j] <= 0.0 or not horde.is_mobile(j) or horde.is_falling(j):
			continue
		var to := horde.body_center(j) - from
		if to.length_squared() < 1.0:
			continue
		var angle := absf(aim.angle_to(to))
		if angle < best_angle:
			best_angle = angle
			best = to.normalized()
	return best


# --- movement helpers used by abilities --------------------------------------------------

func start_dash(dir: Vector2, distance: float, duration: float, iframes: float) -> void:
	var d := dir.normalized() if dir != Vector2.ZERO else aim_dir
	_dash_velocity = d * (distance / maxf(duration, 0.01))
	dash_time_left = duration
	invulnerable_time = maxf(invulnerable_time, iframes)
	velocity = d * move_speed


func teleport(to: Vector2, iframes: float) -> void:
	position = to
	velocity = Vector2.ZERO
	invulnerable_time = maxf(invulnerable_time, iframes)


# --- combat ----------------------------------------------------------------------------------

## Damage with the hero's multipliers and active buffs. Crits are rolled per
## hit (World.hit_enemy, or at spawn for projectiles), not here.
func base_damage(base: float) -> float:
	return base * damage_mult * buff_product(&"damage_factor")


func roll_crit() -> bool:
	return _rng.randf() < crit_chance


## Hook for on-hit effects of melee/area abilities.
func on_hits(_count: int) -> void:
	pass


## Called by the World when an enemy this hero damaged last dies.
func on_kill() -> void:
	var amount := life_on_kill + buff_sum(&"heal_on_kill")
	if amount > 0.0:
		heal(amount)


## Called by the World with the damage this hero (and its minions) dealt.
func on_damage_dealt(amount: float) -> void:
	var steal := buff_sum(&"lifesteal")
	if steal > 0.0:
		heal(amount * steal)


func add_ult_charge(damage_dealt: float) -> void:
	if state == State.ALIVE and damage_dealt > 0.0:
		ult_charge = minf(1.0, ult_charge + damage_dealt * ult_charge_mult / maxf(data.ult_cost, 1.0))


## Applies a hit; returns true if damage was taken.
func take_hit(amount: float) -> bool:
	if not is_targetable() or amount <= 0.0:
		return false
	var dmg := maxf(1.0, amount * buff_product(&"damage_taken_factor") - armor)
	hp -= dmg
	invulnerable_time = HIT_IFRAMES
	_hurt_flash = 0.12
	Events.hero_damaged.emit(slot, dmg)
	# The harder the hit, the harder the rumble.
	var share := clampf(dmg / maxf(max_hp, 1.0), 0.0, 1.0)
	input.rumble(minf(1.0, 0.25 + share * 2.0), minf(1.0, 0.35 + share * 2.5), 0.1 + share * 0.4)
	if hp <= 0.0:
		go_down()
	else:
		_update_low_hp()
	return true


func heal(amount: float) -> void:
	if state == State.ALIVE:
		hp = minf(max_hp, hp + amount)


func go_down() -> void:
	hp = 0.0
	state = State.DOWNED
	_low_hp = false
	revive_progress = 0.0
	dash_time_left = 0.0
	chill_time = 0.0
	velocity = Vector2.ZERO
	for ability in abilities:
		ability.cancel()
	input.rumble(0.8, 1.0, 0.4)
	Events.hero_downed.emit(slot)


func add_revive_progress(seconds: float) -> void:
	if state != State.DOWNED:
		return
	revive_progress += seconds
	if revive_progress >= REVIVE_TIME:
		revive(REVIVE_HP_FRACTION)


func revive(hp_fraction: float) -> void:
	if state != State.DOWNED:
		return
	state = State.ALIVE
	hp = maxf(1.0, max_hp * hp_fraction)
	revive_progress = 0.0
	invulnerable_time = REVIVE_IFRAMES
	revive_shield = REVIVE_IFRAMES
	tag_time = TAG_TIME
	Events.hero_revived.emit(slot)
	_update_low_hp()


# --- rendering -------------------------------------------------------------------------------

func _update_visuals(delta: float) -> void:
	_anim_time += delta
	var frame: int = Frame.IDLE0
	if state == State.DOWNED:
		frame = Frame.DOWNED
	elif is_dashing():
		frame = Frame.DASH
	elif velocity.length_squared() > 100.0:
		frame = Frame.RUN0 + int(_anim_time * 10.0) % 4
	else:
		frame = Frame.IDLE0 + int(_anim_time * 2.0) % 2
	sprite.frame = frame
	var s := buff_product(&"sprite_scale")
	sprite.scale = Vector2(s, s)
	sprite.position = SPRITE_FEET_OFFSET * s - Vector2(0, roundf(air_height))
	if state == State.ALIVE and absf(aim_dir.x) > 0.05:
		sprite.flip_h = aim_dir.x < 0.0
	_hurt_flash = maxf(0.0, _hurt_flash - delta)
	# Each kind of invulnerability looks different: hit (blink), dash
	# (bright), fresh revive (gold shimmer).
	if _hurt_flash > 0.0:
		sprite.modulate = Color.WHITE.lerp(Color(2.0, 0.6, 0.6), Settings.flash_scale())
	elif is_dashing():
		sprite.modulate = Color(1.6, 1.6, 1.6)
	elif state == State.ALIVE and revive_shield > 0.0:
		var shimmer := 0.5 + 0.5 * sin(_anim_time * 14.0)
		sprite.modulate = Color(1.2, 1.12, 0.8).lerp(Color(1.7, 1.5, 0.85), shimmer)
	elif state == State.ALIVE and invulnerable_time > 0.0:
		if Settings.reduce_flashing:
			sprite.modulate = Color(1, 1, 1, 0.7)  # steady instead of blinking
		else:
			sprite.modulate = Color(1, 1, 1, 0.55 if int(invulnerable_time * 20.0) % 2 == 0 else 1.0)
	elif state == State.ALIVE and chill_time > 0.0:
		sprite.modulate = CHILL_TINT
	else:
		sprite.modulate = Color.WHITE
	var outline := color
	if _low_hp:
		outline = color.lerp(LOW_HP_COLOR, 0.5 + 0.5 * sin(_anim_time * 9.0))
	var mat := sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("outline_color", outline)
	queue_redraw()


func _draw() -> void:
	# Player-colour ring under the feet; pulses when the ultimate is ready.
	var ring_color := color
	if ult_charge >= 1.0 and state == State.ALIVE:
		ring_color = color.lerp(Color.WHITE, 0.5 + 0.5 * sin(_anim_time * 10.0))
	draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.35), true, -1.0, false)
	if not blessings.is_empty() and state == State.ALIVE:
		draw_arc(Vector2.ZERO, 9.0 + sin(_anim_time * 6.0), 0.0, TAU, 20, Color(BLESSING_RING, 0.7), 1.0, false)
	draw_arc(Vector2.ZERO, 7.0, 0.0, TAU, 20, ring_color, 1.0, false)
	draw_set_transform(Vector2.ZERO)
	if state == State.DOWNED:
		return  # the World's HeroOverlay shows the revive circle and progress
	# (The aim reticle is drawn by the World's HeroOverlay, above effects.)
	# Small HP bar once hurt.
	if hp < max_hp:
		var bw := 12.0
		draw_rect(Rect2(-bw * 0.5 - 1, 3, bw + 2, 3), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(-bw * 0.5, 4, bw * hp / max_hp, 1), Color(0.3, 0.95, 0.35) if hp > max_hp * 0.3 else Color(1, 0.3, 0.3))
