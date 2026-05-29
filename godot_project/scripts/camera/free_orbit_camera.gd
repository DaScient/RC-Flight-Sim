## free_orbit_camera.gd
## Free-orbit camera: RMB drag to orbit, scroll wheel to zoom, always
## orbiting around the current aircraft target.
class_name FreeOrbitCamera
extends Camera3D

@export var orbit_speed:   float = 0.4   ## degrees per pixel of mouse movement
@export var zoom_speed:    float = 2.0   ## metres per scroll tick
@export var min_distance:  float = 1.0
@export var max_distance:  float = 100.0
@export var default_distance: float = 10.0

var target: Node3D = null

var _yaw:   float = 0.0    ## degrees
var _pitch: float = 20.0   ## degrees
var _dist:  float = 10.0

var _is_orbiting: bool = false

func _ready() -> void:
	set_as_top_level(true)
	_dist = default_distance

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_is_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = clampf(_dist - zoom_speed, min_distance, max_distance)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = clampf(_dist + zoom_speed, min_distance, max_distance)

	elif event is InputEventMouseMotion and _is_orbiting:
		var mm := event as InputEventMouseMotion
		_yaw   -= mm.relative.x * orbit_speed
		_pitch -= mm.relative.y * orbit_speed
		_pitch  = clampf(_pitch, -89.0, 89.0)

func _process(_delta: float) -> void:
	if target == null:
		return
	var center := target.global_position
	var offset := Vector3(
		_dist * cos(deg_to_rad(_pitch)) * sin(deg_to_rad(_yaw)),
		_dist * sin(deg_to_rad(_pitch)),
		_dist * cos(deg_to_rad(_pitch)) * cos(deg_to_rad(_yaw))
	)
	global_position = center + offset
	look_at(center, Vector3.UP)
