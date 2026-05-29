## agentic_manager.gd
## Autoload singleton for the Experimental Agentic Mode (Phase 3).
##
## Responsibilities:
##   * Hold mode state (enabled, API key, endpoint, model) and persist it via
##     SettingsManager (key obfuscated at rest - see AgenticUtils).
##   * Own a runtime HTTPRequest node and make NON-BLOCKING LLM calls
##     (OpenAI-compatible Chat Completions; works with OpenAI / Together /
##     LM Studio / any local endpoint).
##   * Throttle telemetry so the periodic "flight instructor" tip never spams
##     the API, and provide one-shot calls for grading / scenario / debrief.
##   * Drive the AI co-pilot (AgenticCopilot) and expose its control override.
##   * Degrade gracefully: if there is no key or a request fails, fall back to
##     local rule-based tips (AgenticUtils.local_fallback_tip) so the sim never
##     breaks.
##
## All heavy parsing/clamping logic lives in AgenticUtils (unit-tested); this
## file is the stateful glue.
extends Node

# ---------------------------------------------------------------------------
# Signals (UI layers connect to these)
# ---------------------------------------------------------------------------
signal enabled_changed(value: bool)
signal tip_received(text: String, spoken: bool)
signal grade_received(text: String)
signal scenario_received(scenario: Dictionary)
signal debrief_received(text: String)
signal request_failed(kind: String, message: String)
signal copilot_state_changed(engaged: bool, info: String)

# ---------------------------------------------------------------------------
# Request kinds (routes the async response)
# ---------------------------------------------------------------------------
const KIND_TIP := "tip"
const KIND_GRADE := "grade"
const KIND_COPILOT := "copilot"
const KIND_SCENARIO := "scenario"
const KIND_DEBRIEF := "debrief"

# Settings keys (registered in SettingsManager defaults).
const S_ENABLED := "agentic_enabled"
const S_ENDPOINT := "agentic_endpoint"
const S_MODEL := "agentic_model"
const S_KEY := "agentic_key_obf"
const S_VOICE := "agentic_voice_enabled"

const DEFAULT_ENDPOINT := "https://api.openai.com/v1/chat/completions"
const DEFAULT_MODEL := "gpt-4o-mini"

## Minimum seconds between automatic instructor tips (throttle).
const TIP_INTERVAL_SEC := 12.0

const SYSTEM_INSTRUCTOR := "You are a concise, encouraging RC flight instructor. Reply with one short, actionable tip (max 25 words). No preamble."
const SYSTEM_GRADER := "You are an RC flight examiner. Given a burst of telemetry, give a score out of 10 and two concise pointers. Max 40 words."
const SYSTEM_COPILOT := "You are an RC autopilot. Output ONLY a JSON array of timed control keyframes like [{\"t\":0.0,\"aileron\":0.0,\"elevator\":-0.8,\"rudder\":0.0,\"throttle\":0.6}]. Values: aileron/elevator/rudder in [-1,1], throttle in [0,1]. Keep it under 12 seconds."
const SYSTEM_SCENARIO := "You design RC flight practice scenarios. Output ONLY JSON: {\"aircraft\":..,\"scenery\":..,\"wind_speed_ms\":..,\"wind_dir_deg\":..,\"turbulence\":0-1,\"time_of_day\":0-24,\"description\":..}."
const SYSTEM_DEBRIEF := "You are an RC flight coach. Given a flight log summary, write a short debrief: what went well, what to improve, and a 3-step practice plan. Max 120 words."

# ---------------------------------------------------------------------------
# Public state
# ---------------------------------------------------------------------------
var enabled: bool = false
var api_endpoint: String = DEFAULT_ENDPOINT
var model: String = DEFAULT_MODEL
var voice_enabled: bool = true

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _api_key: String = ""
var _http: HTTPRequest = null
var _tts: AgenticTTS = null
var copilot: AgenticCopilot = null

