# Changelog

## v1.2.0 - Unreleased

### Added

- Added grayscale brush texture masks for paint and scatter strength.
- Added sculpt brush workflows for raise, lower, smooth, height, and slope shaping.
- Added sculpt brush mask options, including soft circle, hard circle, noise, ridge, and custom masks.
- Added navigation bake helper actions for creating a terrain navigation region and baking from generated chunks.
- Added terrain occluder bake helper for generating lower-detail occluder geometry.
- Added public terrain query support for height, normal, slope, region lookup, material weights, and dominant painted material sampling.

### Changed

- Improved generated terrain resource externalization before editor saves.
- Improved saved LOD resource rebuilding after sculpting and mesh topology changes.
- Reduced LOD terrain meshes now keep a full-detail outer perimeter and stitch into shared coarse interior edges, eliminating editor and runtime hairline gaps between chunks in Balanced/Performance presets.
- Updated the example scene with the latest baked terrain, collision, LOD, and helper-resource state.

### Fixed

- Fixed chunk-edge gaps caused by mixed terrain LODs in Balance and Performance presets.
- Fixed runtime-only LOD hairlines caused by internal T-junctions in reduced-detail chunk meshes.
- Fixed collision and helper bake paths so they reject stale LOD resources with older seam geometry.

## v1.1.0 - 2026-05-23

### Added

- Added a Terrain3D-inspired editor UI that appears when selecting a `GdtTerrain3D` node.
- Added a left tool palette for select, material paint, scatter add, and scatter erase.
- Added a bottom contextual settings bar for paint and scatter brush controls.
- Added a `GDT Terrain` editor menu for generation, collision, scatter, preset, and utility actions.
- Added material painting for lowland, ground, upper, rocky, cliff, and snow layers.
- Added scatter add/erase brush workflow using existing scatter resources.
- Added performance summary tooling for quick terrain diagnostics.
- Added helper action to create/setup a texture focus camera for clean texture-distance transitions.

### Changed

- Moved generation and utility actions out of inspector buttons and into the editor UI/menu.
- Cleaned up the inspector so it focuses on settings rather than one-off actions.
- Simplified performance controls around Quality, Balanced, and Performance presets.
- Made Active Camera the default texture focus behavior to reduce runtime texture flicker.
- Improved close, medium, and far texture tiling transitions.
- Updated addon defaults for a lighter first-run setup.
- Improved material layer toggles so procedural layers update correctly.
- Improved material painting so painted layers ignore procedural remapping and paint the chosen layer directly.
- Improved paint strength, softness, and clear painted mask behavior.
- Improved runtime LOD stability, collision refresh behavior, and cached terrain resources.
- Updated the example scene and addon version to `1.1.0`.

### Fixed

- Fixed console errors caused by loading `.png.import` files as textures.
- Fixed snow painting stacking or leaking into adjacent material layers.
- Fixed procedural material layer toggles not visually updating after brush changes.
- Fixed texture focus behavior in runtime scenes and fresh plugin test projects.
- Fixed large text-scene warnings by keeping generated binary terrain data external.

### Packaging

- Added Asset Library `.gitattributes` export rules so downloads include the addon folder without the full repository.
- Kept the main README short and focused on installation, usage, materials, presets, and the example scene.
