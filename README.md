# GDT Terrain Generator

Procedural terrain generator for Godot 4.6, packaged as an editor addon with a `GdtTerrain3D` custom node. It generates chunked terrain from noise, supports high-resolution final builds, and includes procedural terrain materials, distance LOD, culling, and game-ready collision bake presets.

## Features

- Chunked static terrain generation with configurable terrain size, per-chunk resolution, and chunk count.
- Fast preview mode and progressive final generation to keep the editor responsive.
- Noise controls for seed, terrain scale, frequency, octaves, lacunarity, gain, and height scale.
- Shared heightfield pipeline with noise or imported 16-bit PNG heightmaps.
- Terrain3D-inspired region data resources for final terrain metadata, queries, painting, and scatter.
- Public terrain query API for height, normal, slope, region lookup, and projecting positions onto terrain.
- Native Godot `.tres` terrain presets for saving and loading styles/settings.
- Heightmap import/export for PNG, EXR, and R16/RAW workflows.
- Material mask painting-lite API for editing visual layer influence without height sculpting.
- Deterministic static MultiMesh scatter foundation with cell-based culling.
- Visual material modes for basic generated colors or imported PBR texture layers.
- Configurable texture layers for sand, forest ground, upper grass/rock, rocky terrain, cliff faces, and snow.
- Shader-based stochastic texture bombing to reduce obvious tiling on large terrain surfaces.
- Terrain performance presets for quality, balanced, or performance rendering budgets.
- High-view LOD bias, visible LOD counters, and estimated visible triangle counts for all-visible terrain profiling.
- Distance-based material quality so far terrain uses cheaper shader paths.
- Optional baked far-material color cache for final terrain, giving a lightweight virtual-texture-like far view without runtime page streaming.
- Editable grass, lowland, rock, and optional snow colors without rebuilding terrain when using the basic color mode.
- Legacy vertex-color fallback for older generated V4 chunks.
- External binary `.res` mesh saving so large final terrain does not bloat the text scene.
- Saved mesh LODs for final terrain:
  - LOD 0: full resolution
  - LOD 1: half resolution
  - LOD 2: quarter resolution
  - LOD 3: eighth resolution
- Automatic camera or target-driven LOD focus.
- Distance culling and LOD profile presets for viewport performance.
- Terrain shadow casting policy so Balanced/Performance can disable terrain self-shadowing while keeping lighting.
- Bake presets for visual-only output, game-ready all-terrain collision, and high-accuracy collision.
- Progressive collision generation with coverage and quality controls.
- Preview lighting helper for quick terrain inspection in the editor.

## Requirements

- Godot 4.6 or newer.
- Jolt Physics is enabled in `project.godot`.

## Quick Start

1. Copy `addons/gdt_terrain/` into a Godot 4.6 project.
2. Enable `GDT Terrain Generator` in Project Settings > Plugins.
3. Add a `GdtTerrain3D` node, or instance `res://addons/gdt_terrain/scenes/gdt_terrain_3d.tscn`.
4. Tune terrain settings in the Inspector.
5. Pick a `Bake Preset`.
6. Use `Generate Preview` while shaping the terrain.
7. Use `Generate Final` when you want to lock and save the generated terrain.

This repository also includes `game_ready_demo.tscn`, which is the default run scene and a clean playable proof scene for collision baking.

The default terrain settings are chosen for a good first result:

| Setting | Default |
| --- | ---: |
| Terrain Size | 64 |
| Chunk Resolution | 256 |
| Chunks Per Side | 1 |
| Height Scale | 5 |
| Seed | 1345 |
| Terrain Scale | 1 |
| Noise Frequency | 0.032 |
| Octaves | 7 |
| Lacunarity | 2.1 |
| Gain | 0.42 |

For a 4096 x 4096 total terrain grid, use:

- `chunk_resolution = 256`
- `chunks_per_side = 16`

This is intentionally expensive. Use preview mode while tuning, then generate final terrain deliberately.

## Workflow

### Preview

