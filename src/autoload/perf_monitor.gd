extends CanvasLayer
## Frame-time statistics + F3 debug overlay.
## Systems report their CPU cost with `record(&"name", usec)` and counts with
## `set_counter(&"name", value)`. The stress test uses begin/end_capture()
## to get average and p99 frame times over a run.

const WINDOW := 240
const REFRESH_INTERVAL := 0.25
const EMA_ALPHA := 0.1

var _frame_ms := PackedFloat32Array()
var _head := 0
var _filled := 0
var _last_usec := 0
var _timers: Dictionary = {}    # StringName -> float (ms, smoothed)
var _last: Dictionary = {}      # StringName -> float (ms, most recent)
var _counters: Dictionary = {}  # StringName -> int
var _refresh_left := 0.0

var _capturing := false
var _cap_frames := PackedFloat32Array()
var _cap_timer_sums: Dictionary = {}  # StringName -> float (ms)
var _cap_timer_max: Dictionary = {}   # StringName -> float (ms)
var _cap_counter_sums: Dictionary = {}  # StringName -> float

var _panel: ColorRect
var _label: Label


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_frame_ms.resize(WINDOW)
	_panel = ColorRect.new()
	_panel.color = Color(0, 0, 0, 0.55)
	_panel.position = Vector2(2, 2)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	_label = Label.new()
	_label.position = Vector2(5, 3)
	var settings := LabelSettings.new()
	settings.font_size = 8
	settings.line_spacing = 0
	_label.label_settings = settings
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	visible = OS.get_cmdline_user_args().has("--perf")


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec != 0:
		var ms := float(now - _last_usec) / 1000.0
		_frame_ms[_head] = ms
		_head = (_head + 1) % WINDOW
		_filled = mini(_filled + 1, WINDOW)
		if _capturing:
			_cap_frames.append(ms)
			for counter: StringName in _counters:
				_cap_counter_sums[counter] = _cap_counter_sums.get(counter, 0.0) + float(_counters[counter])
	_last_usec = now
	if visible:
		_refresh_left -= delta
		if _refresh_left <= 0.0:
			_refresh_left = REFRESH_INTERVAL
			_refresh_text()


## Report how long a system took this frame, in microseconds.
func record(system: StringName, usec: int) -> void:
	var ms := float(usec) / 1000.0
	_last[system] = ms
	_timers[system] = lerpf(_timers.get(system, ms), ms, EMA_ALPHA)
	if _capturing:
		_cap_timer_sums[system] = _cap_timer_sums.get(system, 0.0) + ms
		_cap_timer_max[system] = maxf(_cap_timer_max.get(system, 0.0), ms)


## Most recent value reported for `system`, in ms.
func last_ms(system: StringName) -> float:
	return _last.get(system, 0.0)


func set_counter(counter: StringName, value: int) -> void:
	_counters[counter] = value


func get_counter(counter: StringName) -> int:
	return _counters.get(counter, 0)


func begin_capture() -> void:
	_capturing = true
	_cap_frames = PackedFloat32Array()
	_cap_timer_sums.clear()
	_cap_timer_max.clear()
	_cap_counter_sums.clear()


## Stops capturing and returns frame statistics (all times in ms).
func end_capture() -> Dictionary:
	_capturing = false
	var frames := _cap_frames.duplicate()
	var n := frames.size()
	var result := {"frames": n}
	if n == 0:
		return result
	var total := 0.0
	for f in frames:
		total += f
	frames.sort()
	result["avg_ms"] = total / n
	result["p50_ms"] = frames[int(n * 0.50)]
	result["p99_ms"] = frames[mini(int(n * 0.99), n - 1)]
	result["max_ms"] = frames[n - 1]
	result["avg_fps"] = 1000.0 / (total / n)
	var timers := {}
	for system: StringName in _cap_timer_sums:
		timers[system] = {"avg_ms": _cap_timer_sums[system] / n, "max_ms": _cap_timer_max[system]}
	result["timers"] = timers
	var counters := {}
	for counter: StringName in _cap_counter_sums:
		counters[counter] = _cap_counter_sums[counter] / n
	result["counters"] = counters
	return result


func frame_stats() -> Vector3:
	## x = avg ms, y = p99 ms, z = max ms over the rolling window.
	if _filled == 0:
		return Vector3.ZERO
	var window := _frame_ms.slice(0, _filled)
	var total := 0.0
	for f in window:
		total += f
	window.sort()
	return Vector3(total / _filled, window[mini(int(_filled * 0.99), _filled - 1)], window[_filled - 1])


func _refresh_text() -> void:
	var s := frame_stats()
	var lines := PackedStringArray()
	lines.append("FPS %d   frame %.2f ms  p99 %.2f  max %.2f" % [
		Engine.get_frames_per_second(), s.x, s.y, s.z])
	lines.append("draw calls %d   nodes %d" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var timer_parts := PackedStringArray()
	for system: StringName in _timers:
		timer_parts.append("%s %.2f" % [system, _timers[system]])
	if not timer_parts.is_empty():
		lines.append("ms: " + "  ".join(timer_parts))
	var counter_parts := PackedStringArray()
	for counter: StringName in _counters:
		counter_parts.append("%s %d" % [counter, _counters[counter]])
	if not counter_parts.is_empty():
		lines.append("  ".join(counter_parts))
	_label.text = "\n".join(lines)
	_panel.size = _label.get_minimum_size() + Vector2(6, 2)
