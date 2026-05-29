## smoke_writer_skill.gd
## Built-in Agentic skill (Phase 5.5): the AI flies a pattern "written" in the
## sky. It asks the LLM for a maneuver keyframe sequence that traces a shape
## (heart, figure-8, the user's initials...) and hands it to the co-pilot.
##
## Smoke emission is left to the aircraft's existing smoke system; this skill is
## responsible only for generating and flying the path.
class_name SmokeWriterSkill
extends AgenticSkill

const SYSTEM := "You are an RC aerobatic autopilot drawing shapes in the sky with smoke. Output ONLY a JSON array of timed control keyframes [{\"t\":0.0,\"aileron\":0.0,\"elevator\":0.0,\"rudder\":0.0,\"throttle\":0.6}]. aileron/elevator/rudder in [-1,1], throttle [0,1]. Keep it under 15 seconds and end roughly level."

func _init() -> void:
	id = &"smoke_writer"
	display_name = "Smoke Writer"
	description = "The AI traces a shape in the sky with smoke."

## Draw [param shape] (e.g. "a big loop", "a figure eight"). Falls back silently
## if the LLM is offline.
func draw(shape: String) -> void:
	var snapshot := request_snapshot()
	send_prompt(SYSTEM, "Current state: %s\nDraw with smoke: %s" % [
		AgenticUtils.snapshot_to_prompt_text(snapshot), shape])

func on_llm_response(text: String) -> void:
	play_maneuver(text, "%s pattern" % display_name)
