@tool
extends Resource
class_name TerrainPreset

@export_group("Terrain Shape")
@export var terrain_size := 64.0
@export var chunk_resolution := 256
@export var chunks_per_side := 1
@export var height_scale := 5.0

@export_group("Terrain Source")
@export var source_mode := 0
@export var heightmap_path := ""
@export var heightmap_flip_x := false
@export var heightmap_flip_z := false
@export var heightmap_invert := false

@export_group("Terrain Pattern")
@export var seed := 1345
@export var noise_frequency := 0.032
@export var terrain_scale := 1.0
@export var octaves := 7
@export var lacunarity := 2.1
@export var gain := 0.42

@export_group("Environment")
@export var water_enabled := true
@export var water_level := 0.0
@export var water_color := Color(0.09, 0.25, 0.36, 1.0)
@export var water_alpha := 0.8
@export var auto_create_water := true
@export var snow_enabled := true
@export var snow_height := 5.0
@export var rock_slope_threshold := 0.44
@export var lowland_color := Color(0.15, 0.21, 0.09)
@export var grass_color := Color(0.24, 0.33, 0.15)
@export var shore_color := Color(0.52, 0.48, 0.30)
@export var seabed_color := Color(0.20, 0.17, 0.10)
@export var rock_color := Color(0.27, 0.24, 0.18)
@export var snow_color := Color(0.86, 0.84, 0.76)

@export_group("Visual Material")
@export var procedural_material_enabled := true
@export var macro_variation_strength := 0.18
@export var macro_variation_scale := 0.04
@export var detail_noise_strength := 0.15
@export var detail_noise_scale := 0.45
@export var rock_detail_strength := 0.25
@export var snow_detail_strength := 0.08
@export var shore_wetness_strength := 0.28
@export var material_brightness := 1.32
@export var material_contrast := 1.0

@export_group("Viewport")
@export var bake_preset := 1
@export var viewport_quality := 0
@export var viewport_lod_enabled := true
@export var lod_profile := 1
@export var automatic_lod_focus := true
@export var visible_radius := 48.0
@export var viewport_culling_enabled := true

@export_group("Collision")
@export var collision_mode := 0
@export var collision_coverage := 0
@export var collision_quality := 2
@export var collision_radius := 22.4
@export var collision_chunks_per_frame := 1
