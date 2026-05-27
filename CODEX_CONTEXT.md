# Codex Project Context

This project is a Godot 4.6 procedural terrain generator packaged as the `GDT Terrain Generator` addon. The public terrain node is `GdtTerrain3D`, backed by `addons/gdt_terrain/src/gdt_terrain_3d.gd`.

## Current Goal

Build an editor-friendly static terrain generator that can produce large terrain grids, keep the Godot editor responsive, and provide good-looking terrain materials and game-ready baked collision.

The tool currently focuses on:

- Chunked terrain generation up to 4096 x 4096 total samples.
- Preview and final generation workflows.
- External `.res` resources for generated meshes/materials to avoid bloating text scenes.
- Distance-based viewport LOD and culling for editor FPS.
- Terrain performance presets, high-view visual LOD bias, and LOD/triangle counters for all-visible terrain profiling.
- Bake presets for visual-only, game-ready, and high-accuracy final output.
- Collision generation with coverage/quality controls, where game-ready output means all chunks receive collision.
- Procedural terrain material masks, basic color fallback shading, and PBR texture layer shading.
- Stochastic texture bombing controls to reduce visible texture repetition on large terrain.
- Heightmap import/export and terrain preset resources.

## Important Files

- `addons/gdt_terrain/plugin.cfg`: Godot editor plugin manifest.
- `addons/gdt_terrain/plugin.gd`: Registers `GdtTerrain3D` in Add Node.
- `addons/gdt_terrain/src/gdt_terrain_3d.gd`: Main terrain generator, inspector workflow, generation orchestration, LOD/culling, collision, presets, and heightmap I/O.
- `addons/gdt_terrain/src/terrain_mesh_builder.gd`: Builds chunk meshes, LOD meshes, terrain masks, normals, collision meshes, and LOD edge stitching.
- `addons/gdt_terrain/src/terrain_material_manager.gd`: Owns terrain procedural/legacy materials and terrain shader resources.
- `addons/gdt_terrain/src/terrain_heightfield.gd`: Shared heightfield source for noise or heightmap input.
- `addons/gdt_terrain/src/terrain_preset.gd`: Native Godot `.tres` preset data resource.
- `material/`: Optional Poly Haven CC0 source PBR texture sets used by the default terrain texture layers in this development project.
- `game_ready_demo.tscn`: Playable validation scene with a terrain generator, `CharacterBody3D`, camera, and light.
- `demo_player_controller.gd`: Minimal demo player controller.
- `README.md`: Public-facing documentation.
- `CHANGELOG.md`: Release/history notes.

## Generated Files Policy

Generated terrain data is intentionally not part of the clean source push unless explicitly requested.

The current `game_ready_demo.tscn` state may intentionally include the user's saved baked demo terrain, including `TerrainChunk_*` children and references to local `generated_terrain/*.res` resources. Do not automatically restore this scene as editor serialization noise just because generated chunks are present. If preparing a distributable commit or release, make an explicit choice first:

- Keep the baked playable demo and include the required `generated_terrain/` resources, likely with Git LFS if size becomes a concern.
- Or clear the generated demo terrain and keep `game_ready_demo.tscn` as a clean generate-on-demand proof scene.

Usually do not commit:

- `generated_terrain/`
- `terrain_heightmap.png`
- screenshot files and `.import` files
- generated/editor-heavy changes that embed generated chunks

Commit addon source scripts, docs, preset/resource scripts, optional credited source texture assets under `material/`, and intentional scene setup changes only.

## Current Terrain Behavior

`GdtTerrain3D` creates a `TerrainChunks` parent and adds chunk `MeshInstance3D` children progressively. Final builds can save chunk LOD meshes as external resources. The final terrain lock prevents accidental preview regeneration after a final build.

Terrain can come from:

- `Noise`: FastNoiseLite sampled into a shared heightfield.
- `Heightmap`: imported PNG resampled into the active heightfield.

Mesh generation reads from the active heightfield, so visual mesh, collision, LOD, material masks, and heightmap export all share the same data.

`Terrain Scale` is an artist-facing noise zoom multiplier. The default value `1.0` preserves existing output. Larger values divide world coordinates before sampling FastNoiseLite, creating broader continent-scale features without forcing users to type very small `Noise Frequency` values.

`Snow Enabled` is an artist-facing material/mesh mask toggle. When disabled, new mesh color masks store no snow and the procedural terrain shader ignores both height-derived and baked snow masks. Keep `Snow Height`, `Snow Color`, and `Snow Detail Strength` available so users can re-enable snow without losing tuning.

`Material Mode` selects the visual shader path:

- `Basic Colors`: dry procedural color blending with generated noise variation.
- `Texture Layers`: PBR texture blending using user-assigned texture folders. This repo includes optional Poly Haven CC0 defaults under `res://material/`.

The default texture folders are `sand_03`, `forest_ground`, `aerial_grass_rock`, `rocky_terrain`, `rock_face`, and `snow`. Texture layers use diffuse/albedo, Normal GL, roughness, and optional displacement/height textures. Texture bombing is implemented in the terrain shader with stable world-space randomization; it does not change terrain geometry.

