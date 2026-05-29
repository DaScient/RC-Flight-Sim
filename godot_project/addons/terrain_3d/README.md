# Terrain3D Addon

This directory should contain the [Terrain3D](https://github.com/TokisanGames/Terrain3D) Godot addon.

## Setup

Add Terrain3D as a git submodule:

```bash
git submodule add https://github.com/TokisanGames/Terrain3D godot_project/addons/terrain_3d
git submodule update --init --recursive
```

Or download the latest release from:
https://github.com/TokisanGames/Terrain3D/releases

and extract it here so that this folder contains:
```
terrain_3d/
├── addons/
│   └── terrain_3d/
│       ├── plugin.cfg
│       └── ...
```

After adding the addon, enable it in Godot via **Project → Project Settings → Plugins → Terrain3D**.
