class_name HordeSim
extends RefCounted
## All enemies as plain data (structure of packed arrays), updated in one
## typed loop per frame and drawn through a single InstanceLayer.
##
## Per frame (called by World):
##   update(dt, targets)  move along the flow field + separation + walls,
##                        remove the dead, rebuild the spatial hash
##   queries / damage()   abilities and projectiles (hash is valid until the
##                        next update)
##   render(layer)
## Kills are recorded in kill_* arrays at damage time; World drains them.
## Alive enemies occupy indices [0, count); removal swaps with the last one,
## so use `uid` (stable) when an enemy must be remembered across frames.
## `pos` is an enemy's feet. Two shapes hang off it: the footprint circle
## (`t_radius`) for walls, crowding, contact and ground-level attacks, and the
## hurtbox (`t_hurt_*`, a box standing on the feet, as big as the sprite's
## body) that projectiles hit.

const CAPACITY := 512
const INDEX_BITS := 10  # CAPACITY must fit
const INDEX_MASK := (1 << INDEX_BITS) - 1
const TILE := 16.0
const INV_TILE := 1.0 / 16.0
const HASH_CELL := 16.0
const ATLAS_COLUMNS := 8
## Atlas cells are 32x32 with the feet (an enemy's `pos`) at (16, 24).
const SPRITE_CELL := Vector2i(32, 32)
const SPRITE_FEET := Vector2(16, 24)

const DIRECT_CHASE_TILES := 2
const SEPARATION_STRENGTH := 7.0
const MAX_NEIGHBORS := 6
const KNOCKBACK_DECAY := 9.0
const FLASH_TIME := 0.08
const SLOW_FACTOR := 0.45
const MARK_DAMAGE_MULT := 1.75
const RANGED_BACKOFF := 0.55   # ranged enemies retreat inside this fraction of their range
## Ranged enemies stand still and glow this long before each shot.
const WINDUP_TIME := 0.4
## A ranged enemy that can't shoot yet (no sight line, off screen) looks again after this.
const RETRY_TIME := 0.25
## Enemies pushed harder than this (px/s) toward a chasm go over the edge.
const FALL_PUSH := 30.0
const FALL_TIME := 0.45
## Elemental statuses from attack upgrades (see Elements): chilled enemies
## walk at CHILL_SPEED, and each poison stack slows 6%, down to half speed.
const CHILL_SPEED := 0.6
const POISON_SLOW_PER_STACK := 0.06
const POISON_MIN_SPEED := 0.5
## status_flags bits: what a status does beyond its basic effect.
const FLAG_WILDFIRE := 1  ## burning: spreads to enemies it touches (World)
const FLAG_INFERNO := 2   ## burning: explodes when it dies
const FLAG_SHATTER := 4   ## frozen: shatters into a freezing nova when it dies
const FLAG_PLAGUE := 8    ## poisoned: bursts into a toxic cloud when it dies
enum DeathFx { INFERNO, SHATTER, PLAGUE }
## Render tint codes (atlas shader, custom.b).
enum Tint { NONE, CHILL, FROZEN, BURN, POISON, CHARGING }

var count := 0
var pos := PackedVector2Array()
var vel := PackedVector2Array()        # knockback / impulses, decays
var sep := PackedVector2Array()        # last separation push (updated every other frame)
var hp := PackedFloat32Array()
var type := PackedInt32Array()
var uid := PackedInt32Array()
var flash := PackedFloat32Array()
var anim := PackedFloat32Array()
var stun := PackedFloat32Array()
var slow := PackedFloat32Array()
var facing := PackedFloat32Array()     # +1 right, -1 left
var action := PackedFloat32Array()     # behaviour timer (ranged cooldown, exploder fuse)
var state := PackedInt32Array()        # behaviour state (exploder: 1 = fuse lit)
var mark := PackedFloat32Array()       # > 0: takes critical damage (Rogue marks)
var fall := PackedFloat32Array()       # > 0: falling into a chasm (seconds left)
var last_slot := PackedInt32Array()    # player slot that last hit or pushed it (-1 none)
# Elemental statuses (attack upgrades):
var burn := PackedFloat32Array()          # seconds left burning
var burn_dps := PackedFloat32Array()
var poison := PackedFloat32Array()        # seconds left poisoned
var poison_stacks := PackedFloat32Array()
var poison_dps := PackedFloat32Array()    # per stack
var chill := PackedFloat32Array()         # seconds left chilled (slowed)
var frost := PackedFloat32Array()         # chills since the last freeze
var frozen := PackedFloat32Array()        # seconds left frozen solid (also stunned)
var ice_power := PackedFloat32Array()     # hit damage behind the frost (shatter nova)
var status_time := PackedFloat32Array()   # longest status left; 0 = none (fast skip)
var status_flags := PackedByteArray()

