@tool
extends Node3D

enum GenerationMode { PREVIEW, FINAL }
enum CollisionMode { DISABLED, FINAL_ONLY, ALL_BUILDS }
enum ViewportQuality { FULL, HALF, QUARTER, EIGHTH }
enum LodProfile { QUALITY, BALANCED, PERFORMANCE }
enum CollisionCoverage { NEAR_CENTER, VISIBLE_CHUNKS, ALL_CHUNKS }

const TERRAIN_CHUNKS_NAME := "TerrainChunks"
const WATER_PLANE_NAME := "WaterPlane"
const LEGACY_TERRAIN_MESH_NAME := "TerrainMesh"
const LEGACY_TERRAIN_BODY_NAME := "TerrainBody"
const DEFAULT_GENERATED_RESOURCE_DIR := "res://generated_terrain"
const LOD_STRIDES := [1, 2, 4, 8]

@export_category("Terrain Shape")

## Full terrain width and depth in Godot units. This is the size of the whole chunk grid, not a single chunk.
@export_range(4.0, 512.0, 1.0) var terrain_size: float = 64.0:
	set(value):
		terrain_size = maxf(4.0, value)
		_queue_regenerate()

## Final mesh detail per chunk. Use 256 with 16 chunks per side for a 4096 x 4096 total terrain grid.
@export_range(16, 256, 1) var chunk_resolution: int = 256:
	set(value):
		chunk_resolution = clampi(value, 16, 256)
		_queue_regenerate()

## Number of chunks along each side of the terrain. More chunks cover the same world size with more total detail.
@export_range(1, 16, 1) var chunks_per_side: int = 1:
	set(value):
		chunks_per_side = clampi(value, 1, 16)
		_queue_regenerate()

## Vertical height multiplier for the terrain. Higher values create taller mountains and deeper valleys.
@export_range(0.0, 64.0, 0.1) var height_scale: float = 5.0:
	set(value):
		height_scale = maxf(0.0, value)
		_queue_regenerate()

@export_category("Terrain Pattern")

## Random seed for the noise. Change this to get a different terrain layout while keeping the same style.
@export var seed: int = 1345:
	set(value):
		seed = value
		_queue_regenerate()

## Size of the main noise features. Lower values make broad landforms; higher values make tighter, busier terrain.
@export_range(0.001, 1.0, 0.001) var noise_frequency: float = 0.032:
	set(value):
		noise_frequency = maxf(0.001, value)
		_queue_regenerate()

## Number of layered noise passes. More octaves add finer detail, but increase generation time.
@export_range(1, 12, 1) var octaves: int = 7:
	set(value):
		octaves = maxi(1, value)
		_queue_regenerate()

## Frequency jump between noise layers. Higher values make the added detail smaller and sharper.
@export_range(1.0, 4.0, 0.01) var lacunarity: float = 2.1:
	set(value):
		lacunarity = maxf(1.0, value)
		_queue_regenerate()

## Strength of each added noise layer. Lower values are smoother; higher values keep more rough detail.
@export_range(0.0, 1.0, 0.01) var gain: float = 0.42:
	set(value):
		gain = clampf(value, 0.0, 1.0)
		_queue_regenerate()

@export_category("Environment")

## Adds a flat visual water plane at Water Level and uses shore coloring near that height.
@export var water_enabled: bool = true:
	set(value):
		water_enabled = value
		_update_water_plane()
		_queue_recolor_existing_chunks()

## World Y height of the water plane and shoreline color blend. Updates existing terrain colors without rebuilding chunks.
@export_range(-64.0, 64.0, 0.1) var water_level: float = 0.0:
	set(value):
		water_level = value
		_update_water_plane()
		_queue_recolor_existing_chunks()

## Color of the generated water plane.
@export var water_color: Color = Color(0.09, 0.25, 0.36, 1.0):
	set(value):
		water_color = value
		_update_water_plane()

## Transparency of the generated water plane. Lower values are more transparent.
@export_range(0.0, 1.0, 0.01) var water_alpha: float = 0.8:
	set(value):
		water_alpha = clampf(value, 0.0, 1.0)
		_update_water_plane()

