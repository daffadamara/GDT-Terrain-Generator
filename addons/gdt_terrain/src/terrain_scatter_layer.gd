@tool
extends Resource
class_name TerrainScatterLayer

@export var enabled := true
@export var mesh: Mesh
@export_file("*.tscn", "*.scn", "*.glb", "*.gltf") var scene_path := ""
@export var material_override: Material
@export_range(0.0, 64.0, 0.01) var density := 0.35
@export var height_min := -64.0
@export var height_max := 64.0
@export_range(0.0, 1.0, 0.01) var slope_min := 0.0
@export_range(0.0, 1.0, 0.01) var slope_max := 0.55
@export_range(0.01, 10.0, 0.01) var min_scale := 0.8
@export_range(0.01, 10.0, 0.01) var max_scale := 1.25
@export_range(0.0, 5.0, 0.01) var y_offset := 0.0
@export var align_to_normal := true


func get_mesh() -> Mesh:
	if mesh != null:
		return mesh
	if scene_path.strip_edges().is_empty():
		return null
	var packed_scene := ResourceLoader.load(scene_path) as PackedScene
	if packed_scene == null:
		return null
	var instance := packed_scene.instantiate()
	var found_mesh := _find_first_mesh(instance)
	instance.free()
	return found_mesh


func _find_first_mesh(node: Node) -> Mesh:
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null:
		return mesh_instance.mesh
	for child in node.get_children():
		var child_mesh := _find_first_mesh(child)
		if child_mesh != null:
			return child_mesh
	return null
