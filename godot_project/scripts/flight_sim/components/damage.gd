## damage.gd
## Damage component: tracks structural integrity and detects events that cause
## damage - hard landings, overspeed structural stress and prop strikes when the
## propeller touches the ground. Emits signals so visual/audio systems (e.g.
## prop-strike particles + sound) can respond.
class_name DamageComponent
extends AircraftComponent

## Emitted when the propeller contacts the ground while spinning.
signal prop_strike(power_level: float)
## Emitted when health changes. [param health] is in [0, 1].
signal health_changed(health: float)
## Emitted once when the aircraft is considered destroyed.
signal destroyed()

@export var propeller_tip_node: Node3D = null

var _health: float = 1.0
var _hard_landing_ms: float = 4.0     # vertical speed threshold for damage
var _prop_radius: float = 0.15
var _destroyed: bool = false
var _prev_velocity: Vector3 = Vector3.ZERO

func setup(owner_aircraft: Node) -> void:
	super.setup(owner_aircraft)
	var cfg := _config()
	_hard_landing_ms = ConfigLoader.get_number(cfg, "hard_landing_ms", 4.0, 0.1, 100.0)
	_prop_radius = ConfigLoader.get_number(cfg, "prop_radius_m", 0.15, 0.0, 5.0)

func physics_tick(_delta: float, state: Dictionary) -> void:
	if _destroyed:
		return
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var on_ground: bool = bool(state.get("on_ground", false))

	# Detect the touchdown instant: previously descending, now on ground.
	if on_ground and _prev_velocity.y < -0.01:
		var impact := absf(_prev_velocity.y)
		if impact > _hard_landing_ms:
			# Damage scales with how far over the threshold the impact was.
			var severity := clampf((impact - _hard_landing_ms) / _hard_landing_ms, 0.0, 1.0)
			_apply_damage(severity * 0.5)

	# Prop strike: spinning prop tip below ground level while on the ground.
	if on_ground and aircraft != null and aircraft.has_method("get_power_level"):
		var power: float = aircraft.get_power_level()
		if power > 0.05 and _prop_tip_below_ground():
			prop_strike.emit(power)
			_apply_damage(power * 0.25)

	_prev_velocity = velocity

func _prop_tip_below_ground() -> bool:
	if propeller_tip_node == null:
		return false
	# Ground plane assumed at y = 0 in this scaffold; replace with terrain query.
	return propeller_tip_node.global_position.y - _prop_radius <= 0.0

func _apply_damage(amount: float) -> void:
	if _destroyed or amount <= 0.0:
		return
	_health = clampf(_health - amount, 0.0, 1.0)
	health_changed.emit(_health)
	if _health <= 0.0:
		_destroyed = true
		destroyed.emit()

func get_health() -> float:
	return _health

func repair() -> void:
	_health = 1.0
	_destroyed = false
	health_changed.emit(_health)
