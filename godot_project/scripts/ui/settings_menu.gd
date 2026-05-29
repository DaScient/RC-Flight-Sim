## settings_menu.gd
## Settings menu: graphics presets, audio volumes, display options.
extends Control

@onready var _preset_option:    OptionButton = $ScrollContainer/VBox/PresetOption
@onready var _fullscreen_check: CheckBox     = $ScrollContainer/VBox/FullscreenCheck
@onready var _vsync_check:      CheckBox     = $ScrollContainer/VBox/VsyncCheck
@onready var _master_slider:    HSlider      = $ScrollContainer/VBox/MasterSlider
@onready var _sfx_slider:       HSlider      = $ScrollContainer/VBox/SFXSlider
@onready var _music_slider:     HSlider      = $ScrollContainer/VBox/MusicSlider
@onready var _btn_apply:        Button       = $Buttons/BtnApply
@onready var _btn_back:         Button       = $Buttons/BtnBack

const PRESETS := [
	SettingsManager.PRESET_LOW,
	SettingsManager.PRESET_MEDIUM,
	SettingsManager.PRESET_HIGH,
	SettingsManager.PRESET_ULTRA,
]

func _ready() -> void:
	_btn_apply.pressed.connect(_on_apply_pressed)
	_btn_back.pressed.connect(_on_back_pressed)

	_preset_option.clear()
	for p in PRESETS:
		_preset_option.add_item(p)

	_load_current_settings()

func _load_current_settings() -> void:
	var preset := SettingsManager.get_setting("graphics_preset", SettingsManager.PRESET_MEDIUM)
	_preset_option.selected = max(PRESETS.find(preset), 0)
	_fullscreen_check.button_pressed = SettingsManager.get_setting("fullscreen", false)
	_vsync_check.button_pressed      = SettingsManager.get_setting("vsync", true)
	_master_slider.value = SettingsManager.get_setting("audio_master_vol", 1.0)
	_sfx_slider.value    = SettingsManager.get_setting("audio_sfx_vol", 1.0)
	_music_slider.value  = SettingsManager.get_setting("audio_music_vol", 0.5)

func _on_apply_pressed() -> void:
	SettingsManager.apply_graphics_preset(PRESETS[_preset_option.selected])
	SettingsManager.set_setting("fullscreen",        _fullscreen_check.button_pressed)
	SettingsManager.set_setting("vsync",             _vsync_check.button_pressed)
	SettingsManager.set_setting("audio_master_vol",  _master_slider.value)
	SettingsManager.set_setting("audio_sfx_vol",     _sfx_slider.value)
	SettingsManager.set_setting("audio_music_vol",   _music_slider.value)
	SettingsManager.save()

	# Re-apply display settings immediately
	if _fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if _vsync_check.button_pressed else DisplayServer.VSYNC_DISABLED
	)

	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus, linear_to_db(_master_slider.value))

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
