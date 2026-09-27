class_name EndScreen
extends Control
## Run results: victory or defeat (GAME OVER and the wave reached, after
## Endless Waves), the team's numbers, any records set, a table of every
## player's numbers with awards, and
##   Play again     - same team, heroes and mode, straight into a new game
##   Change heroes  - character select with everyone still joined
##   Main menu

const GAME := "res://src/main/game.tscn"
const CHARACTER_SELECT := "res://src/ui/character_select.tscn"
const MAIN_MENU := "res://src/ui/main_menu.tscn"
## Buttons ignore input this long, so a player still mashing A / Space from
## the fight doesn't skip the results.
const INPUT_GRACE := 0.6
const ROW_HEIGHT := 11.0
## Table columns: [header, right edge x] (the name and awards are left-aligned).
const COLUMNS: Array = [["Kills", 132.0], ["Damage", 180.0], ["Taken", 222.0], ["Downs", 260.0],
	["Revives", 305.0], ["Best hit", 352.0]]
const AWARDS_X := 366.0
const AWARD_COLOR := Color("ffe07a")

var _grace := INPUT_GRACE
var _players: Array = []   # GameState slots that played
var _awards: Dictionary = {}


func _ready() -> void:
	get_tree().paused = false
	Audio.play_music(&"menu")
	var victory := GameState.last_run_victory
	var waves := GameState.mode == GameState.Mode.WAVES
	%Title.text = "GAME OVER" if waves else ("VICTORY!" if victory else "DEFEAT")
	%Title.add_theme_color_override("font_color", Color("ffe07a") if victory else Color("e8504a"))
	%Stats.text = stats_line()
	var news := GameState.last_run_news
	var records := PackedStringArray()
	if news.get("best_time", false):
		records.append("NEW BEST TIME!")
	if news.get("best_wave", false):
		records.append("NEW BEST WAVE!")
	if news.get("hard_unlocked", false):
		records.append("HARD UNLOCKED!")
	%Records.text = "   ".join(records)
	%Records.visible = not records.is_empty()
	for s in GameState.slots:
		if s.hero_id != &"":
			_players.append(s)
	_awards = awards(_players)
	%Table.custom_minimum_size.y = (_players.size() + 1) * ROW_HEIGHT + 4.0
	%Table.draw.connect(_draw_table)
	%AgainButton.pressed.connect(_play_again)
	%ChangeButton.pressed.connect(func() -> void:
		GameState.keep_team = true
		get_tree().change_scene_to_file(CHARACTER_SELECT))
	%MenuButton.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU))
	for button: Button in _buttons():
		button.disabled = true
	UiSounds.attach(self)


func _buttons() -> Array[Button]:
	return [%AgainButton, %ChangeButton, %MenuButton]


## The team's numbers: the difficulty, how far it got (levels, or the wave in
## Endless Waves), enemies, team level, time and Second Winds.
static func stats_line() -> String:
	var difficulty := GameState.DIFFICULTY_NAMES[GameState.difficulty]
	var parts := PackedStringArray()
	if GameState.mode == GameState.Mode.WAVES:
		parts.append_array(["Endless Waves", difficulty, "Wave %d" % GameState.wave])
	else:
		parts.append_array([difficulty,
			"Levels %d/%d" % [GameState.levels_cleared, RunConfig.load_default().levels.size()]])
	var minutes := int(GameState.run_time) / 60
	var seconds := int(GameState.run_time) % 60
	parts.append_array([
		"Enemies %d" % GameState.run_kills,
		"Team level %d" % GameState.team_level,
		"Time %d:%02d" % [minutes, seconds],
	])
	if GameState.lives_used > 0:
		parts.append("Second Winds %d" % GameState.lives_used)
	return "   ".join(parts)


func _process(delta: float) -> void:
	if _grace <= 0.0:
		return
	_grace -= delta
	if _grace <= 0.0:
		for button in _buttons():
			button.disabled = false
		UiSounds.focus_quietly(%AgainButton)


## Same team, same heroes, same difficulty: a new run right away.
func _play_again() -> void:
	GameState.reset_run()
	GameState.level_index = 0
	get_tree().change_scene_to_file(GAME)


## Awards per player slot: Slayer (most kills), Medic (most revives), Tank
## (most damage taken), Sharpshooter (biggest hit) - only with teammates to
## beat - and Untouchable (never downed).
static func awards(players: Array) -> Dictionary:
	var out: Dictionary = {}
	for s in players:
		out[s.slot] = PackedStringArray()
	if players.size() >= 2:
		for award: Array in [["Slayer", "kills"], ["Medic", "revives"], ["Tank", "damage_taken"],
				["Sharpshooter", "biggest_hit"]]:
			var best: Variant = null
			for s in players:
				var v := float(s.get(award[1]))
				if v > 0.0 and (best == null or v > float(best.get(award[1]))):
					best = s
			if best != null:
				_give(out, best.slot, award[0])
	for s in players:
		if s.downs == 0:
			_give(out, s.slot, "Untouchable")
	return out


## Packed arrays are values: take it out, add, and put it back.
static func _give(awards: Dictionary, slot: int, award: String) -> void:
	var list: PackedStringArray = awards[slot]
	list.append(award)
	awards[slot] = list


static func short_number(v: float) -> String:
	if v >= 1_000_000.0:
		return "%.1fM" % (v / 1_000_000.0)
	if v >= 10_000.0:
		return "%dk" % int(v / 1000.0)
	if v >= 1000.0:
		return "%.1fk" % (v / 1000.0)
	return str(int(round(v)))


func _draw_table() -> void:
	var table: Control = %Table
	var font := table.get_theme_default_font()
	var grey := Color(0.55, 0.55, 0.62)
	var y := 8.0
	for column: Array in COLUMNS:
		_right(table, font, column[0], column[1], y, grey)
	table.draw_string(font, Vector2(AWARDS_X, y), "Awards", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, grey)
	for s in _players:
		y += ROW_HEIGHT
		var color := GameState.player_color(s.slot)
		table.draw_string(font, Vector2(4, y), "P%d  %s" % [s.slot + 1, String(s.hero_id).capitalize()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)
		var values := [str(s.kills), short_number(s.damage_dealt), short_number(s.damage_taken), str(s.downs),
			str(s.revives), short_number(s.biggest_hit)]
		for k in COLUMNS.size():
			_right(table, font, values[k], COLUMNS[k][1], y, Color(0.9, 0.9, 0.95))
		var awarded: PackedStringArray = _awards.get(s.slot, PackedStringArray())
		table.draw_string(font, Vector2(AWARDS_X, y), ", ".join(awarded), HORIZONTAL_ALIGNMENT_LEFT,
			table.size.x - AWARDS_X, 8, AWARD_COLOR)


static func _right(table: Control, font: Font, text: String, right: float, y: float, color: Color) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	table.draw_string(font, Vector2(right - width, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, color)