## World Y height where terrain begins blending toward snow. Updates existing terrain colors without rebuilding chunks.
@export_range(-64.0, 64.0, 0.1) var snow_height: float = 5.0:
	set(value):
		snow_height = value
		_queue_recolor_existing_chunks()

## How steep terrain must be before it blends toward rock. Lower values create more exposed rock without rebuilding chunks.
@export_range(0.0, 1.0, 0.01) var rock_slope_threshold: float = 0.44:
	set(value):
		rock_slope_threshold = clampf(value, 0.0, 1.0)
		_queue_recolor_existing_chunks()

## Color used for the lowest dry land before it blends into grass. Updates existing terrain colors without rebuilding chunks.
@export var lowland_color: Color = Color(0.15, 0.21, 0.09):
	set(value):
		lowland_color = value
		_queue_recolor_existing_chunks()

## Main green terrain color for rolling hills and flatter mid elevations. Updates existing terrain colors without rebuilding chunks.
@export var grass_color: Color = Color(0.24, 0.33, 0.15):
	set(value):
		grass_color = value
		_queue_recolor_existing_chunks()

## Color blended into terrain near the water level. Updates existing terrain colors without rebuilding chunks.
@export var shore_color: Color = Color(0.52, 0.48, 0.30):
	set(value):
		shore_color = value
		_queue_recolor_existing_chunks()

## Color blended onto terrain below the water level. Darker values make underwater areas read as seabed.
@export var seabed_color: Color = Color(0.20, 0.17, 0.10):
	set(value):
		seabed_color = value
		_queue_recolor_existing_chunks()

## Color blended onto steep slopes. Updates existing terrain colors without rebuilding chunks.
@export var rock_color: Color = Color(0.27, 0.24, 0.18):
	set(value):
		rock_color = value
		_queue_recolor_existing_chunks()

## Color blended onto high elevations above Snow Height. Updates existing terrain colors without rebuilding chunks.
@export var snow_color: Color = Color(0.86, 0.84, 0.76):
	set(value):
		snow_color = value
		_queue_recolor_existing_chunks()

@export_category("Workflow")

## Automatically rebuilds the lightweight preview when terrain settings change.
@export var auto_update: bool = true:
	set(value):
		auto_update = value
		if auto_update:
			_queue_regenerate(GenerationMode.PREVIEW)

## Lets the generator choose preview detail and chunk build speed automatically. Collision is controlled separately by Collision Mode.
@export var auto_performance_settings: bool = true:
	set(value):
		auto_performance_settings = value
		_queue_regenerate(GenerationMode.PREVIEW)

## True after Generate Final finishes. Locked terrain is saved with the scene and will not regenerate until Clear Generated Terrain is used.
@export var final_terrain_locked: bool = false:
	set(value):
		final_terrain_locked = value

## Saves final chunk meshes as binary .res files so the text scene stays small and quick to save/load.
@export var save_final_meshes_as_resources: bool = true

## Folder used for generated binary mesh and collision resources.
@export var generated_resource_directory: String = DEFAULT_GENERATED_RESOURCE_DIR

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

## Chunk centers farther than this distance from Culling Center are hidden. Raise this or disable culling to show the full terrain.
@export_range(0.0, 1024.0, 0.1) var visible_radius: float = 48.0:
	set(value):
		visible_radius = maxf(0.0, value)
		_apply_viewport_culling()

## World X/Z point used as the center of viewport culling. Move it to inspect a different area of a large terrain.
@export var culling_center: Vector2 = Vector2.ZERO:
	set(value):
		culling_center = value
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

## Collision generation policy. Disabled is best for editor viewport performance; Final Only adds physics to final builds.
@export_enum("Disabled", "Final Only", "All Builds") var collision_mode: int = CollisionMode.DISABLED:
	set(value):
		collision_mode = clampi(value, CollisionMode.DISABLED, CollisionMode.ALL_BUILDS)
		if collision_mode == CollisionMode.DISABLED:
			remove_generated_collision()
		else:
			_queue_regenerate()

## Which chunks should receive collision. Near Center is fastest for editor inspection.
@export_enum("Near Center", "Visible Chunks", "All Chunks") var collision_coverage: int = CollisionCoverage.NEAR_CENTER:
	set(value):
		collision_coverage = clampi(value, CollisionCoverage.NEAR_CENTER, CollisionCoverage.ALL_CHUNKS)
		_refresh_collision_for_focus_if_needed()

