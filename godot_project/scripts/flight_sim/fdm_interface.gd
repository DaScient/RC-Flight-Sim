## fdm_interface.gd
## Common Flight Dynamics Model interface for all aircraft.
## When the JSBSim GDExtension is available it delegates to JSBSimFDM;
## otherwise it falls back to a built-in kinematic model suitable for
## simple testing without native library compilation.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal state_updated(state: Dictionary)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
## Control surface names
const SURFACE_AILERON  := "aileron"
const SURFACE_ELEVATOR := "elevator"
const SURFACE_RUDDER   := "rudder"
const SURFACE_THROTTLE := "throttle"
const SURFACE_FLAP     := "flap"

# ---------------------------------------------------------------------------
# FDM backend selection
# ---------------------------------------------------------------------------
enum FDMBackend { KINEMATIC, JSBSIM }

var backend: FDMBackend = FDMBackend.KINEMATIC
var _jsbsim_node: Node = null

# ---------------------------------------------------------------------------
# Current flight state (published each physics frame)
# ---------------------------------------------------------------------------
var state: Dictionary = {
	"position":          Vector3.ZERO,   # m, world-space
	"velocity":          Vector3.ZERO,   # m/s, world-space
	"angular_velocity":  Vector3.ZERO,   # rad/s, body-frame
	"orientation":       Quaternion.IDENTITY,
	"euler_deg":         Vector3.ZERO,   # roll, pitch, yaw (degrees)
	"airspeed_ms":       0.0,
	"altitude_m":        0.0,
	"aoa_deg":           0.0,            # Angle of Attack
	"engine_rpm":        0.0,
	"throttle_pos":      0.0,
	"on_ground":         true,
}

# ---------------------------------------------------------------------------
# Control surface commands [-1, 1] (throttle [0, 1])
# ---------------------------------------------------------------------------
var _controls: Dictionary = {
	SURFACE_AILERON:  0.0,
	SURFACE_ELEVATOR: 0.0,
	SURFACE_RUDDER:   0.0,
	SURFACE_THROTTLE: 0.0,
	SURFACE_FLAP:     0.0,
}

# ---------------------------------------------------------------------------
# Aircraft configuration (loaded from JSON)
# ---------------------------------------------------------------------------
var aircraft_config: Dictionary = {}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	# Try to locate a JSBSimFDM node that may have been added by AircraftNode
	_jsbsim_node = get_node_or_null("JSBSimFDM")
	if _jsbsim_node != null and _jsbsim_node.has_method("load_aircraft"):
		backend = FDMBackend.JSBSIM
		print("[FDMInterface] Using JSBSim backend.")
	else:
		backend = FDMBackend.KINEMATIC
		print("[FDMInterface] Using kinematic fallback backend.")

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Set a control surface value. Value range: [-1, 1] (throttle: [0, 1]).
func set_control_surface(surface: String, value: float) -> void:
	_controls[surface] = value
	if backend == FDMBackend.JSBSIM and _jsbsim_node != null:
		var jsbsim_prop := _surface_to_jsbsim_prop(surface)
		if jsbsim_prop != "":
			_jsbsim_node.set_property(jsbsim_prop, value)

## Return a copy of the current flight state dictionary.
func get_state() -> Dictionary:
	return state.duplicate()

## Load aircraft definition and initialize FDM.
func load_aircraft(config_path: String) -> void:
	var f := FileAccess.open(config_path, FileAccess.READ)
	if f == null:
		push_error("[FDMInterface] Cannot open aircraft config: %s" % config_path)
		return
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	f.close()
	if err != OK:
		push_error("[FDMInterface] JSON parse error in %s: %s" % [config_path, json.get_error_message()])
		return
	aircraft_config = json.get_data()
	if backend == FDMBackend.JSBSIM and _jsbsim_node != null:
		var xml_path: String = aircraft_config.get("jsbsim_xml", "")
		if xml_path != "":
			_jsbsim_node.load_aircraft(xml_path)

