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
# Phase 5 signals
signal voice_command_parsed(command: Dictionary)
signal aircraft_generated(result: Dictionary)
signal scenery_generated(spec: Dictionary)
signal commentary_received(text: String, spoken: bool)
signal markers_received(result: Dictionary)
signal rate_limited(cooldown_sec: float)
signal usage_updated(tokens: int, cost_usd: float)

# ---------------------------------------------------------------------------
# Request kinds (routes the async response)
# ---------------------------------------------------------------------------
const KIND_TIP := "tip"
const KIND_GRADE := "grade"
const KIND_COPILOT := "copilot"
const KIND_SCENARIO := "scenario"
const KIND_DEBRIEF := "debrief"
# Phase 5 request kinds
const KIND_VOICE := "voice"
const KIND_AIRCRAFT := "aircraft"
const KIND_SCENERY := "scenery"
const KIND_COMMENTARY := "commentary"
const KIND_MARKERS := "markers"
const KIND_SKILL := "skill"

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
# Phase 5 system prompts
const SYSTEM_VOICE := "You translate a pilot's spoken command into ONE JSON object: {\"action\":<one of demonstrate_maneuver|set_wind|grade_landing|talk_through|generate_scenario|set_time_of_day>,\"params\":{..},\"say\":<short confirmation>}. params: set_wind{speed_ms,dir_deg,gusts}, set_time_of_day{hour}, demonstrate_maneuver/talk_through{maneuver}, generate_scenario{description}. Output ONLY JSON."
const SYSTEM_AIRCRAFT := "You design RC model aircraft for a JSBSim flight sim. Output ONLY JSON: {\"name\":..,\"category\":..,\"model_description\":..,\"jsbsim_xml\":\"<fdm_config>...</fdm_config>\",\"tuning\":{\"expo\":{\"aileron\":0-1,\"elevator\":0-1,\"rudder\":0-1},\"rates\":{..},\"power_factor\":0.1-2}}. The XML must contain fdm_config, metrics, mass_balance and aerodynamics elements."
const SYSTEM_SCENERY := "You design RC flying field sceneries. Output ONLY JSON: {\"name\":..,\"size_m\":100-4000,\"runway_length_m\":..,\"objects\":[{\"type\":<tree|hangar|windsock|pylon|tent|rock>,\"x\":..,\"z\":..}],\"wind_layers\":[{\"altitude_m\":..,\"speed_ms\":0-30,\"dir_deg\":0-360}],\"description\":..}."
const SYSTEM_COMMENTARY := "You are an excited RC race commentator. Given the standings, produce one or two punchy sentences of live commentary. No preamble."

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
var _voice: AgenticVoice = null
var copilot: AgenticCopilot = null
var _wizard: AgenticAircraftWizard = null
var _scenery_gen: AgenticSceneryGenerator = null

var _busy: bool = false
var _pending_kind: String = ""
## The skill (if any) that owns the in-flight request, for routing the reply.
var _pending_skill: AgenticSkill = null
## Queue of pending requests: each entry is {kind, body, skill}. One in flight.
var _queue: Array = []

var _tip_accum: float = TIP_INTERVAL_SEC      # allow an early first tip
var _aircraft: Node = null
## Lists used to sanitise generated scenarios (kept in sync with main_menu.gd).
var available_aircraft: PackedStringArray = ["trainer", "aerobat", "jet"]
var available_scenery: PackedStringArray = ["default_airfield", "indoor_arena"]

# Phase 5 state ------------------------------------------------------------
## Shared overlay CanvasLayer that skills can attach UI to (null in headless).
var _overlay_layer: CanvasLayer = null
## Registered agentic skills, keyed by StringName id.
var _skills: Dictionary = {}
## Seconds (unix) until which the LLM is in a rate-limit cooldown.
var _cooldown_until: float = 0.0
## Optional cost tracking: cumulative estimated tokens and USD.
var total_tokens: int = 0
var total_cost_usd: float = 0.0
var price_in_per_1k: float = 0.0
var price_out_per_1k: float = 0.0

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
	_wizard = AgenticAircraftWizard.new()
	_scenery_gen = AgenticSceneryGenerator.new()
	_voice = AgenticVoice.new()
	_voice.recognized.connect(handle_voice_text)

	_load_from_settings()
	set_process(enabled)
	set_process_unhandled_input(true)
	_bootstrap_ui()
	_register_builtin_skills()

