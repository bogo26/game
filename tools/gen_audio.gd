extends SceneTree
## Renders the game's placeholder audio with a tiny synthesizer (square /
## saw / triangle / sine / pitched noise, slides, arpeggios, envelopes,
## one-pole lowpass) and a 16th-note sequencer for music loops.
##   godot --headless --path . -s res://tools/gen_audio.gd
## Writes assets/audio/sfx/*.wav and assets/audio/music/*.wav (mono 16-bit).
## Deterministic, license-free; swap for real audio in a later polish pass.

const RATE := 22050

## f0/f1: start/end frequency (exponential slide), dur: seconds, attack: s,
## decay: envelope power (higher = snappier), noise: 0..1 pitched-noise mix,
## arp: semitone steps cycled every arp_step s, vib: [depth, rate], lp: 0..1
## lowpass amount (1 = none), duty: square pulse width.
const SFX := {
	"shoot_arrow": {"wave": "square", "f0": 1400.0, "f1": 700.0, "dur": 0.07, "decay": 2.0, "vol": 0.22, "duty": 0.25},
	"shoot_magic": {"wave": "saw", "f0": 500.0, "f1": 1100.0, "dur": 0.13, "decay": 1.5, "vol": 0.2, "vib": [0.08, 30.0], "lp": 0.4},
	"shoot_orb": {"wave": "sine", "f0": 520.0, "f1": 820.0, "dur": 0.14, "decay": 1.2, "vol": 0.28},
	"shoot_rivet": {"wave": "square", "f0": 1000.0, "f1": 600.0, "dur": 0.045, "decay": 3.0, "vol": 0.16, "noise": 0.4},
	"shoot_knife": {"wave": "noise", "f0": 5000.0, "f1": 2500.0, "dur": 0.08, "decay": 2.0, "vol": 0.2, "lp": 0.5},
	"shoot_soul": {"wave": "triangle", "f0": 300.0, "f1": 700.0, "dur": 0.16, "decay": 1.2, "vol": 0.3, "vib": [0.12, 18.0]},
	"slash": {"wave": "noise", "f0": 6000.0, "f1": 1500.0, "dur": 0.11, "decay": 1.6, "vol": 0.22, "lp": 0.35},
	"hit": {"wave": "noise", "f0": 3000.0, "f1": 800.0, "dur": 0.045, "decay": 3.0, "vol": 0.2, "lp": 0.6},
	"crit": {"wave": "square", "f0": 1760.0, "f1": 2640.0, "dur": 0.09, "decay": 1.6, "vol": 0.17, "duty": 0.25, "noise": 0.15},
	"kill": {"wave": "square", "f0": 420.0, "f1": 120.0, "dur": 0.09, "decay": 2.0, "vol": 0.16, "duty": 0.5, "noise": 0.25},
	"explosion": {"wave": "noise", "f0": 1400.0, "f1": 90.0, "dur": 0.55, "decay": 1.6, "vol": 0.45, "lp": 0.25},
	"slam": {"wave": "sine", "f0": 140.0, "f1": 38.0, "dur": 0.32, "decay": 1.5, "vol": 0.55, "noise": 0.35, "lp": 0.3},
	"dash": {"wave": "noise", "f0": 800.0, "f1": 5000.0, "dur": 0.14, "decay": 1.3, "vol": 0.16, "lp": 0.3},
	"blink": {"wave": "sine", "f0": 400.0, "f1": 1800.0, "dur": 0.18, "decay": 1.0, "vol": 0.22, "vib": [0.05, 40.0]},
	"pickup": {"wave": "square", "f0": 1300.0, "f1": 1900.0, "dur": 0.05, "decay": 1.5, "vol": 0.12, "duty": 0.25},
	"heal": {"wave": "sine", "f0": 660.0, "f1": 660.0, "dur": 0.3, "decay": 1.0, "vol": 0.25, "arp": [0, 4, 7, 12], "arp_step": 0.07},
	"hurt": {"wave": "square", "f0": 240.0, "f1": 90.0, "dur": 0.16, "decay": 1.5, "vol": 0.28, "noise": 0.3, "duty": 0.5},
	"down": {"wave": "saw", "f0": 330.0, "f1": 70.0, "dur": 0.6, "decay": 1.2, "vol": 0.3, "lp": 0.3},
	"revive": {"wave": "triangle", "f0": 440.0, "f1": 440.0, "dur": 0.45, "decay": 0.8, "vol": 0.3, "arp": [0, 4, 7, 12, 16], "arp_step": 0.08},
	"level_up": {"wave": "square", "f0": 523.0, "f1": 523.0, "dur": 0.55, "decay": 0.7, "vol": 0.22, "duty": 0.25, "arp": [0, 4, 7, 12, 7, 12], "arp_step": 0.08},
	"ult": {"wave": "saw", "f0": 110.0, "f1": 220.0, "dur": 0.7, "decay": 1.0, "vol": 0.3, "attack": 0.08, "arp": [0, 7, 12], "arp_step": 0.05, "lp": 0.25},
	"buff": {"wave": "saw", "f0": 180.0, "f1": 360.0, "dur": 0.35, "decay": 1.2, "vol": 0.26, "vib": [0.1, 12.0], "lp": 0.35},
	"summon": {"wave": "triangle", "f0": 150.0, "f1": 420.0, "dur": 0.3, "decay": 1.1, "vol": 0.3, "noise": 0.2, "vib": [0.1, 9.0]},
	"cast": {"wave": "sine", "f0": 300.0, "f1": 900.0, "dur": 0.25, "decay": 1.0, "vol": 0.25, "vib": [0.06, 25.0]},
	"door": {"wave": "noise", "f0": 600.0, "f1": 80.0, "dur": 0.28, "decay": 1.8, "vol": 0.4, "lp": 0.2},
	"clear": {"wave": "square", "f0": 392.0, "f1": 392.0, "dur": 0.7, "decay": 0.6, "vol": 0.2, "duty": 0.25, "arp": [0, 4, 7, 12, 16, 19], "arp_step": 0.09},
	"portal": {"wave": "sine", "f0": 200.0, "f1": 1200.0, "dur": 0.7, "decay": 0.8, "vol": 0.25, "vib": [0.08, 6.0]},
	"roar": {"wave": "saw", "f0": 120.0, "f1": 55.0, "dur": 1.0, "decay": 1.1, "vol": 0.4, "noise": 0.4, "vib": [0.1, 7.0], "lp": 0.25},
	"fireball": {"wave": "noise", "f0": 900.0, "f1": 300.0, "dur": 0.22, "decay": 1.4, "vol": 0.22, "lp": 0.3},
	"spit": {"wave": "square", "f0": 320.0, "f1": 180.0, "dur": 0.09, "decay": 2.0, "vol": 0.14, "noise": 0.5},
	"tesla": {"wave": "noise", "f0": 8000.0, "f1": 3000.0, "dur": 0.1, "decay": 2.0, "vol": 0.14, "lp": 0.8},
	"ui_move": {"wave": "square", "f0": 780.0, "f1": 780.0, "dur": 0.03, "decay": 2.0, "vol": 0.12, "duty": 0.25},
	"ui_confirm": {"wave": "square", "f0": 880.0, "f1": 1320.0, "dur": 0.09, "decay": 1.5, "vol": 0.15, "duty": 0.25},
	"spikes": {"wave": "square", "f0": 2300.0, "f1": 1500.0, "dur": 0.11, "decay": 2.4, "vol": 0.14, "duty": 0.125, "noise": 0.6},
	"fall": {"wave": "sine", "f0": 900.0, "f1": 160.0, "dur": 0.42, "decay": 0.9, "vol": 0.16},
	"break": {"wave": "noise", "f0": 5200.0, "f1": 1600.0, "dur": 0.17, "decay": 2.2, "vol": 0.26, "lp": 0.6},
	"chest": {"wave": "square", "f0": 784.0, "f1": 784.0, "dur": 0.62, "decay": 0.8, "vol": 0.18, "duty": 0.25, "arp": [0, 4, 7, 12, 16, 19, 24], "arp_step": 0.06},
	"shrine": {"wave": "triangle", "f0": 330.0, "f1": 330.0, "dur": 0.95, "decay": 0.7, "vol": 0.3, "arp": [0, 7, 12, 19, 24], "arp_step": 0.12, "vib": [0.05, 5.0]},
	"nest": {"wave": "saw", "f0": 170.0, "f1": 90.0, "dur": 0.18, "decay": 1.8, "vol": 0.2, "noise": 0.4, "lp": 0.3},
	"nest_break": {"wave": "noise", "f0": 1300.0, "f1": 110.0, "dur": 0.5, "decay": 1.4, "vol": 0.42, "lp": 0.3},
	"zap": {"wave": "square", "f0": 1900.0, "f1": 800.0, "dur": 0.09, "decay": 2.2, "vol": 0.11, "duty": 0.125, "noise": 0.7},
	"thunder": {"wave": "noise", "f0": 2600.0, "f1": 55.0, "dur": 0.75, "decay": 1.2, "vol": 0.45, "lp": 0.3},
	"freeze": {"wave": "sine", "f0": 2300.0, "f1": 3300.0, "dur": 0.16, "decay": 1.6, "vol": 0.14, "noise": 0.3},
	"shatter": {"wave": "noise", "f0": 7500.0, "f1": 3000.0, "dur": 0.22, "decay": 1.8, "vol": 0.26, "lp": 0.7},
	"plague": {"wave": "saw", "f0": 150.0, "f1": 105.0, "dur": 0.4, "decay": 1.2, "vol": 0.16, "noise": 0.5, "lp": 0.25, "vib": [0.08, 8.0]},
	# Warnings: an exploder's fuse hiss, the boss winding up, a spawn portal opening.
	"fuse": {"wave": "noise", "f0": 5200.0, "f1": 7400.0, "dur": 0.6, "decay": 0.5, "vol": 0.13, "lp": 0.55, "vib": [0.25, 13.0]},
	"windup": {"wave": "saw", "f0": 170.0, "f1": 520.0, "dur": 0.48, "decay": 0.45, "vol": 0.24, "attack": 0.08, "lp": 0.3, "vib": [0.06, 17.0]},
	"spawn": {"wave": "sine", "f0": 560.0, "f1": 150.0, "dur": 0.34, "decay": 0.9, "vol": 0.13, "noise": 0.35, "lp": 0.35, "vib": [0.1, 11.0]},
}

