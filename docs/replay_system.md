# Flight Replay System

The replay system records flight telemetry, lets you save and review flights
with a scrubber and graphs, and feeds segments to the AI for an annotated
debrief. It is part of **Phase 5.3** of Agentic Mode but works on its own.

---

## Components

| Component | File | Role |
|-----------|------|------|
| `FlightRecorder` (autoload) | `scripts/autoload/flight_recorder.gd` | Captures telemetry into a ring buffer; saves/loads replay files |
| `AgenticUtils` (replay helpers) | `scripts/agentic/agentic_utils.gd` | `ring_capacity`, `downsample_frames`, `summarize_replay`, timecodes, `parse_debrief_markers` (unit‑tested) |
| `AgenticManager` | `scripts/autoload/agentic_manager.gd` | `request_debrief()` → `debrief_received` + `markers_received` |

`FlightRecorder` is the stateful glue; all maths/parsing lives in `AgenticUtils`
so it can be tested headless (`tests/test_agentic_phase5.gd`,
`tests/test_agentic_integration.gd`).

---

## Recording

- Register the active aircraft once it spawns:
  `FlightRecorder.register_aircraft(aircraft)` (same shape `AgenticManager`
  expects — an object exposing `fdm.get_state()` / `fdm.get_controls()`).
- Call `FlightRecorder.start()` to begin recording and `stop()` to pause.
- Frames are captured at a fixed rate (default **50 Hz**, configurable with
  `set_rate(hz)`), independent of frame rate, by accumulating delta time.
- Only the last **5 minutes** (`RING_SECONDS`) are kept in memory — a true ring
  buffer (`ring_capacity(hz, seconds)` frames), so long sessions never grow
  unbounded.
- You can also feed frames manually with `push_frame(snapshot)` (used by tests
  and external feeders).

## Saving & loading

- **Save Replay** (pause menu) → `FlightRecorder.save_replay(name)` writes a
  ZSTD‑compressed binary to `user://replays/<slug>.rcfs` containing a small
  header (`magic`, `version`, `rate_hz`, `recorded_at`, `summary`) and the
  frames. Emits `replay_saved(path)`.
- `load_replay(path)` returns the payload `Dictionary`, or `{}` on any error or
  magic/version mismatch. `list_replays()` returns saved paths, newest first.

### File format (`.rcfs`, v1)

A single Godot `var` (via `store_var`/`get_var` with full‑object support off for
the frame data) holding:

```
{
  "magic": "RCFSREPLAY",
  "version": 1,
  "rate_hz": 50.0,
  "recorded_at": "2026-05-29T07:02:06",
  "summary": { "frames", "duration_s", "max_altitude_m", ... },
  "frames": [ { "airspeed_ms", "altitude_m", "roll_deg", ... }, ... ]
}
```

Each frame is a compact telemetry snapshot
(`AgenticUtils.build_telemetry_snapshot`).

---

## Replay viewer (`ReplayScreen`)

The viewer reuses the existing aircraft scene by feeding **recorded** state
instead of live FDM:

1. `FlightRecorder.load_replay(path)` → frames + summary.
2. A scrubber maps playback time → frame index (`time = index / rate_hz`).
3. Overlay graphs plot altitude, airspeed and G‑force from the frames; summary
   stats come from `AgenticUtils.summarize_replay()`.
4. Standard camera controls (the sim's existing camera rig) apply.

> Implementation note: the recorder, file format and analysis helpers are
> complete and tested. The on‑screen `ReplayScreen` widget is a thin Control
> that binds these APIs to a scrubber/graphs; wire it to your scene's camera rig
> as you would the live HUD.

---

## AI debrief & timeline markers

With Agentic Mode on and a replay loaded, **Analyze with AI**:

1. `FlightRecorder.get_ai_segment(max_samples)` down‑samples the flight
   (`AgenticUtils.downsample_frames`) so it fits an LLM prompt.
2. `AgenticManager.request_debrief(segment)` sends it.
3. The reply arrives on `debrief_received(text)`, and
   `markers_received(result)` carries
   `{ "summary": String, "markers": [ { "t": seconds, "label": String } ] }`.
4. Markers (e.g. *"Stall at 1:23 – nose too high"*) are placed on the scrubber
   and clicking one jumps playback to that time.

`AgenticUtils.parse_debrief_markers()` accepts either a structured
`{"summary":..,"markers":[{"t":83,"label":..}]}` block **or** plain prose with
`"<label> at M:SS"` phrases, and always returns time‑sorted markers.
