## run_tests.gd
## Minimal dependency-free test runner for RC-Flight-Sim.
##
## Usage (headless, from the godot_project directory):
##   godot --headless --path . --script tests/run_tests.gd
##
## Exit code is 0 when all tests pass, 1 otherwise, so it can be wired into CI.
## Test suites are plain RefCounted classes exposing `test_*` methods that take
## a single argument: this runner (used as the assertion context).
extends SceneTree

var _passed: int = 0
var _failed: int = 0
var _current_suite: String = ""

func _initialize() -> void:
	print("== RC-Flight-Sim test run ==")
	# Test suites to execute. Add new TestXxx classes here.
	var suites: Array = [
		TestMathUtils,
		TestConfigParser,
		TestSimConsole,
		TestAgenticUtils,
	]
	for suite_class in suites:
		var suite: Object = suite_class.new()
		_current_suite = suite.get_script().resource_path.get_file()
		for method in suite.get_method_list():
			var mname: String = method.get("name", "")
			if mname.begins_with("test_"):
				suite.call(mname, self)
	print("\n== Results: %d passed, %d failed ==" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)

# ---------------------------------------------------------------------------
# Assertion API used by test suites
# ---------------------------------------------------------------------------
func assert_true(condition: bool, message: String) -> void:
	if condition:
		_pass(message)
	else:
		_fail(message)

func assert_approx(actual: float, expected: float, message: String, tol: float = 0.0001) -> void:
	if absf(actual - expected) <= tol:
		_pass(message)
	else:
		_fail("%s (expected %f, got %f)" % [message, expected, actual])

func _pass(message: String) -> void:
	_passed += 1
	print("  [PASS] %s :: %s" % [_current_suite, message])

func _fail(message: String) -> void:
	_failed += 1
	printerr("  [FAIL] %s :: %s" % [_current_suite, message])