## Chords are MIDI note triads per bar; bpm; drums: "full", "light" or "none".
const MUSIC := {
	"dungeon": {"bpm": 104.0, "bars": 8, "drums": "light",
		"chords": [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]], "arp_wave": "square", "bass_wave": "triangle"},
	"boss": {"bpm": 140.0, "bars": 8, "drums": "full",
		"chords": [[62, 65, 69], [58, 62, 65], [55, 58, 62], [57, 61, 64]], "arp_wave": "saw", "bass_wave": "square"},
	"menu": {"bpm": 76.0, "bars": 8, "drums": "none",
		"chords": [[57, 60, 64], [52, 55, 59], [53, 57, 60], [55, 59, 62]], "arp_wave": "triangle", "bass_wave": "sine"},
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/audio/sfx"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/audio/music"))
	for sfx_name: String in SFX:
		_save(_render_sfx(SFX[sfx_name], sfx_name.hash()), "res://assets/audio/sfx/%s.wav" % sfx_name)
	for track: String in MUSIC:
		_save(_render_music(MUSIC[track]), "res://assets/audio/music/%s.wav" % track)
	print("audio generated: %d sfx, %d music" % [SFX.size(), MUSIC.size()])
	quit()


# --- synth ---------------------------------------------------------------------------------

static func _osc(wave: String, phase: float, duty: float) -> float:
	match wave:
		"square":
			return 1.0 if phase < duty else -1.0
		"saw":
			return 2.0 * phase - 1.0
		"triangle":
			return 4.0 * absf(phase - 0.5) - 1.0
		"sine":
			return sin(TAU * phase)
	return 0.0


