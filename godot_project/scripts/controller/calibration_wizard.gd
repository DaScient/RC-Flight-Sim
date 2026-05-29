## calibration_wizard.gd
## Step-by-step controller calibration wizard.
## Guides the user through: detect sticks → move to endpoints → set center
## → reverse axes → configure deadzones → save.
class_name CalibrationWizard
extends Control

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal calibration_complete()
signal calibration_cancelled()

# ---------------------------------------------------------------------------
# Wizard steps
# ---------------------------------------------------------------------------
enum Step {
	WELCOME,
	DETECT_DEVICE,
	MOVE_AILERON,
	MOVE_ELEVATOR,
	MOVE_THROTTLE,
	MOVE_RUDDER,
	SET_CENTER,
	REVERSE_AXES,
	SET_DEADZONE,
	CONFIRM,
}

var _step: Step = Step.WELCOME

# Channel currently being calibrated
const CHANNELS: Array[String] = ["aileron", "elevator", "throttle", "rudder"]
var _current_channel_idx: int = 0

# Recorded min/max/center for each channel
var _recorded: Dictionary = {}

# Temporary working calibration
var _working_cal: Dictionary = {}

# ---------------------------------------------------------------------------
# UI node references (configure in editor or set programmatically)
# ---------------------------------------------------------------------------
@onready var _label_title:       Label  = $VBox/Title
@onready var _label_instruction: Label  = $VBox/Instruction
@onready var _progress_bar:      ProgressBar = $VBox/Progress
@onready var _axis_readout:      Label  = $VBox/AxisReadout
@onready var _btn_next:          Button = $VBox/Buttons/BtnNext
@onready var _btn_cancel:        Button = $VBox/Buttons/BtnCancel
@onready var _reverse_check:     CheckBox = $VBox/ReverseCheck
@onready var _deadzone_slider:   HSlider  = $VBox/DeadzoneSlider

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_btn_next.pressed.connect(_on_next_pressed)
	_btn_cancel.pressed.connect(_on_cancel_pressed)
	_init_working_cal()
	_show_step(_step)

func _process(_delta: float) -> void:
	_update_readout()

# ---------------------------------------------------------------------------
# Wizard navigation
# ---------------------------------------------------------------------------
func _on_next_pressed() -> void:
	_commit_current_step()
	_advance_step()

func _on_cancel_pressed() -> void:
	calibration_cancelled.emit()
	queue_free()

func _advance_step() -> void:
	_step = (_step + 1) as Step
	if _step > Step.CONFIRM:
		_finish()
		return
	_show_step(_step)

func _show_step(step: Step) -> void:
	_reverse_check.visible  = false
	_deadzone_slider.visible = false
	_progress_bar.value = (float(step) / float(Step.CONFIRM)) * 100.0

	match step:
		Step.WELCOME:
			_label_title.text = "Controller Calibration Wizard"
			_label_instruction.text = "This wizard will calibrate your RC controller.\nMake sure your transmitter or dongle is connected."
		Step.DETECT_DEVICE:
			var dev_id := InputManager.get_active_device()
			if dev_id >= 0:
				_label_title.text = "Device Detected"
				_label_instruction.text = "Found: %s\nPress Next to continue." % Input.get_joy_name(dev_id)
			else:
				_label_title.text = "No Device Found"
				_label_instruction.text = "No joystick detected. Connect your controller and press Next."
		Step.MOVE_AILERON, Step.MOVE_ELEVATOR, Step.MOVE_THROTTLE, Step.MOVE_RUDDER:
			var ch := _get_channel_for_step(step)
			_label_title.text = "Move %s to full extent" % ch.capitalize()
			_label_instruction.text = "Move the %s stick/channel from MIN to MAX and back several times.\nPress Next when done." % ch
		Step.SET_CENTER:
			_label_title.text = "Centre All Sticks"
			_label_instruction.text = "Release all sticks to their natural centre position.\nPress Next to record centre."
		Step.REVERSE_AXES:
			_label_title.text = "Reverse Axes"
			_label_instruction.text = "Check the box if the channel moves in the wrong direction."
			_reverse_check.visible = true
			_reverse_check.text = "Reverse %s" % CHANNELS[_current_channel_idx].capitalize()
		Step.SET_DEADZONE:
			_label_title.text = "Set Deadzone"
			_label_instruction.text = "Adjust the deadzone slider for %s." % CHANNELS[_current_channel_idx].capitalize()
			_deadzone_slider.visible = true
			_deadzone_slider.min_value = 0.01
			_deadzone_slider.max_value = 0.3
			_deadzone_slider.step = 0.01
			_deadzone_slider.value = _working_cal.get("deadzone", {}).get(CHANNELS[_current_channel_idx], 0.05)
		Step.CONFIRM:
			_label_title.text = "Calibration Complete"
			_label_instruction.text = "Calibration data has been recorded.\nPress Next to save and close."