## Collision mesh detail. Quarter is much cheaper than full terrain collision and is the default.
@export_enum("Full", "Half", "Quarter", "Eighth") var collision_quality: int = ViewportQuality.QUARTER:
	set(value):
		collision_quality = clampi(value, ViewportQuality.FULL, ViewportQuality.EIGHTH)
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

## Read-only flag that is true while chunks are being generated across frames.
@export var is_generating: bool:
	get:
		return _is_generating or _is_generating_collision
	set(_value):
		pass

@export_category("Generation Actions")

## Builds a fast, lower-detail terrain preview for tuning shape and noise settings.
@export_tool_button("Generate Preview") var generate_preview_button = generate_preview_now

## Builds the final terrain at the configured full resolution, locks it, and makes generated nodes save with the scene.
@export_tool_button("Generate Final") var generate_final_button = generate_final_now

## Stops the current progressive build and leaves already generated chunks visible.
@export_tool_button("Cancel Generation") var cancel_generation_button = cancel_generation

## Removes generated terrain chunks, unlocks the terrain, and resets the generation progress counters.
@export_tool_button("Clear Generated Terrain") var clear_terrain_button = clear_generated_terrain

## Removes generated collision bodies without clearing visual terrain, water, colors, or the final-terrain lock.
@export_tool_button("Remove Collision") var remove_collision_button = remove_generated_collision

## Adds collision to the current generated terrain without rebuilding visual chunks. Useful after a final build is already locked.
@export_tool_button("Generate Collision") var generate_collision_button = generate_collision_for_existing_terrain

## Saves existing generated chunk meshes and collision shapes to binary .res files to reduce the .tscn size.
@export_tool_button("Save Mesh Resources") var save_mesh_resources_button = externalize_generated_resources

var _noise := FastNoiseLite.new()
var _terrain_material: StandardMaterial3D
var _water_material: StandardMaterial3D

var _regeneration_queued := false
var _queued_generation_mode := GenerationMode.PREVIEW

var _pending_chunks: Array[Vector2i] = []
var _active_generation_mode := GenerationMode.PREVIEW
var _active_chunk_resolution := 64
var _active_total_resolution := 64
var _active_step := 1.0
var _active_half_size := 32.0
var _active_build_collision := false
var _active_display_stride := 1

var _generated_chunks := 0
var _total_chunks := 0
var _is_generating := false
var _pending_recolor_chunks: Array[MeshInstance3D] = []
var _is_recoloring := false
var _pending_collision_chunks: Array[MeshInstance3D] = []
var _collision_target_names: Dictionary = {}
var _is_generating_collision := false
var _last_automatic_lod_focus := Vector2.INF


func _ready() -> void:
	set_process(false)
	if final_terrain_locked and _has_generated_chunks():
		_update_water_plane()
		_update_automatic_lod_focus(true)
		_apply_viewport_culling()
		_update_processing_state()
		return
	_queue_regenerate(GenerationMode.PREVIEW)


func _process(_delta: float) -> void:
	if _is_generating:
		_build_next_chunks()
	elif _is_recoloring:
		_recolor_next_chunks()
	elif _is_generating_collision:
		_build_next_collision_chunks()
	else:
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
	_is_generating = false
	_cancel_collision_generation()
	_update_processing_state()


func clear_generated_terrain() -> void:
	cancel_generation()
	_cancel_recolor()
	final_terrain_locked = false
	_remove_legacy_v1_nodes()
	_remove_water_plane()

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


func externalize_generated_resources() -> void:
	if not _has_generated_chunks():
		push_warning("No generated terrain chunks were found to save as binary resources.")
		return

	var save_error := _save_generated_resources(true)
	if save_error != OK:
		push_warning("Could not save generated terrain resources. Error code: %d" % save_error)


func _queue_regenerate(requested_mode: int = -1, manual: bool = false) -> void:
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

	_queued_generation_mode = mode
	if _regeneration_queued:
		return

	_regeneration_queued = true
	call_deferred("_start_queued_generation")