`Generate Preview` builds a lower-detail terrain for fast iteration. With `Auto Performance Settings` enabled, the preview resolution is chosen automatically. Preview chunks are editor-transient and are not saved into the edited scene, which keeps scene files small. Starting a final bake clears the active preview first.

### Bake Presets

`Bake Preset` controls the normal final-output intent before the lower-level collision controls:

- `Visual Only`: baked meshes, LODs, and materials without collision.
- `Game Ready`: baked visuals plus collision on every chunk at half resolution. This is the default playable terrain bake.
- `High Accuracy`: baked visuals plus collision on every chunk at full resolution.
- `Custom`: appears when advanced collision controls no longer match one of the presets.

`Bake State` reports whether the current workflow is preview-only, visual-only, game-ready, or testing-only.

### Final

`Generate Final` builds the full configured terrain progressively. When it finishes:

- `final_terrain_locked` becomes `true`.
- Generated chunk nodes are saved with the scene.
- Mesh, material, shader, and generated noise resources are saved to `generated_terrain/`.
- Collision shape resources are saved when the active bake preset or collision settings include collision.
- Terrain will not regenerate from preview settings until `Clear Generated Terrain` is used.

### Terrain Source

`Source Mode` chooses the height source:

- `Noise` uses the procedural noise controls.
- `Heightmap` imports a PNG heightmap and resamples it to the active terrain grid.

Heightmap import replaces procedural noise shape data. `Height Scale` still controls the vertical amplitude, and imported values are mapped into the terrain height range. Flip and invert controls help match heightmaps from third-party terrain tools.

PNG remains available for simple workflows, but EXR or R16/RAW is recommended for terrain exchange when height precision matters. R16/RAW import requires explicit width, height, and min/max height because raw files do not store metadata.

### Terrain Pattern

`Terrain Scale` zooms the procedural noise pattern without changing the physical terrain size. Larger values make broader continents and wider mountain systems; smaller values reveal tighter local detail. `Noise Frequency` remains available as the lower-level noise density control.

### Rendering Performance

`Terrain Performance Preset` is the high-level control for rendering cost:

- `Quality`: keeps visual detail farther out and leaves terrain shadow casting available.
- `Balanced`: the default target for high close-up quality with much cheaper all-visible terrain views.
- `Performance`: pushes distant terrain to lower LODs sooner and caps costly shader features more aggressively.

`High View LOD Bias` adds extra visual LOD when the camera or LOD target rises high enough to see most of the terrain. This only changes rendered meshes; baked collision remains unchanged. The LOD counters show how many visible chunks are using LOD 0/1/2/3, and `Estimated Visible Triangles` helps confirm that all-visible views are actually dropping primitive count.

In texture layer mode, far pixels avoid expensive normal, roughness, height blend, and texture bombing work. When `Far Material Cache Enabled` is on, final bake also saves a low-resolution whole-terrain color cache to `generated_terrain/` and far terrain can sample that cache instead of recomputing all six PBR layers. This is a static Godot-friendly cache, not Unreal-style virtual texturing.

### Presets

`Save Preset` writes generator, terrain source, environment, material, viewport, and collision settings to a native Godot `.tres` resource. Presets do not include generated chunks or mesh resources.

`Load Preset` applies the saved settings. If final terrain is locked, only non-geometry visual/environment settings are applied; clear the terrain before loading shape/source changes.

Preset actions live beside `Preset Path` in the Inspector so file workflow stays separate from terrain generation.

### Heightmap I/O

`Export Heightmap` writes the current active heightfield to `Export Heightmap Path` as a grayscale PNG.

The main terrain actions are grouped under `Terrain Actions`: generate a preview, generate a locked final terrain, cancel a running build, or clear generated terrain. Less common maintenance commands use `Selected Utility` plus `Run Selected Utility` under the advanced controls. `Reveal All Chunks` disables viewport culling when a full bake is complete but only nearby chunks are visible.

### Editing Environment After Final

