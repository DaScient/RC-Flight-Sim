## agentic_skill.gd
## Base class for the Agentic Plugin API (Phase 5.5).
##
## A "skill" is a self-contained unit of agentic behaviour that the community
## can drop into res://scripts/agentic/skills/ to teach the AI new tricks
## without touching the core. Extend this class, override the hooks you need,
## and register an instance with AgenticManager.register_skill().
##
## A skill may:
##   * Read a live telemetry snapshot                -> request_snapshot()
##   * Ask the LLM a question                        -> send_prompt()
##   * Drive the aircraft via the AI co-pilot         -> play_maneuver()
##   * Spawn its own UI on the agentic overlay        -> spawn_ui()
##
## All of these route through AgenticManager so skills inherit the same
## non-blocking HTTP, throttling, clamping and safety guarantees as the core.
class_name AgenticSkill
extends RefCounted

## Stable identifier (snake_case) used to register/lookup the skill.
var id: StringName = &"skill"
## Human-readable name shown in menus.
var display_name: String = "Unnamed Skill"
## One-line description for the skill picker.
var description: String = ""

## Back-reference to the manager, injected on registration. Typed as Node to
## avoid a hard cyclic dependency on the autoload script.
var manager: Node = null

## Called once when the skill is registered with the manager. Override to set
## up state or UI. Always call super() first.
func setup(host: Node) -> void:
	manager = host

## Called when the skill is unregistered or the manager shuts down. Override to
## tear down UI / disconnect signals.
func teardown() -> void:
	manager = null

## Override to react to a fresh telemetry snapshot (when the skill requested one
## via request_snapshot()).
func on_snapshot(_snapshot: Dictionary) -> void:
	pass

## Override to react to an LLM reply to a prompt this skill sent.
func on_llm_response(_text: String) -> void:
	pass

# ---------------------------------------------------------------------------
# Helpers skills call (thin wrappers over the manager, null-safe)
# ---------------------------------------------------------------------------
## Returns the current telemetry snapshot, or {} if unavailable.
func request_snapshot() -> Dictionary:
	if manager != null and manager.has_method("get_snapshot"):
		return manager.get_snapshot()
	return {}

## Send a free-form prompt to the LLM on behalf of this skill. The reply is
## delivered to on_llm_response(). No-op (returns false) if the LLM is offline.
func send_prompt(system_prompt: String, user_prompt: String) -> bool:
	if manager != null and manager.has_method("send_skill_prompt"):
		return bool(manager.send_skill_prompt(self, system_prompt, user_prompt))
	return false

## Engage the AI co-pilot to fly a maneuver sequence (raw JSON or Array).
func play_maneuver(maneuver: Variant, label: String = "skill maneuver") -> bool:
	if manager != null and manager.has_method("play_skill_maneuver"):
		return bool(manager.play_skill_maneuver(maneuver, label))
	return false

## Add a Control to the shared agentic overlay CanvasLayer. Returns false in
## headless/test runs where there is no overlay.
func spawn_ui(control: Control) -> bool:
	if manager != null and manager.has_method("attach_skill_ui"):
		return bool(manager.attach_skill_ui(control))
	return false
