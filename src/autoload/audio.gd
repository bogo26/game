extends Node
## Sound effects and music. SFX are pre-rendered WAVs (tools/gen_audio.gd)
## played through a small voice pool; each sound has a minimum interval so a
## 300-enemy fight doesn't turn into noise. Music loops per screen on its own
## bus. Volumes are saved to user://settings.cfg.

const SFX_PATH := "res://assets/audio/sfx/%s.wav"
const MUSIC_PATH := "res://assets/audio/music/%s.wav"
const SETTINGS_PATH := "user://settings.cfg"
const VOICES := 24
const DEFAULT_INTERVAL := 0.03
## Minimum seconds between two plays of the same sound.
const INTERVALS := {
	&"hit": 0.035, &"kill": 0.05, &"pickup": 0.04, &"slash": 0.05, &"shoot_arrow": 0.05,
	&"shoot_rivet": 0.06, &"shoot_knife": 0.05, &"spit": 0.12, &"tesla": 0.1, &"fireball": 0.08,
	&"hurt": 0.1, &"explosion": 0.08, &"crit": 0.06, &"spikes": 0.1, &"fall": 0.08, &"break": 0.05,
	&"nest": 0.15, &"zap": 0.06, &"thunder": 0.15, &"freeze": 0.08, &"shatter": 0.08, &"plague": 0.2,
}
## Per-sound volume trims (dB).
const TRIMS := {&"hit": -6.0, &"kill": -5.0, &"pickup": -8.0, &"spit": -4.0, &"tesla": -6.0}

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _last_played: Dictionary = {}
var _cache: Dictionary = {}
var _music: AudioStreamPlayer
var _music_name := &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(&"Music")
	_ensure_bus(&"SFX")
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_voices.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	_music.volume_db = -6.0
	_music.finished.connect(_music.play)  # loop
	add_child(_music)
	_load_settings()


func play(sound: StringName, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if sound == &"":
		return
	var now := Time.get_ticks_msec() * 0.001
	if now - float(_last_played.get(sound, -100.0)) < float(INTERVALS.get(sound, DEFAULT_INTERVAL)):
		return
	var stream := _stream(SFX_PATH % sound)
	if stream == null:
		return
	_last_played[sound] = now
	var p := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	p.stream = stream
	p.volume_db = volume_db + float(TRIMS.get(sound, 0.0))
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


func play_music(track: StringName) -> void:
	if track == _music_name and _music.playing:
		return
	_music_name = track
	var stream := _stream(MUSIC_PATH % track)
	if stream == null:
		return
	_music.stream = stream
	_music.play()


func stop_music() -> void:
	_music_name = &""
	_music.stop()


func set_bus_volume(bus: StringName, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_linear(index, clampf(linear, 0.0, 1.0))
		_save_settings()


func get_bus_volume(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_volume_linear(index) if index >= 0 else 1.0


func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


func _ensure_bus(bus: StringName) -> void:
	if AudioServer.get_bus_index(bus) == -1:
		AudioServer.add_bus()
		var index := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, &"Master")


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for bus: StringName in [&"Master", &"Music", &"SFX"]:
		var index := AudioServer.get_bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_volume_linear(index, float(cfg.get_value("audio", String(bus), 1.0)))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for bus: StringName in [&"Master", &"Music", &"SFX"]:
		cfg.set_value("audio", String(bus), get_bus_volume(bus))
	cfg.save(SETTINGS_PATH)
