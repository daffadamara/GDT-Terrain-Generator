@tool
extends RefCounted

signal tool_selected(tool_id: int)
signal action_requested(action_id: int)
signal property_changed(property_name: StringName, value)

const TOOL_NONE := -1
const TOOL_PAINT := 0
const TOOL_SCATTER_ADD := 1
const TOOL_SCATTER_ERASE := 2

const ACTION_GENERATE_PREVIEW := 0
const ACTION_GENERATE_FINAL := 1
const ACTION_CANCEL_GENERATION := 2
const ACTION_CLEAR_TERRAIN := 3
const ACTION_SAVE_PRESET := 4
const ACTION_LOAD_PRESET := 5
const ACTION_EXPORT_HEIGHTMAP := 6
const ACTION_SAVE_MESH_RESOURCES := 7
const ACTION_SETUP_PREVIEW_LIGHTING := 8
const ACTION_GENERATE_COLLISION := 9
const ACTION_REMOVE_COLLISION := 10
const ACTION_REVEAL_ALL_CHUNKS := 11
const ACTION_REBUILD_REGION_DATA := 12
const ACTION_CLEAR_PAINTED_MASKS := 13
const ACTION_GENERATE_SCATTER := 14
const ACTION_CLEAR_SCATTER := 15
const ACTION_PRINT_PERFORMANCE_SUMMARY := 16
const ACTION_SETUP_FOCUS_CAMERA := 17

const PAINT_LAYERS := ["Lowland", "Ground", "Upper", "Rocky", "Cliff", "Snow"]
const PAINT_MODES := ["Add", "Subtract", "Smooth"]
const ACTIONS_REQUIRING_TERRAIN := [
	ACTION_SAVE_MESH_RESOURCES,
	ACTION_GENERATE_COLLISION,
	ACTION_REMOVE_COLLISION,
	ACTION_REVEAL_ALL_CHUNKS,
	ACTION_REBUILD_REGION_DATA,
	ACTION_CLEAR_PAINTED_MASKS,
	ACTION_GENERATE_SCATTER,
	ACTION_CLEAR_SCATTER,
	ACTION_PRINT_PERFORMANCE_SUMMARY,
]

var _plugin: EditorPlugin
var _terrain
var _toolbar: VBoxContainer
var _settings_panel: PanelContainer
var _settings_row: HBoxContainer
var _status_label: Label
var _menu_button: MenuButton
var _tool_group := ButtonGroup.new()
var _tool_buttons := {}
var _is_refreshing := false


func setup(plugin: EditorPlugin) -> void:
	_plugin = plugin
	_create_menu()
	_create_toolbar()
	_create_settings_panel()
	_plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _menu_button)
	_plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _toolbar)
	_plugin.add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, _settings_panel)
	_menu_button.about_to_popup.connect(_refresh_menu_state)
	set_terrain(null)


func cleanup() -> void:
	if _plugin != null:
		if _menu_button != null:
			_plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, _menu_button)
		if _toolbar != null:
			_plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_SIDE_LEFT, _toolbar)
		if _settings_panel != null:
			_plugin.remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_BOTTOM, _settings_panel)
	if _menu_button != null:
		_menu_button.queue_free()
	if _toolbar != null:
		_toolbar.queue_free()
	if _settings_panel != null:
		_settings_panel.queue_free()
	_menu_button = null
	_toolbar = null
	_settings_panel = null
	_settings_row = null
	_status_label = null
	_tool_buttons.clear()
	_terrain = null
	_plugin = null


func set_terrain(terrain) -> void:
	_terrain = terrain
	var has_terrain := _terrain != null
	if _menu_button != null:
		_menu_button.visible = has_terrain
	if _toolbar != null:
		_toolbar.visible = has_terrain
	if _settings_panel != null:
		_settings_panel.visible = has_terrain
	refresh()


func refresh() -> void:
	if _settings_row == null:
		return
	_is_refreshing = true
	_refresh_tool_buttons()
	_refresh_menu_state()
	refresh_status()
	_rebuild_settings()
	_is_refreshing = false


func refresh_status() -> void:
	if _status_label == null:
		return
	if _terrain == null:
		_status_label.text = ""
		_status_label.tooltip_text = ""
		return

	var status := _get_generation_status()
	var generated := int(status.get("generated_chunks", 0))
	var total := int(status.get("total_chunks", 0))
	var visible := int(status.get("visible_chunks", 0))
	var phase := str(status.get("generation_phase", "Idle"))
	var bake := str(status.get("bake_state", ""))
	var is_active := bool(status.get("is_generating", false))
	_status_label.text = _shorten_status_phase(phase)
	_status_label.tooltip_text = "Generation status\nGenerated chunks: %d\nTotal chunks: %d\nVisible chunks: %d\nActive: %s\nBake state: %s" % [
		generated,
		total,
		visible,
		"Yes" if is_active else "No",
		bake,
	]


