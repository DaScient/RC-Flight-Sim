## test_agentic_integration.gd
## Integration tests for Phase 5 stateful agentic systems that don't need a
## live LLM/HTTP connection: the FlightRecorder ring buffer + save/load, the
## AgenticAircraftWizard's validate-and-save pipeline (fed a mock LLM reply),
## and the AgenticSceneryGenerator's spec/scene building.
## Run via tests/run_tests.gd.
class_name TestAgenticIntegration
extends RefCounted

const TMP_AIRCRAFT_DIR := "user://aircraft/custom/"
const TMP_REPLAY_DIR := "user://replays/"

# ---------------------------------------------------------------------------
# 5.3  FlightRecorder ring buffer + save/load
# ---------------------------------------------------------------------------
func test_recorder_ring_buffer_caps(t) -> void:
	var rec := _new_recorder()
	rec.set_rate(10.0)  # capacity = 10Hz * 300s = 3000
	for i in range(5):
		rec.push_frame({"altitude_m": float(i)})
	t.assert_true(rec.frame_count() == 5, "frames buffered")

func test_recorder_ai_segment_downsamples(t) -> void:
	var rec := _new_recorder()
	rec.set_rate(50.0)
	for i in range(200):
		rec.push_frame({"altitude_m": float(i), "airspeed_ms": float(i) * 0.1, "climb_ms": 0.0})
	var seg: Array = rec.get_ai_segment(20)
	t.assert_true(seg.size() == 20, "ai segment downsampled to 20")
	var summary: Dictionary = rec.get_summary()
	t.assert_approx(summary["max_altitude_m"], 199.0, "summary peak altitude")

func test_recorder_save_load_roundtrip(t) -> void:
	var rec := _new_recorder()
	rec.set_rate(50.0)
	for i in range(10):
		rec.push_frame({"altitude_m": float(i)})
	var path: String = rec.save_replay("integration_test")
	t.assert_true(path != "", "replay saved")
	var loaded: Dictionary = rec.load_replay(path)
	t.assert_true((loaded.get("frames", []) as Array).size() == 10, "frames round-trip")
	t.assert_true(int(loaded.get("version", 0)) == rec.REPLAY_VERSION, "version stamped")
	DirAccess.remove_absolute(path)

# ---------------------------------------------------------------------------
# 5.1.1  Aircraft wizard end-to-end (mock LLM reply)
# ---------------------------------------------------------------------------
func test_wizard_saves_valid_aircraft(t) -> void:
	var wizard := AgenticAircraftWizard.new()
	var mock := "Here you go: {\"name\":\"Test Foamie\",\"category\":\"3d\"," \
		+ "\"model_description\":\"a light foamie\"," \
		+ "\"jsbsim_xml\":\"<fdm_config><metrics/><mass_balance/><aerodynamics/></fdm_config>\"," \
		+ "\"tuning\":{\"power_factor\":1.5}}"
	var res := wizard.process_response(mock)
	t.assert_true(res["saved"], "valid aircraft saved")
	t.assert_true(FileAccess.file_exists(res["dir"] + "test_foamie.xml"), "xml written")
	t.assert_true(FileAccess.file_exists(res["dir"] + "tuning.json"), "tuning written")
	_rmdir(res["dir"])

func test_wizard_rejects_invalid_xml(t) -> void:
	var wizard := AgenticAircraftWizard.new()
	var mock := "{\"name\":\"Bad\",\"jsbsim_xml\":\"<fdm_config></fdm_config>\"}"
	var res := wizard.process_response(mock)
	t.assert_true(not res["saved"], "incomplete xml rejected")
	t.assert_true(String(res["error"]).find("missing") != -1, "error names missing nodes")

func test_wizard_rejects_non_json(t) -> void:
	var wizard := AgenticAircraftWizard.new()
	var res := wizard.process_response("Sorry, I cannot do that.")
	t.assert_true(not res["saved"], "no json -> not saved")

# ---------------------------------------------------------------------------
# 5.1.2  Scenery generator
# ---------------------------------------------------------------------------
func test_scenery_process_response(t) -> void:
	var gen := AgenticSceneryGenerator.new()
	var spec := gen.process_response("{\"name\":\"Lakeside\",\"size_m\":800,\"objects\":[{\"type\":\"tree\",\"x\":10,\"z\":20}]}")
	t.assert_true(spec["name"] == "Lakeside", "name parsed")
	t.assert_true((spec["objects"] as Array).size() == 1, "prop kept")

func test_scenery_build_scene(t) -> void:
	var gen := AgenticSceneryGenerator.new()
	var spec := AgenticUtils.parse_scenery_spec({
		"name": "Field", "size_m": 500.0,
		"objects": [{"type": "tree", "x": 0.0, "z": 0.0}, {"type": "hangar", "x": 50.0, "z": 0.0}],
	})
	var scene := gen.build_scene(spec)
	# Ground + runway + 2 props = 4 children.
	t.assert_true(scene.get_child_count() == 4, "scene has ground, runway and props")
	scene.free()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _new_recorder() -> Node:
	var script: GDScript = load("res://scripts/autoload/flight_recorder.gd")
	var rec: Node = script.new()
	rec._recompute_capacity()
	return rec

func _rmdir(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(dir + f)
	DirAccess.remove_absolute(dir)
