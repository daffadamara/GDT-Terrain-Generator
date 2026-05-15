@tool
extends MeshInstance3D
class_name ProceduralWater3D

enum WaterQuality { LIGHTWEIGHT, BALANCED, HIGH_FIDELITY }
enum WaterMotionPreset { CALM_LAKE, COASTAL, WINDY, FLAT_VISUAL, CUSTOM }

const WATER_PROCEDURAL_SHADER_PATH := "water_procedural_shader.res"
const WATER_PROCEDURAL_MATERIAL_PATH := "water_procedural_material.res"
const WATER_NOISE_PATH := "water_noise.res"

const WATER_SHADER_CODE := """
shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D water_noise_texture;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform vec4 water_color : source_color = vec4(0.17647, 0.46667, 0.40392, 0.8);
uniform vec4 mid_water_color : source_color = vec4(0.05882, 0.20392, 0.23922, 1.0);
uniform vec4 deep_water_color : source_color = vec4(0.02353, 0.08627, 0.13333, 1.0);
uniform vec4 foam_color : source_color = vec4(0.55982, 0.70500, 0.67298, 1.0);
uniform float water_alpha = 0.8;
uniform float wave_strength = 0.14;
uniform float foam_strength = 0.70;
uniform float refraction_strength = 0.025;
uniform float normal_strength = 0.25;
uniform float wave_scale = 1.0;
uniform float normal_tiling = 0.1;
uniform float foam_tiling = 0.5;
uniform float shore_alpha_fade = 0.3;
uniform float wave_speed = 0.14;
uniform float swell_scale = 42.0;
uniform float swell_cross_strength = 0.35;
uniform float ripple_strength = 0.16;
uniform float ripple_scale = 18.0;
uniform float surface_distortion = 0.22;
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
	float wavelength = max(swell_scale / max(wave_scale, 0.001), 0.001);
	float wave_a = sin(dot(VERTEX.xz, direction_a) / wavelength * 6.28318 + TIME * wave_speed * 3.14159);
	float wave_b = sin(dot(VERTEX.xz, direction_b) / (wavelength * 0.62) * 6.28318 - TIME * wave_speed * 2.15);
	float drift_noise = sample_noise(VERTEX.xz / (wavelength * 2.0) + vec2(TIME * wave_speed * 0.025, -TIME * wave_speed * 0.018)) * 2.0 - 1.0;
	float combined_wave = wave_a * (1.0 - swell_cross_strength * 0.35) + wave_b * swell_cross_strength * 0.45 + drift_noise * 0.08;
	VERTEX.y += combined_wave * wave_strength;
	wave_mask = clamp(combined_wave * 0.5 + 0.5, 0.0, 1.0);
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	water_view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec2 direction_a = normalize(primary_wave_direction);
	vec2 direction_b = normalize(secondary_wave_direction);
	float legacy_ripple_multiplier = max(normal_tiling, 0.05) / 0.1;
	float ripple_wavelength = max(ripple_scale / max(wave_scale * legacy_ripple_multiplier, 0.001), 0.001);
	vec2 scroll_a = world_position.xz / ripple_wavelength + direction_a * TIME * wave_speed * 0.08;
	vec2 scroll_b = world_position.xz / (ripple_wavelength * 0.57) + direction_b * TIME * wave_speed * 0.11;
	vec2 foam_scroll = world_position.xz / max(ripple_wavelength * 1.45 / max(foam_tiling, 0.001), 0.001) + normalize(primary_wave_direction + secondary_wave_direction) * TIME * wave_speed * 0.05;
	float noise_a = sample_noise(scroll_a);
	float noise_b = sample_noise(scroll_b);
	float foam_pattern = sample_noise(foam_scroll);
	float ripple = noise_a * 0.58 + noise_b * 0.42;
	vec2 distortion = vec2(noise_a - 0.5, noise_b - 0.5) * ripple_strength * normal_strength;
	float surface_lines = smoothstep(0.68, 0.94, ripple + wave_mask * 0.12);

	float swell_wavelength = max(swell_scale / max(wave_scale, 0.001), 0.001);
	float swell_phase_a = dot(world_position.xz, direction_a) / swell_wavelength * 6.28318 + TIME * wave_speed * 3.14159;
	float swell_phase_b = dot(world_position.xz, direction_b) / (swell_wavelength * 0.62) * 6.28318 - TIME * wave_speed * 2.15;
	float slope_a = cos(swell_phase_a) * wave_strength * 6.28318 / swell_wavelength * (1.0 - swell_cross_strength * 0.35);
	float slope_b = cos(swell_phase_b) * wave_strength * 6.28318 / (swell_wavelength * 0.62) * swell_cross_strength * 0.45;
	vec2 swell_slope = direction_a * slope_a + direction_b * slope_b;
	vec2 normal_slope = swell_slope + distortion * (1.65 + surface_distortion * 2.25);
	NORMAL = normalize(NORMAL + vec3(normal_slope.x, 0.0, normal_slope.y));
	float view_alignment = clamp(abs(dot(NORMAL, VIEW)), 0.075, 1.0);
	float fresnel = pow(1.0 - view_alignment, 2.35);

	float raw_scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 normalized_device_coordinates = vec3(SCREEN_UV * 2.0 - 1.0, raw_scene_depth);
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(normalized_device_coordinates, 1.0);
	scene_view.xyz /= scene_view.w;
	float scene_view_depth = -scene_view.z;
	float depth_delta = max(scene_view_depth - water_view_depth, 0.0);
	float corrected_depth_delta = depth_delta * view_alignment;
	float depth_gradient = fwidth(raw_scene_depth);
	float depth_amount = clamp(corrected_depth_delta / max(depth_fade_distance, 0.001), 0.0, 1.0) * quality_depth_enabled;
	float shallow_amount = 1.0 - smoothstep(0.0, 0.35, depth_amount);
	float mid_amount = smoothstep(0.08, 0.62, depth_amount);
	float deep_amount = smoothstep(0.48, 1.0, depth_amount);
	vec3 water_tint = mix(water_color.rgb, mid_water_color.rgb, mid_amount);
	water_tint = mix(water_tint, deep_water_color.rgb, deep_amount);

	vec3 refracted = texture(screen_texture, SCREEN_UV + distortion * surface_distortion * refraction_strength * quality_refraction_enabled).rgb;
	vec3 color = mix(water_tint, refracted, 0.14 * quality_refraction_enabled * (1.0 - shallow_amount * 0.55));
	color *= 0.96 + ripple * 0.07 * ripple_strength;
	color = mix(color, color + vec3(0.08, 0.13, 0.15), surface_lines * ripple_strength * (0.08 + fresnel * 0.18));
	color = mix(color, vec3(0.62, 0.84, 0.94), fresnel * 0.30);

	float depth_edge = smoothstep(0.00005, 0.0012, depth_gradient);
	float wet_edge = smoothstep(0.0, max(foam_cutoff * 0.38, 0.001), corrected_depth_delta);
	float contact_falloff = 1.0 - smoothstep(max(foam_cutoff * 0.75, 0.001), max(foam_cutoff * 5.8, 0.002), corrected_depth_delta);
	float shoreline_band = wet_edge * contact_falloff;
	float shallow_shelf = (1.0 - smoothstep(0.05, 0.34, depth_amount)) * smoothstep(0.0, 0.13, depth_amount);
	float shore_contact = max(depth_edge * shoreline_band, max(shoreline_band, shallow_shelf * 0.42)) * quality_depth_enabled;
	float broad_breakup = mix(0.68, 1.0, smoothstep(0.24, 0.86, foam_pattern + wave_mask * 0.05));
	float feather = 1.0 - smoothstep(0.82, 1.0, shoreline_band);
	float crest_lines = smoothstep(0.92, 0.995, wave_mask) * smoothstep(0.78, 0.96, foam_pattern);
	float shore_foam = shore_contact * broad_breakup * (0.72 + feather * 0.28);
	float crest_foam = crest_lines * 0.018 * ripple_strength * (1.0 - shore_contact);
	float foam = clamp((shore_foam + crest_foam) * foam_strength, 0.0, 1.0);
	color = mix(color, foam_color.rgb, foam);
	float shore_fade = (1.0 - smoothstep(0.0, max(shore_alpha_fade, 0.001), corrected_depth_delta)) * quality_depth_enabled;
	float alpha = mix(water_alpha, water_alpha * 0.36, shore_fade);
	float grazing_opacity = fresnel * (0.18 + clamp(wave_strength * 0.08, 0.0, 0.22));

	ALBEDO = clamp(color, vec3(0.0), vec3(1.0));
	ALPHA = clamp(alpha + foam * 0.14 + grazing_opacity * (1.0 - shore_fade * 0.35), 0.0, 1.0);
	ROUGHNESS = mix(0.06, 0.24, depth_amount) - fresnel * 0.025;
	SPECULAR = mix(0.62, 0.92, fresnel);
}
"""

