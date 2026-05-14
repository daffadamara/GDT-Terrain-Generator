@tool
extends MeshInstance3D
class_name ProceduralWater3D

enum WaterQuality { LIGHTWEIGHT, BALANCED, HIGH_FIDELITY }

const WATER_PROCEDURAL_SHADER_PATH := "water_procedural_shader.res"
const WATER_PROCEDURAL_MATERIAL_PATH := "water_procedural_material.res"
const WATER_NOISE_PATH := "water_noise.res"

const WATER_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D water_noise_texture;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec4 water_color : source_color = vec4(0.17647, 0.46667, 0.40392, 0.8);
uniform vec4 mid_water_color : source_color = vec4(0.05882, 0.20392, 0.23922, 1.0);
uniform vec4 deep_water_color : source_color = vec4(0.02353, 0.08627, 0.13333, 1.0);
uniform vec4 foam_color : source_color = vec4(0.55982, 0.70500, 0.67298, 1.0);
uniform float water_alpha = 0.8;
uniform float wave_strength = 0.25;
uniform float foam_strength = 1.0;
uniform float refraction_strength = 0.025;
uniform float normal_strength = 0.25;
uniform float wave_scale = 1.0;
uniform float normal_tiling = 0.1;
uniform float foam_tiling = 0.5;
uniform float shore_alpha_fade = 0.3;
uniform float wave_speed = 0.16;
uniform vec2 primary_wave_direction = vec2(1.0, 0.27);
uniform vec2 secondary_wave_direction = vec2(-0.38, 1.0);
uniform float depth_fade_distance = 8.0;
uniform float foam_cutoff = 0.35;
uniform float quality_depth_enabled = 1.0;
uniform float quality_refraction_enabled = 1.0;

varying vec3 world_position;
varying float wave_mask;
varying float water_view_depth;

float sample_noise(vec2 uv) {
	return texture(water_noise_texture, uv).r;
}