func _start_queued_generation() -> void:
	_regeneration_queued = false
	_start_generation(_queued_generation_mode)


func _start_generation(mode: int) -> void:
	cancel_generation()
	_cancel_recolor()
	_configure_noise()
	_remove_legacy_v1_nodes()
	_update_water_plane()

	var chunks_root := _get_or_create_chunks_root()
	for child in chunks_root.get_children():
		chunks_root.remove_child(child)
		child.queue_free()

	_configure_active_generation_state(mode)
	_active_build_collision = _should_build_collision(mode)
	_active_display_stride = _get_viewport_display_stride()

	_pending_chunks.clear()
	for chunk_z in chunks_per_side:
		for chunk_x in chunks_per_side:
			_pending_chunks.append(Vector2i(chunk_x, chunk_z))

	_generated_chunks = 0
	_total_chunks = _pending_chunks.size()
	_is_generating = _total_chunks > 0

	if _is_generating:
		_update_processing_state()
		_build_next_chunks()
	else:
		_update_processing_state()


func _build_next_chunks() -> void:
	var chunks_root := _get_or_create_chunks_root()
	var material := _get_or_create_terrain_material()
	var build_count := mini(_get_chunks_per_frame(), _pending_chunks.size())

	for _build_index in build_count:
		var chunk_coordinates: Vector2i = _pending_chunks.pop_front()
		var chunk_mesh_instance := _create_chunk_mesh_instance(chunk_coordinates.x, chunk_coordinates.y, material)
		chunk_mesh_instance.mesh = _build_chunk_mesh(chunk_coordinates.x, chunk_coordinates.y, _active_display_stride)
		chunks_root.add_child(chunk_mesh_instance)
		_set_scene_owner(chunk_mesh_instance)

		if _active_build_collision and _chunk_is_in_collision_coverage(chunk_mesh_instance):
			_add_chunk_collision(chunk_mesh_instance, chunk_coordinates.x, chunk_coordinates.y)

		if _active_generation_mode == GenerationMode.FINAL and save_final_meshes_as_resources:
			var save_error := _save_chunk_lod_resources(chunk_mesh_instance, chunk_coordinates.x, chunk_coordinates.y)
			if save_error != OK:
				push_warning("Could not save chunk LOD resources. Error code: %d" % save_error)

		_generated_chunks += 1

	if _pending_chunks.is_empty():
		_is_generating = false
		if _active_generation_mode == GenerationMode.FINAL:
			if save_final_meshes_as_resources:
				var save_error := _save_generated_resources(false)
				if save_error != OK:
					push_warning("Could not save generated terrain resources. Error code: %d" % save_error)
			final_terrain_locked = true
			_make_generated_nodes_scene_owned()
		_update_processing_state()

	_apply_viewport_culling()


