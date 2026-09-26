extends RefCounted
## Base class for tests. Test files are named tests/test_*.gd and extend this
## script by path; every method whose name starts with `test_` is run on a
## fresh instance.

var failures: PackedStringArray = []
var assert_count := 0
## Tests that deliberately trigger engine errors (push_error) declare how many.
var expected_errors := 0


func assert_true(condition: bool, message: String = "") -> void:
	assert_count += 1
	if not condition:
		failures.append("expected true: " + message)


func assert_false(condition: bool, message: String = "") -> void:
	assert_count += 1
	if condition:
		failures.append("expected false: " + message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	assert_count += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("expected %s, got %s. %s" % [var_to_str(expected), var_to_str(actual), message])


func assert_near(actual: float, expected: float, epsilon: float = 0.0001, message: String = "") -> void:
	assert_count += 1
	if absf(actual - expected) > epsilon:
		failures.append("expected %f ± %f, got %f. %s" % [expected, epsilon, actual, message])


func assert_vec_near(actual: Vector2, expected: Vector2, epsilon: float = 0.0001, message: String = "") -> void:
	assert_count += 1
	if actual.distance_to(expected) > epsilon:
		failures.append("expected %s, got %s. %s" % [expected, actual, message])


func fail(message: String) -> void:
	assert_count += 1
	failures.append(message)
