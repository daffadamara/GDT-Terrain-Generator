@tool
extends EditorPlugin

const TERRAIN_TYPE_NAME := "GdtTerrain3D"
const TERRAIN_BASE_TYPE := "Node3D"
const TERRAIN_SCRIPT := preload("res://addons/gdt_terrain/src/gdt_terrain_3d.gd")


func _enter_tree() -> void:
	var icon := get_editor_interface().get_base_control().get_theme_icon("Node3D", "EditorIcons")
	add_custom_type(TERRAIN_TYPE_NAME, TERRAIN_BASE_TYPE, TERRAIN_SCRIPT, icon)


func _exit_tree() -> void:
	remove_custom_type(TERRAIN_TYPE_NAME)
