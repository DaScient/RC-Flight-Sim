## camera_manager.gd
## Manages switching between all five camera modes via hotkeys F1-F5.
## Attach to the scene root. All camera child nodes must be registered.
class_name CameraManager
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal camera_mode_changed(mode: String)

# ---------------------------------------------------------------------------
# Camera mode enum
# ---------------------------------------------------------------------------
enum CameraMode { FPV, CHASE, STATIONARY, TOWER, FREE_ORBIT }

# ---------------------------------------------------------------------------
# Exported node references (drag-and-drop in editor)
# ---------------------------------------------------------------------------
@export var fpv_camera:         Camera3D = null
@export var chase_camera:       Camera3D = null
@export var stationary_camera:  Camera3D = null
@export var tower_camera:       Camera3D = null
@export var free_orbit_camera:  Camera3D = null

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var current_mode: CameraMode = CameraMode.CHASE

var _cameras: Dictionary = {}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_cameras[CameraMode.FPV]        = fpv_camera
	_cameras[CameraMode.CHASE]      = chase_camera
	_cameras[CameraMode.STATIONARY] = stationary_camera
	_cameras[CameraMode.TOWER]      = tower_camera
	_cameras[CameraMode.FREE_ORBIT] = free_orbit_camera

	# Apply saved preference
	var saved: String = SettingsManager.get_setting("camera_mode", "chase")
	match saved:
		"fpv":        set_camera(CameraMode.FPV)
		"stationary": set_camera(CameraMode.STATIONARY)
		"tower":      set_camera(CameraMode.TOWER)
		"orbit":      set_camera(CameraMode.FREE_ORBIT)
		_:            set_camera(CameraMode.CHASE)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_fpv"):
		set_camera(CameraMode.FPV)
	elif event.is_action_pressed("camera_chase"):
		set_camera(CameraMode.CHASE)
	elif event.is_action_pressed("camera_stationary"):
		set_camera(CameraMode.STATIONARY)
	elif event.is_action_pressed("camera_tower"):
		set_camera(CameraMode.TOWER)
	elif event.is_action_pressed("camera_orbit"):
		set_camera(CameraMode.FREE_ORBIT)
	elif event.is_action_pressed("camera_cycle"):
		_cycle_camera()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func set_camera(mode: CameraMode) -> void:
	current_mode = mode
	for m in _cameras:
		var cam := _cameras[m] as Camera3D
		if cam != null:
			cam.current = (m == mode)

	var mode_name := _mode_to_string(mode)
	SettingsManager.set_setting("camera_mode", mode_name)
	camera_mode_changed.emit(mode_name)
	print("[CameraManager] Active camera: %s" % mode_name)

func get_active_camera() -> Camera3D:
	return _cameras.get(current_mode) as Camera3D

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _cycle_camera() -> void:
	var next := (current_mode + 1) % (CameraMode.FREE_ORBIT + 1)
	set_camera(next as CameraMode)

func _mode_to_string(mode: CameraMode) -> String:
	match mode:
		CameraMode.FPV:        return "fpv"
		CameraMode.CHASE:      return "chase"
		CameraMode.STATIONARY: return "stationary"
		CameraMode.TOWER:      return "tower"
		CameraMode.FREE_ORBIT: return "orbit"
	return "chase"