## Step the FDM by delta seconds (called from AircraftNode._physics_process).
func update_fdm(delta: float, transform: Transform3D) -> void:
	if backend == FDMBackend.JSBSIM and _jsbsim_node != null:
		_jsbsim_node.update(delta)
		_read_jsbsim_state()
	else:
		_step_kinematic(delta, transform)
	state_updated.emit(state)

# ---------------------------------------------------------------------------
# JSBSim state reader
# ---------------------------------------------------------------------------
func _read_jsbsim_state() -> void:
	if _jsbsim_node == null:
		return
	state["airspeed_ms"]  = _jsbsim_node.get_property("velocities/vt-fps") * 0.3048
	state["altitude_m"]   = _jsbsim_node.get_property("position/h-sl-ft") * 0.3048
	state["aoa_deg"]      = rad_to_deg(_jsbsim_node.get_property("aero/alpha-rad"))
	state["engine_rpm"]   = _jsbsim_node.get_property("propulsion/engine/rpm")
	state["throttle_pos"] = _controls[SURFACE_THROTTLE]

	# Extract body-frame forces → world position/velocity update is handled by AircraftNode
	var vx := _jsbsim_node.get_property("velocities/v-east-fps")  * 0.3048
	var vy := _jsbsim_node.get_property("velocities/v-up-fps")    * 0.3048
	var vz := _jsbsim_node.get_property("velocities/v-north-fps") * 0.3048
	state["velocity"] = Vector3(vx, vy, -vz)  # Godot Y-up, Z-forward

	var roll_deg  := rad_to_deg(_jsbsim_node.get_property("attitude/roll-rad"))
	var pitch_deg := rad_to_deg(_jsbsim_node.get_property("attitude/pitch-rad"))
	var yaw_deg   := rad_to_deg(_jsbsim_node.get_property("attitude/psi-rad"))
	state["euler_deg"] = Vector3(roll_deg, pitch_deg, yaw_deg)
	state["orientation"] = Quaternion.from_euler(Vector3(
		deg_to_rad(roll_deg), deg_to_rad(yaw_deg), deg_to_rad(pitch_deg)
	))

# ---------------------------------------------------------------------------
# Built-in kinematic fallback model
# ---------------------------------------------------------------------------
## Simple 6-DOF kinematic model used when JSBSim is not available.
## Based on trainer-like parameters baked from aircraft_config.
var _kin_velocity: Vector3     = Vector3.ZERO
var _kin_ang_vel:  Vector3     = Vector3.ZERO
var _kin_rotation: Vector3     = Vector3.ZERO  # Euler angles degrees: roll, pitch, yaw
var _kin_on_ground: bool       = true

