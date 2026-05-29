## agentic_hud.gd
## In-flight HUD element for Experimental Agentic Mode (Phase 3.3 / 3.4).
##
## Shows LLM (or local-fallback) instructor tips for a few seconds, a co-pilot
## status line during demonstrations, and provides two quick actions: "Grade
## last 10s" and "Demo maneuver". All controls are created in code so this can
## be added as a child of the main HUD CanvasLayer without a .tscn.
##
## It records a rolling buffer of telemetry snapshots so grading/debrief can be
## requested without the manager having to keep history.
extends Control

const TIP_DISPLAY_SEC := 8.0
const HISTORY_SECONDS := 60.0
const SAMPLE_INTERVAL := 0.25   # 4 Hz rolling telemetry history

var _tip_label: Label
var _status_label: Label
var _btn_grade: Button
var _btn_demo: Button
var _maneuver_edit: LineEdit

var _tip_timer: float = 0.0
var _sample_accum: float = 0.0
## Rolling history of {snapshot, t} for grading/debrief.
var _history: Array = []

func _ready() -> void:
	_build_ui()
	var mgr := get_node_or_null("/root/AgenticManager")
	if mgr != null:
		mgr.tip_received.connect(_on_tip)
		mgr.grade_received.connect(_on_grade)
		mgr.request_failed.connect(_on_failed)
		mgr.copilot_state_changed.connect(_on_copilot_state)
		mgr.enabled_changed.connect(func(v: bool) -> void: visible = v)
		visible = bool(mgr.enabled)

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	add_child(vbox)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.modulate = Color(0.6, 0.9, 1.0)
	vbox.add_child(_status_label)

	_tip_label = Label.new()
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_tip_label)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	vbox.add_child(row)

	_btn_grade = Button.new()
	_btn_grade.text = "Grade last 10s"
	_btn_grade.pressed.connect(_on_grade_pressed)
	row.add_child(_btn_grade)

	_maneuver_edit = LineEdit.new()
	_maneuver_edit.placeholder_text = "Describe a maneuver (e.g. show me a loop)"
	_maneuver_edit.custom_minimum_size = Vector2(280, 0)
	row.add_child(_maneuver_edit)

	_btn_demo = Button.new()
	_btn_demo.text = "Demo"
	_btn_demo.pressed.connect(_on_demo_pressed)
	row.add_child(_btn_demo)

func _process(delta: float) -> void:
	if not visible:
		return
	_record_history(delta)
	if _tip_timer > 0.0:
		_tip_timer -= delta
		if _tip_timer <= 0.0:
			_tip_label.text = ""

# ---------------------------------------------------------------------------
# Telemetry history (for grading / debrief)
# ---------------------------------------------------------------------------
func _record_history(delta: float) -> void:
	_sample_accum += delta
	if _sample_accum < SAMPLE_INTERVAL:
		return
	_sample_accum = 0.0
	var mgr := get_node_or_null("/root/AgenticManager")
	if mgr == null:
		return
	var snap: Dictionary = mgr._current_snapshot()
	if snap.is_empty():
		return
	var now := float(Time.get_ticks_msec()) / 1000.0
	_history.append({"snapshot": snap, "t": now})
	# Trim to the rolling window.
	while not _history.is_empty() and now - float(_history[0]["t"]) > HISTORY_SECONDS:
		_history.pop_front()

## Return the snapshots recorded in the last [param seconds].
func get_recent_snapshots(seconds: float) -> Array:
	var now := float(Time.get_ticks_msec()) / 1000.0
	var out: Array = []
	for entry in _history:
		if now - float(entry["t"]) <= seconds:
			out.append(entry["snapshot"])
	return out

## Full rolling history snapshots (used by the debrief screen).
func get_all_snapshots() -> Array:
	var out: Array = []
	for entry in _history:
		out.append(entry["snapshot"])
	return out

# ---------------------------------------------------------------------------
# Button handlers
# ---------------------------------------------------------------------------
func _on_grade_pressed() -> void:
	var mgr := get_node_or_null("/root/AgenticManager")
	if mgr != null:
		mgr.request_grade(get_recent_snapshots(10.0))

func _on_demo_pressed() -> void:
	var mgr := get_node_or_null("/root/AgenticManager")
	if mgr != null and _maneuver_edit.text.strip_edges() != "":
		mgr.request_maneuver(_maneuver_edit.text.strip_edges())

# ---------------------------------------------------------------------------
# Manager signal handlers
# ---------------------------------------------------------------------------
func _on_tip(text: String, _spoken: bool) -> void:
	_tip_label.modulate = Color.WHITE
	_tip_label.text = text
	_tip_timer = TIP_DISPLAY_SEC

func _on_grade(text: String) -> void:
	_tip_label.modulate = Color(1.0, 0.95, 0.6)
	_tip_label.text = "Grade: " + text
	_tip_timer = TIP_DISPLAY_SEC * 1.5

func _on_failed(_kind: String, message: String) -> void:
	_tip_label.modulate = Color(1.0, 0.6, 0.6)
	_tip_label.text = "AI: " + message
	_tip_timer = TIP_DISPLAY_SEC

func _on_copilot_state(engaged: bool, info: String) -> void:
	_status_label.text = ("AI co-pilot: %s" % info) if engaged else ""
