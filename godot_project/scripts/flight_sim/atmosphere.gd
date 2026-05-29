## atmosphere.gd
## Autoload singleton for atmospheric conditions (wind, density, temperature).
## Reads from scenario files or global settings and exposes values to the FDM.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal atmosphere_changed()

# ---------------------------------------------------------------------------
# Public properties – read by FDMInterface and JSBSimFDM
# ---------------------------------------------------------------------------
## Wind vector in m/s, world space (X=East, Y=Up, Z=South)
var wind_velocity: Vector3 = Vector3.ZERO

## Wind gusts: maximum extra speed added per gust cycle
var wind_gust_max: float = 0.0

## Wind turbulence intensity 0-1
var wind_turbulence: float = 0.0

## Air temperature in Celsius at sea level
var temperature_sea_level: float = 15.0

## Air pressure in hPa at sea level
var pressure_sea_level: float = 1013.25

## Air density at sea level (kg/m³) – computed from T and P
var air_density: float = 1.225

# ---------------------------------------------------------------------------
# Wind layers (altitude-dependent wind, Part 3B)
# ---------------------------------------------------------------------------
## Optional list of wind layers ordered by altitude. Each entry is a
## Dictionary: { "altitude_m": float, "direction_deg": float (FROM),
## "speed_ms": float, "gust_max_ms": float, "turbulence": float }.
## When non-empty, get_wind_at_altitude() interpolates between layers; when
## empty it falls back to the single-layer shear model below.
var wind_layers: Array = []

# ---------------------------------------------------------------------------
# Time-of-day
# ---------------------------------------------------------------------------
## Current time in hours (0-24)
var time_of_day: float = 12.0

## Speed of time passage (1 = real time, 0 = frozen)
var time_scale: float = 1.0

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------
var _gust_timer: float = 0.0
var _gust_period: float = 5.0  # seconds between gust pulses
var _current_gust: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_compute_air_density()

func _process(delta: float) -> void:
	_update_gusts(delta)
	_update_time(delta)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Load atmosphere settings from a scenario Dictionary
func load_from_scenario(scenario: Dictionary) -> void:
	var wind_dir_deg: float = scenario.get("wind_direction_deg", 0.0)
	var wind_speed: float   = scenario.get("wind_speed_ms", 0.0)
	var wind_dir_rad := deg_to_rad(wind_dir_deg)
	# Wind direction is "FROM" direction (meteorological convention)
	wind_velocity = Vector3(-sin(wind_dir_rad) * wind_speed, 0.0, -cos(wind_dir_rad) * wind_speed)
	wind_gust_max   = scenario.get("wind_gust_max_ms", 0.0)
	wind_turbulence = scenario.get("wind_turbulence", 0.0)
	temperature_sea_level = scenario.get("temperature_c", 15.0)
	pressure_sea_level    = scenario.get("pressure_hpa", 1013.25)
	time_of_day  = scenario.get("start_time_h", 12.0)
	time_scale   = scenario.get("time_scale", 1.0)
	# Optional altitude-dependent wind layers.
	wind_layers = scenario.get("wind_layers", [])
	_compute_air_density()
	atmosphere_changed.emit()

## Load a standalone atmospheric profile JSON file (Part 3B). The file may
## contain any subset of the scenario atmosphere keys plus "wind_layers".
## Returns true on success. Custom sceneries can ship their own profile.
func load_profile(path: String) -> bool:
	var err_out: Array = [""]
	var data := ConfigLoader.load_json_file(path, err_out)
	if data.is_empty():
		push_error("[Atmosphere] Failed to load profile '%s': %s" % [path, err_out[0]])
		return false
	load_from_scenario(data)
	return true

## Set the surface (sea-level) wind vector directly. Used by the
## WeatherController so live weather changes drive the physics wind model.
func set_surface_wind(v: Vector3) -> void:
	wind_velocity = v

