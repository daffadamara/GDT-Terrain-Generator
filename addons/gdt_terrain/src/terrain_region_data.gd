@tool
extends Resource
class_name TerrainRegionData

@export var region_coordinates := Vector2i.ZERO
@export var chunk_name := ""
@export var resolution := 0
@export var terrain_size := 64.0
@export var world_min := Vector2.ZERO
@export var world_max := Vector2.ZERO
@export var height_samples := PackedFloat32Array()
@export var sculpt_height_deltas := PackedFloat32Array()
@export var painted_material_masks := PackedColorArray()
@export var painted_material_mask_extra := PackedVector2Array()
@export var lod_mesh_paths := PackedStringArray()


func is_valid() -> bool:
	var expected_side := resolution + 1
	return resolution > 0 and height_samples.size() == expected_side * expected_side


func contains_world_position(world_position: Vector3) -> bool:
	return world_position.x >= world_min.x and world_position.x <= world_max.x and world_position.z >= world_min.y and world_position.z <= world_max.y


func sample_height(world_x: float, world_z: float) -> float:
	if not is_valid():
		return NAN
	var grid := _world_to_grid(world_x, world_z)
	return sample_sculpted_grid_bilinear(grid.x, grid.y)


func sample_sculpted_height(world_x: float, world_z: float) -> float:
	if not is_valid():
		return NAN
	var grid := _world_to_grid(world_x, world_z)
	return sample_sculpted_grid_bilinear(grid.x, grid.y)


func sample_grid_bilinear(grid_x: float, grid_z: float) -> float:
	if not is_valid():
		return NAN
	var side := resolution + 1
	var x0 := clampi(floori(grid_x), 0, side - 1)
	var z0 := clampi(floori(grid_z), 0, side - 1)
	var x1 := clampi(x0 + 1, 0, side - 1)
	var z1 := clampi(z0 + 1, 0, side - 1)
	var tx := clampf(grid_x - float(x0), 0.0, 1.0)
	var tz := clampf(grid_z - float(z0), 0.0, 1.0)
	var top := lerpf(_sample_grid(x0, z0), _sample_grid(x1, z0), tx)
	var bottom := lerpf(_sample_grid(x0, z1), _sample_grid(x1, z1), tx)
	return lerpf(top, bottom, tz)


func sample_sculpted_grid_bilinear(grid_x: float, grid_z: float) -> float:
	if not is_valid():
		return NAN
	var side := resolution + 1
	var x0 := clampi(floori(grid_x), 0, side - 1)
	var z0 := clampi(floori(grid_z), 0, side - 1)
	var x1 := clampi(x0 + 1, 0, side - 1)
	var z1 := clampi(z0 + 1, 0, side - 1)
	var tx := clampf(grid_x - float(x0), 0.0, 1.0)
	var tz := clampf(grid_z - float(z0), 0.0, 1.0)
	var top := lerpf(get_sculpted_height_grid(x0, z0), get_sculpted_height_grid(x1, z0), tx)
	var bottom := lerpf(get_sculpted_height_grid(x0, z1), get_sculpted_height_grid(x1, z1), tx)
	return lerpf(top, bottom, tz)


func sample_normal(world_x: float, world_z: float) -> Vector3:
	if not is_valid():
		return Vector3.UP
	var step := _grid_step()
	var left_height := sample_sculpted_height(world_x - step, world_z)
	var right_height := sample_sculpted_height(world_x + step, world_z)
	var back_height := sample_sculpted_height(world_x, world_z - step)
	var forward_height := sample_sculpted_height(world_x, world_z + step)
	if is_nan(left_height) or is_nan(right_height) or is_nan(back_height) or is_nan(forward_height):
		return Vector3.UP
	return Vector3(left_height - right_height, step * 2.0, back_height - forward_height).normalized()


func ensure_sculpt_storage() -> void:
	_ensure_sculpt_storage()


func clear_sculpt_deltas() -> void:
	sculpt_height_deltas = PackedFloat32Array()


func set_sculpt_delta_grid(x: int, z: int, value: float) -> void:
	var side := resolution + 1
	if side <= 1:
		return
	_ensure_sculpt_storage()
	sculpt_height_deltas[_index(clampi(x, 0, side - 1), clampi(z, 0, side - 1))] = value


func get_sculpt_delta_grid(x: int, z: int) -> float:
	var side := resolution + 1
	if sculpt_height_deltas.size() != side * side:
		return 0.0
	return sculpt_height_deltas[_index(clampi(x, 0, side - 1), clampi(z, 0, side - 1))]


func get_base_height_grid(x: int, z: int) -> float:
	var side := resolution + 1
	if height_samples.size() != side * side:
		return 0.0
	return height_samples[_index(clampi(x, 0, side - 1), clampi(z, 0, side - 1))]


func get_sculpted_height_grid(x: int, z: int) -> float:
	return get_base_height_grid(x, z) + get_sculpt_delta_grid(x, z)


func set_painted_mask_grid(x: int, z: int, value: Color, extra: Vector2 = Vector2.ZERO) -> void:
	var side := resolution + 1
	if side <= 1:
		return
	_ensure_painted_mask_storage()
	var index := _index(clampi(x, 0, side - 1), clampi(z, 0, side - 1))
	painted_material_masks[index] = value
	painted_material_mask_extra[index] = extra


