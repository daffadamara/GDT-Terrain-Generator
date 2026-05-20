@tool
extends EditorPlugin

const TERRAIN_TYPE_NAME := "GdtTerrain3D"
const TERRAIN_BASE_TYPE := "Node3D"
const TERRAIN_SCRIPT := preload("res://addons/gdt_terrain/src/gdt_terrain_3d.gd")
const BRUSH_PREVIEW_NAME := "_GdtTerrainBrushPreview"
const BRUSH_SEGMENTS := 96
const MAX_STAMPS_PER_MOTION := 8

var _edited_terrain
var _brush_preview: MeshInstance3D
var _brush_material: StandardMaterial3D
var _brush_pressed := false
var _last_stamp_position := Vector3.INF


func _enter_tree() -> void:
	var icon := get_editor_interface().get_base_control().get_theme_icon("Node3D", "EditorIcons")
	add_custom_type(TERRAIN_TYPE_NAME, TERRAIN_BASE_TYPE, TERRAIN_SCRIPT, icon)


func _exit_tree() -> void:
	_clear_brush_preview()
	remove_custom_type(TERRAIN_TYPE_NAME)


func _handles(object: Object) -> bool:
	return object is Node3D and object.get_script() == TERRAIN_SCRIPT


func _edit(object: Object) -> void:
	_edited_terrain = object if _handles(object) else null
	_brush_pressed = false
	_last_stamp_position = Vector3.INF
	if _edited_terrain == null:
		_clear_brush_preview()


func _forward_3d_gui_input(viewport_camera: Camera3D, event: InputEvent) -> int:
	if _edited_terrain == null:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if not _is_brush_active():
		_hide_brush_preview()
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.alt_pressed or mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		var hit_position = _raycast_terrain(viewport_camera, mouse_button.position)
		if hit_position == null:
			_hide_brush_preview()
			_brush_pressed = false
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_update_brush_preview(hit_position)
		_brush_pressed = mouse_button.pressed
		if mouse_button.pressed:
			_stamp_brush(hit_position, true)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	if event is InputEventMouseMotion:
		var mouse_motion := event as InputEventMouseMotion
		if mouse_motion.alt_pressed:
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		var hit_position = _raycast_terrain(viewport_camera, mouse_motion.position)
		if hit_position == null:
			_hide_brush_preview()
			return EditorPlugin.AFTER_GUI_INPUT_PASS
		_update_brush_preview(hit_position)
		if _brush_pressed:
			_stamp_brush(hit_position, false)
			return EditorPlugin.AFTER_GUI_INPUT_STOP

	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _is_brush_active() -> bool:
	if _edited_terrain == null or not bool(_edited_terrain.editor_brush_enabled):
		return false
	match int(_edited_terrain.editor_brush_mode):
		0:
			return bool(_edited_terrain.paint_enabled)
		1, 2:
			return bool(_edited_terrain.scatter_enabled)
		_:
			return false


func _stamp_brush(world_position: Vector3, force: bool) -> void:
	var radius := _get_brush_radius()
	var spacing := maxf(radius * float(_edited_terrain.editor_brush_spacing), 0.001)
	if force or not _last_stamp_position.is_finite():
		_apply_brush_at(world_position)
		_last_stamp_position = world_position
		return
	var distance := world_position.distance_to(_last_stamp_position)
	if distance < spacing:
		return
	var stamp_count := clampi(floori(distance / spacing), 1, MAX_STAMPS_PER_MOTION)
	var start_position := _last_stamp_position
	for stamp_index in range(1, stamp_count + 1):
		var stamp_position := start_position.lerp(world_position, float(stamp_index) / float(stamp_count))
		_apply_brush_at(stamp_position)
	_last_stamp_position = world_position


func _apply_brush_at(world_position: Vector3) -> void:
	match int(_edited_terrain.editor_brush_mode):
		0:
			_edited_terrain.paint_material_mask(
				world_position,
				float(_edited_terrain.paint_radius),
				int(_edited_terrain.paint_layer),
				float(_edited_terrain.paint_strength),
				int(_edited_terrain.paint_mode),
				false
			)
		1:
			_edited_terrain.scatter_brush_stamp(
				world_position,
				float(_edited_terrain.scatter_brush_radius),
				float(_edited_terrain.scatter_brush_strength)
			)
		2:
			_edited_terrain.erase_scatter_brush(world_position, float(_edited_terrain.scatter_brush_radius))


