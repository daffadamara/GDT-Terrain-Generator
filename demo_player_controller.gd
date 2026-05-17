extends CharacterBody3D
class_name GdtTerrainDemoPlayer

@export_range(1.0, 20.0, 0.1) var move_speed := 8.0
@export_range(1.0, 30.0, 0.1) var jump_velocity := 8.0
@export_range(0.1, 20.0, 0.1) var mouse_sensitivity := 3.0
@export_range(0.0, 512.0, 1.0) var ground_snap_height := 128.0
@export_range(0.0, 8.0, 0.01) var ground_clearance := 1.05

var _gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float
var _pitch := 0.0
@onready var _camera := $Camera3D as Camera3D


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().physics_frame
	_snap_to_baked_terrain()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity * 0.001)
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity * 0.001, -1.2, 1.2)
		_camera.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity

	var input_vector := Vector2.ZERO
	input_vector.y += 1.0 if Input.is_key_pressed(KEY_W) else 0.0
	input_vector.y -= 1.0 if Input.is_key_pressed(KEY_S) else 0.0
	input_vector.x -= 1.0 if Input.is_key_pressed(KEY_A) else 0.0
	input_vector.x += 1.0 if Input.is_key_pressed(KEY_D) else 0.0
	input_vector = input_vector.normalized()

	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var direction := (right * input_vector.x + forward * input_vector.y).normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	move_and_slide()


func _snap_to_baked_terrain() -> void:
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(global_position.x, ground_snap_height, global_position.z),
		Vector3(global_position.x, -ground_snap_height, global_position.z)
	)
	query.exclude = [get_rid()]
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		push_warning("GDT Terrain demo player could not find baked terrain collision below its start position.")
		return
	global_position.y = (hit["position"] as Vector3).y + ground_clearance
	velocity = Vector3.ZERO
