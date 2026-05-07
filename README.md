# GDT Terrain

Procedural terrain generator for Godot 4.6, built as an editor-friendly `@tool` scene. It generates chunked terrain from noise, supports high-resolution final builds, and includes water, vertex-color biomes, distance LOD, culling, and lightweight collision controls.

## Features

- Chunked static terrain generation with configurable terrain size, per-chunk resolution, and chunk count.
- Fast preview mode and progressive final generation to keep the editor responsive.
- Noise controls for seed, frequency, octaves, lacunarity, gain, and height scale.
- Vertex-color terrain bands for seabed, shore, grass, lowland, rock, and snow.
- Flat visual water plane with editable level, color, and transparency.
- External binary `.res` mesh saving so large final terrain does not bloat the text scene.
- Saved mesh LODs for final terrain:
  - LOD 0: full resolution
  - LOD 1: half resolution
  - LOD 2: quarter resolution
  - LOD 3: eighth resolution
- Automatic camera or target-driven LOD focus.
- Distance culling and LOD profile presets for viewport performance.
- Progressive collision generation with coverage and quality controls.

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

`Generate Preview` builds a lower-detail terrain for fast iteration. With `Auto Performance Settings` enabled, the preview resolution is chosen automatically.

### Final

`Generate Final` builds the full configured terrain progressively. When it finishes:

- `final_terrain_locked` becomes `true`.
- Generated chunk nodes are saved with the scene.
- Mesh resources are saved to `generated_terrain/`.
- Terrain will not regenerate from preview settings until `Clear Generated Terrain` is used.

### Editing Environment After Final

Water, shoreline, seabed, snow, rock, and color changes update existing terrain colors without rebuilding geometry. Recolored final meshes are written back to their external `.res` files.

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

`generated_terrain/` contains binary `.res` files for generated chunk meshes and LODs. These files can be large.

For open-source distribution:

- Commit `generated_terrain/` only if you want to ship a ready-made sample terrain.
- Use Git LFS if the generated resources become large.
- Or clear generated terrain before committing and let users generate their own terrain locally.

## Project Structure

| Path | Purpose |
| --- | --- |
| `node_3d.gd` | Main procedural terrain generator script. |
| `node_3d.tscn` | Main Godot scene using the generator. |
| `generated_terrain/` | Generated binary terrain mesh resources. |
| `project.godot` | Godot project configuration. |

## License

MIT. See `LICENSE`.
