# Changelog

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
