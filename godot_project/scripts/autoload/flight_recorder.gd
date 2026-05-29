## flight_recorder.gd
## Autoload singleton that records the aircraft's telemetry into a rolling ring
## buffer (Phase 5.3) and can persist full replays to disk.
##
## Design:
##   * Captures at a fixed rate (default 50 Hz) independent of frame rate, by
##     accumulating delta time. Each captured frame is a compact telemetry
##     snapshot (see AgenticUtils.build_telemetry_snapshot).
##   * Keeps only the last RING_SECONDS of flight in memory (a true ring buffer)
##     so long sessions never grow unbounded.
##   * "Save Replay" writes the in-memory frames to user://replays/ as a
##     compressed binary file with a small JSON header (see docs/replay_system).
##   * All maths (capacity, summary, down-sampling) lives in AgenticUtils so it
##     is unit-tested; this file is the stateful glue.
extends Node

## Magic + version stamped into every replay header so future formats can be
## migrated/rejected cleanly.
const REPLAY_MAGIC := "RCFSREPLAY"
const REPLAY_VERSION := 1

const REPLAY_DIR := "user://replays/"

## Capture rate (Hz) and how many seconds the in-memory ring buffer keeps.
const DEFAULT_RATE_HZ := 50.0
const RING_SECONDS := 300.0  # 5 minutes

signal recording_changed(active: bool)
signal replay_saved(path: String)

var rate_hz: float = DEFAULT_RATE_HZ
var recording: bool = false

var _aircraft: Node = null
var _buffer: Array = []
var _capacity: int = 0
var _accum: float = 0.0
var _interval: float = 1.0 / DEFAULT_RATE_HZ

func _ready() -> void:
	_recompute_capacity()
	_ensure_dir()
	set_process(false)

func _recompute_capacity() -> void:
	_capacity = AgenticUtils.ring_capacity(rate_hz, RING_SECONDS)
	_interval = 1.0 / maxf(1.0, rate_hz)

func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(REPLAY_DIR):
		DirAccess.make_dir_recursive_absolute(REPLAY_DIR)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
## Register the aircraft to record from (same shape AgenticManager expects:
## an object exposing `fdm` with get_state()/get_controls()). Pass null to stop.
func register_aircraft(aircraft: Node) -> void:
	_aircraft = aircraft

## Set the capture rate (Hz). Resizes the ring buffer capacity to keep the same
## RING_SECONDS window.
func set_rate(hz: float) -> void:
	rate_hz = maxf(1.0, hz)
	_recompute_capacity()

## Begin/resume recording. Clears any existing buffer when [param fresh] is true.
func start(fresh: bool = true) -> void:
	if fresh:
		_buffer.clear()
	_accum = 0.0
	recording = true
	set_process(true)
	recording_changed.emit(true)

## Pause recording (keeps the buffer so it can be saved or resumed).
func stop() -> void:
	recording = false
	set_process(false)
	recording_changed.emit(false)

## Manually append a telemetry snapshot (used by tests and external feeders).
func push_frame(frame: Dictionary) -> void:
	if _capacity <= 0:
		_recompute_capacity()
	_buffer.append(frame)
	while _buffer.size() > _capacity:
		_buffer.pop_front()

## Number of frames currently buffered.
func frame_count() -> int:
	return _buffer.size()

## A defensive copy of the buffered frames (oldest first).
func get_frames() -> Array:
	return _buffer.duplicate(true)

## Summary stats over the buffered flight (see AgenticUtils.summarize_replay).
func get_summary() -> Dictionary:
	return AgenticUtils.summarize_replay(_buffer, rate_hz)

## A down-sampled copy suitable for an LLM prompt (see AgenticManager debrief).
func get_ai_segment(max_samples: int = 60) -> Array:
	return AgenticUtils.downsample_frames(_buffer, max_samples)

## Persist the current buffer to user://replays/ as a compressed binary file.
## Returns the saved path, or "" on failure. [param name] is slugified.
func save_replay(name: String = "") -> String:
	_ensure_dir()
	if _buffer.is_empty():
		return ""
	var slug := AgenticUtils.slugify(name) if name != "" else "replay_" + str(Time.get_unix_time_from_system())
	var path := REPLAY_DIR + slug + ".rcfs"
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return ""
	var payload := {
		"magic": REPLAY_MAGIC,
		"version": REPLAY_VERSION,
		"rate_hz": rate_hz,
		"recorded_at": Time.get_datetime_string_from_system(),
		"summary": get_summary(),
		"frames": _buffer,
	}
	file.store_var(payload, true)
	file.close()
	replay_saved.emit(path)
	return path

## Load a replay file written by save_replay(). Returns {} on any error or
## version/magic mismatch.
func load_replay(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return {}
	var data: Variant = file.get_var(true)
	file.close()
	if not (data is Dictionary):
		return {}
	var d: Dictionary = data
	if String(d.get("magic", "")) != REPLAY_MAGIC or int(d.get("version", 0)) != REPLAY_VERSION:
		return {}
	return d

## List saved replay file paths (newest first by name).
func list_replays() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(REPLAY_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".rcfs"):
			out.append(REPLAY_DIR + f)
	out.sort()
	out.reverse()
	return out

# ---------------------------------------------------------------------------
# Capture loop
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not recording or _aircraft == null:
		return
	_accum += delta
	if _accum < _interval:
		return
	_accum = 0.0
	var frame := _capture_frame()
	if not frame.is_empty():
		push_frame(frame)

func _capture_frame() -> Dictionary:
	var fdm: Object = _aircraft.get("fdm")
	if fdm == null or not fdm.has_method("get_state"):
		return {}
	var controls: Dictionary = fdm.get_controls() if fdm.has_method("get_controls") else {}
	return AgenticUtils.build_telemetry_snapshot(fdm.get_state(), controls)
