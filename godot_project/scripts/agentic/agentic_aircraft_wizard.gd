## agentic_aircraft_wizard.gd
## Phase 5.1.1 - turns a natural-language aircraft description into saved,
## validated assets: a JSBSim XML, a tuning.json, and a model-description
## sidecar under user://aircraft/custom/<slug>/.
##
## This class is the file-IO + validation glue; the LLM call itself is owned by
## AgenticManager (non-blocking HTTP). All validation lives in AgenticUtils so
## it is unit-tested.
class_name AgenticAircraftWizard
extends RefCounted

const CUSTOM_DIR := "user://aircraft/custom/"

## Build the user prompt sent to the LLM for [param description].
static func build_prompt(description: String) -> String:
	return "Design this RC aircraft: %s" % description.strip_edges()

## Process the LLM's JSON reply. Validates the embedded JSBSim XML and tuning,
## and on success writes the asset bundle to disk.
## Returns {"saved": bool, "dir": String, "config": Dictionary, "error": String}.
func process_response(content: String) -> Dictionary:
	var block: Variant = AgenticUtils.extract_json_block(content)
	if not (block is Dictionary):
		return {"saved": false, "dir": "", "config": {}, "error": "No JSON object found in response."}
	var data: Dictionary = block
	var config := AgenticUtils.validate_aircraft_config(data)
	var xml := String(data.get("jsbsim_xml", ""))
	var xml_check := AgenticUtils.validate_xml(xml)
	if not bool(xml_check["valid"]):
		return {
			"saved": false, "dir": "", "config": config,
			"error": "JSBSim XML missing nodes: " + ", ".join(xml_check["missing"]),
		}
	var dir: String = CUSTOM_DIR + String(config["slug"]) + "/"
	if not _save_bundle(dir, xml, config):
		return {"saved": false, "dir": dir, "config": config, "error": "Could not write files."}
	return {"saved": true, "dir": dir, "config": config, "error": ""}

func _save_bundle(dir: String, xml: String, config: Dictionary) -> bool:
	if not DirAccess.dir_exists_absolute(dir):
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			return false
	if not _write_text(dir + String(config["slug"]) + ".xml", xml):
		return false
	if not _write_text(dir + "tuning.json", JSON.stringify(config["tuning"], "\t")):
		return false
	if not _write_text(dir + "model_description.txt", String(config["model_description"])):
		return false
	return true

func _write_text(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true
