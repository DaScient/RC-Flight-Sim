## test_agentic_utils.gd
## Unit tests for AgenticUtils (Experimental Agentic Mode, Phase 3).
## Pure-function tests, no scene/HTTP required. Run via tests/run_tests.gd.
class_name TestAgenticUtils
extends RefCounted

# ---------------------------------------------------------------------------
# Telemetry snapshot
# ---------------------------------------------------------------------------
func test_snapshot_extracts_fields(t) -> void:
	var state := {
		"airspeed_ms": 12.345,
		"altitude_m": 30.0,
		"euler_deg": Vector3(10.0, 90.0, -5.0),
		"velocity": Vector3(0.0, 1.5, 0.0),
		"engine_rpm": 8000.0,
		"on_ground": false,
	}
	var controls := {"aileron": 0.5, "elevator": -0.25, "rudder": 0.0, "throttle": 0.75}
	var snap := AgenticUtils.build_telemetry_snapshot(state, controls)
	t.assert_approx(snap["airspeed_ms"], 12.35, "airspeed rounded to 2dp", 0.001)
	t.assert_approx(snap["roll_deg"], 10.0, "roll from euler.x")
	t.assert_approx(snap["pitch_deg"], -5.0, "pitch from euler.z")
	t.assert_approx(snap["climb_ms"], 1.5, "climb from velocity.y")
	t.assert_true(snap["on_ground"] == false, "on_ground preserved")

func test_snapshot_prompt_text_is_sorted(t) -> void:
	var text := AgenticUtils.snapshot_to_prompt_text({"zebra": 1, "alpha": 2})
	t.assert_true(text.find("alpha") < text.find("zebra"), "keys sorted alphabetically")

# ---------------------------------------------------------------------------
# Control clamping & safety
# ---------------------------------------------------------------------------
func test_clamp_controls_ranges(t) -> void:
	var c := AgenticUtils.clamp_control_inputs({"aileron": 5.0, "elevator": -9.0, "rudder": 0.3, "throttle": 2.0})
	t.assert_approx(c["aileron"], 1.0, "aileron clamped to +1")
	t.assert_approx(c["elevator"], -1.0, "elevator clamped to -1")
	t.assert_approx(c["rudder"], 0.3, "rudder passthrough")
	t.assert_approx(c["throttle"], 1.0, "throttle clamped to +1")

func test_clamp_controls_throttle_floor(t) -> void:
	var c := AgenticUtils.clamp_control_inputs({"throttle": -0.5})
	t.assert_approx(c["throttle"], 0.0, "throttle floored at 0")

func test_clamp_controls_defaults_neutral(t) -> void:
	var c := AgenticUtils.clamp_control_inputs({})
	t.assert_approx(c["aileron"], 0.0, "missing aileron -> 0")
	t.assert_true(not c.has("bogus"), "unknown keys dropped")

func test_dangerous_attitude_roll(t) -> void:
	t.assert_true(AgenticUtils.is_dangerous_attitude({"euler_deg": Vector3(120.0, 0.0, 0.0)}),
		"excessive roll is dangerous")
	t.assert_true(not AgenticUtils.is_dangerous_attitude({"euler_deg": Vector3(10.0, 0.0, 0.0), "altitude_m": 50.0}),
		"level flight is safe")

func test_dangerous_attitude_low_altitude(t) -> void:
	t.assert_true(AgenticUtils.is_dangerous_attitude({"altitude_m": 0.5, "on_ground": false}),
		"low airborne altitude is dangerous")
	t.assert_true(not AgenticUtils.is_dangerous_attitude({"altitude_m": 0.5, "on_ground": true}),
		"low altitude on ground is fine")

func test_detect_user_override(t) -> void:
	t.assert_true(AgenticUtils.detect_user_override({"aileron": 0.9}), "big stick -> override")
	t.assert_true(not AgenticUtils.detect_user_override({"aileron": 0.05, "elevator": 0.0, "rudder": 0.0}),
		"small jitter -> no override")

# ---------------------------------------------------------------------------
# Maneuver sequence parsing & sampling
# ---------------------------------------------------------------------------
func test_parse_maneuver_sorts_and_clamps(t) -> void:
	var seq := AgenticUtils.parse_maneuver_sequence('[{"t":1.0,"elevator":-5.0},{"t":0.0,"elevator":0.0}]')
	t.assert_true(seq.size() == 2, "two frames parsed")
	t.assert_approx(seq[0]["t"], 0.0, "frames sorted by time")
	t.assert_approx(seq[1]["elevator"], -1.0, "clamped elevator")

func test_parse_maneuver_wrapper_object(t) -> void:
	var seq := AgenticUtils.parse_maneuver_sequence('{"sequence":[{"t":0.0,"aileron":0.5}]}')
	t.assert_true(seq.size() == 1, "unwrapped sequence key")

func test_parse_maneuver_invalid(t) -> void:
	t.assert_true(AgenticUtils.parse_maneuver_sequence("not json").is_empty(), "garbage -> empty")
	t.assert_true(AgenticUtils.parse_maneuver_sequence('{"foo":1}').is_empty(), "no sequence -> empty")

