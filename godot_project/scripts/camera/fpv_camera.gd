## fpv_camera.gd
## First-Person-View camera. Parented directly to the aircraft node and
## placed at the cockpit eye point. Follows the aircraft orientation exactly.
class_name FPVCamera
extends Camera3D

## Offset from the aircraft pivot to the FPV eye point (metres)
@export var eye_offset: Vector3 = Vector3(0.0, 0.05, -0.1)

func _ready() -> void:
	position = eye_offset
	# The camera inherits orientation from parent (AircraftNode), so nothing
	# extra needed – just ensure it is correctly positioned.

func _process(_delta: float) -> void:
	# Optionally add a tiny stabilisation lag for head-tracking effect
	pass