# Per-type tables (index = type id).
var types: Array[EnemyData] = []
var t_speed := PackedFloat32Array()
var t_radius := PackedFloat32Array()
var t_hurt_half_width := PackedFloat32Array()
var t_hurt_height := PackedFloat32Array()
var t_hp := PackedFloat32Array()
var t_damage := PackedFloat32Array()
var t_knockback := PackedFloat32Array()
var t_frame0 := PackedInt32Array()
var t_frames := PackedInt32Array()
var t_fps := PackedFloat32Array()
var t_behavior := PackedInt32Array()
var t_xp := PackedInt32Array()
var t_range := PackedFloat32Array()
var t_cooldown := PackedFloat32Array()
var t_shot_damage := PackedFloat32Array()
var t_shot_speed := PackedFloat32Array()
var t_blast_radius := PackedFloat32Array()
var t_blast_damage := PackedFloat32Array()
var t_fuse := PackedFloat32Array()
## 1 for types that never walk on their own (bosses, breakable objects, nests).
var t_static := PackedByteArray()
var t_scale := PackedFloat32Array()      # drawn size (elites are bigger)
var t_elite := PackedByteArray()         # Elites.Trait, 0 for ordinary enemies
var t_base := PackedInt32Array()         # the ordinary kind an elite is made from (itself otherwise)
var max_radius := 0.0
## Largest hurtbox among the enemies that exist right now: how far around a
## shot to look for bodies. A boss widens it only while it's alive.
var hurt_max_half_width := 0.0
var hurt_max_height := 0.0

# Kill log since the last drain.
var kill_pos := PackedVector2Array()
var kill_type := PackedInt32Array()
var kill_slot := PackedInt32Array()
## Damage dealt per player slot since the last drain (ultimate charge).
var damage_by_slot := PackedFloat32Array([0, 0, 0, 0])
## Biggest single hit per player slot since the World last read it.
var biggest_hit_by_slot := PackedFloat32Array([0, 0, 0, 0])
## Hits since the last drain (position, damage) for sparks and numbers.
var hit_pos := PackedVector2Array()
var hit_amount := PackedFloat32Array()
var hit_type := PackedInt32Array()
var hit_crit := PackedByteArray()
## Enemy shots fired since the World last checked (for sound).
var shots_fired := 0
## Ranged enemies only start a shot inside this rectangle (the camera view),
## so nothing fires from off screen. Empty = anywhere.
var view_rect := Rect2()
## Strength of the white hit flash (lower with "reduce flashing").
var flash_strength := 1.0
## Difficulty: multiplies every hit enemies deal (contact, shots, blasts).
var damage_mult := 1.0
## Exploders whose fuse lit this frame (uids), and ranged enemies that started
## winding up a shot (positions), for the World's warnings.
var fuse_uids := PackedInt32Array()
var windup_pos := PackedVector2Array()
## Enemies that went over a chasm edge since the World last checked (sound).
var falls := 0
## Elemental death effects since the last drain (the World plays them out):
## position, DeathFx kind, power (the damage they're based on), credited slot.
var death_fx_pos := PackedVector2Array()
var death_fx_kind := PackedByteArray()
var death_fx_power := PackedFloat32Array()
var death_fx_slot := PackedInt32Array()
## Exploder blasts since the last drain (World damages heroes + draws FX).
var blast_pos := PackedVector2Array()
var blast_radius := PackedFloat32Array()
var blast_damage := PackedFloat32Array()
## Kill-log slot for enemies that died on their own (no XP drop).
const SELF_KILL := -2

var hash := SpatialHash.new()
var grid: LevelGrid
var flow: FlowField
## Enemy shots are spawned here (optional; ranged enemies hold fire without it).
var projectiles: ProjectileSim

var _dead_pending := 0
var _type_count := PackedInt32Array()  # entries per type, dead-but-not-removed included
var _next_uid := 1
var _frame := 0
var _sort_keys := PackedInt32Array()
var _scratch := PackedInt32Array()