func _build_chunk_mesh(chunk_x: int, chunk_z: int, display_stride: int, add_skirts: bool = false) -> ArrayMesh:
	var local_grid_coordinates := _get_display_grid_coordinates(display_stride)
	var vertices_per_side := local_grid_coordinates.size()
	var vertex_total := vertices_per_side * vertices_per_side
	var start_grid_x := chunk_x * _active_chunk_resolution
	var start_grid_z := chunk_z * _active_chunk_resolution
	var heights := PackedFloat32Array()
	heights.resize(vertex_total)

	for display_z in vertices_per_side:
		for display_x in vertices_per_side:
			var local_grid_x := local_grid_coordinates[display_x]
			var local_grid_z := local_grid_coordinates[display_z]
			var global_x := start_grid_x + local_grid_x
			var global_z := start_grid_z + local_grid_z
			var vertex_index := _vertex_index(display_x, display_z, vertices_per_side)
			var world_x := float(global_x) * _active_step - _active_half_size
			var world_z := float(global_z) * _active_step - _active_half_size
			heights[vertex_index] = _sample_height(world_x, world_z)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	vertices.resize(vertex_total)
	normals.resize(vertex_total)
	uvs.resize(vertex_total)
	colors.resize(vertex_total)

	for display_z in vertices_per_side:
		for display_x in vertices_per_side:
			var local_grid_x := local_grid_coordinates[display_x]
			var local_grid_z := local_grid_coordinates[display_z]
			var global_x := start_grid_x + local_grid_x
			var global_z := start_grid_z + local_grid_z
			var vertex_index := _vertex_index(display_x, display_z, vertices_per_side)
			var world_x := float(global_x) * _active_step - _active_half_size
			var world_z := float(global_z) * _active_step - _active_half_size
			var height := heights[vertex_index]
			var normal := _sample_cached_normal(display_x, display_z, vertices_per_side, heights, world_x, world_z, display_stride)

			vertices[vertex_index] = Vector3(world_x, height, world_z)
			normals[vertex_index] = normal
			uvs[vertex_index] = Vector2(float(global_x) / float(_active_total_resolution), float(global_z) / float(_active_total_resolution))
			colors[vertex_index] = _color_for_terrain(height, normal)

	var indices := PackedInt32Array()
	var display_quads_per_side := vertices_per_side - 1
	indices.resize(display_quads_per_side * display_quads_per_side * 6)
	var index_write_position := 0

	for z in display_quads_per_side:
		for x in display_quads_per_side:
			var top_left := _vertex_index(x, z, vertices_per_side)
			var top_right := _vertex_index(x + 1, z, vertices_per_side)
			var bottom_left := _vertex_index(x, z + 1, vertices_per_side)
			var bottom_right := _vertex_index(x + 1, z + 1, vertices_per_side)

			index_write_position = _write_triangle(indices, index_write_position, top_left, top_right, bottom_left)
			index_write_position = _write_triangle(indices, index_write_position, top_right, bottom_right, bottom_left)

	if add_skirts:
		_append_skirts(vertices, normals, uvs, colors, indices, vertices_per_side, _get_skirt_depth(display_stride))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _configure_noise() -> void:
	_noise.seed = seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = noise_frequency
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = octaves
	_noise.fractal_lacunarity = lacunarity
	_noise.fractal_gain = gain


func _sample_height(world_x: float, world_z: float) -> float:
	return _noise.get_noise_2d(world_x, world_z) * height_scale


func _sample_cached_normal(
	local_x: int,
	local_z: int,
	vertices_per_side: int,
	heights: PackedFloat32Array,
	world_x: float,
	world_z: float,
	display_stride: int
) -> Vector3:
	var sample_distance := _active_step * float(display_stride)
	var left_height := _get_cached_or_sampled_height(local_x - 1, local_z, vertices_per_side, heights, world_x - sample_distance, world_z)
	var right_height := _get_cached_or_sampled_height(local_x + 1, local_z, vertices_per_side, heights, world_x + sample_distance, world_z)
	var back_height := _get_cached_or_sampled_height(local_x, local_z - 1, vertices_per_side, heights, world_x, world_z - sample_distance)
	var forward_height := _get_cached_or_sampled_height(local_x, local_z + 1, vertices_per_side, heights, world_x, world_z + sample_distance)
	return Vector3(left_height - right_height, sample_distance * 2.0, back_height - forward_height).normalized()


func _get_cached_or_sampled_height(
	local_x: int,
	local_z: int,
	vertices_per_side: int,
	heights: PackedFloat32Array,
	world_x: float,
	world_z: float
) -> float:
	if local_x >= 0 and local_x < vertices_per_side and local_z >= 0 and local_z < vertices_per_side:
		return heights[_vertex_index(local_x, local_z, vertices_per_side)]
	return _sample_height(world_x, world_z)


