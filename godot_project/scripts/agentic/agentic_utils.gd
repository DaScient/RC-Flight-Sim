## agentic_utils.gd
## Pure, side-effect-free helpers for the Experimental Agentic Mode (Phase 3).
##
## Everything here is a `static` function with no engine/runtime dependencies
## (no HTTPRequest, no autoloads, no scene tree) so it can be unit-tested
## headless via tests/run_tests.gd. The stateful glue (HTTP, timers, UI) lives
## in AgenticManager and the agentic UI scripts, which call into this file.
##
## Conventions:
## * Control values are normalised: aileron/elevator/rudder in [-1, 1],
##   throttle in [0, 1].
## * Telemetry "snapshots" are compact Dictionaries safe to serialise to JSON
##   and embed in an LLM prompt.
class_name AgenticUtils
extends RefCounted

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
## Control channels the AI co-pilot is allowed to drive.
const CONTROL_KEYS: PackedStringArray = ["aileron", "elevator", "rudder", "throttle"]

## Default safety envelope used to disengage the AI co-pilot (see
## is_dangerous_attitude). Conservative values suitable for RC models.
const DEFAULT_SAFETY_LIMITS: Dictionary = {
	"max_roll_deg":   85.0,    # near-knife-edge; beyond this hand back control
	"max_pitch_deg":  80.0,
	"min_altitude_m": 2.0,     # don't let the AI fly into the ground
}

## Stick movement (absolute, normalised) above which we treat the human as
## having grabbed control back from the AI co-pilot.
const OVERRIDE_THRESHOLD: float = 0.15

# ---------------------------------------------------------------------------
# Telemetry snapshots
# ---------------------------------------------------------------------------
## Build a compact, JSON-serialisable telemetry snapshot from a raw FDM state
## Dictionary (see FDMInterface.state) and a controls Dictionary
## (see FDMInterface.get_controls()). Values are rounded to keep prompts small.
static func build_telemetry_snapshot(state: Dictionary, controls: Dictionary) -> Dictionary:
	var euler: Vector3 = state.get("euler_deg", Vector3.ZERO)
	var vel: Vector3 = state.get("velocity", Vector3.ZERO)
	return {
		"airspeed_ms": _round2(float(state.get("airspeed_ms", 0.0))),
		"altitude_m":  _round2(float(state.get("altitude_m", 0.0))),
		"aoa_deg":     _round2(float(state.get("aoa_deg", 0.0))),
		"roll_deg":    _round2(euler.x),
		"pitch_deg":   _round2(euler.z),
		"yaw_deg":     _round2(euler.y),
		"climb_ms":    _round2(vel.y),
		"rpm":         _round2(float(state.get("engine_rpm", 0.0))),
		"on_ground":   bool(state.get("on_ground", false)),
		"aileron":     _round2(float(controls.get("aileron", 0.0))),
		"elevator":    _round2(float(controls.get("elevator", 0.0))),
		"rudder":      _round2(float(controls.get("rudder", 0.0))),
		"throttle":    _round2(float(controls.get("throttle", 0.0))),
	}

## Render a snapshot as a short single-line "key=value" string for embedding in
## an LLM prompt. Deterministic key order keeps prompts (and tests) stable.
static func snapshot_to_prompt_text(snapshot: Dictionary) -> String:
	var keys: Array = snapshot.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%s" % [k, str(snapshot[k])])
	return ", ".join(parts)

