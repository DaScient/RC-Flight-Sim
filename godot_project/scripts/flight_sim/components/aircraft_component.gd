## aircraft_component.gd
## Base class for modular aircraft subsystems (propulsion, aerodynamics,
## damage, sound). Components are children of an AircraftNode and are driven
## once per physics tick after the FDM has produced a new state snapshot.
##
## Lifecycle:
##   setup(aircraft)            -> called once when the aircraft is ready
##   physics_tick(delta, state) -> called every _physics_process with the
##                                 latest FDM state Dictionary
class_name AircraftComponent
extends Node

## Back-reference to the owning aircraft. Typed loosely to avoid a hard cyclic
## dependency between the component scripts and AircraftNode.
var aircraft: Node = null

## Called once by AircraftNode after all components are added to the tree.
## Override to cache references and read configuration. The default stores the
## aircraft reference.
func setup(owner_aircraft: Node) -> void:
	aircraft = owner_aircraft

## Called every physics frame with the freshly computed FDM [param state].
## Override in subclasses; the base implementation does nothing.
func physics_tick(_delta: float, _state: Dictionary) -> void:
	pass

## Convenience accessor for the merged aircraft configuration Dictionary.
func _config() -> Dictionary:
	if aircraft != null and aircraft.has_method("get_config"):
		return aircraft.get_config()
	return {}
