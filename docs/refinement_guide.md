# RC-Flight-Sim Refinement Guide

This guide summarizes the systems added/refactored during the refinement phase
and shows how to extend each one. All code is MIT-licensed, statically typed,
targets **Godot 4.2+**, and stays viable on the **GLES3 / Compatibility**
renderer for Web exports.

---

## 1. Code architecture (Part 4)

### Component-based aircraft
`scripts/flight_sim/aircraft_node.gd` is now a thin coordinator. Each frame it
ticks the FDM and dispatches to child components under
`scripts/flight_sim/components/`:

| Component | Responsibility |
| --- | --- |
| `propulsion.gd` | Throttle → thrust/RPM, audio pitch hook |
| `aerodynamics.gd` | Surface deflection → control response |
| `damage.gd` | Impact / prop-strike state |
| `sound.gd` | Engine/wind audio levels |

All extend `aircraft_component.gd`. To add a component: subclass the base,
implement `setup(aircraft)` and `physics_tick(delta, state)`, then add it as a
child of the aircraft node — `_setup_components()` discovers it automatically.

**Determinism:** all simulation runs in `_physics_process`; no `delta`-scaled
randomness. Keep new physics in `_physics_process` and seed any RNG explicitly.

### Utilities & tests
- `scripts/util/math_utils.gd` — `expo`, `deadzone`, `remap`, `exp_smooth`,
  `isa_density`, `safe_slerp`.
- `scripts/util/config_loader.gd` — `load_json_file`, `deep_merge`, `get_number`.
- Tests live in `godot_project/tests/`. Run headless:
  ```
  godot --headless --path godot_project --script tests/run_tests.gd
  ```
  Register a new `TestXxx` suite in the `suites` array in `run_tests.gd`.
  Assertions: `assert_true`, `assert_approx`.

---

## 2. Variable configurations (Part 2)

### Settings manager
`scripts/autoload/settings_manager.gd` persists a hierarchical settings tree
(Graphics / Controls / Audio / Simulation). Graphics presets are defined in
`PRESET_DETAILS`; query with `get_preset_detail(key)` (see
`docs/visual_optimization.md`).

### Aircraft tuning overrides
Drop a `tuning.json` next to an aircraft's config (e.g.
`assets/aircraft/trainer/tuning.json`). `FDMInterface.load_aircraft()`
deep-merges it over the base config and applies the values without editing
JSBSim XML. Supported tunables:

| Key | Effect |
| --- | --- |
| `engine_power_factor` | Thrust / engine power scale |
| `drag_multiplier` | Overall drag scale |
| `aileron_effectiveness` | Roll authority |
| `mass_factor` | Mass scale |
| `inertia_scale` | Rotational inertia scale |

Add a tunable by reading `cfg.get("<key>", 1.0)` in the FDM kinematic model and,
where applicable, mapping it to a JSBSim property in `_apply_tuning_to_jsbsim()`.

### Quick-Tune (in-flight)
`scripts/ui/quick_tune.gd` exposes the high-impact tunables on sliders, applies
them live (`apply_gain`), and can write them back via `save_to_tuning_json()`.
Toggle with the `quick_tune_toggle` input action.

### Controller profiles
`scripts/autoload/input_manager.gd` exports/imports `.rcprofile` JSON files:
`export_profile(path, name)` and `import_profile(path)` serialize the per-GUID
calibration dictionary so profiles can be shared.

---

## 3. Physics parameters & protocols (Part 3)

### Atmosphere
`scripts/flight_sim/atmosphere.gd` provides ISA `get_density_at_altitude`,
`get_temperature_at_altitude`, `get_pressure_at_altitude`, altitude-interpolated
`get_wind_at_altitude`, `set_surface_wind`, and `load_profile(path)` for custom
JSON atmospheres. The FDM uses density at altitude for lift/drag.

### JSBSim exposure
The GDExtension adds `get_property_tree()` returning the full property tree as a
`Dictionary`. `FDMInterface` exposes `get_property_tree()` and
`set_property(path, value)`. The sim console (`scripts/debug/sim_console.gd`)
implements `sim.set_property <path> <value>` for runtime tweaking; toggle with
`console_toggle`.

### Telemetry (UDP)
`scripts/net/telemetry_transmitter.gd` (autoload `TelemetryTransmitter`) sends a
**82-byte** little-endian packet at 20 Hz. Layout is documented in
`docs/telemetry_protocol.md`; the Python receiver/grapher is
`tools/telemetry_receiver.py`. **Keep `PACKET_MAGIC`, `PROTOCOL_VERSION`, and
the field order in sync across the transmitter, the doc, and the receiver.**

### Multiplayer & buddy-box
- `scripts/net/multiplayer_manager.gd` — ENet host/join, peer lifecycle.
- `scripts/net/remote_aircraft.gd` — interpolated/predicted remote state.
- `scripts/net/buddy_box.gd` — instructor/student control mixing; instructor
  takes over while holding `instructor_override`.

These are functional skeletons with `# TODO` markers for lag-compensation
tuning and full session management.

---

## 4. Visualization (Part 1)

See `docs/visual_optimization.md` for shaders, presets, and profiling. Key
pieces: `shaders/sky_clouds.gdshader`, `shaders/grass_wind.gdshader`,
`shaders/aircraft_pbr.gdshader`, the master
`assets/materials/standard_flight_material.tres`, and
`scripts/env/weather_controller.gd` (time-of-day, clouds, wind, precipitation).

---

## Project registration

New autoloads and input actions are registered in `godot_project/project.godot`:
- Autoloads: `TelemetryTransmitter` (plus existing `InputManager`,
  `SettingsManager`, `SceneManager`, `Atmosphere`).
- Input actions: `instructor_override`, `quick_tune_toggle`,
  `cinematic_toggle`, `console_toggle`.

## Extending the project — checklist
1. New script → static types, tab indentation, avoid `:=` from Variant
   expressions (Godot 4.2 treats it as a hard parse error).
2. New tunable → add to `tuning.json` keys + FDM read + (optional) JSBSim map.
3. New telemetry field → bump `PROTOCOL_VERSION`, update transmitter + doc +
   receiver together.
4. New shader → keep it GLES3-safe; gate Vulkan-only effects behind a preset.
5. Validate: import the project headless, then run `tests/run_tests.gd`.
