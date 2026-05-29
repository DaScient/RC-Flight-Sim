## agentic_copilot.gd
## Stateful AI co-pilot that plays back an LLM-generated maneuver sequence by
## overriding the aircraft's control inputs for a bounded duration.
##
## Design goals (Phase 3.4):
##   * The human can always abort instantly by moving a stick (override check).
##   * Generated controls are clamped and bounded by a safety envelope; if the
##     aircraft reaches a dangerous attitude the co-pilot disengages itself.
##   * Pure playback math lives in AgenticUtils so it is unit-tested; this class
##     only manages engaged/disengaged state and elapsed time.
class_name AgenticCopilot
extends RefCounted

signal engaged(label: String)
signal disengaged(reason: String)

## Reasons surfaced via [signal disengaged] / get_last_reason().
const REASON_COMPLETED := "completed"
const REASON_USER_OVERRIDE := "user_override"
const REASON_UNSAFE := "unsafe_attitude"
const REASON_ABORTED := "aborted"

var is_engaged: bool = false
var label: String = ""

var _sequence: Array = []
var _elapsed: float = 0.0
var _duration: float = 0.0
var _last_reason: String = ""
var _safety_limits: Dictionary = {}

## Begin playing [param maneuver] (raw JSON string or parsed Array). Returns
## false if the maneuver is empty/invalid. [param safety_limits] overrides the
## AgenticUtils defaults (e.g. tighter limits for a beginner aircraft).
func engage(maneuver: Variant, maneuver_label: String = "maneuver", safety_limits: Dictionary = {}) -> bool:
	_sequence = AgenticUtils.parse_maneuver_sequence(maneuver)
	if _sequence.is_empty():
		return false
	_duration = AgenticUtils.maneuver_duration(_sequence)
	_elapsed = 0.0
	_safety_limits = safety_limits
	label = maneuver_label
	is_engaged = true
	engaged.emit(label)
	return true

## Disengage immediately, returning control to the human.
func disengage(reason: String = REASON_ABORTED) -> void:
	if not is_engaged:
		return
	is_engaged = false
	_last_reason = reason
	disengaged.emit(reason)

## Advance playback by [param delta] seconds and return the control override to
## apply this frame, or an empty Dictionary when the co-pilot is not driving.
## [param state] is the current FDM state, [param channels] the human stick
## inputs (for override detection). Safe to call every physics frame.
func advance(delta: float, state: Dictionary, channels: Dictionary) -> Dictionary:
	if not is_engaged:
		return {}
	# Human grabbed a stick -> hand back control immediately.
	if AgenticUtils.detect_user_override(channels):
		disengage(REASON_USER_OVERRIDE)
		return {}
	# Dangerous attitude -> safety disengage.
	if AgenticUtils.is_dangerous_attitude(state, _safety_limits):
		disengage(REASON_UNSAFE)
		return {}
	_elapsed += delta
	if _elapsed > _duration:
		disengage(REASON_COMPLETED)
		return {}
	return AgenticUtils.sample_maneuver(_sequence, _elapsed)

## Progress through the current maneuver in [0, 1].
func get_progress() -> float:
	if _duration <= 0.0:
		return 0.0
	return clampf(_elapsed / _duration, 0.0, 1.0)

func get_last_reason() -> String:
	return _last_reason