@export_category("Water")

## Enables this water surface. Disable to hide it without removing the node.
@export var water_enabled: bool = true:
	set(value):
		if water_enabled == value:
			return
		water_enabled = value
		_update_water()

## Width and depth of the water surface in Godot units.
@export_range(1.0, 4096.0, 1.0) var water_size: float = 64.0:
	set(value):
		var clamped_value := maxf(1.0, value)
		if is_equal_approx(water_size, clamped_value):
			return
		water_size = clamped_value
		_rebuild_mesh()

## World Y height of the water surface.
@export_range(-512.0, 512.0, 0.1) var water_level: float = 0.0:
	set(value):
		if is_equal_approx(water_level, value):
			return
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

## Motion style for the water surface. Pick this first, then fine-tune advanced motion controls.
@export_enum("Calm Lake", "Coastal", "Windy", "Flat Visual", "Custom") var motion_preset: int = WaterMotionPreset.COASTAL:
	set(value):
		motion_preset = clampi(value, WaterMotionPreset.CALM_LAKE, WaterMotionPreset.CUSTOM)
		_apply_motion_preset()

## Height of animated waves. Set to 0 for a flat animated surface.
@export_range(0.0, 4.0, 0.01) var wave_strength: float = 0.14:
	set(value):
		wave_strength = maxf(0.0, value)
		_mark_motion_preset_custom()
		_update_material()

