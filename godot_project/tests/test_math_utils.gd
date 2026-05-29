## test_math_utils.gd
## Unit tests for MathUtils. Pure-function tests, no scene required.
## Run via tests/run_tests.gd (see that file for the headless command).
class_name TestMathUtils
extends RefCounted

## Each test method is named `test_*` and uses the supplied `t` test context
## (see run_tests.gd) to assert. Returns nothing.

func test_expo_endpoints(t) -> void:
	# Endpoints and centre are fixed points for any expo value.
	t.assert_approx(MathUtils.apply_expo(0.0, 0.5), 0.0, "expo(0) == 0")
	t.assert_approx(MathUtils.apply_expo(1.0, 0.5), 1.0, "expo(1) == 1")
	t.assert_approx(MathUtils.apply_expo(-1.0, 0.5), -1.0, "expo(-1) == -1")

func test_expo_softens_centre(t) -> void:
	# With expo, mid-stick output should be below linear (softer).
	var linear := 0.5
	var curved := MathUtils.apply_expo(0.5, 0.5)
	t.assert_true(curved < linear, "expo softens mid-stick")

func test_expo_linear_when_zero(t) -> void:
	t.assert_approx(MathUtils.apply_expo(0.4, 0.0), 0.4, "expo 0 == linear")

func test_deadzone_zeroes_centre(t) -> void:
	t.assert_approx(MathUtils.apply_deadzone(0.05, 0.1), 0.0, "inside deadzone -> 0")
	t.assert_approx(MathUtils.apply_deadzone(0.1, 0.1), 0.0, "edge deadzone -> 0")

func test_deadzone_rescales(t) -> void:
	# Just past the deadzone should map to ~0; full stick stays at 1.
	t.assert_approx(MathUtils.apply_deadzone(1.0, 0.1), 1.0, "full stick stays 1")
	t.assert_approx(MathUtils.apply_deadzone(-1.0, 0.1), -1.0, "full neg stays -1")

func test_remap_range(t) -> void:
	t.assert_approx(MathUtils.remap_range(5.0, 0.0, 10.0, 0.0, 100.0), 50.0, "remap midpoint")
	t.assert_approx(MathUtils.remap_range(0.0, 0.0, 0.0, 1.0, 2.0), 1.0, "remap degenerate range")

func test_isa_density_decreases_with_altitude(t) -> void:
	var sea := MathUtils.isa_density(0.0, 15.0, 1013.25)
	var high := MathUtils.isa_density(3000.0, 15.0, 1013.25)
	t.assert_approx(sea, 1.225, "ISA sea-level density ~1.225", 0.02)
	t.assert_true(high < sea, "density decreases with altitude")

func test_exp_smooth_converges(t) -> void:
	var v := 0.0
	for i in range(200):
		v = MathUtils.exp_smooth(v, 10.0, 5.0, 0.016)
	t.assert_approx(v, 10.0, "exp_smooth converges to target", 0.01)