# ---------------------------------------------------------------------------
# Control clamping & safety
# ---------------------------------------------------------------------------
## Clamp a control command Dictionary to valid, safe ranges. Unknown keys are
## dropped; missing keys default to neutral. Throttle is clamped to [0, 1], all
## other channels to [-1, 1]. Never trusts AI/LLM output blindly.
static func clamp_control_inputs(cmd: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in CONTROL_KEYS:
		var raw: float = float(cmd.get(key, 0.0))
		if key == "throttle":
			out[key] = clampf(raw, 0.0, 1.0)
		else:
			out[key] = clampf(raw, -1.0, 1.0)
	return out

## Return true if the aircraft state violates the safety envelope and the AI
## co-pilot should immediately disengage and hand control back to the human.
static func is_dangerous_attitude(state: Dictionary, limits: Dictionary = {}) -> bool:
	var lim: Dictionary = DEFAULT_SAFETY_LIMITS.duplicate()
	lim.merge(limits, true)
	var euler: Vector3 = state.get("euler_deg", Vector3.ZERO)
	if absf(euler.x) > float(lim["max_roll_deg"]):
		return true
	if absf(euler.z) > float(lim["max_pitch_deg"]):
		return true
	# Only treat low altitude as dangerous while airborne and descending-ish.
	var altitude: float = float(state.get("altitude_m", 0.0))
	if not bool(state.get("on_ground", false)) and altitude < float(lim["min_altitude_m"]):
		return true
	return false

## Return true if the human moved any stick beyond [param threshold], meaning
## they want control back from the AI co-pilot. [param channels] mirrors
## InputManager.channels (aileron/elevator/rudder in [-1,1], throttle [0,1]).
static func detect_user_override(channels: Dictionary, threshold: float = OVERRIDE_THRESHOLD) -> bool:
	for key in ["aileron", "elevator", "rudder"]:
		if absf(float(channels.get(key, 0.0))) > threshold:
			return true
	return false

# ---------------------------------------------------------------------------
# Maneuver sequences (AI co-pilot playback)
# ---------------------------------------------------------------------------
## Parse an LLM-supplied maneuver into a clean, time-sorted Array of keyframes.
## Accepts either a raw JSON string or an already-parsed Array. Each keyframe is
## an object like {"t": 0.0, "aileron": 0.0, "elevator": -0.8, ...}. Invalid
## entries are skipped; controls are clamped. Returns [] on malformed input.
static func parse_maneuver_sequence(source: Variant) -> Array:
	var raw: Variant = source
	if source is String:
		var json: JSON = JSON.new()
		if json.parse(source) != OK:
			return []
		raw = json.data
	# Allow {"sequence": [...]} or {"keyframes": [...]} wrappers.
	if raw is Dictionary:
		var dict: Dictionary = raw
		if dict.has("sequence"):
			raw = dict["sequence"]
		elif dict.has("keyframes"):
			raw = dict["keyframes"]
	if not (raw is Array):
		return []
	var frames: Array = []
	for entry in (raw as Array):
		if not (entry is Dictionary):
			continue
		var e: Dictionary = entry
		var clamped: Dictionary = clamp_control_inputs(e)
		clamped["t"] = maxf(0.0, float(e.get("t", 0.0)))
		frames.append(clamped)
	frames.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["t"]) < float(b["t"]))
	return frames

## Sample a parsed maneuver [param sequence] at time [param t] (seconds),
## linearly interpolating control values between the surrounding keyframes.
## Returns clamped controls. An empty sequence yields neutral controls.
static func sample_maneuver(sequence: Array, t: float) -> Dictionary:
	if sequence.is_empty():
		return clamp_control_inputs({})
	if t <= float(sequence[0]["t"]):
		return clamp_control_inputs(sequence[0])
	var last: Dictionary = sequence[sequence.size() - 1]
	if t >= float(last["t"]):
		return clamp_control_inputs(last)
	for i in range(sequence.size() - 1):
		var a: Dictionary = sequence[i]
		var b: Dictionary = sequence[i + 1]
		var ta: float = float(a["t"])
		var tb: float = float(b["t"])
		if t >= ta and t <= tb:
			var span: float = tb - ta
			var f: float = 0.0 if span <= 0.0 else (t - ta) / span
			var blended: Dictionary = {}
			for key in CONTROL_KEYS:
				blended[key] = lerpf(float(a.get(key, 0.0)), float(b.get(key, 0.0)), f)
			return clamp_control_inputs(blended)
	return clamp_control_inputs(last)

## Total duration (seconds) of a parsed maneuver sequence (time of last frame).
static func maneuver_duration(sequence: Array) -> float:
	if sequence.is_empty():
		return 0.0
	return float(sequence[sequence.size() - 1]["t"])

# ---------------------------------------------------------------------------
# Local (offline) fallback feedback
# ---------------------------------------------------------------------------
## Rule-based flight tip used when no LLM is available (no key / network error).
## Keeps Agentic Mode useful and never breaks the sim. Returns "" if all looks
## nominal so callers can choose to stay quiet.
static func local_fallback_tip(state: Dictionary, config: Dictionary = {}) -> String:
	var airspeed: float = float(state.get("airspeed_ms", 0.0))
	var altitude: float = float(state.get("altitude_m", 0.0))
	var aoa: float = float(state.get("aoa_deg", 0.0))
	var on_ground: bool = bool(state.get("on_ground", false))
	var stall_speed: float = float(config.get("stall_speed_ms", 7.0))

	if on_ground:
		return ""
	if airspeed < stall_speed:
		return "Watch your airspeed - you're near stall. Lower the nose and add power."
	if absf(aoa) > 14.0:
		return "High angle of attack - ease off the elevator to avoid a stall."
	if altitude < 5.0:
		return "Low altitude - climb to a safe height before maneuvering."
	var euler: Vector3 = state.get("euler_deg", Vector3.ZERO)
	if absf(euler.z) > 60.0:
		return "Steep pitch attitude - return toward level flight."
	return ""

