class_name XpCurve
extends RefCounted
## Team XP needed to go from `level` to `level + 1`.
## Scales with player count because more players kill faster, and every
## player gets their own pick on each team level-up.
## Every level-up pauses the game until everyone has picked, so they're
## paced at about two per regular level (a dozen in a run), not one every
## few seconds.

const BASE := 24.0
const EXPONENT := 1.35
const LINEAR := 16.0
const PER_EXTRA_PLAYER := 0.35


static func xp_to_next(level: int, player_count: int = 1) -> int:
	var lvl := maxi(level, 1)
	var players := clampi(player_count, 1, 4)
	var raw := BASE * pow(float(lvl), EXPONENT) + LINEAR * float(lvl)
	return int(round(raw * (1.0 + PER_EXTRA_PLAYER * float(players - 1))))
