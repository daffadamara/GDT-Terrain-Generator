@tool
extends Resource
class_name TerrainPreset

@export_group("Terrain Shape")
@export var terrain_size := 64.0
@export var chunk_resolution := 256
@export var chunks_per_side := 4
@export var height_scale := 2.0

@export_group("Terrain Source")
@export var source_mode := 0
@export var heightmap_path := ""
@export var heightmap_flip_x := false
@export var heightmap_flip_z := false
@export var heightmap_invert := false
@export var heightmap_format := 0
@export var heightmap_raw_width := 257
@export var heightmap_raw_height := 257
@export var heightmap_raw_min_height := -5.0
@export var heightmap_raw_max_height := 5.0
@export var heightmap_export_min_height := 0.0
@export var heightmap_export_max_height := 0.0

@export_group("Region Data")
@export var region_data_enabled := true
@export var save_region_data := true
@export var region_data_directory := "res://generated_terrain/regions"

@export_group("Terrain Pattern")
@export var terrain_seed := 1345
@export var noise_frequency := 0.032
@export var terrain_scale := 1.0
@export var octaves := 7
@export var lacunarity := 2.1
@export var gain := 0.42

@export_group("Environment")
@export var snow_enabled := true
@export var snow_height := 5.0
@export var rock_slope_threshold := 0.44
@export var lowland_color := Color(0.15, 0.21, 0.09)
@export var grass_color := Color(0.24, 0.33, 0.15)
@export var rock_color := Color(0.27, 0.24, 0.18)
@export var snow_color := Color(0.86, 0.84, 0.76)

@export_group("Visual Material")
@export var procedural_material_enabled := true
@export var material_mode := 1
@export var lowland_layer_enabled := false
@export var ground_layer_enabled := true
@export var upper_layer_enabled := false
@export var rocky_layer_enabled := true
@export var cliff_layer_enabled := true
@export var snow_layer_enabled := true
@export var lowland_material_folder := "res://material/sand_03"
@export var ground_material_folder := "res://material/forest_ground"
@export var upper_material_folder := "res://material/aerial_grass_rock"
@export var rocky_material_folder := "res://material/rocky_terrain"
@export var cliff_material_folder := "res://material/rock_face"
@export var snow_material_folder := "res://material/snow"
@export var texture_tile_scale := 0.18
@export var macro_texture_tiling_enabled := true
@export var texture_focus_mode := 2
@export var texture_focus_target_path := NodePath()
@export var close_texture_tile_scale := 0.20
@export var medium_texture_tile_scale := 0.03
@export var far_texture_tile_scale := 0.01
@export var close_texture_radius := 24.0
@export var medium_texture_radius := 48.0
@export var far_texture_radius := 92.0
@export var layer_blend_softness := 0.18
@export var texture_normal_strength := 0.75
@export var roughness_multiplier := 1.0
@export var height_blend_strength := 0.12
@export var texture_bombing_enabled := true
@export var texture_bombing_strength := 0.55
@export var texture_bombing_cell_scale := 0.65
@export var texture_bombing_samples := 2
@export var terrain_performance_preset := 2
@export var high_view_lod_bias_enabled := true
@export var high_view_lod_start_height := 36.0
@export var high_view_lod_full_height := 96.0
@export var high_view_lod_max_bias := 2
@export var terrain_shadow_casting := 1
@export var far_material_cache_enabled := true
@export var far_material_cache_resolution := 512
@export var macro_variation_strength := 0.18
@export var macro_variation_scale := 0.04
@export var detail_noise_strength := 0.15
@export var detail_noise_scale := 0.45
@export var rock_detail_strength := 0.25
@export var snow_detail_strength := 0.08
@export var material_brightness := 1.2
@export var material_contrast := 1.05

@export_group("Viewport")
@export var bake_preset := 1
@export var viewport_quality := 0
@export var viewport_lod_enabled := true
@export var lod_profile := 1
@export var automatic_lod_focus := true
@export var visible_radius := 128.0
@export var viewport_culling_enabled := true

@export_group("Collision")
@export var collision_mode := 0
@export var collision_coverage := 0
@export var collision_quality := 2
@export var collision_radius := 22.4
@export var collision_chunks_per_frame := 1
@export var dynamic_collision_enabled := false
@export var dynamic_collision_radius := 16.0
@export var dynamic_collision_update_distance := 16.0
@export var dynamic_collision_max_chunks_per_frame := 1

@export_group("Editor Brush")
@export var editor_brush_enabled := false
@export var editor_brush_mode := 0
@export var editor_brush_spacing := 0.16

@export_group("Material Paint")
@export var paint_enabled := false
@export var paint_layer := 1
@export var paint_strength := 0.5
@export var paint_radius := 4.0
@export var paint_softness := 0.5
@export var paint_mode := 0

@export_group("Scatter")
@export var scatter_enabled := false
@export var scatter_resource_directory := "res://generated_terrain/scatter"
@export var scatter_seed := 1001
@export var scatter_density := 0.35
@export var scatter_height_min := -64.0
@export var scatter_height_max := 64.0
@export var scatter_slope_min := 0.0
@export var scatter_slope_max := 0.55
@export var scatter_cell_size := 32.0
@export var scatter_visible_distance := 128.0
@export var scatter_brush_radius := 4.0
@export var scatter_brush_strength := 0.5
