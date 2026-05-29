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

# Fine-grained per-preset detail (Part 1E). Consumed by the renderer/sky/FX
# systems via get_preset_detail(); kept declarative so adding a preset or a
# tunable is a one-line change.
const PRESET_DETAILS := {
	PRESET_LOW: {
		"shadow_cascades":      1,
		"reflection_interval":  0,      # 0 = never update probes after first bake
		"particle_density":     0.25,
		"cloud_quality":        "off",
		"render_scale":         0.75,
		"detail_maps":          false,
	},
	PRESET_MEDIUM: {
		"shadow_cascades":      2,
		"reflection_interval":  4,
		"particle_density":     0.5,
		"cloud_quality":        "low",
		"render_scale":         1.0,
		"detail_maps":          true,
	},
	PRESET_HIGH: {
		"shadow_cascades":      4,
		"reflection_interval":  2,
		"particle_density":     1.0,
		"cloud_quality":        "medium",
		"render_scale":         1.0,
		"detail_maps":          true,
	},
	PRESET_ULTRA: {
		"shadow_cascades":      4,
		"reflection_interval":  1,
		"particle_density":     1.5,
		"cloud_quality":        "high",
		"render_scale":         1.0,
		"detail_maps":          true,
	},
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

	# Telemetry (UDP stream – see docs/telemetry_protocol.md)
	"telemetry_enabled": false,
	"telemetry_host":    "127.0.0.1",
	"telemetry_port":    9001,
	"telemetry_rate_hz": 20.0,

	# Expanded graphics detail (per-preset overrides applied on top of preset)
	"cloud_quality":     "medium",   # off | low | medium | high
	"particle_density":  1.0,        # 0..1 multiplier for FX particle counts
	"render_scale":      1.0,        # 0.5..2.0 (web/perf scaling)
	"cinematic_mode":    false,      # DoF + film grain toggle
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

	# Apply fine-grained detail derived from the preset (Part 1E).
	var detail: Dictionary = PRESET_DETAILS.get(preset, PRESET_DETAILS[PRESET_MEDIUM])
	set_setting("particle_density", detail["particle_density"])
	set_setting("cloud_quality", detail["cloud_quality"])
	set_setting("render_scale", detail["render_scale"])
	var cascades: int = detail["shadow_cascades"]
	RenderingServer.directional_shadow_atlas_set_size(shadow_size, cascades > 1)

	preset_changed.emit(preset)

## Return the fine-grained detail Dictionary for a preset (or the active one).
## Renderer, sky and FX systems read this to size their workloads.
func get_preset_detail(preset: String = "") -> Dictionary:
	var key := preset if preset != "" else String(get_setting("graphics_preset", PRESET_MEDIUM))
	return (PRESET_DETAILS.get(key, PRESET_DETAILS[PRESET_MEDIUM]) as Dictionary).duplicate()

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
