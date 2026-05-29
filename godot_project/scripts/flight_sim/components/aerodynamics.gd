## aerodynamics.gd
## Aerodynamics monitoring component. It does not integrate forces (the FDM
## does that); instead it watches the FDM state and emits high-level events
## that drive HUD warnings and audio cues: stall, overspeed and gear/ground.
class_name AerodynamicsComponent
extends AircraftComponent

## Emitted when the stall condition starts/stops (true = stalling).
signal stall_changed(active: bool)
## Emitted when airspeed crosses the never-exceed speed (true = overspeed).
signal overspeed_changed(active: bool)

var _stall_aoa_deg: float = 15.0
var _vne_ms: float = 30.0          # never-exceed speed
var _stall_active: bool = false
var _overspeed_active: bool = false

func setup(owner_aircraft: Node) -> void:
	super.setup(owner_aircraft)
	var cfg := _config()
	_stall_aoa_deg = ConfigLoader.get_number(cfg, "stall_aoa_deg", 15.0, 1.0, 89.0)
	# Derive Vne from configured max speed with a small margin if not given.
	var max_speed := ConfigLoader.get_number(cfg, "max_speed_ms", 30.0, 0.1, 1000.0)
	_vne_ms = ConfigLoader.get_number(cfg, "vne_ms", max_speed * 1.1, 0.1, 2000.0)

func physics_tick(_delta: float, state: Dictionary) -> void:
	var aoa: float = absf(float(state.get("aoa_deg", 0.0)))
	var airspeed: float = float(state.get("airspeed_ms", 0.0))
	var on_ground: bool = bool(state.get("on_ground", false))

	# Stall only meaningful in the air and with some airflow.
	var stalling := (not on_ground) and airspeed > 0.5 and aoa >= _stall_aoa_deg
	if stalling != _stall_active:
		_stall_active = stalling
		stall_changed.emit(stalling)

	var over := airspeed > _vne_ms
	if over != _overspeed_active:
		_overspeed_active = over
		overspeed_changed.emit(over)

func is_stalling() -> bool:
	return _stall_active

func is_overspeed() -> bool:
	return _overspeed_active