func _commit_current_step() -> void:
	var dev_id := InputManager.get_active_device()
	if dev_id < 0:
		return

	match _step:
		Step.MOVE_AILERON, Step.MOVE_ELEVATOR, Step.MOVE_THROTTLE, Step.MOVE_RUDDER:
			# The readout has been continuously updating; just save recorded values
			var ch := _get_channel_for_step(_step)
			_cal_section("range_min")[ch] = _recorded.get(ch + "_min", -1.0)
			_cal_section("range_max")[ch] = _recorded.get(ch + "_max",  1.0)
		Step.SET_CENTER:
			for ch in CHANNELS:
				var axis_idx: int = _working_cal.get("axis_map", {}).get(ch, 0)
				_cal_section("center")[ch] = InputManager.get_raw_axis(dev_id, axis_idx)
		Step.REVERSE_AXES:
			var ch := CHANNELS[_current_channel_idx]
			_cal_section("reversed")[ch] = _reverse_check.button_pressed
		Step.SET_DEADZONE:
			var ch := CHANNELS[_current_channel_idx]
			_cal_section("deadzone")[ch] = _deadzone_slider.value

## Return the named sub-dictionary of the working calibration, creating it if
## absent. (Replaces Dictionary.get_or_add(), which requires Godot 4.4+.)
func _cal_section(section: String) -> Dictionary:
	if not _working_cal.has(section):
		_working_cal[section] = {}
	return _working_cal[section]

func _update_readout() -> void:
	var dev_id := InputManager.get_active_device()
	if dev_id < 0:
		_axis_readout.text = "No device"
		return
	var text := ""
	for i in range(6):
		var v := InputManager.get_raw_axis(dev_id, i)
		text += "Axis %d: %+.3f\n" % [i, v]
		# Track min/max per channel for endpoint recording
		var ch_name := _axis_to_channel_name(i)
		if ch_name != "":
			_recorded[ch_name + "_min"] = minf(_recorded.get(ch_name + "_min", INF), v)
			_recorded[ch_name + "_max"] = maxf(_recorded.get(ch_name + "_max", -INF), v)
	_axis_readout.text = text

func _get_channel_for_step(step: Step) -> String:
	match step:
		Step.MOVE_AILERON:  return "aileron"
		Step.MOVE_ELEVATOR: return "elevator"
		Step.MOVE_THROTTLE: return "throttle"
		Step.MOVE_RUDDER:   return "rudder"
	return ""

func _axis_to_channel_name(axis: int) -> String:
	match axis:
		0: return "aileron"
		1: return "elevator"
		2: return "throttle"
		3: return "rudder"
	return ""

func _init_working_cal() -> void:
	_working_cal = InputManager._cal.duplicate(true) if InputManager._cal else {}
	for ch in CHANNELS:
		_recorded[ch + "_min"] = INF
		_recorded[ch + "_max"] = -INF

func _finish() -> void:
	# Push working calibration back to InputManager and save
	for key in _working_cal:
		InputManager._cal[key] = _working_cal[key]
	InputManager.save_calibration()
	calibration_complete.emit()
	queue_free()
