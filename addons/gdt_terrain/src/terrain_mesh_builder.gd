@tool
extends RefCounted
class_name TerrainMeshBuilder

var noise: FastNoiseLite
var heightfield: RefCounted
var active_chunk_resolution := 64
var active_total_resolution := 64
var active_step := 1.0
var active_half_size := 32.0
var height_scale := 2.0
var terrain_scale := 1.0
var snow_enabled := true
var snow_height := 5.0
var rock_slope_threshold := 0.44
var lowland_color := Color(0.15, 0.21, 0.09)
var grass_color := Color(0.24, 0.33, 0.15)
var rock_color := Color(0.27, 0.24, 0.18)
var snow_color := Color(0.86, 0.84, 0.76)
var use_v5_masks := true
const TERRAIN_PAINT_ENCODING_WEIGHTS_V1 := "paint_weights_v1"


func configure(settings: Dictionary) -> void:
	noise = settings.get("noise", noise) as FastNoiseLite
	heightfield = settings.get("heightfield", heightfield) as RefCounted
	active_chunk_resolution = int(settings.get("active_chunk_resolution", active_chunk_resolution))
	active_total_resolution = int(settings.get("active_total_resolution", active_total_resolution))
	active_step = float(settings.get("active_step", active_step))
	active_half_size = float(settings.get("active_half_size", active_half_size))
	height_scale = float(settings.get("height_scale", height_scale))
	terrain_scale = maxf(0.1, float(settings.get("terrain_scale", terrain_scale)))
	snow_enabled = bool(settings.get("snow_enabled", snow_enabled))
	snow_height = float(settings.get("snow_height", snow_height))
	rock_slope_threshold = float(settings.get("rock_slope_threshold", rock_slope_threshold))
	lowland_color = settings.get("lowland_color", lowland_color) as Color
	grass_color = settings.get("grass_color", grass_color) as Color
	rock_color = settings.get("rock_color", rock_color) as Color
	snow_color = settings.get("snow_color", snow_color) as Color
	use_v5_masks = bool(settings.get("use_v5_masks", use_v5_masks))


func build_chunk_mesh(chunk_x: int, chunk_z: int, display_stride: int, add_skirts: bool = false) -> ArrayMesh:
	return create_mesh_from_arrays(build_chunk_mesh_arrays(chunk_x, chunk_z, display_stride, add_skirts))


