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
	_compute_air_density()
	atmosphere_changed.emit()

## Get effective wind at a given altitude (m above sea level)
func get_wind_at_altitude(altitude_m: float) -> Vector3:
	# Simple linear wind shear model
	var shear_factor := clampf(altitude_m / 300.0, 0.0, 1.5)
	var base_wind := wind_velocity * shear_factor
	var gust_contribution := wind_velocity.normalized() * _current_gust if wind_velocity.length() > 0.01 else Vector3.ZERO
	return base_wind + gust_contribution

## Return sun angle in degrees (0 = midnight, 90 = noon)
func get_sun_angle_degrees() -> float:
	return (time_of_day / 24.0) * 360.0 - 90.0

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