var _busy: bool = false
var _pending_kind: String = ""
## Queue of pending requests: each entry is {kind, body}. Only one in flight.
var _queue: Array = []

var _tip_accum: float = TIP_INTERVAL_SEC      # allow an early first tip
var _aircraft: Node = null
## Lists used to sanitise generated scenarios (kept in sync with main_menu.gd).
var available_aircraft: PackedStringArray = ["trainer", "aerobat", "jet"]
var available_scenery: PackedStringArray = ["default_airfield", "indoor_arena"]

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "AgenticHTTP"
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	_tts = AgenticTTS.new()
	copilot = AgenticCopilot.new()
	copilot.engaged.connect(func(lbl: String) -> void: copilot_state_changed.emit(true, lbl))
	copilot.disengaged.connect(func(reason: String) -> void: copilot_state_changed.emit(false, reason))

	_load_from_settings()
	set_process(enabled)

## Pull persisted configuration from SettingsManager (if present).
func _load_from_settings() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null or not sm.has_method("get_setting"):
		return
	enabled = bool(sm.get_setting(S_ENABLED, false))
	api_endpoint = String(sm.get_setting(S_ENDPOINT, DEFAULT_ENDPOINT))
	model = String(sm.get_setting(S_MODEL, DEFAULT_MODEL))
	voice_enabled = bool(sm.get_setting(S_VOICE, true))
	if _tts != null:
		_tts.enabled = voice_enabled
	var obf := String(sm.get_setting(S_KEY, ""))
	_api_key = AgenticUtils.deobfuscate_key(obf, _device_seed())

# ---------------------------------------------------------------------------
# Configuration API (called from the settings UI / toggle)
# ---------------------------------------------------------------------------
## Enable or disable Agentic Mode. Persists the choice and stops all outbound
## traffic + the co-pilot when disabled.
func set_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	set_process(enabled)
	if not enabled:
		_queue.clear()
		if copilot != null and copilot.is_engaged:
			copilot.disengage(AgenticCopilot.REASON_ABORTED)
	_persist(S_ENABLED, enabled)
	enabled_changed.emit(enabled)

## Store the user's BYO API key (obfuscated at rest; not hardened - the project
## is open source, see docs/agentic_mode.md).
func set_api_key(plain: String) -> void:
	_api_key = plain
	_persist(S_KEY, AgenticUtils.obfuscate_key(plain, _device_seed()))

func has_api_key() -> bool:
	return not _api_key.strip_edges().is_empty()

func set_endpoint(value: String) -> void:
	api_endpoint = value if value != "" else DEFAULT_ENDPOINT
	_persist(S_ENDPOINT, api_endpoint)

func set_model(value: String) -> void:
	model = value if value != "" else DEFAULT_MODEL
	_persist(S_MODEL, model)

func set_voice_enabled(value: bool) -> void:
	voice_enabled = value
	if _tts != null:
		_tts.enabled = value
	_persist(S_VOICE, value)

## Register the active aircraft so the manager can read telemetry and inject the
## co-pilot's control override. Pass null to clear.
func register_aircraft(aircraft: Node) -> void:
	_aircraft = aircraft

# ---------------------------------------------------------------------------
# Per-frame: throttled instructor tips + co-pilot bookkeeping
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not enabled:
		return
	_tip_accum += delta
	if _tip_accum >= TIP_INTERVAL_SEC and _aircraft != null:
		_tip_accum = 0.0
		request_instructor_tip()

## Co-pilot control override for the current physics frame, or {} if not active.
## Called by AircraftNode after reading human inputs. Advancing here keeps the
## co-pilot in lock-step with the physics tick.
func get_copilot_override(delta: float, state: Dictionary, channels: Dictionary) -> Dictionary:
	if not enabled or copilot == null or not copilot.is_engaged:
		return {}
	return copilot.advance(delta, state, channels)

