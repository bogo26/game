extends Node
## Sound effects and music. SFX are pre-rendered WAVs (tools/gen_audio.gd)
## played through a small voice pool; each sound has a minimum interval so a
## 300-enemy fight doesn't turn into noise. Cues players must not miss (a
## teammate down, low HP, the boss winding up...) have voices of their own, so
## a flood of hits can never cut them off. Music loops per screen on its own
## bus and crossfades between tracks. Volumes live in the Settings autoload.

const SFX_PATH := "res://assets/audio/sfx/%s.wav"
const MUSIC_PATH := "res://assets/audio/music/%s.wav"
const VOICES := 24
## The last PRIORITY_VOICES voices only play PRIORITY sounds.
const PRIORITY_VOICES := 6
const PRIORITY := {
	&"down": true, &"revive": true, &"ult": true, &"level_up": true, &"roar": true, &"clear": true,
	&"door": true, &"portal": true, &"heartbeat": true, &"ult_ready": true, &"help": true,
	&"boss_death": true, &"victory": true, &"defeat": true, &"wave": true, &"windup": true,
}
const MUSIC_DB := -6.0
const MUSIC_FADE := 0.6
const DEFAULT_INTERVAL := 0.03
## Minimum seconds between two plays of the same sound.
const INTERVALS := {
	&"hit": 0.035, &"kill": 0.05, &"pickup": 0.04, &"slash": 0.05, &"shoot_arrow": 0.05,
	&"shoot_rivet": 0.06, &"shoot_knife": 0.05, &"spit": 0.12, &"tesla": 0.1, &"fireball": 0.08,
	&"hurt": 0.1, &"explosion": 0.08, &"crit": 0.06, &"spikes": 0.1, &"fall": 0.08, &"break": 0.05,
	&"nest": 0.15, &"zap": 0.06, &"thunder": 0.15, &"freeze": 0.08, &"shatter": 0.08, &"plague": 0.2,
	&"fuse": 0.12, &"spawn": 0.12, &"windup": 0.2,
	&"heartbeat": 3.0, &"help": 3.0, &"denied": 0.15, &"ready": 0.1, &"revive_tick": 0.22, &"ult_ready": 0.3,
}
## Per-sound volume trims (dB).
const TRIMS := {&"hit": -6.0, &"kill": -5.0, &"pickup": -8.0, &"spit": -4.0, &"tesla": -6.0}

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _next_priority := 0
var _last_played: Dictionary = {}
var _cache: Dictionary = {}
## Two music players crossfade: _music is the current one.
var _music: AudioStreamPlayer
var _music_old: AudioStreamPlayer
var _music_name := &""
var _fade: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus(&"Music")
	_ensure_bus(&"SFX")
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_voices.append(p)
	_music = _new_music_player()
	_music_old = _new_music_player()


func _new_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = &"Music"
	p.volume_db = MUSIC_DB
	p.finished.connect(p.play)  # loop
	add_child(p)
	return p


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
	var p := pick_voice(sound)
	p.stream = stream
	p.volume_db = volume_db + float(TRIMS.get(sound, 0.0))
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


## The voice a sound plays on: key cues cycle through the reserved voices,
## everything else through the rest (round robin, the oldest is cut).
func pick_voice(sound: StringName) -> AudioStreamPlayer:
	if PRIORITY.has(sound):
		var p := _voices[VOICES - PRIORITY_VOICES + _next_priority]
		_next_priority = (_next_priority + 1) % PRIORITY_VOICES
		return p
	var q := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % (VOICES - PRIORITY_VOICES)
	return q


## Crossfades to `track` (no-op if it's already playing).
func play_music(track: StringName) -> void:
	if track == _music_name and _music.playing:
		return
	_music_name = track
	var stream := _stream(MUSIC_PATH % track)
	if stream == null:
		return
	var old := _music
	_music = _music_old
	_music_old = old
	_music.stream = stream
	_music.volume_db = -40.0 if old.playing else MUSIC_DB
	_music.play()
	if _fade:
		_fade.kill()
	_fade = create_tween().set_parallel()
	_fade.tween_property(_music, "volume_db", MUSIC_DB, MUSIC_FADE)
	if old.playing:
		_fade.tween_property(old, "volume_db", -40.0, MUSIC_FADE)
		_fade.chain().tween_callback(old.stop)


func stop_music() -> void:
	_music_name = &""
	if _fade:
		_fade.kill()
	_music.stop()
	_music_old.stop()


func music_track() -> StringName:
	return _music_name


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
