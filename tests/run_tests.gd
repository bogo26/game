extends SceneTree
## Headless test runner.
##   godot --headless --path . -s res://tests/run_tests.gd [-- --filter=<text>]
## 1. Compiles every script and loads every scene/resource under res://src,
##    res://tools and res://assets (catches parse errors in untested code).
## 2. Runs every `test_*` method in res://tests/test_*.gd on a fresh instance.
## Any engine or script error logged while a test runs fails that test.
## Exits with code 0 when everything passes, 1 otherwise.

const LOAD_ROOTS: Array[String] = ["res://src", "res://tools", "res://assets"]
const LOAD_EXTENSIONS: Array[String] = ["gd", "tscn", "tres", "gdshader"]


class ErrorCounter extends Logger:
	var errors := 0
	var messages: PackedStringArray = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors += 1
		var text := rationale if rationale != "" else code
		messages.append("%s (%s:%d in %s)" % [text, file, line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var _logger := ErrorCounter.new()
var _passed := 0
var _failed := 0


func _initialize() -> void:
	OS.add_logger(_logger)
	var filter := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			filter = arg.substr("--filter=".length())

	if filter == "":
		_check_everything_loads()

	var test_files := _find_files("res://tests", ["gd"]).filter(
		func(p: String) -> bool: return p.get_file().begins_with("test_"))
	test_files.sort()
	for path: String in test_files:
		_run_file(path, filter)

	print("")
	print("%d passed, %d failed" % [_passed, _failed])
	OS.remove_logger(_logger)
	quit(0 if _failed == 0 else 1)


func _check_everything_loads() -> void:
	var files: Array[String] = []
	for root in LOAD_ROOTS:
		files.append_array(_find_files(root, LOAD_EXTENSIONS))
	files.sort()
	var before := _logger.errors
	var bad: PackedStringArray = []
	for path in files:
		var errors_before := _logger.errors
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if res == null or _logger.errors > errors_before:
			bad.append(path)
		elif res is GDScript and not (res as GDScript).can_instantiate() and not _is_abstract(res):
			bad.append(path + " (cannot instantiate)")
	if bad.is_empty() and _logger.errors == before:
		_passed += 1
		print("PASS  load check (%d files)" % files.size())
	else:
		_failed += 1
		print("FAIL  load check")
		for b in bad:
			print("        ", b)
		for i in range(before, _logger.errors):
			print("        ", _logger.messages[i])


func _is_abstract(script: GDScript) -> bool:
	# Scripts that only hold static helpers / are meant to be extended are fine.
	return script.is_abstract() if script.has_method("is_abstract") else false


func _run_file(path: String, filter: String) -> void:
	var script := load(path) as GDScript
	if script == null or not script.can_instantiate():
		_failed += 1
		print("FAIL  %s (could not load)" % path)
		return
	for method in script.get_script_method_list():
		var method_name: String = method["name"]
		if not method_name.begins_with("test_"):
			continue
		var full_name := "%s:%s" % [path.get_file().get_basename(), method_name]
		if filter != "" and not full_name.contains(filter):
			continue
		var instance: Object = script.new()
		var errors_before := _logger.errors
		var start := Time.get_ticks_usec()
		instance.call(method_name)
		var elapsed_ms := float(Time.get_ticks_usec() - start) / 1000.0
		var failures: PackedStringArray = instance.get("failures")
		for i in range(errors_before, _logger.errors):
			failures.append("error: " + _logger.messages[i])
		if failures.is_empty() and int(instance.get("assert_count")) == 0:
			failures.append("no assertions ran")
		if failures.is_empty():
			_passed += 1
			print("PASS  %s (%.1f ms)" % [full_name, elapsed_ms])
		else:
			_failed += 1
			print("FAIL  %s" % full_name)
			for f in failures:
				print("        ", f)


func _find_files(root: String, extensions: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.include_hidden = false
	for sub in dir.get_directories():
		out.append_array(_find_files(root.path_join(sub), extensions))
	for file in dir.get_files():
		if file.get_extension() in extensions:
			out.append(root.path_join(file))
	return out
