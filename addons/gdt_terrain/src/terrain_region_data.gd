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
@export var painted_material_masks := PackedColorArray()
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
	return sample_grid_bilinear(grid.x, grid.y)


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


func sample_normal(world_x: float, world_z: float) -> Vector3:
	if not is_valid():
		return Vector3.UP
	var step := _grid_step()
	var left_height := sample_height(world_x - step, world_z)
	var right_height := sample_height(world_x + step, world_z)
	var back_height := sample_height(world_x, world_z - step)
	var forward_height := sample_height(world_x, world_z + step)
	if is_nan(left_height) or is_nan(right_height) or is_nan(back_height) or is_nan(forward_height):
		return Vector3.UP
	return Vector3(left_height - right_height, step * 2.0, back_height - forward_height).normalized()


func set_painted_mask_grid(x: int, z: int, value: Color) -> void:
	var side := resolution + 1
	if side <= 1:
		return
	if painted_material_masks.size() != side * side:
		painted_material_masks.resize(side * side)
		for index in painted_material_masks.size():
			painted_material_masks[index] = Color(0.0, 0.0, 0.0, 0.0)
	painted_material_masks[_index(clampi(x, 0, side - 1), clampi(z, 0, side - 1))] = value


func get_painted_mask_grid(x: int, z: int) -> Color:
	var side := resolution + 1
	if painted_material_masks.size() != side * side:
		return Color(0.0, 0.0, 0.0, 0.0)
	return painted_material_masks[_index(clampi(x, 0, side - 1), clampi(z, 0, side - 1))]


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