func create_mesh_from_arrays(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if use_v5_masks:
		mesh.set_meta("terrain_paint_encoding", TERRAIN_PAINT_ENCODING_WEIGHTS_V1)
	return mesh


func build_chunk_mesh_arrays(chunk_x: int, chunk_z: int, display_stride: int, add_skirts: bool = false) -> Array:
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
			heights[vertex_index] = sample_height_grid(global_x, global_z)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	vertices.resize(vertex_total)
	normals.resize(vertex_total)
	uvs.resize(vertex_total)
	uv2s.resize(vertex_total)
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
			var normal := _sample_cached_normal(display_x, display_z, vertices_per_side, heights, global_x, global_z, display_stride)

			vertices[vertex_index] = Vector3(world_x, height, world_z)
			normals[vertex_index] = normal
			uvs[vertex_index] = Vector2(float(global_x) / float(active_total_resolution), float(global_z) / float(active_total_resolution))
			uv2s[vertex_index] = Vector2.ZERO
			colors[vertex_index] = Color(0.0, 0.0, 0.0, 0.0) if use_v5_masks else color_for_terrain(height, normal)

	var indices := PackedInt32Array()
	var display_quads_per_side := vertices_per_side - 1
	indices.resize(display_quads_per_side * display_quads_per_side * 6)
	var index_write_position := 0

	for z in display_quads_per_side:
		for x in display_quads_per_side:
			if add_skirts and _quad_is_in_lod_edge_ring(x, z, display_quads_per_side):
				continue
			var top_left := _vertex_index(x, z, vertices_per_side)
			var top_right := _vertex_index(x + 1, z, vertices_per_side)
			var bottom_left := _vertex_index(x, z + 1, vertices_per_side)
			var bottom_right := _vertex_index(x + 1, z + 1, vertices_per_side)

			index_write_position = _write_triangle(indices, index_write_position, top_left, top_right, bottom_left)
			index_write_position = _write_triangle(indices, index_write_position, top_right, bottom_right, bottom_left)

	if add_skirts:
		if index_write_position < indices.size():
			indices.resize(index_write_position)
		_append_lod_edge_stitching(vertices, normals, uvs, uv2s, colors, indices, chunk_x, chunk_z, display_stride)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if use_v5_masks:
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	return arrays


func sample_height(world_x: float, world_z: float) -> float:
	if heightfield != null and heightfield.is_valid():
		return heightfield.sample_world(world_x, world_z)
	if noise == null:
		return 0.0
	return noise.get_noise_2d(world_x / terrain_scale, world_z / terrain_scale) * height_scale


func sample_height_grid(grid_x: int, grid_z: int) -> float:
	if heightfield != null and heightfield.is_valid():
		return heightfield.sample_grid(grid_x, grid_z)
	var world_x := float(grid_x) * active_step - active_half_size
	var world_z := float(grid_z) * active_step - active_half_size
	return sample_height(world_x, world_z)


func color_for_terrain(height: float, normal: Vector3) -> Color:
	var height_range := maxf(height_scale, 0.001)
	var normalized_height := clampf((height / height_range + 1.0) * 0.5, 0.0, 1.0)
	var color := lowland_color.lerp(grass_color, normalized_height)

	var slope := clampf(1.0 - normal.y, 0.0, 1.0)
	var rock_amount := _smoothstep(rock_slope_threshold, minf(1.0, rock_slope_threshold + 0.25), slope)
	color = color.lerp(rock_color, rock_amount)

	var snow_blend_width := maxf(height_scale * 0.12, 0.35)
	var snow_amount := _smoothstep(snow_height - snow_blend_width, snow_height + snow_blend_width, height) if snow_enabled else 0.0
	return color.lerp(snow_color, snow_amount)


func mask_for_terrain(height: float, normal: Vector3) -> Color:
	var height_range := maxf(height_scale, 0.001)
	var normalized_height := clampf((height / height_range + 1.0) * 0.5, 0.0, 1.0)
	var slope := clampf(1.0 - normal.y, 0.0, 1.0)

	var snow_blend_width := maxf(height_scale * 0.12, 0.35)
	var snow_amount := _smoothstep(snow_height - snow_blend_width, snow_height + snow_blend_width, height) if snow_enabled else 0.0
	return Color(normalized_height, slope, 0.0, snow_amount)


func _sample_cached_normal(
	local_x: int,
	local_z: int,
	vertices_per_side: int,
	heights: PackedFloat32Array,
	grid_x: int,
	grid_z: int,
	display_stride: int
) -> Vector3:
	var sample_distance := active_step * float(display_stride)
	var left_height := _get_cached_or_sampled_height(local_x - 1, local_z, vertices_per_side, heights, grid_x - display_stride, grid_z)
	var right_height := _get_cached_or_sampled_height(local_x + 1, local_z, vertices_per_side, heights, grid_x + display_stride, grid_z)
	var back_height := _get_cached_or_sampled_height(local_x, local_z - 1, vertices_per_side, heights, grid_x, grid_z - display_stride)
	var forward_height := _get_cached_or_sampled_height(local_x, local_z + 1, vertices_per_side, heights, grid_x, grid_z + display_stride)
	return Vector3(left_height - right_height, sample_distance * 2.0, back_height - forward_height).normalized()


func _get_cached_or_sampled_height(
	local_x: int,
	local_z: int,
	vertices_per_side: int,
	heights: PackedFloat32Array,
	grid_x: int,
	grid_z: int
) -> float:
	if local_x >= 0 and local_x < vertices_per_side and local_z >= 0 and local_z < vertices_per_side:
		return heights[_vertex_index(local_x, local_z, vertices_per_side)]
	return sample_height_grid(grid_x, grid_z)


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


func _quad_is_in_lod_edge_ring(x: int, z: int, quads_per_side: int) -> bool:
	return x == 0 or z == 0 or x == quads_per_side - 1 or z == quads_per_side - 1


func _append_lod_edge_stitching(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	chunk_x: int,
	chunk_z: int,
	display_stride: int
) -> void:
	var stride := maxi(1, display_stride)
	if active_chunk_resolution <= stride:
		return
	var start_grid_x := chunk_x * active_chunk_resolution
	var start_grid_z := chunk_z * active_chunk_resolution
	var end_grid_x := start_grid_x + active_chunk_resolution
	var end_grid_z := start_grid_z + active_chunk_resolution

	for x in range(start_grid_x, end_grid_x, stride):
		_append_lod_stitch_segment_horizontal(
			vertices,
			normals,
			uvs,
			uv2s,
			colors,
			indices,
			Vector2i(x, start_grid_z),
			Vector2i(x + stride, start_grid_z),
			Vector2i(x, start_grid_z + stride),
			Vector2i(x + stride, start_grid_z + stride),
			stride,
			true,
			false
		)
		_append_lod_stitch_segment_horizontal(
			vertices,
			normals,
			uvs,
			uv2s,
			colors,
			indices,
			Vector2i(x, end_grid_z - stride),
			Vector2i(x + stride, end_grid_z - stride),
			Vector2i(x, end_grid_z),
			Vector2i(x + stride, end_grid_z),
			stride,
			false,
			true
		)

	for z in range(start_grid_z + stride, end_grid_z - stride, stride):
		_append_lod_stitch_segment_vertical(
			vertices,
			normals,
			uvs,
			uv2s,
			colors,
			indices,
			Vector2i(start_grid_x, z),
			Vector2i(start_grid_x + stride, z),
			Vector2i(start_grid_x, z + stride),
			Vector2i(start_grid_x + stride, z + stride),
			stride,
			true,
			false
		)
		_append_lod_stitch_segment_vertical(
			vertices,
			normals,
			uvs,
			uv2s,
			colors,
			indices,
			Vector2i(end_grid_x - stride, z),
			Vector2i(end_grid_x, z),
			Vector2i(end_grid_x - stride, z + stride),
			Vector2i(end_grid_x, z + stride),
			stride,
			false,
			true
		)


func _append_lod_stitch_segment_horizontal(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	top_left_grid: Vector2i,
	top_right_grid: Vector2i,
	bottom_left_grid: Vector2i,
	bottom_right_grid: Vector2i,
	stride: int,
	top_is_detailed_edge: bool,
	bottom_is_detailed_edge: bool
) -> void:
	var top_left := _terrain_vertex_from_grid(top_left_grid.x, top_left_grid.y)
	var top_right := _terrain_vertex_from_grid(top_right_grid.x, top_right_grid.y)
	var bottom_left := _terrain_vertex_from_grid(bottom_left_grid.x, bottom_left_grid.y)
	var bottom_right := _terrain_vertex_from_grid(bottom_right_grid.x, bottom_right_grid.y)

	for step_index in stride:
		var start_t := float(step_index) / float(stride)
		var end_t := float(step_index + 1) / float(stride)
		var top_a_grid := _lerp_grid(top_left_grid, top_right_grid, start_t)
		var top_b_grid := _lerp_grid(top_left_grid, top_right_grid, end_t)
		var bottom_a_grid := _lerp_grid(bottom_left_grid, bottom_right_grid, start_t)
		var bottom_b_grid := _lerp_grid(bottom_left_grid, bottom_right_grid, end_t)
		var top_a := _terrain_vertex_from_grid(roundi(top_a_grid.x), roundi(top_a_grid.y)) if top_is_detailed_edge else top_left.lerp(top_right, start_t)
		var top_b := _terrain_vertex_from_grid(roundi(top_b_grid.x), roundi(top_b_grid.y)) if top_is_detailed_edge else top_left.lerp(top_right, end_t)
		var bottom_a := _terrain_vertex_from_grid(roundi(bottom_a_grid.x), roundi(bottom_a_grid.y)) if bottom_is_detailed_edge else bottom_left.lerp(bottom_right, start_t)
		var bottom_b := _terrain_vertex_from_grid(roundi(bottom_b_grid.x), roundi(bottom_b_grid.y)) if bottom_is_detailed_edge else bottom_left.lerp(bottom_right, end_t)
		var top_a_index := _append_surface_vertex(vertices, normals, uvs, uv2s, colors, top_a, top_a_grid)
		var top_b_index := _append_surface_vertex(vertices, normals, uvs, uv2s, colors, top_b, top_b_grid)
		var bottom_a_index := _append_surface_vertex(vertices, normals, uvs, uv2s, colors, bottom_a, bottom_a_grid)
		var bottom_b_index := _append_surface_vertex(vertices, normals, uvs, uv2s, colors, bottom_b, bottom_b_grid)

		indices.append(top_a_index)
		indices.append(top_b_index)
		indices.append(bottom_a_index)
		indices.append(top_b_index)
		indices.append(bottom_b_index)
		indices.append(bottom_a_index)


func _append_lod_stitch_segment_vertical(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	top_left_grid: Vector2i,
	top_right_grid: Vector2i,
	bottom_left_grid: Vector2i,
	bottom_right_grid: Vector2i,
	stride: int,
	left_is_detailed_edge: bool,
	right_is_detailed_edge: bool
) -> void:
	var top_left := _terrain_vertex_from_grid(top_left_grid.x, top_left_grid.y)
	var top_right := _terrain_vertex_from_grid(top_right_grid.x, top_right_grid.y)
	var bottom_left := _terrain_vertex_from_grid(bottom_left_grid.x, bottom_left_grid.y)
	var bottom_right := _terrain_vertex_from_grid(bottom_right_grid.x, bottom_right_grid.y)

	for step_index in stride:
		var start_t := float(step_index) / float(stride)
		var end_t := float(step_index + 1) / float(stride)
		var left_a_grid := _lerp_grid(top_left_grid, bottom_left_grid, start_t)
		var left_b_grid := _lerp_grid(top_left_grid, bottom_left_grid, end_t)
		var right_a_grid := _lerp_grid(top_right_grid, bottom_right_grid, start_t)
		var right_b_grid := _lerp_grid(top_right_grid, bottom_right_grid, end_t)
		var left_a := _terrain_vertex_from_grid(roundi(left_a_grid.x), roundi(left_a_grid.y)) if left_is_detailed_edge else top_left.lerp(bottom_left, start_t)
		var left_b := _terrain_vertex_from_grid(roundi(left_b_grid.x), roundi(left_b_grid.y)) if left_is_detailed_edge else top_left.lerp(bottom_left, end_t)
		var right_a := _terrain_vertex_from_grid(roundi(right_a_grid.x), roundi(right_a_grid.y)) if right_is_detailed_edge else top_right.lerp(bottom_right, start_t)
		var right_b := _terrain_vertex_from_grid(roundi(right_b_grid.x), roundi(right_b_grid.y)) if right_is_detailed_edge else top_right.lerp(bottom_right, end_t)
		var left_a_index := _append_surface_vertex(vertices, normals, uvs, uv2s, colors, left_a, left_a_grid)
		var right_a_index := _append_surface_vertex(vertices, normals, uvs, uv2s, colors, right_a, right_a_grid)
		var left_b_index := _append_surface_vertex(vertices, normals, uvs, uv2s, colors, left_b, left_b_grid)
		var right_b_index := _append_surface_vertex(vertices, normals, uvs, uv2s, colors, right_b, right_b_grid)

		indices.append(left_a_index)
		indices.append(right_a_index)
		indices.append(left_b_index)
		indices.append(right_a_index)
		indices.append(right_b_index)
		indices.append(left_b_index)


func _append_surface_vertex(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	colors: PackedColorArray,
	vertex: Vector3,
	grid_position: Vector2
) -> int:
	var normal := _sample_normal_for_grid(roundi(grid_position.x), roundi(grid_position.y), 1)
	var vertex_index := vertices.size()
	vertices.append(vertex)
	normals.append(normal)
	uvs.append(Vector2(grid_position.x / float(active_total_resolution), grid_position.y / float(active_total_resolution)))
	if use_v5_masks:
		uv2s.append(Vector2.ZERO)
		colors.append(Color(0.0, 0.0, 0.0, 0.0))
	else:
		colors.append(color_for_terrain(vertex.y, normal))
	return vertex_index


func _lerp_grid(from_grid: Vector2i, to_grid: Vector2i, weight: float) -> Vector2:
	return Vector2(lerpf(float(from_grid.x), float(to_grid.x), weight), lerpf(float(from_grid.y), float(to_grid.y), weight))


func _terrain_vertex_from_grid(grid_x: int, grid_z: int) -> Vector3:
	var world_x := float(grid_x) * active_step - active_half_size
	var world_z := float(grid_z) * active_step - active_half_size
	return Vector3(world_x, sample_height_grid(grid_x, grid_z), world_z)


func _sample_normal_for_grid(grid_x: int, grid_z: int, sample_stride: int) -> Vector3:
	var sample_distance := active_step * float(maxi(1, sample_stride))
	var grid_stride := maxi(1, sample_stride)
	var left_height := sample_height_grid(grid_x - grid_stride, grid_z)
	var right_height := sample_height_grid(grid_x + grid_stride, grid_z)
	var back_height := sample_height_grid(grid_x, grid_z - grid_stride)
	var forward_height := sample_height_grid(grid_x, grid_z + grid_stride)
	return Vector3(left_height - right_height, sample_distance * 2.0, back_height - forward_height).normalized()


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if is_equal_approx(edge0, edge1):
		return 0.0

	var x := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