void vertex() {
	vec2 direction_a = normalize(primary_wave_direction);
	vec2 direction_b = normalize(secondary_wave_direction);
	float wave_a = sin(dot(VERTEX.xz, direction_a) * wave_scale + TIME * wave_speed * 6.28318);
	float wave_b = sin(dot(VERTEX.xz, direction_b) * wave_scale * 1.73 - TIME * wave_speed * 4.71239);
	float wave_c = sample_noise(VERTEX.xz * wave_scale * 0.12 + vec2(TIME * wave_speed * 0.08, -TIME * wave_speed * 0.05)) * 2.0 - 1.0;
	float combined_wave = wave_a * 0.45 + wave_b * 0.35 + wave_c * 0.20;
	VERTEX.y += combined_wave * wave_strength;
	wave_mask = combined_wave * 0.5 + 0.5;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	water_view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec2 scroll_a = world_position.xz * wave_scale * 0.22 * normal_tiling + normalize(primary_wave_direction) * TIME * wave_speed * 0.08;
	vec2 scroll_b = world_position.xz * wave_scale * 0.37 * normal_tiling + normalize(secondary_wave_direction) * TIME * wave_speed * 0.12;
	vec2 foam_scroll = world_position.xz * wave_scale * 0.62 * foam_tiling + normalize(primary_wave_direction + secondary_wave_direction) * TIME * wave_speed * 0.10;
	float noise_a = sample_noise(scroll_a);
	float noise_b = sample_noise(scroll_b);
	float foam_pattern = sample_noise(foam_scroll);
	float ripple = noise_a * 0.55 + noise_b * 0.45;
	vec2 distortion = vec2(noise_a - 0.5, noise_b - 0.5) * normal_strength;
	float surface_lines = smoothstep(0.54, 0.88, ripple + wave_mask * 0.25);

	float raw_scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 normalized_device_coordinates = vec3(SCREEN_UV * 2.0 - 1.0, raw_scene_depth);
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(normalized_device_coordinates, 1.0);
	scene_view.xyz /= scene_view.w;
	float scene_view_depth = -scene_view.z;
	float depth_delta = max(scene_view_depth - water_view_depth, 0.0);
	float depth_gradient = fwidth(raw_scene_depth);
	float depth_amount = clamp(depth_delta / max(depth_fade_distance, 0.001), 0.0, 1.0) * quality_depth_enabled;
	float shallow_amount = 1.0 - smoothstep(0.0, 0.35, depth_amount);
	float mid_amount = smoothstep(0.08, 0.62, depth_amount);
	float deep_amount = smoothstep(0.48, 1.0, depth_amount);
	vec3 water_tint = mix(water_color.rgb, mid_water_color.rgb, mid_amount);
	water_tint = mix(water_tint, deep_water_color.rgb, deep_amount);

	vec3 refracted = texture(screen_texture, SCREEN_UV + distortion * refraction_strength * quality_refraction_enabled).rgb;
	vec3 color = mix(water_tint, refracted, 0.14 * quality_refraction_enabled * (1.0 - shallow_amount * 0.55));
	color *= 0.90 + ripple * 0.17;
	color = mix(color, color + vec3(0.11, 0.18, 0.20), surface_lines * 0.16);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	color = mix(color, vec3(0.62, 0.84, 0.94), fresnel * 0.22);

	float depth_edge = smoothstep(0.00005, 0.0012, depth_gradient);
	float contact_band = 1.0 - smoothstep(foam_cutoff, foam_cutoff * 5.5, depth_delta);
	float shallow_contact = (1.0 - smoothstep(0.04, 0.28, depth_amount)) * smoothstep(0.001, foam_cutoff * 2.0, depth_delta);
	float shore_contact = max(depth_edge * contact_band, shallow_contact * 0.35) * quality_depth_enabled;
	float shore_foam_shape = smoothstep(0.22, 0.58, foam_pattern + wave_mask * 0.24);
	float crest_lines = smoothstep(0.82, 0.98, wave_mask) * smoothstep(0.55, 0.88, foam_pattern);
	float shore_foam = shore_contact * shore_foam_shape;
	float crest_foam = crest_lines * 0.045 * (1.0 - shore_contact);
	float foam = clamp((shore_foam + crest_foam) * foam_strength, 0.0, 1.0);
	color = mix(color, foam_color.rgb, foam);
	float shore_fade = (1.0 - smoothstep(0.0, max(shore_alpha_fade, 0.001), depth_delta)) * quality_depth_enabled;
	float alpha = mix(water_alpha, water_alpha * 0.36, shore_fade);

	NORMAL = normalize(NORMAL + vec3(distortion.x, 0.0, distortion.y));
	ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
	ALPHA = clamp(alpha + foam * 0.20, 0.0, 1.0);
	ROUGHNESS = mix(0.08, 0.22, depth_amount);
	SPECULAR = mix(0.58, 0.85, fresnel);
}
"""

@export_category("Water")

## Enables this water surface. Disable to hide it without removing the node.
@export var water_enabled: bool = true:
	set(value):
		water_enabled = value
		_update_water()

## Width and depth of the water surface in Godot units.
@export_range(1.0, 4096.0, 1.0) var water_size: float = 64.0:
	set(value):
		water_size = maxf(1.0, value)
		_rebuild_mesh()

## World Y height of the water surface.
@export_range(-512.0, 512.0, 0.1) var water_level: float = 0.0:
	set(value):
		water_level = value
		position.y = water_level

## Shallow-water color near shore and low-depth areas.
@export var water_color: Color = Color.html("2d7767"):
	set(value):
		water_color = value
		_update_material()

## Transparency of the water surface.
@export_range(0.0, 1.0, 0.01) var water_alpha: float = 0.8:
	set(value):
		water_alpha = clampf(value, 0.0, 1.0)
		_update_material()

## Rendering cost/quality preset for depth tint, foam, and refraction.
@export_enum("Lightweight", "Balanced", "High Fidelity") var quality_preset: int = WaterQuality.HIGH_FIDELITY:
	set(value):
		quality_preset = clampi(value, WaterQuality.LIGHTWEIGHT, WaterQuality.HIGH_FIDELITY)
		_apply_quality_defaults()
		_update_material()

## Height of animated waves. Set to 0 for a flat animated surface.
@export_range(0.0, 4.0, 0.01) var wave_strength: float = 0.25:
	set(value):
		wave_strength = maxf(0.0, value)
		_update_material()

## Strength of shoreline foam and subtle wave-crest highlights.
@export_range(0.0, 1.0, 0.01) var foam_strength: float = 1.0:
	set(value):
		foam_strength = clampf(value, 0.0, 1.0)
		_update_material()

## Strength of screen-space refraction. High values are more visible but can shimmer.
@export_range(0.0, 0.12, 0.001) var refraction_strength: float = 0.025:
	set(value):
		refraction_strength = clampf(value, 0.0, 0.12)
		_update_material()

@export_group("Advanced")

## Mid-depth water color between shallow cyan and deep blue.
@export var mid_water_color: Color = Color.html("0f343d"):
	set(value):
		mid_water_color = value
		_update_material()

## Dark color used where depth tint reads as deeper water.
@export var deep_water_color: Color = Color.html("061622"):
	set(value):
		deep_water_color = value
		_update_material()

## Foam highlight color along shallow intersections.
@export var foam_color: Color = Color(0.5598185, 0.7050046, 0.6729808, 1.0):
	set(value):
		foam_color = value
		_update_material()

## Strength of animated normal/ripple perturbation.
@export_range(0.0, 2.0, 0.01) var normal_strength: float = 0.25:
	set(value):
		normal_strength = maxf(0.0, value)
		_update_material()

## World-space wave frequency. Higher values create tighter waves.
@export_range(0.001, 2.0, 0.001) var wave_scale: float = 1.0:
	set(value):
		wave_scale = maxf(0.001, value)
		_update_material()

## Multiplier for normal/ripple texture tiling. Higher values create tighter surface detail.
@export_range(0.05, 8.0, 0.01) var normal_tiling: float = 0.1:
	set(value):
		normal_tiling = clampf(value, 0.05, 8.0)
		_update_material()

## Multiplier for foam texture tiling. Lower values make larger, less patchy foam shapes.
@export_range(0.05, 8.0, 0.01) var foam_tiling: float = 0.5:
	set(value):
		foam_tiling = clampf(value, 0.05, 8.0)
		_update_material()

## Distance over which shoreline water fades more transparent to hide terrain intersection seams.
@export_range(0.0, 8.0, 0.01) var shore_alpha_fade: float = 0.3:
	set(value):
		shore_alpha_fade = clampf(value, 0.0, 8.0)
		_update_material()

## Animation speed for waves and ripples.
@export_range(0.0, 4.0, 0.01) var wave_speed: float = 0.16:
	set(value):
		wave_speed = maxf(0.0, value)
		_update_material()

## Primary travel direction for large waves.
@export var primary_wave_direction: Vector2 = Vector2(1.0, 0.27):
	set(value):
		primary_wave_direction = value if value.length_squared() > 0.0001 else Vector2.RIGHT
		_update_material()

## Secondary travel direction for crossing wave motion.
@export var secondary_wave_direction: Vector2 = Vector2(-0.38, 1.0):
	set(value):
		secondary_wave_direction = value if value.length_squared() > 0.0001 else Vector2.UP
		_update_material()

## Depth distance over which shallow water blends into deep water.
@export_range(0.1, 128.0, 0.1) var depth_fade_distance: float = 8.0:
	set(value):
		depth_fade_distance = maxf(0.1, value)
		_update_material()

## Shoreline foam width in view-depth units. Higher values make foam wider and easier to see around terrain intersections.
@export_range(0.01, 4.0, 0.01) var foam_cutoff: float = 0.35:
	set(value):
		foam_cutoff = clampf(value, 0.01, 4.0)
		_update_material()

## Number of subdivisions per side for animated vertex waves.
@export_range(1, 1024, 1) var mesh_subdivisions: int = 1024:
	set(value):
		mesh_subdivisions = clampi(value, 1, 1024)
		_rebuild_mesh()

## Folder for saving water shader, material, and noise resources.
@export var generated_resource_directory: String = "res://generated_terrain"

var _water_material: ShaderMaterial
var _water_shader: Shader
var _water_noise_texture: Texture2D


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ready() -> void:
	_update_water()


func configure_from_terrain(settings: Dictionary) -> void:
	generated_resource_directory = str(settings.get("generated_resource_directory", generated_resource_directory))
	water_enabled = bool(settings.get("water_enabled", water_enabled))
	water_size = float(settings.get("water_size", water_size))
	water_level = float(settings.get("water_level", water_level))
	water_color = settings.get("water_color", water_color) as Color
	water_alpha = float(settings.get("water_alpha", water_alpha))
	_update_water()


func save_visual_resources(resource_directory: String) -> int:
	generated_resource_directory = resource_directory
	var directory_error := DirAccess.make_dir_recursive_absolute(resource_directory)
	if directory_error != OK:
		return directory_error

	var noise_error := ResourceSaver.save(_get_or_create_water_noise_texture(), "%s/%s" % [resource_directory, WATER_NOISE_PATH])
	if noise_error != OK:
		return noise_error
	var shader_error := ResourceSaver.save(_get_or_create_water_shader(), "%s/%s" % [resource_directory, WATER_PROCEDURAL_SHADER_PATH])
	if shader_error != OK:
		return shader_error
	var material_error := ResourceSaver.save(_get_or_create_water_material(), "%s/%s" % [resource_directory, WATER_PROCEDURAL_MATERIAL_PATH])
	if material_error != OK:
		return material_error

	_reload_saved_resources()
	_update_water()
	return OK


func _update_water() -> void:
	visible = water_enabled
	position.y = water_level
	if not water_enabled:
		return
	_rebuild_mesh()
	_update_material()


func _rebuild_mesh() -> void:
	if not water_enabled:
		return
	var water_mesh := PlaneMesh.new()
	water_mesh.size = Vector2(water_size, water_size)
	water_mesh.subdivide_width = mesh_subdivisions
	water_mesh.subdivide_depth = mesh_subdivisions
	mesh = water_mesh


func _update_material() -> void:
	if not water_enabled:
		return
	material_override = _get_or_create_water_material()
	_apply_shader_parameters()


func _apply_quality_defaults() -> void:
	match quality_preset:
		WaterQuality.LIGHTWEIGHT:
			mesh_subdivisions = mini(mesh_subdivisions, 48)
		WaterQuality.BALANCED:
			mesh_subdivisions = clampi(mesh_subdivisions, 48, 96)
		WaterQuality.HIGH_FIDELITY:
			mesh_subdivisions = maxi(mesh_subdivisions, 96)


func _get_or_create_water_material() -> ShaderMaterial:
	if _water_material == null:
		_water_material = _load_external_shader_material(WATER_PROCEDURAL_MATERIAL_PATH)
		if _water_material == null:
			_water_material = ShaderMaterial.new()
			_water_material.shader = _get_or_create_water_shader()
	_apply_shader_parameters()
	return _water_material


func _get_or_create_water_shader() -> Shader:
	if _water_shader == null:
		_water_shader = _load_external_shader(WATER_PROCEDURAL_SHADER_PATH)
		if _water_shader == null:
			_water_shader = Shader.new()
	_water_shader.code = WATER_SHADER_CODE
	return _water_shader


func _apply_shader_parameters() -> void:
	if _water_material == null:
		return
	var color := water_color
	color.a = water_alpha
	_water_material.shader = _get_or_create_water_shader()
	_water_material.set_shader_parameter("water_noise_texture", _get_or_create_water_noise_texture())
	_water_material.set_shader_parameter("water_color", color)
	_water_material.set_shader_parameter("mid_water_color", mid_water_color)
	_water_material.set_shader_parameter("deep_water_color", deep_water_color)
	_water_material.set_shader_parameter("foam_color", foam_color)
	_water_material.set_shader_parameter("water_alpha", water_alpha)
	_water_material.set_shader_parameter("wave_strength", wave_strength)
	_water_material.set_shader_parameter("foam_strength", foam_strength)
	_water_material.set_shader_parameter("refraction_strength", refraction_strength)
	_water_material.set_shader_parameter("normal_strength", normal_strength)
	_water_material.set_shader_parameter("wave_scale", wave_scale)
	_water_material.set_shader_parameter("normal_tiling", normal_tiling)
	_water_material.set_shader_parameter("foam_tiling", foam_tiling)
	_water_material.set_shader_parameter("shore_alpha_fade", shore_alpha_fade)
	_water_material.set_shader_parameter("wave_speed", wave_speed)
	_water_material.set_shader_parameter("primary_wave_direction", primary_wave_direction)
	_water_material.set_shader_parameter("secondary_wave_direction", secondary_wave_direction)
	_water_material.set_shader_parameter("depth_fade_distance", depth_fade_distance)
	_water_material.set_shader_parameter("foam_cutoff", foam_cutoff)
	_water_material.set_shader_parameter("quality_depth_enabled", 0.0 if quality_preset == WaterQuality.LIGHTWEIGHT else 1.0)
	_water_material.set_shader_parameter("quality_refraction_enabled", 1.0 if quality_preset == WaterQuality.HIGH_FIDELITY else 0.0)


func _get_or_create_water_noise_texture() -> Texture2D:
	if _water_noise_texture == null:
		_water_noise_texture = _load_external_texture(WATER_NOISE_PATH)
		if _water_noise_texture == null:
			_water_noise_texture = _create_noise_texture(104729, 0.12, 256)
	return _water_noise_texture


func _create_noise_texture(noise_seed: int, texture_frequency: float, texture_size: int) -> ImageTexture:
	var texture_noise := FastNoiseLite.new()
	texture_noise.seed = noise_seed
	texture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	texture_noise.frequency = texture_frequency
	texture_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	texture_noise.fractal_octaves = 4
	texture_noise.fractal_lacunarity = 2.0
	texture_noise.fractal_gain = 0.5

	var image := Image.create(texture_size, texture_size, false, Image.FORMAT_RGB8)
	for y in texture_size:
		for x in texture_size:
			var value := texture_noise.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			image.set_pixel(x, y, Color(value, value, value, 1.0))

	return ImageTexture.create_from_image(image)


func _get_visual_resource_path(file_name: String) -> String:
	return "%s/%s" % [generated_resource_directory, file_name]


func _load_external_shader_material(file_name: String) -> ShaderMaterial:
	var path := _get_visual_resource_path(file_name)
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "ShaderMaterial", ResourceLoader.CACHE_MODE_REPLACE) as ShaderMaterial


func _load_external_shader(file_name: String) -> Shader:
	var path := _get_visual_resource_path(file_name)
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "Shader", ResourceLoader.CACHE_MODE_REPLACE) as Shader


func _load_external_texture(file_name: String) -> Texture2D:
	var path := _get_visual_resource_path(file_name)
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D


func _reload_saved_resources() -> void:
	_water_noise_texture = _load_external_texture(WATER_NOISE_PATH)
	_water_shader = _load_external_shader(WATER_PROCEDURAL_SHADER_PATH)
	_water_material = _load_external_shader_material(WATER_PROCEDURAL_MATERIAL_PATH)