## Strength of shoreline foam and subtle wave-crest highlights.
@export_range(0.0, 1.0, 0.01) var foam_strength: float = 0.70:
	set(value):
		foam_strength = clampf(value, 0.0, 1.0)
		_mark_motion_preset_custom()
		_update_material()

## Strength of screen-space refraction. High values are more visible but can shimmer.
@export_range(0.0, 0.12, 0.001) var refraction_strength: float = 0.025:
	set(value):
		refraction_strength = clampf(value, 0.0, 0.12)
		_update_material()

@export_group("Advanced")

## Wavelength for broad vertex swell. Larger values make calmer, wider coastal waves.
@export_range(4.0, 512.0, 0.1) var swell_scale: float = 42.0:
	set(value):
		swell_scale = maxf(4.0, value)
		_mark_motion_preset_custom()
		_update_material()

## Strength of the secondary crossing swell. Lower values keep motion cleaner.
@export_range(0.0, 1.0, 0.01) var swell_cross_strength: float = 0.35:
	set(value):
		swell_cross_strength = clampf(value, 0.0, 1.0)
		_mark_motion_preset_custom()
		_update_material()

## Strength of fine surface ripples and normal perturbation.
@export_range(0.0, 1.0, 0.01) var ripple_strength: float = 0.16:
	set(value):
		ripple_strength = clampf(value, 0.0, 1.0)
		_mark_motion_preset_custom()
		_update_material()

## Wavelength for fine surface ripples. Larger values make smoother water.
@export_range(1.0, 256.0, 0.1) var ripple_scale: float = 18.0:
	set(value):
		ripple_scale = maxf(1.0, value)
		_mark_motion_preset_custom()
		_update_material()

## Multiplier for screen-space distortion. Keep low for readable editor water.
@export_range(0.0, 1.0, 0.01) var surface_distortion: float = 0.22:
	set(value):
		surface_distortion = clampf(value, 0.0, 1.0)
		_mark_motion_preset_custom()
		_update_material()

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
		_mark_motion_preset_custom()
		_update_material()

## Legacy compatibility multiplier for older saved scenes. Prefer Swell Scale and Ripple Scale.
@export_range(0.001, 2.0, 0.001) var wave_scale: float = 1.0:
	set(value):
		wave_scale = maxf(0.001, value)
		_update_material()

## Legacy compatibility multiplier for older saved scenes. Prefer Ripple Strength and Ripple Scale.
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
@export_range(0.0, 4.0, 0.01) var wave_speed: float = 0.14:
	set(value):
		wave_speed = maxf(0.0, value)
		_mark_motion_preset_custom()
		_update_material()

## Primary travel direction for large waves.
@export var primary_wave_direction: Vector2 = Vector2(1.0, 0.27):
	set(value):
		primary_wave_direction = value if value.length_squared() > 0.0001 else Vector2.RIGHT
		_mark_motion_preset_custom()
		_update_material()

## Secondary travel direction for crossing wave motion.
@export var secondary_wave_direction: Vector2 = Vector2(-0.38, 1.0):
	set(value):
		secondary_wave_direction = value if value.length_squared() > 0.0001 else Vector2.UP
		_mark_motion_preset_custom()
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
		var clamped_value := clampi(value, 1, 1024)
		if mesh_subdivisions == clamped_value:
			return
		mesh_subdivisions = clamped_value
		_rebuild_mesh()

