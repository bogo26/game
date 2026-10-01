class_name Profile
extends RefCounted
## Records kept between runs (user://profile.cfg): runs played, wins and best
## time per difficulty, the hardest difficulty each hero has won on (the
## stars in character select), and the furthest wave reached in Endless Waves
## per difficulty. Casual and Normal are open from the start; every harder
## difficulty unlocks with a win on the one before it, or by reaching wave
## UNLOCK_WAVE on it in Endless Waves (Hard: a Normal win or wave 20 on Normal).

const DEFAULT_PATH := "user://profile.cfg"
## Bumped when runs change length, so best times stay comparable: version 2
## is the 8-level run (a mini boss after level 3, then levels 4-6 and the
## final boss). Loading an older profile drops its best times but keeps wins,
## the difficulties unlocked and the hero stars.
const RUN_VERSION := 2
## How many difficulties there are (GameState.Difficulty: Casual, Normal,
## Hard, Nightmare, Torment). Profiles saved with fewer are padded.
const DIFFICULTIES := 5
## The first difficulty that has to be unlocked (Hard).
const FIRST_LOCKED := 2
## Endless Waves: reaching this wave on a difficulty unlocks the next one too.
const UNLOCK_WAVE := 20
## Where the profile is saved (tests point this elsewhere).
static var path := DEFAULT_PATH

var runs_played := 0
## Per difficulty (GameState.Difficulty): wins, and the fastest win in seconds (0 = none).
var wins := _ints([])
var best_time := _floats([])
## Hero id -> the hardest difficulty won with it.
var hero_best: Dictionary = {}
## Per difficulty: the furthest wave reached in Endless Waves (0 = none).
var best_wave := _ints([])


static func load_profile() -> Profile:
	var p := Profile.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return p
	p.runs_played = int(cfg.get_value("runs", "played", 0))
	p.wins = _ints(cfg.get_value("runs", "wins", []))
	if int(cfg.get_value("runs", "version", 1)) >= RUN_VERSION:
		p.best_time = _floats(cfg.get_value("runs", "best_time", []))
	p.hero_best = cfg.get_value("heroes", "best", {})
	p.best_wave = _ints(cfg.get_value("waves", "best", []))
	return p


## One number per difficulty (missing ones, from older profiles, are 0).
static func _ints(values: Array) -> PackedInt32Array:
	var out := PackedInt32Array(values)
	out.resize(DIFFICULTIES)
	return out


static func _floats(values: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array(values)
	out.resize(DIFFICULTIES)
	return out


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("runs", "version", RUN_VERSION)
	cfg.set_value("runs", "played", runs_played)
	cfg.set_value("runs", "wins", Array(wins))
	cfg.set_value("runs", "best_time", Array(best_time))
	cfg.set_value("heroes", "best", hero_best)
	cfg.set_value("waves", "best", Array(best_wave))
	cfg.save(path)


## Whether `difficulty` can be picked: Casual and Normal always, a harder one
## after a win on the one before it (or anything harder), or reaching
## UNLOCK_WAVE there in Endless Waves.
func unlocked(difficulty: int) -> bool:
	if difficulty < FIRST_LOCKED:
		return true
	for d in range(difficulty - 1, DIFFICULTIES):
		if wins[d] > 0 or best_wave[d] >= UNLOCK_WAVE:
			return true
	return false


## The hardest difficulty that can be picked.
func hardest_unlocked() -> int:
	var d := DIFFICULTIES - 1
	while d > 0 and not unlocked(d):
		d -= 1
	return d


## The hardest difficulty won with a hero, or -1.
func hero_rank(hero_id: StringName) -> int:
	return int(hero_best.get(String(hero_id), -1))


## Records a finished run and saves. Returns what's new, for the end screen:
## {"best_time": bool, "unlocked": the difficulty it opened, or -1}.
func record_run(victory: bool, difficulty: int, seconds: float, hero_ids: Array) -> Dictionary:
	var news := {"best_time": false, "unlocked": -1}
	runs_played += 1
	if victory:
		var hardest := hardest_unlocked()
		wins[difficulty] += 1
		if best_time[difficulty] <= 0.0 or seconds < best_time[difficulty]:
			news["best_time"] = true  # the first win is a best time too
			best_time[difficulty] = seconds
		news["unlocked"] = _newly_unlocked(hardest)
		for id: StringName in hero_ids:
			if difficulty > hero_rank(id):
				hero_best[String(id)] = difficulty
	save()
	return news


## Records an Endless Waves game (the furthest wave the team reached) and
## saves. Returns what's new, for the end screen:
## {"best_wave": bool, "unlocked": the difficulty it opened, or -1}.
func record_waves(difficulty: int, wave: int) -> Dictionary:
	var hardest := hardest_unlocked()
	var news := {"best_wave": wave > best_wave[difficulty], "unlocked": -1}
	if news["best_wave"]:
		best_wave[difficulty] = wave
	news["unlocked"] = _newly_unlocked(hardest)
	save()
	return news


func _newly_unlocked(hardest_before: int) -> int:
	var hardest := hardest_unlocked()
	return hardest if hardest > hardest_before else -1
