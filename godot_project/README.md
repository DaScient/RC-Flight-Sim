# RC-Flight-Sim — Godot Project

This folder contains the Godot 4 project for RC-Flight-Sim.

## Opening the Project

1. Download [Godot 4.2+](https://godotengine.org/download) (standard, non-Mono edition).
2. Launch Godot and click **Import**.
3. Navigate to this folder and select `project.godot`.
4. Click **Import & Edit**.
5. Press **F5** to run.

## Project Structure

```
godot_project/
├── assets/          Aircraft configs, scenery assets, UI resources
├── scripts/         GDScript source files
│   ├── autoload/    Singletons (auto-loaded on startup)
│   ├── camera/      Camera controller scripts
│   ├── controller/  Input calibration wizard
│   ├── flight_sim/  FDM interface, aircraft node, atmosphere
│   └── ui/          Menu and HUD scripts
├── addons/          Third-party addons (Terrain3D, JSBSim GDExtension)
├── scenes/          .tscn scene files
└── project.godot    Godot project configuration
```

## First Run Notes

- If the JSBSim extension `.dll`/`.so`/`.dylib` is missing from `../bin/`,
  the simulator falls back to the built-in kinematic physics model.
- See [../docs/build_instructions.md](../docs/build_instructions.md) to build the extension.
