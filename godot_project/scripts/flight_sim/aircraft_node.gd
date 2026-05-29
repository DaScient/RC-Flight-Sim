## aircraft_node.gd
## Main aircraft node. Reads inputs from InputManager, drives the FDMInterface,
## and applies the resulting physics state to the Node3D transform.
## Attach this script to a Node3D (or RigidBody3D) that represents the aircraft.
class_name AircraftNode
extends Node3D

# ---------------------------------------------------------------------------
# Exported properties (configure per aircraft scene)
# ---------------------------------------------------------------------------
@export var aircraft_config_path: String = "res://assets/aircraft/trainer/trainer.json"
@export var engine_audio: AudioStreamPlayer3D = null
@export var propeller_mesh: MeshInstance3D   = null

# ---------------------------------------------------------------------------
# Child node references
# ---------------------------------------------------------------------------
@onready var fdm: FDMInterface = $FDMInterface as FDMInterface

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
if fdm == null:
push_error("[AircraftNode] FDMInterface child node not found!")
return
fdm.load_aircraft(aircraft_config_path)

func _physics_process(delta: float) -> void:
if fdm == null:
return

# 1. Read smoothed inputs from InputManager
var inputs := InputManager.channels

# 2. Apply expo/dual-rates from aircraft config
var cfg := fdm.aircraft_config
var aileron_rate:  float = cfg.get("aileron_rate",  1.0)
var elevator_rate: float = cfg.get("elevator_rate", 1.0)
var rudder_rate:   float = cfg.get("rudder_rate",   1.0)
var expo: float = cfg.get("expo", 0.3)

fdm.set_control_surface(FDMInterface.SURFACE_AILERON,  _apply_expo(inputs["aileron"],  expo) * aileron_rate)
fdm.set_control_surface(FDMInterface.SURFACE_ELEVATOR, _apply_expo(inputs["elevator"], expo) * elevator_rate)
fdm.set_control_surface(FDMInterface.SURFACE_RUDDER,   _apply_expo(inputs["rudder"],   expo) * rudder_rate)
fdm.set_control_surface(FDMInterface.SURFACE_THROTTLE, inputs["throttle"])

# 3. Step the FDM
fdm.update_fdm(delta, global_transform)

# 4. Apply resulting state to transform
var state := fdm.get_state()
global_position = state["position"]
global_transform.basis = Basis(state["orientation"])

# 5. Animate propeller
if propeller_mesh != null:
var rpm: float = state.get("engine_rpm", 0.0)
propeller_mesh.rotation.z += deg_to_rad(rpm / 60.0 * 360.0 * delta)

# 6. Drive engine audio pitch by RPM
if engine_audio != null:
var rpm: float = state.get("engine_rpm", 0.0)
var max_rpm: float = cfg.get("max_rpm", 10000.0)
engine_audio.pitch_scale = clampf(0.4 + (rpm / max_rpm) * 1.4, 0.4, 1.8)
engine_audio.volume_db   = linear_to_db(clampf(rpm / max_rpm, 0.05, 1.0))

## Called by external systems (e.g., camera) to get current airspeed
func get_airspeed() -> float:
return fdm.state.get("airspeed_ms", 0.0)

## Called by external systems to get altitude
func get_altitude() -> float:
return fdm.state.get("altitude_m", 0.0)

## Apply exponential curve to a control input value.
## v: raw input [-1, 1]; e: expo factor [0, 1] (0 = linear, 1 = maximum curve)
func _apply_expo(v: float, e: float) -> float:
return v * (absf(v) * e + (1.0 - e))