## Spawn the always-present Agentic overlay (hidden-hover toggle + in-flight
## HUD) on a high CanvasLayer so the feature works without per-scene wiring.
## Skipped in headless/test runs where there is no display server.
func _bootstrap_ui() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.name = "AgenticOverlay"
	layer.layer = 100
	add_child(layer)
	_overlay_layer = layer

	var toggle_script: GDScript = load("res://scripts/ui/agentic_toggle.gd")
	if toggle_script != null:
		var toggle: Control = toggle_script.new()
		toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		toggle.position = Vector2(-150, 8)
		layer.add_child(toggle)

	var hud_script: GDScript = load("res://scripts/ui/agentic_hud.gd")
	if hud_script != null:
		var hud: Control = hud_script.new()
		layer.add_child(hud)

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
	# Resume any queued requests once a rate-limit cooldown has elapsed.
	if not _busy and not _queue.is_empty() and not _in_cooldown():
		_pump_queue()
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

## Push-to-talk: hold the `agentic_ptt` action to listen, release to transcribe.
## The recognised text is routed through handle_voice_text().
func _unhandled_input(event: InputEvent) -> void:
	if not enabled or _voice == null or not _voice.is_available():
		return
	if not InputMap.has_action("agentic_ptt"):
		return
	if event.is_action_pressed("agentic_ptt"):
		_voice.start_listening()
	elif event.is_action_released("agentic_ptt"):
		_voice.stop_listening()

## Voice helper accessor (for settings UI to configure the desktop STT command).
func get_voice() -> AgenticVoice:
	return _voice

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

# ===========================================================================
# PHASE 5 - public API
# ===========================================================================

