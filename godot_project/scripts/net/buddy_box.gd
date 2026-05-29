## buddy_box.gd
## "Buddy Box" trainer mode (Part 3D): an instructor (master) and a student
## (slave) share control of one aircraft, mirroring real RC trainer cables.
##
## Behaviour:
##  - The student flies by default; their channels are sent to the instructor.
##  - While the instructor holds the override button, the instructor's channels
##    take command and are applied to the aircraft instead.
##  - A configurable mix blends student/instructor inputs (0 = full student,
##    1 = full instructor) so an instructor can "nudge" rather than fully grab.
##
## Control states are exchanged over reliable-ordered RPCs so a dropped frame
## never leaves the aircraft on a stale command. Attach this beside the
## MultiplayerManager; it reads local channels from InputManager.
class_name BuddyBox
extends Node

enum Role { STUDENT, INSTRUCTOR }

signal control_authority_changed(instructor_in_control: bool)

@export var role: Role = Role.STUDENT
## Blend applied while the instructor is overriding (1 = full takeover).
@export_range(0.0, 1.0) var override_mix: float = 1.0

## The aircraft to drive (its FDM receives the resolved channels).
var aircraft: Node = null

var _student_channels: Dictionary = _zero_channels()
var _instructor_channels: Dictionary = _zero_channels()
var _instructor_override: bool = false

const CHANNELS: Array[String] = ["aileron", "elevator", "rudder", "throttle"]

func _physics_process(_delta: float) -> void:
	# Capture local inputs and share them with the peer.
	var local := _read_local_channels()
	if role == Role.STUDENT:
		_student_channels = local
		_rpc_student_channels.rpc(local)
	else:
		_instructor_channels = local
		_instructor_override = Input.is_action_pressed("instructor_override")
		_rpc_instructor_state.rpc(local, _instructor_override)

	# Only the host authoritatively resolves and applies the mixed command.
	if multiplayer.is_server():
		_apply_resolved_channels()

## Resolve the effective channels from student/instructor state and apply them.
func _apply_resolved_channels() -> void:
	var resolved := _student_channels.duplicate()
	if _instructor_override:
		for ch in CHANNELS:
			var s: float = float(_student_channels.get(ch, 0.0))
			var i: float = float(_instructor_channels.get(ch, 0.0))
			resolved[ch] = lerpf(s, i, override_mix)
	_apply_to_aircraft(resolved)

func _apply_to_aircraft(channels: Dictionary) -> void:
	if aircraft == null:
		return
	var fdm: Object = aircraft.get("fdm")
	if fdm == null:
		return
	fdm.set_control_surface(FDMInterface.SURFACE_AILERON, float(channels.get("aileron", 0.0)))
	fdm.set_control_surface(FDMInterface.SURFACE_ELEVATOR, float(channels.get("elevator", 0.0)))
	fdm.set_control_surface(FDMInterface.SURFACE_RUDDER, float(channels.get("rudder", 0.0)))
	fdm.set_control_surface(FDMInterface.SURFACE_THROTTLE, float(channels.get("throttle", 0.0)))

# ---------------------------------------------------------------------------
# RPCs
# ---------------------------------------------------------------------------
@rpc("any_peer", "call_remote", "reliable")
func _rpc_student_channels(channels: Dictionary) -> void:
	_student_channels = channels

@rpc("any_peer", "call_remote", "reliable")
func _rpc_instructor_state(channels: Dictionary, override_active: bool) -> void:
	_instructor_channels = channels
	if override_active != _instructor_override:
		_instructor_override = override_active
		control_authority_changed.emit(override_active)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
func _read_local_channels() -> Dictionary:
	var im := get_node_or_null("/root/InputManager")
	if im != null:
		return (im.channels as Dictionary).duplicate()
	return _zero_channels()

static func _zero_channels() -> Dictionary:
	return {"aileron": 0.0, "elevator": 0.0, "rudder": 0.0, "throttle": 0.0}