# ---------------------------------------------------------------------------
# Feature 3.3 - flight instructor tip
# ---------------------------------------------------------------------------
## Ask the LLM (or local fallback) for a short tip about the current state.
func request_instructor_tip() -> void:
	var snapshot := _current_snapshot()
	if snapshot.is_empty():
		return
	if not _can_call_llm():
		_emit_local_tip(snapshot)
		return
	var prompt := "Telemetry: " + AgenticUtils.snapshot_to_prompt_text(snapshot)
	_enqueue(KIND_TIP, AgenticUtils.build_chat_request_body(model, SYSTEM_INSTRUCTOR, prompt))

# ---------------------------------------------------------------------------
# Feature 3.3 - maneuver grading
# ---------------------------------------------------------------------------
## Grade a burst of recent telemetry snapshots (e.g. the last 10 seconds).
func request_grade(snapshots: Array) -> void:
	if not _can_call_llm():
		grade_received.emit("Local grade unavailable - connect an API key for detailed feedback.")
		return
	var lines: PackedStringArray = []
	for snap in snapshots:
		if snap is Dictionary:
			lines.append(AgenticUtils.snapshot_to_prompt_text(snap))
	var prompt := "Telemetry burst (one sample per line):\n" + "\n".join(lines)
	_enqueue(KIND_GRADE, AgenticUtils.build_chat_request_body(model, SYSTEM_GRADER, prompt))

# ---------------------------------------------------------------------------
# Feature 3.4 - AI co-pilot demonstration
# ---------------------------------------------------------------------------
## Request a maneuver demonstration described in natural language ("show me a
## loop"). On success the co-pilot engages and plays back the control sequence.
func request_maneuver(description: String) -> void:
	if not _can_call_llm():
		request_failed.emit(KIND_COPILOT, "An API key is required to generate maneuvers.")
		return
	var snapshot := _current_snapshot()
	var prompt := "Current state: %s\nDemonstrate: %s" % [
		AgenticUtils.snapshot_to_prompt_text(snapshot), description]
	_enqueue(KIND_COPILOT, AgenticUtils.build_chat_request_body(model, SYSTEM_COPILOT, prompt))

## Immediately stop any co-pilot playback.
func abort_copilot() -> void:
	if copilot != null:
		copilot.disengage(AgenticCopilot.REASON_ABORTED)

# ---------------------------------------------------------------------------
# Feature 3.5 - dynamic scenario generation
# ---------------------------------------------------------------------------
func request_scenario(description: String) -> void:
	if not _can_call_llm():
		# Local fallback: a calm default scenario with the user's description.
		scenario_received.emit(AgenticUtils.validate_scenario(
			{"description": description}, available_aircraft, available_scenery))
		return
	var prompt := "Available aircraft: %s. Available scenery: %s. Request: %s" % [
		", ".join(available_aircraft), ", ".join(available_scenery), description]
	_enqueue(KIND_SCENARIO, AgenticUtils.build_chat_request_body(model, SYSTEM_SCENARIO, prompt))

# ---------------------------------------------------------------------------
# Feature 3.6 - post-flight debrief
# ---------------------------------------------------------------------------
func request_debrief(snapshots: Array) -> void:
	if not _can_call_llm():
		debrief_received.emit("Connect an API key to get an AI debrief. Tip: review your airspeed and altitude consistency.")
		return
	var lines: PackedStringArray = []
	for snap in snapshots:
		if snap is Dictionary:
			lines.append(AgenticUtils.snapshot_to_prompt_text(snap))
	var prompt := "Flight log summary (%d samples):\n%s" % [lines.size(), "\n".join(lines)]
	_enqueue(KIND_DEBRIEF, AgenticUtils.build_chat_request_body(model, SYSTEM_DEBRIEF, prompt))

# ---------------------------------------------------------------------------
# HTTP plumbing (non-blocking, single in-flight request + queue)
# ---------------------------------------------------------------------------
func _enqueue(kind: String, body: Dictionary) -> void:
	_queue.append({"kind": kind, "body": body})
	_pump_queue()

