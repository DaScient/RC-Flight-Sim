## config_loader.gd
## Pure helpers for loading and merging JSON configuration dictionaries.
##
## Used by the aircraft tuning system (`tuning.json` overrides on top of the
## base aircraft definition) and by atmospheric profile loading. Kept free of
## node/scene state so the merge logic can be unit-tested directly.
class_name ConfigLoader
extends RefCounted

## Parse JSON text into a Dictionary. Returns an empty Dictionary on error and
## reports the parse error via [param out_error] (if a one-element array is
## supplied) so callers can surface a message without exceptions.
static func parse_json_dict(text: String, out_error: Array = []) -> Dictionary:
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		if out_error.size() > 0:
			out_error[0] = "JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return {}
	var data: Variant = json.get_data()
	if typeof(data) != TYPE_DICTIONARY:
		if out_error.size() > 0:
			out_error[0] = "Expected a JSON object at the top level."
		return {}
	return data

## Load and parse a JSON file from [param path]. Returns {} if missing/invalid.
static func load_json_file(path: String, out_error: Array = []) -> Dictionary:
	if not FileAccess.file_exists(path):
		if out_error.size() > 0:
			out_error[0] = "File not found: %s" % path
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		if out_error.size() > 0:
			out_error[0] = "Cannot open file: %s" % path
		return {}
	var text := f.get_as_text()
	f.close()
	return parse_json_dict(text, out_error)

## Deep-merge [param override] onto [param base] and return a new Dictionary.
## Nested dictionaries are merged recursively; any other type in [param override]
## replaces the corresponding key in [param base]. Neither input is mutated.
static func deep_merge(base: Dictionary, override: Dictionary) -> Dictionary:
	var result := base.duplicate(true)
	for key in override.keys():
		var ov: Variant = override[key]
		if result.has(key) and typeof(result[key]) == TYPE_DICTIONARY and typeof(ov) == TYPE_DICTIONARY:
			result[key] = deep_merge(result[key], ov)
		else:
			result[key] = ov
	return result

## Fetch a numeric value with a default and clamp to an optional range.
## Skips non-numeric entries so a malformed config can't crash the sim.
static func get_number(cfg: Dictionary, key: String, default_val: float, min_v: float = -INF, max_v: float = INF) -> float:
	if not cfg.has(key):
		return default_val
	var v: Variant = cfg[key]
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return default_val
	return clampf(float(v), min_v, max_v)
