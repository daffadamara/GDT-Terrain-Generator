@tool
extends RefCounted
class_name TerrainMeshBuilder

var noise: FastNoiseLite
var active_chunk_resolution := 64
var active_total_resolution := 64
var active_step := 1.0
var active_half_size := 32.0
var height_scale := 5.0
var water_enabled := true
var water_level := 0.0
var snow_height := 5.0
var rock_slope_threshold := 0.44
var lowland_color := Color(0.15, 0.21, 0.09)
var grass_color := Color(0.24, 0.33, 0.15)
var shore_color := Color(0.52, 0.48, 0.30)
var seabed_color := Color(0.20, 0.17, 0.10)
var rock_color := Color(0.27, 0.24, 0.18)
var snow_color := Color(0.86, 0.84, 0.76)
var use_v5_masks := true


func configure(settings: Dictionary) -> void:
	noise = settings.get("noise", noise) as FastNoiseLite
	active_chunk_resolution = int(settings.get("active_chunk_resolution", active_chunk_resolution))
	active_total_resolution = int(settings.get("active_total_resolution", active_total_resolution))
	active_step = float(settings.get("active_step", active_step))
	active_half_size = float(settings.get("active_half_size", active_half_size))
	height_scale = float(settings.get("height_scale", height_scale))
	water_enabled = bool(settings.get("water_enabled", water_enabled))
	water_level = float(settings.get("water_level", water_level))
	snow_height = float(settings.get("snow_height", snow_height))
	rock_slope_threshold = float(settings.get("rock_slope_threshold", rock_slope_threshold))
	lowland_color = settings.get("lowland_color", lowland_color) as Color
	grass_color = settings.get("grass_color", grass_color) as Color
	shore_color = settings.get("shore_color", shore_color) as Color
	seabed_color = settings.get("seabed_color", seabed_color) as Color
	rock_color = settings.get("rock_color", rock_color) as Color
	snow_color = settings.get("snow_color", snow_color) as Color
	use_v5_masks = bool(settings.get("use_v5_masks", use_v5_masks))


func build_chunk_mesh(chunk_x: int, chunk_z: int, display_stride: int, add_skirts: bool = false) -> ArrayMesh:
	var local_grid_coordinates := _get_display_grid_coordinates(display_stride)
	var vertices_per_side := local_grid_coordinates.size()
	var vertex_total := vertices_per_side * vertices_per_side
	var start_grid_x := chunk_x * active_chunk_resolution
	var start_grid_z := chunk_z * active_chunk_resolution
	var heights := PackedFloat32Array()
	heights.resize(vertex_total)

	for display_z in vertices_per_side:
		for display_x in vertices_per_side:
			var local_grid_x := local_grid_coordinates[display_x]
			var local_grid_z := local_grid_coordinates[display_z]
			var global_x := start_grid_x + local_grid_x
			var global_z := start_grid_z + local_grid_z
			var vertex_index := _vertex_index(display_x, display_z, vertices_per_side)
			var world_x := float(global_x) * active_step - active_half_size
			var world_z := float(global_z) * active_step - active_half_size
			heights[vertex_index] = sample_height(world_x, world_z)

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
			var world_x := float(global_x) * active_step - active_half_size
			var world_z := float(global_z) * active_step - active_half_size
			var height := heights[vertex_index]
			var normal := _sample_cached_normal(display_x, display_z, vertices_per_side, heights, world_x, world_z, display_stride)

			vertices[vertex_index] = Vector3(world_x, height, world_z)
			normals[vertex_index] = normal
			uvs[vertex_index] = Vector2(float(global_x) / float(active_total_resolution), float(global_z) / float(active_total_resolution))
			colors[vertex_index] = mask_for_terrain(height, normal) if use_v5_masks else color_for_terrain(height, normal)

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


func sample_height(world_x: float, world_z: float) -> float:
	if noise == null:
		return 0.0
	return noise.get_noise_2d(world_x, world_z) * height_scale


func color_for_terrain(height: float, normal: Vector3) -> Color:
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


func mask_for_terrain(height: float, normal: Vector3) -> Color:
	var height_range := maxf(height_scale, 0.001)
	var normalized_height := clampf((height / height_range + 1.0) * 0.5, 0.0, 1.0)
	var slope := clampf(1.0 - normal.y, 0.0, 1.0)
	var shore_width := maxf(height_scale * 0.10, 0.35)
	var shore_or_seabed := 0.0

	if water_enabled:
		if height < water_level:
			shore_or_seabed = _smoothstep(0.0, maxf(height_scale * 0.35, 0.75), water_level - height)
		else:
			shore_or_seabed = 1.0 - _smoothstep(0.0, shore_width, height - water_level)

	var snow_blend_width := maxf(height_scale * 0.12, 0.35)
	var snow_amount := _smoothstep(snow_height - snow_blend_width, snow_height + snow_blend_width, height)
	return Color(normalized_height, slope, clampf(shore_or_seabed, 0.0, 1.0), snow_amount)


func _sample_cached_normal(
	local_x: int,
	local_z: int,
	vertices_per_side: int,
	heights: PackedFloat32Array,
	world_x: float,
	world_z: float,
	display_stride: int
) -> Vector3:
	var sample_distance := active_step * float(display_stride)
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
	return sample_height(world_x, world_z)


func _get_display_grid_coordinates(display_stride: int) -> PackedInt32Array:
	var stride := maxi(1, display_stride)
	var coordinates := PackedInt32Array()
	var grid_coordinate := 0

	while grid_coordinate < active_chunk_resolution:
		coordinates.append(grid_coordinate)
		grid_coordinate += stride

	coordinates.append(active_chunk_resolution)
	return coordinates


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
	return maxf(active_step * float(maxi(1, display_stride)) * 2.0, maxf(height_scale * 0.05, 0.15))


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0

	var x := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
