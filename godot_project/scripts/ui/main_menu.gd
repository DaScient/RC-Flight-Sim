## main_menu.gd
## Main menu UI: handles aircraft/scenery selection and launches flight.
extends Control

@onready var _btn_fly:         Button  = $VBox/BtnFly
@onready var _btn_settings:    Button  = $VBox/BtnSettings
@onready var _btn_calibrate:   Button  = $VBox/BtnCalibrate
@onready var _btn_quit:        Button  = $VBox/BtnQuit
@onready var _aircraft_option: OptionButton = $VBox/AircraftOption
@onready var _scenery_option:  OptionButton = $VBox/SceneryOption
@onready var _version_label:   Label   = $VersionLabel

const AIRCRAFT_LIST := ["trainer", "aerobat", "jet"]
const SCENERY_LIST  := ["default_airfield", "indoor_arena"]

func _ready() -> void:
	_btn_fly.pressed.connect(_on_fly_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)
	_btn_calibrate.pressed.connect(_on_calibrate_pressed)
	_btn_quit.pressed.connect(_on_quit_pressed)

	# Populate dropdowns
	_aircraft_option.clear()
	for a in AIRCRAFT_LIST:
		_aircraft_option.add_item(a.capitalize())
	_scenery_option.clear()
	for s in SCENERY_LIST:
		_scenery_option.add_item(s.replace("_", " ").capitalize())

	# Restore last selection
	var saved_aircraft := SettingsManager.get_setting("aircraft", "trainer")
	var saved_scenery  := SettingsManager.get_setting("scenery", "default_airfield")
	_aircraft_option.selected = max(AIRCRAFT_LIST.find(saved_aircraft), 0)
	_scenery_option.selected  = max(SCENERY_LIST.find(saved_scenery), 0)

	_version_label.text = "RC-Flight-Sim v%s" % ProjectSettings.get_setting("application/config/version", "0.1.0")

func _on_fly_pressed() -> void:
	var aircraft := AIRCRAFT_LIST[_aircraft_option.selected]
	var scenery  := SCENERY_LIST[_scenery_option.selected]
	SceneManager.start_flight(aircraft, scenery)

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/settings_menu.tscn")

func _on_calibrate_pressed() -> void:
	var wizard_scene := load("res://scenes/ui/calibration_wizard.tscn") as PackedScene
	if wizard_scene:
		var wizard := wizard_scene.instantiate()
		add_child(wizard)
	else:
		push_warning("[MainMenu] Calibration wizard scene not found.")

func _on_quit_pressed() -> void:
	get_tree().quit()
