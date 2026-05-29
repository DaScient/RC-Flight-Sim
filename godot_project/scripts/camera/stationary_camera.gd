## stationary_camera.gd
## Fixed-position pilot-box camera. Always looks at the aircraft with smooth
## tracking. Position is set in the editor or via the camera_manager.
class_name StationaryCamera
extends Camera3D

@export var track_speed: float = 4.0  ## How fast the camera rotates to follow

var target: Node3D = null

func _ready() -> void:
	set_as_top_level(true)

func _process(delta: float) -> void:
	if target == null:
		return
	# Smoothly look towards the aircraft
	var look_pos := target.global_position
	var current_basis := global_transform.basis
	var desired_transform := global_transform.looking_at(look_pos, Vector3.UP)
	global_transform.basis = current_basis.slerp(desired_transform.basis, clampf(track_speed * delta, 0.0, 1.0))