func setup(p_grid: LevelGrid, p_flow: FlowField, p_types: Array[EnemyData]) -> void:
	grid = p_grid
	flow = p_flow
	types = p_types
	pos.resize(CAPACITY)
	vel.resize(CAPACITY)
	sep.resize(CAPACITY)
	hp.resize(CAPACITY)
	type.resize(CAPACITY)
	uid.resize(CAPACITY)
	flash.resize(CAPACITY)
	anim.resize(CAPACITY)
	stun.resize(CAPACITY)
	slow.resize(CAPACITY)
	facing.resize(CAPACITY)
	action.resize(CAPACITY)
	state.resize(CAPACITY)
	mark.resize(CAPACITY)
	fall.resize(CAPACITY)
	last_slot.resize(CAPACITY)
	burn.resize(CAPACITY)
	burn_dps.resize(CAPACITY)
	poison.resize(CAPACITY)
	poison_stacks.resize(CAPACITY)
	poison_dps.resize(CAPACITY)
	chill.resize(CAPACITY)
	frost.resize(CAPACITY)
	frozen.resize(CAPACITY)
	ice_power.resize(CAPACITY)
	status_time.resize(CAPACITY)
	status_flags.resize(CAPACITY)
	count = 0
	t_speed.clear()
	t_radius.clear()
	t_hurt_half_width.clear()
	t_hurt_height.clear()
	t_hp.clear()
	t_damage.clear()
	t_knockback.clear()
	t_frame0.clear()
	t_frames.clear()
	t_fps.clear()
	t_behavior.clear()
	t_xp.clear()
	t_range.clear()
	t_cooldown.clear()
	t_shot_damage.clear()
	t_shot_speed.clear()
	t_blast_radius.clear()
	t_blast_damage.clear()
	t_fuse.clear()
	t_static.clear()
	t_scale.clear()
	t_elite.clear()
	t_base.clear()
	max_radius = 0.0
	for data in types:
		t_speed.append(data.speed)
		t_radius.append(data.radius)
		t_hurt_half_width.append(data.hurt_size.x * 0.5)
		t_hurt_height.append(data.hurt_size.y)
		t_hp.append(data.max_hp)
		t_damage.append(data.contact_damage)
		t_knockback.append(data.knockback_taken)
		t_frame0.append(data.atlas_row * ATLAS_COLUMNS)
		t_frames.append(data.walk_frames)
		t_fps.append(data.anim_fps)
		t_behavior.append(data.behavior)
		t_xp.append(data.xp)
		t_range.append(data.attack_range)
		t_cooldown.append(data.attack_cooldown)
		t_shot_damage.append(data.projectile_damage)
		t_shot_speed.append(data.projectile_speed)
		t_blast_radius.append(data.explosion_radius)
		t_blast_damage.append(data.explosion_damage)
		t_fuse.append(data.fuse_time)
		t_static.append(1 if data.is_static() else 0)
		t_scale.append(data.draw_scale)
		t_elite.append(data.elite_trait)
		max_radius = maxf(max_radius, data.radius)
	for t in types.size():
		var base := type_index(types[t].base_id) if types[t].base_id != &"" else t
		t_base.append(base if base >= 0 else t)
	_type_count.resize(types.size())
	_type_count.fill(0)
	_refresh_hurt_reach()
	hash.setup(grid.size_px(), HASH_CELL, CAPACITY)


## Enemies of type `t` (alive or not yet removed).
func count_of_type(t: int) -> int:
	return _type_count[t]


func is_elite(i: int) -> bool:
	return t_elite[type[i]] != 0


func type_index(id: StringName) -> int:
	for i in types.size():
		if types[i].id == id:
			return i
	return -1


## Returns the new enemy's index, or -1 when full.
func spawn(type_id: int, p: Vector2, hp_multiplier: float = 1.0) -> int:
	if count >= CAPACITY:
		return -1
	var i := count
	count += 1
	pos[i] = p
	vel[i] = Vector2.ZERO
	sep[i] = Vector2.ZERO
	hp[i] = t_hp[type_id] * hp_multiplier
	type[i] = type_id
	uid[i] = _next_uid
	_next_uid += 1
	flash[i] = 0.0
	anim[i] = randf() * 4.0
	stun[i] = 0.0
	slow[i] = 0.0
	facing[i] = 1.0
	action[i] = randf() * 1.5
	state[i] = 0
	mark[i] = 0.0
	fall[i] = 0.0
	last_slot[i] = -1
	burn[i] = 0.0
	burn_dps[i] = 0.0
	poison[i] = 0.0
	poison_stacks[i] = 0.0
	poison_dps[i] = 0.0
	chill[i] = 0.0
	frost[i] = 0.0
	frozen[i] = 0.0
	ice_power[i] = 0.0
	status_time[i] = 0.0
	status_flags[i] = 0
	_type_count[type_id] += 1
	hurt_max_half_width = maxf(hurt_max_half_width, t_hurt_half_width[type_id])
	hurt_max_height = maxf(hurt_max_height, t_hurt_height[type_id])
	return i


func _refresh_hurt_reach() -> void:
	hurt_max_half_width = 0.0
	hurt_max_height = 0.0
	for t in _type_count.size():
		if _type_count[t] > 0:
			hurt_max_half_width = maxf(hurt_max_half_width, t_hurt_half_width[t])
			hurt_max_height = maxf(hurt_max_height, t_hurt_height[t])


func is_alive(i: int) -> bool:
	return i >= 0 and i < count and hp[i] > 0.0


## Regular walking enemies (not a boss body, breakable object or nest).
func is_mobile(i: int) -> bool:
	return t_static[type[i]] == 0


## Breakable scenery (barrels, urns): hittable, but not an enemy.
func is_object(i: int) -> bool:
	return t_behavior[type[i]] == EnemyData.Behavior.OBJECT


## Alive entries minus objects and nests: what the spawner's cap counts.
func enemy_count() -> int:
	var props := 0
	for t in _type_count.size():
		var b := t_behavior[t]
		if b == EnemyData.Behavior.OBJECT or b == EnemyData.Behavior.NEST:
			props += _type_count[t]
	return maxi(0, alive_count() - props)


func alive_count() -> int:
	return count - _dead_pending


