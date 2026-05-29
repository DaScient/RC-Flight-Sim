# Scenery Creation Guide

This guide explains how to create new flying environments for **RC-Flight-Sim**.

---

## Overview

A scenery consists of:
- A **Godot scene** (`.tscn`) containing terrain, sky, lighting, and props.
- An optional **scenario JSON** file that defines wind, time-of-day, and other dynamic parameters.
- Assets: heightmaps, textures, meshes.

---

## Using Terrain3D

RC-Flight-Sim uses the [Terrain3D](https://github.com/TokisanGames/Terrain3D) addon for large outdoor environments.

### Setup

1. Open your scenery scene in Godot.
2. Add a `Terrain3D` node.
3. In the Inspector, set `Storage > Region Size` (default 1024 m is good for most fields).
4. Select the Terrain3D node and use the **Terrain Painter** toolbar at the top of the viewport.

### Heightmap Painting

- Use the **Sculpt** tool to raise/lower terrain.
- For a flat airfield, keep the base height at 0 m and sculpt gentle hills around the edges.
- Import a heightmap PNG via `Storage > Import Heightmap`.

### Texture Painting

1. In Terrain3D's texture panel, add texture layers (grass, dirt, asphalt).
2. Paint the runway strip using the asphalt texture.
3. Add a normal map for surface detail.

### Tree / Prop Placement

Use `MultiMeshInstance3D` for efficient tree placement:

```gdscript
# Example: scatter 500 trees using MultiMesh
var mm := MultiMesh.new()
mm.transform_format = MultiMesh.TRANSFORM_3D
mm.instance_count = 500
mm.mesh = load("res://assets/sceneries/props/tree_low.mesh")

for i in 500:
    var pos := Vector3(randf_range(-400, 400), 0, randf_range(-400, 400))
    mm.set_instance_transform(i, Transform3D(Basis(), pos))

$TreeLayer.multimesh = mm
```

Set `GeometryInstance3D.visibility_range_end` on the `MultiMeshInstance3D` to enable LOD (e.g., `300.0` metres).

---

## Scene Structure

```
SceneryName (Node3D)
├── WorldEnvironment        # Sky, ambient, fog
├── DirectionalLight3D      # Sun (driven by atmosphere.gd)
├── Terrain3D               # Ground terrain
├── Runway (MeshInstance3D or CSGBox3D)
├── Props (Node3D)
│   ├── TreeLayer (MultiMeshInstance3D)
│   ├── Hangar (MeshInstance3D)
│   └── PilotBox (MeshInstance3D)
├── AircraftSpawnPoint (Marker3D)
└── ScenarioData (Node)     # Holds scenario JSON path
```

---

## Scenario JSON

Place a `scenario.json` file alongside your scene:

```json
{
  "name":              "Default Airfield – Calm Morning",
  "wind_direction_deg": 270,
  "wind_speed_ms":      3.0,
  "wind_gust_max_ms":   5.0,
  "wind_turbulence":    0.2,
  "temperature_c":      18.0,
  "pressure_hpa":      1013.0,
  "start_time_h":       8.5,
  "time_scale":         1.0
}
```

Load it at runtime:

```gdscript
func _ready():
    var f := FileAccess.open("res://assets/sceneries/my_field/scenario.json", FileAccess.READ)
    var data: Dictionary = JSON.parse_string(f.get_as_text())
    Atmosphere.load_from_scenario(data)
```

---

## Sky and Lighting

Use a `ProceduralSkyMaterial` for a dynamic sky driven by `Atmosphere.time_of_day`:

```gdscript
func _process(delta):
    var sun_angle := Atmosphere.get_sun_angle_degrees()
    $DirectionalLight3D.rotation_degrees.x = sun_angle
    # Adjust sky energy based on time of day
    var energy := clampf(sin(deg_to_rad(sun_angle + 90.0)), 0.05, 1.0)
    $DirectionalLight3D.light_energy = energy * 2.0
```

---

## Indoor Arena

For indoor arenas, skip Terrain3D and use a simple enclosed room:

1. Model the arena in Blender and export as `.glb`.
2. Import into Godot, set up collision via `MeshInstance3D > Create Trimesh Static Body`.
3. Disable wind in the scenario JSON (`wind_speed_ms: 0`).

---

## Registering Your Scenery

1. Add your scenery to `SCENERY_LIST` in `scripts/ui/main_menu.gd`.
2. Create a thumbnail image (512×288 PNG) in your scenery folder.
3. Submit via pull request – see [contributing.md](contributing.md).
