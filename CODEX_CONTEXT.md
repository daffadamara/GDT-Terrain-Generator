# Codex Project Context

This project is a Godot 4.6 procedural terrain generator intended to become an open-source editor tool. The main scene is `node_3d.tscn`, driven by the `@tool` script `node_3d.gd`.

## Current Goal

Build an editor-friendly static terrain generator that can produce large terrain grids, keep the Godot editor responsive, and provide good-looking procedural terrain, water, and game-ready baked collision without imported texture assets.

The tool currently focuses on:

- Chunked terrain generation up to 4096 x 4096 total samples.
- Preview and final generation workflows.
- External `.res` resources for generated meshes/materials to avoid bloating text scenes.
- Distance-based viewport LOD and culling for editor FPS.
- Bake presets for visual-only, game-ready, and high-accuracy final output.
- Collision generation with coverage/quality controls, where game-ready output means all chunks receive collision.
- Procedural terrain material masks and shader-based visual tuning.
- Standalone animated `ProceduralWater3D` that integrates with terrain but can be used independently.
- Heightmap import/export and terrain preset resources.

## Important Files

- `node_3d.gd`: Main terrain generator, inspector workflow, generation orchestration, LOD/culling, collision, presets, heightmap I/O, and water integration.
- `terrain_mesh_builder.gd`: Builds chunk meshes, LOD meshes, terrain masks, normals, collision meshes, and LOD edge stitching.
- `terrain_material_manager.gd`: Owns terrain procedural/legacy materials and terrain shader resources.
- `terrain_heightfield.gd`: Shared heightfield source for noise or heightmap input.
- `terrain_preset.gd`: Native Godot `.tres` preset data resource.
- `procedural_water_3d.gd`: Standalone animated water node with its own mesh, shader, material, noise, quality presets, and resource saving.
- `game_ready_demo.tscn`: Playable validation scene with a terrain generator, `CharacterBody3D`, camera, and light.
- `demo_player_controller.gd`: Minimal demo player controller.
- `README.md`: Public-facing documentation.
- `CHANGELOG.md`: Release/history notes.

## Generated Files Policy

Generated terrain data is intentionally not part of the clean source push unless explicitly requested.

Usually do not commit:

- `generated_terrain/`
- `terrain_heightmap.png`
- screenshot files and `.import` files
- generated/editor-heavy changes to `node_3d.tscn` that embed generated chunks

Commit source scripts, docs, preset/resource scripts, and intentional scene setup changes only.

## Current Terrain Behavior

`node_3d.gd` creates a `TerrainChunks` parent and adds chunk `MeshInstance3D` children progressively. Final builds can save chunk LOD meshes as external resources. The final terrain lock prevents accidental preview regeneration after a final build.

Terrain can come from:

- `Noise`: FastNoiseLite sampled into a shared heightfield.
- `Heightmap`: imported PNG resampled into the active heightfield.

Mesh generation reads from the active heightfield, so visual mesh, collision, LOD, material masks, and heightmap export all share the same data.

`Terrain Scale` is an artist-facing noise zoom multiplier. The default value `1.0` preserves existing output. Larger values divide world coordinates before sampling FastNoiseLite, creating broader continent-scale features without forcing users to type very small `Noise Frequency` values.

`Snow Enabled` is an artist-facing material/mesh mask toggle. When disabled, new mesh color masks store no snow and the procedural terrain shader ignores both height-derived and baked snow masks. Keep `Snow Height`, `Snow Color`, and `Snow Detail Strength` available so users can re-enable snow without losing tuning.

## Bake Workflow Notes

The public terrain node identity target is `GdtTerrain3D`, currently provided by `node_3d.gd` through `class_name GdtTerrain3D`.

Final output should be explained through three states:

- Preview: fast visual iteration, not playable output.
- Visual Bake: saved visual meshes/materials/water with collision disabled.
- Game Ready Bake: saved visuals plus all-terrain collision.

`Bake Preset` is the high-level workflow control. The default `Game Ready` preset sets collision to final-only, all chunks, half quality. `Near Center` and `Visible Chunks` collision coverage are testing/editor modes, not final playable terrain defaults.

`Generated Chunks` and `Total Chunks` report build completion. `Visible Chunks` reports how many generated chunks are currently visible after viewport culling. If a complete bake looks partial, check `Viewport Culling Enabled`, `Visible Radius`, `Culling Center`, or use the `Reveal All Chunks` utility.

## LOD / Seam Notes

Viewport LOD swaps chunk meshes by distance from the culling/LOD focus. A previous seam fix used vertical edge curtains, but those showed as dark triangular split artifacts on steep terrain. The current fix uses surface stitching:

- Lower LOD meshes skip their coarse outer ring.
- The outer ring is rebuilt with full-detail border samples.
- That detailed border is stitched into the coarser interior with regular surface triangles.
- `TERRAIN_LOD_EDGE_VERSION` in `node_3d.gd` should be incremented when changing LOD seam geometry so old `.res` LOD meshes are rebuilt automatically.

## Water Notes

Water is now owned by `ProceduralWater3D`, not `TerrainMaterialManager`.

`node_3d.gd` auto-creates or reuses a `ProceduralWater3D` child named `WaterPlane` when `water_enabled` is true. Once the water node exists, it owns its visual tuning. The terrain generator should only sync integration values:

- enabled state
- water size
- water level
- generated resource directory

Do not overwrite the water node's color, alpha, waves, foam, tiling, subdivision, or other visual settings during reload.

Water motion is preset-first. `Coastal` is the default and should remain restrained: broad slow swell, clean low-strength ripples, low screen distortion, and mostly shoreline/depth-driven foam. `Calm Lake`, `Windy`, and `Flat Visual` are alternate motion presets. Advanced controls should favor `Swell Scale`, `Ripple Scale`, `Ripple Strength`, and `Surface Distortion`; older `Wave Scale` and `Normal Tiling` are compatibility multipliers for saved scenes.

The water shader intentionally uses backface culling (`cull_back`) to avoid transparent backface tearing when animated waves are tall. Water is visual-only for now; no buoyancy, flow maps, or gameplay water physics are part of the pre-plugin milestone.

## Validation Commands

Use these checks after changes:

```bash
godot --headless --path . --check-only --script res://node_3d.gd
godot --headless --path . --check-only --script res://terrain_mesh_builder.gd
godot --headless --path . --check-only --script res://procedural_water_3d.gd
godot --headless --path . --quit-after 5
git diff --check
```

Scene boot may print existing warnings about generated-resource UIDs or loading `terrain_heightmap.png` as an image. Those warnings are known and not necessarily related to code changes.

## Development Style

Keep this tool editor-first and practical:

- Prefer progressive work over freezing the editor.
- Keep expensive features opt-in or manual.
- Avoid committing generated terrain resources unless the user explicitly asks.
- Preserve standalone water usability.
- Keep inspector controls understandable and document hover descriptions for new exported properties.
- For future major work, consider runtime streaming, foliage/rocks, biome masks, better heightmap import resources, or water presets.