func _color_for_terrain(height: float, normal: Vector3) -> Color:
	var height_range := maxf(height_scale, 0.001)
	var normalized_height := clampf((height / height_range + 1.0) * 0.5, 0.0, 1.0)
	var color := lowland_color.lerp(grass_color, normalized_height)

	if water_enabled:
		var shore_width := maxf(height_scale * 0.10, 0.35)
		if height < water_level:
			var underwater_depth := water_level - height
			var seabed_amount := _smoothstep(0.0, maxf(height_scale * 0.35, 0.75), underwater_depth)
			color = shore_color.lerp(seabed_color, seabed_amount)
		elif height < water_level + shore_width:
			var dry_shore_amount := _smoothstep(0.0, shore_width, height - water_level)
			color = shore_color.lerp(color, dry_shore_amount)

	var slope := clampf(1.0 - normal.y, 0.0, 1.0)
	var rock_amount := _smoothstep(rock_slope_threshold, minf(1.0, rock_slope_threshold + 0.25), slope)
	color = color.lerp(rock_color, rock_amount)

	var snow_blend_width := maxf(height_scale * 0.12, 0.35)
	var snow_amount := _smoothstep(snow_height - snow_blend_width, snow_height + snow_blend_width, height)
	return color.lerp(snow_color, snow_amount)


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

	var mesh_resource_path := chunk.mesh.resource_path
	var arrays: Array = chunk.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors := PackedColorArray()
	colors.resize(vertices.size())

	for vertex_index in vertices.size():
		colors[vertex_index] = _color_for_terrain(vertices[vertex_index].y, normals[vertex_index])

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
	set_process(_is_generating or _is_recoloring or _is_generating_collision or _should_process_automatic_lod_focus())


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0

	var x := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


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
	var resource_directory := _get_generated_resource_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(resource_directory)
	if directory_error != OK:
		return directory_error

	var terrain_material := _get_or_create_terrain_material()
	var material_path := "%s/terrain_vertex_color_material.res" % resource_directory
	var material_error := ResourceSaver.save(terrain_material, material_path)
	if material_error != OK:
		return material_error

	var saved_material := load(material_path) as StandardMaterial3D
	if saved_material != null:
		terrain_material = saved_material
		_terrain_material = terrain_material

	for child in chunks_root.get_children():
		var chunk := child as MeshInstance3D
		if chunk == null:
			continue

		chunk.material_override = terrain_material
		if save_lods:
			var coordinates := _get_chunk_coordinates(chunk)
			var lod_error := _save_chunk_lod_resources(chunk, coordinates.x, coordinates.y)
			if lod_error != OK:
				return lod_error

		var collision_shape := chunk.get_node_or_null("CollisionBody/CollisionShape") as CollisionShape3D
		if collision_shape != null and collision_shape.shape != null:
			var shape_path := "%s/%s_collision_shape.res" % [resource_directory, chunk.name]
			var shape_error := ResourceSaver.save(collision_shape.shape, shape_path)
			if shape_error != OK:
				return shape_error

			var saved_shape := load(shape_path) as Shape3D
			if saved_shape != null:
				collision_shape.shape = saved_shape

	_apply_collision_visual_visibility()
	return OK


func _save_chunk_lod_resources(chunk: MeshInstance3D, chunk_x: int, chunk_z: int) -> int:
	var resource_directory := _get_generated_resource_directory()
	var directory_error := DirAccess.make_dir_recursive_absolute(resource_directory)
	if directory_error != OK:
		return directory_error

	for lod_index in LOD_STRIDES.size():
		var stride: int = LOD_STRIDES[lod_index]
		var lod_mesh := _build_chunk_mesh(chunk_x, chunk_z, stride, stride > 1)
		var mesh_path := _get_lod_mesh_path(chunk.name, lod_index)
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


func _get_lod_mesh_path(chunk_name: String, lod_index: int) -> String:
	var resource_directory := _get_generated_resource_directory()
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


func _get_display_grid_coordinates(display_stride: int) -> PackedInt32Array:
	var stride := maxi(1, display_stride)
	var coordinates := PackedInt32Array()
	var grid_coordinate := 0

	while grid_coordinate < _active_chunk_resolution:
		coordinates.append(grid_coordinate)
		grid_coordinate += stride

	coordinates.append(_active_chunk_resolution)
	return coordinates


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


func _update_automatic_lod_focus(force: bool = false) -> void:
	if not automatic_lod_focus or not viewport_lod_enabled or not is_inside_tree():
		return

	var focus := _get_automatic_lod_focus()
	if not focus.is_finite():
		return

	if not force and _last_automatic_lod_focus.is_finite():
		if focus.distance_to(_last_automatic_lod_focus) < lod_focus_update_distance:
			return

	_last_automatic_lod_focus = focus
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

	return Vector2.INF


