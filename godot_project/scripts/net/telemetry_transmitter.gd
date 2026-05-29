## telemetry_transmitter.gd
## Autoload that streams a compact binary telemetry packet over UDP at a fixed
## rate (default 20 Hz). Intended for external tools: live plotting, motion
## platforms, data logging and research (see tools/telemetry_receiver.py).
##
## The packet format is documented in docs/telemetry_protocol.md and kept in
## sync with PACKET_MAGIC / PROTOCOL_VERSION below. All multi-byte values are
## little-endian; floats are 32-bit.
extends Node

const PACKET_MAGIC: int = 0x52434654   # "RCFT"
const PROTOCOL_VERSION: int = 1

# ---------------------------------------------------------------------------
# Runtime configuration (overridable via SettingsManager)
# ---------------------------------------------------------------------------
var enabled: bool = false
var host: String = "127.0.0.1"
var port: int = 9001
var rate_hz: float = 20.0

# ---------------------------------------------------------------------------
# Internal state
# ---------------------------------------------------------------------------
var _udp: PacketPeerUDP = PacketPeerUDP.new()
var _aircraft: Node = null
var _accum: float = 0.0
var _connected: bool = false

func _ready() -> void:
	# Pull persisted settings if available (keys are optional).
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("get_setting"):
		enabled = bool(sm.get_setting("telemetry_enabled", false))
		host = String(sm.get_setting("telemetry_host", host))
		port = int(sm.get_setting("telemetry_port", port))
		rate_hz = float(sm.get_setting("telemetry_rate_hz", rate_hz))
	set_physics_process(enabled)

## Register the aircraft whose state should be streamed. Pass null to stop.
func register_aircraft(aircraft: Node) -> void:
	_aircraft = aircraft

## Enable/disable streaming at runtime (also (re)opens the UDP socket).
func set_enabled(value: bool) -> void:
	enabled = value
	if enabled:
		_ensure_connection()
	set_physics_process(enabled)

func _physics_process(delta: float) -> void:
	if not enabled or _aircraft == null:
		return
	_accum += delta
	var interval := 1.0 / maxf(rate_hz, 1.0)
	if _accum < interval:
		return
	_accum = 0.0
	_send_packet()

# ---------------------------------------------------------------------------
# Packet assembly
# ---------------------------------------------------------------------------
func _send_packet() -> void:
	if not _ensure_connection():
		return
	var fdm: Object = _aircraft.get("fdm") if _aircraft.has_method("get") else null
	if fdm == null or not fdm.has_method("get_state"):
		return
	var state: Dictionary = fdm.get_state()
	var controls: Dictionary = fdm.get_controls() if fdm.has_method("get_controls") else {}

	var pos: Vector3 = state.get("position", Vector3.ZERO)
	var vel: Vector3 = state.get("velocity", Vector3.ZERO)
	var ang: Vector3 = state.get("angular_velocity", Vector3.ZERO)
	var quat: Quaternion = state.get("orientation", Quaternion.IDENTITY)
	var rpm: float = float(state.get("engine_rpm", 0.0))

	var buf := StreamPeerBuffer.new()
	buf.big_endian = false
	# Header: magic (u32) + version (u16).
	buf.put_u32(PACKET_MAGIC)
	buf.put_u16(PROTOCOL_VERSION)
	# Timestamp (seconds since engine start).
	buf.put_float(float(Time.get_ticks_msec()) / 1000.0)
	# Position (3), attitude quaternion (4), velocity (3), angular velocity (3).
	buf.put_float(pos.x); buf.put_float(pos.y); buf.put_float(pos.z)
	buf.put_float(quat.x); buf.put_float(quat.y); buf.put_float(quat.z); buf.put_float(quat.w)
	buf.put_float(vel.x); buf.put_float(vel.y); buf.put_float(vel.z)
	buf.put_float(ang.x); buf.put_float(ang.y); buf.put_float(ang.z)
	# Motor RPM (1).
	buf.put_float(rpm)
	# Control surface deflections (4): aileron, elevator, rudder, throttle.
	buf.put_float(float(controls.get("aileron", 0.0)))
	buf.put_float(float(controls.get("elevator", 0.0)))
	buf.put_float(float(controls.get("rudder", 0.0)))
	buf.put_float(float(controls.get("throttle", 0.0)))

	_udp.put_packet(buf.data_array)

func _ensure_connection() -> bool:
	if _connected:
		return true
	var err := _udp.set_dest_address(host, port)
	if err != OK:
		push_error("[Telemetry] Invalid destination %s:%d (err %d)" % [host, port, err])
		return false
	_connected = true
	return true

func _exit_tree() -> void:
	_udp.close()