Newly generated V5 terrain stores material masks in vertex colors and uses the terrain shader for either basic colors or layered PBR textures. Snow, rock, and visual material changes update shader parameters without rebuilding chunks or rewriting mesh resources.

Older V4 terrain chunks remain visible through the legacy vertex-color material path. Regenerate terrain once to get the full V5 mask-based material workflow.

### Visual Material

`Procedural Material Enabled` is on by default. `Material Mode` chooses how the terrain is shaded:

- `Basic Colors`: the dry procedural color shader, useful as a lightweight fallback.
- `Texture Layers`: the default PBR texture workflow using user-assigned folders. This development project includes optional Poly Haven CC0 texture examples under `res://material/`.

The default texture layer folders are:

- `sand_03`: lowland and beach-like terrain.
- `forest_ground`: main ground.
- `aerial_grass_rock`: upper broken grass and exposed ground.
- `rocky_terrain`: rocky slope transitions.
- `rock_face`: steep cliff faces.
- `snow`: snow layer.

Each layer uses diffuse/albedo, Normal GL, roughness, and optional displacement/height textures when present. Terrain generation itself is unchanged; displacement textures are only used for material blend breakup in this pass.

Each texture source also has an `Enabled` checkbox. The enabled sources collapse into the terrain layer stack in order, so the first enabled source becomes the base layer. For example, disabling `Lowland` makes `Ground` use the lowland/base height role, `Upper` use the ground role, `Rocky` use the upper role, and so on.

Useful controls:

- `Texture Tile Scale` for world-space texture density.
- `Macro Texture Tiling Enabled` plus close, medium, and far tile scales/radii for camera-aware texture density. Close ranges use smaller, sharper texture tiles; far ranges blend into larger broad tiling.
- `Texture Bombing Enabled`, `Texture Bombing Strength`, `Texture Bombing Cell Scale`, and `Texture Bombing Samples` for reducing visible texture repetition.
- `Texture Normal Strength`, `Roughness Multiplier`, and `Height Blend Strength` for PBR tuning.
- `Macro Variation Strength` and `Macro Variation Scale` for broad natural color breakup.
- `Detail Noise Strength` and `Detail Noise Scale` for fine surface variation.
- `Rock Detail Strength` and `Snow Detail Strength` for material-specific contrast.
- `Snow Enabled` to turn snow blending off without changing the stored snow color or height.
- `Material Brightness` and `Material Contrast` for final look tuning.

`Texture Layers` is best inspected with Mesh Preview or Final generation. Shader Preview remains a lightweight shape/material-mask preview path for fast slider tuning.

Use `Setup Preview Lighting` to add a simple editor light and environment for inspecting the terrain material.

## Viewport LOD

Final terrain stores four mesh LODs per chunk. The viewport swaps between them based on distance from the LOD focus point.

LOD focus priority:

1. `LOD Target Path`, if assigned to a `Node3D`.
2. Active `Camera3D`, if available.
3. Manual `Culling Center`, when automatic focus cannot find a target or camera.

LOD controls:

- `Automatic LOD Focus`: follows the target or camera automatically.
- `LOD Target Path`: optional Node3D focus target.
- `LOD Focus Update Distance`: minimum movement before LOD refreshes.
- `LOD Profile`: controls how aggressively lower LODs are used.
- `Viewport Quality`: caps the best visual LOD.
- `Visible Radius`: hides chunks outside the inspection area.
- `Visible Chunks`: status count showing how many generated chunks are currently visible after viewport culling.

If `Generated Chunks` equals `Total Chunks` but the viewport only shows part of the terrain, viewport culling is hiding the rest. Disable `Viewport Culling Enabled`, increase `Visible Radius`, move `Culling Center`, or run the `Reveal All Chunks` utility.

Profile behavior:

- `Quality`: keeps high detail farther away.
- `Balanced`: default middle ground.
- `Performance`: switches to lower detail sooner.

## Collision