func test_sample_maneuver_interpolates(t) -> void:
	var seq := AgenticUtils.parse_maneuver_sequence('[{"t":0.0,"elevator":0.0},{"t":2.0,"elevator":-1.0}]')
	var mid := AgenticUtils.sample_maneuver(seq, 1.0)
	t.assert_approx(mid["elevator"], -0.5, "midpoint interpolation")
	var before := AgenticUtils.sample_maneuver(seq, -1.0)
	t.assert_approx(before["elevator"], 0.0, "clamps to first frame")
	var after := AgenticUtils.sample_maneuver(seq, 99.0)
	t.assert_approx(after["elevator"], -1.0, "clamps to last frame")

func test_maneuver_duration(t) -> void:
	var seq := AgenticUtils.parse_maneuver_sequence('[{"t":0.0},{"t":3.5}]')
	t.assert_approx(AgenticUtils.maneuver_duration(seq), 3.5, "duration = last frame time")
	t.assert_approx(AgenticUtils.maneuver_duration([]), 0.0, "empty duration 0")

# ---------------------------------------------------------------------------
# Local fallback tips
# ---------------------------------------------------------------------------
func test_local_tip_stall(t) -> void:
	var tip := AgenticUtils.local_fallback_tip({"airspeed_ms": 3.0, "altitude_m": 50.0, "on_ground": false})
	t.assert_true(tip.to_lower().find("stall") != -1, "warns about stall")

func test_local_tip_nominal_empty(t) -> void:
	var tip := AgenticUtils.local_fallback_tip(
		{"airspeed_ms": 20.0, "altitude_m": 50.0, "aoa_deg": 2.0, "on_ground": false, "euler_deg": Vector3.ZERO})
	t.assert_true(tip == "", "nominal flight -> no tip")

func test_local_tip_on_ground_empty(t) -> void:
	var tip := AgenticUtils.local_fallback_tip({"airspeed_ms": 0.0, "on_ground": true})
	t.assert_true(tip == "", "on ground -> no tip")

# ---------------------------------------------------------------------------
# LLM request / response helpers
# ---------------------------------------------------------------------------
func test_build_request_body(t) -> void:
	var body := AgenticUtils.build_chat_request_body("gpt-x", "sys", "usr", false)
	t.assert_true(body["model"] == "gpt-x", "model set")
	t.assert_true((body["messages"] as Array).size() == 2, "system + user messages")
	t.assert_true(body["stream"] == false, "stream flag passthrough")

func test_extract_message_content(t) -> void:
	var resp := {"choices": [{"message": {"content": "hello"}}]}
	t.assert_true(AgenticUtils.extract_message_content(resp) == "hello", "extracts message content")
	t.assert_true(AgenticUtils.extract_message_content({}) == "", "missing choices -> empty")

func test_extract_json_block(t) -> void:
	var parsed = AgenticUtils.extract_json_block("Sure! Here it is: {\"a\":1} cheers")
	t.assert_true(parsed is Dictionary and parsed["a"] == 1, "extracts embedded json object")
	var arr = AgenticUtils.extract_json_block("```json\n[1,2,3]\n```")
	t.assert_true(arr is Array and (arr as Array).size() == 3, "extracts embedded json array")
	t.assert_true(AgenticUtils.extract_json_block("no json here") == null, "no json -> null")

# ---------------------------------------------------------------------------
# Scenario validation
# ---------------------------------------------------------------------------
func test_validate_scenario_clamps_and_whitelists(t) -> void:
	var avail_a: PackedStringArray = ["trainer", "jet"]
	var avail_s: PackedStringArray = ["default_airfield"]
	var s := AgenticUtils.validate_scenario(
		{"aircraft": "ufo", "scenery": "moon", "wind_speed_ms": 999.0, "turbulence": 5.0, "time_of_day": 30.0},
		avail_a, avail_s)
	t.assert_true(s["aircraft"] == "trainer", "unknown aircraft falls back to first")
	t.assert_true(s["scenery"] == "default_airfield", "unknown scenery falls back")
	t.assert_approx(s["wind_speed_ms"], 25.0, "wind clamped")
	t.assert_approx(s["turbulence"], 1.0, "turbulence clamped")
	t.assert_approx(s["time_of_day"], 24.0, "time clamped")

func test_validate_scenario_accepts_valid(t) -> void:
	var s := AgenticUtils.validate_scenario(
		{"aircraft": "jet", "scenery": "default_airfield", "wind_speed_ms": 5.0},
		["trainer", "jet"], ["default_airfield"])
	t.assert_true(s["aircraft"] == "jet", "valid aircraft kept")

# ---------------------------------------------------------------------------
# Key obfuscation round-trip
# ---------------------------------------------------------------------------
func test_key_obfuscation_roundtrip(t) -> void:
	var key := "sk-test-1234567890"
	var enc := AgenticUtils.obfuscate_key(key, "device-seed")
	t.assert_true(enc != key, "encoded differs from plaintext")
	t.assert_true(AgenticUtils.deobfuscate_key(enc, "device-seed") == key, "round-trips back")

func test_key_obfuscation_empty(t) -> void:
	t.assert_true(AgenticUtils.obfuscate_key("", "seed") == "", "empty key -> empty")
	t.assert_true(AgenticUtils.deobfuscate_key("", "seed") == "", "empty enc -> empty")
