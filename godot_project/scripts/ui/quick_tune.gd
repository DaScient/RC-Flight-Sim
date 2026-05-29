## quick_tune.gd
## In-flight "Quick Tune" panel (Part 2B). Lets advanced users adjust a small
## set of high-impact gains live and immediately feel the effect, then save the
## values back to the aircraft's tuning.json.
##
## The data layer (apply_gain / save) is fully implemented and testable; the
## visual layout is built programmatically from TUNABLES so adding a parameter
## is a one-line change. Toggle visibility with the "quick_tune_toggle" action.
extends Control

## The aircraft being tuned. Set by the scene/main controller.
var aircraft: Node = null

## Tunables exposed by the panel: key -> { label, min, max, step }.
const TUNABLES := {
	"engine_power_factor":   {"label": "Engine Power",        "min": 0.2, "max": 3.0, "step": 0.05},
	"drag_multiplier":       {"label": "Drag",                "min": 0.2, "max": 3.0, "step": 0.05},
	"aileron_effectiveness": {"label": "Aileron Authority",   "min": 0.2, "max": 3.0, "step": 0.05},
	"inertia_scale":         {"label": "Rotational Inertia",  "min": 0.2, "max": 3.0, "step": 0.05},
	"expo":                  {"label": "Stick Expo",          "min": 0.0, "max": 1.0, "step": 0.01},
}

var _sliders: Dictionary = {}

func _ready() -> void:
	hide()
	_build_ui()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quick_tune_toggle"):
		visible = not visible
		if visible:
			_sync_from_aircraft()

## Apply a gain live to the aircraft's in-memory config (takes effect next tick).
func apply_gain(key: String, value: float) -> void:
	if aircraft == null:
		return
	var cfg: Dictionary = aircraft.get_config()
	cfg[key] = value

## Persist the current tunable values back to the aircraft's tuning.json.
func save_to_tuning_json() -> bool:
	if aircraft == null:
		return false
	var cfg: Dictionary = aircraft.get_config()
	var base_path: String = String(aircraft.get("aircraft_config_path"))
	if base_path == "":
		return false
	var out_path := base_path.get_base_dir().path_join("tuning.json")
	var doc := {}
	for key in TUNABLES.keys():
		doc[key] = cfg.get(key, 1.0)
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("[QuickTune] Cannot write %s" % out_path)
		return false
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	return true

# ---------------------------------------------------------------------------
# UI construction
# ---------------------------------------------------------------------------
func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	add_child(vbox)
	var title := Label.new()
	title.text = "Quick Tune"
	vbox.add_child(title)

	for key in TUNABLES.keys():
		var spec: Dictionary = TUNABLES[key]
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = String(spec["label"])
		label.custom_minimum_size = Vector2(160, 0)
		var slider := HSlider.new()
		slider.min_value = float(spec["min"])
		slider.max_value = float(spec["max"])
		slider.step = float(spec["step"])
		slider.custom_minimum_size = Vector2(200, 0)
		slider.value_changed.connect(_on_slider_changed.bind(key))
		row.add_child(label)
		row.add_child(slider)
		vbox.add_child(row)
		_sliders[key] = slider

	var save_btn := Button.new()
	save_btn.text = "Save to tuning.json"
	save_btn.pressed.connect(save_to_tuning_json)
	vbox.add_child(save_btn)

func _on_slider_changed(value: float, key: String) -> void:
	apply_gain(key, value)

func _sync_from_aircraft() -> void:
	if aircraft == null:
		return
	var cfg: Dictionary = aircraft.get_config()
	for key in _sliders.keys():
		var slider: HSlider = _sliders[key]
		slider.set_value_no_signal(float(cfg.get(key, 1.0)))