## Folder for saving water shader, material, and noise resources.
@export var generated_resource_directory: String = "res://generated_terrain"

var _water_material: ShaderMaterial
var _water_shader: Shader
var _water_noise_texture: Texture2D
var _water_shader_code_applied := false
var _material_update_queued := false
var _flushing_material_update := false
var _applying_motion_preset := false


func _init() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _ready() -> void:
	_update_water()


func configure_from_terrain(settings: Dictionary) -> void:
	var next_resource_directory := str(settings.get("generated_resource_directory", generated_resource_directory))
	var next_enabled := bool(settings.get("water_enabled", water_enabled))
	var next_size := maxf(1.0, float(settings.get("water_size", water_size)))
	var next_level := float(settings.get("water_level", water_level))
	var next_color := settings.get("water_color", water_color) as Color
	var next_alpha := clampf(float(settings.get("water_alpha", water_alpha)), 0.0, 1.0)

	generated_resource_directory = next_resource_directory
	water_enabled = next_enabled
	water_size = next_size
	water_level = next_level
	water_color = next_color
	water_alpha = next_alpha


func save_visual_resources(resource_directory: String) -> int:
	generated_resource_directory = resource_directory
	_flush_material_update()
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
	if Engine.is_editor_hint() and not _flushing_material_update:
		_queue_material_update()
		return
	var water_material := _get_or_create_water_material()
	if material_override != water_material:
		material_override = water_material
	_apply_shader_parameters()


func _queue_material_update() -> void:
	if _material_update_queued:
		return
	_material_update_queued = true
	call_deferred("_flush_material_update")


func _flush_material_update() -> void:
	if _flushing_material_update:
		return
	_material_update_queued = false
	_flushing_material_update = true
	_update_material()
	_flushing_material_update = false


func _apply_motion_preset() -> void:
	if _applying_motion_preset or motion_preset == WaterMotionPreset.CUSTOM:
		return

	_applying_motion_preset = true
	match motion_preset:
		WaterMotionPreset.CALM_LAKE:
			wave_strength = 0.045
			wave_speed = 0.08
			swell_scale = 72.0
			swell_cross_strength = 0.15
			ripple_strength = 0.07
			ripple_scale = 30.0
			surface_distortion = 0.10
			foam_strength = 0.45
		WaterMotionPreset.WINDY:
			wave_strength = 0.32
			wave_speed = 0.28
			swell_scale = 30.0
			swell_cross_strength = 0.55
			ripple_strength = 0.32
			ripple_scale = 11.0
			surface_distortion = 0.42
			foam_strength = 0.90
		WaterMotionPreset.FLAT_VISUAL:
			wave_strength = 0.0
			wave_speed = 0.0
			swell_scale = 80.0
			swell_cross_strength = 0.0
			ripple_strength = 0.0
			ripple_scale = 30.0
			surface_distortion = 0.0
			foam_strength = 0.35
		_:
			wave_strength = 0.14
			wave_speed = 0.14
			swell_scale = 42.0
			swell_cross_strength = 0.35
			ripple_strength = 0.16
			ripple_scale = 18.0
			surface_distortion = 0.22
			foam_strength = 0.70
	_applying_motion_preset = false
	_queue_material_update()


func _mark_motion_preset_custom() -> void:
	if _applying_motion_preset or motion_preset == WaterMotionPreset.CUSTOM:
		return
	motion_preset = WaterMotionPreset.CUSTOM


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
	return _water_material


func _get_or_create_water_shader() -> Shader:
	if _water_shader == null:
		_water_shader = _load_external_shader(WATER_PROCEDURAL_SHADER_PATH)
		if _water_shader == null:
			_water_shader = Shader.new()
		_water_shader_code_applied = false
	if not _water_shader_code_applied or _water_shader.code != WATER_SHADER_CODE:
		_water_shader.code = WATER_SHADER_CODE
		_water_shader_code_applied = true
	return _water_shader


func _apply_shader_parameters() -> void:
	if _water_material == null:
		return
	var color := water_color
	color.a = water_alpha
	var water_shader := _get_or_create_water_shader()
	if _water_material.shader != water_shader:
		_water_material.shader = water_shader
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
	_water_material.set_shader_parameter("swell_scale", swell_scale)
	_water_material.set_shader_parameter("swell_cross_strength", swell_cross_strength)
	_water_material.set_shader_parameter("ripple_strength", ripple_strength)
	_water_material.set_shader_parameter("ripple_scale", ripple_scale)
	_water_material.set_shader_parameter("surface_distortion", surface_distortion)
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
	_water_shader_code_applied = false
