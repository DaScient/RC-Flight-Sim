## aircraft_node.gd
## Main aircraft node. Reads inputs from InputManager, drives the FDMInterface,
## applies the resulting physics state to the transform, and dispatches that
## state to modular components (Propulsion, Aerodynamics, Damage, Sound).
##
## Component-based design (Part 4 refactor): per-frame behaviour lives in small
## AircraftComponent subclasses instead of this monolith. Components may be
## added as child nodes in the scene; any that are missing are created with
## sensible defaults so existing scenes keep working.
##
## Determinism: all simulation runs in _physics_process and avoids delta-scaled
## randomness (see Atmosphere for the gust model, which is seeded separately).
class_name AircraftNode
extends Node3D

# ---------------------------------------------------------------------------
# Exported properties (configure per aircraft scene)
# ---------------------------------------------------------------------------
@export var aircraft_config_path: String = "res://assets/aircraft/trainer/trainer.json"
@export var engine_audio: AudioStreamPlayer3D = null
@export var propeller_mesh: MeshInstance3D = null

# ---------------------------------------------------------------------------
# Child node references
# ---------------------------------------------------------------------------
@onready var fdm: FDMInterface = $FDMInterface as FDMInterface

# ---------------------------------------------------------------------------
# Components
# ---------------------------------------------------------------------------
var propulsion: PropulsionComponent = null
var aerodynamics: AerodynamicsComponent = null
var damage: DamageComponent = null
var sound: SoundComponent = null

var _components: Array[AircraftComponent] = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	if fdm == null:
		push_error("[AircraftNode] FDMInterface child node not found!")
		return
	fdm.load_aircraft(aircraft_config_path)
	_setup_components()

func _physics_process(delta: float) -> void:
	if fdm == null:
		return

	# 1. Read smoothed inputs from InputManager.
	var inputs: Dictionary = InputManager.channels

	# 2. Apply expo / dual-rates from aircraft config (via MathUtils).
	var cfg := fdm.aircraft_config
	var aileron_rate: float = ConfigLoader.get_number(cfg, "aileron_rate", 1.0)
	var elevator_rate: float = ConfigLoader.get_number(cfg, "elevator_rate", 1.0)
	var rudder_rate: float = ConfigLoader.get_number(cfg, "rudder_rate", 1.0)
	var expo: float = ConfigLoader.get_number(cfg, "expo", 0.3)

	fdm.set_control_surface(FDMInterface.SURFACE_AILERON,
		MathUtils.apply_rates_expo(inputs["aileron"], aileron_rate, expo))
	fdm.set_control_surface(FDMInterface.SURFACE_ELEVATOR,
		MathUtils.apply_rates_expo(inputs["elevator"], elevator_rate, expo))
	fdm.set_control_surface(FDMInterface.SURFACE_RUDDER,
		MathUtils.apply_rates_expo(inputs["rudder"], rudder_rate, expo))
	fdm.set_control_surface(FDMInterface.SURFACE_THROTTLE, inputs["throttle"])

	# 3. Step the FDM.
	fdm.update_fdm(delta, global_transform)

	# 4. Apply resulting state to the transform.
	var state := fdm.get_state()
	global_position = state["position"]
	global_transform.basis = Basis(state["orientation"])

	# 5. Drive components with the new state snapshot.
	for c in _components:
		c.physics_tick(delta, state)

# ---------------------------------------------------------------------------
# Component wiring
# ---------------------------------------------------------------------------
func _setup_components() -> void:
	propulsion = _ensure_component("Propulsion", PropulsionComponent) as PropulsionComponent
	aerodynamics = _ensure_component("Aerodynamics", AerodynamicsComponent) as AerodynamicsComponent
	damage = _ensure_component("Damage", DamageComponent) as DamageComponent
	sound = _ensure_component("Sound", SoundComponent) as SoundComponent

	# Wire legacy exported nodes into the relevant components.
	if propeller_mesh != null:
		propulsion.propeller_mesh = propeller_mesh
	if engine_audio != null:
		sound.engine_audio = engine_audio

	_components = [propulsion, aerodynamics, damage, sound]
	for c in _components:
		c.setup(self)

	# Cross-component signal hookups.
	if damage != null and sound != null:
		damage.prop_strike.connect(sound.on_prop_strike)

## Return an existing child component of [param type] named [param node_name],
## or create one if absent so older scenes without components still function.
func _ensure_component(node_name: String, type: GDScript) -> AircraftComponent:
	var existing := get_node_or_null(node_name)
	if existing != null and existing is AircraftComponent:
		return existing
	var comp: AircraftComponent = type.new()
	comp.name = node_name
	add_child(comp)
	return comp

# ---------------------------------------------------------------------------
# Public accessors (used by camera, HUD, components)
# ---------------------------------------------------------------------------
## Merged aircraft configuration (base JSON + tuning overrides), via FDM.
func get_config() -> Dictionary:
	return fdm.aircraft_config if fdm != null else {}

## Normalised propulsion power level in [0, 1]; used by Damage/Sound/dust FX.
func get_power_level() -> float:
	return propulsion.get_power_level() if propulsion != null else 0.0

func get_airspeed() -> float:
	return fdm.state.get("airspeed_ms", 0.0) if fdm != null else 0.0

func get_altitude() -> float:
	return fdm.state.get("altitude_m", 0.0) if fdm != null else 0.0
