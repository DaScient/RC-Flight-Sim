# Build Instructions

This document explains how to build RC-Flight-Sim from source on Windows, Linux, and macOS.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| [Godot 4](https://godotengine.org/download) | 4.2+ | Use the standard (non-Mono) build |
| CMake | 3.22+ | For the C++ GDExtension |
| C++ compiler | GCC 11+ / Clang 14+ / MSVC 2022 | |
| Git | Any | For submodule management |
| Python 3 | 3.8+ | Required by `godot-cpp` SConstruct (if using SCons) |

---

## 1 – Clone the Repository

```bash
git clone https://github.com/DaScient/RC-Flight-Sim.git
cd RC-Flight-Sim
# Initialise submodules (godot-cpp, JSBSim, Terrain3D)
git submodule update --init --recursive
```

Expected submodule layout:
```
RC-Flight-Sim/
├── godot-cpp/                        # godot-cpp binding library
├── jsbsim/                           # JSBSim flight dynamics library
└── godot_project/addons/terrain_3d/  # Terrain3D Godot addon
```

---

## 2 – Build the JSBSim GDExtension

```bash
cd godot_project/addons/jsbsim_gdextension

# Configure (JSBSim and godot-cpp must be submodules at repo root)
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DGODOT_CPP_DIR=../../../godot-cpp \
  -DJSBSIM_DIR=../../../jsbsim

# Build
cmake --build build --config Release -j$(nproc)
```

The compiled library is automatically copied to `godot_project/bin/`:
- `jsbsim_gdextension.dll` (Windows)
- `jsbsim_gdextension.so` (Linux)
- `jsbsim_gdextension.dylib` (macOS)

### Stub build (no JSBSim – kinematic fallback only)

```bash
cmake -B build -DJSBSIM_ENABLED=OFF -DGODOT_CPP_DIR=../../../godot-cpp
cmake --build build --config Release
```

This is sufficient to run the simulator; it uses the built-in kinematic physics model.

---

## 3 – Open the Godot Project

1. Launch Godot 4.
2. Click **Import** and navigate to `godot_project/project.godot`.
3. Godot will import all assets. This may take a minute on first run.
4. Press **F5** to run.

> **No JSBSim library?** The project will still run using the kinematic fallback physics.
> You will see a warning: `[FDMInterface] Using kinematic fallback backend.`

---

## 4 – Export the Project

Godot's export templates must be installed first:

1. In Godot, go to **Editor → Manage Export Templates** and download the templates for your Godot version.
2. Go to **Project → Export**, select a platform preset, and click **Export Project**.

### CI / Automated Builds

GitHub Actions handles automated builds on push to `main`.  
See `.github/workflows/build.yml` for the full pipeline which exports for:
- Windows (x86_64)
- Linux (x86_64)
- macOS (Universal)
- Android (arm64-v8a)
- Web (HTML5)

---

## 5 – Running Tests

Currently, unit tests are run via Godot's built-in test runner.  
From the project root:

```bash
godot --headless --path godot_project/ -s addons/gut/gut_cmdln.gd \
  -gdir=res://tests/ -ginclude_subdirs -gexit
```

> Requires the [GUT](https://github.com/bitwes/Gut) addon (add as a submodule if needed).

---

## Platform-Specific Notes

### Windows

- Use **Visual Studio 2022** or **MSYS2 MinGW-w64** (GCC).
- When using MSVC, open a **Developer Command Prompt** before running CMake.
- JSBSim requires the Windows SDK and may need `expat` (included in the JSBSim repo).

### macOS

- Install Xcode Command Line Tools: `xcode-select --install`
- On Apple Silicon: CMake will produce a universal binary if you add `-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"`.

### Linux

```bash
sudo apt install cmake build-essential libexpat1-dev
```

### Android (cross-compile)

Cross-compilation requires the Android NDK. Set `ANDROID_ABI=arm64-v8a` and
`ANDROID_NDK_HOME` in your environment, then pass the NDK toolchain to CMake:

```bash
cmake -B build_android \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_PLATFORM=android-24 \
  -DGODOT_CPP_DIR=../../../godot-cpp \
  -DJSBSIM_ENABLED=OFF
cmake --build build_android --config Release
```

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `godot-cpp not found` | Run `git submodule update --init --recursive` |
| Extension loads but JSBSim is inactive | Check `bin/` for the compiled `.dll`/`.so` |
| `Class JSBSimFDM not found` | Ensure `jsbsim_extension.gdextension` is in `addons/jsbsim_gdextension/` |
| Black screen on startup | Set rendering method to `gl_compatibility` in `project.godot` |
| No joystick detected | Check OS permissions; on Linux add user to `input` group |