func _create_menu() -> void:
	_menu_button = MenuButton.new()
	_menu_button.text = "GDT Terrain"
	_menu_button.tooltip_text = "GDT Terrain actions"
	var popup := _menu_button.get_popup()
	_add_menu_item(popup, "Generate Preview", ACTION_GENERATE_PREVIEW, ["Reload", "Play"])
	_add_menu_item(popup, "Generate Final", ACTION_GENERATE_FINAL, ["Bake", "Save"])
	_add_menu_item(popup, "Cancel Generation", ACTION_CANCEL_GENERATION, ["Stop", "Close"])
	_add_menu_item(popup, "Clear Generated Terrain", ACTION_CLEAR_TERRAIN, ["Clear", "Remove"])
	popup.add_separator()
	_add_menu_item(popup, "Save Preset", ACTION_SAVE_PRESET, ["Save"])
	_add_menu_item(popup, "Load Preset", ACTION_LOAD_PRESET, ["Load", "Folder"])
	_add_menu_item(popup, "Export Heightmap", ACTION_EXPORT_HEIGHTMAP, ["ImageTexture", "Save"])
	popup.add_separator()
	_add_menu_item(popup, "Save Mesh Resources", ACTION_SAVE_MESH_RESOURCES, ["MeshInstance3D", "Save"])
	_add_menu_item(popup, "Setup Preview Lighting", ACTION_SETUP_PREVIEW_LIGHTING, ["DirectionalLight3D", "Light"])
	_add_menu_item(popup, "Setup Focus Camera", ACTION_SETUP_FOCUS_CAMERA, ["Camera3D", "Camera"])
	_add_menu_item(popup, "Generate Collision", ACTION_GENERATE_COLLISION, ["CollisionShape3D"])
	_add_menu_item(popup, "Remove Collision", ACTION_REMOVE_COLLISION, ["CollisionShape3D", "Remove"])
	_add_menu_item(popup, "Reveal All Chunks", ACTION_REVEAL_ALL_CHUNKS, ["GuiVisibilityVisible", "Show"])
	_add_menu_item(popup, "Rebuild Region Data", ACTION_REBUILD_REGION_DATA, ["ResourcePreloader", "Reload"])
	_add_menu_item(popup, "Clear Painted Masks", ACTION_CLEAR_PAINTED_MASKS, ["CanvasItem", "Clear"])
	_add_menu_item(popup, "Generate Scatter", ACTION_GENERATE_SCATTER, ["MultiMeshInstance3D", "MeshInstance3D"])
	_add_menu_item(popup, "Clear Scatter", ACTION_CLEAR_SCATTER, ["MultiMeshInstance3D", "Remove"])
	popup.add_separator()
	_add_menu_item(popup, "Print Performance Summary", ACTION_PRINT_PERFORMANCE_SUMMARY, ["GraphEdit", "Info"])
	popup.id_pressed.connect(func(id: int): action_requested.emit(id))


func _create_toolbar() -> void:
	_toolbar = VBoxContainer.new()
	_toolbar.custom_minimum_size = Vector2(96.0, 0.0)
	_toolbar.add_theme_constant_override("separation", 6)
	_add_tool_button(TOOL_NONE, "Select", "Select or move terrain without painting", ["ToolSelect", "Cursor"])
	_toolbar.add_child(HSeparator.new())
	_add_tool_button(TOOL_PAINT, "Paint", "Paint material layers", ["CanvasItem", "Edit"])
	_add_tool_button(TOOL_SCATTER_ADD, "Add", "Add scatter instances", ["MultiMeshInstance3D", "MeshInstance3D"])
	_add_tool_button(TOOL_SCATTER_ERASE, "Erase", "Erase scatter instances", ["Remove", "Close"])


func _add_tool_button(tool_id: int, fallback_text: String, tooltip: String, icon_names: Array) -> void:
	var button := Button.new()
	var icon := _get_editor_icon(icon_names)
	if icon != null:
		button.icon = icon
	button.text = fallback_text
	button.tooltip_text = tooltip
	button.toggle_mode = true
	button.button_group = _tool_group
	button.flat = true
	button.expand_icon = false
	button.custom_minimum_size = Vector2(88.0, 38.0)
	button.pressed.connect(func(): tool_selected.emit(tool_id))
	_toolbar.add_child(button)
	_tool_buttons[tool_id] = button


