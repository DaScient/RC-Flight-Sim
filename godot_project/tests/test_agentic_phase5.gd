## test_agentic_phase5.gd
## Unit tests for the Phase 5 agentic logic added to AgenticUtils:
## AI aircraft/scenery generation, voice command parsing, flight replay
## analysis, multiplayer commentary, and token/rate-limit helpers.
## Pure-function tests, no scene/HTTP required. Run via tests/run_tests.gd.
class_name TestAgenticPhase5
extends RefCounted

# ---------------------------------------------------------------------------
# 5.1.1  Aircraft config generation
# ---------------------------------------------------------------------------
func test_validate_xml_accepts_minimal_jsbsim(t) -> void:
	var xml := "<?xml version=\"1.0\"?><fdm_config><metrics/><mass_balance/><aerodynamics/></fdm_config>"
	var res := AgenticUtils.validate_xml(xml)
	t.assert_true(res["valid"], "minimal JSBSim doc is valid")
	t.assert_true((res["missing"] as PackedStringArray).is_empty(), "nothing missing")

func test_validate_xml_reports_missing(t) -> void:
	var res := AgenticUtils.validate_xml("<fdm_config><metrics/></fdm_config>")
	t.assert_true(not res["valid"], "incomplete doc invalid")
	t.assert_true((res["missing"] as PackedStringArray).has("aerodynamics"), "aerodynamics flagged missing")

func test_validate_xml_rejects_garbage(t) -> void:
	t.assert_true(not AgenticUtils.validate_xml("not xml <<<")["valid"], "garbage invalid")
	t.assert_true(not AgenticUtils.validate_xml("")["valid"], "empty invalid")

func test_build_aircraft_tuning_clamps(t) -> void:
	var tune := AgenticUtils.build_aircraft_tuning({
		"expo": {"aileron": 5.0}, "rates": {"elevator": -2.0}, "power_factor": 9.0})
	t.assert_approx(tune["expo"]["aileron"], 1.0, "expo clamped to 1")
	t.assert_approx(tune["rates"]["elevator"], 0.0, "rate clamped to 0")
	t.assert_approx(tune["power_factor"], 2.0, "power factor clamped to 2")

func test_build_aircraft_tuning_defaults(t) -> void:
	var tune := AgenticUtils.build_aircraft_tuning({})
	t.assert_true(tune["expo"].has("rudder"), "rudder expo present by default")
	t.assert_approx(tune["power_factor"], 1.0, "default power factor 1")

func test_slugify(t) -> void:
	t.assert_true(AgenticUtils.slugify("Lightweight 3D Foamie!") == "lightweight_3d_foamie", "slug cleaned")
	t.assert_true(AgenticUtils.slugify("") == "custom", "empty -> custom")

func test_validate_aircraft_config(t) -> void:
	var cfg := AgenticUtils.validate_aircraft_config({"name": "  Edge 540 ", "category": "3d"})
	t.assert_true(cfg["name"] == "Edge 540", "name trimmed")
	t.assert_true(cfg["slug"] == "edge_540", "slug derived")
	t.assert_true(cfg["tuning"].has("power_factor"), "tuning embedded")

# ---------------------------------------------------------------------------
# 5.1.2  Scenery generation
# ---------------------------------------------------------------------------
func test_parse_scenery_spec_whitelists_props(t) -> void:
	var spec := AgenticUtils.parse_scenery_spec({
		"size_m": 600.0,
		"objects": [{"type": "tree", "x": 9999.0, "z": 0.0}, {"type": "ufo", "x": 0.0, "z": 0.0}],
	})
	t.assert_true((spec["objects"] as Array).size() == 1, "unknown prop dropped")
	t.assert_approx((spec["objects"] as Array)[0]["x"], 300.0, "prop clamped to half-size")

func test_parse_scenery_spec_clamps_size_and_runway(t) -> void:
	var spec := AgenticUtils.parse_scenery_spec({"size_m": 99999.0, "runway_length_m": 99999.0})
	t.assert_approx(spec["size_m"], 4000.0, "size clamped")
	t.assert_true(float(spec["runway_length_m"]) <= float(spec["size_m"]), "runway within field")

func test_parse_scenery_spec_wind_layers(t) -> void:
	var spec := AgenticUtils.parse_scenery_spec({"wind_layers": [{"altitude_m": 100.0, "speed_ms": 99.0, "dir_deg": 400.0}]})
	var layer: Dictionary = (spec["wind_layers"] as Array)[0]
	t.assert_approx(layer["speed_ms"], 30.0, "wind speed clamped")
	t.assert_approx(layer["dir_deg"], 40.0, "wind dir wrapped")

# ---------------------------------------------------------------------------
# 5.2  Voice command parsing
# ---------------------------------------------------------------------------
func test_voice_set_wind(t) -> void:
	var cmd := AgenticUtils.parse_voice_command('{"action":"set_wind","params":{"speed_ms":99,"dir_deg":450,"gusts":true}}')
	t.assert_true(cmd["action"] == "set_wind", "action parsed")
	t.assert_approx(cmd["params"]["speed_ms"], 30.0, "wind speed clamped")
	t.assert_approx(cmd["params"]["dir_deg"], 90.0, "wind dir wrapped")
	t.assert_true(cmd["params"]["gusts"] == true, "gusts flag kept")

func test_voice_demonstrate(t) -> void:
	var cmd := AgenticUtils.parse_voice_command({"action": "demonstrate_maneuver", "params": {"maneuver": " knife-edge "}})
	t.assert_true(cmd["params"]["maneuver"] == "knife-edge", "maneuver trimmed")