func _render_sfx(p: Dictionary, seed_value: int) -> PackedFloat32Array:
	var dur: float = p["dur"]
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var wave: String = p["wave"]
	var f0: float = p["f0"]
	var f1: float = p["f1"]
	var vol: float = p.get("vol", 0.3)
	var attack: float = p.get("attack", 0.004)
	var decay: float = p.get("decay", 1.0)
	var duty: float = p.get("duty", 0.5)
	var noise_mix: float = 1.0 if wave == "noise" else p.get("noise", 0.0)
	var arp: Array = p.get("arp", [])
	var arp_step: float = p.get("arp_step", 0.08)
	var vib: Array = p.get("vib", [0.0, 0.0])
	var lp_amount: float = p.get("lp", 1.0)
	var phase := 0.0
	var noise_phase := 0.0
	var noise_value := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var f := f0 * pow(f1 / f0, k)
		if not arp.is_empty():
			f *= pow(2.0, float(arp[int(t / arp_step) % arp.size()]) / 12.0)
		if vib[0] > 0.0:
			f *= 1.0 + float(vib[0]) * sin(TAU * float(vib[1]) * t)
		phase = fmod(phase + f / RATE, 1.0)
		var s := _osc(wave, phase, duty)
		if noise_mix > 0.0:
			noise_phase += f / RATE
			if noise_phase >= 1.0:
				noise_phase -= floorf(noise_phase)
				noise_value = rng.randf_range(-1.0, 1.0)
			s = lerpf(s, noise_value, noise_mix)
		var env := minf(1.0, t / attack) * pow(1.0 - k, decay)
		s *= env * vol
		lp += (s - lp) * lp_amount
		out[i] = lp
	return out


