extends Node
## Player settings, saved to user://settings.cfg: volumes, fullscreen and the
## comfort / accessibility options other systems read from here (screen
## shake, damage numbers, reduced flashing, rumble, player colours, gamepad
## aim assist, tips). Change them with set_value() so they're applied, saved
## and announced.

signal changed(key: StringName)

const PATH := "user://settings.cfg"

enum Shake { OFF, LOW, FULL }
enum Numbers { ALL, CRITS, OFF }
enum AimAssist { OFF, LOW, HIGH }
enum Palette { DEFAULT, COLORBLIND }

## Screen shake strength per setting.
const SHAKE_SCALE: Array[float] = [0.0, 0.5, 1.0]
## Aim assist: half-angle of the cone (degrees) in which it locks on.
const AIM_ASSIST_DEGREES: Array[float] = [0.0, 10.0, 20.0]
const AIM_ASSIST_RANGE := 160.0

var master_volume := 1.0
var music_volume := 1.0
var sfx_volume := 1.0
var fullscreen := false
var screen_shake: Shake = Shake.FULL
var damage_numbers: Numbers = Numbers.ALL
var reduce_flashing := false
var rumble := true
var palette: Palette = Palette.DEFAULT
var aim_assist: AimAssist = AimAssist.OFF
var tips := true
## Tips already shown (onboarding): id -> true.
var seen_tips: Dictionary = {}

## Where settings are saved (tests point this elsewhere).
var path := PATH

## [config section, key] for every saved setting.
const KEYS := {
	&"master_volume": ["audio", "Master"], &"music_volume": ["audio", "Music"], &"sfx_volume": ["audio", "SFX"],
	&"fullscreen": ["video", "fullscreen"], &"screen_shake": ["comfort", "screen_shake"],
	&"damage_numbers": ["comfort", "damage_numbers"], &"reduce_flashing": ["comfort", "reduce_flashing"],
	&"rumble": ["comfort", "rumble"], &"palette": ["comfort", "palette"], &"aim_assist": ["comfort", "aim_assist"],
	&"tips": ["comfort", "tips"], &"seen_tips": ["onboarding", "seen_tips"],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_all()


## Back to the defaults (tests start from these), without saving.
func reset() -> void:
	var fresh: Node = (get_script() as GDScript).new()
	for key: StringName in KEYS:
		set(key, fresh.get(key))
	fresh.free()
	apply_all()


func set_value(key: StringName, value: Variant) -> void:
	set(key, value)
	_apply(key)
	save_settings()
	changed.emit(key)


func shake_scale() -> float:
	return SHAKE_SCALE[screen_shake]


func aim_assist_angle() -> float:
	return deg_to_rad(AIM_ASSIST_DEGREES[aim_assist])


## Multiplier for flashes (hit flashes, full-screen bursts) under "reduce flashing".
func flash_scale() -> float:
	return 0.35 if reduce_flashing else 1.0


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for key: StringName in KEYS:
		var where: Array = KEYS[key]
		if cfg.has_section_key(where[0], where[1]):
			set(key, cfg.get_value(where[0], where[1]))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for key: StringName in KEYS:
		var where: Array = KEYS[key]
		cfg.set_value(where[0], where[1], get(key))
	cfg.save(path)


func apply_all() -> void:
	for key: StringName in KEYS:
		_apply(key)


func _apply(key: StringName) -> void:
	match key:
		&"master_volume":
			_bus_volume(&"Master", master_volume)
		&"music_volume":
			_bus_volume(&"Music", music_volume)
		&"sfx_volume":
			_bus_volume(&"SFX", sfx_volume)
		&"fullscreen":
			if DisplayServer.get_name() == "headless":
				return
			var window := get_window()
			if fullscreen and window.mode != Window.MODE_FULLSCREEN:
				window.mode = Window.MODE_FULLSCREEN
			elif not fullscreen and window.mode == Window.MODE_FULLSCREEN:
				window.mode = Window.MODE_WINDOWED


static func _bus_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_linear(index, clampf(linear, 0.0, 1.0))
