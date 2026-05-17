@tool
extends Node3D
class_name GdtTerrain3D

const TerrainMaterialManagerScript = preload("res://addons/gdt_terrain/src/terrain_material_manager.gd")
const TerrainMeshBuilderScript = preload("res://addons/gdt_terrain/src/terrain_mesh_builder.gd")
const TerrainHeightfieldScript = preload("res://addons/gdt_terrain/src/terrain_heightfield.gd")
const TerrainPresetScript = preload("res://addons/gdt_terrain/src/terrain_preset.gd")

enum GenerationMode { PREVIEW, FINAL }
enum SourceMode { NOISE, HEIGHTMAP }
enum CollisionMode { DISABLED, FINAL_ONLY, ALL_BUILDS }
enum PreviewBackend { MESH, SHADER }
enum BakePreset { VISUAL_ONLY, GAME_READY, HIGH_ACCURACY, CUSTOM }
enum TerrainMaterialMode { BASIC_COLORS, TEXTURE_LAYERS }
enum TextureBombingSamples { OFF, LIGHT, QUALITY }
enum ViewportQuality { FULL, HALF, QUARTER, EIGHTH }
enum LodProfile { QUALITY, BALANCED, PERFORMANCE }
enum TerrainPerformancePreset { QUALITY, BALANCED, PERFORMANCE }
enum TerrainShadowCasting { ON, OFF, PERFORMANCE_PRESET }
enum CollisionCoverage { NEAR_CENTER, VISIBLE_CHUNKS, ALL_CHUNKS }
enum UtilityAction { SAVE_MESH_RESOURCES, SETUP_PREVIEW_LIGHTING, GENERATE_COLLISION, REMOVE_COLLISION, REVEAL_ALL_CHUNKS }
enum GenerationPhase { IDLE, BUILDING_MESH_ARRAYS, FINALIZING_CHUNKS, SAVING_LODS, GENERATING_COLLISION, SAVING_RESOURCES }

const TERRAIN_CHUNKS_NAME := "TerrainChunks"
const SHADER_PREVIEW_NAME := "ShaderPreviewTerrain"
const PREVIEW_LIGHT_NAME := "TerrainPreviewLight"
const PREVIEW_ENVIRONMENT_NAME := "TerrainPreviewEnvironment"
const LEGACY_TERRAIN_MESH_NAME := "TerrainMesh"
const LEGACY_TERRAIN_BODY_NAME := "TerrainBody"
const DEFAULT_GENERATED_RESOURCE_DIR := "res://generated_terrain"
const LOD_STRIDES := [1, 2, 4, 8]
const TERRAIN_LOD_EDGE_VERSION := 3
const TERRAIN_ENCODING_V5_MASKS := TerrainMaterialManagerScript.TERRAIN_ENCODING_V5_MASKS
const TERRAIN_ENCODING_LEGACY_COLORS := TerrainMaterialManagerScript.TERRAIN_ENCODING_LEGACY_COLORS

const SHADER_PREVIEW_CODE := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D height_texture;
uniform vec4 lowland_color : source_color = vec4(0.15, 0.21, 0.09, 1.0);
uniform vec4 grass_color : source_color = vec4(0.24, 0.33, 0.15, 1.0);
uniform vec4 rock_color : source_color = vec4(0.27, 0.24, 0.18, 1.0);
uniform vec4 snow_color : source_color = vec4(0.86, 0.84, 0.76, 1.0);
uniform bool snow_enabled = true;
uniform float height_min = -5.0;
uniform float height_max = 5.0;
uniform float terrain_size = 64.0;
uniform float height_texel_size = 0.001953125;
uniform float height_scale = 5.0;
uniform float snow_height = 5.0;
uniform float rock_slope_threshold = 0.44;
uniform float material_brightness = 1.32;
uniform float material_contrast = 1.0;

varying float terrain_height;
varying float terrain_slope;
varying vec2 terrain_uv;

float soft_band(float edge0, float edge1, float value) {
	if (abs(edge1 - edge0) < 0.0001) {
		return 0.0;
	}
	float x = clamp((value - edge0) / (edge1 - edge0), 0.0, 1.0);
	return x * x * (3.0 - 2.0 * x);
}

float sample_height(vec2 uv) {
	float height_amount = texture(height_texture, clamp(uv, vec2(0.0), vec2(1.0))).r;
	return mix(height_min, height_max, height_amount);
}

vec3 adjust_color(vec3 color) {
	color *= material_brightness;
	color = (color - vec3(0.5)) * material_contrast + vec3(0.5);
	return clamp(color, vec3(0.0), vec3(1.0));
}

void vertex() {
	terrain_uv = UV;
	terrain_height = sample_height(UV);
	float texel = height_texel_size;
	float left_height = sample_height(UV + vec2(-texel, 0.0));
	float right_height = sample_height(UV + vec2(texel, 0.0));
	float back_height = sample_height(UV + vec2(0.0, -texel));
	float forward_height = sample_height(UV + vec2(0.0, texel));
	float sample_distance = max(terrain_size * texel, 0.001);
	vec3 normal_estimate = normalize(vec3(left_height - right_height, sample_distance * 2.0, back_height - forward_height));
	terrain_slope = clamp(1.0 - normal_estimate.y, 0.0, 1.0);
	VERTEX.y = terrain_height;
	NORMAL = normal_estimate;
}

