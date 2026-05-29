# Experimental Agentic Mode (LLM Integration)

> **Status:** Experimental, **opt‑in**, and **off by default**.
> Agentic Mode brings an LLM‑powered flight instructor, AI co‑pilot, scenario
> generator and post‑flight debrief to RC‑Flight‑Sim. It uses **your own** API
> key (BYO‑key) and an OpenAI‑compatible endpoint, so you stay in control of
> cost and provider.

---

## Quick start

1. Launch the sim. A small, semi‑transparent **`AI`** pill appears in the
   top‑right corner of the screen (the *hidden‑hover toggle*). Hover it to
   expand the **Agentic Mode** checkbox.
2. Open **Settings → Agentic AI** and paste your API key. Optionally change the
   endpoint and model (defaults target OpenAI `gpt-4o-mini`).
3. Toggle **Agentic Mode** on. You'll start receiving short instructor tips and
   gain access to grading, the AI co‑pilot, scenario generation and debriefs.

If you have no key, the toggle is greyed out and clicking it routes you to the
settings tab. With the mode on but a request failing, the sim falls back to
local rule‑based tips — **it never breaks the simulation**.

---

## Architecture

| Component | File | Role |
|-----------|------|------|
| `AgenticManager` (autoload) | `scripts/autoload/agentic_manager.gd` | State, async HTTP, queue/throttle, routing, fallback, owns the overlay UI |
| `AgenticUtils` | `scripts/agentic/agentic_utils.gd` | **Pure** helpers: snapshots, control clamping/safety, maneuver parsing, request/response, scenario validation, key obfuscation (fully unit‑tested) |
| `AgenticCopilot` | `scripts/agentic/agentic_copilot.gd` | Plays back a timed control sequence with user‑override + safety disengage |
| `AgenticTTS` | `scripts/agentic/agentic_tts.gd` | Speech: native `DisplayServer` TTS or browser Web Speech API |
| `AgenticToggle` | `scripts/ui/agentic_toggle.gd` | Hidden‑hover top‑right toggle |
| `AgenticHUD` | `scripts/ui/agentic_hud.gd` | Tips, co‑pilot status, "grade"/"demo" actions, rolling telemetry history |
| `DebriefScreen` | `scripts/ui/debrief_screen.gd` | Post‑flight AI debrief panel |

All network/UI state lives in `AgenticManager`; all parsing/clamping/maths live
in `AgenticUtils` so they can be tested headless (`tests/test_agentic_utils.gd`).

### Data flow

```
AircraftNode ── telemetry ──▶ AgenticManager ──▶ AgenticUtils.build_telemetry_snapshot()
                                   │
                                   ├── throttled tip request (every 12 s)
                                   ├── grade / scenario / debrief (one‑shot)
                                   └── maneuver request ─▶ AgenticCopilot.engage()
                                                                │
AircraftNode ◀── control override ──── AgenticManager.get_copilot_override()
```

---

## Features

### 3.3 Flight instructor & maneuver grading
- A compact telemetry snapshot (airspeed, altitude, AoA, attitude, controls) is
  sent every `TIP_INTERVAL_SEC` (12 s) with an instructor prompt; the reply is
  shown on the `AgenticHUD` for a few seconds and optionally spoken.
- **Grade last 10 s** sends a burst of recent snapshots and shows a score + tips.

### 3.4 AI co‑pilot (assisted control)
- Type a maneuver ("show me a loop") and press **Demo**. The LLM returns a JSON
  array of timed control keyframes; `AgenticCopilot` plays it back through the
  FDM, overriding your sticks.
- **Safety:** every keyframe is clamped (`aileron/elevator/rudder ∈ [-1,1]`,
  `throttle ∈ [0,1]`). If the aircraft exceeds the safety envelope
  (`AgenticUtils.DEFAULT_SAFETY_LIMITS`) the co‑pilot disengages instantly.
- **Override:** moving any stick beyond `OVERRIDE_THRESHOLD` returns control to
  you immediately.

### 3.5 Dynamic scenario generation
- Describe what you want to practice; the LLM returns a JSON scenario that is
  **whitelisted/clamped** by `AgenticUtils.validate_scenario()` so it can only
  reference known aircraft/sceneries and sane wind/turbulence/time values.

### 3.6 Telemetry debriefing
- `DebriefScreen` (open from the pause menu) sends the rolling flight log and
  shows a "what went well / improve / practice plan" debrief.

### 3.7 / 3.8 Hidden toggle & graceful degradation
- The toggle persists its state via `SettingsManager`.
- No key → greyed out; failed call → local rule‑based tips
  (`AgenticUtils.local_fallback_tip()`).

---

## Configuration (Settings → Agentic AI)

| Setting key | Default | Notes |
|-------------|---------|-------|
| `agentic_enabled` | `false` | Master toggle |
| `agentic_endpoint` | `https://api.openai.com/v1/chat/completions` | Any OpenAI‑compatible endpoint (Together AI, **LM Studio** `http://localhost:1234/v1/chat/completions`, etc.) |
| `agentic_model` | `gpt-4o-mini` | Model name passed to the endpoint |
| `agentic_key_obf` | `""` | API key, **obfuscated** at rest (see below) |
| `agentic_voice_enabled` | `true` | Speak tips via TTS |

### Using a local LLM (no cost, offline)
Point the endpoint at a local server such as **LM Studio** or **Ollama** (with
its OpenAI‑compatible shim) and use any string for the key. Example:

```
endpoint = http://localhost:1234/v1/chat/completions
model    = your-local-model
```

---

## Security & cost warnings

- **API costs are yours.** Each tip/grade/maneuver/debrief is a paid request on
  hosted providers. Tips are throttled to one every 12 s, but grading, demos and
  debriefs are on‑demand. Use a local endpoint to avoid charges.
- **Key storage is NOT hardened.** Because this is an open‑source project, the
  key is only **obfuscated** (XOR with a device‑derived seed + Base64) via
  `AgenticUtils.obfuscate_key()` — this stops it sitting in plain text in
  `settings.cfg`, but it is *not* encryption. Do not use a high‑privilege key.
- All LLM calls are **non‑blocking** (`HTTPRequest` + `request_completed`); the
  main thread is never stalled. Only one request is in flight at a time; the
  rest queue.

---

## Extending Agentic Mode

- **New request type:** add a `KIND_*` constant, a `request_*()` method that
  enqueues `AgenticUtils.build_chat_request_body(...)`, and a branch in
  `_route_response()`.
- **Custom safety envelope per aircraft:** add `safety_min_altitude_m` (and
  future keys) to the aircraft JSON; `AgenticManager._copilot_limits()` forwards
  them to the co‑pilot.
- **Testing:** keep new logic in `AgenticUtils` as `static` functions and add
  cases to `tests/test_agentic_utils.gd` so they run headless in CI.
