@tool
extends RefCounted
class_name TerrainMaterialManager

const TERRAIN_ENCODING_V5_MASKS := "v5_masks"
const TERRAIN_ENCODING_LEGACY_COLORS := "legacy_colors"
const TERRAIN_PROCEDURAL_SHADER_PATH := "terrain_procedural_shader.res"
const TERRAIN_PROCEDURAL_MATERIAL_PATH := "terrain_procedural_material.res"
const TERRAIN_LEGACY_MATERIAL_PATH := "terrain_vertex_color_material.res"
const TERRAIN_MACRO_NOISE_PATH := "terrain_macro_noise.res"
const TERRAIN_DETAIL_NOISE_PATH := "terrain_detail_noise.res"

const TERRAIN_SHADER_CODE := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform bool use_procedural_detail = true;
uniform bool water_enabled = true;
uniform sampler2D macro_noise_texture;
uniform sampler2D detail_noise_texture;
uniform vec4 lowland_color : source_color = vec4(0.15, 0.21, 0.09, 1.0);
uniform vec4 grass_color : source_color = vec4(0.24, 0.33, 0.15, 1.0);
uniform vec4 shore_color : source_color = vec4(0.52, 0.48, 0.30, 1.0);
uniform vec4 seabed_color : source_color = vec4(0.20, 0.17, 0.10, 1.0);
uniform vec4 rock_color : source_color = vec4(0.27, 0.24, 0.18, 1.0);
uniform vec4 snow_color : source_color = vec4(0.86, 0.84, 0.76, 1.0);
uniform float water_level = 0.0;
uniform float height_scale = 5.0;
uniform float snow_height = 5.0;
uniform float rock_slope_threshold = 0.44;
uniform float macro_variation_strength = 0.18;
uniform float macro_variation_scale = 0.04;
uniform float detail_noise_strength = 0.10;
uniform float detail_noise_scale = 0.45;
uniform float rock_detail_strength = 0.25;
uniform float snow_detail_strength = 0.08;
uniform float shore_wetness_strength = 0.28;
uniform float material_brightness = 1.32;
uniform float material_contrast = 1.0;

varying float terrain_height;
varying vec3 world_position;

float soft_band(float edge0, float edge1, float value) {
	if (abs(edge1 - edge0) < 0.0001) {
		return 0.0;
	}
	float x = clamp((value - edge0) / (edge1 - edge0), 0.0, 1.0);
	return x * x * (3.0 - 2.0 * x);
}

vec3 adjust_color(vec3 color) {
	color *= material_brightness;
	color = (color - vec3(0.5)) * material_contrast + vec3(0.5);
	return clamp(color, vec3(0.0), vec3(1.0));
}

