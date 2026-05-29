## agentic_toggle.gd
## Hidden-hover minimal toggle for Experimental Agentic Mode (Phase 3.7).
##
## A tiny semi-transparent "AI" pill in the top-right corner. On mouse hover it
## expands to reveal a checkbox ("Agentic Mode: ON/OFF"). When no API key is
## configured the toggle is greyed out and clicking it asks the user to open the
## Agentic AI settings tab (signal open_settings_requested).
##
## Build this scene-free: the script creates its own child controls so it can be
## dropped onto any Control/CanvasLayer, or instanced from code by the HUD.
extends Control

signal open_settings_requested

const COLLAPSED_ALPHA := 0.35
const EXPANDED_ALPHA := 1.0

var _panel: PanelContainer
var _row: HBoxContainer
var _icon: Label
var _check: CheckBox
var _expanded: bool = false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(140, 28)
	_build_ui()
	_collapse()

	mouse_entered.connect(_expand)
	mouse_exited.connect(_collapse)

	var mgr := get_node_or_null("/root/AgenticManager")
	if mgr != null:
		mgr.enabled_changed.connect(_on_enabled_changed)
		_check.button_pressed = bool(mgr.enabled)
	_refresh_availability()

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	add_child(_panel)

	_row = HBoxContainer.new()
	_panel.add_child(_row)

	_icon = Label.new()
	_icon.text = "AI"
	_icon.tooltip_text = "Experimental Agentic Mode (LLM). Requires your own API key. May incur API costs."
	_row.add_child(_icon)

	_check = CheckBox.new()
	_check.text = "Agentic Mode"
	_check.toggled.connect(_on_check_toggled)
	_row.add_child(_check)

func _expand() -> void:
	_expanded = true
	_check.visible = true
	modulate.a = EXPANDED_ALPHA

func _collapse() -> void:
	_expanded = false
	# Keep the toggle discoverable but unobtrusive: hide the checkbox label only
	# when the box is unchecked so an active mode stays visible.
	_check.visible = _check.button_pressed
	modulate.a = COLLAPSED_ALPHA

func _on_check_toggled(pressed: bool) -> void:
	var mgr := get_node_or_null("/root/AgenticManager")
	if mgr == null:
		return
	if pressed and not bool(mgr.has_api_key()):
		# Can't enable without a key: revert and route the user to settings.
		_check.set_pressed_no_signal(false)
		open_settings_requested.emit()
		return
	mgr.set_enabled(pressed)

func _on_enabled_changed(value: bool) -> void:
	_check.set_pressed_no_signal(value)

## Grey out + disable the checkbox when no key is configured.
func _refresh_availability() -> void:
	var mgr := get_node_or_null("/root/AgenticManager")
	if mgr == null:
		return
	var has_key := bool(mgr.has_api_key())
	_check.disabled = not has_key
	_icon.modulate = Color.WHITE if has_key else Color(0.7, 0.7, 0.7, 1.0)
	if not has_key:
		_check.tooltip_text = "Add an API key in Settings → Agentic AI to enable."
