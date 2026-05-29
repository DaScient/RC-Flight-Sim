# RC Flight Sim
## DaScient, Inc. | 2026

> **Free, open-source, community-driven RC flight simulator built with Godot 4.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Godot 4.2+](https://img.shields.io/badge/Godot-4.2%2B-blue.svg)](https://godotengine.org)
[![Build Status](https://github.com/DaScient/RC-Flight-Sim/actions/workflows/build.yml/badge.svg)](https://github.com/DaScient/RC-Flight-Sim/actions)

RC-Flight-Sim is a realistic, physics-accurate RC aircraft simulator that runs on everything from
integrated graphics (Intel HD 4000) to high-end GPUs. It supports USB RC dongles, gamepads,
keyboard, and touch controls – out of the box, with no special drivers required.

---

## ✈️ Features

| Feature | Details |
|---------|---------|
| **Physics** | Full 6-DOF aerodynamics via JSBSim (stall, spin, knife-edge, P-factor, ground effect) |
| **Aircraft** | High-wing trainer, 3D aerobat, scale turbine jet – data-driven XML/JSON |
| **Controller** | Any USB RC dongle (HID joystick), Xbox, PlayStation, keyboard, touch; calibration wizard |
| **Environments** | Outdoor airfield, indoor arena; dynamic time-of-day & weather (wind affects FDM) |
| **Cameras** | FPV, Chase (spring-arm), Stationary (pilot box), Tower, Free Orbit |
| **Rendering** | GL Compatibility (low-end) → Forward+ Vulkan (high-end); dynamic shadows, post-FX |
| **Extensible** | Hot-loadable aircraft and sceneries; community Aircraft/Scenery Developer Kit |
| **Agentic AI** | Opt-in [Experimental Agentic Mode](docs/agentic_mode.md): BYO-key LLM flight instructor, AI co-pilot, scenario generator & debrief |
| **Platforms** | Windows, Linux, macOS, Android, Web |

---

## 🚀 Quick Start

### Option A – Download a Release

Grab the latest binary from the [Releases](https://github.com/DaScient/RC-Flight-Sim/releases) page.

### Option B – Run from Source

```bash
# 1. Clone with submodules
git clone --recurse-submodules https://github.com/DaScient/RC-Flight-Sim.git
cd RC-Flight-Sim

# 2. (Optional) Build the JSBSim GDExtension for high-fidelity physics
cd godot_project/addons/jsbsim_gdextension
cmake -B build -DCMAKE_BUILD_TYPE=Release -DJSBSIM_ENABLED=OFF -DGODOT_CPP_DIR=../../../godot-cpp
cmake --build build --config Release
cd ../../..

# 3. Open Godot 4.2+ and import godot_project/project.godot
# 4. Press F5 to fly!
```

> Without compiling the GDExtension the simulator runs with the built-in kinematic physics
> model – perfect for testing input and camera systems.

See [docs/build_instructions.md](docs/build_instructions.md) for full platform-specific details.

---

## 🎮 Controls

### Keyboard (no controller)

| Key | Action |
|-----|--------|
| W / S | Elevator (pitch) |
| A / D | Aileron (roll) |
| Q / E | Rudder (yaw) |
| ↑ / ↓ | Throttle up / down |
| F1 | FPV camera |
| F2 | Chase camera |
| F3 | Stationary camera |
| F4 | Tower camera |
| F5 | Free orbit camera |
| Tab | Cycle cameras |
| Escape | Pause / Menu |

### USB RC Dongle / Joystick

Connect your transmitter's USB dongle before launching. RC-Flight-Sim auto-detects it and
applies a default channel mapping (Aileron/Elevator/Throttle/Rudder → axes 0-3).  
Run the **Calibration Wizard** (Main Menu → Calibrate) for accurate endpoint/direction/deadzone
settings that are saved per-device GUID.

---

## 📁 Repository Structure

```
RC-Flight-Sim/
├── godot_project/          Godot 4 project
│   ├── assets/
│   │   ├── aircraft/       JSON + JSBSim XML configs per aircraft type
│   │   ├── sceneries/      Heightmaps, textures, scenario JSON
│   │   └── ui/             Fonts, icons, themes
│   ├── scripts/
│   │   ├── autoload/       Singletons: InputManager, SettingsManager, SceneManager
│   │   ├── flight_sim/     FDMInterface, AircraftNode, Atmosphere
│   │   ├── camera/         CameraManager + 5 camera types
│   │   ├── controller/     CalibrationWizard
│   │   └── ui/             MainMenu, SettingsMenu, HUD
│   ├── addons/
│   │   ├── terrain_3d/     Terrain3D addon (git submodule)
│   │   └── jsbsim_gdextension/  C++ GDExtension wrapping JSBSim
│   └── scenes/             .tscn scene files
├── docs/                   Aircraft/Scenery creation guides, build instructions
├── bin/                    Pre-compiled extension binaries (platform-specific)
└── .github/                CI/CD workflows, issue templates
```

---

## ✏️ Create Your Own Aircraft

See [docs/aircraft_creation.md](docs/aircraft_creation.md) for the full guide.

The short version:
1. Copy `godot_project/assets/aircraft/trainer/` and rename it.
2. Edit `aircraft.json` with your aircraft's parameters.
3. (Optional) Write a JSBSim XML for high-fidelity aerodynamics.
4. Add your aircraft to `AIRCRAFT_LIST` in `scripts/ui/main_menu.gd`.

---

## 🌄 Create Your Own Scenery

See [docs/scenery_creation.md](docs/scenery_creation.md) for the full guide.

Uses the [Terrain3D](https://github.com/TokisanGames/Terrain3D) addon for GPU-accelerated
heightmap terrain with painted textures, satellite imagery support, and MultiMesh tree
placement.

---

## 🏗️ Technology Stack

| Component | Technology | License |
|-----------|-----------|---------|
| Game Engine | [Godot 4](https://godotengine.org) | MIT |
| Flight Dynamics | [JSBSim](https://github.com/JSBSim-Team/jsbsim) | LGPL |
| Terrain | [Terrain3D](https://github.com/TokisanGames/Terrain3D) | MIT |
| Input | Godot built-in (SDL) | MIT |
| Audio | Godot AudioServer | MIT |
| Starter Models | [Kenney.nl](https://kenney.nl), OpenGameArt | CC0 |

---

## 🤝 Contributing

All contributions are welcome! Please read [docs/contributing.md](docs/contributing.md) first.

- 🐛 **Bug reports** → [GitHub Issues](https://github.com/DaScient/RC-Flight-Sim/issues)
- ✨ **Feature requests** → [GitHub Issues](https://github.com/DaScient/RC-Flight-Sim/issues)
- 🔀 **Pull requests** → [GitHub PRs](https://github.com/DaScient/RC-Flight-Sim/pulls)
- 💬 **Discussions** → [GitHub Discussions](https://github.com/DaScient/RC-Flight-Sim/discussions)

---

## 📜 License

- **Code** (`.gd`, `.cpp`, `.h`, `.yml`, etc.): [MIT License](LICENSE) © 2026 DASCIENT, INC.
- **Art Assets**: [CC0](https://creativecommons.org/publicdomain/zero/1.0/) or
  [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) – see individual asset folders.
