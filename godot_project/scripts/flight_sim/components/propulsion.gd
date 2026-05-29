## propulsion.gd
## Propulsion component: drives the visible propeller/rotor animation from the
## FDM engine RPM and exposes a normalised power level for other systems
## (sound, dust effects). It does not compute thrust itself - that is the FDM's
## job - it only visualises and reports propulsion state.
class_name PropulsionComponent
extends AircraftComponent

## Optional propeller mesh to spin. Assigned by AircraftNode from its export.
@export var propeller_mesh: Node3D = null

## Axis around which the propeller spins (local space). Default: Z (nose axis).
@export var spin_axis: Vector3 = Vector3(0, 0, 1)

var _max_rpm: float = 10000.0
var _current_rpm: float = 0.0

## Emitted when the engine transitions between running/stopped so audio and
## particle systems can react.
signal engine_state_changed(running: bool)

var _was_running: bool = false

func setup(owner_aircraft: Node) -> void:
	super.setup(owner_aircraft)
	_max_rpm = ConfigLoader.get_number(_config(), "max_rpm", 10000.0, 1.0, 1.0e7)

func physics_tick(delta: float, state: Dictionary) -> void:
	_current_rpm = float(state.get("engine_rpm", 0.0))

	# Spin the propeller. RPM -> radians/sec = rpm/60 * 2*PI.
	if propeller_mesh != null:
		var rad_per_sec := _current_rpm / 60.0 * TAU
		propeller_mesh.rotate_object_local(spin_axis.normalized(), rad_per_sec * delta)

	var running := _current_rpm > _max_rpm * 0.02
	if running != _was_running:
		_was_running = running
		engine_state_changed.emit(running)

## Normalised power level in [0, 1] derived from RPM. Used by sound and dust.
func get_power_level() -> float:
	if _max_rpm <= 0.0:
		return 0.0
	return clampf(_current_rpm / _max_rpm, 0.0, 1.0)

func get_rpm() -> float:
	return _current_rpm
