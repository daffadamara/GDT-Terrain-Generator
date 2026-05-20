# GDT Terrain Generator

GDT Terrain Generator is a Godot 4 editor addon for creating procedural 3D terrain. It adds a `GdtTerrain3D` node that can generate preview terrain while you work, then bake final terrain meshes, materials, LODs, and optional collision for gameplay.

## Features

- Procedural terrain from noise, with controls for seed, scale, resolution, height, and chunk count.
- Optional imported heightmap source.
- Fast preview generation and progressive final baking.
- Basic color material mode or layered PBR texture material mode.
- Distance-based LOD and viewport culling for large terrain previews.
- Collision bake presets for visual-only terrain, game-ready terrain, or higher accuracy collision.
- Native Godot `.tres` presets for saving and reusing terrain settings.
- Example scene with a playable character controller.

## Requirements

- Godot 4.6 or newer.
- Jolt Physics enabled in `project.godot` for the included demo scene.

## Installation

1. Copy `addons/gdt_terrain/` into your Godot project.
2. Open Project Settings > Plugins.
3. Enable `GDT Terrain Generator`.
4. Add a `GdtTerrain3D` node to your scene, or instance `res://addons/gdt_terrain/scenes/gdt_terrain_3d.tscn`.

## Basic Usage

1. Select the `GdtTerrain3D` node.
2. Adjust the terrain size, chunk resolution, seed, noise, and height settings in the Inspector.
3. Click `Generate Preview` while experimenting.
4. Choose a `Bake Preset`.
5. Click `Generate Final` when you want to save the terrain output.

Use `Clear Generated Terrain` if you want to remove the baked result and generate again.

## Bake Presets

- `Visual Only`: creates terrain meshes and materials without collision.
- `Game Ready`: creates terrain meshes, materials, and collision suitable for basic gameplay testing.
- `High Accuracy`: creates denser collision for more accurate physics.
- `Custom`: appears when advanced collision settings no longer match a preset.

Generated final resources are saved to `generated_terrain/`.

## Materials

The addon supports two material modes:

- `Basic Colors`: lightweight generated terrain colors.
- `Texture Layers`: PBR texture layers for lowland, ground, upper terrain, rocky terrain, cliff faces, and snow.

Texture folders can be assigned in the Inspector. The included demo project contains example material folders under `res://material/`.

## Presets And Heightmaps

Use `Save Preset` to store terrain settings as a Godot `.tres` resource, and `Load Preset` to reuse them later.

Use `Source Mode` to switch between procedural noise and imported PNG heightmaps. Heightmaps are mapped through the current `Height Scale`, so you can still tune the vertical strength after import.

## Example Scene

This repository includes `game_ready_demo.tscn`.

To try it:

1. Open `game_ready_demo.tscn`.
2. Select the `Terrain` node.
3. Keep `Bake Preset` set to `Game Ready`.
4. Click `Generate Final`.
5. Press Play and walk around the generated terrain.

The demo scene includes a simple character, camera, light, and terrain node so you can quickly test collision and movement.

## Disclaimer

This addon project is part of my hobby aside from my job. Created with the help of Codex. I will keep this updated when I have a free time. Thank you for your understanding.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/V7L61ZVBKK)

## License

MIT. See `LICENSE`.