## Applies damage; returns true if this hit killed the enemy. `crit` only
## marks the hit for feedback (the caller already multiplied the damage).
## Marked enemies turn non-crit hits into crits (x MARK_DAMAGE_MULT); hits
## that already crit aren't multiplied twice. `at` is where the hit landed
## (sparks, numbers); by default the middle of the body.
func damage(i: int, amount: float, knockback: Vector2, source_slot: int, crit: bool = false,
		at: Vector2 = Vector2.INF) -> bool:
	var h := hp[i]
	if h <= 0.0 or fall[i] > 0.0:
		return false
	if source_slot >= 0:
		last_slot[i] = source_slot
	if mark[i] > 0.0 and not crit:
		amount *= MARK_DAMAGE_MULT
		crit = true
	var remaining := h - amount
	hp[i] = remaining
	flash[i] = FLASH_TIME
	if hit_pos.size() < 256:
		hit_pos.append(at if at.is_finite() else body_center(i))
		hit_amount.append(amount)
		hit_type.append(type[i])
		hit_crit.append(1 if crit else 0)
	if knockback != Vector2.ZERO:
		vel[i] += knockback * t_knockback[type[i]]
	if source_slot >= 0 and source_slot < damage_by_slot.size():
		damage_by_slot[source_slot] += minf(amount, h)
		if amount > biggest_hit_by_slot[source_slot]:
			biggest_hit_by_slot[source_slot] = amount
	if remaining <= 0.0:
		kill_pos.append(pos[i])
		kill_type.append(type[i])
		kill_slot.append(source_slot)
		_dead_pending += 1
		if status_time[i] > 0.0:
			_log_death_fx(pos[i], status_flags[i], burn[i] > 0.0, burn_dps[i], poison[i] > 0.0,
				poison_dps[i], frozen[i] > 0.0, ice_power[i], last_slot[i])
		return true
	return false


# --- elemental statuses --------------------------------------------------------------------

## Scenery (barrels, urns) and enemies on their way down a chasm don't burn.
func can_take_status(i: int) -> bool:
	return hp[i] > 0.0 and fall[i] <= 0.0 and t_behavior[type[i]] != EnemyData.Behavior.OBJECT


## Sets it on fire: `dps` for `seconds` (a stronger or longer burn replaces
## a weaker one; they don't add up).
func ignite(i: int, dps: float, seconds: float, slot: int, flags: int = 0) -> void:
	if not can_take_status(i):
		return
	burn[i] = maxf(burn[i], seconds)
	burn_dps[i] = maxf(burn_dps[i], dps)
	_add_status(i, seconds, slot, flags)


## Adds a poison stack (up to `max_stacks`); every stack deals `dps_per_stack`
## and slows a little. Each dose refreshes the timer.
func add_poison(i: int, dps_per_stack: float, seconds: float, max_stacks: int, slot: int,
		flags: int = 0) -> void:
	if not can_take_status(i):
		return
	poison[i] = maxf(poison[i], seconds)
	poison_stacks[i] = minf(poison_stacks[i] + 1.0, float(max_stacks))
	poison_dps[i] = maxf(poison_dps[i], dps_per_stack)
	_add_status(i, seconds, slot, flags)


## Chills it (slowed). With `freeze_hits` > 0, every that many chills freeze
## it solid for `freeze_time` (bosses never freeze). Returns true if it froze.
func add_chill(i: int, seconds: float, freeze_hits: int, freeze_time: float, power: float, slot: int,
		flags: int = 0) -> bool:
	if not can_take_status(i):
		return false
	chill[i] = maxf(chill[i], seconds)
	ice_power[i] = maxf(ice_power[i], power)
	_add_status(i, seconds, slot, flags)
	if freeze_hits <= 0 or frozen[i] > 0.0 or t_behavior[type[i]] == EnemyData.Behavior.BOSS:
		return false
	frost[i] += 1.0
	if frost[i] < float(freeze_hits):
		return false
	frost[i] = 0.0
	frozen[i] = freeze_time
	stun[i] = maxf(stun[i], freeze_time)
	status_time[i] = maxf(status_time[i], freeze_time)
	return true


func is_frozen(i: int) -> bool:
	return frozen[i] > 0.0


func is_burning(i: int) -> bool:
	return burn[i] > 0.0


func _add_status(i: int, seconds: float, slot: int, flags: int) -> void:
	status_time[i] = maxf(status_time[i], seconds)
	status_flags[i] |= flags
	if slot >= 0:
		last_slot[i] = slot


func clear_death_fx() -> void:
	death_fx_pos.clear()
	death_fx_kind.clear()
	death_fx_power.clear()
	death_fx_slot.clear()


## Removes the first `n` logged death effects (played).
func drop_death_fx(n: int) -> void:
	death_fx_pos = death_fx_pos.slice(n)
	death_fx_kind = death_fx_kind.slice(n)
	death_fx_power = death_fx_power.slice(n)
	death_fx_slot = death_fx_slot.slice(n)


func _log_death_fx(p: Vector2, flags: int, burning: bool, burn_power: float, poisoned: bool,
		poison_power: float, is_ice: bool, frost_power: float, slot: int) -> void:
	if burning and flags & FLAG_INFERNO:
		_push_death_fx(p, DeathFx.INFERNO, burn_power, slot)
	if is_ice and flags & FLAG_SHATTER:
		_push_death_fx(p, DeathFx.SHATTER, frost_power, slot)
	if poisoned and flags & FLAG_PLAGUE:
		_push_death_fx(p, DeathFx.PLAGUE, poison_power, slot)


