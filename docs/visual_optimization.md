# Visual Optimization Guide

This document covers the rendering features added during the refinement phase
and how to keep RC-Flight-Sim fast on a wide range of hardware, including the
**GLES3 / Compatibility** renderer used for Web exports.

## Renderer compatibility

All shaders shipped under `godot_project/shaders/` are written for the
**Compatibility (GLES3)** backend as well as Forward+:

| Shader | Type | Notes |
| --- | --- | --- |
| `sky_clouds.gdshader` | `sky` | fBm value-noise clouds, time-of-day blend, stars. No compute / screen buffers. |
| `grass_wind.gdshader` | `spatial` | Vertex wind sway driven by per-vertex `COLOR.g`. `world_vertex_coords` for field-wide phase. |
| `aircraft_pbr.gdshader` | `spatial` | Albedo/metal/rough/normal + baked AO + livery decal. `detail_enabled` toggles detail work. |

Avoid Vulkan-only features (SDFGI, compute-based volumetrics, screen-space
reflections requiring the Forward+ buffers). Where an effect needs them, gate it
behind a graphics preset and provide a cheaper fallback.

## Graphics presets

`SettingsManager.PRESET_DETAILS` (see `scripts/autoload/settings_manager.gd`)
defines fine-grained controls per preset, queried with
`SettingsManager.get_preset_detail(key)`:

| Key | Low | Medium | High | Ultra |
| --- | --- | --- | --- | --- |
| `shadow_cascades` | 1 | 2 | 4 | 4 |
| `reflection_update` | disabled | once | once | always |
| `particle_count` | 0.25× | 0.5× | 1× | 1× |
| `cloud_quality` (fBm octaves) | 1 | 2 | 3 | 5 |
| `detail_maps` | off | on | on | on |

When the preset sets `detail_maps = off`, set the aircraft material's
`detail_enabled` shader parameter to `false` to skip normal/AO/decal sampling.
Set the sky's `cloud_quality` parameter from the preset to scale fBm octaves.

## Optimization techniques

- **Cloud quality LOD** — `cloud_quality` controls fBm octaves (1–5). Each
  dropped octave halves the noise cost; Low uses a single octave.
- **MultiMesh grass** — render grass as a single `MultiMeshInstance3D`; the
  vertex shader does the bending so there is zero per-blade CPU cost. Use
  `VisibleOnScreenNotifier3D` / visibility ranges to cull distant patches.
- **Visibility ranges & LOD** — set `visibility_range_begin/end` on aircraft and
  scenery `GeometryInstance3D`s, and enable automatic LOD in the model import
  settings (`Meshes > Generate LODs`). Use `AABB`-based ranges for swaps.
- **Reflection probes** — set update mode to `ONCE` on Medium/High and only use
  `ALWAYS` on Ultra. Bake static reflections where possible.
- **Shadows** — fewer cascades on Low; reduce `directional_shadow_max_distance`.
- **Particles** — multiply emitter `amount` by the preset `particle_count`
  factor; disable rain/snow entirely on Low.
- **Post-processing** — keep bloom/auto-exposure/color-grading in a single
  `Compositor`/`Environment` so they share buffers. Disable DOF and film grain
  outside cinematic mode.

## Profiling workflow

1. Enable **Debug ▸ Visible Collision Shapes** off; open **Monitors** and the
   **Profiler** in the editor.
2. Watch `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` and
   `RENDER_TOTAL_PRIMITIVES_IN_FRAME`. Grass and aircraft LODs should keep draw
   calls flat as the camera pulls back.
3. For Web builds, test in a browser with the same preset; the Compatibility
   renderer has different costs (no clustered lighting). Prefer fewer real-time
   lights.
4. Use the in-game telemetry HUD (`get_property_tree()`) to confirm physics rate
   is decoupled from frame rate — physics runs in `_physics_process`.
