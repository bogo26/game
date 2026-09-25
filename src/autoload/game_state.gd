extends Node
## Run-wide state that survives scene changes: which hero each player picked,
## team XP/level, and where the team is in the level sequence.

const MAX_PLAYERS := 4
const PLAYER_COLORS: Array[Color] = [
	Color("e8504a"),  # P1 red
	Color("4c93f2"),  # P2 blue
	Color("5cc85e"),  # P3 green
	Color("f2c63c"),  # P4 yellow
]


class PlayerSlot:
	var slot: int
	var hero_id: StringName = &""
	var ready := false

	func _init(p_slot: int) -> void:
		slot = p_slot


var slots: Array[PlayerSlot] = []
var team_level := 1
var xp := 0
var level_index := 0
var run_active := false
## Level-ups earned but not yet resolved by the pick screen.
var pending_level_ups := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in MAX_PLAYERS:
		slots.append(PlayerSlot.new(i))


func player_color(slot: int) -> Color:
	return PLAYER_COLORS[slot % PLAYER_COLORS.size()]


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


func reset_run() -> void:
	team_level = 1
	xp = 0
	level_index = 0
	pending_level_ups = 0
	run_active = true
	Events.xp_changed.emit(xp, xp_to_next(), team_level)


func add_xp(amount: int) -> void:
	xp += amount
	var needed := xp_to_next()
	while xp >= needed:
		xp -= needed
		team_level += 1
		pending_level_ups += 1
		Events.team_level_up.emit(team_level)
		needed = xp_to_next()
	Events.xp_changed.emit(xp, needed, team_level)


func clear_players() -> void:
	for s in slots:
		s.hero_id = &""
		s.ready = false
