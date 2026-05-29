## multiplayer_manager.gd
## Peer-to-peer multiplayer session manager (Part 3D) built on Godot's
## high-level networking (ENetMultiplayerPeer + RPC). Handles hosting/joining,
## a lightweight chat channel and broadcasting of remote aircraft state for
## interpolation by RemoteAircraft nodes.
##
## This is an integration skeleton: the transport, session lifecycle, chat and
## the state-broadcast RPC are implemented; visual spawning of remote aircraft
## and full SceneReplication wiring are marked with TODOs because they depend
## on the project's aircraft scenes.
class_name MultiplayerManager
extends Node

signal session_started(is_server: bool)
signal session_ended()
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)
signal chat_received(peer_id: int, message: String)
## Emitted for each remote state update; RemoteAircraft listens and interpolates.
signal remote_state_received(peer_id: int, state: Dictionary)

const DEFAULT_PORT: int = 9050
const MAX_PLAYERS: int = 8

var _peer: ENetMultiplayerPeer = null

# ---------------------------------------------------------------------------
# Session lifecycle
# ---------------------------------------------------------------------------
func host_game(port: int = DEFAULT_PORT) -> bool:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("[MP] Failed to create server on port %d (err %d)" % [port, err])
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	_connect_signals()
	session_started.emit(true)
	return true

func join_game(address: String, port: int = DEFAULT_PORT) -> bool:
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(address, port)
	if err != OK:
		push_error("[MP] Failed to connect to %s:%d (err %d)" % [address, port, err])
		_peer = null
		return false
	multiplayer.multiplayer_peer = _peer
	_connect_signals()
	session_started.emit(false)
	return true

func leave_game() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	session_ended.emit()

func is_active() -> bool:
	return _peer != null

# ---------------------------------------------------------------------------
# State broadcast (interpolated on receivers)
# ---------------------------------------------------------------------------
## Called locally each network tick to share this player's aircraft state.
## Sends an unreliable, compact snapshot to all peers.
func broadcast_state(state: Dictionary) -> void:
	if not is_active():
		return
	var payload := {
		"position": state.get("position", Vector3.ZERO),
		"orientation": state.get("orientation", Quaternion.IDENTITY),
		"velocity": state.get("velocity", Vector3.ZERO),
		"t": Time.get_ticks_msec(),
	}
	_rpc_state.rpc(payload)

@rpc("any_peer", "call_remote", "unreliable")
func _rpc_state(payload: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	remote_state_received.emit(sender, payload)

# ---------------------------------------------------------------------------
# Chat
# ---------------------------------------------------------------------------
func send_chat(message: String) -> void:
	if not is_active():
		return
	_rpc_chat.rpc(message)
	# Echo locally so the sender also sees their message.
	chat_received.emit(multiplayer.get_unique_id(), message)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_chat(message: String) -> void:
	chat_received.emit(multiplayer.get_remote_sender_id(), message)

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------
func _connect_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_connected(peer_id: int) -> void:
	# TODO: spawn a RemoteAircraft instance for peer_id using the project's
	# aircraft scene, and register it with SceneReplication for the host.
	peer_joined.emit(peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	# TODO: free the RemoteAircraft instance associated with peer_id.
	peer_left.emit(peer_id)
