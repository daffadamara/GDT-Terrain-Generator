# Changelog

All notable changes to this project are documented here.

## Unreleased

### Added

- Shared heightfield pipeline for noise, imported heightmaps, mesh generation, collision, and export.
- `Terrain Source` controls for replacing procedural noise with an imported PNG heightmap.
- Standalone `ProceduralWater3D` node with animated waves, depth tint, foam, refraction controls, and water quality presets.
- Improved water defaults with shallow/mid/deep blue depth coloring, linear-depth shoreline foam, shoreline alpha fade, larger foam tiling controls, and more visible top-down surface highlights.
- Water now renders as a one-sided surface to prevent transparent backface tearing when waves are tall.
- Replaced visible LOD edge curtains with surface stitching so reduced-detail chunks keep seamless full-detail borders without dark split-line artifacts.
- Native Godot `.tres` terrain preset save/load workflow.
- Heightmap export to grayscale PNG.

### Changed

- Terrain mesh generation now samples from the active heightfield instead of calling noise directly.
- Water shader, material, mesh, and resource saving now live outside the terrain material manager.
- Terrain water controls now configure an auto-created or assigned `ProceduralWater3D` node without overwriting existing water visual tuning on scene reload.
- Tidied the Inspector workflow by moving preset and heightmap buttons beside their paths, grouping primary terrain actions, and replacing several maintenance buttons with a single selected utility runner.
- Split terrain mesh building into `terrain_mesh_builder.gd`.
- Kept terrain material handling in `terrain_material_manager.gd`.
- Kept `node_3d.gd` focused on editor workflow, generation orchestration, LOD, culling, collision, and scene ownership.

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