func _push_death_fx(p: Vector2, kind: DeathFx, power: float, slot: int) -> void:
	if death_fx_pos.size() >= 128:
		return
	death_fx_pos.append(p)
	death_fx_kind.append(kind)
	death_fx_power.append(power)
	death_fx_slot.append(slot)


func apply_stun(i: int, seconds: float) -> void:
	if t_behavior[type[i]] != EnemyData.Behavior.BOSS:
		stun[i] = maxf(stun[i], seconds)


func apply_slow(i: int, seconds: float) -> void:
	if t_behavior[type[i]] != EnemyData.Behavior.BOSS:
		slow[i] = maxf(slow[i], seconds)


## Knockback without damage; the pusher gets the kill if it goes into a chasm.
func push(i: int, impulse: Vector2, source_slot: int) -> void:
	vel[i] += impulse * t_knockback[type[i]]
	if source_slot >= 0:
		last_slot[i] = source_slot


func is_falling(i: int) -> bool:
	return fall[i] > 0.0


## Middle of the enemy's hurtbox (its drawn body); `pos` is the feet.
func body_center(i: int) -> Vector2:
	return pos[i] - Vector2(0.0, t_hurt_height[type[i]] * 0.5)


## Current index of the enemy with this uid (indices move on removal), or -1.
func index_of_uid(id: int, hint: int = -1) -> int:
	if hint >= 0 and hint < count and uid[hint] == id:
		return hint
	for i in count:
		if uid[i] == id:
			return i
	return -1


func apply_mark(i: int, seconds: float) -> void:
	mark[i] = maxf(mark[i], seconds)


## Forgets this frame's fuse and wind-up logs (the World read them).
func clear_warning_logs() -> void:
	fuse_uids.clear()
	windup_pos.clear()


func clear_blasts() -> void:
	blast_pos.clear()
	blast_radius.clear()
	blast_damage.clear()


func relocate(i: int, p: Vector2) -> void:
	pos[i] = p
	vel[i] = Vector2.ZERO


func clear_hit_log() -> void:
	hit_pos.clear()
	hit_amount.clear()
	hit_type.clear()
	hit_crit.clear()


func clear_kill_log() -> void:
	kill_pos.clear()
	kill_type.clear()
	kill_slot.clear()


func update(dt: float, targets: PackedVector2Array) -> void:
	_frame += 1
	var n := count
	if n > 0:
		_move(dt, targets, n)
	_compact()
	hash.rebuild(pos, count)