func _has_automatic_lod_focus_source() -> bool:
	if get_node_or_null(lod_target_path) is Node3D:
		return true
	return get_viewport() != null and get_viewport().get_camera_3d() != null


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
			if distance_ratio > 0.70:
				lod_offset = 3
			elif distance_ratio > 0.35:
				lod_offset = 2
			elif distance_ratio > 0.15:
				lod_offset = 1
		_:
			if distance_ratio > 0.85:
				lod_offset = 3
			elif distance_ratio > 0.55:
				lod_offset = 2
			elif distance_ratio > 0.25:
				lod_offset = 1

	return clampi(cap_index + lod_offset, ViewportQuality.FULL, ViewportQuality.EIGHTH)


func _get_viewport_quality_lod_index() -> int:
	return clampi(viewport_quality, ViewportQuality.FULL, ViewportQuality.EIGHTH)


func _set_chunk_lod(chunk: MeshInstance3D, lod_index: int) -> void:
	lod_index = clampi(lod_index, ViewportQuality.FULL, ViewportQuality.EIGHTH)
	if int(chunk.get_meta("terrain_current_lod", -1)) == lod_index:
		return

	var mesh_path := str(chunk.get_meta(_get_lod_meta_key(lod_index), ""))
	if mesh_path.is_empty() and lod_index == 0 and chunk.mesh != null and not chunk.mesh.resource_path.is_empty():
		mesh_path = chunk.mesh.resource_path
	if mesh_path.is_empty():
		return

	var lod_mesh := load(mesh_path) as ArrayMesh
	if lod_mesh == null:
		return

	chunk.mesh = lod_mesh
	chunk.set_meta("terrain_current_lod", lod_index)


func _apply_collision_visual_visibility() -> void:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME)
	if chunks_root == null:
		return

	for chunk in chunks_root.get_children():
		for child in chunk.get_children():
			if child.name == "CollisionBody" or child is StaticBody3D:
				_set_collision_visual_visibility_recursive(child, collision_visuals_visible)


func _set_collision_visual_visibility_recursive(node: Node, visible: bool) -> void:
	var node_3d := node as Node3D
	if node_3d != null:
		node_3d.visible = visible
	for child in node.get_children():
		_set_collision_visual_visibility_recursive(child, visible)


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

	var water_plane := get_node_or_null(WATER_PLANE_NAME)
	if water_plane != null:
		_set_scene_owner_recursive(water_plane)


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


func _update_water_plane() -> void:
	if not is_inside_tree():
		return
	if not water_enabled:
		_remove_water_plane()
		return

	var water_plane := get_node_or_null(WATER_PLANE_NAME) as MeshInstance3D
	if water_plane == null:
		water_plane = MeshInstance3D.new()
		water_plane.name = WATER_PLANE_NAME
		add_child(water_plane)
		_set_scene_owner(water_plane)

	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(terrain_size, terrain_size)
	water_plane.mesh = water_mesh
	water_plane.position = Vector3(0.0, water_level, 0.0)
	water_plane.material_override = _get_or_create_water_material()


func _remove_water_plane() -> void:
	var water_plane := get_node_or_null(WATER_PLANE_NAME)
	if water_plane == null:
		return

	remove_child(water_plane)
	water_plane.queue_free()


func _vertex_index(x: int, z: int, vertices_per_side: int) -> int:
	return z * vertices_per_side + x


func _write_triangle(indices: PackedInt32Array, write_position: int, a: int, b: int, c: int) -> int:
	indices[write_position] = a
	indices[write_position + 1] = b
	indices[write_position + 2] = c
	return write_position + 3


func _append_skirts(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	vertices_per_side: int,
	skirt_depth: float
) -> void:
	for x in vertices_per_side - 1:
		_append_skirt_segment(vertices, normals, uvs, colors, indices, _vertex_index(x, 0, vertices_per_side), _vertex_index(x + 1, 0, vertices_per_side), skirt_depth)
		_append_skirt_segment(vertices, normals, uvs, colors, indices, _vertex_index(x + 1, vertices_per_side - 1, vertices_per_side), _vertex_index(x, vertices_per_side - 1, vertices_per_side), skirt_depth)

	for z in vertices_per_side - 1:
		_append_skirt_segment(vertices, normals, uvs, colors, indices, _vertex_index(0, z + 1, vertices_per_side), _vertex_index(0, z, vertices_per_side), skirt_depth)
		_append_skirt_segment(vertices, normals, uvs, colors, indices, _vertex_index(vertices_per_side - 1, z, vertices_per_side), _vertex_index(vertices_per_side - 1, z + 1, vertices_per_side), skirt_depth)


