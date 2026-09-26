extends Node
## Run-wide state that survives scene changes: which hero each player picked,
## team XP/level, and where the team is in the level sequence.

const MAX_PLAYERS := 4
## Pick rounds that don't come from a team level-up.
const TREASURE_ROUND := 0
const BONUS_ROUND := -1
## Team lives at the start of every level.
const LIVES_PER_LEVEL := 1
const PLAYER_COLORS: Array[Color] = [
	Color("e8504a"),  # P1 red
	Color("4c93f2"),  # P2 blue
	Color("5cc85e"),  # P3 green
	Color("f2c63c"),  # P4 yellow
]
## Colour-blind friendly set (Okabe-Ito based): told apart by hue and lightness
## under the common kinds of colour blindness.
const COLORBLIND_COLORS: Array[Color] = [
	Color("e69f00"),  # P1 orange
	Color("56b4e9"),  # P2 sky blue
	Color("f0f0f0"),  # P3 white
	Color("cc79a7"),  # P4 reddish purple
]


class PlayerSlot:
	var slot: int
	var hero_id: StringName = &""
	var ready := false
	## Upgrade ids taken this run, in order (re-applied on every level).
	var upgrades: Array[StringName] = []
	## Ultimate charge carried from one level to the next.
	var ult_charge := 0.0

	func _init(p_slot: int) -> void:
		slot = p_slot


var slots: Array[PlayerSlot] = []
var team_level := 1
var xp := 0
var level_index := 0
var run_active := false
## Pick rounds earned but not yet resolved by the pick screen, oldest first:
## the team level each was earned at, or TREASURE_ROUND / BONUS_ROUND.
var pending_rounds: Array[int] = []
## How many pick rounds are waiting. Setting it (tests, debug) adds bonus
## rounds or drops the newest ones.
var pending_level_ups: int:
	get:
		return pending_rounds.size()
	set(value):
		while pending_rounds.size() < value:
			pending_rounds.append(BONUS_ROUND)
		if pending_rounds.size() > value:
			pending_rounds.resize(maxi(value, 0))
## How many of the waiting rounds are treasure (chest) rounds.
var pending_treasures: int:
	get:
		return pending_rounds.count(TREASURE_ROUND)
## --debug-levelups is granted once per run, not on every level.
var debug_picks_given := false
## Team lives left this level: a wipe with one left is a Second Wind (everyone
## gets back up) instead of the end of the run. Refilled every level.
var team_lives := 0
## Second Winds used this run (end screen).
var lives_used := 0
## Run statistics (shown on the end screen).
var run_kills := 0
var run_time := 0.0
var levels_cleared := 0
var last_run_victory := false


func _init() -> void:
	for i in MAX_PLAYERS:
		slots.append(PlayerSlot.new(i))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func player_color(slot: int) -> Color:
	var colors := COLORBLIND_COLORS if Settings.palette == Settings.Palette.COLORBLIND else PLAYER_COLORS
	return colors[slot % colors.size()]


## Slots that have a device assigned and a hero picked.
func active_slots() -> Array[int]:
	var out: Array[int] = []
	for s in slots:
		if InputRouter.get_player(s.slot).is_assigned() and s.hero_id != &"":
			out.append(s.slot)
	return out


func player_count() -> int:
	return maxi(active_slots().size(), 1)


func xp_to_next() -> int:
	return XpCurve.xp_to_next(team_level, player_count())


## A treasure chest: one extra upgrade pick for everyone, shown first.
func add_treasure_pick() -> void:
	pending_rounds.push_front(TREASURE_ROUND)


## The next pick round (see pending_rounds); -2 when none is waiting.
func next_round() -> int:
	return pending_rounds[0] if not pending_rounds.is_empty() else -2


## The next pick round was resolved.
func pop_round() -> void:
	if not pending_rounds.is_empty():
		pending_rounds.remove_at(0)


func reset_run() -> void:
	team_level = 1
	xp = 0
	level_index = 0
	pending_rounds.clear()
	debug_picks_given = false
	team_lives = LIVES_PER_LEVEL
	lives_used = 0
	run_kills = 0
	run_time = 0.0
	levels_cleared = 0
	last_run_victory = false
	run_active = true
	for s in slots:
		s.upgrades.clear()
		s.ult_charge = 0.0
	Events.xp_changed.emit(xp, xp_to_next(), team_level)


func add_xp(amount: int) -> void:
	xp += amount
	var needed := xp_to_next()
	while xp >= needed:
		xp -= needed
		team_level += 1
		pending_rounds.append(team_level)
		Events.team_level_up.emit(team_level)
		needed = xp_to_next()
	Events.xp_changed.emit(xp, needed, team_level)


func clear_players() -> void:
	for s in slots:
		s.hero_id = &""
		s.ready = false
		s.upgrades.clear()
		s.ult_charge = 0.0
