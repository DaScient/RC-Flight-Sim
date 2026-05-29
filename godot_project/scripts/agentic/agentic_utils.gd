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

# ===========================================================================
# PHASE 5 - Deepening agentic integration & simulation intelligence
# ===========================================================================

# ---------------------------------------------------------------------------
# 5.1.1  AI-generated aircraft configuration
# ---------------------------------------------------------------------------
## Minimal JSBSim element set an AI-generated aircraft must define before we
## trust it enough to write to disk. We only check node *existence* (a light
## schema), never the physics values themselves.
const JSBSIM_REQUIRED_NODES: PackedStringArray = [
	"fdm_config", "metrics", "mass_balance", "aerodynamics",
]

## Validate an LLM-generated JSBSim XML document by element existence only.
## Returns {"valid": bool, "missing": PackedStringArray, "elements": Array}.
## Uses Godot's streaming XMLParser so malformed XML fails gracefully rather
## than crashing. [param required] overrides JSBSIM_REQUIRED_NODES.
static func validate_xml(xml_text: String, required: PackedStringArray = JSBSIM_REQUIRED_NODES) -> Dictionary:
	var seen: Dictionary = {}
	var ordered: Array = []
	var parser := XMLParser.new()
	if xml_text.strip_edges().is_empty():
		return {"valid": false, "missing": required.duplicate(), "elements": ordered}
	if parser.open_buffer(xml_text.to_utf8_buffer()) != OK:
		return {"valid": false, "missing": required.duplicate(), "elements": ordered}
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			var name := parser.get_node_name()
			if not seen.has(name):
				seen[name] = true
				ordered.append(name)
	var missing: PackedStringArray = []
	for req in required:
		if not seen.has(req):
			missing.append(req)
	return {"valid": missing.is_empty(), "missing": missing, "elements": ordered}

## Normalise an LLM-suggested tuning block into a safe `tuning.json` Dictionary.
## Expo/rates are per-channel in [0,1]; power_factor scales thrust in [0.1,2.0].
## Always returns a complete, clamped structure regardless of input shape.
static func build_aircraft_tuning(data: Dictionary) -> Dictionary:
	var expo_in: Dictionary = data.get("expo", {}) if data.get("expo", {}) is Dictionary else {}
	var rates_in: Dictionary = data.get("rates", {}) if data.get("rates", {}) is Dictionary else {}
	var expo: Dictionary = {}
	var rates: Dictionary = {}
	for ch in ["aileron", "elevator", "rudder"]:
		expo[ch] = clampf(float(expo_in.get(ch, 0.3)), 0.0, 1.0)
		rates[ch] = clampf(float(rates_in.get(ch, 1.0)), 0.0, 1.0)
	return {
		"expo": expo,
		"rates": rates,
		"power_factor": clampf(float(data.get("power_factor", 1.0)), 0.1, 2.0),
	}

## Sanitise the wizard's full aircraft description into a safe summary used for
## file naming and the model-description sidecar. Never returns empty strings
## for required fields.
static func validate_aircraft_config(data: Dictionary) -> Dictionary:
	var raw_name := String(data.get("name", "")).strip_edges()
	if raw_name.is_empty():
		raw_name = "custom_aircraft"
	return {
		"name": raw_name,
		"slug": slugify(raw_name),
		"category": String(data.get("category", "sport")).strip_edges(),
		"model_description": String(data.get("model_description", "")).strip_edges(),
		"tuning": build_aircraft_tuning(data.get("tuning", {}) if data.get("tuning", {}) is Dictionary else {}),
	}

## Convert an arbitrary name into a filesystem-safe lowercase slug.
static func slugify(text: String) -> String:
	var out: String = ""
	for ch in text.strip_edges().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.lstrip("_").rstrip("_")
	return out if not out.is_empty() else "custom"

# ---------------------------------------------------------------------------
# 5.1.2  AI-generated sceneries
# ---------------------------------------------------------------------------
## Prop types the scenery generator is allowed to place. Anything else from the
## LLM is dropped so a hallucinated mesh name can never reach the loader.
const SCENERY_PROP_TYPES: PackedStringArray = ["tree", "hangar", "windsock", "pylon", "tent", "rock"]

## Validate an LLM scenery description into a safe, complete spec the
## AgenticSceneryGenerator can script. Clamps sizes, whitelists prop types and
## wind layers, and drops malformed placements.
static func parse_scenery_spec(data: Dictionary) -> Dictionary:
	var size: float = clampf(float(data.get("size_m", 500.0)), 100.0, 4000.0)
	var props_in: Variant = data.get("objects", [])
	var props: Array = []
	if props_in is Array:
		for entry in (props_in as Array):
			if not (entry is Dictionary):
				continue
			var e: Dictionary = entry
			var ptype := String(e.get("type", ""))
			if not SCENERY_PROP_TYPES.has(ptype):
				continue
			var half := size * 0.5
			props.append({
				"type": ptype,
				"x": clampf(float(e.get("x", 0.0)), -half, half),
				"z": clampf(float(e.get("z", 0.0)), -half, half),
			})
	var layers_in: Variant = data.get("wind_layers", [])
	var layers: Array = []
	if layers_in is Array:
		for entry in (layers_in as Array):
			if not (entry is Dictionary):
				continue
			var l: Dictionary = entry
			layers.append({
				"altitude_m": clampf(float(l.get("altitude_m", 0.0)), 0.0, 2000.0),
				"speed_ms": clampf(float(l.get("speed_ms", 0.0)), 0.0, 30.0),
				"dir_deg": fposmod(float(l.get("dir_deg", 0.0)), 360.0),
			})
	return {
		"name": String(data.get("name", "AI Airfield")).strip_edges(),
		"size_m": size,
		"runway_length_m": clampf(float(data.get("runway_length_m", 300.0)), 50.0, size),
		"objects": props,
		"wind_layers": layers,
		"description": String(data.get("description", "")).strip_edges(),
	}

