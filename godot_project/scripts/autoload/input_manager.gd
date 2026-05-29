## input_manager.gd
## Autoload singleton that manages all RC controller input, joystick detection,
## calibration profiles, and provides smoothed, scaled input values to the FDM.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal joystick_connected(device_id: int, name: String)
signal joystick_disconnected(device_id: int)
signal calibration_changed()

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const PROFILE_PATH := "user://controller_profiles.cfg"
const DEFAULT_AXIS_AILERON  := 0
const DEFAULT_AXIS_ELEVATOR := 1
const DEFAULT_AXIS_THROTTLE := 2
const DEFAULT_AXIS_RUDDER   := 3

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
## Processed channel values in range [-1, 1] (throttle: [0, 1])
var channels: Dictionary = {
	"aileron":  0.0,
	"elevator": 0.0,
	"throttle": 0.0,
	"rudder":   0.0,
	"aux1":     0.0,
	"aux2":     0.0,
}

## Active joystick device index (-1 = keyboard fallback)
var active_device: int = -1

## Per-device calibration profiles loaded from config
## Structure: { guid: { axis_map, reversed, deadzone, min, max, center } }
var _profiles: Dictionary = {}

## Current calibration data for the active device
var _cal: Dictionary = {}

## Config file for profiles
var _config := ConfigFile.new()

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_load_profiles()
	_detect_joysticks()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _process(_delta: float) -> void:
	_update_channels()

# ---------------------------------------------------------------------------
# Joystick detection
# ---------------------------------------------------------------------------
func _detect_joysticks() -> void:
	for id in Input.get_connected_joypads():
		_on_joy_connection_changed(id, true)

func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if connected:
		var joy_name := Input.get_joy_name(device_id)
		var guid := Input.get_joy_guid(device_id)
		print("[InputManager] Joystick connected: %s (GUID: %s, device: %d)" % [joy_name, guid, device_id])
		if active_device == -1:
			active_device = device_id
			_load_calibration_for_guid(guid)
		joystick_connected.emit(device_id, joy_name)
	else:
		print("[InputManager] Joystick disconnected: device %d" % device_id)
		if active_device == device_id:
			active_device = -1
			_cal = _default_calibration()
			# Try to activate next available joystick
			var pads := Input.get_connected_joypads()
			if not pads.is_empty():
				active_device = pads[0]
				_load_calibration_for_guid(Input.get_joy_guid(active_device))
		joystick_disconnected.emit(device_id)

# ---------------------------------------------------------------------------
# Channel update
# ---------------------------------------------------------------------------
func _update_channels() -> void:
	if active_device >= 0:
		channels["aileron"]  = _read_axis("aileron")
		channels["elevator"] = _read_axis("elevator")
		channels["throttle"] = _read_throttle()
		channels["rudder"]   = _read_axis("rudder")
		channels["aux1"]     = _read_raw_axis(4)
		channels["aux2"]     = _read_raw_axis(5)
	else:
		# Keyboard fallback (useful for testing without hardware)
		channels["aileron"]  = float(int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A)))
		channels["elevator"] = float(int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W)))
		channels["throttle"] = clampf(channels["throttle"]
			+ float(int(Input.is_key_pressed(KEY_UP)) - int(Input.is_key_pressed(KEY_DOWN))) * get_process_delta_time(),
			0.0, 1.0)
		channels["rudder"]   = float(int(Input.is_key_pressed(KEY_E)) - int(Input.is_key_pressed(KEY_Q)))

func _read_axis(channel: String) -> float:
	var axis_idx: int = _cal.get("axis_map", {}).get(channel, _default_axis_for(channel))
	var raw := Input.get_joy_axis(active_device, axis_idx)
	return _apply_calibration(channel, raw)

func _read_throttle() -> float:
	var axis_idx: int = _cal.get("axis_map", {}).get("throttle", DEFAULT_AXIS_THROTTLE)
	var raw := Input.get_joy_axis(active_device, axis_idx)
	var cal_val := _apply_calibration("throttle", raw)
	# Throttle is typically 0-1 (from -1 to 1 raw)
	return (cal_val + 1.0) * 0.5

func _read_raw_axis(axis_idx: int) -> float:
	return Input.get_joy_axis(active_device, axis_idx)

func _apply_calibration(channel: String, raw: float) -> float:
	var deadzone: float = _cal.get("deadzone", {}).get(channel, 0.05)
	var reversed: bool  = _cal.get("reversed", {}).get(channel, false)
	var center: float   = _cal.get("center", {}).get(channel, 0.0)
	var range_min: float = _cal.get("range_min", {}).get(channel, -1.0)
	var range_max: float = _cal.get("range_max", {}).get(channel, 1.0)

	# Remove center offset
	var v := raw - center

	# Apply deadzone
	if absf(v) < deadzone:
		return 0.0

	# Normalize to [-1, 1] based on recorded range
	var half_range := (range_max - range_min) * 0.5
	if half_range > 0.001:
		v = v / half_range

	v = clampf(v, -1.0, 1.0)

	if reversed:
		v = -v

	return v