func _create_settings_panel() -> void:
	_settings_panel = PanelContainer.new()
	_settings_panel.custom_minimum_size = Vector2(0.0, 52.0)
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 12)
	_settings_row = HBoxContainer.new()
	_settings_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_settings_row.add_theme_constant_override("separation", 8)
	bottom_row.add_child(_settings_row)

	bottom_row.add_child(VSeparator.new())
	var status_title := Label.new()
	status_title.text = "Status"
	status_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom_row.add_child(status_title)
	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(88.0, 0.0)
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.clip_text = true
	bottom_row.add_child(_status_label)
	_settings_panel.add_child(bottom_row)


func _refresh_tool_buttons() -> void:
	var selected_tool := TOOL_NONE
	if _terrain != null and bool(_terrain.editor_brush_enabled):
		selected_tool = int(_terrain.editor_brush_mode)
	for tool_id in _tool_buttons.keys():
		var button := _tool_buttons[tool_id] as Button
		if button != null:
			button.set_pressed_no_signal(int(tool_id) == selected_tool)


func _refresh_menu_state() -> void:
	if _menu_button == null:
		return
	var popup := _menu_button.get_popup()
	var has_terrain := _terrain != null
	var has_generated := _has_generated_terrain()
	var status := _get_generation_status()
	var is_generating := has_terrain and bool(status.get("is_generating", false))
	_set_menu_item_disabled(popup, ACTION_GENERATE_PREVIEW, not has_terrain or bool(_terrain.final_terrain_locked) or is_generating)
	_set_menu_item_disabled(popup, ACTION_GENERATE_FINAL, not has_terrain or bool(_terrain.final_terrain_locked) or is_generating)
	_set_menu_item_disabled(popup, ACTION_CANCEL_GENERATION, not has_terrain or not is_generating)
	_set_menu_item_disabled(popup, ACTION_CLEAR_TERRAIN, not has_terrain or not has_generated)
	for action_id in ACTIONS_REQUIRING_TERRAIN:
		_set_menu_item_disabled(popup, action_id, not has_terrain or not has_generated)
	_set_menu_item_disabled(popup, ACTION_SETUP_PREVIEW_LIGHTING, not has_terrain)
	_set_menu_item_disabled(popup, ACTION_SETUP_FOCUS_CAMERA, not has_terrain)
	_set_menu_item_disabled(popup, ACTION_SAVE_PRESET, not has_terrain)
	_set_menu_item_disabled(popup, ACTION_LOAD_PRESET, not has_terrain)
	_set_menu_item_disabled(popup, ACTION_EXPORT_HEIGHTMAP, not has_terrain)


func _rebuild_settings() -> void:
	for child in _settings_row.get_children():
		_settings_row.remove_child(child)
		child.queue_free()
	if _terrain == null:
		return

	var title := Label.new()
	title.custom_minimum_size = Vector2(104.0, 0.0)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_settings_row.add_child(title)

	if not bool(_terrain.editor_brush_enabled):
		title.text = "Brush"
		var hint := Label.new()
		hint.text = "Select a terrain tool to edit brush settings."
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_settings_row.add_child(hint)
		return

	match int(_terrain.editor_brush_mode):
		TOOL_PAINT:
			title.text = "Material Paint"
			_add_option_setting("Layer", "paint_layer", PAINT_LAYERS)
			_add_option_setting("Mode", "paint_mode", PAINT_MODES)
			_add_number_setting("Radius", "paint_radius", 0.01, 256.0, 0.01)
			_add_number_setting("Strength", "paint_strength", 0.0, 1.0, 0.01)
			_add_number_setting("Softness", "paint_softness", 0.0, 1.0, 0.01)
			_add_number_setting("Spacing", "editor_brush_spacing", 0.01, 1.0, 0.01)
		TOOL_SCATTER_ADD:
			title.text = "Scatter Add"
			_add_number_setting("Radius", "scatter_brush_radius", 0.01, 256.0, 0.01)
			_add_number_setting("Strength", "scatter_brush_strength", 0.0, 1.0, 0.01)
			_add_number_setting("Density", "scatter_density", 0.0, 16.0, 0.01)
			_add_number_setting("Spacing", "editor_brush_spacing", 0.01, 1.0, 0.01)
			_add_scatter_layer_readout()
		TOOL_SCATTER_ERASE:
			title.text = "Scatter Erase"
			_add_number_setting("Radius", "scatter_brush_radius", 0.01, 256.0, 0.01)
			_add_number_setting("Strength", "scatter_brush_strength", 0.0, 1.0, 0.01)
			_add_number_setting("Spacing", "editor_brush_spacing", 0.01, 1.0, 0.01)