# ---------------------------------------------------------------------------
# 5.2  Voice command parsing
# ---------------------------------------------------------------------------
## Actions the voice pipeline understands. The LLM maps free-form speech onto
## one of these; anything else becomes "unknown" so callers can no-op safely.
const VOICE_ACTIONS: PackedStringArray = [
	"demonstrate_maneuver", "set_wind", "grade_landing",
	"talk_through", "generate_scenario", "set_time_of_day",
]

## Parse an LLM-structured voice command (JSON string, embedded JSON, or an
## already-parsed Dictionary) into a safe action envelope:
##   {"action": String, "params": Dictionary, "say": String}
## Unknown/garbled commands return action "unknown" with the original text in
## `say` so the UI can ask the user to repeat.
static func parse_voice_command(source: Variant) -> Dictionary:
	var data: Variant = source
	if source is String:
		var block: Variant = extract_json_block(source)
		data = block if block != null else {}
	if not (data is Dictionary):
		return {"action": "unknown", "params": {}, "say": str(source)}
	var d: Dictionary = data
	var action := String(d.get("action", "")).strip_edges().to_lower()
	var params_in: Dictionary = d.get("params", {}) if d.get("params", {}) is Dictionary else {}
	var say := String(d.get("say", ""))
	if not VOICE_ACTIONS.has(action):
		return {"action": "unknown", "params": {}, "say": say if say != "" else str(source)}
	return {"action": action, "params": _sanitise_voice_params(action, params_in), "say": say}

## Clamp/whitelist parameters per action so a malicious or hallucinated command
## can never push out-of-range values into the sim.
static func _sanitise_voice_params(action: String, p: Dictionary) -> Dictionary:
	match action:
		"set_wind":
			return {
				"speed_ms": clampf(float(p.get("speed_ms", 0.0)), 0.0, 30.0),
				"dir_deg": fposmod(float(p.get("dir_deg", 0.0)), 360.0),
				"gusts": bool(p.get("gusts", false)),
			}
		"set_time_of_day":
			return {"hour": clampf(float(p.get("hour", 12.0)), 0.0, 24.0)}
		"demonstrate_maneuver", "talk_through":
			return {"maneuver": String(p.get("maneuver", "")).strip_edges()}
		"generate_scenario":
			return {"description": String(p.get("description", "")).strip_edges()}
		_:
			return {}

# ---------------------------------------------------------------------------
# 5.3  Flight replay & AI analysis
# ---------------------------------------------------------------------------
## Number of frames a ring buffer needs to hold [param seconds] at [param hz].
static func ring_capacity(hz: float, seconds: float) -> int:
	return int(maxf(1.0, ceilf(maxf(0.0, hz) * maxf(0.0, seconds))))

## Evenly down-sample a frame Array to at most [param max_samples] entries while
## always keeping the first and last frame. Used to fit a flight into an LLM
## prompt without blowing the token budget.
static func downsample_frames(frames: Array, max_samples: int) -> Array:
	if max_samples <= 0 or frames.is_empty():
		return []
	if frames.size() <= max_samples:
		return frames.duplicate()
	var out: Array = []
	var step: float = float(frames.size() - 1) / float(max_samples - 1)
	for i in range(max_samples):
		out.append(frames[int(round(i * step))])
	return out

## Compute summary stats over a flight's telemetry snapshots: duration, peak
## speed/altitude, descent rate, etc. Empty input yields zeros.
static func summarize_replay(frames: Array, hz: float = 50.0) -> Dictionary:
	var summary: Dictionary = {
		"frames": frames.size(),
		"duration_s": 0.0 if hz <= 0.0 else float(frames.size()) / hz,
		"max_altitude_m": 0.0,
		"max_airspeed_ms": 0.0,
		"min_altitude_m": 0.0,
		"max_climb_ms": 0.0,
		"max_descent_ms": 0.0,
	}
	if frames.is_empty():
		return summary
	var first := true
	for f in frames:
		if not (f is Dictionary):
			continue
		var alt: float = float(f.get("altitude_m", 0.0))
		var spd: float = float(f.get("airspeed_ms", 0.0))
		var climb: float = float(f.get("climb_ms", 0.0))
		if first:
			summary["max_altitude_m"] = alt
			summary["min_altitude_m"] = alt
			first = false
		summary["max_altitude_m"] = maxf(summary["max_altitude_m"], alt)
		summary["min_altitude_m"] = minf(summary["min_altitude_m"], alt)
		summary["max_airspeed_ms"] = maxf(summary["max_airspeed_ms"], spd)
		summary["max_climb_ms"] = maxf(summary["max_climb_ms"], climb)
		summary["max_descent_ms"] = minf(summary["max_descent_ms"], climb)
	return summary