Collision is separate from visual LOD. For game-ready output, use the `Game Ready` bake preset, which sets `Collision Mode` to `Final Only`, `Collision Coverage` to `All Chunks`, and `Collision Quality` to `Half`.

`Dynamic Near Focus` collision is available for editor testing and lightweight prototypes. It follows the same target/camera/culling focus used by viewport LOD and only keeps collision near that focus.

Collision controls:

- `Collision Mode`
  - `Disabled`
  - `Final Only`
  - `All Builds`
- `Collision Coverage`
  - `Near Center`
  - `Visible Chunks`
  - `All Chunks`
- `Collision Quality`
  - `Full`
  - `Half`
  - `Quarter`
  - `Eighth`
- `Collision Radius`
- `Collision Chunks Per Frame`
- `Collision Visuals Visible`

Use `Generate Collision` after generating final terrain if you want to rebuild physics without rebuilding the terrain. `Near Center` and `Visible Chunks` are useful editor/testing coverage modes, but they are not safe final playable-terrain defaults because a player can leave the generated collision area.

## Game-Ready Demo

`game_ready_demo.tscn` is a clean test scene with a `GdtTerrain3D` terrain node, a basic `CharacterBody3D`, camera, and light. It does not commit generated terrain binaries. To test a playable bake:

1. Open `game_ready_demo.tscn`.
2. Select `Terrain`.
3. Keep `Bake Preset` set to `Game Ready`.
4. Click `Generate Final`.
5. Press Play and walk the character across chunk boundaries.

## Generated Files

`generated_terrain/` contains binary `.res` files for generated chunk meshes, LODs, collision shapes, procedural materials, shaders, and generated noise textures. These files can be large.

`material/` contains optional Poly Haven CC0 source PBR texture sets used by the demo/default terrain material layers. These are normal project assets, not generated output.

For open-source distribution:

- Commit `generated_terrain/` only if you want to ship a ready-made sample terrain.
- Use Git LFS if the generated resources become large.
- Or clear generated terrain before committing and let users generate their own terrain locally.

## Addon Publishing Checklist

- Keep `addons/gdt_terrain/`, `LICENSE`, README files, demo scenes, and optional credited example textures.
- Exclude `.godot/`, `.import/`, `generated_terrain/`, logs, temporary files, and local screenshots unless intentionally used for AssetLib marketing.
- Confirm `GDT Terrain Generator` enables cleanly in Project Settings > Plugins.
- Confirm `GdtTerrain3D` appears in Add Node and can generate preview/final terrain in a fresh Godot 4.6 project.
- Include `THIRD_PARTY_NOTICES.md` when shipping the optional Poly Haven CC0 texture examples.

## Project Structure

| Path | Purpose |
| --- | --- |
| `addons/gdt_terrain/` | Installable Godot addon for `GDT Terrain Generator`. |
| `addons/gdt_terrain/src/gdt_terrain_3d.gd` | Main editor-facing terrain generator script and Inspector workflow. |
| `addons/gdt_terrain/scenes/gdt_terrain_3d.tscn` | Reusable terrain node scene. |
| `game_ready_demo.tscn` | Playable proof scene for game-ready baked terrain collision. |
| `demo_player_controller.gd` | Minimal WASD/mouse `CharacterBody3D` controller used by the demo scene. |
| `addons/gdt_terrain/src/terrain_heightfield.gd` | Shared noise/imported height data used by meshes, collision, and export. |
| `addons/gdt_terrain/src/terrain_mesh_builder.gd` | Chunk mesh, LOD mesh, skirt, normal, and terrain mask generation. |
| `addons/gdt_terrain/src/terrain_material_manager.gd` | Procedural terrain shaders, materials, and generated noise resources. |
| `addons/gdt_terrain/src/terrain_preset.gd` | Native Godot Resource used by terrain preset save/load. |
| `material/` | Optional Poly Haven CC0 source PBR texture sets for terrain texture layers. |
| `generated_terrain/` | Generated binary terrain mesh resources. |
| `project.godot` | Godot project configuration. |

## License

MIT. See `LICENSE`.
