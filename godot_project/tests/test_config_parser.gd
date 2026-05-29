## test_config_parser.gd
## Unit tests for ConfigLoader (JSON parsing + deep merge + numeric access).
class_name TestConfigParser
extends RefCounted

func test_parse_valid_json(t) -> void:
	var d := ConfigLoader.parse_json_dict('{"a": 1, "b": {"c": 2}}')
	t.assert_true(d.has("a"), "parsed key a")
	t.assert_approx(float(d["a"]), 1.0, "value a == 1")

func test_parse_invalid_json_returns_empty(t) -> void:
	var err: Array = [""]
	var d := ConfigLoader.parse_json_dict("{not valid", err)
	t.assert_true(d.is_empty(), "invalid json -> empty dict")
	t.assert_true(String(err[0]) != "", "error message populated")

func test_parse_non_object_returns_empty(t) -> void:
	var d := ConfigLoader.parse_json_dict("[1, 2, 3]")
	t.assert_true(d.is_empty(), "top-level array -> empty dict")

func test_deep_merge_overrides_scalars(t) -> void:
	var base := {"mass": 1.5, "drag": 0.03}
	var ov := {"mass": 2.0}
	var merged := ConfigLoader.deep_merge(base, ov)
	t.assert_approx(float(merged["mass"]), 2.0, "override replaces scalar")
	t.assert_approx(float(merged["drag"]), 0.03, "untouched key preserved")

func test_deep_merge_recurses(t) -> void:
	var base := {"engine": {"power": 1.0, "kv": 1000}}
	var ov := {"engine": {"power": 1.2}}
	var merged := ConfigLoader.deep_merge(base, ov)
	t.assert_approx(float(merged["engine"]["power"]), 1.2, "nested override")
	t.assert_approx(float(merged["engine"]["kv"]), 1000.0, "nested sibling preserved")

func test_deep_merge_does_not_mutate_inputs(t) -> void:
	var base := {"a": {"x": 1}}
	var ov := {"a": {"x": 2}}
	ConfigLoader.deep_merge(base, ov)
	t.assert_approx(float(base["a"]["x"]), 1.0, "base not mutated by merge")

func test_get_number_defaults_and_clamps(t) -> void:
	var cfg := {"power": 5.0, "bad": "nope"}
	t.assert_approx(ConfigLoader.get_number(cfg, "power", 1.0), 5.0, "reads number")
	t.assert_approx(ConfigLoader.get_number(cfg, "missing", 3.0), 3.0, "missing -> default")
	t.assert_approx(ConfigLoader.get_number(cfg, "bad", 3.0), 3.0, "non-number -> default")
	t.assert_approx(ConfigLoader.get_number(cfg, "power", 1.0, 0.0, 2.0), 2.0, "clamped to max")