void fragment() {
	float height_range = max(height_scale, 0.001);
	float normalized_height = clamp((terrain_height / height_range + 1.0) * 0.5, 0.0, 1.0);
	vec3 color = mix(lowland_color.rgb, grass_color.rgb, soft_band(0.20, 0.78, normalized_height));

	float rock_amount = soft_band(rock_slope_threshold, min(1.0, rock_slope_threshold + 0.25), terrain_slope);
	float snow_blend_width = max(height_scale * 0.12, 0.35);
	float snow_amount = snow_enabled ? soft_band(snow_height - snow_blend_width, snow_height + snow_blend_width, terrain_height) : 0.0;
	color = mix(color, rock_color.rgb, rock_amount);
	color = mix(color, snow_color.rgb, snow_amount);

	ALBEDO = adjust_color(color);
	ROUGHNESS = mix(0.92, 0.64, rock_amount);
	SPECULAR = 0.18;
}
"""

@export_category("Terrain Shape")

## Full terrain width and depth in Godot units. This is the size of the whole chunk grid, not a single chunk.
@export_range(4.0, 512.0, 1.0) var terrain_size: float = 64.0:
	set(value):
		terrain_size = maxf(4.0, value)
		_sync_auto_visible_radius()
		_mark_heightfield_dirty()
		_queue_regenerate()

## Final mesh detail per chunk. Use 256 with 16 chunks per side for a 4096 x 4096 total terrain grid.
@export_range(16, 256, 1) var chunk_resolution: int = 256:
	set(value):
		chunk_resolution = clampi(value, 16, 256)
		_mark_heightfield_dirty()
		_queue_regenerate()

## Number of chunks along each side of the terrain. More chunks cover the same world size with more total detail.
@export_range(1, 16, 1) var chunks_per_side: int = 1:
	set(value):
		chunks_per_side = clampi(value, 1, 16)
		_mark_heightfield_dirty()
		_queue_regenerate()

## Vertical height multiplier for the terrain. Higher values create taller mountains and deeper valleys.
@export_range(0.0, 64.0, 0.1) var height_scale: float = 5.0:
	set(value):
		height_scale = maxf(0.0, value)
		_mark_heightfield_dirty()
		_queue_regenerate()

@export_category("Terrain Pattern")

## Random seed for the noise. Change this to get a different terrain layout while keeping the same style.
@export var terrain_seed: int = 1345:
	set(value):
		terrain_seed = value
		_mark_heightfield_dirty()
		_reset_visual_noise_textures()
		_queue_regenerate()

## Size of the main noise features. Lower values make broad landforms; higher values make tighter, busier terrain.
@export_range(0.001, 1.0, 0.001) var noise_frequency: float = 0.032:
	set(value):
		noise_frequency = maxf(0.001, value)
		_mark_heightfield_dirty()
		_queue_regenerate()

## Zooms the procedural noise pattern. Larger values create broader continents without changing terrain size.
@export_range(0.1, 256.0, 0.1, "or_greater") var terrain_scale: float = 1.0:
	set(value):
		terrain_scale = maxf(0.1, value)
		_mark_heightfield_dirty()
		_queue_regenerate()

## Number of layered noise passes. More octaves add finer detail, but increase generation time.
@export_range(1, 12, 1) var octaves: int = 7:
	set(value):
		octaves = maxi(1, value)
		_mark_heightfield_dirty()
		_queue_regenerate()

## Frequency jump between noise layers. Higher values make the added detail smaller and sharper.
@export_range(1.0, 4.0, 0.01) var lacunarity: float = 2.1:
	set(value):
		lacunarity = maxf(1.0, value)
		_mark_heightfield_dirty()
		_queue_regenerate()

## Strength of each added noise layer. Lower values are smoother; higher values keep more rough detail.
@export_range(0.0, 1.0, 0.01) var gain: float = 0.42:
	set(value):
		gain = clampf(value, 0.0, 1.0)
		_mark_heightfield_dirty()
		_queue_regenerate()

@export_category("Terrain Source")

## Chooses where terrain heights come from. Noise uses the procedural controls; Heightmap imports a 16-bit PNG and replaces noise shape data.
@export_enum("Noise", "Heightmap") var source_mode: int = SourceMode.NOISE:
	set(value):
		source_mode = clampi(value, SourceMode.NOISE, SourceMode.HEIGHTMAP)
		_mark_heightfield_dirty()
		_queue_regenerate()

## 16-bit PNG heightmap used when Source Mode is Heightmap. The image is resampled to the current terrain grid.
@export_file("*.png") var heightmap_path: String = "":
	set(value):
		heightmap_path = value
		_mark_heightfield_dirty()
		_queue_regenerate()

## Mirrors the imported heightmap along the terrain X axis.
@export var heightmap_flip_x: bool = false:
	set(value):
		heightmap_flip_x = value
		_mark_heightfield_dirty()
		_queue_regenerate()

## Mirrors the imported heightmap along the terrain Z axis.
@export var heightmap_flip_z: bool = false:
	set(value):
		heightmap_flip_z = value
		_mark_heightfield_dirty()
		_queue_regenerate()

## Inverts imported height values before applying Height Scale.
@export var heightmap_invert: bool = false:
	set(value):
		heightmap_invert = value
		_mark_heightfield_dirty()
		_queue_regenerate()

@export_category("Environment")

## World Y height where terrain begins blending toward snow. Updates existing terrain colors without rebuilding chunks.
@export var snow_enabled: bool = true:
	set(value):
		snow_enabled = value
		_queue_visual_update()

## World Y height where terrain begins blending toward snow. Updates existing terrain colors without rebuilding chunks.
@export_range(-64.0, 64.0, 0.1) var snow_height: float = 5.0:
	set(value):
		snow_height = value
		_queue_visual_update()

## How steep terrain must be before it blends toward rock. Lower values create more exposed rock without rebuilding chunks.
@export_range(0.0, 1.0, 0.01) var rock_slope_threshold: float = 0.44:
	set(value):
		rock_slope_threshold = clampf(value, 0.0, 1.0)
		_queue_visual_update()

## Color used for the lowest dry land before it blends into grass. Updates existing terrain colors without rebuilding chunks.
@export var lowland_color: Color = Color(0.15, 0.21, 0.09):
	set(value):
		lowland_color = value
		_queue_visual_update()

## Main green terrain color for rolling hills and flatter mid elevations. Updates existing terrain colors without rebuilding chunks.
@export var grass_color: Color = Color(0.24, 0.33, 0.15):
	set(value):
		grass_color = value
		_queue_visual_update()

## Color blended onto steep slopes. Updates existing terrain colors without rebuilding chunks.
@export var rock_color: Color = Color(0.27, 0.24, 0.18):
	set(value):
		rock_color = value
		_queue_visual_update()

## Color blended onto high elevations above Snow Height. Updates existing terrain colors without rebuilding chunks.
@export var snow_color: Color = Color(0.86, 0.84, 0.76):
	set(value):
		snow_color = value
		_queue_visual_update()

@export_category("Visual Material")

## Uses a procedural shader material for newly generated terrain. Existing V4 chunks remain visible, but regenerate once for full V5 mask-based visuals.
@export var procedural_material_enabled: bool = true:
	set(value):
		procedural_material_enabled = value
		_update_visual_materials()

## Chooses between the old color-ramp terrain shader and layered PBR texture materials.
@export_enum("Basic Colors", "Texture Layers") var material_mode: int = TerrainMaterialMode.TEXTURE_LAYERS:
	set(value):
		material_mode = clampi(value, TerrainMaterialMode.BASIC_COLORS, TerrainMaterialMode.TEXTURE_LAYERS)
		_update_visual_materials()

## Enables the low-elevation texture source. Disabled texture sources are removed from the ordered layer stack.
@export var lowland_layer_enabled: bool = true:
	set(value):
		lowland_layer_enabled = value
		_update_visual_materials()

## Folder containing the low-elevation diffuse, normal GL, roughness, and displacement maps.
@export_dir var lowland_material_folder: String = "res://material/sand_03":
	set(value):
		lowland_material_folder = value
		_update_visual_materials()

## Enables the main ground texture source. If Lowland is disabled, this becomes the base layer.
@export var ground_layer_enabled: bool = true:
	set(value):
		ground_layer_enabled = value
		_update_visual_materials()

## Folder containing the main ground diffuse, normal GL, roughness, and displacement maps.
@export_dir var ground_material_folder: String = "res://material/forest_ground":
	set(value):
		ground_material_folder = value
		_update_visual_materials()

## Enables the upper grass/rock texture source.
@export var upper_layer_enabled: bool = true:
	set(value):
		upper_layer_enabled = value
		_update_visual_materials()

## Folder containing the upper grass or broken ground diffuse, normal GL, roughness, and displacement maps.
@export_dir var upper_material_folder: String = "res://material/aerial_grass_rock":
	set(value):
		upper_material_folder = value
		_update_visual_materials()

## Enables the rocky transition texture source.
@export var rocky_layer_enabled: bool = true:
	set(value):
		rocky_layer_enabled = value
		_update_visual_materials()

## Folder containing the rocky transition diffuse, normal GL, roughness, and displacement maps.
@export_dir var rocky_material_folder: String = "res://material/rocky_terrain":
	set(value):
		rocky_material_folder = value
		_update_visual_materials()

## Enables the steep cliff texture source.
@export var cliff_layer_enabled: bool = true:
	set(value):
		cliff_layer_enabled = value
		_update_visual_materials()

## Folder containing the cliff face diffuse, normal GL, roughness, and displacement maps.
@export_dir var cliff_material_folder: String = "res://material/rock_face":
	set(value):
		cliff_material_folder = value
		_update_visual_materials()

## Enables the snow texture source. Snow Enabled still controls whether snow masks are produced.
@export var snow_layer_enabled: bool = true:
	set(value):
		snow_layer_enabled = value
		_update_visual_materials()

## Folder containing the snow diffuse, normal GL, roughness, and displacement maps.
@export_dir var snow_material_folder: String = "res://material/snow":
	set(value):
		snow_material_folder = value
		_update_visual_materials()

## World-space texture tiling density for layered terrain materials.
@export_range(0.01, 2.0, 0.01) var texture_tile_scale: float = 0.18:
	set(value):
		texture_tile_scale = maxf(0.01, value)
		_update_visual_materials()

## Blends close, medium, and far texture tiling by distance from the LOD target or active camera.
@export var macro_texture_tiling_enabled: bool = true:
	set(value):
		macro_texture_tiling_enabled = value
		_update_visual_materials()

## Close-range texture density. Higher values create smaller, sharper nearby tiles.
@export_range(0.01, 2.0, 0.01) var close_texture_tile_scale: float = 0.30:
	set(value):
		close_texture_tile_scale = maxf(0.01, value)
		_update_visual_materials()

## Medium-range texture density used through the normal viewing distance.
@export_range(0.01, 2.0, 0.01) var medium_texture_tile_scale: float = 0.18:
	set(value):
		medium_texture_tile_scale = maxf(0.01, value)
		_update_visual_materials()

## Far-range texture density. Lower values create larger broad distant tiles.
@export_range(0.01, 2.0, 0.01) var far_texture_tile_scale: float = 0.075:
	set(value):
		far_texture_tile_scale = maxf(0.01, value)
		_update_visual_materials()

## Distance from the focus point that keeps close texture tiling fully active.
@export_range(0.0, 4096.0, 0.1) var close_texture_radius: float = 32.0:
	set(value):
		close_texture_radius = maxf(0.0, value)
		_update_visual_materials()

## Distance where close tiling has fully blended into medium tiling.
@export_range(0.0, 4096.0, 0.1) var medium_texture_radius: float = 96.0:
	set(value):
		medium_texture_radius = maxf(0.0, value)
		_update_visual_materials()

## Distance where medium tiling has fully blended into far tiling.
@export_range(0.0, 4096.0, 0.1) var far_texture_radius: float = 192.0:
	set(value):
		far_texture_radius = maxf(0.0, value)
		_update_visual_materials()

## Softens transitions between terrain texture layers.
@export_range(0.01, 1.0, 0.01) var layer_blend_softness: float = 0.18:
	set(value):
		layer_blend_softness = clampf(value, 0.01, 1.0)
		_update_visual_materials()

## Strength of sampled normal maps in texture layer mode.
@export_range(0.0, 2.0, 0.01) var texture_normal_strength: float = 0.75:
	set(value):
		texture_normal_strength = clampf(value, 0.0, 2.0)
		_update_visual_materials()

## Multiplier applied to sampled roughness maps in texture layer mode.
@export_range(0.1, 2.0, 0.01) var roughness_multiplier: float = 1.0:
	set(value):
		roughness_multiplier = clampf(value, 0.1, 2.0)
		_update_visual_materials()

## Uses displacement maps as subtle blend breakup between material layers without moving geometry.
@export_range(0.0, 1.0, 0.01) var height_blend_strength: float = 0.12:
	set(value):
		height_blend_strength = clampf(value, 0.0, 1.0)
		_update_visual_materials()

## Randomizes texture UV cells to reduce visible tiling repetition.
@export var texture_bombing_enabled: bool = true:
	set(value):
		texture_bombing_enabled = value
		_update_visual_materials()

## Strength of stochastic UV offsets and rotations.
@export_range(0.0, 1.0, 0.01) var texture_bombing_strength: float = 0.55:
	set(value):
		texture_bombing_strength = clampf(value, 0.0, 1.0)
		_update_visual_materials()

## World-space size of stochastic texture bombing cells.
@export_range(0.05, 4.0, 0.01) var texture_bombing_cell_scale: float = 0.65:
	set(value):
		texture_bombing_cell_scale = maxf(0.05, value)
		_update_visual_materials()

## Number of randomized texture samples used for texture bombing.
@export_enum("Off", "Light", "Quality") var texture_bombing_samples: int = TextureBombingSamples.LIGHT:
	set(value):
		texture_bombing_samples = clampi(value, TextureBombingSamples.OFF, TextureBombingSamples.QUALITY)
		_update_visual_materials()

## Strength of broad color variation across the terrain surface. Higher values break up flat color bands.
@export_range(0.0, 1.0, 0.01) var macro_variation_strength: float = 0.18:
	set(value):
		macro_variation_strength = clampf(value, 0.0, 1.0)
		_update_visual_materials()

## World-space scale of broad material variation. Lower values make larger patches; higher values make tighter variation.
@export_range(0.001, 1.0, 0.001) var macro_variation_scale: float = 0.04:
	set(value):
		macro_variation_scale = maxf(0.001, value)
		_update_visual_materials()

## Strength of fine procedural noise on grass, rock, and snow. Keep low for stable viewport performance.
@export_range(0.0, 1.0, 0.01) var detail_noise_strength: float = 0.15:
	set(value):
		detail_noise_strength = clampf(value, 0.0, 1.0)
		_update_visual_materials()

## World-space scale of fine procedural detail. Higher values make smaller speckled detail.
@export_range(0.01, 4.0, 0.01) var detail_noise_scale: float = 0.45:
	set(value):
		detail_noise_scale = maxf(0.01, value)
		_update_visual_materials()

## Extra procedural contrast on steep rock areas.
@export_range(0.0, 1.0, 0.01) var rock_detail_strength: float = 0.25:
	set(value):
		rock_detail_strength = clampf(value, 0.0, 1.0)
		_update_visual_materials()

## Extra procedural contrast on snowy areas.
@export_range(0.0, 1.0, 0.01) var snow_detail_strength: float = 0.08:
	set(value):
		snow_detail_strength = clampf(value, 0.0, 1.0)
		_update_visual_materials()

## Overall material brightness multiplier applied by the procedural terrain shader.
@export_range(0.25, 2.0, 0.01) var material_brightness: float = 1.32:
	set(value):
		material_brightness = clampf(value, 0.25, 2.0)
		_update_visual_materials()

## Overall material contrast applied by the procedural terrain shader.
@export_range(0.25, 2.0, 0.01) var material_contrast: float = 1.0:
	set(value):
		material_contrast = clampf(value, 0.25, 2.0)
		_update_visual_materials()

@export_category("Workflow")

## Automatically rebuilds the lightweight preview when terrain settings change.
@export var auto_update: bool = true:
	set(value):
		auto_update = value
		if auto_update:
			_queue_regenerate(GenerationMode.PREVIEW)

## High-level bake intent. Use Game Ready when the baked terrain should be playable immediately.
@export_enum("Visual Only", "Game Ready", "High Accuracy", "Custom") var bake_preset: int = BakePreset.GAME_READY:
	set(value):
		bake_preset = clampi(value, BakePreset.VISUAL_ONLY, BakePreset.CUSTOM)
		_apply_bake_preset()

## Lets the generator choose preview detail and chunk build speed automatically. Collision is controlled separately by Collision Mode.
@export var auto_performance_settings: bool = true:
	set(value):
		auto_performance_settings = value
		_queue_regenerate(GenerationMode.PREVIEW)

## Preview renderer used while tuning terrain before a final mesh bake.
@export_enum("Mesh Preview", "Shader Preview") var preview_backend: int = PreviewBackend.SHADER:
	set(value):
		preview_backend = clampi(value, PreviewBackend.MESH, PreviewBackend.SHADER)
		_queue_regenerate(GenerationMode.PREVIEW, true)

## Height texture detail used by Shader Preview.
@export_range(64, 1024, 1) var shader_preview_texture_resolution: int = 256:
	set(value):
		shader_preview_texture_resolution = clampi(value, 64, 1024)
		_queue_regenerate(GenerationMode.PREVIEW)

## Plane subdivisions used by Shader Preview. Higher values show smoother GPU displacement but cost more viewport rendering.
@export_range(16, 512, 1) var shader_preview_subdivisions: int = 128:
	set(value):
		shader_preview_subdivisions = clampi(value, 16, 512)
		_queue_regenerate(GenerationMode.PREVIEW)

## Number of CPU worker threads used to prepare terrain mesh arrays before main-thread finalization.
@export_range(1, 8, 1) var generation_worker_count: int = 1

## Approximate milliseconds per frame spent on main-thread chunk finalization, LOD saving, and collision.
@export_range(1.0, 33.0, 0.5) var finalization_time_budget_ms: float = 8.0

## Builds final collision after visible chunks and saved LODs are ready, keeping the editor more responsive.
@export var defer_final_collision: bool = true

## True after Generate Final finishes. Locked terrain is saved with the scene and will not regenerate until Clear Generated Terrain is used.
@export var final_terrain_locked: bool = false:
	set(value):
		final_terrain_locked = value

## Saves final chunk meshes as binary .res files so the text scene stays small and quick to save/load.
@export var save_final_meshes_as_resources: bool = true

## Prints final generation timing buckets to the output panel for profiling.
@export var print_generation_timings: bool = false

## Folder used for generated binary mesh and collision resources.
@export var generated_resource_directory: String = DEFAULT_GENERATED_RESOURCE_DIR

@export_category("Presets")

## Path for saving or loading a native Godot terrain preset resource.
@export_file("*.tres") var preset_path: String = "res://terrain_preset.tres"

## Saves the current generator, visual, viewport, and collision settings to Preset Path.
@export_tool_button("Save Preset") var save_preset_button = save_preset

## Loads settings from Preset Path. Locked final terrain only receives non-geometry visual settings.
@export_tool_button("Load Preset") var load_preset_button = load_preset

@export_category("Heightmap I/O")

## Path where Export Heightmap writes the current active heightfield as a 16-bit grayscale PNG.
@export_file("*.png") var export_heightmap_path: String = "res://terrain_heightmap.png"

## Exports the current active heightfield to Export Heightmap Path as a grayscale PNG.
@export_tool_button("Export Heightmap") var export_heightmap_button = export_heightmap

@export_category("Viewport Performance")

## Viewport-only visual detail. Lower quality draws fewer vertices and triangles, but does not change terrain settings.
@export_enum("Full", "Half", "Quarter", "Eighth") var viewport_quality: int = ViewportQuality.FULL:
	set(value):
		viewport_quality = clampi(value, ViewportQuality.FULL, ViewportQuality.EIGHTH)
		if final_terrain_locked:
			_apply_viewport_culling()
		else:
			_queue_regenerate(_active_generation_mode, true)

## Swaps saved final chunk meshes by distance from Culling Center, similar to Unity-style terrain LOD.
@export var viewport_lod_enabled: bool = true:
	set(value):
		viewport_lod_enabled = value
		_apply_viewport_culling()

## Distance LOD aggressiveness. Quality keeps detail farther out; Performance drops detail sooner.
@export_enum("Quality", "Balanced", "Performance") var lod_profile: int = LodProfile.BALANCED:
	set(value):
		lod_profile = clampi(value, LodProfile.QUALITY, LodProfile.PERFORMANCE)
		_apply_viewport_culling()

## One-click rendering budget for baked terrain. Balanced keeps nearby quality while making all-visible views cheaper.
@export_enum("Quality", "Balanced", "Performance") var terrain_performance_preset: int = TerrainPerformancePreset.BALANCED:
	set(value):
		terrain_performance_preset = clampi(value, TerrainPerformancePreset.QUALITY, TerrainPerformancePreset.PERFORMANCE)
		_apply_terrain_performance_preset()

## Adds extra visual LOD when the focus camera/player is high enough to see most of the terrain.
@export var high_view_lod_bias_enabled: bool = true:
	set(value):
		high_view_lod_bias_enabled = value
		_apply_viewport_culling()

## Height above the terrain origin where High View LOD Bias starts adding cheaper visual LOD.
@export_range(0.0, 4096.0, 0.1) var high_view_lod_start_height: float = 36.0:
	set(value):
		high_view_lod_start_height = maxf(0.0, value)
		_apply_viewport_culling()

## Height where High View LOD Bias reaches its maximum effect.
@export_range(0.0, 4096.0, 0.1) var high_view_lod_full_height: float = 96.0:
	set(value):
		high_view_lod_full_height = maxf(0.0, value)
		_apply_viewport_culling()

## Maximum extra visual LOD applied at high camera/player views. Collision is unchanged.
@export_range(0, 3, 1) var high_view_lod_max_bias: int = 2:
	set(value):
		high_view_lod_max_bias = clampi(value, 0, 3)
		_apply_viewport_culling()

## Terrain chunk shadow casting policy. Performance Preset disables terrain shadows in Balanced/Performance.
@export_enum("On", "Off", "Performance Preset") var terrain_shadow_casting: int = TerrainShadowCasting.PERFORMANCE_PRESET:
	set(value):
		terrain_shadow_casting = clampi(value, TerrainShadowCasting.ON, TerrainShadowCasting.PERFORMANCE_PRESET)
		_apply_terrain_shadow_policy()

## Saves and uses a low-resolution baked color cache for far terrain material pixels.
@export var far_material_cache_enabled: bool = true:
	set(value):
		far_material_cache_enabled = value
		_update_visual_materials()

## Resolution of the whole-terrain far color cache saved with final visual resources.
@export_range(128, 2048, 128) var far_material_cache_resolution: int = 512:
	set(value):
		far_material_cache_resolution = clampi(value, 128, 2048)
		_update_visual_materials()

@export_group("LOD Counters")
@export var visible_lod0_chunks: int = 0
@export var visible_lod1_chunks: int = 0
@export var visible_lod2_chunks: int = 0
@export var visible_lod3_chunks: int = 0
@export var estimated_visible_triangles: int = 0

## Automatically moves the LOD/culling focus to LOD Target Path, or to the active camera when no target is assigned.
@export var automatic_lod_focus: bool = true:
	set(value):
		automatic_lod_focus = value
		_update_processing_state()
		_update_automatic_lod_focus(true)

## Optional Node3D used as the LOD/culling focus. Leave empty to use the active camera when possible.
@export_node_path("Node3D") var lod_target_path: NodePath:
	set(value):
		lod_target_path = value
		_update_automatic_lod_focus(true)

## Minimum world-unit movement before automatic focus reapplies LOD. Larger values reduce editor update work.
@export_range(0.0, 64.0, 0.1) var lod_focus_update_distance: float = 1.0:
	set(value):
		lod_focus_update_distance = maxf(0.0, value)

## Hides chunks outside the visible radius to improve viewport FPS. Disable this if terrain appears to have missing chunks.
@export var viewport_culling_enabled: bool = true:
	set(value):
		viewport_culling_enabled = value
		_apply_viewport_culling()

## Chunk centers farther than this distance from Culling Center are hidden. Auto-scales with Terrain Size until edited manually.
@export_range(0.0, 1024.0, 0.1) var visible_radius: float = 48.0:
	set(value):
		visible_radius = maxf(0.0, value)
		if not _setting_auto_visible_radius:
			_visible_radius_auto_managed = false
		_apply_viewport_culling()

## World X/Z point used as the center of viewport culling. Move it to inspect a different area of a large terrain.
@export var culling_center: Vector2 = Vector2.ZERO:
	set(value):
		culling_center = value
		_update_material_focus_position(Vector3(culling_center.x, 0.0, culling_center.y))
		_apply_viewport_culling()
		_refresh_collision_for_focus_if_needed()

## Shows or hides generated collision helper nodes in the editor viewport. This does not add or remove collision.
@export var collision_visuals_visible: bool = false:
	set(value):
		collision_visuals_visible = value
		_apply_collision_visual_visibility()

@export_group("Advanced Manual Overrides")

## Manual preview detail per chunk. Used only when Auto Performance Settings is off.
@export_range(16, 256, 1) var preview_chunk_resolution: int = 64:
	set(value):
		preview_chunk_resolution = clampi(value, 16, 256)
		if not auto_performance_settings:
			_queue_regenerate(GenerationMode.PREVIEW)

## Manual progressive build speed. Higher values finish faster but may make the editor less responsive. Used only when Auto Performance Settings is off.
@export_range(1, 16, 1) var chunks_per_frame: int = 1:
	set(value):
		chunks_per_frame = clampi(value, 1, 16)

## Collision generation policy. Final Only is the game-ready default; Disabled creates a visual-only bake.
@export_enum("Disabled", "Final Only", "All Builds") var collision_mode: int = CollisionMode.FINAL_ONLY:
	set(value):
		collision_mode = clampi(value, CollisionMode.DISABLED, CollisionMode.ALL_BUILDS)
		_mark_bake_preset_custom()
		if collision_mode == CollisionMode.DISABLED:
			remove_generated_collision()
		else:
			_queue_regenerate()

## Which chunks should receive collision. All Chunks is for playable baked terrain; Near Center and Visible Chunks are editor/testing modes.
@export_enum("Near Center (Testing)", "Visible Chunks (Testing)", "All Chunks") var collision_coverage: int = CollisionCoverage.ALL_CHUNKS:
	set(value):
		collision_coverage = clampi(value, CollisionCoverage.NEAR_CENTER, CollisionCoverage.ALL_CHUNKS)
		_mark_bake_preset_custom()
		_refresh_collision_for_focus_if_needed()

## Collision mesh detail. Half is the default balance for game-ready terrain.
@export_enum("Full", "Half", "Quarter", "Eighth") var collision_quality: int = ViewportQuality.HALF:
	set(value):
		collision_quality = clampi(value, ViewportQuality.FULL, ViewportQuality.EIGHTH)
		_mark_bake_preset_custom()
		_refresh_collision_for_focus_if_needed()

## Collision radius around Culling Center when coverage is Near Center. Auto Performance uses Terrain Size * 0.35.
@export_range(0.0, 1024.0, 0.1) var collision_radius: float = 22.4:
	set(value):
		collision_radius = maxf(0.0, value)
		_refresh_collision_for_focus_if_needed()

## Progressive collision build speed. Higher values finish faster but can make the editor less responsive.
@export_range(1, 16, 1) var collision_chunks_per_frame: int = 1:
	set(value):
		collision_chunks_per_frame = clampi(value, 1, 16)

## Utility command used by Run Selected Utility. These are less common maintenance actions kept out of the primary workflow buttons.
@export_enum("Save Mesh Resources", "Setup Preview Lighting", "Generate Collision", "Remove Collision", "Reveal All Chunks") var selected_utility_action: int = UtilityAction.SAVE_MESH_RESOURCES

## Runs the utility selected above.
@export_tool_button("Run Selected Utility") var run_selected_utility_button = run_selected_utility

@export_group("")
@export_category("Generation Status")

## Read-only progress counter for the current progressive build.
@export var generated_chunks: int:
	get:
		return _generated_chunks
	set(_value):
		pass

## Read-only total number of chunks in the current progressive build.
@export var total_chunks: int:
	get:
		return _total_chunks
	set(_value):
		pass

## Read-only number of generated terrain chunks currently visible after viewport culling.
@export var visible_chunks: int:
	get:
		return _count_visible_generated_chunks()
	set(_value):
		pass

## Read-only flag that is true while chunks are being generated across frames.
@export var is_generating: bool:
	get:
		return _is_generating or _is_generating_collision
	set(_value):
		pass

## Read-only label for the active generation phase.
@export var generation_phase: String:
	get:
		return _generation_phase_text
	set(_value):
		pass

## Read-only summary of whether the current workflow is preview-only, visual-only, or playable.
@export var bake_state: String:
	get:
		return _last_bake_state
	set(_value):
		pass

@export_category("Terrain Actions")

@export_group("Build")

## Builds a fast, lower-detail terrain preview for tuning shape and noise settings.
@export_tool_button("Generate Preview") var generate_preview_button = generate_preview_now

## Builds the final terrain at the configured full resolution, locks it, and makes generated nodes save with the scene.
@export_tool_button("Generate Final") var generate_final_button = generate_final_now

## Stops the current progressive build and leaves already generated chunks visible.
@export_tool_button("Cancel Generation") var cancel_generation_button = cancel_generation

@export_group("Reset")

## Removes generated terrain chunks, unlocks the terrain, and resets the generation progress counters.
@export_tool_button("Clear Generated Terrain") var clear_terrain_button = clear_generated_terrain

@export_group("")

var _noise := FastNoiseLite.new()
var _material_manager := TerrainMaterialManagerScript.new()
var _mesh_builder := TerrainMeshBuilderScript.new()
var _source_heightfield := TerrainHeightfieldScript.new()
var _active_heightfield := TerrainHeightfieldScript.new()
var _shader_preview_material: ShaderMaterial
var _shader_preview_shader: Shader
var _shader_preview_height_texture: Texture2D
var _shader_preview_regenerate_pending := false
var _shader_preview_regenerate_delay := 0.0
var _heightfield_resolution := 0
var _heightfield_dirty := true
var _loading_preset := false
var _applying_bake_preset := false
var _visible_radius_auto_managed := true
var _setting_auto_visible_radius := false

var _regeneration_queued := false
var _queued_generation_mode: int = GenerationMode.PREVIEW

var _pending_chunks: Array[Vector2i] = []
var _mesh_build_jobs: Array = []
var _pending_chunk_results: Array = []
var _pending_lod_save_jobs: Array = []
var _pending_deferred_collision_chunks: Array[MeshInstance3D] = []
var _active_generation_phase: int = GenerationPhase.IDLE
var _generation_phase_text := "Idle"
var _active_generation_mode: int = GenerationMode.PREVIEW
var _active_chunk_resolution := 64
var _active_total_resolution := 64
var _active_step := 1.0
var _active_half_size := 32.0
var _active_build_collision := false
var _active_display_stride := 1
var _last_bake_state := "Preview is for visual iteration only."
var _generation_timing_active := false
var _generation_timing_total_start_usec := 0
var _generation_timing_usec := {}

var _generated_chunks := 0
var _total_chunks := 0
var _is_generating := false
var _pending_recolor_chunks: Array[MeshInstance3D] = []
var _is_recoloring := false
var _pending_collision_chunks: Array[MeshInstance3D] = []
var _collision_target_names: Dictionary = {}
var _is_generating_collision := false
var _last_automatic_lod_focus := Vector2.INF
var _last_material_focus := Vector3.INF
var _last_lod_focus_height := INF


func _reset_generation_timings(mode: int) -> void:
	_generation_timing_active = print_generation_timings and mode == GenerationMode.FINAL
	_generation_timing_total_start_usec = Time.get_ticks_usec() if _generation_timing_active else 0
	_generation_timing_usec = {
		"heightfield": 0,
		"chunk_mesh": 0,
		"lod_save": 0,
		"collision": 0,
		"visual_resource_save": 0,
	}


func _timing_begin() -> int:
	return Time.get_ticks_usec() if _generation_timing_active else 0


func _timing_add(bucket: String, start_usec: int) -> void:
	if not _generation_timing_active or start_usec <= 0:
		return
	_generation_timing_usec[bucket] = int(_generation_timing_usec.get(bucket, 0)) + Time.get_ticks_usec() - start_usec


func _print_generation_timings() -> void:
	if not _generation_timing_active:
		return
	var total_usec := Time.get_ticks_usec() - _generation_timing_total_start_usec
	print(
		"Final terrain timings: total=%.2fs heightfield=%.2fs chunk_mesh=%.2fs lod_save=%.2fs collision=%.2fs visual_resource_save=%.2fs" % [
			float(total_usec) / 1000000.0,
			float(_generation_timing_usec.get("heightfield", 0)) / 1000000.0,
			float(_generation_timing_usec.get("chunk_mesh", 0)) / 1000000.0,
			float(_generation_timing_usec.get("lod_save", 0)) / 1000000.0,
			float(_generation_timing_usec.get("collision", 0)) / 1000000.0,
			float(_generation_timing_usec.get("visual_resource_save", 0)) / 1000000.0,
		]
	)
	_generation_timing_active = false


func _set_generation_phase(phase: int) -> void:
	_active_generation_phase = phase
	match phase:
		GenerationPhase.BUILDING_MESH_ARRAYS:
			_generation_phase_text = "Building mesh arrays"
		GenerationPhase.FINALIZING_CHUNKS:
			_generation_phase_text = "Finalizing chunks"
		GenerationPhase.SAVING_LODS:
			_generation_phase_text = "Saving LOD resources"
		GenerationPhase.GENERATING_COLLISION:
			_generation_phase_text = "Generating collision"
		GenerationPhase.SAVING_RESOURCES:
			_generation_phase_text = "Saving final resources"
		_:
			_generation_phase_text = "Idle"


func _main_thread_budget_exhausted(start_usec: int, processed_count: int) -> bool:
	if processed_count <= 0:
		return false
	var elapsed_usec := Time.get_ticks_usec() - start_usec
	return elapsed_usec >= int(finalization_time_budget_ms * 1000.0)


func _ready() -> void:
	set_process(false)
	_sync_auto_visible_radius(false)
	_apply_terrain_performance_preset(false)
	_update_visual_materials()
	_apply_terrain_shadow_policy()
	_update_material_focus(true)
	if final_terrain_locked and _has_generated_chunks():
		_configure_noise()
		_configure_active_generation_state(GenerationMode.FINAL)
		_ensure_active_heightfield()
		_configure_existing_collision_shapes()
		_update_automatic_lod_focus(true)
		_apply_viewport_culling()
		_update_processing_state()
		return
	_queue_regenerate(GenerationMode.PREVIEW)


func _exit_tree() -> void:
	_finish_mesh_build_thread()


func _process(delta: float) -> void:
	if _is_generating:
		_build_next_chunks()
	elif _is_recoloring:
		_recolor_next_chunks()
	elif _is_generating_collision:
		_build_next_collision_chunks()
	elif _shader_preview_regenerate_pending:
		_process_shader_preview_regenerate(delta)
	else:
		_update_material_focus()
		_update_automatic_lod_focus()


func generate_preview_now() -> void:
	if final_terrain_locked:
		push_warning("Final terrain is locked. Use Clear Generated Terrain before generating a new preview.")
		return
	_queue_regenerate(GenerationMode.PREVIEW, true)


func generate_final_now() -> void:
	if final_terrain_locked:
		push_warning("Final terrain is already locked. Use Clear Generated Terrain before generating it again.")
		return
	_queue_regenerate(GenerationMode.FINAL, true)


func cancel_generation() -> void:
	_pending_chunks.clear()
	_pending_chunk_results.clear()
	_pending_lod_save_jobs.clear()
	_pending_deferred_collision_chunks.clear()
	_shader_preview_regenerate_pending = false
	_is_generating = false
	_finish_mesh_build_thread()
	_set_generation_phase(GenerationPhase.IDLE)
	_cancel_collision_generation()
	_update_processing_state()


func clear_generated_terrain() -> void:
	cancel_generation()
	_cancel_recolor()
	final_terrain_locked = false
	_remove_legacy_v1_nodes()
	_remove_shader_preview()

	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		_generated_chunks = 0
		_total_chunks = 0
		return

	for child in chunks_root.get_children():
		chunks_root.remove_child(child)
		child.queue_free()

	_generated_chunks = 0
	_total_chunks = 0


func remove_generated_collision() -> void:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return

	for chunk in chunks_root.get_children():
		_remove_collision_from_chunk(chunk)


func generate_collision_for_existing_terrain() -> void:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null or chunks_root.get_child_count() == 0:
		push_warning("No generated terrain chunks were found for collision generation.")
		return

	_configure_noise()
	_configure_active_generation_state(GenerationMode.FINAL if final_terrain_locked else _active_generation_mode)
	if not _ensure_active_heightfield():
		return
	_cancel_collision_generation()
	_pending_collision_chunks = _get_collision_target_chunks()
	if _pending_collision_chunks.is_empty():
		push_warning("No chunks matched the current collision coverage settings.")
		return

	_collision_target_names.clear()
	for chunk in _pending_collision_chunks:
		_collision_target_names[chunk.name] = true
	_clear_collision_outside_targets()

	_generated_chunks = 0
	_total_chunks = _pending_collision_chunks.size()
	_is_generating_collision = true
	_update_processing_state()
	_build_next_collision_chunks()


func run_selected_utility() -> void:
	match selected_utility_action:
		UtilityAction.SAVE_MESH_RESOURCES:
			externalize_generated_resources()
		UtilityAction.SETUP_PREVIEW_LIGHTING:
			setup_preview_lighting()
		UtilityAction.GENERATE_COLLISION:
			generate_collision_for_existing_terrain()
		UtilityAction.REMOVE_COLLISION:
			remove_generated_collision()
		UtilityAction.REVEAL_ALL_CHUNKS:
			reveal_all_generated_chunks()


func externalize_generated_resources() -> void:
	if not _has_generated_chunks():
		push_warning("No generated terrain chunks were found to save as binary resources.")
		return

	var save_error := _save_generated_resources(true)
	if save_error != OK:
		push_warning("Could not save generated terrain resources. Error code: %d" % save_error)


func setup_preview_lighting() -> void:
	var preview_light := get_node_or_null(PREVIEW_LIGHT_NAME) as DirectionalLight3D
	if preview_light == null:
		preview_light = DirectionalLight3D.new()
		preview_light.name = PREVIEW_LIGHT_NAME
		add_child(preview_light)
		_set_scene_owner(preview_light)

	preview_light.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	preview_light.light_energy = 1.25
	preview_light.shadow_enabled = true

	var preview_environment := get_node_or_null(PREVIEW_ENVIRONMENT_NAME) as WorldEnvironment
	if preview_environment == null:
		preview_environment = WorldEnvironment.new()
		preview_environment.name = PREVIEW_ENVIRONMENT_NAME
		add_child(preview_environment)
		_set_scene_owner(preview_environment)

	var environment := preview_environment.environment
	if environment == null:
		environment = Environment.new()
		preview_environment.environment = environment
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.58, 0.64, 0.70)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.68, 0.72, 0.76)
	environment.ambient_light_energy = 0.55


func reveal_all_generated_chunks() -> void:
	if not _has_generated_chunks():
		push_warning("No generated terrain chunks were found to reveal.")
		return
	viewport_culling_enabled = false
	_apply_viewport_culling()
	_update_bake_state(GenerationMode.FINAL if final_terrain_locked else _active_generation_mode)


func _apply_bake_preset() -> void:
	if _applying_bake_preset or bake_preset == BakePreset.CUSTOM:
		return

	_applying_bake_preset = true
	match bake_preset:
		BakePreset.VISUAL_ONLY:
			collision_mode = CollisionMode.DISABLED
			collision_coverage = CollisionCoverage.ALL_CHUNKS
			collision_quality = ViewportQuality.HALF
		BakePreset.HIGH_ACCURACY:
			collision_mode = CollisionMode.FINAL_ONLY
			collision_coverage = CollisionCoverage.ALL_CHUNKS
			collision_quality = ViewportQuality.FULL
		_:
			collision_mode = CollisionMode.FINAL_ONLY
			collision_coverage = CollisionCoverage.ALL_CHUNKS
			collision_quality = ViewportQuality.HALF
	_applying_bake_preset = false
	_update_bake_state(GenerationMode.PREVIEW)


func _mark_bake_preset_custom() -> void:
	if _applying_bake_preset or bake_preset == BakePreset.CUSTOM:
		return
	var expected := _get_bake_preset_collision_settings(bake_preset)
	if expected.is_empty():
		return
	if collision_mode != int(expected["collision_mode"]) or collision_coverage != int(expected["collision_coverage"]) or collision_quality != int(expected["collision_quality"]):
		bake_preset = BakePreset.CUSTOM


func _get_bake_preset_collision_settings(preset: int) -> Dictionary:
	match preset:
		BakePreset.VISUAL_ONLY:
			return {
				"collision_mode": CollisionMode.DISABLED,
				"collision_coverage": CollisionCoverage.ALL_CHUNKS,
				"collision_quality": ViewportQuality.HALF,
			}
		BakePreset.GAME_READY:
			return {
				"collision_mode": CollisionMode.FINAL_ONLY,
				"collision_coverage": CollisionCoverage.ALL_CHUNKS,
				"collision_quality": ViewportQuality.HALF,
			}
		BakePreset.HIGH_ACCURACY:
			return {
				"collision_mode": CollisionMode.FINAL_ONLY,
				"collision_coverage": CollisionCoverage.ALL_CHUNKS,
				"collision_quality": ViewportQuality.FULL,
			}
		_:
			return {}


func _update_bake_state(mode: int) -> void:
	var visibility_summary := _get_chunk_visibility_summary()
	if mode == GenerationMode.PREVIEW:
		_last_bake_state = "Preview is for visual iteration only.%s" % visibility_summary
		return
	if collision_mode == CollisionMode.DISABLED:
		_last_bake_state = "Visual Bake complete: terrain visuals are baked, collision is disabled.%s" % visibility_summary
		return
	if collision_coverage == CollisionCoverage.ALL_CHUNKS:
		_last_bake_state = "Game Ready Bake complete: every chunk has collision.%s" % visibility_summary
		return
	_last_bake_state = "Testing Bake complete: collision is limited and is not safe for final playable terrain.%s" % visibility_summary


func _get_chunk_visibility_summary() -> String:
	if not _has_generated_chunks():
		return ""
	var total_count := _count_generated_chunks()
	var visible_count := _count_visible_generated_chunks()
	if visible_count >= total_count:
		return ""
	return " %d/%d chunks visible; viewport culling is hiding the rest." % [visible_count, total_count]


func save_preset() -> void:
	var normalized_path := _normalize_resource_path(preset_path, "terrain_preset.tres")
	var preset := TerrainPresetScript.new()
	_write_settings_to_preset(preset)
	var directory_error := DirAccess.make_dir_recursive_absolute(normalized_path.get_base_dir())
	if directory_error != OK:
		push_warning("Could not create preset directory. Error code: %d" % directory_error)
		return
	var save_error := ResourceSaver.save(preset, normalized_path)
	if save_error != OK:
		push_warning("Could not save terrain preset. Error code: %d" % save_error)


func load_preset() -> void:
	var normalized_path := _normalize_resource_path(preset_path, "terrain_preset.tres")
	var preset := ResourceLoader.load(normalized_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	if preset == null or preset.get_script() != TerrainPresetScript:
		push_warning("Could not load terrain preset at %s." % normalized_path)
		return

	_loading_preset = true
	if final_terrain_locked:
		_apply_visual_preset_settings(preset)
		push_warning("Final terrain is locked. Loaded visual/environment preset settings only; clear terrain before applying shape/source changes.")
	else:
		_apply_full_preset_settings(preset)
		_mark_heightfield_dirty()
	_loading_preset = false

	_update_visual_materials()
	if final_terrain_locked:
		return
	_queue_regenerate(GenerationMode.PREVIEW, true)


func export_heightmap() -> void:
	var normalized_path := _normalize_resource_path(export_heightmap_path, "terrain_heightmap.png")
	_configure_noise()
	_configure_active_generation_state(GenerationMode.FINAL if final_terrain_locked else _active_generation_mode)
	if not _ensure_active_heightfield():
		push_warning("No active heightfield is available to export.")
		return

	if FileAccess.file_exists(normalized_path):
		push_warning("Export Heightmap will overwrite %s." % normalized_path)
	var directory_error := DirAccess.make_dir_recursive_absolute(normalized_path.get_base_dir())
	if directory_error != OK:
		push_warning("Could not create heightmap export directory. Error code: %d" % directory_error)
		return
	var save_error := _active_heightfield.export_png(normalized_path)
	if save_error != OK:
		push_warning("Could not export heightmap. Error code: %d" % save_error)


func _queue_regenerate(requested_mode: int = -1, manual: bool = false) -> void:
	if _loading_preset:
		return
	if final_terrain_locked:
		return
	if not manual and not auto_update:
		return
	if not is_inside_tree():
		return

	var mode := requested_mode
	if mode < 0:
		mode = GenerationMode.PREVIEW
	if not manual:
		mode = GenerationMode.PREVIEW

	if _use_shader_preview(mode) and not manual:
		_queue_shader_preview_regenerate()
		return

	_queued_generation_mode = mode
	if _regeneration_queued:
		return

	_regeneration_queued = true
	call_deferred("_start_queued_generation")


func _start_queued_generation() -> void:
	_regeneration_queued = false
	_start_generation(_queued_generation_mode)


func _queue_shader_preview_regenerate() -> void:
	_regeneration_queued = false
	_shader_preview_regenerate_pending = true
	_shader_preview_regenerate_delay = 0.18
	_update_processing_state()


func _process_shader_preview_regenerate(delta: float) -> void:
	_shader_preview_regenerate_delay -= delta
	if _shader_preview_regenerate_delay > 0.0:
		return
	_shader_preview_regenerate_pending = false
	_start_generation(GenerationMode.PREVIEW)


func _start_generation(mode: int) -> void:
	_reset_generation_timings(mode)
	cancel_generation()
	_cancel_recolor()
	_configure_noise()
	_remove_legacy_v1_nodes()
	_remove_shader_preview()
	_update_visual_materials()

	var chunks_root := _get_or_create_chunks_root()
	_clear_chunk_nodes(chunks_root)

	_configure_active_generation_state(mode)
	if not _ensure_active_heightfield():
		_update_processing_state()
		return

	if _use_shader_preview(mode):
		_generate_shader_preview()
		_generated_chunks = 1
		_total_chunks = 1
		_is_generating = false
		_set_generation_phase(GenerationPhase.IDLE)
		_update_bake_state(mode)
		_update_processing_state()
		return

	_active_build_collision = _should_build_collision(mode)
	_active_display_stride = _get_viewport_display_stride()

	_pending_chunks.clear()
	_pending_chunk_results.clear()
	_pending_lod_save_jobs.clear()
	_pending_deferred_collision_chunks.clear()
	for chunk_z in chunks_per_side:
		for chunk_x in chunks_per_side:
			_pending_chunks.append(Vector2i(chunk_x, chunk_z))

	_generated_chunks = 0
	_total_chunks = _pending_chunks.size()
	_is_generating = _total_chunks > 0
	_set_generation_phase(GenerationPhase.BUILDING_MESH_ARRAYS if _is_generating else GenerationPhase.IDLE)
	_update_bake_state(mode)

	if _is_generating:
		_update_processing_state()
		_build_next_chunks()
	else:
		_update_processing_state()


func _build_next_chunks() -> void:
	_collect_finished_mesh_build_jobs()
	_start_mesh_build_jobs()

	var budget_start := Time.get_ticks_usec()
	_finalize_pending_threaded_chunks(budget_start)

	if _has_active_mesh_build_work():
		_update_generation_phase_for_mesh_work()
		return

	if _active_generation_mode == GenerationMode.FINAL and save_final_meshes_as_resources and not _pending_lod_save_jobs.is_empty():
		if _active_generation_phase != GenerationPhase.SAVING_LODS:
			_generated_chunks = 0
			_total_chunks = _pending_lod_save_jobs.size()
		_set_generation_phase(GenerationPhase.SAVING_LODS)
		_process_pending_lod_saves(budget_start)
		return

	if _active_build_collision and not _pending_deferred_collision_chunks.is_empty():
		if _active_generation_phase != GenerationPhase.GENERATING_COLLISION:
			_generated_chunks = 0
			_total_chunks = _pending_deferred_collision_chunks.size()
		_set_generation_phase(GenerationPhase.GENERATING_COLLISION)
		_process_pending_deferred_collision(budget_start)
		return

	_finish_generation_if_complete()


func _collect_finished_mesh_build_jobs() -> void:
	for index in range(_mesh_build_jobs.size() - 1, -1, -1):
		var job: Dictionary = _mesh_build_jobs[index]
		var thread := job["thread"] as Thread
		if thread.is_alive():
			continue
		var result = thread.wait_to_finish()
		_mesh_build_jobs.remove_at(index)
		if result is Dictionary:
			result["timing_start_usec"] = int(job.get("timing_start_usec", 0))
			_pending_chunk_results.append(result)


func _start_mesh_build_jobs() -> void:
	var settings := _get_mesh_builder_settings()
	var max_workers := clampi(generation_worker_count, 1, 8)
	while not _pending_chunks.is_empty() and _mesh_build_jobs.size() < max_workers:
		var chunk_coordinates: Vector2i = _pending_chunks.pop_front()
		var build_lods := _active_generation_mode == GenerationMode.FINAL and save_final_meshes_as_resources
		var thread := Thread.new()
		var timing_start := _timing_begin()
		var start_error := thread.start(Callable(self, "_build_chunk_data_threaded").bind(chunk_coordinates, _active_display_stride, build_lods, settings))
		if start_error == OK:
			_mesh_build_jobs.append({
				"thread": thread,
				"timing_start_usec": timing_start,
			})
			continue

		var fallback_result := _build_chunk_data_threaded(chunk_coordinates, _active_display_stride, build_lods, settings)
		fallback_result["timing_start_usec"] = timing_start
		_pending_chunk_results.append(fallback_result)


func _has_active_mesh_build_work() -> bool:
	return not _pending_chunks.is_empty() or not _mesh_build_jobs.is_empty() or not _pending_chunk_results.is_empty()


func _update_generation_phase_for_mesh_work() -> void:
	if _pending_chunk_results.is_empty() and (not _pending_chunks.is_empty() or not _mesh_build_jobs.is_empty()):
		_set_generation_phase(GenerationPhase.BUILDING_MESH_ARRAYS)
	else:
		_set_generation_phase(GenerationPhase.FINALIZING_CHUNKS)


func _build_chunk_data_threaded(chunk_coordinates: Vector2i, display_stride: int, build_lods: bool, settings: Dictionary) -> Dictionary:
	var builder := TerrainMeshBuilderScript.new()
	builder.configure(settings)
	var display_arrays := builder.build_chunk_mesh_arrays(chunk_coordinates.x, chunk_coordinates.y, display_stride)
	var lod_arrays := []

	if build_lods:
		for lod_index in LOD_STRIDES.size():
			var stride: int = LOD_STRIDES[lod_index]
			if lod_index == 0 and display_stride == 1:
				lod_arrays.append(display_arrays)
			else:
				lod_arrays.append(builder.build_chunk_mesh_arrays(chunk_coordinates.x, chunk_coordinates.y, stride, stride > 1))

	return {
		"chunk_coordinates": chunk_coordinates,
		"display_arrays": display_arrays,
		"lod_arrays": lod_arrays,
	}


func _finish_mesh_build_thread():
	var results := []
	for job in _mesh_build_jobs:
		var thread := job["thread"] as Thread
		var result = thread.wait_to_finish()
		if result is Dictionary:
			result["timing_start_usec"] = int(job.get("timing_start_usec", 0))
			results.append(result)
	_mesh_build_jobs.clear()
	return results


func _finalize_pending_threaded_chunks(budget_start: int) -> void:
	var finalized_count := 0
	while not _pending_chunk_results.is_empty() and not _main_thread_budget_exhausted(budget_start, finalized_count):
		_finalize_threaded_chunk(_pending_chunk_results.pop_front())
		finalized_count += 1


func _finalize_threaded_chunk(result: Dictionary) -> void:
	var chunks_root := _get_or_create_chunks_root()
	var material := _get_material_for_encoding(_get_new_mesh_material_encoding())
	var resource_directory := _get_generated_resource_directory() if _active_generation_mode == GenerationMode.FINAL and save_final_meshes_as_resources else ""

	var chunk_coordinates: Vector2i = result["chunk_coordinates"] as Vector2i
	var chunk_mesh_instance := _create_chunk_mesh_instance(chunk_coordinates.x, chunk_coordinates.y, material)
	chunk_mesh_instance.mesh = _mesh_builder.create_mesh_from_arrays(result["display_arrays"] as Array)
	_timing_add("chunk_mesh", int(result.get("timing_start_usec", 0)))
	chunks_root.add_child(chunk_mesh_instance)
	if _active_generation_mode == GenerationMode.FINAL:
		_set_scene_owner(chunk_mesh_instance)

	if _active_generation_mode == GenerationMode.FINAL and save_final_meshes_as_resources:
		_pending_lod_save_jobs.append({
			"chunk": chunk_mesh_instance,
			"chunk_x": chunk_coordinates.x,
			"chunk_z": chunk_coordinates.y,
			"resource_directory": resource_directory,
			"lod_arrays": result["lod_arrays"] as Array,
		})

	if _active_build_collision and _chunk_is_in_collision_coverage(chunk_mesh_instance):
		if _should_defer_collision_for_active_generation():
			_pending_deferred_collision_chunks.append(chunk_mesh_instance)
		else:
			var collision_timing_start := _timing_begin()
			_add_chunk_collision(chunk_mesh_instance, chunk_coordinates.x, chunk_coordinates.y)
			_timing_add("collision", collision_timing_start)

	_generated_chunks += 1
	_apply_viewport_culling()


func _process_pending_lod_saves(budget_start: int) -> void:
	var processed_count := 0

	while not _pending_lod_save_jobs.is_empty() and not _main_thread_budget_exhausted(budget_start, processed_count):
		var job: Dictionary = _pending_lod_save_jobs.pop_front()
		var lod_timing_start := _timing_begin()
		var chunk := job["chunk"] as MeshInstance3D
		var save_error := _save_chunk_lod_resources_from_arrays(
			chunk,
			int(job["chunk_x"]),
			int(job["chunk_z"]),
			str(job["resource_directory"]),
			job["lod_arrays"] as Array
		)
		_timing_add("lod_save", lod_timing_start)
		if save_error != OK:
			push_warning("Could not save chunk LOD resources. Error code: %d" % save_error)
		elif chunk.visible:
			_apply_lod_to_chunk(chunk)
		_generated_chunks += 1
		processed_count += 1


func _process_pending_deferred_collision(budget_start: int) -> void:
	var processed_count := 0

	while not _pending_deferred_collision_chunks.is_empty() and not _main_thread_budget_exhausted(budget_start, processed_count):
		var chunk: MeshInstance3D = _pending_deferred_collision_chunks.pop_front()
		var collision_timing_start := _timing_begin()
		_add_collision_from_existing_mesh(chunk)
		_timing_add("collision", collision_timing_start)
		_generated_chunks += 1
		processed_count += 1


func _should_defer_collision_for_active_generation() -> bool:
	return defer_final_collision and _active_generation_mode == GenerationMode.FINAL


func _finish_generation_if_complete() -> void:
	if _has_active_mesh_build_work() or not _pending_lod_save_jobs.is_empty() or not _pending_deferred_collision_chunks.is_empty():
		return

	_set_generation_phase(GenerationPhase.SAVING_RESOURCES)
	_is_generating = false
	if _active_generation_mode == GenerationMode.FINAL:
		if save_final_meshes_as_resources:
			var save_error := _save_generated_resources(false)
			if save_error != OK:
				push_warning("Could not save generated terrain resources. Error code: %d" % save_error)
		final_terrain_locked = true
		_assign_materials_to_existing_chunks()
		_make_generated_nodes_scene_owned()
		_update_bake_state(GenerationMode.FINAL)
		print(_last_bake_state)
	_update_processing_state()
	if _active_generation_mode == GenerationMode.FINAL:
		_print_generation_timings()
	_set_generation_phase(GenerationPhase.IDLE)


func _build_chunk_mesh(chunk_x: int, chunk_z: int, display_stride: int, add_skirts: bool = false) -> ArrayMesh:
	return _mesh_builder.build_chunk_mesh(chunk_x, chunk_z, display_stride, add_skirts)


func _configure_noise() -> void:
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = noise_frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = octaves
	_noise.fractal_lacunarity = lacunarity
	_noise.fractal_gain = gain


func _mark_heightfield_dirty() -> void:
	_heightfield_dirty = true


func _target_heightfield_resolution() -> int:
	if _active_generation_mode == GenerationMode.FINAL or source_mode == SourceMode.HEIGHTMAP:
		return chunk_resolution * chunks_per_side
	return _active_total_resolution


func _ensure_active_heightfield() -> bool:
	var target_resolution := _target_heightfield_resolution()
	if _active_heightfield.is_valid() and not _heightfield_dirty and _heightfield_resolution == target_resolution:
		return true
	var timing_start := _timing_begin()
	if not _build_source_heightfield(target_resolution):
		_timing_add("heightfield", timing_start)
		return false
	_active_heightfield.copy_from(_source_heightfield)
	_heightfield_dirty = false
	_heightfield_resolution = target_resolution
	_timing_add("heightfield", timing_start)
	return true


func _build_source_heightfield(total_resolution: int) -> bool:
	total_resolution = maxi(1, total_resolution)
	if source_mode == SourceMode.HEIGHTMAP:
		var image := _load_heightmap_image()
		if image == null:
			_source_heightfield.create_from_noise(total_resolution, terrain_size, height_scale, _noise, terrain_scale)
			push_warning("Heightmap could not be loaded. Falling back to procedural noise.")
			return true
		if image.get_width() != total_resolution + 1 or image.get_height() != total_resolution + 1:
			push_warning("Heightmap dimensions %dx%d are being resampled to %dx%d." % [image.get_width(), image.get_height(), total_resolution + 1, total_resolution + 1])
		_source_heightfield.create_from_image(total_resolution, terrain_size, height_scale, image, heightmap_flip_x, heightmap_flip_z, heightmap_invert)
		return true

	_source_heightfield.create_from_noise(total_resolution, terrain_size, height_scale, _noise, terrain_scale)
	return true


func _load_heightmap_image() -> Image:
	var normalized_path := heightmap_path.strip_edges()
	if normalized_path.is_empty():
		return null
	var image := Image.load_from_file(normalized_path)
	if image == null or image.is_empty():
		return null
	return image


func _new_meshes_use_v5_masks() -> bool:
	return procedural_material_enabled


func _get_new_mesh_material_encoding() -> String:
	if _new_meshes_use_v5_masks():
		return TERRAIN_ENCODING_V5_MASKS
	return TERRAIN_ENCODING_LEGACY_COLORS


func _queue_recolor_existing_chunks() -> void:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return

	_pending_recolor_chunks.clear()
	for child in chunks_root.get_children():
		var chunk := child as MeshInstance3D
		if chunk != null:
			_pending_recolor_chunks.append(chunk)

	_is_recoloring = not _pending_recolor_chunks.is_empty()
	_update_processing_state()


func _queue_visual_update() -> void:
	_update_visual_materials()
	_update_shader_preview_material()
	_maybe_externalize_final_visual_resources()
	if _all_existing_chunks_use_v5_masks():
		return
	_queue_recolor_existing_chunks()


func _all_existing_chunks_use_v5_masks() -> bool:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return false

	var found_chunk := false
	for child in chunks_root.get_children():
		var chunk := child as MeshInstance3D
		if chunk == null:
			continue
		found_chunk = true
		if not _chunk_uses_v5_masks(chunk):
			return false

	return found_chunk


func _recolor_next_chunks() -> void:
	var recolor_count := mini(_get_chunks_per_frame(), _pending_recolor_chunks.size())

	for _recolor_index in recolor_count:
		var chunk: MeshInstance3D = _pending_recolor_chunks.pop_front()
		_recolor_chunk(chunk)

	if _pending_recolor_chunks.is_empty():
		_is_recoloring = false
		_update_processing_state()


func _recolor_chunk(chunk: MeshInstance3D) -> void:
	if chunk == null or chunk.mesh == null or chunk.mesh.get_surface_count() == 0:
		return
	if _chunk_uses_v5_masks(chunk):
		chunk.material_override = _get_material_for_chunk(chunk)
		return

	var mesh_resource_path := chunk.mesh.resource_path
	var arrays: Array = chunk.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors := PackedColorArray()
	colors.resize(vertices.size())

	_configure_mesh_builder()
	for vertex_index in vertices.size():
		colors[vertex_index] = _mesh_builder.color_for_terrain(vertices[vertex_index].y, normals[vertex_index])

	arrays[Mesh.ARRAY_COLOR] = colors

	var recolored_mesh := ArrayMesh.new()
	recolored_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if final_terrain_locked and save_final_meshes_as_resources:
		if mesh_resource_path.is_empty():
			var resource_directory := _get_generated_resource_directory()
			DirAccess.make_dir_recursive_absolute(resource_directory)
			mesh_resource_path = "%s/%s_mesh.res" % [resource_directory, chunk.name]

		var save_error := ResourceSaver.save(recolored_mesh, mesh_resource_path)
		if save_error == OK:
			var saved_mesh := ResourceLoader.load(mesh_resource_path, "ArrayMesh", ResourceLoader.CACHE_MODE_REPLACE) as ArrayMesh
			if saved_mesh != null:
				recolored_mesh = saved_mesh
		else:
			push_warning("Could not save recolored terrain mesh. Error code: %d" % save_error)

	chunk.mesh = recolored_mesh


func _cancel_recolor() -> void:
	_pending_recolor_chunks.clear()
	_is_recoloring = false
	_update_processing_state()


func _update_processing_state() -> void:
	set_process(_is_generating or _is_recoloring or _is_generating_collision or _shader_preview_regenerate_pending or _should_process_automatic_lod_focus() or _should_process_material_focus())


func _get_chunk_resolution_for_mode(mode: int) -> int:
	if mode == GenerationMode.FINAL:
		return chunk_resolution
	if not auto_performance_settings:
		return mini(preview_chunk_resolution, chunk_resolution)

	var final_total_resolution := chunk_resolution * chunks_per_side
	var target_preview_total_resolution := mini(final_total_resolution, 512)
	var automatic_preview_resolution := ceili(float(target_preview_total_resolution) / float(chunks_per_side))
	return clampi(automatic_preview_resolution, 16, mini(128, chunk_resolution))


func _configure_active_generation_state(mode: int) -> void:
	_active_generation_mode = mode
	_active_chunk_resolution = _get_chunk_resolution_for_mode(mode)
	_active_total_resolution = _active_chunk_resolution * chunks_per_side
	_active_step = terrain_size / float(_active_total_resolution)
	_active_half_size = terrain_size * 0.5
	_sync_auto_visible_radius(false)
	_configure_mesh_builder()


func _configure_mesh_builder() -> void:
	_mesh_builder.configure(_get_mesh_builder_settings())


func _get_mesh_builder_settings() -> Dictionary:
	return {
		"noise": _noise,
		"heightfield": _active_heightfield,
		"active_chunk_resolution": _active_chunk_resolution,
		"active_total_resolution": _active_total_resolution,
		"active_step": _active_step,
		"active_half_size": _active_half_size,
		"height_scale": height_scale,
		"terrain_scale": terrain_scale,
		"snow_height": snow_height,
		"snow_enabled": snow_enabled,
		"rock_slope_threshold": rock_slope_threshold,
		"lowland_color": lowland_color,
		"grass_color": grass_color,
		"rock_color": rock_color,
		"snow_color": snow_color,
		"use_v5_masks": _new_meshes_use_v5_masks(),
	}


func _get_chunks_per_frame() -> int:
	if not auto_performance_settings:
		return chunks_per_frame
	if _active_generation_mode == GenerationMode.FINAL:
		return 1
	if _active_chunk_resolution <= 32:
		return 8
	if _active_chunk_resolution <= 64:
		return 4
	if _active_chunk_resolution <= 128:
		return 2
	return 1


func _sync_auto_visible_radius(apply_culling: bool = true) -> void:
	if not _visible_radius_auto_managed:
		return

	var target_radius := terrain_size * 0.75
	if is_equal_approx(visible_radius, target_radius):
		return

	_setting_auto_visible_radius = true
	visible_radius = target_radius
	_setting_auto_visible_radius = false
	if apply_culling:
		_apply_viewport_culling()


func _apply_terrain_performance_preset(apply_updates: bool = true) -> void:
	match terrain_performance_preset:
		TerrainPerformancePreset.QUALITY:
			lod_profile = LodProfile.QUALITY
			high_view_lod_max_bias = 1
		TerrainPerformancePreset.PERFORMANCE:
			lod_profile = LodProfile.PERFORMANCE
			high_view_lod_max_bias = 3
			if texture_bombing_samples > TextureBombingSamples.LIGHT:
				texture_bombing_samples = TextureBombingSamples.LIGHT
		_:
			lod_profile = LodProfile.BALANCED
			high_view_lod_max_bias = 2
			if texture_bombing_samples > TextureBombingSamples.LIGHT:
				texture_bombing_samples = TextureBombingSamples.LIGHT

	high_view_lod_start_height = maxf(high_view_lod_start_height, terrain_size * 0.14)
	high_view_lod_full_height = maxf(high_view_lod_full_height, terrain_size * 0.38)

	if not apply_updates:
		return
	_apply_terrain_shadow_policy()
	_update_visual_materials()
	_apply_viewport_culling()


func _terrain_should_cast_shadows() -> bool:
	match terrain_shadow_casting:
		TerrainShadowCasting.ON:
			return true
		TerrainShadowCasting.OFF:
			return false
		_:
			return terrain_performance_preset == TerrainPerformancePreset.QUALITY


func _apply_terrain_shadow_policy() -> void:
	var shadow_setting := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _terrain_should_cast_shadows() else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root != null:
		for child in chunks_root.get_children():
			var chunk := child as MeshInstance3D
			if chunk != null:
				chunk.cast_shadow = shadow_setting
	var preview := get_node_or_null(SHADER_PREVIEW_NAME) as MeshInstance3D
	if preview != null:
		preview.cast_shadow = shadow_setting


func _should_build_collision(mode: int) -> bool:
	if collision_mode == CollisionMode.DISABLED:
		return false
	if collision_mode == CollisionMode.ALL_BUILDS:
		return true
	return mode == GenerationMode.FINAL


func _save_generated_resources(save_lods: bool = true) -> int:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return OK

	_configure_noise()
	_configure_active_generation_state(GenerationMode.FINAL)
	if not _ensure_active_heightfield():
		return ERR_UNCONFIGURED
	var resource_directory := _get_generated_resource_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(resource_directory)
	if directory_error != OK:
		return directory_error

	var material_error := _save_visual_resources(resource_directory)
	if material_error != OK:
		return material_error

	for child in chunks_root.get_children():
		var chunk := child as MeshInstance3D
		if chunk == null:
			continue

		chunk.material_override = _get_material_for_chunk(chunk)
		if save_lods:
			var coordinates := _get_chunk_coordinates(chunk)
			var lod_error := _save_chunk_lod_resources(chunk, coordinates.x, coordinates.y, resource_directory)
			if lod_error != OK:
				return lod_error

		var collision_shape := chunk.get_node_or_null("CollisionBody/CollisionShape") as CollisionShape3D
		if collision_shape != null and collision_shape.shape != null:
			var shape_path := "%s/%s_collision_shape.res" % [resource_directory, chunk.name]
			var shape_error := ResourceSaver.save(collision_shape.shape, shape_path)
			if shape_error != OK:
				return shape_error

			var saved_shape := ResourceLoader.load(shape_path, "Shape3D", ResourceLoader.CACHE_MODE_REPLACE) as Shape3D
			if saved_shape != null:
				_configure_terrain_collision_shape(saved_shape)
				collision_shape.shape = saved_shape

	_apply_collision_visual_visibility()
	return OK


func _save_chunk_lod_resources(chunk: MeshInstance3D, chunk_x: int, chunk_z: int, resource_directory: String = "", existing_lod0_mesh: ArrayMesh = null) -> int:
	if resource_directory.is_empty():
		resource_directory = _get_generated_resource_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(resource_directory)
	if directory_error != OK:
		return directory_error

	chunk.set_meta("terrain_material_encoding", _get_new_mesh_material_encoding())
	for lod_index in LOD_STRIDES.size():
		var stride: int = LOD_STRIDES[lod_index]
		var lod_mesh := existing_lod0_mesh if lod_index == 0 and existing_lod0_mesh != null and _active_display_stride == 1 else _build_chunk_mesh(chunk_x, chunk_z, stride, stride > 1)
		lod_mesh.set_meta("terrain_lod_edge_version", TERRAIN_LOD_EDGE_VERSION)
		var mesh_path := _get_lod_mesh_path(chunk.name, lod_index, resource_directory)
		var mesh_error := ResourceSaver.save(lod_mesh, mesh_path)
		if mesh_error != OK:
			return mesh_error

		chunk.set_meta(_get_lod_meta_key(lod_index), mesh_path)
		if lod_index == 0:
			var saved_mesh := ResourceLoader.load(mesh_path, "ArrayMesh", ResourceLoader.CACHE_MODE_REPLACE) as ArrayMesh
			if saved_mesh != null:
				chunk.mesh = saved_mesh

	chunk.set_meta("terrain_chunk_x", chunk_x)
	chunk.set_meta("terrain_chunk_z", chunk_z)
	chunk.set_meta("terrain_current_lod", 0)
	return OK


func _save_chunk_lod_resources_from_arrays(chunk: MeshInstance3D, chunk_x: int, chunk_z: int, resource_directory: String, lod_arrays: Array) -> int:
	if lod_arrays.is_empty():
		return _save_chunk_lod_resources(chunk, chunk_x, chunk_z, resource_directory, chunk.mesh as ArrayMesh)
	if resource_directory.is_empty():
		resource_directory = _get_generated_resource_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(resource_directory)
	if directory_error != OK:
		return directory_error

	chunk.set_meta("terrain_material_encoding", _get_new_mesh_material_encoding())
	for lod_index in mini(LOD_STRIDES.size(), lod_arrays.size()):
		var lod_mesh := _mesh_builder.create_mesh_from_arrays(lod_arrays[lod_index] as Array)
		lod_mesh.set_meta("terrain_lod_edge_version", TERRAIN_LOD_EDGE_VERSION)
		var mesh_path := _get_lod_mesh_path(chunk.name, lod_index, resource_directory)
		var mesh_error := ResourceSaver.save(lod_mesh, mesh_path)
		if mesh_error != OK:
			return mesh_error

		chunk.set_meta(_get_lod_meta_key(lod_index), mesh_path)
		if lod_index == 0:
			var saved_mesh := ResourceLoader.load(mesh_path, "ArrayMesh", ResourceLoader.CACHE_MODE_REPLACE) as ArrayMesh
			if saved_mesh != null:
				chunk.mesh = saved_mesh

	chunk.set_meta("terrain_chunk_x", chunk_x)
	chunk.set_meta("terrain_chunk_z", chunk_z)
	chunk.set_meta("terrain_current_lod", 0)
	return OK


func _get_lod_mesh_path(chunk_name: String, lod_index: int, resource_directory: String = "") -> String:
	if resource_directory.is_empty():
		resource_directory = _get_generated_resource_directory()
	if lod_index == 0:
		return "%s/%s_mesh.res" % [resource_directory, chunk_name]
	return "%s/%s_lod%d_mesh.res" % [resource_directory, chunk_name, lod_index]


func _get_lod_meta_key(lod_index: int) -> String:
	return "terrain_lod_%d_path" % lod_index


func _get_generated_resource_directory() -> String:
	var resource_directory := generated_resource_directory.strip_edges()
	if resource_directory.is_empty():
		resource_directory = DEFAULT_GENERATED_RESOURCE_DIR
	if not resource_directory.begins_with("res://"):
		resource_directory = "res://%s" % resource_directory.trim_prefix("/")
	while resource_directory.ends_with("/") and resource_directory.length() > "res://".length():
		resource_directory = resource_directory.trim_suffix("/")
	return resource_directory


func _normalize_resource_path(path: String, fallback_file_name: String) -> String:
	var normalized_path := path.strip_edges()
	if normalized_path.is_empty():
		normalized_path = "res://%s" % fallback_file_name
	if normalized_path.begins_with("res://") or normalized_path.begins_with("user://") or normalized_path.is_absolute_path():
		return normalized_path
	if not normalized_path.begins_with("res://") and not normalized_path.begins_with("user://"):
		normalized_path = "res://%s" % normalized_path.trim_prefix("/")
	return normalized_path


func _write_settings_to_preset(preset: Resource) -> void:
	preset.terrain_size = terrain_size
	preset.chunk_resolution = chunk_resolution
	preset.chunks_per_side = chunks_per_side
	preset.height_scale = height_scale
	preset.source_mode = source_mode
	preset.heightmap_path = heightmap_path
	preset.heightmap_flip_x = heightmap_flip_x
	preset.heightmap_flip_z = heightmap_flip_z
	preset.heightmap_invert = heightmap_invert
	preset.terrain_seed = terrain_seed
	preset.noise_frequency = noise_frequency
	preset.terrain_scale = terrain_scale
	preset.octaves = octaves
	preset.lacunarity = lacunarity
	preset.gain = gain
	preset.snow_enabled = snow_enabled
	preset.snow_height = snow_height
	preset.rock_slope_threshold = rock_slope_threshold
	preset.lowland_color = lowland_color
	preset.grass_color = grass_color
	preset.rock_color = rock_color
	preset.snow_color = snow_color
	preset.procedural_material_enabled = procedural_material_enabled
	preset.material_mode = material_mode
	preset.lowland_layer_enabled = lowland_layer_enabled
	preset.ground_layer_enabled = ground_layer_enabled
	preset.upper_layer_enabled = upper_layer_enabled
	preset.rocky_layer_enabled = rocky_layer_enabled
	preset.cliff_layer_enabled = cliff_layer_enabled
	preset.snow_layer_enabled = snow_layer_enabled
	preset.lowland_material_folder = lowland_material_folder
	preset.ground_material_folder = ground_material_folder
	preset.upper_material_folder = upper_material_folder
	preset.rocky_material_folder = rocky_material_folder
	preset.cliff_material_folder = cliff_material_folder
	preset.snow_material_folder = snow_material_folder
	preset.texture_tile_scale = texture_tile_scale
	preset.macro_texture_tiling_enabled = macro_texture_tiling_enabled
	preset.close_texture_tile_scale = close_texture_tile_scale
	preset.medium_texture_tile_scale = medium_texture_tile_scale
	preset.far_texture_tile_scale = far_texture_tile_scale
	preset.close_texture_radius = close_texture_radius
	preset.medium_texture_radius = medium_texture_radius
	preset.far_texture_radius = far_texture_radius
	preset.layer_blend_softness = layer_blend_softness
	preset.texture_normal_strength = texture_normal_strength
	preset.roughness_multiplier = roughness_multiplier
	preset.height_blend_strength = height_blend_strength
	preset.texture_bombing_enabled = texture_bombing_enabled
	preset.texture_bombing_strength = texture_bombing_strength
	preset.texture_bombing_cell_scale = texture_bombing_cell_scale
	preset.texture_bombing_samples = texture_bombing_samples
	preset.terrain_performance_preset = terrain_performance_preset
	preset.high_view_lod_bias_enabled = high_view_lod_bias_enabled
	preset.high_view_lod_start_height = high_view_lod_start_height
	preset.high_view_lod_full_height = high_view_lod_full_height
	preset.high_view_lod_max_bias = high_view_lod_max_bias
	preset.terrain_shadow_casting = terrain_shadow_casting
	preset.far_material_cache_enabled = far_material_cache_enabled
	preset.far_material_cache_resolution = far_material_cache_resolution
	preset.macro_variation_strength = macro_variation_strength
	preset.macro_variation_scale = macro_variation_scale
	preset.detail_noise_strength = detail_noise_strength
	preset.detail_noise_scale = detail_noise_scale
	preset.rock_detail_strength = rock_detail_strength
	preset.snow_detail_strength = snow_detail_strength
	preset.material_brightness = material_brightness
	preset.material_contrast = material_contrast
	preset.bake_preset = bake_preset
	preset.viewport_quality = viewport_quality
	preset.viewport_lod_enabled = viewport_lod_enabled
	preset.lod_profile = lod_profile
	preset.automatic_lod_focus = automatic_lod_focus
	preset.visible_radius = visible_radius
	preset.viewport_culling_enabled = viewport_culling_enabled
	preset.collision_mode = collision_mode
	preset.collision_coverage = collision_coverage
	preset.collision_quality = collision_quality
	preset.collision_radius = collision_radius
	preset.collision_chunks_per_frame = collision_chunks_per_frame


func _apply_full_preset_settings(preset: Resource) -> void:
	terrain_size = preset.terrain_size
	chunk_resolution = preset.chunk_resolution
	chunks_per_side = preset.chunks_per_side
	height_scale = preset.height_scale
	source_mode = preset.source_mode
	heightmap_path = preset.heightmap_path
	heightmap_flip_x = preset.heightmap_flip_x
	heightmap_flip_z = preset.heightmap_flip_z
	heightmap_invert = preset.heightmap_invert
	var loaded_terrain_seed = preset.get("terrain_seed")
	if loaded_terrain_seed != null:
		terrain_seed = int(loaded_terrain_seed)
	else:
		var legacy_seed = preset.get("seed")
		if legacy_seed != null:
			terrain_seed = int(legacy_seed)
	noise_frequency = preset.noise_frequency
	var loaded_terrain_scale = preset.get("terrain_scale")
	if loaded_terrain_scale != null:
		terrain_scale = float(loaded_terrain_scale)
	octaves = preset.octaves
	lacunarity = preset.lacunarity
	gain = preset.gain
	_apply_visual_preset_settings(preset)
	var loaded_bake_preset = preset.get("bake_preset")
	if loaded_bake_preset != null:
		bake_preset = int(loaded_bake_preset)
	viewport_quality = preset.viewport_quality
	viewport_lod_enabled = preset.viewport_lod_enabled
	lod_profile = preset.lod_profile
	automatic_lod_focus = preset.automatic_lod_focus
	visible_radius = preset.visible_radius
	viewport_culling_enabled = preset.viewport_culling_enabled
	collision_mode = preset.collision_mode
	collision_coverage = preset.collision_coverage
	collision_quality = preset.collision_quality
	collision_radius = preset.collision_radius
	collision_chunks_per_frame = preset.collision_chunks_per_frame


func _apply_visual_preset_settings(preset: Resource) -> void:
	var loaded_snow_enabled = preset.get("snow_enabled")
	if loaded_snow_enabled != null:
		snow_enabled = bool(loaded_snow_enabled)
	snow_height = preset.snow_height
	rock_slope_threshold = preset.rock_slope_threshold
	lowland_color = preset.lowland_color
	grass_color = preset.grass_color
	rock_color = preset.rock_color
	snow_color = preset.snow_color
	procedural_material_enabled = preset.procedural_material_enabled
	var loaded_material_mode = preset.get("material_mode")
	if loaded_material_mode != null:
		material_mode = int(loaded_material_mode)
	var loaded_lowland_layer_enabled = preset.get("lowland_layer_enabled")
	if loaded_lowland_layer_enabled != null:
		lowland_layer_enabled = bool(loaded_lowland_layer_enabled)
	var loaded_ground_layer_enabled = preset.get("ground_layer_enabled")
	if loaded_ground_layer_enabled != null:
		ground_layer_enabled = bool(loaded_ground_layer_enabled)
	var loaded_upper_layer_enabled = preset.get("upper_layer_enabled")
	if loaded_upper_layer_enabled != null:
		upper_layer_enabled = bool(loaded_upper_layer_enabled)
	var loaded_rocky_layer_enabled = preset.get("rocky_layer_enabled")
	if loaded_rocky_layer_enabled != null:
		rocky_layer_enabled = bool(loaded_rocky_layer_enabled)
	var loaded_cliff_layer_enabled = preset.get("cliff_layer_enabled")
	if loaded_cliff_layer_enabled != null:
		cliff_layer_enabled = bool(loaded_cliff_layer_enabled)
	var loaded_snow_layer_enabled = preset.get("snow_layer_enabled")
	if loaded_snow_layer_enabled != null:
		snow_layer_enabled = bool(loaded_snow_layer_enabled)
	var loaded_lowland_material_folder = preset.get("lowland_material_folder")
	if loaded_lowland_material_folder != null:
		lowland_material_folder = str(loaded_lowland_material_folder)
	var loaded_ground_material_folder = preset.get("ground_material_folder")
	if loaded_ground_material_folder != null:
		ground_material_folder = str(loaded_ground_material_folder)
	var loaded_upper_material_folder = preset.get("upper_material_folder")
	if loaded_upper_material_folder != null:
		upper_material_folder = str(loaded_upper_material_folder)
	var loaded_rocky_material_folder = preset.get("rocky_material_folder")
	if loaded_rocky_material_folder != null:
		rocky_material_folder = str(loaded_rocky_material_folder)
	var loaded_cliff_material_folder = preset.get("cliff_material_folder")
	if loaded_cliff_material_folder != null:
		cliff_material_folder = str(loaded_cliff_material_folder)
	var loaded_snow_material_folder = preset.get("snow_material_folder")
	if loaded_snow_material_folder != null:
		snow_material_folder = str(loaded_snow_material_folder)
	var loaded_texture_tile_scale = preset.get("texture_tile_scale")
	if loaded_texture_tile_scale != null:
		texture_tile_scale = float(loaded_texture_tile_scale)
	var loaded_macro_texture_tiling_enabled = preset.get("macro_texture_tiling_enabled")
	if loaded_macro_texture_tiling_enabled != null:
		macro_texture_tiling_enabled = bool(loaded_macro_texture_tiling_enabled)
	var loaded_close_texture_tile_scale = preset.get("close_texture_tile_scale")
	if loaded_close_texture_tile_scale != null:
		close_texture_tile_scale = float(loaded_close_texture_tile_scale)
	var loaded_medium_texture_tile_scale = preset.get("medium_texture_tile_scale")
	if loaded_medium_texture_tile_scale != null:
		medium_texture_tile_scale = float(loaded_medium_texture_tile_scale)
	var loaded_far_texture_tile_scale = preset.get("far_texture_tile_scale")
	if loaded_far_texture_tile_scale != null:
		far_texture_tile_scale = float(loaded_far_texture_tile_scale)
	var loaded_close_texture_radius = preset.get("close_texture_radius")
	if loaded_close_texture_radius != null:
		close_texture_radius = float(loaded_close_texture_radius)
	var loaded_medium_texture_radius = preset.get("medium_texture_radius")
	if loaded_medium_texture_radius != null:
		medium_texture_radius = float(loaded_medium_texture_radius)
	var loaded_far_texture_radius = preset.get("far_texture_radius")
	if loaded_far_texture_radius != null:
		far_texture_radius = float(loaded_far_texture_radius)
	var loaded_layer_blend_softness = preset.get("layer_blend_softness")
	if loaded_layer_blend_softness != null:
		layer_blend_softness = float(loaded_layer_blend_softness)
	var loaded_texture_normal_strength = preset.get("texture_normal_strength")
	if loaded_texture_normal_strength != null:
		texture_normal_strength = float(loaded_texture_normal_strength)
	var loaded_roughness_multiplier = preset.get("roughness_multiplier")
	if loaded_roughness_multiplier != null:
		roughness_multiplier = float(loaded_roughness_multiplier)
	var loaded_height_blend_strength = preset.get("height_blend_strength")
	if loaded_height_blend_strength != null:
		height_blend_strength = float(loaded_height_blend_strength)
	var loaded_texture_bombing_enabled = preset.get("texture_bombing_enabled")
	if loaded_texture_bombing_enabled != null:
		texture_bombing_enabled = bool(loaded_texture_bombing_enabled)
	var loaded_texture_bombing_strength = preset.get("texture_bombing_strength")
	if loaded_texture_bombing_strength != null:
		texture_bombing_strength = float(loaded_texture_bombing_strength)
	var loaded_texture_bombing_cell_scale = preset.get("texture_bombing_cell_scale")
	if loaded_texture_bombing_cell_scale != null:
		texture_bombing_cell_scale = float(loaded_texture_bombing_cell_scale)
	var loaded_texture_bombing_samples = preset.get("texture_bombing_samples")
	if loaded_texture_bombing_samples != null:
		texture_bombing_samples = int(loaded_texture_bombing_samples)
	var loaded_terrain_performance_preset = preset.get("terrain_performance_preset")
	if loaded_terrain_performance_preset != null:
		terrain_performance_preset = int(loaded_terrain_performance_preset)
	var loaded_high_view_lod_bias_enabled = preset.get("high_view_lod_bias_enabled")
	if loaded_high_view_lod_bias_enabled != null:
		high_view_lod_bias_enabled = bool(loaded_high_view_lod_bias_enabled)
	var loaded_high_view_lod_start_height = preset.get("high_view_lod_start_height")
	if loaded_high_view_lod_start_height != null:
		high_view_lod_start_height = float(loaded_high_view_lod_start_height)
	var loaded_high_view_lod_full_height = preset.get("high_view_lod_full_height")
	if loaded_high_view_lod_full_height != null:
		high_view_lod_full_height = float(loaded_high_view_lod_full_height)
	var loaded_high_view_lod_max_bias = preset.get("high_view_lod_max_bias")
	if loaded_high_view_lod_max_bias != null:
		high_view_lod_max_bias = int(loaded_high_view_lod_max_bias)
	var loaded_terrain_shadow_casting = preset.get("terrain_shadow_casting")
	if loaded_terrain_shadow_casting != null:
		terrain_shadow_casting = int(loaded_terrain_shadow_casting)
	var loaded_far_material_cache_enabled = preset.get("far_material_cache_enabled")
	if loaded_far_material_cache_enabled != null:
		far_material_cache_enabled = bool(loaded_far_material_cache_enabled)
	var loaded_far_material_cache_resolution = preset.get("far_material_cache_resolution")
	if loaded_far_material_cache_resolution != null:
		far_material_cache_resolution = int(loaded_far_material_cache_resolution)
	macro_variation_strength = preset.macro_variation_strength
	macro_variation_scale = preset.macro_variation_scale
	detail_noise_strength = preset.detail_noise_strength
	detail_noise_scale = preset.detail_noise_scale
	rock_detail_strength = preset.rock_detail_strength
	snow_detail_strength = preset.snow_detail_strength
	material_brightness = preset.material_brightness
	material_contrast = preset.material_contrast


func _get_viewport_display_stride() -> int:
	match viewport_quality:
		ViewportQuality.HALF:
			return 2
		ViewportQuality.QUARTER:
			return 4
		ViewportQuality.EIGHTH:
			return 8
		_:
			return 1


func _get_chunk_center(chunk_x: int, chunk_z: int) -> Vector2:
	var chunk_world_size := terrain_size / float(chunks_per_side)
	return Vector2(
		float(chunk_x) * chunk_world_size + chunk_world_size * 0.5 - _active_half_size,
		float(chunk_z) * chunk_world_size + chunk_world_size * 0.5 - _active_half_size
	)


func _get_chunk_coordinates(chunk: MeshInstance3D) -> Vector2i:
	if chunk.has_meta("terrain_chunk_x") and chunk.has_meta("terrain_chunk_z"):
		return Vector2i(int(chunk.get_meta("terrain_chunk_x")), int(chunk.get_meta("terrain_chunk_z")))

	var name_parts := chunk.name.split("_")
	if name_parts.size() >= 3:
		return Vector2i(int(name_parts[1]), int(name_parts[2]))

	var chunk_center := chunk.get_meta("terrain_chunk_center", Vector2.ZERO) as Vector2
	var chunk_world_size := terrain_size / float(chunks_per_side)
	var chunk_x := clampi(floori((chunk_center.x + _active_half_size) / chunk_world_size), 0, chunks_per_side - 1)
	var chunk_z := clampi(floori((chunk_center.y + _active_half_size) / chunk_world_size), 0, chunks_per_side - 1)
	return Vector2i(chunk_x, chunk_z)


func _should_process_automatic_lod_focus() -> bool:
	return automatic_lod_focus and viewport_lod_enabled and _has_generated_chunks() and _has_automatic_lod_focus_source()


func _should_process_material_focus() -> bool:
	return macro_texture_tiling_enabled and material_mode == TerrainMaterialMode.TEXTURE_LAYERS and _has_generated_chunks() and _has_automatic_lod_focus_source()


func _update_material_focus(force: bool = false) -> void:
	if not macro_texture_tiling_enabled or material_mode != TerrainMaterialMode.TEXTURE_LAYERS or not is_inside_tree():
		return

	var focus := _get_material_focus()
	if not focus.is_finite():
		return

	if not force and _last_material_focus.is_finite() and focus.distance_to(_last_material_focus) < 0.05:
		return

	_last_material_focus = focus
	_update_material_focus_position(focus)


func _get_material_focus() -> Vector3:
	var editor_camera_position := _get_editor_viewport_camera_position()
	if editor_camera_position.is_finite():
		return editor_camera_position

	var target := get_node_or_null(lod_target_path) as Node3D
	if target != null:
		return target.global_position

	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera != null:
		return camera.global_position

	var focus_2d := _get_automatic_lod_focus()
	if focus_2d.is_finite():
		return Vector3(focus_2d.x, 0.0, focus_2d.y)

	return Vector3.INF


func _update_automatic_lod_focus(force: bool = false) -> void:
	if not automatic_lod_focus or not viewport_lod_enabled or not is_inside_tree():
		return

	var focus := _get_automatic_lod_focus()
	if not focus.is_finite():
		return

	if not force and _last_automatic_lod_focus.is_finite():
		var focus_height := _get_lod_focus_height()
		var height_changed := is_finite(focus_height) and (not is_finite(_last_lod_focus_height) or absf(focus_height - _last_lod_focus_height) >= lod_focus_update_distance)
		if focus.distance_to(_last_automatic_lod_focus) < lod_focus_update_distance and not height_changed:
			return

	_last_automatic_lod_focus = focus
	_last_lod_focus_height = _get_lod_focus_height()
	if culling_center.distance_to(focus) <= 0.0001:
		_apply_viewport_culling()
		return

	culling_center = focus


func _get_automatic_lod_focus() -> Vector2:
	var target := get_node_or_null(lod_target_path) as Node3D
	if target != null:
		return Vector2(target.global_position.x, target.global_position.z)

	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera != null:
		return Vector2(camera.global_position.x, camera.global_position.z)

	var editor_camera_focus := _get_editor_viewport_camera_focus()
	if editor_camera_focus.is_finite():
		return editor_camera_focus

	return Vector2.INF


func _get_editor_viewport_camera_focus() -> Vector2:
	if not Engine.is_editor_hint():
		return Vector2.INF

	for viewport_index in 4:
		var editor_viewport = EditorInterface.get_editor_viewport_3d(viewport_index)
		if editor_viewport == null:
			continue
		var editor_camera := editor_viewport.get_camera_3d()
		if editor_camera != null:
			return Vector2(editor_camera.global_position.x, editor_camera.global_position.z)

	return Vector2.INF


func _get_editor_viewport_camera_position() -> Vector3:
	if not Engine.is_editor_hint():
		return Vector3.INF

	for viewport_index in 4:
		var editor_viewport = EditorInterface.get_editor_viewport_3d(viewport_index)
		if editor_viewport == null:
			continue
		var editor_camera := editor_viewport.get_camera_3d()
		if editor_camera != null:
			return editor_camera.global_position

	return Vector3.INF


func _has_automatic_lod_focus_source() -> bool:
	if get_node_or_null(lod_target_path) is Node3D:
		return true
	if get_viewport() != null and get_viewport().get_camera_3d() != null:
		return true
	return _get_editor_viewport_camera_focus().is_finite()


func _apply_viewport_culling() -> void:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return

	for child in chunks_root.get_children():
		var chunk := child as MeshInstance3D
		if chunk == null:
			continue
		if not viewport_culling_enabled:
			chunk.visible = true
			_apply_lod_to_chunk(chunk)
			continue

		var chunk_center := chunk.get_meta("terrain_chunk_center", Vector2.ZERO) as Vector2
		chunk.visible = chunk_center.distance_to(culling_center) <= visible_radius
		if chunk.visible:
			_apply_lod_to_chunk(chunk)
	_update_lod_statistics()
	_update_bake_state(GenerationMode.FINAL if final_terrain_locked else _active_generation_mode)


func _count_generated_chunks() -> int:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return 0
	var count := 0
	for child in chunks_root.get_children():
		if child is MeshInstance3D:
			count += 1
	return count


func _count_visible_generated_chunks() -> int:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return 0
	var count := 0
	for child in chunks_root.get_children():
		var chunk := child as MeshInstance3D
		if chunk != null and chunk.visible:
			count += 1
	return count


func _apply_lod_to_chunk(chunk: MeshInstance3D) -> void:
	if not viewport_lod_enabled and final_terrain_locked:
		_set_chunk_lod(chunk, _get_viewport_quality_lod_index())
		return
	if not viewport_lod_enabled:
		return

	var lod_index := _get_distance_lod_index(chunk)
	_set_chunk_lod(chunk, lod_index)


func _get_distance_lod_index(chunk: MeshInstance3D) -> int:
	var cap_index := _get_viewport_quality_lod_index()
	var radius := maxf(visible_radius, 0.001)
	var chunk_center := chunk.get_meta("terrain_chunk_center", Vector2.ZERO) as Vector2
	var distance_ratio := chunk_center.distance_to(culling_center) / radius
	var lod_offset := 0

	match lod_profile:
		LodProfile.QUALITY:
			if distance_ratio > 0.75:
				lod_offset = 2
			elif distance_ratio > 0.45:
				lod_offset = 1
		LodProfile.PERFORMANCE:
			if distance_ratio > 0.35:
				lod_offset = 3
			elif distance_ratio > 0.15:
				lod_offset = 2
			elif distance_ratio > 0.05:
				lod_offset = 1
		_:
			if distance_ratio > 0.45:
				lod_offset = 3
			elif distance_ratio > 0.25:
				lod_offset = 2
			elif distance_ratio > 0.10:
				lod_offset = 1

	lod_offset += _get_high_view_lod_bias()
	return clampi(cap_index + lod_offset, ViewportQuality.FULL, ViewportQuality.EIGHTH)


func _get_high_view_lod_bias() -> int:
	if not high_view_lod_bias_enabled or high_view_lod_max_bias <= 0:
		return 0
	var focus_height := _get_lod_focus_height()
	if not is_finite(focus_height):
		return 0
	var start_height := maxf(0.0, high_view_lod_start_height)
	var full_height := maxf(high_view_lod_full_height, start_height + 0.001)
	var amount := clampf((focus_height - start_height) / (full_height - start_height), 0.0, 1.0)
	return clampi(roundi(amount * float(high_view_lod_max_bias)), 0, high_view_lod_max_bias)


func _get_lod_focus_height() -> float:
	var target := get_node_or_null(lod_target_path) as Node3D
	if target != null:
		return target.global_position.y

	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera != null:
		return camera.global_position.y

	if Engine.is_editor_hint():
		for viewport_index in 4:
			var editor_viewport = EditorInterface.get_editor_viewport_3d(viewport_index)
			if editor_viewport == null:
				continue
			var editor_camera := editor_viewport.get_camera_3d()
			if editor_camera != null:
				return editor_camera.global_position.y

	return INF


func _update_lod_statistics() -> void:
	visible_lod0_chunks = 0
	visible_lod1_chunks = 0
	visible_lod2_chunks = 0
	visible_lod3_chunks = 0
	estimated_visible_triangles = 0

	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return

	for child in chunks_root.get_children():
		var chunk := child as MeshInstance3D
		if chunk == null or not chunk.visible:
			continue
		var lod_index := clampi(int(chunk.get_meta("terrain_current_lod", _get_viewport_quality_lod_index())), ViewportQuality.FULL, ViewportQuality.EIGHTH)
		match lod_index:
			ViewportQuality.FULL:
				visible_lod0_chunks += 1
			ViewportQuality.HALF:
				visible_lod1_chunks += 1
			ViewportQuality.QUARTER:
				visible_lod2_chunks += 1
			ViewportQuality.EIGHTH:
				visible_lod3_chunks += 1
		estimated_visible_triangles += _estimate_chunk_triangle_count(lod_index)


func _estimate_chunk_triangle_count(lod_index: int) -> int:
	var stride: int = LOD_STRIDES[clampi(lod_index, ViewportQuality.FULL, ViewportQuality.EIGHTH)]
	var quads_per_side := ceili(float(_active_chunk_resolution) / float(maxi(1, stride)))
	return quads_per_side * quads_per_side * 2


func _get_viewport_quality_lod_index() -> int:
	return clampi(viewport_quality, ViewportQuality.FULL, ViewportQuality.EIGHTH)


func _set_chunk_lod(chunk: MeshInstance3D, lod_index: int) -> void:
	lod_index = clampi(lod_index, ViewportQuality.FULL, ViewportQuality.EIGHTH)
	if int(chunk.get_meta("terrain_current_lod", -1)) == lod_index and not _chunk_lod_mesh_needs_rebuild(chunk, lod_index):
		return

	var mesh_path := str(chunk.get_meta(_get_lod_meta_key(lod_index), ""))
	if mesh_path.is_empty() and lod_index == 0 and chunk.mesh != null and not chunk.mesh.resource_path.is_empty():
		mesh_path = chunk.mesh.resource_path
	if mesh_path.is_empty():
		return

	var lod_mesh := load(mesh_path) as ArrayMesh
	if lod_mesh == null:
		return
	if lod_index > 0 and int(lod_mesh.get_meta("terrain_lod_edge_version", 0)) < TERRAIN_LOD_EDGE_VERSION:
		lod_mesh = _rebuild_chunk_lod_mesh(chunk, lod_index, mesh_path)
		if lod_mesh == null:
			return

	chunk.mesh = lod_mesh
	chunk.set_meta("terrain_current_lod", lod_index)


func _chunk_lod_mesh_needs_rebuild(chunk: MeshInstance3D, lod_index: int) -> bool:
	if lod_index <= 0:
		return false
	var lod_mesh := chunk.mesh as ArrayMesh
	return lod_mesh != null and int(lod_mesh.get_meta("terrain_lod_edge_version", 0)) < TERRAIN_LOD_EDGE_VERSION


func _rebuild_chunk_lod_mesh(chunk: MeshInstance3D, lod_index: int, mesh_path: String) -> ArrayMesh:
	_configure_noise()
	_configure_active_generation_state(GenerationMode.FINAL if final_terrain_locked else _active_generation_mode)
	if not _ensure_active_heightfield():
		return null
	var coordinates := _get_chunk_coordinates(chunk)
	var stride: int = LOD_STRIDES[clampi(lod_index, ViewportQuality.FULL, ViewportQuality.EIGHTH)]
	var rebuilt_mesh := _build_chunk_mesh(coordinates.x, coordinates.y, stride, stride > 1)
	rebuilt_mesh.set_meta("terrain_lod_edge_version", TERRAIN_LOD_EDGE_VERSION)
	if not mesh_path.is_empty():
		ResourceSaver.save(rebuilt_mesh, mesh_path)
	return rebuilt_mesh


func _apply_collision_visual_visibility() -> void:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return

	for chunk in chunks_root.get_children():
		for child in chunk.get_children():
			if child.name == "CollisionBody" or child is StaticBody3D:
				_set_collision_visual_visibility_recursive(child, collision_visuals_visible)


func _set_collision_visual_visibility_recursive(node: Node, is_visible: bool) -> void:
	var node_3d := node as Node3D
	if node_3d != null:
		node_3d.visible = is_visible
	for child in node.get_children():
		_set_collision_visual_visibility_recursive(child, is_visible)


func _get_collision_target_chunks() -> Array[MeshInstance3D]:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	var targets: Array[MeshInstance3D] = []
	if chunks_root == null:
		return targets

	for child in chunks_root.get_children():
		var chunk := child as MeshInstance3D
		if chunk == null:
			continue

		if _chunk_is_in_collision_coverage(chunk):
			targets.append(chunk)

	return targets


func _chunk_is_in_collision_coverage(chunk: MeshInstance3D) -> bool:
	match collision_coverage:
		CollisionCoverage.ALL_CHUNKS:
			return true
		CollisionCoverage.VISIBLE_CHUNKS:
			if not viewport_culling_enabled:
				return true
			var visible_center := chunk.get_meta("terrain_chunk_center", Vector2.ZERO) as Vector2
			return visible_center.distance_to(culling_center) <= visible_radius
		_:
			var chunk_center := chunk.get_meta("terrain_chunk_center", Vector2.ZERO) as Vector2
			return chunk_center.distance_to(culling_center) <= _get_effective_collision_radius()


func _build_next_collision_chunks() -> void:
	var build_count := mini(collision_chunks_per_frame, _pending_collision_chunks.size())

	for _build_index in build_count:
		var chunk: MeshInstance3D = _pending_collision_chunks.pop_front()
		_add_collision_from_existing_mesh(chunk)
		_generated_chunks += 1

	if _pending_collision_chunks.is_empty():
		_is_generating_collision = false
		if final_terrain_locked and save_final_meshes_as_resources:
			var save_error := _save_generated_resources(false)
			if save_error != OK:
				push_warning("Could not save generated collision resources. Error code: %d" % save_error)
		_make_generated_nodes_scene_owned()
		_apply_collision_visual_visibility()
		_update_bake_state(GenerationMode.FINAL if final_terrain_locked else _active_generation_mode)
		print(_last_bake_state)
		_update_processing_state()


func _clear_collision_outside_targets() -> void:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return

	for child in chunks_root.get_children():
		var chunk := child as MeshInstance3D
		if chunk != null and not _collision_target_names.has(chunk.name):
			_remove_collision_from_chunk(chunk)


func _refresh_collision_for_focus_if_needed() -> void:
	if collision_coverage != CollisionCoverage.NEAR_CENTER:
		return
	if not _has_generated_collision():
		return
	generate_collision_for_existing_terrain()


func _has_generated_collision() -> bool:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return false

	for chunk in chunks_root.get_children():
		if chunk.has_node("CollisionBody/CollisionShape"):
			return true
	return false


func _cancel_collision_generation() -> void:
	_pending_collision_chunks.clear()
	_collision_target_names.clear()
	_is_generating_collision = false


func _get_effective_collision_radius() -> float:
	if auto_performance_settings:
		return terrain_size * 0.35
	return collision_radius


func _has_generated_chunks() -> bool:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	return chunks_root != null and chunks_root.get_child_count() > 0


func _make_generated_nodes_scene_owned() -> void:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root != null:
		_set_scene_owner_recursive(chunks_root)


func _set_scene_owner_recursive(node: Node) -> void:
	_set_scene_owner(node)
	for child in node.get_children():
		_set_scene_owner_recursive(child)


func _set_scene_owner(node: Node) -> void:
	var scene_owner := _get_scene_owner()
	if scene_owner == null or node == scene_owner:
		return
	node.owner = scene_owner


func _get_scene_owner() -> Node:
	if Engine.is_editor_hint() and get_tree() != null:
		var edited_scene_root := get_tree().edited_scene_root
		if edited_scene_root != null:
			return edited_scene_root
	return owner


func _use_shader_preview(mode: int) -> bool:
	return mode == GenerationMode.PREVIEW and preview_backend == PreviewBackend.SHADER


func _generate_shader_preview() -> void:
	var preview := _get_or_create_shader_preview()
	var preview_mesh := PlaneMesh.new()
	preview_mesh.size = Vector2(terrain_size, terrain_size)
	preview_mesh.subdivide_width = shader_preview_subdivisions
	preview_mesh.subdivide_depth = shader_preview_subdivisions
	preview.mesh = preview_mesh
	preview.material_override = _get_or_create_shader_preview_material()
	preview.visible = true
	preview.position = Vector3.ZERO
	_shader_preview_height_texture = _create_shader_preview_height_texture()
	_update_shader_preview_material()


func _get_or_create_shader_preview() -> MeshInstance3D:
	var preview := get_node_or_null(SHADER_PREVIEW_NAME) as MeshInstance3D
	if preview == null:
		preview = MeshInstance3D.new()
		preview.name = SHADER_PREVIEW_NAME
		preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _terrain_should_cast_shadows() else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(preview)
	return preview


func _remove_shader_preview() -> void:
	var preview := get_node_or_null(SHADER_PREVIEW_NAME)
	if preview == null:
		return
	remove_child(preview)
	preview.queue_free()


func _get_or_create_shader_preview_material() -> ShaderMaterial:
	if _shader_preview_material == null:
		_shader_preview_material = ShaderMaterial.new()
		_shader_preview_material.shader = _get_or_create_shader_preview_shader()
	return _shader_preview_material


func _get_or_create_shader_preview_shader() -> Shader:
	if _shader_preview_shader == null:
		_shader_preview_shader = Shader.new()
	_shader_preview_shader.code = SHADER_PREVIEW_CODE
	return _shader_preview_shader


func _create_shader_preview_height_texture() -> Texture2D:
	if not _active_heightfield.is_valid():
		return null

	var texture_resolution := clampi(shader_preview_texture_resolution, 64, 1024)
	var image_size := texture_resolution + 1
	var image := Image.create(image_size, image_size, false, Image.FORMAT_RF)
	var min_height := _active_heightfield.get_min_height()
	var max_height := _active_heightfield.get_max_height()
	var height_range := maxf(max_height - min_height, 0.0001)

	for z in image_size:
		var source_z := float(z) / float(texture_resolution) * float(_active_heightfield.height - 1)
		for x in image_size:
			var source_x := float(x) / float(texture_resolution) * float(_active_heightfield.width - 1)
			var height_value := _active_heightfield.sample_grid_bilinear(source_x, source_z)
			var normalized_height := clampf((height_value - min_height) / height_range, 0.0, 1.0)
			image.set_pixel(x, z, Color(normalized_height, 0.0, 0.0, 1.0))

	return ImageTexture.create_from_image(image)


func _update_shader_preview_material() -> void:
	var preview := get_node_or_null(SHADER_PREVIEW_NAME) as MeshInstance3D
	if preview == null or preview.material_override == null:
		return
	var material := preview.material_override as ShaderMaterial
	if material == null:
		return
	if _shader_preview_height_texture == null:
		_shader_preview_height_texture = _create_shader_preview_height_texture()
	if _shader_preview_height_texture == null:
		return

	var texture_resolution := clampi(shader_preview_texture_resolution, 64, 1024)
	material.shader = _get_or_create_shader_preview_shader()
	material.set_shader_parameter("height_texture", _shader_preview_height_texture)
	material.set_shader_parameter("height_min", _active_heightfield.get_min_height())
	material.set_shader_parameter("height_max", _active_heightfield.get_max_height())
	material.set_shader_parameter("terrain_size", terrain_size)
	material.set_shader_parameter("height_texel_size", 1.0 / float(texture_resolution))
	material.set_shader_parameter("snow_enabled", snow_enabled)
	material.set_shader_parameter("height_scale", height_scale)
	material.set_shader_parameter("snow_height", snow_height)
	material.set_shader_parameter("rock_slope_threshold", rock_slope_threshold)
	material.set_shader_parameter("lowland_color", lowland_color)
	material.set_shader_parameter("grass_color", grass_color)
	material.set_shader_parameter("rock_color", rock_color)
	material.set_shader_parameter("snow_color", snow_color)
	material.set_shader_parameter("material_brightness", material_brightness)
	material.set_shader_parameter("material_contrast", material_contrast)


func _get_or_create_chunks_root() -> Node3D:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME) as Node3D
	if chunks_root == null:
		chunks_root = Node3D.new()
		chunks_root.name = TERRAIN_CHUNKS_NAME
		add_child(chunks_root)
		_set_scene_owner(chunks_root)
	return chunks_root


func _clear_chunk_nodes(chunks_root: Node) -> void:
	for child in chunks_root.get_children():
		var child_3d := child as Node3D
		if child_3d != null:
			child_3d.visible = false
		chunks_root.remove_child(child)
		child.queue_free()


func _create_chunk_mesh_instance(chunk_x: int, chunk_z: int, material: Material) -> MeshInstance3D:
	var chunk_mesh_instance := MeshInstance3D.new()
	chunk_mesh_instance.name = "TerrainChunk_%02d_%02d" % [chunk_x, chunk_z]
	chunk_mesh_instance.material_override = material
	chunk_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _terrain_should_cast_shadows() else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	chunk_mesh_instance.set_meta("terrain_chunk_center", _get_chunk_center(chunk_x, chunk_z))
	chunk_mesh_instance.set_meta("terrain_chunk_x", chunk_x)
	chunk_mesh_instance.set_meta("terrain_chunk_z", chunk_z)
	chunk_mesh_instance.set_meta("terrain_material_encoding", _get_new_mesh_material_encoding())
	return chunk_mesh_instance


func _add_collision_from_existing_mesh(chunk_mesh_instance: MeshInstance3D) -> void:
	if chunk_mesh_instance.mesh == null:
		return

	_remove_collision_from_chunk(chunk_mesh_instance)
	var collision_mesh := _get_collision_mesh_for_chunk(chunk_mesh_instance)
	if collision_mesh == null:
		return

	var body := StaticBody3D.new()
	body.name = "CollisionBody"
	body.visible = collision_visuals_visible
	chunk_mesh_instance.add_child(body)
	_set_scene_owner(body)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape"
	collision_shape.visible = collision_visuals_visible
	collision_shape.shape = _create_terrain_collision_shape(collision_mesh)
	body.add_child(collision_shape)
	_set_scene_owner(collision_shape)


func _add_chunk_collision(chunk_mesh_instance: MeshInstance3D, chunk_x: int, chunk_z: int) -> void:
	_remove_collision_from_chunk(chunk_mesh_instance)

	var body := StaticBody3D.new()
	body.name = "CollisionBody"
	body.visible = collision_visuals_visible
	chunk_mesh_instance.add_child(body)
	_set_scene_owner(body)

	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape"
	collision_shape.visible = collision_visuals_visible
	var collision_stride: int = LOD_STRIDES[clampi(collision_quality, ViewportQuality.FULL, ViewportQuality.EIGHTH)]
	collision_shape.shape = _create_terrain_collision_shape(_build_chunk_mesh(chunk_x, chunk_z, collision_stride, collision_stride > 1))
	body.add_child(collision_shape)
	_set_scene_owner(collision_shape)


func _create_terrain_collision_shape(mesh: ArrayMesh) -> Shape3D:
	var shape := mesh.create_trimesh_shape()
	_configure_terrain_collision_shape(shape)
	return shape


func _configure_terrain_collision_shape(shape: Shape3D) -> void:
	if shape == null:
		return
	if shape is ConcavePolygonShape3D:
		(shape as ConcavePolygonShape3D).backface_collision = true


func _configure_existing_collision_shapes() -> void:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return

	for chunk in chunks_root.get_children():
		var collision_shape := chunk.get_node_or_null("CollisionBody/CollisionShape") as CollisionShape3D
		if collision_shape != null:
			_configure_terrain_collision_shape(collision_shape.shape)


func _get_collision_mesh_for_chunk(chunk: MeshInstance3D) -> ArrayMesh:
	var lod_index := clampi(collision_quality, ViewportQuality.FULL, ViewportQuality.EIGHTH)
	var mesh_path := str(chunk.get_meta(_get_lod_meta_key(lod_index), ""))
	if not mesh_path.is_empty():
		var saved_lod_mesh := ResourceLoader.load(mesh_path, "ArrayMesh", ResourceLoader.CACHE_MODE_REPLACE) as ArrayMesh
		if saved_lod_mesh != null:
			return saved_lod_mesh

	var coordinates := _get_chunk_coordinates(chunk)
	var collision_stride: int = LOD_STRIDES[lod_index]
	return _build_chunk_mesh(coordinates.x, coordinates.y, collision_stride, collision_stride > 1)


func _remove_collision_from_chunk(chunk: Node) -> void:
	for child in chunk.get_children():
		if child.name == "CollisionBody" or child is StaticBody3D:
			chunk.remove_child(child)
			child.queue_free()


func _remove_legacy_v1_nodes() -> void:
	for legacy_node_name in [LEGACY_TERRAIN_MESH_NAME, LEGACY_TERRAIN_BODY_NAME]:
		var legacy_node := get_node_or_null(legacy_node_name)
		if legacy_node != null:
			remove_child(legacy_node)
			legacy_node.queue_free()


func _chunk_uses_v5_masks(chunk: MeshInstance3D) -> bool:
	return str(chunk.get_meta("terrain_material_encoding", "")) == TERRAIN_ENCODING_V5_MASKS


func _get_material_for_chunk(chunk: MeshInstance3D) -> Material:
	return _material_manager.get_material_for_encoding(TERRAIN_ENCODING_V5_MASKS if _chunk_uses_v5_masks(chunk) else TERRAIN_ENCODING_LEGACY_COLORS)


func _get_material_for_encoding(encoding: String) -> Material:
	_configure_material_manager()
	return _material_manager.get_material_for_encoding(encoding)


func _update_visual_materials() -> void:
	_configure_material_manager()
	_material_manager.update_materials()
	_assign_materials_to_existing_chunks()


func _update_material_focus_position(focus_position: Vector3) -> void:
	_material_manager.set_texture_focus_position(focus_position)


func _configure_material_manager() -> void:
	_material_manager.configure({
		"generated_resource_directory": _get_generated_resource_directory(),
		"seed": terrain_seed,
		"material_mode": material_mode,
		"texture_focus_position": _last_material_focus if _last_material_focus.is_finite() else Vector3(culling_center.x, 0.0, culling_center.y),
		"height_scale": height_scale,
		"snow_height": snow_height,
		"snow_enabled": snow_enabled,
		"rock_slope_threshold": rock_slope_threshold,
		"lowland_color": lowland_color,
		"grass_color": grass_color,
		"rock_color": rock_color,
		"snow_color": snow_color,
		"lowland_layer_enabled": lowland_layer_enabled,
		"ground_layer_enabled": ground_layer_enabled,
		"upper_layer_enabled": upper_layer_enabled,
		"rocky_layer_enabled": rocky_layer_enabled,
		"cliff_layer_enabled": cliff_layer_enabled,
		"snow_layer_enabled": snow_layer_enabled,
		"lowland_material_folder": lowland_material_folder,
		"ground_material_folder": ground_material_folder,
		"upper_material_folder": upper_material_folder,
		"rocky_material_folder": rocky_material_folder,
		"cliff_material_folder": cliff_material_folder,
		"snow_material_folder": snow_material_folder,
		"texture_tile_scale": texture_tile_scale,
		"macro_texture_tiling_enabled": macro_texture_tiling_enabled,
		"close_texture_tile_scale": close_texture_tile_scale,
		"medium_texture_tile_scale": medium_texture_tile_scale,
		"far_texture_tile_scale": far_texture_tile_scale,
		"close_texture_radius": close_texture_radius,
		"medium_texture_radius": medium_texture_radius,
		"far_texture_radius": far_texture_radius,
		"layer_blend_softness": layer_blend_softness,
		"texture_normal_strength": texture_normal_strength,
		"roughness_multiplier": roughness_multiplier,
		"height_blend_strength": height_blend_strength,
		"texture_bombing_enabled": texture_bombing_enabled,
		"texture_bombing_strength": texture_bombing_strength,
		"texture_bombing_cell_scale": texture_bombing_cell_scale,
		"texture_bombing_samples": texture_bombing_samples,
		"material_performance_preset": terrain_performance_preset,
		"far_material_cache_enabled": far_material_cache_enabled,
		"far_material_cache_resolution": far_material_cache_resolution,
		"terrain_world_size": terrain_size,
		"procedural_material_enabled": procedural_material_enabled,
		"macro_variation_strength": macro_variation_strength,
		"macro_variation_scale": macro_variation_scale,
		"detail_noise_strength": detail_noise_strength,
		"detail_noise_scale": detail_noise_scale,
		"rock_detail_strength": rock_detail_strength,
		"snow_detail_strength": snow_detail_strength,
		"material_brightness": material_brightness,
		"material_contrast": material_contrast,
	})


func _assign_materials_to_existing_chunks() -> void:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return

	for child in chunks_root.get_children():
		var chunk := child as MeshInstance3D
		if chunk != null:
			chunk.material_override = _get_material_for_chunk(chunk)
			chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _terrain_should_cast_shadows() else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _maybe_externalize_final_visual_resources() -> void:
	if _material_manager.is_saving() or not final_terrain_locked or not save_final_meshes_as_resources:
		return
	if not _has_generated_chunks():
		return

	var resource_directory := _get_generated_resource_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(resource_directory)
	if directory_error != OK:
		push_warning("Could not create generated resource directory. Error code: %d" % directory_error)
		return

	var save_error := _save_visual_resources(resource_directory)
	if save_error != OK:
		push_warning("Could not save procedural visual resources. Error code: %d" % save_error)
		return

	_assign_materials_to_existing_chunks()


func _reset_visual_noise_textures() -> void:
	_material_manager.reset_noise_textures()
	_update_visual_materials()


func _save_visual_resources(resource_directory: String) -> int:
	var timing_start := _timing_begin()
	_configure_material_manager()
	var terrain_material_error: int = _material_manager.save_visual_resources(resource_directory, _active_heightfield)
	_timing_add("visual_resource_save", timing_start)
	return terrain_material_error