func _render_music(m: Dictionary) -> PackedFloat32Array:
	var step_len := 60.0 / float(m["bpm"]) / 4.0
	var steps: int = int(m["bars"]) * 16
	var n := int(steps * step_len * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var chords: Array = m["chords"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for step in steps:
		var start := int(step * step_len * RATE)
		var bar := step / 16
		var chord: Array = chords[bar % chords.size()]
		var beat_step := step % 16
		# Bass on eighth notes, root with an octave jump on the off-beat.
		if step % 2 == 0:
			var root: int = int(chord[0]) - 24 + (12 if beat_step % 4 == 2 else 0)
			_note(out, start, step_len * 2.0 * 0.95, _midi(root), m["bass_wave"], 0.16, 0.8, 0.5, rng)
		# Arpeggio on sixteenths, up the chord and back.
		var order := [0, 1, 2, 1]
		var arp_note: int = int(chord[order[step % 4]]) + (12 if bar % 2 == 1 and step % 8 >= 4 else 0)
		_note(out, start, step_len * 0.9, _midi(arp_note), m["arp_wave"], 0.07, 2.0, 0.25, rng)
		# Drums.
		match m["drums"]:
			"full":
				if beat_step % 4 == 0:
					_kick(out, start)
				if beat_step == 4 or beat_step == 12:
					_noise_hit(out, start, 0.12, 0.2, 0.35, rng)
				_noise_hit(out, start, 0.03, 0.05 if step % 2 == 0 else 0.03, 1.0, rng)
			"light":
				if beat_step == 0 or beat_step == 8 or beat_step == 10:
					_kick(out, start)
				if beat_step == 4 or beat_step == 12:
					_noise_hit(out, start, 0.1, 0.14, 0.35, rng)
				if step % 2 == 0:
					_noise_hit(out, start, 0.025, 0.035, 1.0, rng)
	for i in n:
		out[i] = clampf(out[i], -1.0, 1.0)
	return out


static func _midi(note: int) -> float:
	return 440.0 * pow(2.0, float(note - 69) / 12.0)


func _note(out: PackedFloat32Array, start: int, dur: float, freq: float, wave: String, vol: float,
		decay: float, duty: float, _rng: RandomNumberGenerator) -> void:
	var n := mini(int(dur * RATE), out.size() - start)
	var phase := 0.0
	for i in n:
		var k := float(i) / float(n)
		phase = fmod(phase + freq / RATE, 1.0)
		var env := minf(1.0, float(i) / 60.0) * pow(1.0 - k, decay)
		out[start + i] += _osc(wave, phase, duty) * vol * env


func _kick(out: PackedFloat32Array, start: int) -> void:
	var n := mini(int(0.16 * RATE), out.size() - start)
	var phase := 0.0
	for i in n:
		var k := float(i) / float(n)
		var f := 140.0 * pow(40.0 / 140.0, k)
		phase = fmod(phase + f / RATE, 1.0)
		out[start + i] += sin(TAU * phase) * 0.45 * pow(1.0 - k, 1.5)


func _noise_hit(out: PackedFloat32Array, start: int, dur: float, vol: float, lp_amount: float,
		rng: RandomNumberGenerator) -> void:
	var n := mini(int(dur * RATE), out.size() - start)
	var lp := 0.0
	for i in n:
		var k := float(i) / float(n)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * lp_amount
		out[start + i] += lp * vol * pow(1.0 - k, 2.0)


func _save(samples: PackedFloat32Array, path: String) -> void:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	var err := stream.save_to_wav(path)
	if err != OK:
		push_error("failed to save %s: %s" % [path, error_string(err)])