func _get_brush_radius() -> float:
	if _edited_terrain == null:
		return 1.0
	if int(_edited_terrain.editor_brush_mode) == 0:
		return maxf(float(_edited_terrain.paint_radius), 0.01)
	return maxf(float(_edited_terrain.scatter_brush_radius), 0.01)


func _raycast_terrain(viewport_camera: Camera3D, screen_position: Vector2):
	var ray_origin := viewport_camera.project_ray_origin(screen_position)
	var ray_direction := viewport_camera.project_ray_normal(screen_position).normalized()
	var max_distance := maxf(float(_edited_terrain.terrain_size) * 4.0, viewport_camera.far)
	var previous_distance := 0.0
	for step in range(1, 160):
		var distance := max_distance * float(step) / 159.0
		var sample := ray_origin + ray_direction * distance
		var height := float(_edited_terrain.get_height_at(sample))
		if not is_nan(height) and sample.y <= height:
			var low := previous_distance
			var high := distance
			for _refine_step in 12:
				var mid := (low + high) * 0.5
				var mid_sample := ray_origin + ray_direction * mid
				var mid_height := float(_edited_terrain.get_height_at(mid_sample))
				if not is_nan(mid_height) and mid_sample.y <= mid_height:
					high = mid
				else:
					low = mid
			var hit := ray_origin + ray_direction * high
			var hit_height := float(_edited_terrain.get_height_at(hit))
			if is_nan(hit_height):
				return null
			return Vector3(hit.x, hit_height, hit.z)
		previous_distance = distance
	return null


func _update_brush_preview(world_position: Vector3) -> void:
	_ensure_brush_preview()
	if _brush_preview == null:
		return
	_brush_preview.visible = true
	_brush_preview.global_position = _edited_terrain.project_position_to_terrain(world_position, 0.06)
	_brush_preview.mesh = _create_brush_ring_mesh(_get_brush_radius())
	_update_brush_material()


func _ensure_brush_preview() -> void:
	if _edited_terrain == null:
		return
	if _brush_preview != null and is_instance_valid(_brush_preview) and _brush_preview.get_parent() == _edited_terrain:
		return
	_clear_brush_preview()
	_brush_preview = MeshInstance3D.new()
	_brush_preview.name = BRUSH_PREVIEW_NAME
	_brush_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_brush_preview.visible = false
	_edited_terrain.add_child(_brush_preview, false, Node.INTERNAL_MODE_FRONT)


func _create_brush_ring_mesh(radius: float) -> Mesh:
	var vertices := PackedVector3Array()
	var inner_radius := maxf(radius - maxf(radius * 0.035, 0.08), radius * 0.85)
	var indices := PackedInt32Array()
	for index in BRUSH_SEGMENTS:
		var angle_a := TAU * float(index) / float(BRUSH_SEGMENTS)
		var angle_b := TAU * float(index + 1) / float(BRUSH_SEGMENTS)
		var base_index := vertices.size()
		vertices.append(Vector3(cos(angle_a) * radius, 0.0, sin(angle_a) * radius))
		vertices.append(Vector3(cos(angle_b) * radius, 0.0, sin(angle_b) * radius))
		vertices.append(Vector3(cos(angle_a) * inner_radius, 0.0, sin(angle_a) * inner_radius))
		vertices.append(Vector3(cos(angle_b) * inner_radius, 0.0, sin(angle_b) * inner_radius))
		indices.append_array(PackedInt32Array([base_index, base_index + 1, base_index + 2, base_index + 1, base_index + 3, base_index + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _update_brush_material() -> void:
	if _brush_material == null:
		_brush_material = StandardMaterial3D.new()
		_brush_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_brush_material.no_depth_test = true
		_brush_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_brush_material.emission_enabled = true
		_brush_material.emission_energy_multiplier = 1.4
	match int(_edited_terrain.editor_brush_mode):
		0:
			_brush_material.albedo_color = Color(0.15, 0.55, 1.0, 0.95)
		1:
			_brush_material.albedo_color = Color(0.2, 1.0, 0.25, 0.95)
		2:
			_brush_material.albedo_color = Color(1.0, 0.18, 0.12, 0.95)
	_brush_material.emission = _brush_material.albedo_color
	if _brush_preview != null:
		_brush_preview.set_surface_override_material(0, _brush_material)


func _hide_brush_preview() -> void:
	if _brush_preview != null and is_instance_valid(_brush_preview):
		_brush_preview.visible = false


func _clear_brush_preview() -> void:
	if _brush_preview != null and is_instance_valid(_brush_preview):
		_brush_preview.queue_free()
	_brush_preview = null