# ---------------------------------------------------------------------------
# LLM request / response helpers (OpenAI-compatible Chat Completions)
# ---------------------------------------------------------------------------
## Build an OpenAI-compatible Chat Completions request body. Works with OpenAI,
## Together AI, LM Studio and other local endpoints that mirror the schema.
static func build_chat_request_body(model: String, system_prompt: String, user_prompt: String, stream: bool = false) -> Dictionary:
	return {
		"model": model,
		"stream": stream,
		"temperature": 0.4,
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": user_prompt},
		],
	}

## Extract the assistant message text from a parsed Chat Completions response.
## Returns "" if the structure is missing/unexpected (caller falls back).
static func extract_message_content(response: Dictionary) -> String:
	var choices: Variant = response.get("choices", null)
	if not (choices is Array) or (choices as Array).is_empty():
		return ""
	var first: Variant = (choices as Array)[0]
	if not (first is Dictionary):
		return ""
	var message: Variant = (first as Dictionary).get("message", null)
	if message is Dictionary:
		return String((message as Dictionary).get("content", ""))
	# Streaming chunks use "delta" instead of "message".
	var delta: Variant = (first as Dictionary).get("delta", null)
	if delta is Dictionary:
		return String((delta as Dictionary).get("content", ""))
	return ""

## Pull the first JSON object/array embedded in [param text] (LLMs often wrap
## JSON in prose or ```code fences```). Returns the parsed Variant, or null.
static func extract_json_block(text: String) -> Variant:
	var start_obj: int = text.find("{")
	var start_arr: int = text.find("[")
	var start: int = -1
	var open_ch: String = "{"
	var close_ch: String = "}"
	if start_arr != -1 and (start_obj == -1 or start_arr < start_obj):
		start = start_arr
		open_ch = "["
		close_ch = "]"
	else:
		start = start_obj
	if start == -1:
		return null
	var depth: int = 0
	for i in range(start, text.length()):
		var c: String = text[i]
		if c == open_ch:
			depth += 1
		elif c == close_ch:
			depth -= 1
			if depth == 0:
				var json: JSON = JSON.new()
				if json.parse(text.substr(start, i - start + 1)) == OK:
					return json.data
				return null
	return null

# ---------------------------------------------------------------------------
# Scenario validation (dynamic scenario generation)
# ---------------------------------------------------------------------------
## Sanitise an LLM-generated scenario so it can only reference known aircraft /
## sceneries and sane environment values. Always returns a complete, safe
## scenario Dictionary regardless of how malformed the input was.
static func validate_scenario(data: Dictionary, available_aircraft: PackedStringArray, available_scenery: PackedStringArray) -> Dictionary:
	var aircraft: String = String(data.get("aircraft", ""))
	if not available_aircraft.has(aircraft):
		aircraft = available_aircraft[0] if available_aircraft.size() > 0 else "trainer"
	var scenery: String = String(data.get("scenery", ""))
	if not available_scenery.has(scenery):
		scenery = available_scenery[0] if available_scenery.size() > 0 else "default_airfield"
	return {
		"aircraft": aircraft,
		"scenery": scenery,
		"wind_speed_ms":   clampf(float(data.get("wind_speed_ms", 0.0)), 0.0, 25.0),
		"wind_dir_deg":    fposmod(float(data.get("wind_dir_deg", 0.0)), 360.0),
		"turbulence":      clampf(float(data.get("turbulence", 0.0)), 0.0, 1.0),
		"time_of_day":     clampf(float(data.get("time_of_day", 12.0)), 0.0, 24.0),
		"description":     String(data.get("description", "")),
	}

# ---------------------------------------------------------------------------
# Lightweight API-key obfuscation
# ---------------------------------------------------------------------------
## NOTE: This is deliberately *not* strong encryption. The project is open
## source, so we only obfuscate the key at rest with an XOR + Base64 pass so it
## isn't sitting in plain text in settings.cfg. The seed is device-derived by
## the caller. See docs/agentic_mode.md for the security caveats.
static func obfuscate_key(plain: String, seed: String) -> String:
	if plain.is_empty():
		return ""
	return Marshalls.raw_to_base64(_xor_bytes(plain.to_utf8_buffer(), seed))

## Reverse obfuscate_key(). Returns "" on malformed input.
static func deobfuscate_key(encoded: String, seed: String) -> String:
	if encoded.is_empty():
		return ""
	var bytes: PackedByteArray = Marshalls.base64_to_raw(encoded)
	if bytes.is_empty():
		return ""
	return _xor_bytes(bytes, seed).get_string_from_utf8()

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------
static func _xor_bytes(data: PackedByteArray, seed: String) -> PackedByteArray:
	var key: PackedByteArray = seed.to_utf8_buffer()
	if key.is_empty():
		key = PackedByteArray([0x5A])  # fixed non-zero fallback
	var out: PackedByteArray = PackedByteArray()
	out.resize(data.size())
	for i in range(data.size()):
		out[i] = data[i] ^ key[i % key.size()]
	return out

static func _round2(value: float) -> float:
	return snappedf(value, 0.01)
