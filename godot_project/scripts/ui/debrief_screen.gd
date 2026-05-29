## debrief_screen.gd
## Post-flight AI debrief panel for Experimental Agentic Mode (Phase 3.6).
##
## Accessible from the pause menu. Sends a compressed flight-log summary (a set
## of telemetry snapshots) to the LLM and shows the returned debrief. Falls back
## to a canned message when no key/network is available (handled by the manager).
extends Control

var _text: RichTextLabel
var _btn_generate: Button
var _btn_close: Button
var _spinner: Label

## Snapshots to summarise. Set by the caller (e.g. from AgenticHUD history)
## before showing the panel.
var snapshots: Array = []

func _ready() -> void:
	_build_ui()
	var mgr := get_node_or_null("/root/AgenticManager")
	if mgr != null:
		mgr.debrief_received.connect(_on_debrief)
		mgr.request_failed.connect(_on_failed)

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 420)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Flight Debrief"
	vbox.add_child(title)

	_spinner = Label.new()
	_spinner.text = ""
	vbox.add_child(_spinner)

	_text = RichTextLabel.new()
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(520, 300)
	_text.bbcode_enabled = true
	vbox.add_child(_text)

	var row := HBoxContainer.new()
	vbox.add_child(row)

	_btn_generate = Button.new()
	_btn_generate.text = "Generate Debrief"
	_btn_generate.pressed.connect(_on_generate_pressed)
	row.add_child(_btn_generate)

	_btn_close = Button.new()
	_btn_close.text = "Close"
	_btn_close.pressed.connect(func() -> void: hide())
	row.add_child(_btn_close)

## Show the panel and (optionally) immediately request a debrief for [param data].
func open_with(data: Array, auto_generate: bool = false) -> void:
	snapshots = data
	_text.text = ""
	show()
	if auto_generate:
		_on_generate_pressed()

func _on_generate_pressed() -> void:
	var mgr := get_node_or_null("/root/AgenticManager")
	if mgr == null:
		return
	_spinner.text = "Analysing flight…"
	_btn_generate.disabled = true
	mgr.request_debrief(snapshots)

func _on_debrief(text: String) -> void:
	_spinner.text = ""
	_btn_generate.disabled = false
	_text.text = text

func _on_failed(kind: String, message: String) -> void:
	if kind != "debrief":
		return
	_spinner.text = ""
	_btn_generate.disabled = false
	_text.text = "[color=#ff8888]%s[/color]" % message