func _move(dt: float, targets: PackedVector2Array, n: int) -> void:
	var P := pos
	var V := vel
	var S := sep
	var HP := hp
	var T := type
	var FL := flash
	var AN := anim
	var STN := stun
	var SLW := slow
	var FC := facing
	var ACT := action
	var STATE := state
	var MK := mark
	var FALLS := fall
	var terr := grid.terrain
	var STT := status_time
	var BRN := burn
	var BDPS := burn_dps
	var PSN := poison
	var PSTK := poison_stacks
	var PDPS := poison_dps
	var CHL := chill
	var FRST := frost
	var FRZ := frozen
	var speed_t := t_speed
	var radius_t := t_radius
	var behavior_t := t_behavior
	var range_t := t_range
	var cooldown_t := t_cooldown
	var shot_speed_t := t_shot_speed
	var shot_damage_t := t_shot_damage
	var blast_radius_t := t_blast_radius
	var blast_damage_t := t_blast_damage
	var fuse_t := t_fuse
	var static_t := t_static
	var head := hash.head
	var nxt := hash.next
	var hcols := hash.cols
	var hrows := hash.rows
	var hinv := hash.inv_cell
	var solid := grid.solid
	var gw := grid.width
	var gh := grid.height
	var ncells := gw * gh
	var fdir := flow.dirs
	var fdist := flow.dist
	var dirs := FlowField.DIRS
	var ntargets := targets.size()
	var decay := exp(-KNOCKBACK_DECAY * dt)
	var parity := _frame & 1
	var check_view := view_rect.has_area()
	var view := view_rect.grow(-4.0)

	for i in n:
		if HP[i] <= 0.0:
			continue
		var p := P[i]
		var t := T[i]
		var falling := FALLS[i]
		if falling > 0.0:
			# Tumbling into a chasm: drift with the push, then gone (kill
			# credit to whoever pushed it; no self-kill, so XP still drops).
			falling -= dt
			P[i] = p + V[i] * (dt * 0.5)
			V[i] = V[i] * decay
			if falling <= 0.0:
				FALLS[i] = 0.0
				HP[i] = 0.0
				kill_pos.append(p)
				kill_type.append(t)
				kill_slot.append(last_slot[i])
				_dead_pending += 1
			else:
				FALLS[i] = falling
			continue
		if STT[i] > 0.0:
			# Elemental statuses: burn and poison damage over time, timers.
			STT[i] = maxf(0.0, STT[i] - dt)
			var dot := 0.0
			var b := BRN[i]
			if b > 0.0:
				BRN[i] = b - dt
				dot += BDPS[i] * dt
			var ps := PSN[i]
			if ps > 0.0:
				dot += PDPS[i] * PSTK[i] * dt
				PSN[i] = ps - dt
				if ps - dt <= 0.0:
					PSTK[i] = 0.0
			var ch := CHL[i]
			if ch > 0.0:
				CHL[i] = ch - dt
				if ch - dt <= 0.0:
					FRST[i] = 0.0
			var fz := FRZ[i]
			if fz > 0.0:
				FRZ[i] = fz - dt
			if dot > 0.0:
				var before := HP[i]
				HP[i] = before - dot
				var slot := last_slot[i]
				if slot >= 0 and slot < damage_by_slot.size():
					damage_by_slot[slot] += minf(dot, before)
				if before - dot <= 0.0:
					kill_pos.append(p)
					kill_type.append(t)
					kill_slot.append(slot)
					_dead_pending += 1
					_log_death_fx(p, status_flags[i], b > 0.0, BDPS[i], ps > 0.0, PDPS[i], fz > 0.0,
						ice_power[i], slot)
					continue
			if STT[i] <= 0.0:
				status_flags[i] = 0  # all statuses over: forget their death effects
		var r := radius_t[t]
		var fl := FL[i]
		if fl > 0.0:
			FL[i] = fl - dt
		var sl := SLW[i]
		if sl > 0.0:
			SLW[i] = sl - dt
		var mk := MK[i]
		if mk > 0.0:
			MK[i] = mk - dt
		if static_t[t] != 0:
			AN[i] += dt  # boss (moved by BossDemon), objects and nests stay put
			continue
		var desired := Vector2.ZERO
		var st := STN[i]
		if st > 0.0:
			STN[i] = st - dt
		else:
			var behavior := behavior_t[t]
			var ci := int(p.y * INV_TILE) * gw + int(p.x * INV_TILE)
			var direct := true
			if ci >= 0 and ci < ncells:
				var fd := fdir[ci]
				if fd != 0 and fdist[ci] > DIRECT_CHASE_TILES:
					desired = dirs[fd]
					direct = false
			# Nearest hero (cheap: at most 4). Chasers only need it up close.
			var best := INF
			var tp := p
			if (direct or behavior != EnemyData.Behavior.CHASER) and ntargets > 0:
				for k in ntargets:
					var q := targets[k]
					var d2 := p.distance_squared_to(q)
					if d2 < best:
						best = d2
						tp = q
				if direct and best > 1.0:
					desired = (tp - p) / sqrt(best)
			if behavior == EnemyData.Behavior.RANGED and best < INF:
				var dist := sqrt(best)
				var attack_range := range_t[t]
				if STATE[i] == 1:
					# Winding up (pose + pink glow): stand still, then fire at the
					# nearest hero if it's still in sight.
					desired = Vector2.ZERO
					var wind := ACT[i] - dt
					if wind <= 0.0:
						STATE[i] = 0
						wind = cooldown_t[t] - WINDUP_TIME
						if projectiles != null and grid.line_of_sight(p, tp):
							var aim := (tp - p) / maxf(dist, 0.001)
							projectiles.spawn(p + Vector2(0, -8), aim * shot_speed_t[t], shot_damage_t[t] * damage_mult, 3.0,
								attack_range * 1.6 / shot_speed_t[t], ProjectileSim.Team.ENEMY, -1,
								ProjectileSim.Look.SPIT)
							shots_fired += 1
					ACT[i] = wind
				elif dist < attack_range:
					if dist < attack_range * RANGED_BACKOFF:
						desired = (p - tp) / maxf(dist, 0.001)
					else:
						desired = Vector2.ZERO
					var cd := ACT[i] - dt
					if cd <= 0.0:
						if (not check_view or view.has_point(p)) and grid.line_of_sight(p, tp):
							STATE[i] = 1
							cd = WINDUP_TIME
							windup_pos.append(p)
						else:
							cd = RETRY_TIME
					ACT[i] = cd
			elif behavior == EnemyData.Behavior.EXPLODER and best < INF:
				if STATE[i] == 0 and best < blast_radius_t[t] * blast_radius_t[t] * 0.4:
					STATE[i] = 1
					ACT[i] = fuse_t[t]
					fuse_uids.append(uid[i])
				if STATE[i] == 1:
					desired = Vector2.ZERO
					var fuse := ACT[i] - dt
					ACT[i] = fuse
					if fuse <= 0.0:
						blast_pos.append(p)
						blast_radius.append(blast_radius_t[t])
						blast_damage.append(blast_damage_t[t] * damage_mult)
						HP[i] = 0.0
						kill_pos.append(p)
						kill_type.append(t)
						kill_slot.append(SELF_KILL)
						_dead_pending += 1
						continue
			var spd := speed_t[t]
			if sl > 0.0:
				spd *= SLOW_FACTOR
			if ci >= 0 and ci < ncells and terr[ci] == LevelGrid.Terrain.WATER:
				spd *= LevelGrid.WATER_SPEED
			if STT[i] > 0.0:
				if CHL[i] > 0.0:
					spd *= CHILL_SPEED
				if PSTK[i] > 0.0:
					spd *= maxf(POISON_MIN_SPEED, 1.0 - POISON_SLOW_PER_STACK * PSTK[i])
			desired *= spd

		# Separation: half of the enemies refresh their push each frame.
		if (i & 1) == parity:
			var push := Vector2.ZERO
			var fx := p.x * hinv
			var fy := p.y * hinv
			var hx := clampi(int(fx), 0, hcols - 1)
			var hy := clampi(int(fy), 0, hrows - 1)
			var ox := 1 if fx - hx >= 0.5 else -1
			var oy := 1 if fy - hy >= 0.5 else -1
			var checked := 0
			for q in 4:
				var qx := hx + (ox if (q & 1) != 0 else 0)
				var qy := hy + (oy if (q & 2) != 0 else 0)
				if qx < 0 or qy < 0 or qx >= hcols or qy >= hrows:
					continue
				var j := head[qy * hcols + qx]
				while j != -1 and checked < MAX_NEIGHBORS:
					if j != i and j < n:
						var dv := p - P[j]
						var d2 := dv.length_squared()
						var rr := r + radius_t[T[j]]
						if d2 < rr * rr:
							checked += 1
							if d2 > 0.0001:
								var dist := sqrt(d2)
								push += dv * ((rr - dist) / dist)
							else:
								push += Vector2(1.0 if i > j else -1.0, 0.5)
					j = nxt[j]
			S[i] = push

		var kv := V[i]
		var v := desired + S[i] * SEPARATION_STRENGTH + kv
		V[i] = kv * decay
		# A hard enough push carries it over a chasm's edge.
		var knocked := kv.length_squared() > FALL_PUSH * FALL_PUSH
		if v.x > 2.0:
			FC[i] = 1.0
		elif v.x < -2.0:
			FC[i] = -1.0
		AN[i] += dt

		# Tile collision, per axis, probing the leading edge.
		var nx := p.x + v.x * dt
		var ny := p.y + v.y * dt
		var edge_x := nx + (r if v.x > 0.0 else -r)
		var ex := int(edge_x * INV_TILE)
		var py := int(p.y * INV_TILE)
		if edge_x < 0.0 or ex >= gw:
			nx = p.x
		else:
			var cx_i := py * gw + ex
			if solid[cx_i] != 0 and not (knocked and terr[cx_i] == LevelGrid.Terrain.CHASM):
				nx = p.x
		var edge_y := ny + (r if v.y > 0.0 else -r)
		var ey := int(edge_y * INV_TILE)
		var ncx := int(nx * INV_TILE)
		if edge_y < 0.0 or ey >= gh:
			ny = p.y
		else:
			var cy_i := ey * gw + ncx
			if solid[cy_i] != 0 and not (knocked and terr[cy_i] == LevelGrid.Terrain.CHASM):
				ny = p.y
		P[i] = Vector2(nx, ny)
		if knocked:
			var cc := int(ny * INV_TILE) * gw + int(nx * INV_TILE)
			if cc >= 0 and cc < ncells and terr[cc] == LevelGrid.Terrain.CHASM:
				FALLS[i] = FALL_TIME
				falls += 1

	pos = P
	vel = V
	sep = S
	hp = HP
	flash = FL
	anim = AN
	stun = STN
	slow = SLW
	facing = FC
	action = ACT
	state = STATE
	mark = MK
	fall = FALLS
	status_time = STT
	burn = BRN
	burn_dps = BDPS
	poison = PSN
	poison_stacks = PSTK
	poison_dps = PDPS
	chill = CHL
	frost = FRST
	frozen = FRZ