# ---------------------------------------------------------------------------
# Calibration helpers
# ---------------------------------------------------------------------------
func _default_axis_for(channel: String) -> int:
	match channel:
		"aileron":  return DEFAULT_AXIS_AILERON
		"elevator": return DEFAULT_AXIS_ELEVATOR
		"throttle": return DEFAULT_AXIS_THROTTLE
		"rudder":   return DEFAULT_AXIS_RUDDER
	return 0

func _default_calibration() -> Dictionary:
	return {
		"axis_map":  {
			"aileron":  DEFAULT_AXIS_AILERON,
			"elevator": DEFAULT_AXIS_ELEVATOR,
			"throttle": DEFAULT_AXIS_THROTTLE,
			"rudder":   DEFAULT_AXIS_RUDDER,
		},
		"reversed":  { "aileron": false, "elevator": false, "throttle": false, "rudder": false },
		"deadzone":  { "aileron": 0.05, "elevator": 0.05, "throttle": 0.05, "rudder": 0.05 },
		"center":    { "aileron": 0.0, "elevator": 0.0, "throttle": 0.0, "rudder": 0.0 },
		"range_min": { "aileron": -1.0, "elevator": -1.0, "throttle": -1.0, "rudder": -1.0 },
		"range_max": { "aileron":  1.0, "elevator":  1.0, "throttle":  1.0, "rudder":  1.0 },
	}

func _load_calibration_for_guid(guid: String) -> void:
	if _profiles.has(guid):
		_cal = _profiles[guid]
		print("[InputManager] Loaded calibration for GUID: %s" % guid)
	else:
		_cal = _default_calibration()
		print("[InputManager] Using default calibration for GUID: %s" % guid)

## Save calibration for the currently active device
func save_calibration() -> void:
	if active_device < 0:
		return
	var guid := Input.get_joy_guid(active_device)
	_profiles[guid] = _cal.duplicate(true)
	_store_profile_to_config(guid, _cal)
	var err := _config.save(PROFILE_PATH)
	if err != OK:
		push_error("[InputManager] Failed to save profiles: %d" % err)
	calibration_changed.emit()

func _store_profile_to_config(guid: String, cal: Dictionary) -> void:
	for key in cal:
		if cal[key] is Dictionary:
			for sub_key in cal[key]:
				_config.set_value(guid + "_" + key, sub_key, cal[key][sub_key])
		else:
			_config.set_value(guid, key, cal[key])

func _load_profiles() -> void:
	var err := _config.load(PROFILE_PATH)
	if err != OK:
		return  # No saved profiles yet — that's fine
	# Profiles are loaded on demand per GUID in _load_calibration_for_guid

## Update a calibration parameter at runtime (used by CalibrationWizard)
func set_calibration_value(channel: String, param: String, value) -> void:
	if not _cal.has(param):
		_cal[param] = {}
	_cal[param][channel] = value

## Export the active device's calibration as a portable `.rcprofile` JSON file
## (Part 2C). Returns true on success. The file can be shared between users.
func export_profile(path: String, profile_name: String = "") -> bool:
	var doc := {
		"format": "rcprofile",
		"version": 1,
		"name": profile_name if profile_name != "" else _active_guid_name(),
		"guid": Input.get_joy_guid(active_device) if active_device >= 0 else "",
		"calibration": _cal,
	}
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[InputManager] Cannot write profile: %s" % path)
		return false
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	return true

## Import a `.rcprofile` JSON file and apply it to the active device, also
## persisting it to the per-GUID profile store. Returns true on success.
func import_profile(path: String) -> bool:
	var err_out: Array = [""]
	var doc := ConfigLoader.load_json_file(path, err_out)
	if doc.is_empty():
		push_error("[InputManager] Failed to import profile '%s': %s" % [path, err_out[0]])
		return false
	if String(doc.get("format", "")) != "rcprofile":
		push_error("[InputManager] Not an rcprofile file: %s" % path)
		return false
	var cal: Variant = doc.get("calibration", {})
	if typeof(cal) != TYPE_DICTIONARY:
		push_error("[InputManager] rcprofile missing 'calibration' object.")
		return false
	_cal = (cal as Dictionary).duplicate(true)
	if active_device >= 0:
		var guid := Input.get_joy_guid(active_device)
		_profiles[guid] = _cal.duplicate(true)
	calibration_changed.emit()
	return true

func _active_guid_name() -> String:
	return Input.get_joy_name(active_device) if active_device >= 0 else "Default"

## Expose raw joystick axis value for calibration UI
func get_raw_axis(device_id: int, axis: int) -> float:
	return Input.get_joy_axis(device_id, axis)

## Return the currently active device id
func get_active_device() -> int:
	return active_device
