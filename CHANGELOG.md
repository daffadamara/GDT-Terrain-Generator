# Changelog

All notable changes to this project are documented here.

## Unreleased

### Added

- Packaged the terrain tool as the `GDT Terrain Generator` addon under `addons/gdt_terrain/`.
- Added an editor plugin manifest and custom `GdtTerrain3D` node registration.
- Added Poly Haven CC0 texture attribution for the optional example terrain material sets.
- `GdtTerrain3D` class name as the public terrain node identity.
- `Bake Preset` workflow choices for `Visual Only`, `Game Ready`, `High Accuracy`, and `Custom`.
- Read-only `Bake State` summary for preview-only, visual-only, playable, and testing-collision workflows.
- `game_ready_demo.tscn` with a simple `CharacterBody3D` proof scene for walking on baked terrain collision.
- `Terrain Scale` noise zoom control for broader continent-scale landforms without tiny frequency values.
- `Visible Chunks` status and `Reveal All Chunks` utility to make viewport culling obvious after a complete bake.
- `Snow Enabled` toggle for disabling snow blending while keeping snow settings available.
- `Material Mode` for switching between basic dry terrain colors and PBR texture layers.
- Default terrain texture layers using the six `res://material/` source texture sets.
- Per-texture-layer enable checkboxes so users can choose which terrain materials participate, with enabled texture sources collapsing into the base-to-top material stack.
- Shader-based stochastic texture bombing controls to reduce repeated texture tiling.
- Camera/focus-based macro texture tiling controls for close, medium, and far terrain texture density.
- `Terrain Performance Preset` for Quality, Balanced, and Performance rendering budgets.
- High-view visual LOD bias for camera/player views that expose most terrain chunks at once.
- Visible LOD counters and estimated visible triangle count for profiling all-visible terrain.
- Optional baked far-material color cache for cheaper distant texture-layer shading.
- Shared heightfield pipeline for noise, imported heightmaps, mesh generation, collision, and export.
- `Terrain Source` controls for replacing procedural noise with an imported PNG heightmap.
- Replaced visible LOD edge curtains with surface stitching so reduced-detail chunks keep seamless full-detail borders without dark split-line artifacts.
- Native Godot `.tres` terrain preset save/load workflow.
- Heightmap export to grayscale PNG.

### Changed

- Game-ready collision intent now defaults to final-only, all chunks, half quality.
- Final generation now clears active mesh or shader preview nodes before building final chunks.
- Saved LOD and collision resources now reload with cache replacement so regenerated terrain scale/settings cannot reuse stale collision meshes.
- Terrain material generation can now sample albedo, Normal GL, roughness, and optional height maps without changing terrain mesh generation.
- Balanced rendering now uses more aggressive distant LOD thresholds, disables terrain self-shadowing through the performance policy, and avoids expensive far normal/roughness/height/texture-bombing shader work.
- Macro texture tiling now uses full 3D focus distance so high editor/game cameras no longer force close tiling onto terrain directly below them.
- Texture bombing now blends randomized neighboring cells so close-range layer samples break repeated tiles more effectively.
- Fixed texture-bombing zero-weight gaps in both Light and Quality sampling paths that could show up as black square artifacts.
- Far-material cache usage is now restricted to genuinely distant horizontal terrain so close inspection views keep full PBR texture layers after final save.
- Terrain mesh generation now samples from the active heightfield instead of calling noise directly.
- Tidied the Inspector workflow by moving preset and heightmap buttons beside their paths, grouping primary terrain actions, and replacing several maintenance buttons with a single selected utility runner.
- Split terrain mesh building into `addons/gdt_terrain/src/terrain_mesh_builder.gd`.
- Kept terrain material handling in `addons/gdt_terrain/src/terrain_material_manager.gd`.
- Renamed and moved the main terrain script to `addons/gdt_terrain/src/gdt_terrain_3d.gd`.
- Moved the reusable terrain scene into the addon folder while keeping `game_ready_demo.tscn` as the root project demo.

### Removed

- Removed the current procedural water renderer and water-level terrain coloring so the project can return to a clean dry-terrain baseline before a replacement water system is planned.

## v5 - Procedural Visual Material Upgrade

### Added

- Procedural terrain shader for newly generated terrain.
- V5 vertex mask encoding for height, slope, shore/seabed influence, and snow influence.
- Generated procedural noise textures for terrain material variation.
- Visual Material controls for macro variation, detail noise, rock detail, snow detail, shore wetness, brightness, and contrast.
- Procedural water shader with subtle static color variation.
- `Setup Preview Lighting` helper for editor inspection.
- Saved visual resources: procedural terrain material, water material, shaders, and generated noise textures.

### Changed

- Newly generated terrain uses shader parameters for water, snow, rock, shore, seabed, and color tuning instead of rewriting mesh colors.
- Water level and material tuning no longer regenerate or recolor V5 terrain chunks.
- Existing V4 generated terrain remains visible through the legacy vertex-color material path.

### Performance

- V5 visual edits update material uniforms only, avoiding expensive mesh resource rewrites.
- Procedural detail is static and lightweight by default.

## v4 - Editor LOD + Lightweight Collision

### Added

- Automatic camera or target-driven LOD focus.
- Optional `LOD Target Path` for using any `Node3D` as the LOD center.
- Distance-based terrain LOD using saved final mesh resources.
- LOD profile presets: `Quality`, `Balanced`, and `Performance`.
- Four final mesh LODs per chunk: full, half, quarter, and eighth resolution.
- Skirt geometry on lower LOD meshes to reduce visible cracks between LOD levels.
- Progressive collision generation.
- Collision coverage controls: `Near Center`, `Visible Chunks`, and `All Chunks`.
- Collision quality controls: `Full`, `Half`, `Quarter`, and `Eighth`.
- Collision radius and collision chunks-per-frame controls.
- Collision visual toggle for inspecting generated collision helper nodes.

### Changed

- LOD and culling now follow an automatic target/camera focus when available.
- Collision is no longer assumed to cover every chunk.
- Collision can be generated after final terrain without rebuilding visual chunks.
- Project main scene reference now uses `res://node_3d.tscn`.

### Performance

- Final terrain can use lower-detail meshes in the viewport without changing terrain generation settings.
- Collision can be restricted to the active inspection area.
- Collision defaults to lower-detail physics meshes for cheaper editor interaction.

## v3 - Environment Detail Pass

### Added

- Flat generated water plane.
- Water level, color, and alpha controls.
- Height and slope-aware vertex coloring.
- Editable lowland, grass, shore, seabed, rock, and snow colors.
- Seabed coloring below the water level.

### Changed

- Water and color-band changes recolor existing chunks instead of rebuilding terrain geometry.
- Final terrain recolors are saved back to external mesh resources.

## v2 - Chunked 4K Terrain

### Added

- Chunked terrain generation under `TerrainChunks`.
- Configurable chunk resolution and chunks per side.
- Progressive generation to keep the editor responsive.
- Preview and final generation modes.
- Final terrain locking.
- External binary mesh resource saving.
- Viewport quality controls.
- Distance culling.
- Optional collision generation and collision removal.

### Fixed

- Seam and hole issues from earlier single-mesh terrain generation.
- Large `.tscn` bloat by externalizing generated mesh resources.

## v1 - Procedural Terrain Generator

### Added

- Noise-based procedural terrain generation.
- Configurable terrain size, resolution, height scale, seed, frequency, octaves, lacunarity, and gain.
- Vertex-color terrain material.
- Inspector descriptions for terrain controls.