func test_voice_unknown(t) -> void:
	var cmd := AgenticUtils.parse_voice_command('{"action":"launch_nukes"}')
	t.assert_true(cmd["action"] == "unknown", "unwhitelisted -> unknown")
	var garbage := AgenticUtils.parse_voice_command("mmm hello")
	t.assert_true(garbage["action"] == "unknown", "non-json -> unknown")

func test_voice_embedded_json(t) -> void:
	var cmd := AgenticUtils.parse_voice_command("Sure: {\"action\":\"grade_landing\",\"params\":{}} done")
	t.assert_true(cmd["action"] == "grade_landing", "embedded json parsed")

# ---------------------------------------------------------------------------
# 5.3  Flight replay analysis
# ---------------------------------------------------------------------------
func test_ring_capacity(t) -> void:
	t.assert_true(AgenticUtils.ring_capacity(50.0, 300.0) == 15000, "50Hz * 5min")
	t.assert_true(AgenticUtils.ring_capacity(0.0, 0.0) == 1, "never zero capacity")

func test_downsample_frames_keeps_ends(t) -> void:
	var frames: Array = []
	for i in range(100):
		frames.append({"i": i})
	var ds := AgenticUtils.downsample_frames(frames, 10)
	t.assert_true(ds.size() == 10, "downsampled to 10")
	t.assert_true(ds[0]["i"] == 0, "keeps first")
	t.assert_true(ds[9]["i"] == 99, "keeps last")

func test_downsample_frames_small(t) -> void:
	var frames: Array = [{"i": 0}, {"i": 1}]
	t.assert_true(AgenticUtils.downsample_frames(frames, 10).size() == 2, "fewer than max kept")
	t.assert_true(AgenticUtils.downsample_frames([], 10).is_empty(), "empty stays empty")

func test_summarize_replay(t) -> void:
	var frames: Array = [
		{"altitude_m": 10.0, "airspeed_ms": 5.0, "climb_ms": 2.0},
		{"altitude_m": 50.0, "airspeed_ms": 20.0, "climb_ms": -3.0},
	]
	var s := AgenticUtils.summarize_replay(frames, 50.0)
	t.assert_approx(s["max_altitude_m"], 50.0, "max altitude")
	t.assert_approx(s["min_altitude_m"], 10.0, "min altitude")
	t.assert_approx(s["max_airspeed_ms"], 20.0, "max airspeed")
	t.assert_approx(s["max_descent_ms"], -3.0, "max descent")
	t.assert_approx(s["duration_s"], 0.04, "duration from frame count", 0.001)

func test_timecode_roundtrip(t) -> void:
	t.assert_true(AgenticUtils.format_timecode(83.0) == "1:23", "formats 1:23")
	t.assert_approx(AgenticUtils.parse_timecode("1:23"), 83.0, "parses back")
	t.assert_approx(AgenticUtils.parse_timecode("nope"), -1.0, "invalid -> -1")

func test_parse_debrief_markers_structured(t) -> void:
	var res := AgenticUtils.parse_debrief_markers('{"summary":"Good flight","markers":[{"t":83,"label":"Stall"},{"t":10,"label":"Takeoff"}]}')
	t.assert_true(res["summary"] == "Good flight", "summary extracted")
	t.assert_true((res["markers"] as Array).size() == 2, "two markers")
	t.assert_approx((res["markers"] as Array)[0]["t"], 10.0, "markers sorted by time")

func test_parse_debrief_markers_prose(t) -> void:
	var res := AgenticUtils.parse_debrief_markers("You did well. Stall at 1:23 because the nose was high.")
	var markers: Array = res["markers"]
	t.assert_true(markers.size() >= 1, "scraped at least one marker")
	t.assert_approx(markers[0]["t"], 83.0, "prose timecode parsed")

# ---------------------------------------------------------------------------
# 5.4  Multiplayer commentary
# ---------------------------------------------------------------------------
func test_build_commentary_prompt_sorts(t) -> void:
	var text := AgenticUtils.build_commentary_prompt([
		{"name": "Bravo", "position": 2, "altitude_m": 30.0, "airspeed_ms": 18.0},
		{"name": "Alpha", "position": 1, "altitude_m": 25.0, "airspeed_ms": 22.0},
	])
	t.assert_true(text.find("Alpha") < text.find("Bravo"), "leader listed first")

# ---------------------------------------------------------------------------
# 5.6  Token usage & rate-limit awareness
# ---------------------------------------------------------------------------
func test_estimate_token_count(t) -> void:
	t.assert_true(AgenticUtils.estimate_token_count("12345678") == 2, "~4 chars per token")
	t.assert_true(AgenticUtils.estimate_token_count("") == 0, "empty -> 0")

func test_estimate_cost(t) -> void:
	t.assert_approx(AgenticUtils.estimate_cost(1000, 1000, 0.5, 1.5), 2.0, "cost from prices")
	t.assert_approx(AgenticUtils.estimate_cost(1000, 1000), 0.0, "no pricing -> 0")

func test_parse_rate_limit_cooldown(t) -> void:
	var headers: PackedStringArray = ["Content-Type: application/json", "Retry-After: 30"]
	t.assert_approx(AgenticUtils.parse_rate_limit_cooldown(headers), 30.0, "reads Retry-After")
	t.assert_approx(AgenticUtils.parse_rate_limit_cooldown([], 12.0), 12.0, "falls back to default")