void vertex() {
	terrain_height = VERTEX.y;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float normalized_height = clamp(COLOR.r, 0.0, 1.0);
	float slope = clamp(COLOR.g, 0.0, 1.0);
	float baked_shore_mask = clamp(COLOR.b, 0.0, 1.0);
	float baked_snow_mask = clamp(COLOR.a, 0.0, 1.0);
	float shore_width = max(height_scale * 0.10, 0.35);
	vec3 color = mix(lowland_color.rgb, grass_color.rgb, soft_band(0.20, 0.78, normalized_height));

	if (water_enabled) {
		if (terrain_height < water_level) {
			float underwater_depth = water_level - terrain_height;
			float seabed_amount = soft_band(0.0, max(height_scale * 0.35, 0.75), underwater_depth);
			color = mix(shore_color.rgb, seabed_color.rgb, seabed_amount);
		} else if (terrain_height < water_level + shore_width) {
			float dry_shore_amount = soft_band(0.0, shore_width, terrain_height - water_level);
			color = mix(shore_color.rgb, color, dry_shore_amount);
		}
	}

	float rock_amount = soft_band(rock_slope_threshold, min(1.0, rock_slope_threshold + 0.25), slope);
	float snow_blend_width = max(height_scale * 0.12, 0.35);
	float snow_amount = max(soft_band(snow_height - snow_blend_width, snow_height + snow_blend_width, terrain_height), baked_snow_mask * 0.20);

	if (use_procedural_detail) {
		float macro_noise = texture(macro_noise_texture, world_position.xz * macro_variation_scale).r * 2.0 - 1.0;
		float detail_noise = texture(detail_noise_texture, world_position.xz * detail_noise_scale).r * 2.0 - 1.0;
		color *= 1.0 + macro_noise * macro_variation_strength;
		color *= 1.0 + detail_noise * detail_noise_strength * (1.0 - snow_amount * 0.45);
		vec3 detailed_rock = rock_color.rgb * (1.0 + detail_noise * rock_detail_strength);
		vec3 detailed_snow = snow_color.rgb * (1.0 + detail_noise * snow_detail_strength);
		color = mix(color, detailed_rock, rock_amount);
		color = mix(color, detailed_snow, snow_amount);
		if (water_enabled) {
			float wet_amount = max(1.0 - soft_band(0.0, shore_width, abs(terrain_height - water_level)), baked_shore_mask * 0.35);
			color = mix(color, color * 0.68, wet_amount * shore_wetness_strength);
		}
	} else {
		color = mix(color, rock_color.rgb, rock_amount);
		color = mix(color, snow_color.rgb, snow_amount);
	}

	ALBEDO = adjust_color(color);
	ROUGHNESS = mix(0.92, 0.64, rock_amount);
	SPECULAR = 0.18;
}
"""

var generated_resource_directory := "res://generated_terrain"
var seed := 1345
var water_enabled := true
var water_level := 0.0
var height_scale := 5.0
var snow_height := 5.0
var rock_slope_threshold := 0.44
var lowland_color := Color(0.15, 0.21, 0.09)
var grass_color := Color(0.24, 0.33, 0.15)
var shore_color := Color(0.52, 0.48, 0.30)
var seabed_color := Color(0.20, 0.17, 0.10)
var rock_color := Color(0.27, 0.24, 0.18)
var snow_color := Color(0.86, 0.84, 0.76)
var procedural_material_enabled := true
var macro_variation_strength := 0.18
var macro_variation_scale := 0.04
var detail_noise_strength := 0.10
var detail_noise_scale := 0.45
var rock_detail_strength := 0.25
var snow_detail_strength := 0.08
var shore_wetness_strength := 0.28
var material_brightness := 1.32
var material_contrast := 1.0

var _legacy_terrain_material: StandardMaterial3D
var _procedural_terrain_material: ShaderMaterial
var _simple_mask_terrain_material: ShaderMaterial
var _terrain_shader: Shader
var _terrain_macro_noise_texture: Texture2D
var _terrain_detail_noise_texture: Texture2D
var _saving_visual_resources := false


func configure(settings: Dictionary) -> void:
	generated_resource_directory = str(settings.get("generated_resource_directory", generated_resource_directory))
	seed = int(settings.get("seed", seed))
	water_enabled = bool(settings.get("water_enabled", water_enabled))
	water_level = float(settings.get("water_level", water_level))
	height_scale = float(settings.get("height_scale", height_scale))
	snow_height = float(settings.get("snow_height", snow_height))
	rock_slope_threshold = float(settings.get("rock_slope_threshold", rock_slope_threshold))
	lowland_color = settings.get("lowland_color", lowland_color) as Color
	grass_color = settings.get("grass_color", grass_color) as Color
	shore_color = settings.get("shore_color", shore_color) as Color
	seabed_color = settings.get("seabed_color", seabed_color) as Color
	rock_color = settings.get("rock_color", rock_color) as Color
	snow_color = settings.get("snow_color", snow_color) as Color
	procedural_material_enabled = bool(settings.get("procedural_material_enabled", procedural_material_enabled))
	macro_variation_strength = float(settings.get("macro_variation_strength", macro_variation_strength))
	macro_variation_scale = float(settings.get("macro_variation_scale", macro_variation_scale))
	detail_noise_strength = float(settings.get("detail_noise_strength", detail_noise_strength))
	detail_noise_scale = float(settings.get("detail_noise_scale", detail_noise_scale))
	rock_detail_strength = float(settings.get("rock_detail_strength", rock_detail_strength))
	snow_detail_strength = float(settings.get("snow_detail_strength", snow_detail_strength))
	shore_wetness_strength = float(settings.get("shore_wetness_strength", shore_wetness_strength))
	material_brightness = float(settings.get("material_brightness", material_brightness))
	material_contrast = float(settings.get("material_contrast", material_contrast))
	update_materials()


func get_material_for_encoding(encoding: String) -> Material:
	if encoding == TERRAIN_ENCODING_V5_MASKS:
		if procedural_material_enabled:
			return _get_or_create_procedural_terrain_material()
		return _get_or_create_simple_mask_terrain_material()
	return _get_or_create_legacy_terrain_material()


func update_materials() -> void:
	_update_terrain_shader_parameters()


func reset_noise_textures() -> void:
	_terrain_macro_noise_texture = null
	_terrain_detail_noise_texture = null
	update_materials()


func save_visual_resources(resource_directory: String) -> int:
	if _saving_visual_resources:
		return OK

	_saving_visual_resources = true
	update_materials()

	var macro_error := ResourceSaver.save(_get_or_create_terrain_macro_noise_texture(), "%s/%s" % [resource_directory, TERRAIN_MACRO_NOISE_PATH])
	if macro_error != OK:
		_saving_visual_resources = false
		return macro_error
	var detail_error := ResourceSaver.save(_get_or_create_terrain_detail_noise_texture(), "%s/%s" % [resource_directory, TERRAIN_DETAIL_NOISE_PATH])
	if detail_error != OK:
		_saving_visual_resources = false
		return detail_error
	var terrain_shader_error := ResourceSaver.save(_get_or_create_terrain_shader(), "%s/%s" % [resource_directory, TERRAIN_PROCEDURAL_SHADER_PATH])
	if terrain_shader_error != OK:
		_saving_visual_resources = false
		return terrain_shader_error

	var terrain_material_error := ResourceSaver.save(_get_or_create_procedural_terrain_material(), "%s/%s" % [resource_directory, TERRAIN_PROCEDURAL_MATERIAL_PATH])
	if terrain_material_error != OK:
		_saving_visual_resources = false
		return terrain_material_error

	var legacy_material_error := ResourceSaver.save(_get_or_create_legacy_terrain_material(), "%s/%s" % [resource_directory, TERRAIN_LEGACY_MATERIAL_PATH])
	if legacy_material_error != OK:
		_saving_visual_resources = false
		return legacy_material_error

	_reload_saved_visual_resources()
	_saving_visual_resources = false
	return OK


func is_saving() -> bool:
	return _saving_visual_resources


func _get_or_create_legacy_terrain_material() -> StandardMaterial3D:
	if _legacy_terrain_material == null:
		_legacy_terrain_material = _load_external_legacy_terrain_material()
		if _legacy_terrain_material == null:
			_legacy_terrain_material = StandardMaterial3D.new()
			_legacy_terrain_material.vertex_color_use_as_albedo = true
			_legacy_terrain_material.roughness = 0.9
	return _legacy_terrain_material


func _get_or_create_procedural_terrain_material() -> ShaderMaterial:
	if _procedural_terrain_material == null:
		_procedural_terrain_material = _load_external_shader_material(TERRAIN_PROCEDURAL_MATERIAL_PATH)
		if _procedural_terrain_material == null:
			_procedural_terrain_material = ShaderMaterial.new()
			_procedural_terrain_material.shader = _get_or_create_terrain_shader()
	_update_terrain_shader_parameters()
	return _procedural_terrain_material


func _get_or_create_simple_mask_terrain_material() -> ShaderMaterial:
	if _simple_mask_terrain_material == null:
		_simple_mask_terrain_material = ShaderMaterial.new()
		_simple_mask_terrain_material.shader = _get_or_create_terrain_shader()
	_update_terrain_shader_parameters()
	_simple_mask_terrain_material.set_shader_parameter("use_procedural_detail", false)
	return _simple_mask_terrain_material


func _get_or_create_terrain_shader() -> Shader:
	if _terrain_shader == null:
		_terrain_shader = _load_external_shader(TERRAIN_PROCEDURAL_SHADER_PATH)
		if _terrain_shader == null:
			_terrain_shader = Shader.new()
			_terrain_shader.code = TERRAIN_SHADER_CODE
	return _terrain_shader


func _update_terrain_shader_parameters() -> void:
	for material in [_procedural_terrain_material, _simple_mask_terrain_material]:
		if material == null:
			continue
		material.shader = _get_or_create_terrain_shader()
		material.set_shader_parameter("use_procedural_detail", material == _procedural_terrain_material and procedural_material_enabled)
		material.set_shader_parameter("water_enabled", water_enabled)
		material.set_shader_parameter("macro_noise_texture", _get_or_create_terrain_macro_noise_texture())
		material.set_shader_parameter("detail_noise_texture", _get_or_create_terrain_detail_noise_texture())
		material.set_shader_parameter("lowland_color", lowland_color)
		material.set_shader_parameter("grass_color", grass_color)
		material.set_shader_parameter("shore_color", shore_color)
		material.set_shader_parameter("seabed_color", seabed_color)
		material.set_shader_parameter("rock_color", rock_color)
		material.set_shader_parameter("snow_color", snow_color)
		material.set_shader_parameter("water_level", water_level)
		material.set_shader_parameter("height_scale", height_scale)
		material.set_shader_parameter("snow_height", snow_height)
		material.set_shader_parameter("rock_slope_threshold", rock_slope_threshold)
		material.set_shader_parameter("macro_variation_strength", macro_variation_strength)
		material.set_shader_parameter("macro_variation_scale", macro_variation_scale)
		material.set_shader_parameter("detail_noise_strength", detail_noise_strength)
		material.set_shader_parameter("detail_noise_scale", detail_noise_scale)
		material.set_shader_parameter("rock_detail_strength", rock_detail_strength)
		material.set_shader_parameter("snow_detail_strength", snow_detail_strength)
		material.set_shader_parameter("shore_wetness_strength", shore_wetness_strength)
		material.set_shader_parameter("material_brightness", material_brightness)
		material.set_shader_parameter("material_contrast", material_contrast)


func _get_or_create_terrain_macro_noise_texture() -> Texture2D:
	if _terrain_macro_noise_texture == null:
		_terrain_macro_noise_texture = _load_external_texture(TERRAIN_MACRO_NOISE_PATH)
		if _terrain_macro_noise_texture == null:
			_terrain_macro_noise_texture = _create_noise_texture(seed + 2197, 0.045, 256)
	return _terrain_macro_noise_texture


func _get_or_create_terrain_detail_noise_texture() -> Texture2D:
	if _terrain_detail_noise_texture == null:
		_terrain_detail_noise_texture = _load_external_texture(TERRAIN_DETAIL_NOISE_PATH)
		if _terrain_detail_noise_texture == null:
			_terrain_detail_noise_texture = _create_noise_texture(seed + 7919, 0.18, 256)
	return _terrain_detail_noise_texture


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


func _load_external_legacy_terrain_material() -> StandardMaterial3D:
	var path := _get_visual_resource_path(TERRAIN_LEGACY_MATERIAL_PATH)
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path, "StandardMaterial3D", ResourceLoader.CACHE_MODE_REPLACE) as StandardMaterial3D


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


func _reload_saved_visual_resources() -> void:
	_terrain_macro_noise_texture = _load_external_texture(TERRAIN_MACRO_NOISE_PATH)
	_terrain_detail_noise_texture = _load_external_texture(TERRAIN_DETAIL_NOISE_PATH)
	_terrain_shader = _load_external_shader(TERRAIN_PROCEDURAL_SHADER_PATH)
	_procedural_terrain_material = _load_external_shader_material(TERRAIN_PROCEDURAL_MATERIAL_PATH)
	_legacy_terrain_material = _load_external_legacy_terrain_material()
	update_materials()
