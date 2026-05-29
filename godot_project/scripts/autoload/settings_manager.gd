## settings_manager.gd
## Autoload singleton that persists user preferences and adjusts graphics quality presets.
extends Node

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------
signal settings_changed(key: String, value: Variant)
signal preset_changed(preset: String)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const SETTINGS_PATH := "user://settings.cfg"

const PRESET_LOW    := "Low"
const PRESET_MEDIUM := "Medium"
const PRESET_HIGH   := "High"
const PRESET_ULTRA  := "Ultra"

# Shadow size map
const SHADOW_SIZES := {
	PRESET_LOW:    512,
	PRESET_MEDIUM: 1024,
	PRESET_HIGH:   2048,
	PRESET_ULTRA:  4096,
}

# MSAA map (RenderingServer values)
const MSAA_VALUES := {
	PRESET_LOW:    0,  # Disabled
	PRESET_MEDIUM: 2,  # 2x
	PRESET_HIGH:   4,  # 4x
	PRESET_ULTRA:  8,  # 8x
}

# ---------------------------------------------------------------------------
# Default settings
# ---------------------------------------------------------------------------
var _defaults: Dictionary = {
	"graphics_preset":   PRESET_MEDIUM,
	"fullscreen":        false,
	"vsync":             true,
	"draw_distance":     1000.0,
	"grass_density":     0.5,
	"post_processing":   true,
	"audio_master_vol":  1.0,
	"audio_sfx_vol":     1.0,
	"audio_music_vol":   0.5,
	"aircraft":          "trainer",
	"scenery":           "default_airfield",
	"camera_mode":       "chase",
	"show_hud":          true,
	"language":          "en",
}

var _settings: Dictionary = {}
var _config := ConfigFile.new()

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_settings = _defaults.duplicate()
	_load()
	_apply_all()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func get_setting(key: String, default_val: Variant = null) -> Variant:
	if _settings.has(key):
		return _settings[key]
	if _defaults.has(key):
		return _defaults[key]
	return default_val

func set_setting(key: String, value: Variant) -> void:
	_settings[key] = value
	settings_changed.emit(key, value)

func save() -> void:
	for key in _settings:
		_config.set_value("settings", key, _settings[key])
	var err := _config.save(SETTINGS_PATH)
	if err != OK:
		push_error("[SettingsManager] Failed to save settings: %d" % err)

func apply_graphics_preset(preset: String) -> void:
	set_setting("graphics_preset", preset)

	# Shadow quality
	var shadow_size: int = SHADOW_SIZES.get(preset, 1024)
	RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)

	# MSAA
	var msaa: int = MSAA_VALUES.get(preset, 0)
	get_viewport().msaa_3d = msaa

	# Post-processing toggle
	var post_proc: bool = preset in [PRESET_HIGH, PRESET_ULTRA]
	set_setting("post_processing", post_proc)

	preset_changed.emit(preset)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
func _load() -> void:
	var err := _config.load(SETTINGS_PATH)
	if err != OK:
		return  # First run, use defaults
	for key in _defaults:
		if _config.has_section_key("settings", key):
			_settings[key] = _config.get_value("settings", key)

func _apply_all() -> void:
	# Fullscreen
	if _settings.get("fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	# VSync
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if _settings.get("vsync", true) else DisplayServer.VSYNC_DISABLED
	)
	# Audio volumes
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_volume_db(master_bus,
			linear_to_db(_settings.get("audio_master_vol", 1.0)))
	# Graphics preset
	apply_graphics_preset(_settings.get("graphics_preset", PRESET_MEDIUM))
