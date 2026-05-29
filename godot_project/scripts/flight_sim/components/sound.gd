## sound.gd
## Sound component: drives engine and wind audio from propulsion power and
## airspeed. Volumes are routed through the SettingsManager audio levels so the
## settings menu sliders affect them live.
class_name SoundComponent
extends AircraftComponent

@export var engine_audio: AudioStreamPlayer3D = null
@export var wind_audio: AudioStreamPlayer3D = null
@export var prop_strike_audio: AudioStreamPlayer3D = null

var _wind_max_ms: float = 30.0

func setup(owner_aircraft: Node) -> void:
	super.setup(owner_aircraft)
	_wind_max_ms = ConfigLoader.get_number(_config(), "max_speed_ms", 30.0, 1.0, 1000.0)
	# Start looping ambient layers if assigned.
	if engine_audio != null and not engine_audio.playing:
		engine_audio.play()
	if wind_audio != null and not wind_audio.playing:
		wind_audio.play()

func physics_tick(_delta: float, state: Dictionary) -> void:
	var sfx := _sfx_volume()

	# Engine: pitch + volume scale with normalised power.
	if engine_audio != null:
		var power := 0.0
		if aircraft != null and aircraft.has_method("get_power_level"):
			power = aircraft.get_power_level()
		engine_audio.pitch_scale = lerpf(0.4, 1.8, power)
		engine_audio.volume_db = linear_to_db(clampf(power, 0.02, 1.0) * sfx)

	# Wind: louder/higher with airspeed.
	if wind_audio != null:
		var airspeed := float(state.get("airspeed_ms", 0.0))
		var wind_norm := clampf(airspeed / _wind_max_ms, 0.0, 1.0)
		wind_audio.pitch_scale = lerpf(0.8, 1.6, wind_norm)
		wind_audio.volume_db = linear_to_db(clampf(wind_norm, 0.001, 1.0) * sfx)

## Play a one-shot prop-strike sound; connected to DamageComponent.prop_strike.
func on_prop_strike(_power_level: float) -> void:
	if prop_strike_audio != null:
		prop_strike_audio.play()

func _sfx_volume() -> float:
	if Engine.has_singleton("SettingsManager"):
		return 1.0
	# SettingsManager is an autoload, accessible by name at runtime.
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("get_setting"):
		return float(sm.get_setting("audio_sfx_vol", 1.0))
	return 1.0
