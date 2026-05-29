## remote_aircraft.gd
## Visual representation of another player's aircraft (Part 3D). Smooths the
## stream of networked snapshots using a small interpolation buffer plus
## velocity-based dead-reckoning for the gap between packets.
##
## Strategy:
##  - Snapshots are stored with their arrival time.
##  - We render `INTERP_DELAY` seconds in the past so there is always a pair of
##    snapshots to interpolate between (hides jitter and minor packet loss).
##  - If the buffer runs dry (lag/loss), we extrapolate from the last snapshot
##    using its velocity (dead reckoning) and clamp how far we predict.
class_name RemoteAircraft
extends Node3D

## How far in the past to render, in seconds (one to two packet intervals).
const INTERP_DELAY: float = 0.1
## Maximum extrapolation time before freezing, to avoid wild predictions.
const MAX_EXTRAPOLATION: float = 0.3

var _buffer: Array = []   # of { t (local sec), pos, rot (Quaternion), vel }

func push_state(state: Dictionary) -> void:
	var now := _now()
	_buffer.append({
		"t": now,
		"pos": state.get("position", Vector3.ZERO),
		"rot": state.get("orientation", Quaternion.IDENTITY),
		"vel": state.get("velocity", Vector3.ZERO),
	})
	# Keep the buffer small; we only need a short history.
	while _buffer.size() > 32:
		_buffer.pop_front()

func _process(_delta: float) -> void:
	if _buffer.is_empty():
		return
	var render_time := _now() - INTERP_DELAY
	var newest: Dictionary = _buffer[_buffer.size() - 1]

	# Find the two snapshots that bracket render_time.
	for i in range(_buffer.size() - 1):
		var a: Dictionary = _buffer[i]
		var b: Dictionary = _buffer[i + 1]
		if float(a["t"]) <= render_time and render_time <= float(b["t"]):
			var span := float(b["t"]) - float(a["t"])
			var t := 0.0 if span <= 0.0 else (render_time - float(a["t"])) / span
			_apply(a["pos"].lerp(b["pos"], t), (a["rot"] as Quaternion).slerp(b["rot"], t))
			return

	# No bracketing pair: dead-reckon forward from the newest snapshot.
	var ahead := clampf(render_time - float(newest["t"]), 0.0, MAX_EXTRAPOLATION)
	_apply(newest["pos"] + newest["vel"] * ahead, newest["rot"])

func _apply(pos: Vector3, rot: Quaternion) -> void:
	global_position = pos
	global_transform.basis = Basis(rot)

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
