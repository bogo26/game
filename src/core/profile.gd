class_name Profile
extends RefCounted
## Records kept between runs (user://profile.cfg): runs played, wins and best
## time per difficulty, and the hardest difficulty each hero has won on (the
## stars in character select). Hard unlocks with a win on Normal.

const DEFAULT_PATH := "user://profile.cfg"
## Bumped when runs change length, so best times stay comparable: version 2
## is the 8-level run (a mini boss after level 3, then levels 4-6 and the
## final boss). Loading an older profile drops its best times but keeps wins,
## Hard unlocked and the hero stars.
const RUN_VERSION := 2
## Where the profile is saved (tests point this elsewhere).
static var path := DEFAULT_PATH

var runs_played := 0
## Per difficulty (GameState.Difficulty): wins, and the fastest win in seconds (0 = none).
var wins := PackedInt32Array([0, 0, 0])
var best_time := PackedFloat32Array([0.0, 0.0, 0.0])
## Hero id -> the hardest difficulty won with it.
var hero_best: Dictionary = {}


static func load_profile() -> Profile:
	var p := Profile.new()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return p
	p.runs_played = int(cfg.get_value("runs", "played", 0))
	p.wins = PackedInt32Array(cfg.get_value("runs", "wins", [0, 0, 0]))
	if int(cfg.get_value("runs", "version", 1)) >= RUN_VERSION:
		p.best_time = PackedFloat32Array(cfg.get_value("runs", "best_time", [0.0, 0.0, 0.0]))
	p.hero_best = cfg.get_value("heroes", "best", {})
	return p


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("runs", "version", RUN_VERSION)
	cfg.set_value("runs", "played", runs_played)
	cfg.set_value("runs", "wins", Array(wins))
	cfg.set_value("runs", "best_time", Array(best_time))
	cfg.set_value("heroes", "best", hero_best)
	cfg.save(path)


func hard_unlocked() -> bool:
	return wins[1] > 0 or wins[2] > 0


## The hardest difficulty won with a hero, or -1.
func hero_rank(hero_id: StringName) -> int:
	return int(hero_best.get(String(hero_id), -1))


## Records a finished run and saves. Returns what's new, for the end screen:
## {"best_time": bool, "hard_unlocked": bool}.
func record_run(victory: bool, difficulty: int, seconds: float, hero_ids: Array) -> Dictionary:
	var news := {"best_time": false, "hard_unlocked": false}
	runs_played += 1
	if victory:
		var was_unlocked := hard_unlocked()
		wins[difficulty] += 1
		if best_time[difficulty] <= 0.0 or seconds < best_time[difficulty]:
			news["best_time"] = true  # the first win is a best time too
			best_time[difficulty] = seconds
		news["hard_unlocked"] = hard_unlocked() and not was_unlocked
		for id: StringName in hero_ids:
			if difficulty > hero_rank(id):
				hero_best[String(id)] = difficulty
	save()
	return news
