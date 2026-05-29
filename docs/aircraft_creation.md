# Aircraft Creation Guide

This guide explains how to create a new aircraft for **RC-Flight-Sim**. Aircraft consist of two parts:

1. A **JSON configuration file** (`aircraft.json`) that defines aerodynamic and physical parameters.
2. An optional **JSBSim XML** flight-dynamics model (`aircraft_fdm.xml`) for high-fidelity simulation.
3. A **Godot scene** (`aircraft.tscn`) containing the 3D model, collision shapes, and audio.

---

## Quick Start

1. Copy the `godot_project/assets/aircraft/trainer/` folder and rename it.
2. Edit the JSON configuration with your aircraft's parameters.
3. Replace or update the 3D model in the Godot scene.
4. Register the aircraft name in `scripts/ui/main_menu.gd` → `AIRCRAFT_LIST`.

---

## JSON Configuration Reference

All keys are optional unless marked **required**.

```json
{
  "name":            "My Aircraft",     // Display name (required)
  "id":              "my_aircraft",     // Internal ID, no spaces (required)
  "jsbsim_xml":      "res://...",       // Path to JSBSim XML (optional – uses kinematic fallback)
  "model_scene":     "res://...",       // Path to .tscn Godot scene (required)

  // Physical properties
  "mass_kg":          1.5,              // All-up weight in kilograms
  "wingspan_m":       1.4,
  "wing_area_m2":     0.27,
  "aspect_ratio":     7.3,
  "oswald":           0.82,             // Oswald efficiency factor (0.6–0.9 typical)

  // Aerodynamic coefficients (kinematic fallback only; ignored when JSBSim XML is provided)
  "cl0":              0.35,             // Zero-alpha lift coefficient
  "cl_alpha":         5.1,              // Lift-curve slope (1/rad)
  "cd0":              0.032,            // Zero-lift drag coefficient

  // Propulsion
  "max_thrust_n":     18.0,             // Maximum static thrust (Newtons)
  "max_rpm":          9500,             // Maximum motor RPM (for audio scaling)
  "engine_type":      "electric_brushless",

  // Performance limits (kinematic fallback)
  "max_roll_rate_dps":  150.0,
  "max_pitch_rate_dps":  70.0,
  "max_yaw_rate_dps":    45.0,

  // RC control mixing
  "aileron_rate":     0.8,              // Scale factor applied to input (0–1)
  "elevator_rate":    0.75,
  "rudder_rate":      0.6,
  "expo":             0.25,             // Exponential curve (0 = linear, 1 = max expo)

  // Audio
  "sounds": {
    "motor": "res://assets/audio/motor_electric.ogg"
  }
}
```

---

## JSBSim XML Model

For a more realistic simulation, provide a full JSBSim aircraft definition.  
The XML format follows the [JSBSim Reference Manual](http://jsbsim.sourceforge.net/JSBSimReferenceManual/).

**Key sections required:**

| Section | Description |
|---------|-------------|
| `<metrics>` | Wing area, span, MAC, tail geometry |
| `<mass_balance>` | Empty weight, CG location, moments of inertia |
| `<ground_reactions>` | Landing gear / contact points |
| `<propulsion>` | Engine and propeller definitions |
| `<flight_control>` | FCS (servo mixing, surfaces) |
| `<aerodynamics>` | Lift, drag, side force, moment coefficients |

See `godot_project/assets/aircraft/trainer/trainer_fdm.xml` for a complete example.

**Units:** JSBSim natively uses US customary (fps, slugs, lb) but `unit=` attributes allow SI input.

---

## Godot 3D Scene

The aircraft scene must have this node structure:

```
AircraftName (Node3D + aircraft_node.gd)
├── FDMInterface (Node + fdm_interface.gd)
├── MeshInstance3D (visual model)
├── CollisionShape3D
├── PropellerMesh (MeshInstance3D, optional)
├── FPVCamera (Camera3D + fpv_camera.gd)
└── EngineAudio (AudioStreamPlayer3D)
```

Export these properties on the root node:
- `aircraft_config_path` – path to the JSON config
- `engine_audio` – drag the `EngineAudio` node here
- `propeller_mesh` – drag the propeller mesh here

---

## Testing Your Aircraft

1. Open Godot, go to `scenes/main.tscn`.
2. In the `Aircraft` node, change `aircraft_config_path` to your new config.
3. Press **F5** to run. Use keyboard WASD (aileron/elevator) and Arrow Up/Down (throttle) without a controller.
4. Check the HUD for airspeed and altitude readouts.

---

## Submitting to the Community

1. Fork the repository.
2. Add your aircraft folder to `godot_project/assets/aircraft/<your_id>/`.
3. Open a pull request with screenshots and a brief description.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the full contribution workflow.