func _step_kinematic(delta: float, transform: Transform3D) -> void:
	var cfg := aircraft_config

	var mass: float    = cfg.get("mass_kg", 1.5)
	var wingspan: float = cfg.get("wingspan_m", 1.2)
	var cl_alpha: float = cfg.get("cl_alpha", 5.0)       # lift curve slope (1/rad)
	var cd0: float      = cfg.get("cd0", 0.03)            # zero-lift drag
	var max_rpm: float  = cfg.get("max_rpm", 10000.0)
	var thrust_n: float = cfg.get("max_thrust_n", 15.0)

	var throttle: float  = _controls[SURFACE_THROTTLE]
	var aileron: float   = _controls[SURFACE_AILERON]
	var elevator: float  = _controls[SURFACE_ELEVATOR]
	var rudder: float    = _controls[SURFACE_RUDDER]

	# Effective airspeed
	var fwd   := -transform.basis.z
	var wind  := Atmosphere.get_wind_at_altitude(transform.origin.y)
	var vel_relative := _kin_velocity - wind
	var airspeed := vel_relative.length()

	# Angle of attack (angle between forward vector and velocity vector in body xz-plane)
	var aoa_rad := 0.0
	if airspeed > 0.5:
		var local_vel := transform.basis.inverse() * vel_relative
		aoa_rad = atan2(-local_vel.y, -local_vel.z)
	state["aoa_deg"] = rad_to_deg(aoa_rad)

	# Dynamic pressure
	var q := 0.5 * Atmosphere.air_density * airspeed * airspeed
	var wing_area: float = cfg.get("wing_area_m2", 0.25)

	# Aerodynamic forces in body frame
	var cl := cl_alpha * aoa_rad + cfg.get("cl0", 0.3)
	cl = clampf(cl, -1.5, 1.5)
	var cd := cd0 + (cl * cl) / (PI * cfg.get("aspect_ratio", 5.8) * cfg.get("oswald", 0.8))
	var lift_n := q * wing_area * cl
	var drag_n := q * wing_area * cd

	# Lift acts perpendicular to velocity in the lift plane; drag opposes velocity
	var lift_dir := transform.basis.y  # approximation: vertical in body frame
	var drag_dir := -fwd if airspeed < 0.1 else -vel_relative.normalized()

	var aero_force := lift_dir * lift_n + drag_dir * drag_n

	# Engine thrust
	var thrust_force := fwd * thrust_n * throttle
	state["engine_rpm"]   = max_rpm * throttle
	state["throttle_pos"] = throttle

	# Total force & acceleration
	var gravity := Vector3(0.0, -9.81 * mass, 0.0)
	var total_force := aero_force + thrust_force + gravity

	# Ground clamp
	var ground_y := 0.0
	if transform.origin.y <= ground_y + 0.1:
		_kin_on_ground = true
		if total_force.y < 0.0:
			total_force.y = 0.0
		if _kin_velocity.y < 0.0:
			_kin_velocity.y = 0.0
		transform.origin.y = ground_y + 0.05
	else:
		_kin_on_ground = false

	state["on_ground"] = _kin_on_ground

	# Integrate velocity & position
	_kin_velocity += (total_force / mass) * delta
	state["velocity"]  = _kin_velocity
	state["position"]  = transform.origin + _kin_velocity * delta
	state["airspeed_ms"] = airspeed
	state["altitude_m"]  = state["position"].y

	# Angular dynamics (simple proportional control)
	var roll_rate_max  := deg_to_rad(cfg.get("max_roll_rate_dps",  180.0))
	var pitch_rate_max := deg_to_rad(cfg.get("max_pitch_rate_dps",  90.0))
	var yaw_rate_max   := deg_to_rad(cfg.get("max_yaw_rate_dps",    60.0))

	var speed_factor := clampf(airspeed / 10.0, 0.0, 1.0)
	_kin_ang_vel.x = aileron  * roll_rate_max  * speed_factor
	_kin_ang_vel.z = elevator * pitch_rate_max * speed_factor
	_kin_ang_vel.y = rudder   * yaw_rate_max   * speed_factor

	# Integrate orientation
	_kin_rotation += Vector3(
		rad_to_deg(_kin_ang_vel.x),
		rad_to_deg(_kin_ang_vel.y),
		rad_to_deg(_kin_ang_vel.z)
	) * delta

	state["angular_velocity"] = _kin_ang_vel
	state["euler_deg"]    = _kin_rotation
	state["orientation"]  = Quaternion.from_euler(Vector3(
		deg_to_rad(_kin_rotation.x),
		deg_to_rad(_kin_rotation.y),
		deg_to_rad(_kin_rotation.z)
	))

# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------
func _surface_to_jsbsim_prop(surface: String) -> String:
	match surface:
		SURFACE_AILERON:  return "fcs/aileron-cmd-norm"
		SURFACE_ELEVATOR: return "fcs/elevator-cmd-norm"
		SURFACE_RUDDER:   return "fcs/rudder-cmd-norm"
		SURFACE_THROTTLE: return "fcs/throttle-cmd-norm"
		SURFACE_FLAP:     return "fcs/flap-cmd-norm"
	return ""