func _add_option_setting(label_text: String, property_name: StringName, values: Array) -> void:
	var label := Label.new()
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_settings_row.add_child(label)

	var option := OptionButton.new()
	for index in values.size():
		option.add_item(str(values[index]), index)
	option.select(clampi(int(_terrain.get(property_name)), 0, maxi(0, values.size() - 1)))
	option.custom_minimum_size = Vector2(108.0, 0.0)
	option.item_selected.connect(func(index: int):
		if not _is_refreshing:
			property_changed.emit(property_name, index)
	)
	_settings_row.add_child(option)


func _add_number_setting(label_text: String, property_name: StringName, min_value: float, max_value: float, step: float) -> void:
	var label := Label.new()
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_settings_row.add_child(label)

	var spin_box := SpinBox.new()
	spin_box.min_value = min_value
	spin_box.max_value = max_value
	spin_box.step = step
	spin_box.custom_minimum_size = Vector2(72.0, 0.0)
	var current_value := clampf(float(_terrain.get(property_name)), min_value, max_value)
	spin_box.set_value_no_signal(current_value)
	_settings_row.add_child(spin_box)

	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.custom_minimum_size = Vector2(84.0, 0.0)
	slider.set_value_no_signal(current_value)
	_settings_row.add_child(slider)

	spin_box.value_changed.connect(func(value: float):
		if _is_refreshing:
			return
		slider.set_value_no_signal(clampf(value, min_value, max_value))
		property_changed.emit(property_name, value)
	)
	slider.value_changed.connect(func(value: float):
		if _is_refreshing:
			return
		spin_box.set_value_no_signal(value)
		property_changed.emit(property_name, value)
	)


func _add_scatter_layer_readout() -> void:
	var label := Label.new()
	label.text = "Layer"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_settings_row.add_child(label)

	var value := Label.new()
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.custom_minimum_size = Vector2(180.0, 0.0)
	value.text = _get_scatter_layer_label()
	value.tooltip_text = "Assign the scatter layer resource in the Inspector."
	_settings_row.add_child(value)


func _get_scatter_layer_label() -> String:
	if _terrain == null or _terrain.scatter_layer == null:
		return "Default grass card"
	var resource := _terrain.scatter_layer as Resource
	if resource == null:
		return "Custom layer"
	if not resource.resource_path.is_empty():
		return resource.resource_path.get_file()
	if not resource.resource_name.is_empty():
		return resource.resource_name
	return "Custom layer"


func _shorten_status_phase(phase: String) -> String:
	match phase:
		"Building mesh arrays":
			return "Building"
		"Finalizing chunks":
			return "Finalizing"
		"Saving LOD resources":
			return "Saving LOD"
		"Generating collision":
			return "Collision"
		"Saving final resources":
			return "Saving"
		_:
			return phase


func _add_menu_item(popup: PopupMenu, label: String, action_id: int, icon_names: Array) -> void:
	var icon := _get_editor_icon(icon_names)
	if icon != null:
		popup.add_icon_item(icon, label, action_id)
	else:
		popup.add_item(label, action_id)


func _set_menu_item_disabled(popup: PopupMenu, action_id: int, is_disabled: bool) -> void:
	var index := popup.get_item_index(action_id)
	if index >= 0:
		popup.set_item_disabled(index, is_disabled)


func _get_editor_icon(icon_names: Array) -> Texture2D:
	if _plugin == null:
		return null
	var base_control := _plugin.get_editor_interface().get_base_control()
	for icon_name in icon_names:
		var candidate := str(icon_name)
		if base_control.has_theme_icon(candidate, "EditorIcons"):
			return base_control.get_theme_icon(candidate, "EditorIcons")
	return null


func _has_generated_terrain() -> bool:
	if _terrain == null:
		return false
	if _terrain.has_method("_has_generated_chunks"):
		return bool(_terrain.call("_has_generated_chunks"))
	var status := _get_generation_status()
	return int(status.get("generated_chunks", 0)) > 0 or int(status.get("visible_chunks", 0)) > 0


func _get_generation_status() -> Dictionary:
	if _terrain == null:
		return {}
	if _terrain.has_method("get_generation_status"):
		return _terrain.get_generation_status()
	return {
		"generated_chunks": int(_terrain.generated_chunks),
		"total_chunks": int(_terrain.total_chunks),
		"visible_chunks": int(_terrain.visible_chunks),
		"is_generating": bool(_terrain.is_generating),
		"generation_phase": str(_terrain.generation_phase),
		"bake_state": str(_terrain.bake_state),
	}
