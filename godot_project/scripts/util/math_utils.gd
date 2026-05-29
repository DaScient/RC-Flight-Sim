## math_utils.gd
## Stateless math helpers shared by the flight model, input pipeline and UI.
##
## Every function here is *pure* (no side effects, no global state) so they can
## be exercised by the unit tests in `tests/` and reused deterministically from
## `_physics_process`. Use this class via its static methods, e.g.
##   var v := MathUtils.apply_expo(raw, 0.3)
class_name MathUtils
extends RefCounted

## Apply an exponential response curve to a normalised control input.
## [param v]: raw input in [-1, 1].
## [param expo]: curve strength in [0, 1] (0 = linear, 1 = maximum softening
## around centre). The sign of [param v] is preserved and the endpoints
## (-1, 0, 1) are fixed points for any expo value.
static func apply_expo(v: float, expo: float) -> float:
	var e := clampf(expo, 0.0, 1.0)
	var x := clampf(v, -1.0, 1.0)
	return x * (absf(x) * e + (1.0 - e))

## Apply a symmetric deadzone around centre, then rescale the remaining range
## back to [-1, 1] so there is no discontinuity at the deadzone edge.
static func apply_deadzone(v: float, deadzone: float) -> float:
	var dz := clampf(deadzone, 0.0, 0.99)
	var x := clampf(v, -1.0, 1.0)
	if absf(x) <= dz:
		return 0.0
	var sign_v := signf(x)
	return sign_v * (absf(x) - dz) / (1.0 - dz)

## Remap a value from one range to another (no clamping).
static func remap_range(v: float, in_min: float, in_max: float, out_min: float, out_max: float) -> float:
	if is_equal_approx(in_max, in_min):
		return out_min
	var t := (v - in_min) / (in_max - in_min)
	return out_min + t * (out_max - out_min)

## Frame-rate independent exponential smoothing toward [param target].
## [param rate]: higher = faster convergence (1/seconds). Deterministic given delta.
static func exp_smooth(current: float, target: float, rate: float, delta: float) -> float:
	var alpha := 1.0 - exp(-maxf(rate, 0.0) * maxf(delta, 0.0))
	return current + (target - current) * alpha

## Convert an RC "rates" multiplier and expo into a final scaled command.
static func apply_rates_expo(v: float, rate: float, expo: float) -> float:
	return apply_expo(v, expo) * rate

## ISA air density (kg/m^3) at [param altitude_m] using the troposphere model,
## given sea-level temperature (C) and pressure (hPa).
static func isa_density(altitude_m: float, temp_c_sea: float, pressure_hpa_sea: float) -> float:
	const R := 287.05      # J/(kg*K)
	const G := 9.80665     # m/s^2
	const LAPSE := 0.0065  # K/m
	var t0 := temp_c_sea + 273.15
	var p0 := pressure_hpa_sea * 100.0
	var alt := maxf(altitude_m, 0.0)
	var t := t0 - LAPSE * alt
	if t <= 0.0:
		t = 0.1
	# Barometric formula for the troposphere.
	var p := p0 * pow(t / t0, G / (R * LAPSE))
	return p / (R * t)

## Quaternion shortest-path spherical interpolation helper that is safe for
## near-identical inputs (returns [param a] when they are effectively equal).
static func safe_slerp(a: Quaternion, b: Quaternion, t: float) -> Quaternion:
	if a.is_equal_approx(b):
		return a
	return a.slerp(b, clampf(t, 0.0, 1.0))
