extends Control
## Run results: victory or defeat, stats, and Play Again / Main Menu.

const CHARACTER_SELECT := "res://src/ui/character_select.tscn"
const MAIN_MENU := "res://src/ui/main_menu.tscn"


func _ready() -> void:
	get_tree().paused = false
	var victory := GameState.last_run_victory
	%Title.text = "VICTORY!" if victory else "DEFEAT"
	%Title.add_theme_color_override("font_color", Color("ffe07a") if victory else Color("e8504a"))
	var total := RunConfig.load_default().levels.size()
	var minutes := int(GameState.run_time) / 60
	var seconds := int(GameState.run_time) % 60
	var lines := PackedStringArray([
		"Levels cleared   %d / %d" % [GameState.levels_cleared, total],
		"Enemies slain    %d" % GameState.run_kills,
		"Team level       %d" % GameState.team_level,
		"Time             %d:%02d" % [minutes, seconds],
		"",
	])
	for s in GameState.slots:
		if s.hero_id != &"":
			lines.append("P%d  %s   %d upgrades" % [s.slot + 1, String(s.hero_id).capitalize(), s.upgrades.size()])
	%Stats.text = "\n".join(lines)
	%AgainButton.pressed.connect(func() -> void: get_tree().change_scene_to_file(CHARACTER_SELECT))
	%MenuButton.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU))
	%AgainButton.grab_focus.call_deferred()