## Removes enemies killed since the last update (swap with the last one).
func _compact() -> void:
	if _dead_pending == 0:
		return
	var i := count - 1
	while i >= 0 and _dead_pending > 0:
		if hp[i] <= 0.0:
			_remove_at(i)
			_dead_pending -= 1
		i -= 1
	_dead_pending = 0


func _remove_at(i: int) -> void:
	var t := type[i]
	_type_count[t] -= 1
	if _type_count[t] == 0:
		_refresh_hurt_reach()
	var last := count - 1
	if i != last:
		pos[i] = pos[last]
		vel[i] = vel[last]
		sep[i] = sep[last]
		hp[i] = hp[last]
		type[i] = type[last]
		uid[i] = uid[last]
		flash[i] = flash[last]
		anim[i] = anim[last]
		stun[i] = stun[last]
		slow[i] = slow[last]
		facing[i] = facing[last]
		action[i] = action[last]
		state[i] = state[last]
		mark[i] = mark[last]
		fall[i] = fall[last]
		last_slot[i] = last_slot[last]
		burn[i] = burn[last]
		burn_dps[i] = burn_dps[last]
		poison[i] = poison[last]
		poison_stacks[i] = poison_stacks[last]
		poison_dps[i] = poison_dps[last]
		chill[i] = chill[last]
		frost[i] = frost[last]
		frozen[i] = frozen[last]
		ice_power[i] = ice_power[last]
		status_time[i] = status_time[last]
		status_flags[i] = status_flags[last]
	count = last


# --- queries (valid between update() calls) ------------------------------------------

