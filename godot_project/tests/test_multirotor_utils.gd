## test_multirotor_utils.gd
## Unit tests for MultirotorUtils. Pure-function tests, no scene required.
## Run via tests/run_tests.gd (see that file for the headless command).
class_name TestMultirotorUtils
extends RefCounted

## Each test method is named `test_*` and uses the supplied `t` test context
## (see run_tests.gd) to assert. Returns nothing.

func test_pid_proportional_only(t) -> void:
	# With only kp, output = kp * error. (Integral still tracks error*dt but
	# contributes nothing while ki = 0.)
	var r := MultirotorUtils.pid_step(2.0, 0.0, 0.0, 0.5, 0.0, 0.0, 0.1)
	t.assert_approx(r["output"], 1.0, "P-only output = kp*error")
	t.assert_approx(r["integral"], 0.2, "integral tracks error*dt")
	t.assert_approx(r["prev_error"], 2.0, "prev_error stored")

func test_pid_integral_accumulates(t) -> void:
	# Integral grows by error*dt each step and contributes ki*integral.
	var r := MultirotorUtils.pid_step(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.5)
	t.assert_approx(r["integral"], 0.5, "integral = error*dt")
	t.assert_approx(r["output"], 0.5, "output = ki*integral")

func test_pid_integral_clamped(t) -> void:
	# i_limit prevents wind-up.
	var r := MultirotorUtils.pid_step(100.0, 0.0, 0.0, 0.0, 1.0, 0.0, 1.0, 0.3)
	t.assert_approx(r["integral"], 0.3, "integral clamped to i_limit")

func test_pid_zero_delta_safe(t) -> void:
	# Zero dt must not divide by zero; integral/derivative are skipped so the
	# output is purely proportional and finite.
	var r := MultirotorUtils.pid_step(2.0, 1.0, 5.0, 0.5, 0.0, 1.0, 0.0)
	t.assert_approx(r["output"], 1.0, "zero dt -> only P term, no NaN")
	t.assert_approx(r["integral"], 5.0, "integral unchanged at zero dt")

func test_mix_hover_balanced(t) -> void:
	# Pure throttle with no attitude command -> all four motors equal.
	var m := MultirotorUtils.mix_quad_x(0.5, 0.0, 0.0, 0.0)
	for i in 4:
		t.assert_approx(m[i], 0.5, "balanced hover motor %d" % i)

func test_mix_roll_right(t) -> void:
	# Roll right: left motors faster than right motors.
	var m := MultirotorUtils.mix_quad_x(0.5, 0.2, 0.0, 0.0)
	t.assert_true(m[MultirotorUtils.MOTOR_FRONT_LEFT] > m[MultirotorUtils.MOTOR_FRONT_RIGHT],
		"roll right: front-left > front-right")
	t.assert_true(m[MultirotorUtils.MOTOR_REAR_LEFT] > m[MultirotorUtils.MOTOR_REAR_RIGHT],
		"roll right: rear-left > rear-right")

func test_mix_pitch_up(t) -> void:
	# Pitch up: rear motors faster than front motors.
	var m := MultirotorUtils.mix_quad_x(0.5, 0.0, 0.2, 0.0)
	t.assert_true(m[MultirotorUtils.MOTOR_REAR_LEFT] > m[MultirotorUtils.MOTOR_FRONT_LEFT],
		"pitch up: rear-left > front-left")
	t.assert_true(m[MultirotorUtils.MOTOR_REAR_RIGHT] > m[MultirotorUtils.MOTOR_FRONT_RIGHT],
		"pitch up: rear-right > front-right")

func test_mix_clamped(t) -> void:
	# Outputs never leave [0, 1] even with saturating commands.
	var m := MultirotorUtils.mix_quad_x(1.0, 1.0, 1.0, 1.0)
	for i in 4:
		t.assert_true(m[i] >= 0.0 and m[i] <= 1.0, "motor %d within [0,1]" % i)

func test_total_thrust(t) -> void:
	var m := MultirotorUtils.mix_quad_x(0.5, 0.0, 0.0, 0.0)
	# Four motors at 0.5 with 6 N each -> 0.5*4*6 = 12 N.
	t.assert_approx(MultirotorUtils.total_thrust(m, 6.0), 12.0, "total thrust sums motors")

func test_torque_roll_sign(t) -> void:
	# Roll-right command produces a positive roll torque.
	var m := MultirotorUtils.mix_quad_x(0.5, 0.2, 0.0, 0.0)
	var torque := MultirotorUtils.motors_to_body_torque(m, 0.12, 6.0, 0.02)
	t.assert_true(torque.x > 0.0, "roll-right -> positive roll torque")
	t.assert_approx(torque.y, 0.0, "no pitch torque from pure roll", 0.0001)

func test_torque_pitch_sign(t) -> void:
	var m := MultirotorUtils.mix_quad_x(0.5, 0.0, 0.2, 0.0)
	var torque := MultirotorUtils.motors_to_body_torque(m, 0.12, 6.0, 0.02)
	t.assert_true(torque.y > 0.0, "pitch-up -> positive pitch torque")
	t.assert_approx(torque.x, 0.0, "no roll torque from pure pitch", 0.0001)

func test_torque_short_array_safe(t) -> void:
	var torque := MultirotorUtils.motors_to_body_torque(PackedFloat32Array([0.5, 0.5]), 0.1, 6.0, 0.02)
	t.assert_true(torque == Vector3.ZERO, "short motor array -> zero torque")

func test_hover_throttle(t) -> void:
	# mass 0.6 kg, 4 motors @ 6 N each = 24 N max; weight = 5.886 N.
	var h := MultirotorUtils.hover_throttle(0.6, 6.0, 4, 9.81)
	t.assert_approx(h, 5.886 / 24.0, "hover throttle = weight / max thrust", 0.001)

func test_hover_throttle_underpowered(t) -> void:
	# Cannot lift off: clamps to 1.0 rather than exceeding full throttle.
	var h := MultirotorUtils.hover_throttle(10.0, 1.0, 4, 9.81)
	t.assert_approx(h, 1.0, "underpowered craft clamps hover throttle to 1.0")