## Format a "M:SS" timestamp from seconds (negative clamped to 0).
static func format_timecode(seconds: float) -> String:
	var s: int = int(maxf(0.0, seconds))
	return "%d:%02d" % [s / 60, s % 60]

## Parse "M:SS" / "MM:SS" back into seconds; returns -1.0 if not a timecode.
static func parse_timecode(text: String) -> float:
	var parts := text.strip_edges().split(":")
	if parts.size() != 2:
		return -1.0
	if not (parts[0].is_valid_int() and parts[1].is_valid_int()):
		return -1.0
	return float(int(parts[0]) * 60 + int(parts[1]))

## Extract annotated timeline markers from an AI debrief. Prefers a structured
## {"summary":..,"markers":[{"t":83.0,"label":..}]} block, then falls back to
## scraping "<label> at M:SS" prose. Returns
## {"summary": String, "markers": [{"t": float, "label": String}, ...]} sorted.
static func parse_debrief_markers(text: String) -> Dictionary:
	var summary: String = ""
	var markers: Array = []
	var block: Variant = extract_json_block(text)
	if block is Dictionary:
		var d: Dictionary = block
		summary = String(d.get("summary", ""))
		var raw: Variant = d.get("markers", [])
		if raw is Array:
			for entry in (raw as Array):
				if not (entry is Dictionary):
					continue
				var e: Dictionary = entry
				markers.append({
					"t": maxf(0.0, float(e.get("t", 0.0))),
					"label": String(e.get("label", "")).strip_edges(),
				})
	if markers.is_empty():
		summary = text.strip_edges() if summary == "" else summary
		var regex := RegEx.new()
		regex.compile("(?i)([A-Za-z][A-Za-z0-9 '\\-]{2,60}?)\\s+at\\s+(\\d{1,2}:\\d{2})")
		for m in regex.search_all(text):
			var tc := parse_timecode(m.get_string(2))
			if tc >= 0.0:
				markers.append({"t": tc, "label": m.get_string(1).strip_edges()})
	markers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["t"]) < float(b["t"]))
	return {"summary": summary, "markers": markers}

# ---------------------------------------------------------------------------
# 5.4  Multiplayer AI commentator
# ---------------------------------------------------------------------------
## Build a compact prompt describing the current race standings for the AI
## commentator. [param entries] is an Array of
## {"name": String, "position": int, "altitude_m": float, "airspeed_ms": float}.
static func build_commentary_prompt(entries: Array) -> String:
	var rows: Array = []
	for entry in entries:
		if not (entry is Dictionary):
			continue
		rows.append(entry)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("position", 999)) < int(b.get("position", 999)))
	var lines: PackedStringArray = []
	for r in rows:
		lines.append("P%d %s alt=%sm spd=%sm/s" % [
			int(r.get("position", 0)), String(r.get("name", "?")),
			str(_round2(float(r.get("altitude_m", 0.0)))),
			str(_round2(float(r.get("airspeed_ms", 0.0)))),
		])
	return "Race standings:\n" + "\n".join(lines)

# ---------------------------------------------------------------------------
# 5.6  Token usage tracking & rate-limit awareness
# ---------------------------------------------------------------------------
## Rough token estimate (~4 chars/token) for the optional cost tracker. Good
## enough to give users a ballpark without bundling a real tokenizer.
static func estimate_token_count(text: String) -> int:
	return int(ceilf(float(text.length()) / 4.0)) if not text.is_empty() else 0

## Estimate USD cost from token counts and per-1K prices (defaults to 0 so the
## tracker stays silent until the user provides their plan's pricing).
static func estimate_cost(prompt_tokens: int, completion_tokens: int, price_in_per_1k: float = 0.0, price_out_per_1k: float = 0.0) -> float:
	return (float(prompt_tokens) / 1000.0) * price_in_per_1k + (float(completion_tokens) / 1000.0) * price_out_per_1k

## Read the cooldown (seconds) to honour after an HTTP 429 from response
## headers. Looks for a case-insensitive "Retry-After" header (integer seconds);
## falls back to [param default_sec] when absent or unparseable.
static func parse_rate_limit_cooldown(headers: PackedStringArray, default_sec: float = 20.0) -> float:
	for h in headers:
		var idx := h.find(":")
		if idx == -1:
			continue
		if h.substr(0, idx).strip_edges().to_lower() == "retry-after":
			var val := h.substr(idx + 1).strip_edges()
			if val.is_valid_int():
				return maxf(0.0, float(int(val)))
			if val.is_valid_float():
				return maxf(0.0, val.to_float())
	return maxf(0.0, default_sec)

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
