## chase_camera.gd
## Third-person spring-arm chase camera. Smoothly follows the aircraft from
## behind and above, with configurable arm length and damping.
class_name ChaseCamera
extends Camera3D

@export var arm_length: float       = 5.0     ## metres
@export var height_offset: float    = 1.5     ## metres above aircraft
@export var follow_speed: float     = 5.0     ## positional follow speed
@export var rotation_speed: float   = 3.0     ## rotational lag speed
@export var terrain_margin: float   = 0.5     ## min height above terrain

## Reference to the aircraft node (set by main scene)
var target: Node3D = null

var _desired_pos: Vector3     = Vector3.ZERO
var _desired_basis: Basis     = Basis.IDENTITY

func _ready() -> void:
	set_as_top_level(true)  # Camera moves independently of parent in world space

func _process(delta: float) -> void:
	if target == null:
		return

	var aircraft_pos := target.global_position
	var aircraft_fwd := -target.global_transform.basis.z  # forward

	# Desired camera position: behind and above aircraft
	var back_dir := -aircraft_fwd
	_desired_pos = aircraft_pos + back_dir * arm_length + Vector3.UP * height_offset

	# Simple terrain avoidance: clamp to terrain_margin above y=0 (ground plane)
	_desired_pos.y = maxf(_desired_pos.y, terrain_margin)

	# Smooth positional follow
	global_position = global_position.lerp(_desired_pos, clampf(follow_speed * delta, 0.0, 1.0))

	# Look at aircraft
	var look_target := aircraft_pos + Vector3.UP * 0.3
	look_at(look_target, Vector3.UP)
