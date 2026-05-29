## formation_trainer_skill.gd
## Built-in Agentic skill (Phase 5.5): coaches the pilot on holding a formation
## slot relative to a lead aircraft. Each tick it compares the trainee's state
## with the lead's and produces concise, local corrections; when an LLM is
## available it can also request richer phrasing.
class_name FormationTrainerSkill
extends AgenticSkill

const SYSTEM := "You are a formation flight instructor. Given the trainee's offset from the lead aircraft, give one short correction (max 15 words)."

## Desired slot offset behind/beside the lead, in metres.
var slot_offset := Vector3(-10.0, 0.0, 5.0)
## Tolerance (m) within which we consider the trainee "in the slot".
var tolerance := 4.0

func _init() -> void:
	id = &"formation_trainer"
	display_name = "Formation Trainer"
	description = "Coaches you to hold a formation slot behind a lead aircraft."

## Evaluate the trainee position [param trainee] against the [param lead]
## position (both global metres). Returns a short local tip, or "" when the
## trainee is within tolerance of the slot.
func evaluate(trainee: Vector3, lead: Vector3) -> String:
	var target := lead + slot_offset
	var err := trainee - target
	if err.length() <= tolerance:
		return ""
	var parts: PackedStringArray = []
	if absf(err.y) > tolerance:
		parts.append("descend" if err.y > 0.0 else "climb")
	if absf(err.z) > tolerance:
		parts.append("ease forward" if err.z > 0.0 else "drop back")
	if absf(err.x) > tolerance:
		parts.append("slide right" if err.x > 0.0 else "slide left")
	if parts.is_empty():
		return ""
	return "Hold the slot: " + ", ".join(parts) + "."

## Ask the LLM for richer phrasing of the current correction (optional).
func coach(trainee: Vector3, lead: Vector3) -> void:
	var tip := evaluate(trainee, lead)
	if tip == "":
		return
	send_prompt(SYSTEM, "Offset from slot: %s. Base tip: %s" % [str(trainee - (lead + slot_offset)), tip])
