## hud.gd
## In-flight heads-up display: shows airspeed, altitude, attitude indicator,
## throttle bar, camera mode, and telemetry.
extends CanvasLayer

# ---------------------------------------------------------------------------
# Node references
# ---------------------------------------------------------------------------
@onready var _label_airspeed:  Label = $HUDPanel/Airspeed
@onready var _label_altitude:  Label = $HUDPanel/Altitude
@onready var _label_throttle:  Label = $HUDPanel/Throttle
@onready var _label_camera:    Label = $HUDPanel/CameraMode
@onready var _label_fps:       Label = $HUDPanel/FPS
@onready var _attitude_indicator: Control = $HUDPanel/AttitudeIndicator

## Reference to the active aircraft node (set by main scene)
var aircraft: AircraftNode = null

## Reference to the camera manager (set by main scene)
var camera_manager: CameraManager = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	visible = SettingsManager.get_setting("show_hud", true)

func _process(_delta: float) -> void:
	if not visible:
		return

	# FPS counter
	_label_fps.text = "FPS: %d" % Engine.get_frames_per_second()

	if aircraft == null:
		return

	var state := aircraft.fdm.get_state()

	# Airspeed (m/s → km/h for display)
	var airspeed_kmh: float = float(state.get("airspeed_ms", 0.0)) * 3.6
	_label_airspeed.text = "SPD: %.1f km/h" % airspeed_kmh

	# Altitude (m)
	var alt: float = float(state.get("altitude_m", 0.0))
	_label_altitude.text = "ALT: %.1f m" % alt

	# Throttle percentage
	var thr: float = float(state.get("throttle_pos", 0.0)) * 100.0
	_label_throttle.text = "THR: %.0f%%" % thr

	# Camera mode
	if camera_manager:
		_label_camera.text = "CAM: %s" % camera_manager._mode_to_string(camera_manager.current_mode).to_upper()

	# Attitude indicator: update via euler angles
	var euler: Vector3 = state.get("euler_deg", Vector3.ZERO)
	_update_attitude_indicator(euler.x, euler.z)

## Simple artificial horizon drawing
func _update_attitude_indicator(roll_deg: float, pitch_deg: float) -> void:
	if _attitude_indicator == null:
		return
	_attitude_indicator.rotation = deg_to_rad(-roll_deg)
	# Shift the horizon line based on pitch
	var pitch_pixel_scale := 2.0  # pixels per degree
	_attitude_indicator.position.y = pitch_deg * pitch_pixel_scale

## Toggle HUD visibility
func toggle_hud() -> void:
	visible = not visible
	SettingsManager.set_setting("show_hud", visible)