## Get effective wind at a given altitude (m above sea level)
func get_wind_at_altitude(altitude_m: float) -> Vector3:
	var base_wind: Vector3
	if wind_layers.size() >= 1:
		base_wind = _interpolate_wind_layers(altitude_m)
	else:
		# Simple linear wind shear model (single global wind vector).
		var shear_factor := clampf(altitude_m / 300.0, 0.0, 1.5)
		base_wind = wind_velocity * shear_factor
	var gust_contribution := wind_velocity.normalized() * _current_gust if wind_velocity.length() > 0.01 else Vector3.ZERO
	return base_wind + gust_contribution

## Air density (kg/m³) at the given altitude using the ISA troposphere model.
func get_density_at_altitude(altitude_m: float) -> float:
	return MathUtils.isa_density(altitude_m, temperature_sea_level, pressure_sea_level)

## Air temperature (°C) at altitude using the standard 6.5 °C/km lapse rate.
func get_temperature_at_altitude(altitude_m: float) -> float:
	return temperature_sea_level - 0.0065 * maxf(altitude_m, 0.0)

## Air pressure (hPa) at altitude using the barometric formula.
func get_pressure_at_altitude(altitude_m: float) -> float:
	const R := 287.05
	const G := 9.80665
	const LAPSE := 0.0065
	var t0 := temperature_sea_level + 273.15
	var t := maxf(t0 - LAPSE * maxf(altitude_m, 0.0), 0.1)
	return pressure_sea_level * pow(t / t0, G / (R * LAPSE))

## Return sun angle in degrees (0 = midnight, 90 = noon)
func get_sun_angle_degrees() -> float:
	return (time_of_day / 24.0) * 360.0 - 90.0

# ---------------------------------------------------------------------------
# Wind layer interpolation
# ---------------------------------------------------------------------------
## Linearly interpolate the wind vector between the two bracketing layers for
## [param altitude_m]. Layers are assumed sorted by "altitude_m" ascending.
func _interpolate_wind_layers(altitude_m: float) -> Vector3:
	var lower: Dictionary = wind_layers[0]
	var upper: Dictionary = wind_layers[wind_layers.size() - 1]
	# Below the lowest / above the highest: clamp to the extreme layer.
	if altitude_m <= float(lower.get("altitude_m", 0.0)):
		return _layer_to_vector(lower)
	if altitude_m >= float(upper.get("altitude_m", 0.0)):
		return _layer_to_vector(upper)
	for i in range(wind_layers.size() - 1):
		var a: Dictionary = wind_layers[i]
		var b: Dictionary = wind_layers[i + 1]
		var a_alt := float(a.get("altitude_m", 0.0))
		var b_alt := float(b.get("altitude_m", 0.0))
		if altitude_m >= a_alt and altitude_m <= b_alt:
			var t := MathUtils.remap_range(altitude_m, a_alt, b_alt, 0.0, 1.0)
			return _layer_to_vector(a).lerp(_layer_to_vector(b), t)
	return _layer_to_vector(upper)

func _layer_to_vector(layer: Dictionary) -> Vector3:
	var dir_rad := deg_to_rad(float(layer.get("direction_deg", 0.0)))
	var speed := float(layer.get("speed_ms", 0.0))
	# Meteorological "FROM" convention (matches load_from_scenario).
	return Vector3(-sin(dir_rad) * speed, 0.0, -cos(dir_rad) * speed)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
func _compute_air_density() -> void:
	# Standard atmosphere approximation: ρ = P / (R * T)
	var R_specific := 287.05  # J/(kg·K)
	var T_kelvin := temperature_sea_level + 273.15
	var P_pascals := pressure_sea_level * 100.0  # hPa → Pa
	air_density = P_pascals / (R_specific * T_kelvin)

func _update_gusts(delta: float) -> void:
	if wind_gust_max <= 0.0:
		_current_gust = 0.0
		return
	_gust_timer += delta
	if _gust_timer >= _gust_period:
		_gust_timer = 0.0
		_gust_period = randf_range(3.0, 8.0)
		_current_gust = randf_range(0.0, wind_gust_max)
	else:
		# Smooth gust decay
		_current_gust = move_toward(_current_gust, 0.0, delta * (wind_gust_max / _gust_period))

func _update_time(delta: float) -> void:
	time_of_day += (delta / 3600.0) * time_scale
	if time_of_day >= 24.0:
		time_of_day -= 24.0
