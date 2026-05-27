@tool
extends Node3D
class_name GdtTerrainQuery

const TERRAIN_SCRIPT := preload("res://addons/gdt_terrain/src/gdt_terrain_3d.gd")
const MATERIAL_LAYER_NAMES := ["Lowland", "Ground", "Upper", "Rocky", "Cliff", "Snow"]

## Optional explicit terrain node. Leave empty to auto-find the nearest GdtTerrain3D.
@export var terrain_path: NodePath:
	set(value):
		terrain_path = value
		_terrain_cache = null

## Finds a GdtTerrain3D in parents first, then in the current scene.
@export var auto_find_terrain := true:
	set(value):
		auto_find_terrain = value
		_terrain_cache = null

var _terrain_cache: Node


func _ready() -> void:
	_resolve_terrain()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		_terrain_cache = null


func set_terrain(terrain: Node) -> void:
	if terrain != null and is_inside_tree() and terrain.is_inside_tree():
		terrain_path = get_path_to(terrain)
	else:
		terrain_path = NodePath()
	_terrain_cache = terrain if _is_terrain_node(terrain) else null


func get_terrain() -> Node:
	return _resolve_terrain()


func has_valid_terrain() -> bool:
	return _resolve_terrain() != null


func has_terrain_at(world_position: Vector3) -> bool:
	var terrain := _resolve_terrain()
	return terrain != null and bool(terrain.has_terrain_at(world_position))


func get_height_at(world_position: Vector3, fallback: float = NAN) -> float:
	var terrain := _resolve_terrain()
	if terrain == null:
		return fallback
	var height := float(terrain.get_height_at(world_position))
	return fallback if is_nan(height) else height


func get_normal_at(world_position: Vector3, fallback: Vector3 = Vector3.UP) -> Vector3:
	var terrain := _resolve_terrain()
	if terrain == null or not bool(terrain.has_terrain_at(world_position)):
		return fallback
	return Vector3(terrain.get_normal_at(world_position)).normalized()


func get_slope_at(world_position: Vector3, fallback: float = NAN) -> float:
	var terrain := _resolve_terrain()
	if terrain == null:
		return fallback
	var slope := float(terrain.get_slope_at(world_position))
	return fallback if is_nan(slope) else slope


func project_position_to_terrain(world_position: Vector3, y_offset: float = 0.0) -> Vector3:
	var terrain := _resolve_terrain()
	if terrain == null:
		return world_position
	return terrain.project_position_to_terrain(world_position, y_offset)


func get_region_at(world_position: Vector3) -> Resource:
	var terrain := _resolve_terrain()
	return terrain.get_region_at(world_position) if terrain != null else null


func get_painted_material_weights_at(world_position: Vector3) -> PackedFloat32Array:
	var terrain := _resolve_terrain()
	if terrain != null and terrain.has_method("get_painted_material_weights_at"):
		return terrain.get_painted_material_weights_at(world_position)
	return _empty_material_weights()


func get_dominant_painted_material_layer_at(world_position: Vector3) -> int:
	var terrain := _resolve_terrain()
	if terrain != null and terrain.has_method("get_dominant_painted_material_layer_at"):
		return int(terrain.get_dominant_painted_material_layer_at(world_position))
	return -1


func get_dominant_painted_material_layer_name_at(world_position: Vector3) -> String:
	var layer := get_dominant_painted_material_layer_at(world_position)
	return _get_material_layer_name(layer)


func get_ground_info(world_position: Vector3, y_offset: float = 0.0) -> Dictionary:
	var terrain := _resolve_terrain()
	if terrain == null or not bool(terrain.has_terrain_at(world_position)):
		return {
			"valid": false,
			"position": world_position,
			"height": NAN,
			"normal": Vector3.UP,
			"slope": NAN,
			"region": null,
			"painted_material_weights": _empty_material_weights(),
			"dominant_painted_material_layer": -1,
			"dominant_painted_material_layer_name": "",
		}

	var projected: Vector3 = terrain.project_position_to_terrain(world_position, y_offset)
	var painted_weights: PackedFloat32Array = terrain.get_painted_material_weights_at(world_position) if terrain.has_method("get_painted_material_weights_at") else _empty_material_weights()
	var layer := _get_dominant_layer_from_weights(painted_weights)
	return {
		"valid": true,
		"position": projected,
		"height": projected.y - y_offset,
		"normal": Vector3(terrain.get_normal_at(world_position)).normalized(),
		"slope": float(terrain.get_slope_at(world_position)),
		"region": terrain.get_region_at(world_position),
		"painted_material_weights": painted_weights,
		"dominant_painted_material_layer": layer,
		"dominant_painted_material_layer_name": _get_material_layer_name(layer),
	}


func _empty_material_weights() -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	weights.resize(MATERIAL_LAYER_NAMES.size())
	return weights


func _get_dominant_layer_from_weights(weights: PackedFloat32Array) -> int:
	var best_layer := -1
	var best_weight := 0.0
	for layer in mini(weights.size(), MATERIAL_LAYER_NAMES.size()):
		var weight := float(weights[layer])
		if weight > best_weight:
			best_weight = weight
			best_layer = layer
	return best_layer


func _get_material_layer_name(layer: int) -> String:
	if layer < 0 or layer >= MATERIAL_LAYER_NAMES.size():
		return ""
	return MATERIAL_LAYER_NAMES[layer]


func _resolve_terrain() -> Node:
	if _is_terrain_node(_terrain_cache):
		return _terrain_cache

	if not terrain_path.is_empty():
		var explicit := get_node_or_null(terrain_path)
		if _is_terrain_node(explicit):
			_terrain_cache = explicit
			return _terrain_cache

	if not auto_find_terrain:
		return null

	var parent := get_parent()
	while parent != null:
		if _is_terrain_node(parent):
			_terrain_cache = parent
			return _terrain_cache
		parent = parent.get_parent()

	var tree := get_tree()
	var root := tree.current_scene if tree != null else null
	_terrain_cache = _find_terrain_recursive(root)
	return _terrain_cache


func _find_terrain_recursive(node: Node) -> Node:
	if node == null:
		return null
	if _is_terrain_node(node):
		return node
	for child in node.get_children():
		var found := _find_terrain_recursive(child)
		if found != null:
			return found
	return null


func _is_terrain_node(node: Node) -> bool:
	return node != null and node.get_script() == TERRAIN_SCRIPT
