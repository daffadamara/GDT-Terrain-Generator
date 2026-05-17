# GDT Terrain Generator

Godot 4.6 editor addon for generating static chunked 3D terrain with LODs, PBR texture layers, and game-ready collision baking.

## Install

1. Copy `addons/gdt_terrain/` into a Godot 4.6 project.
2. Enable `GDT Terrain Generator` in Project Settings > Plugins.
3. Add a `GdtTerrain3D` node from the Add Node dialog.

## Basic Workflow

1. Tune the terrain settings in the Inspector.
2. Use `Generate Preview` for quick iteration.
3. Pick a `Bake Preset`.
4. Use `Generate Final` for saved chunk meshes, LODs, materials, and optional collision.

Generated resources are saved to the user project at `res://generated_terrain/`. The addon does not delete user-generated terrain when disabled.

Texture layer mode can use any user-assigned PBR texture folders. If the optional example textures are not present, use Basic Colors mode or assign your own texture folders.
