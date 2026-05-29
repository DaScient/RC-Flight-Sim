# bin/

This directory holds the pre-compiled JSBSim GDExtension shared libraries.

## Platform files expected

| Platform | File |
|----------|------|
| Windows x86_64 | `jsbsim_gdextension.dll` |
| Linux x86_64 | `jsbsim_gdextension.so` |
| macOS (Universal) | `jsbsim_gdextension.dylib` |
| Android arm64-v8a | `jsbsim_gdextension.arm64-v8a.so` |

## Building the extension

See [docs/build_instructions.md](../docs/build_instructions.md) for full build steps.

Quick stub build (kinematic fallback, no JSBSim dependency):

```bash
cd godot_project/addons/jsbsim_gdextension
cmake -B build -DCMAKE_BUILD_TYPE=Release -DJSBSIM_ENABLED=OFF -DGODOT_CPP_DIR=../../../../godot-cpp
cmake --build build --config Release
```