## Fills `out` with alive enemies whose body overlaps the circle.
func query_circle(center: Vector2, radius: float, out: PackedInt32Array) -> int:
	out.clear()
	_scratch.clear()
	hash.gather(center, radius + max_radius, _scratch)
	for j in _scratch:
		if j < count and hp[j] > 0.0 and fall[j] <= 0.0:
			var rr := radius + t_radius[type[j]]
			if center.distance_squared_to(pos[j]) <= rr * rr:
				out.append(j)
	return out.size()


## Enemies within `radius` and inside a cone of `half_angle` around `dir`
## (enemies touching the centre always count).
func query_arc(center: Vector2, dir: Vector2, radius: float, half_angle: float, out: PackedInt32Array) -> int:
	query_circle(center, radius, out)
	var cos_limit := cos(half_angle)
	var i := out.size() - 1
	while i >= 0:
		var j := out[i]
		var to := pos[j] - center
		var dist := to.length()
		if dist > t_radius[type[j]] + 4.0 and to.dot(dir) < cos_limit * dist:
			out.remove_at(i)
		i -= 1
	return out.size()


## Nearest alive enemy within max_distance, or -1. Objects (barrels, urns)
## count only with `include_objects`.
func nearest(center: Vector2, max_distance: float, include_objects: bool = true) -> int:
	_scratch.clear()
	hash.gather(center, max_distance, _scratch)
	var best := -1
	var best_d2 := max_distance * max_distance
	for j in _scratch:
		if j < count and hp[j] > 0.0 and fall[j] <= 0.0 \
				and (include_objects or t_behavior[type[j]] != EnemyData.Behavior.OBJECT):
			var d2 := center.distance_squared_to(pos[j])
			if d2 < best_d2:
				best_d2 = d2
				best = j
	return best


## Highest contact damage among enemies touching a body at `center`.
func contact_damage_at(center: Vector2, body_radius: float) -> float:
	_scratch.clear()
	hash.gather(center, body_radius + max_radius, _scratch)
	var worst := 0.0
	for j in _scratch:
		if j < count and hp[j] > 0.0 and stun[j] <= 0.0 and fall[j] <= 0.0:
			var t := type[j]
			var rr := body_radius + t_radius[t]
			if center.distance_squared_to(pos[j]) <= rr * rr:
				worst = maxf(worst, t_damage[t])
	return worst * damage_mult


# --- rendering -------------------------------------------------------------------------

func render(layer: InstanceLayer) -> void:
	var n := count
	var keys := _sort_keys
	keys.resize(n)
	var P := pos
	for i in n:
		keys[i] = (maxi(int(P[i].y), 0) << INDEX_BITS) | i
	keys.sort()
	_sort_keys = keys

	var buf := layer.buffer
	var HP := hp
	var T := type
	var FC := facing
	var AN := anim
	var FL := flash
	var SLW := slow
	var STN := stun
	var FALLS := fall
	var STT := status_time
	var FRZ := frozen
	var BRN := burn
	var PSN := poison
	var CHL := chill
	var frame0 := t_frame0
	var frames := t_frames
	var fps := t_fps
	var w := 0
	for k in n:
		var i := keys[k] & INDEX_MASK
		if HP[i] <= 0.0:
			continue
		var p := P[i]
		var t := T[i]
		if t_behavior[t] == EnemyData.Behavior.BOSS:
			continue  # drawn by its controller node
		var o := w * InstanceLayer.STRIDE
		var fade := 1.0
		if FALLS[i] > 0.0:
			fade = FALLS[i] / FALL_TIME  # shrinks and fades into the chasm
		var size := t_scale[t] * fade
		buf[o] = FC[i] * size
		buf[o + 5] = size
		buf[o + 11] = fade
		buf[o + 3] = roundf(p.x)
		buf[o + 7] = roundf(p.y)
		var frame := frame0[t]
		var beh := t_behavior[t]
		if beh == EnemyData.Behavior.EXPLODER and state[i] == 1:
			frame += 4 + int(AN[i] * 12.0) % 2
		elif beh == EnemyData.Behavior.NEST and action[i] > 0.0:
			frame += 4 + int(AN[i] * 10.0) % 2  # spawning (LevelDirector sets the pose timer)
		elif beh == EnemyData.Behavior.RANGED and state[i] == 1:
			frame += 4  # winding up a shot
		elif STN[i] <= 0.0:
			frame += int(AN[i] * fps[t]) % frames[t]
		buf[o + 8] = float(frame)
		buf[o + 9] = flash_strength if FL[i] > 0.0 else 0.0
		var tint := Tint.NONE
		if STT[i] > 0.0:
			if FRZ[i] > 0.0:
				tint = Tint.FROZEN
			elif BRN[i] > 0.0:
				tint = Tint.BURN
			elif PSN[i] > 0.0:
				tint = Tint.POISON
			elif CHL[i] > 0.0:
				tint = Tint.CHILL
		if tint == Tint.NONE and SLW[i] > 0.0:
			tint = Tint.CHILL
		if beh == EnemyData.Behavior.RANGED and state[i] == 1 and STN[i] <= 0.0:
			tint = Tint.CHARGING
		# Elites add their trait x 10: the shader draws their outline from it.
		buf[o + 10] = float(tint + t_elite[t] * 10)
		w += 1
	layer.buffer = buf
	layer.commit(w)