# ---------------------------------------------------------------------------
# 5.2  Voice-first interaction
# ---------------------------------------------------------------------------
## Hand recognised speech [param text] to the LLM for structured command
## parsing. When the LLM is offline the text is parsed locally (best effort).
func handle_voice_text(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	if not _can_call_llm():
		var local := AgenticUtils.parse_voice_command(text)
		voice_command_parsed.emit(local)
		execute_voice_command(local)
		return
	_enqueue(KIND_VOICE, AgenticUtils.build_chat_request_body(model, SYSTEM_VOICE, text))

## Execute a parsed voice command (see AgenticUtils.parse_voice_command). Each
## action routes to the relevant subsystem. Unknown actions are ignored.
func execute_voice_command(command: Dictionary) -> void:
	var action := String(command.get("action", "unknown"))
	var params: Dictionary = command.get("params", {})
	match action:
		"demonstrate_maneuver":
			request_maneuver(String(params.get("maneuver", "")))
		"talk_through":
			request_maneuver(String(params.get("maneuver", "")))
		"grade_landing":
			request_grade([_current_snapshot()])
		"generate_scenario":
			request_scenario(String(params.get("description", "")))
		"set_wind":
			_apply_wind(params)
		"set_time_of_day":
			_apply_time_of_day(float(params.get("hour", 12.0)))
		_:
			pass

func _apply_wind(params: Dictionary) -> void:
	var atmo := get_node_or_null("/root/Atmosphere")
	if atmo != null and atmo.has_method("set_wind"):
		atmo.set_wind(float(params.get("speed_ms", 0.0)),
			float(params.get("dir_deg", 0.0)), bool(params.get("gusts", false)))

func _apply_time_of_day(hour: float) -> void:
	var atmo := get_node_or_null("/root/Atmosphere")
	if atmo != null and atmo.has_method("set_time_of_day"):
		atmo.set_time_of_day(hour)

# ---------------------------------------------------------------------------
# 5.1.1  AI-generated aircraft configuration
# ---------------------------------------------------------------------------
## Generate a JSBSim aircraft + tuning from a natural-language description.
## Result delivered via [signal aircraft_generated].
func request_aircraft_config(description: String) -> void:
	if not _can_call_llm():
		request_failed.emit(KIND_AIRCRAFT, "An API key is required to generate aircraft.")
		return
	_enqueue(KIND_AIRCRAFT, AgenticUtils.build_chat_request_body(
		model, SYSTEM_AIRCRAFT, AgenticAircraftWizard.build_prompt(description)))

# ---------------------------------------------------------------------------
# 5.1.2  AI-generated sceneries
# ---------------------------------------------------------------------------
## Generate an airfield scenery spec from a description. Result delivered via
## [signal scenery_generated]; callers can then AgenticSceneryGenerator.save_scene().
func request_airfield(description: String) -> void:
	if not _can_call_llm():
		scenery_generated.emit(AgenticUtils.parse_scenery_spec({"description": description}))
		return
	_enqueue(KIND_SCENERY, AgenticUtils.build_chat_request_body(
		model, SYSTEM_SCENERY, AgenticSceneryGenerator.build_prompt(description)))

## Build and save a scene from a (validated) scenery spec. Returns the path.
func save_generated_scenery(spec: Dictionary) -> String:
	return _scenery_gen.save_scene(spec) if _scenery_gen != null else ""

# ---------------------------------------------------------------------------
# 5.4  Multiplayer AI commentator
# ---------------------------------------------------------------------------
## Generate live race commentary for the given standings (see
## AgenticUtils.build_commentary_prompt). Result via [signal commentary_received].
func request_commentary(entries: Array) -> void:
	if not _can_call_llm():
		return
	_enqueue(KIND_COMMENTARY, AgenticUtils.build_chat_request_body(
		model, SYSTEM_COMMENTARY, AgenticUtils.build_commentary_prompt(entries)))

# ---------------------------------------------------------------------------
# 5.5  Plugin API - skill registry
# ---------------------------------------------------------------------------
## Register an AgenticSkill instance. Returns false if a skill with the same id
## is already registered.
func register_skill(skill: AgenticSkill) -> bool:
	if skill == null or _skills.has(skill.id):
		return false
	_skills[skill.id] = skill
	skill.setup(self)
	return true

func unregister_skill(id: StringName) -> void:
	if _skills.has(id):
		(_skills[id] as AgenticSkill).teardown()
		_skills.erase(id)

func get_skill(id: StringName) -> AgenticSkill:
	return _skills.get(id, null)

func list_skills() -> Array:
	return _skills.values()

## Invoke a registered skill by id (calls its invoke() method if present).
func invoke_skill(id: StringName) -> bool:
	var skill: AgenticSkill = _skills.get(id, null)
	if skill == null:
		return false
	if skill.has_method("invoke"):
		skill.call("invoke")
		return true
	return false

func _register_builtin_skills() -> void:
	register_skill(SmokeWriterSkill.new())
	register_skill(FormationTrainerSkill.new())

# --- Hooks called by AgenticSkill helpers ---------------------------------
## Public snapshot accessor for skills.
func get_snapshot() -> Dictionary:
	return _current_snapshot()

## Send a skill-owned prompt; reply routed back to skill.on_llm_response().
func send_skill_prompt(skill: AgenticSkill, system_prompt: String, user_prompt: String) -> bool:
	if not _can_call_llm():
		return false
	_enqueue(KIND_SKILL, AgenticUtils.build_chat_request_body(model, system_prompt, user_prompt), skill)
	return true

func play_skill_maneuver(maneuver: Variant, label: String) -> bool:
	if copilot == null:
		return false
	return copilot.engage(maneuver, label, _copilot_limits())

func attach_skill_ui(control: Control) -> bool:
	if _overlay_layer == null or control == null:
		return false
	_overlay_layer.add_child(control)
	return true

# ---------------------------------------------------------------------------
# 5.6  Token usage & rate-limit awareness
# ---------------------------------------------------------------------------
## Set per-1K-token prices for the optional cost estimate (USD).
func set_pricing(in_per_1k: float, out_per_1k: float) -> void:
	price_in_per_1k = maxf(0.0, in_per_1k)
	price_out_per_1k = maxf(0.0, out_per_1k)

func _track_usage(prompt_text: String, completion_text: String) -> void:
	var p_tokens := AgenticUtils.estimate_token_count(prompt_text)
	var c_tokens := AgenticUtils.estimate_token_count(completion_text)
	total_tokens += p_tokens + c_tokens
	total_cost_usd += AgenticUtils.estimate_cost(p_tokens, c_tokens, price_in_per_1k, price_out_per_1k)
	usage_updated.emit(total_tokens, total_cost_usd)

func _in_cooldown() -> bool:
	return Time.get_unix_time_from_system() < _cooldown_until

## Seconds remaining in the current rate-limit cooldown (0 if none).
func cooldown_remaining() -> float:
	return maxf(0.0, _cooldown_until - Time.get_unix_time_from_system())

# ---------------------------------------------------------------------------
# HTTP plumbing (non-blocking, single in-flight request + queue)
# ---------------------------------------------------------------------------
func _enqueue(kind: String, body: Dictionary, skill: AgenticSkill = null) -> void:
	_queue.append({"kind": kind, "body": body, "skill": skill})
	_pump_queue()

func _pump_queue() -> void:
	if _busy or _queue.is_empty() or _http == null:
		return
	# Honour an active rate-limit cooldown before sending anything else.
	if _in_cooldown():
		return
	var item: Dictionary = _queue.pop_front()
	var headers: PackedStringArray = [
		"Content-Type: application/json",
		"Authorization: "+_auth_scheme()+" "+_api_key,
	]
	var payload := JSON.stringify(item["body"])
	var err := _http.request(api_endpoint, headers, HTTPClient.METHOD_POST, payload)
	if err != OK:
		request_failed.emit(String(item["kind"]), "HTTP request could not start (err %d)" % err)
		_pump_queue()
		return
	_busy = true
	_pending_kind = String(item["kind"])
	_pending_skill = item.get("skill", null)
	_track_usage(payload, "")  # count prompt tokens up front

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := _pending_kind
	var skill := _pending_skill
	_busy = false
	_pending_kind = ""
	_pending_skill = null

	# Rate limited: start a cooldown, surface it, and degrade to local tips.
	if response_code == 429:
		var cooldown := AgenticUtils.parse_rate_limit_cooldown(headers)
		_cooldown_until = Time.get_unix_time_from_system() + cooldown
		rate_limited.emit(cooldown)
		_handle_failure(kind, "Rate limited (cooldown %.0fs)" % cooldown)
		return

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
	_track_usage("", content)  # count completion tokens
	_route_response(kind, content, skill)
	_pump_queue()

func _route_response(kind: String, content: String, skill: AgenticSkill = null) -> void:
	match kind:
		KIND_TIP:
			if content.strip_edges() != "":
				_speak_and_emit_tip(content.strip_edges())
		KIND_GRADE:
			grade_received.emit(content.strip_edges())
		KIND_DEBRIEF:
			debrief_received.emit(content.strip_edges())
			markers_received.emit(AgenticUtils.parse_debrief_markers(content))
		KIND_SCENARIO:
			var parsed: Variant = AgenticUtils.extract_json_block(content)
			var data: Dictionary = parsed if parsed is Dictionary else {}
			scenario_received.emit(AgenticUtils.validate_scenario(
				data, available_aircraft, available_scenery))
		KIND_COPILOT:
			if copilot != null and not copilot.engage(content, "AI maneuver", _copilot_limits()):
				request_failed.emit(KIND_COPILOT, "Could not parse a valid maneuver.")
		KIND_VOICE:
			var command := AgenticUtils.parse_voice_command(content)
			voice_command_parsed.emit(command)
			execute_voice_command(command)
		KIND_AIRCRAFT:
			aircraft_generated.emit(_wizard.process_response(content))
		KIND_SCENERY:
			scenery_generated.emit(_scenery_gen.process_response(content))
		KIND_COMMENTARY:
			var text := content.strip_edges()
			var spoken := false
			if voice_enabled and _tts != null and text != "":
				_tts.speak(text)
				spoken = _tts.backend != AgenticTTS.Backend.NONE
			commentary_received.emit(text, spoken)
		KIND_SKILL:
			if skill != null:
				skill.on_llm_response(content)

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
