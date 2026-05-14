# GDT Terrain

Procedural terrain generator for Godot 4.6, built as an editor-friendly `@tool` scene. It generates chunked terrain from noise, supports high-resolution final builds, and includes procedural terrain materials, water, distance LOD, culling, and lightweight collision controls.

## Features

- Chunked static terrain generation with configurable terrain size, per-chunk resolution, and chunk count.
- Fast preview mode and progressive final generation to keep the editor responsive.
- Noise controls for seed, frequency, octaves, lacunarity, gain, and height scale.
- Shared heightfield pipeline with noise or imported 16-bit PNG heightmaps.
- Native Godot `.tres` terrain presets for saving and loading styles/settings.
- Heightmap export to grayscale PNG.
- Procedural visual material using generated terrain masks and self-contained noise textures.
- Editable seabed, shore, grass, lowland, rock, and snow colors without rebuilding V5 terrain.
- Standalone `ProceduralWater3D` node with animated waves, depth tint, foam, and optional refraction.
- Legacy vertex-color fallback for older generated V4 chunks.
- External binary `.res` mesh saving so large final terrain does not bloat the text scene.
- Saved mesh LODs for final terrain:
  - LOD 0: full resolution
  - LOD 1: half resolution
  - LOD 2: quarter resolution
  - LOD 3: eighth resolution
- Automatic camera or target-driven LOD focus.
- Distance culling and LOD profile presets for viewport performance.
- Progressive collision generation with coverage and quality controls.
- Preview lighting helper for quick terrain inspection in the editor.

## Requirements

- Godot 4.6 or newer.
- Jolt Physics is enabled in `project.godot`.

## Quick Start

1. Open the project in Godot.
2. Open `node_3d.tscn`.
3. Select the root `Node3D`.
4. Tune terrain settings in the Inspector.
5. Use `Generate Preview` while shaping the terrain.
6. Use `Generate Final` when you want to lock and save the generated terrain.

The default terrain settings are chosen for a good first result:

| Setting | Default |
| --- | ---: |
| Terrain Size | 64 |
| Chunk Resolution | 256 |
| Chunks Per Side | 1 |
| Height Scale | 5 |
| Seed | 1345 |
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

`Generate Preview` builds a lower-detail terrain for fast iteration. With `Auto Performance Settings` enabled, the preview resolution is chosen automatically. Preview chunks are editor-transient and are not saved into `node_3d.tscn`, which keeps the scene file small.

### Final

`Generate Final` builds the full configured terrain progressively. When it finishes:

- `final_terrain_locked` becomes `true`.
- Generated chunk nodes are saved with the scene.
- Mesh, material, shader, and generated noise resources are saved to `generated_terrain/`.
- Terrain will not regenerate from preview settings until `Clear Generated Terrain` is used.

### Terrain Source

`Source Mode` chooses the height source:

- `Noise` uses the procedural noise controls.
- `Heightmap` imports a PNG heightmap and resamples it to the active terrain grid.

Heightmap import replaces procedural noise shape data. `Height Scale` still controls the vertical amplitude, and imported values are mapped into the terrain height range. Flip and invert controls help match heightmaps from third-party terrain tools.

### Presets

`Save Preset` writes generator, terrain source, environment, material, viewport, and collision settings to a native Godot `.tres` resource. Presets do not include generated chunks or mesh resources.

`Load Preset` applies the saved settings. If final terrain is locked, only non-geometry visual/environment settings are applied; clear the terrain before loading shape/source changes.

Preset actions live beside `Preset Path` in the Inspector so file workflow stays separate from terrain generation.

### Heightmap I/O

`Export Heightmap` writes the current active heightfield to `Export Heightmap Path` as a grayscale PNG.

The main terrain actions are grouped under `Terrain Actions`: generate a preview, generate a locked final terrain, cancel a running build, or clear generated terrain. Less common maintenance commands use `Selected Utility` plus `Run Selected Utility` under the advanced controls.

### Editing Environment After Final

Newly generated V5 terrain stores material masks in vertex colors and uses a procedural shader for final color. Water level, shoreline, seabed, snow, rock, and visual material changes update shader parameters without rebuilding chunks or rewriting mesh resources.

Older V4 terrain chunks remain visible through the legacy vertex-color material path. Regenerate terrain once to get the full V5 procedural material workflow.

### Animated Water

Water is provided by a reusable `ProceduralWater3D` node. The terrain generator can auto-create a child named `WaterPlane`, or configure a node assigned through `Water Node Path`.

Top-level water controls stay in the terrain `Environment` section for quick integration: `Water Enabled`, `Water Level`, `Water Color`, `Water Alpha`, `Auto Create Water`, and `Water Node Path`.

Select the `WaterPlane` node directly for advanced water controls such as quality preset, wave strength, foam strength, refraction strength, shallow/mid/deep colors, wave directions, normal and foam tiling, depth fade, shoreline alpha fade, shoreline foam width, and mesh subdivisions. The default quality is `High Fidelity`; lower it to `Balanced` or `Lightweight` if the viewport needs more FPS.

Once a `ProceduralWater3D` node exists, it owns its visual water tuning. The terrain generator still syncs integration values such as enabled state, size, level, and resource directory, but it does not overwrite the water node's color, alpha, wave, foam, or subdivision settings on reload.

### Visual Material

`Procedural Material Enabled` is on by default. It blends lowland, grass, shore, seabed, rock, and snow using baked height/slope masks plus generated noise textures.

Useful controls:

- `Macro Variation Strength` and `Macro Variation Scale` for broad natural color breakup.
- `Detail Noise Strength` and `Detail Noise Scale` for fine surface variation.
- `Rock Detail Strength` and `Snow Detail Strength` for material-specific contrast.
- `Shore Wetness Strength` for darker damp shorelines near the water level.
- `Material Brightness` and `Material Contrast` for final look tuning.

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

Profile behavior:

- `Quality`: keeps high detail farther away.
- `Balanced`: default middle ground.
- `Performance`: switches to lower detail sooner.

## Collision

Collision is separate from visual LOD and is disabled by default for editor performance.

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

Use `Generate Collision` after generating final terrain if you want physics without rebuilding the terrain. The default collision setup uses quarter-resolution collision near the focus point to avoid generating expensive physics for every chunk.

## Generated Files

`generated_terrain/` contains binary `.res` files for generated chunk meshes, LODs, collision shapes, procedural materials, shaders, and generated noise textures. These files can be large.

For open-source distribution:

- Commit `generated_terrain/` only if you want to ship a ready-made sample terrain.
- Use Git LFS if the generated resources become large.
- Or clear generated terrain before committing and let users generate their own terrain locally.

## Project Structure

| Path | Purpose |
| --- | --- |
| `node_3d.gd` | Main editor-facing terrain generator script and Inspector workflow. |
| `terrain_heightfield.gd` | Shared noise/imported height data used by meshes, collision, and export. |
| `terrain_mesh_builder.gd` | Chunk mesh, LOD mesh, skirt, normal, and terrain mask generation. |
| `terrain_material_manager.gd` | Procedural terrain shaders, materials, and generated noise resources. |
| `procedural_water_3d.gd` | Reusable animated water node with its own mesh, shader, material, and saved resources. |
| `terrain_preset.gd` | Native Godot Resource used by terrain preset save/load. |
| `node_3d.tscn` | Main Godot scene using the generator. |
| `generated_terrain/` | Generated binary terrain mesh resources. |
| `project.godot` | Godot project configuration. |

## License

MIT. See `LICENSE`.