func get_painted_mask_grid(x: int, z: int) -> Color:
	var side := resolution + 1
	if painted_material_masks.size() != side * side:
		return Color(0.0, 0.0, 0.0, 0.0)
	return painted_material_masks[_index(clampi(x, 0, side - 1), clampi(z, 0, side - 1))]


func get_painted_mask_extra_grid(x: int, z: int) -> Vector2:
	var side := resolution + 1
	if painted_material_mask_extra.size() != side * side:
		return Vector2.ZERO
	return painted_material_mask_extra[_index(clampi(x, 0, side - 1), clampi(z, 0, side - 1))]


func get_painted_weights_grid(x: int, z: int) -> PackedFloat32Array:
	var color := get_painted_mask_grid(x, z)
	var extra := get_painted_mask_extra_grid(x, z)
	var weights := PackedFloat32Array()
	weights.resize(6)
	weights[0] = clampf(color.r, 0.0, 1.0)
	weights[1] = clampf(color.g, 0.0, 1.0)
	weights[2] = clampf(color.b, 0.0, 1.0)
	weights[3] = clampf(color.a, 0.0, 1.0)
	weights[4] = clampf(extra.x, 0.0, 1.0)
	weights[5] = clampf(extra.y, 0.0, 1.0)
	return weights


func sample_painted_weights(world_x: float, world_z: float) -> PackedFloat32Array:
	var grid := _world_to_grid(world_x, world_z)
	return sample_painted_weights_grid(grid.x, grid.y)


func sample_painted_weights_grid(grid_x: float, grid_z: float) -> PackedFloat32Array:
	var side := resolution + 1
	var result := PackedFloat32Array()
	result.resize(6)
	if side <= 1 or painted_material_masks.size() != side * side:
		return result
	var x0 := clampi(floori(grid_x), 0, side - 1)
	var z0 := clampi(floori(grid_z), 0, side - 1)
	var x1 := clampi(x0 + 1, 0, side - 1)
	var z1 := clampi(z0 + 1, 0, side - 1)
	var tx := clampf(grid_x - float(x0), 0.0, 1.0)
	var tz := clampf(grid_z - float(z0), 0.0, 1.0)

	var top_left_color := get_painted_mask_grid(x0, z0)
	var top_right_color := get_painted_mask_grid(x1, z0)
	var bottom_left_color := get_painted_mask_grid(x0, z1)
	var bottom_right_color := get_painted_mask_grid(x1, z1)
	var top_color := top_left_color.lerp(top_right_color, tx)
	var bottom_color := bottom_left_color.lerp(bottom_right_color, tx)
	var color := top_color.lerp(bottom_color, tz)

	var top_left_extra := get_painted_mask_extra_grid(x0, z0)
	var top_right_extra := get_painted_mask_extra_grid(x1, z0)
	var bottom_left_extra := get_painted_mask_extra_grid(x0, z1)
	var bottom_right_extra := get_painted_mask_extra_grid(x1, z1)
	var top_extra := top_left_extra.lerp(top_right_extra, tx)
	var bottom_extra := bottom_left_extra.lerp(bottom_right_extra, tx)
	var extra := top_extra.lerp(bottom_extra, tz)

	result[0] = clampf(color.r, 0.0, 1.0)
	result[1] = clampf(color.g, 0.0, 1.0)
	result[2] = clampf(color.b, 0.0, 1.0)
	result[3] = clampf(color.a, 0.0, 1.0)
	result[4] = clampf(extra.x, 0.0, 1.0)
	result[5] = clampf(extra.y, 0.0, 1.0)
	return result


func world_to_grid(world_x: float, world_z: float) -> Vector2:
	return _world_to_grid(world_x, world_z)


func _world_to_grid(world_x: float, world_z: float) -> Vector2:
	var size_x := maxf(world_max.x - world_min.x, 0.001)
	var size_z := maxf(world_max.y - world_min.y, 0.001)
	return Vector2(
		clampf((world_x - world_min.x) / size_x, 0.0, 1.0) * float(resolution),
		clampf((world_z - world_min.y) / size_z, 0.0, 1.0) * float(resolution)
	)


func _sample_grid(x: int, z: int) -> float:
	return height_samples[_index(x, z)]


func _index(x: int, z: int) -> int:
	return z * (resolution + 1) + x


func _grid_step() -> float:
	return maxf(world_max.x - world_min.x, world_max.y - world_min.y) / float(maxi(1, resolution))


func _ensure_painted_mask_storage() -> void:
	var expected_size := (resolution + 1) * (resolution + 1)
	if painted_material_masks.size() != expected_size:
		painted_material_masks.resize(expected_size)
		for index in expected_size:
			painted_material_masks[index] = Color(0.0, 0.0, 0.0, 0.0)
	if painted_material_mask_extra.size() != expected_size:
		painted_material_mask_extra.resize(expected_size)
		for index in expected_size:
			painted_material_mask_extra[index] = Vector2.ZERO


func _ensure_sculpt_storage() -> void:
	var expected_size := (resolution + 1) * (resolution + 1)
	if sculpt_height_deltas.size() == expected_size:
		return
	var previous := sculpt_height_deltas
	sculpt_height_deltas = PackedFloat32Array()
	sculpt_height_deltas.resize(expected_size)
	var copy_count := mini(previous.size(), expected_size)
	for index in copy_count:
		sculpt_height_deltas[index] = previous[index]