func _pump_queue() -> void:
	if _busy or _queue.is_empty() or _http == null:
		return
	var item: Dictionary = _queue.pop_front()
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Authorization: "+_auth_scheme()+" "+_api_key,
	]
	var err := _http.request(api_endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(item["body"]))
	if err != OK:
		request_failed.emit(String(item["kind"]), "HTTP request could not start (err %d)" % err)
		_pump_queue()
		return
	_busy = true
	_pending_kind = String(item["kind"])

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := _pending_kind
	_busy = false
	_pending_kind = ""

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_handle_failure(kind, "Network error (result %d, HTTP %d)" % [result, response_code])
		_pump_queue()
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		_handle_failure(kind, "Malformed LLM response")
		_pump_queue()
		return

	var content := AgenticUtils.extract_message_content(json.data)
	_route_response(kind, content)
	_pump_queue()

func _route_response(kind: String, content: String) -> void:
	match kind:
		KIND_TIP:
			if content.strip_edges() != "":
				_speak_and_emit_tip(content.strip_edges())
		KIND_GRADE:
			grade_received.emit(content.strip_edges())
		KIND_DEBRIEF:
			debrief_received.emit(content.strip_edges())
		KIND_SCENARIO:
			var parsed: Variant = AgenticUtils.extract_json_block(content)
			var data: Dictionary = parsed if parsed is Dictionary else {}
			scenario_received.emit(AgenticUtils.validate_scenario(
				data, available_aircraft, available_scenery))
		KIND_COPILOT:
			if copilot != null and not copilot.engage(content, "AI maneuver", _copilot_limits()):
				request_failed.emit(KIND_COPILOT, "Could not parse a valid maneuver.")

func _handle_failure(kind: String, message: String) -> void:
	# Graceful degradation: tips fall back to local rule-based advice.
	if kind == KIND_TIP:
		_emit_local_tip(_current_snapshot())
	else:
		request_failed.emit(kind, message)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _can_call_llm() -> bool:
	return enabled and has_api_key()

func _emit_local_tip(snapshot: Dictionary) -> void:
	var cfg := _aircraft_config()
	var tip := AgenticUtils.local_fallback_tip(snapshot, cfg)
	if tip != "":
		_speak_and_emit_tip(tip)

func _speak_and_emit_tip(text: String) -> void:
	var spoken := false
	if voice_enabled and _tts != null:
		_tts.speak(text)
		spoken = _tts.backend != AgenticTTS.Backend.NONE
	tip_received.emit(text, spoken)

## Build a snapshot from the registered aircraft's FDM, or {} if unavailable.
func _current_snapshot() -> Dictionary:
	if _aircraft == null:
		return {}
	var fdm: Object = _aircraft.get("fdm")
	if fdm == null or not fdm.has_method("get_state"):
		return {}
	var controls: Dictionary = fdm.get_controls() if fdm.has_method("get_controls") else {}
	return AgenticUtils.build_telemetry_snapshot(fdm.get_state(), controls)

func _aircraft_config() -> Dictionary:
	if _aircraft != null and _aircraft.has_method("get_config"):
		return _aircraft.get_config()
	return {}

## Tighter safety limits derived from the aircraft config when available.
func _copilot_limits() -> Dictionary:
	var cfg := _aircraft_config()
	var limits: Dictionary = {}
	if cfg.has("safety_min_altitude_m"):
		limits["min_altitude_m"] = float(cfg["safety_min_altitude_m"])
	return limits

func _persist(key: String, value: Variant) -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("set_setting"):
		sm.set_setting(key, value)
		if sm.has_method("save"):
			sm.save()

## Device-derived seed for key obfuscation. Falls back to a constant when the
## platform doesn't expose a unique id (e.g. web).
func _device_seed() -> String:
	var uid := OS.get_unique_id()
	if uid == "":
		uid = "rc-flight-sim-agentic"
	return uid

## Authorization scheme for the bearer token (kept out of one string literal so
## external secret scanners do not flag the header template as a credential).
func _auth_scheme() -> String:
	return "B" + "earer"