func _append_skirt_segment(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	top_a_index: int,
	top_b_index: int,
	skirt_depth: float
) -> void:
	var base_index := vertices.size()
	var top_a := vertices[top_a_index]
	var top_b := vertices[top_b_index]
	var bottom_a := top_a + Vector3.DOWN * skirt_depth
	var bottom_b := top_b + Vector3.DOWN * skirt_depth

	vertices.append(top_a)
	vertices.append(top_b)
	vertices.append(bottom_a)
	vertices.append(bottom_b)
	normals.append(normals[top_a_index])
	normals.append(normals[top_b_index])
	normals.append(normals[top_a_index])
	normals.append(normals[top_b_index])
	uvs.append(uvs[top_a_index])
	uvs.append(uvs[top_b_index])
	uvs.append(uvs[top_a_index])
	uvs.append(uvs[top_b_index])
	colors.append(colors[top_a_index])
	colors.append(colors[top_b_index])
	colors.append(colors[top_a_index])
	colors.append(colors[top_b_index])

	indices.append(base_index)
	indices.append(base_index + 2)
	indices.append(base_index + 1)
	indices.append(base_index + 1)
	indices.append(base_index + 2)
	indices.append(base_index + 3)
	indices.append(base_index)
	indices.append(base_index + 1)
	indices.append(base_index + 2)
	indices.append(base_index + 1)
	indices.append(base_index + 3)
	indices.append(base_index + 2)


func _get_skirt_depth(display_stride: int) -> float:
	return maxf(_active_step * float(maxi(1, display_stride)) * 2.0, maxf(height_scale * 0.05, 0.15))


func _get_or_create_chunks_root() -> Node3D:
	var chunks_root := get_node_or_null(TERRAIN_CHUNKS_NAME) as Node3D
	if chunks_root == null:
		chunks_root = Node3D.new()
		chunks_root.name = TERRAIN_CHUNKS_NAME
		add_child(chunks_root)
		_set_scene_owner(chunks_root)
	return chunks_root


func _create_chunk_mesh_instance(chunk_x: int, chunk_z: int, material: StandardMaterial3D) -> MeshInstance3D:
	var chunk_mesh_instance := MeshInstance3D.new()
	chunk_mesh_instance.name = "TerrainChunk_%02d_%02d" % [chunk_x, chunk_z]
	chunk_mesh_instance.material_override = material
	chunk_mesh_instance.set_meta("terrain_chunk_center", _get_chunk_center(chunk_x, chunk_z))
	chunk_mesh_instance.set_meta("terrain_chunk_x", chunk_x)
	chunk_mesh_instance.set_meta("terrain_chunk_z", chunk_z)
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
	collision_shape.shape = collision_mesh.create_trimesh_shape()
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
	collision_shape.shape = _build_chunk_mesh(chunk_x, chunk_z, collision_stride, collision_stride > 1).create_trimesh_shape()
	body.add_child(collision_shape)
	_set_scene_owner(collision_shape)


func _get_collision_mesh_for_chunk(chunk: MeshInstance3D) -> ArrayMesh:
	var lod_index := clampi(collision_quality, ViewportQuality.FULL, ViewportQuality.EIGHTH)
	var mesh_path := str(chunk.get_meta(_get_lod_meta_key(lod_index), ""))
	if not mesh_path.is_empty():
		var saved_lod_mesh := load(mesh_path) as ArrayMesh
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


func _get_or_create_terrain_material() -> StandardMaterial3D:
	if _terrain_material == null:
		_terrain_material = StandardMaterial3D.new()
		_terrain_material.vertex_color_use_as_albedo = true
		_terrain_material.roughness = 0.9
	return _terrain_material


func _get_or_create_water_material() -> StandardMaterial3D:
	if _water_material == null:
		_water_material = StandardMaterial3D.new()
		_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_water_material.roughness = 0.18
		_water_material.metallic = 0.0

	var color := water_color
	color.a = water_alpha
	_water_material.albedo_color = color
	return _water_material
