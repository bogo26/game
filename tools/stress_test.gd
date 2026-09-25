extends Node
## Horde stress test and performance gate.
##   ./tools/dev.sh stress [--seconds=20] [--warmup=4] [--enemies=300]
##       [--projectiles=400] [--fullscreen | --size=3840x2160] [--vsync=on]
## Four bot heroes fire constantly while the spawner keeps the horde at the
## cap. After a warm-up it measures frame times and exits with code 0 when the
## targets from docs/DESIGN.md are met, 1 otherwise.

const WORLD_SCENE := "res://src/world/world.tscn"
const TARGET_AVG_MS := 6.0
const TARGET_P99_MS := 8.3
const TARGET_SIM_MS := 3.0

var _seconds := 20.0
var _warmup := 4.0
var _enemies := 300
var _projectiles := 400
var _elapsed := 0.0
var _capturing := false
var _world: World
var _log_slow := false
var _last_usec := 0
var _slow_frames: PackedStringArray = []


func _ready() -> void:
	var fullscreen := false
	var size := Vector2i.ZERO
	var vsync := false
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--seconds="):
			_seconds = value.to_float()
		elif arg.begins_with("--warmup="):
			_warmup = value.to_float()
		elif arg.begins_with("--enemies="):
			_enemies = value.to_int()
		elif arg.begins_with("--projectiles="):
			_projectiles = value.to_int()
		elif arg == "--fullscreen":
			fullscreen = true
		elif arg.begins_with("--size="):
			size = Vector2i(value.get_slice("x", 0).to_int(), value.get_slice("x", 1).to_int())
		elif arg == "--vsync=on":
			vsync = true
		elif arg == "--log-slow":
			_log_slow = true
		elif arg.begins_with("--max-fps="):
			Engine.max_fps = value.to_int()

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	if fullscreen:
		get_window().mode = Window.MODE_FULLSCREEN
	elif size != Vector2i.ZERO:
		get_window().size = size
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

	_world = (load(WORLD_SCENE) as PackedScene).instantiate()
	_world.bot_count = 4
	_world.allow_drop_in = false
	add_child(_world)
	_world.bots.fire_rate = 250.0
	_world.bots.projectile_cap = _projectiles
	_world.spawner.spawn_rate = 250.0
	_world.spawner.alive_cap = _enemies
	for hero in _world.heroes:
		hero.god_mode = true
	PerfMonitor.visible = true
	print("stress test: %d enemies, %d projectiles, %.0fs after %.0fs warm-up" % [
		_enemies, _projectiles, _seconds, _warmup])


func _process(delta: float) -> void:
	_elapsed += delta
	var viewport_rid := get_viewport().get_viewport_rid()
	PerfMonitor.record(&"gpu", int(RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid) * 1000.0))
	PerfMonitor.record(&"draw_cpu", int(RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) * 1000.0))
	var now := Time.get_ticks_usec()
	if _capturing and _log_slow and _last_usec != 0:
		var frame_ms := float(now - _last_usec) / 1000.0
		if frame_ms > TARGET_P99_MS:
			_slow_frames.append("  t=%.2fs frame %.2f ms: sim %.2f draw_cpu %.2f process %.2f" % [
				_elapsed, frame_ms, PerfMonitor.last_ms(&"sim"), PerfMonitor.last_ms(&"draw_cpu"),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	_last_usec = now
	if not _capturing and _elapsed >= _warmup:
		_capturing = true
		PerfMonitor.begin_capture()
	elif _capturing and _elapsed >= _warmup + _seconds:
		_finish()


func _finish() -> void:
	set_process(false)
	var r := PerfMonitor.end_capture()
	var timers: Dictionary = r.get("timers", {})
	var counters: Dictionary = r.get("counters", {})
	var window := get_window()
	var sim_avg: float = timers.get(&"sim", {}).get("avg_ms", 0.0)
	print("")
	print("=== STRESS TEST ===")
	print("window %dx%d (%s), viewport %s, vsync %s, renderer %s" % [
		window.size.x, window.size.y, "fullscreen" if window.mode == Window.MODE_FULLSCREEN else "windowed",
		get_viewport().get_visible_rect().size,
		"on" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "off",
		RenderingServer.get_current_rendering_method()])
	print("device: %s / %s" % [RenderingServer.get_video_adapter_name(), OS.get_processor_name()])
	print("frames %d  avg %.2f ms (%.0f fps)  p50 %.2f  p99 %.2f  max %.2f" % [
		r.get("frames", 0), r.get("avg_ms", 0.0), r.get("avg_fps", 0.0),
		r.get("p50_ms", 0.0), r.get("p99_ms", 0.0), r.get("max_ms", 0.0)])
	for system: StringName in timers:
		print("  %-10s avg %.3f ms  max %.3f ms" % [system, timers[system]["avg_ms"], timers[system]["max_ms"]])
	for counter: StringName in counters:
		print("  %-10s avg %.0f" % [counter, counters[counter]])
	var ok := true
	if Engine.max_fps > 0:
		# Capped run: frames should arrive on time; allow 25% jitter per frame.
		var budget := 1000.0 / Engine.max_fps
		ok = _check("p99 frame", r.get("p99_ms", 999.0), budget * 1.25) and ok
	else:
		ok = _check("avg frame", r.get("avg_ms", 999.0), TARGET_AVG_MS) and ok
		ok = _check("p99 frame", r.get("p99_ms", 999.0), TARGET_P99_MS) and ok
	ok = _check("sim avg", sim_avg, TARGET_SIM_MS) and ok
	var enemies_avg: float = counters.get(&"enemies", 0.0)
	if enemies_avg < _enemies * 0.9:
		print("WARN: horde averaged %.0f of %d enemies" % [enemies_avg, _enemies])
	if _log_slow:
		print("slow frames (> %.1f ms): %d" % [TARGET_P99_MS, _slow_frames.size()])
		for line in _slow_frames.slice(0, 40):
			print(line)
	print("RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _check(label: String, value: float, limit: float) -> bool:
	var ok := value <= limit
	print("%-10s %.2f ms (limit %.2f) %s" % [label, value, limit, "ok" if ok else "OVER"])
	return ok
