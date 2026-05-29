## skill_template.gd
## Copy this file to start a new Agentic skill (Phase 5.5 Plugin API).
##
## 1. Rename the class and file (snake_case).
## 2. Set id / display_name / description in _init().
## 3. Override the hooks you need (on_snapshot, on_llm_response).
## 4. Register it once at startup, e.g. from an autoload or a tool button:
##        AgenticManager.register_skill(MySkill.new())
##    then trigger it with:
##        AgenticManager.invoke_skill(&"my_skill")
##
## See docs/agentic_plugin_api.md for the full guide.
class_name AgenticSkillTemplate
extends AgenticSkill

func _init() -> void:
	id = &"skill_template"
	display_name = "Skill Template"
	description = "A starting point for new agentic skills."

## Called by AgenticManager.invoke_skill(). Do your work here. This example
## reads telemetry then asks the LLM something about it.
func invoke() -> void:
	var snapshot := request_snapshot()
	if snapshot.is_empty():
		return
	send_prompt(
		"You are a helpful RC flight assistant. Reply in one short sentence.",
		"Telemetry: " + AgenticUtils.snapshot_to_prompt_text(snapshot))

func on_llm_response(text: String) -> void:
	# Do something with the reply (speak it, show UI, drive a maneuver...).
	print("[%s] %s" % [display_name, text])