Each texture source has an enabled flag. Disabled sources should be removed from the ordered material stack rather than merely hidden: the first enabled source fills the lowland/base role, the second fills the ground role, the third fills the upper role, and the mapping continues upward. If every source is disabled, ground acts as the safety fallback.

Macro texture tiling is shader-side and distance-based, using a 3D `texture_focus_position` uniform supplied by `GdtTerrain3D`. The terrain node updates only that uniform while the editor/game camera moves, which avoids shader recompiles and keeps the transition responsive. Use full 3D distance for macro tiling, not only X/Z distance, so a high editor camera does not force close tiling onto the terrain directly below it. Do not use non-portable camera built-ins such as `CAMERA_POSITION_WORLD` or `INV_VIEW_MATRIX` in this shader path; they failed in this Godot 4.6 spatial shader context. Close tile scale should be higher for smaller nearby detail, while far tile scale should be lower for broad distant tiling. Do not blend the tile scale number itself; that creates radial UV stretching. Blend separately sampled close/medium/far texture results instead. Steep cliff samples intentionally keep a stable triplanar tile scale instead of inheriting the camera-distance macro scale, because camera-driven planar scale changes can smear cliff textures.

Texture bombing must always use weights that sum to non-zero. Earlier randomized radial weights and a two-sample diagonal light path could leave uncovered gaps and render black squares. Light mode should use two-cell coverage along one axis with weights that sum to 1; Quality mode should use deterministic bilinear four-cell coverage.

`Terrain Performance Preset` controls the practical rendering budget. Balanced is the default target: it keeps close material quality, applies more aggressive distant mesh LOD, disables terrain shadow casting through the performance policy, caps medium/far texture bombing, and can use a baked far color cache after final resource saving. The far cache is static and saved as a normal Godot resource; it is not Unreal-style virtual texturing with page tables, runtime feedback, or streaming. Runtime rendering should remain shader/GPU-driven with only the material focus uniform updated per frame.

The far color cache must stay conservative. It is only for genuinely distant terrain, and should require both far macro weight and enough horizontal distance from the focus point. Do not let it replace terrain merely because a camera is vertically high above a nearby point; that makes close inspection views look like low-resolution baked color.

`High View LOD Bias` is meant for the user-reported jump/fly/editor all-visible case. It adds visual LOD when the focus camera/player gets high enough to see most chunks. It must never change collision, only the displayed chunk mesh.

Shader Preview remains the fast shape/material-mask preview. Use Mesh Preview or Final generation when validating actual PBR texture layers.

## Bake Workflow Notes

The public terrain node identity is `GdtTerrain3D`, provided by the addon script and registered by the `GDT Terrain Generator` editor plugin.

Final output should be explained through three states:

- Preview: fast visual iteration, not playable output.
- Visual Bake: saved visual meshes/materials with collision disabled.
- Game Ready Bake: saved visuals plus all-terrain collision.

`Bake Preset` is the high-level workflow control. The default `Game Ready` preset sets collision to final-only, all chunks, half quality. `Near Center` and `Visible Chunks` collision coverage are testing/editor modes, not final playable terrain defaults.

`Generated Chunks` and `Total Chunks` report build completion. `Visible Chunks` reports how many generated chunks are currently visible after viewport culling. If a complete bake looks partial, check `Viewport Culling Enabled`, `Visible Radius`, `Culling Center`, or use the `Reveal All Chunks` utility.

## LOD / Seam Notes

Viewport LOD swaps chunk meshes by distance from the culling/LOD focus. A previous seam fix used vertical edge curtains, but those showed as dark triangular split artifacts on steep terrain. The current fix uses surface stitching:

- Lower LOD meshes skip their coarse outer ring and rebuild a full-detail outer perimeter.
- Corner patches and edge strips are stitched into the coarser interior using fan triangles that share the coarse interior edge rather than duplicate/interpolated vertices.
- Reduced LOD meshes should have only the real outer perimeter as open boundary edges; internal open edges/T-junctions can show as thin runtime gaps even when chunk-to-chunk heights match.
- Saved LOD resources should be considered valid only when their `terrain_lod_edge_version` is current and topology checks report zero internal open edges.
- `TERRAIN_LOD_EDGE_VERSION` in `gdt_terrain_3d.gd` should be incremented when changing LOD seam geometry so old `.res` LOD meshes are rebuilt automatically.

## Validation Commands

Use these checks after changes:

```bash
godot --headless --path . --check-only --script res://addons/gdt_terrain/src/gdt_terrain_3d.gd
godot --headless --path . --check-only --script res://addons/gdt_terrain/src/terrain_mesh_builder.gd
godot --headless --path . --quit-after 5
git diff --check
```

Scene boot may print existing warnings about generated-resource UIDs or loading `terrain_heightmap.png` as an image. Those warnings are known and not necessarily related to code changes.

## Development Style

Keep this tool editor-first and practical:

- Prefer progressive work over freezing the editor.
- Keep expensive features opt-in or manual.
- Avoid committing generated terrain resources unless the user explicitly asks.
- Keep inspector controls understandable and document hover descriptions for new exported properties.
- For future major work, consider runtime streaming, foliage/rocks, biome masks, better heightmap import resources, or a replacement environment renderer.
