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
const TERRAIN_FAR_COLOR_CACHE_PATH := "terrain_far_color_cache.res"

const TERRAIN_SHADER_CODE := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform bool use_procedural_detail = true;
uniform int material_mode = 0;
uniform bool snow_enabled = true;
uniform bool lowland_layer_enabled = false;
uniform bool ground_layer_enabled = true;
uniform bool upper_layer_enabled = false;
uniform bool rocky_layer_enabled = true;
uniform bool cliff_layer_enabled = true;
uniform bool snow_layer_enabled = true;
uniform sampler2D macro_noise_texture;
uniform sampler2D detail_noise_texture;
uniform sampler2D lowland_albedo_texture : source_color, repeat_enable;
uniform sampler2D lowland_normal_texture : hint_normal, repeat_enable;
uniform sampler2D lowland_roughness_texture : repeat_enable;
uniform sampler2D lowland_height_texture : repeat_enable;
uniform sampler2D ground_albedo_texture : source_color, repeat_enable;
uniform sampler2D ground_normal_texture : hint_normal, repeat_enable;
uniform sampler2D ground_roughness_texture : repeat_enable;
uniform sampler2D ground_height_texture : repeat_enable;
uniform sampler2D upper_albedo_texture : source_color, repeat_enable;
uniform sampler2D upper_normal_texture : hint_normal, repeat_enable;
uniform sampler2D upper_roughness_texture : repeat_enable;
uniform sampler2D upper_height_texture : repeat_enable;
uniform sampler2D rocky_albedo_texture : source_color, repeat_enable;
uniform sampler2D rocky_normal_texture : hint_normal, repeat_enable;
uniform sampler2D rocky_roughness_texture : repeat_enable;
uniform sampler2D rocky_height_texture : repeat_enable;
uniform sampler2D cliff_albedo_texture : source_color, repeat_enable;
uniform sampler2D cliff_normal_texture : hint_normal, repeat_enable;
uniform sampler2D cliff_roughness_texture : repeat_enable;
uniform sampler2D cliff_height_texture : repeat_enable;
uniform sampler2D snow_albedo_texture : source_color, repeat_enable;
uniform sampler2D snow_normal_texture : hint_normal, repeat_enable;
uniform sampler2D snow_roughness_texture : repeat_enable;
uniform sampler2D snow_height_texture : repeat_enable;
uniform sampler2D paint_lowland_albedo_texture : source_color, repeat_enable;
uniform sampler2D paint_lowland_normal_texture : hint_normal, repeat_enable;
uniform sampler2D paint_lowland_roughness_texture : repeat_enable;
uniform sampler2D paint_lowland_height_texture : repeat_enable;
uniform sampler2D paint_ground_albedo_texture : source_color, repeat_enable;
uniform sampler2D paint_ground_normal_texture : hint_normal, repeat_enable;
uniform sampler2D paint_ground_roughness_texture : repeat_enable;
uniform sampler2D paint_ground_height_texture : repeat_enable;
uniform sampler2D paint_upper_albedo_texture : source_color, repeat_enable;
uniform sampler2D paint_upper_normal_texture : hint_normal, repeat_enable;
uniform sampler2D paint_upper_roughness_texture : repeat_enable;
uniform sampler2D paint_upper_height_texture : repeat_enable;
uniform sampler2D paint_rocky_albedo_texture : source_color, repeat_enable;
uniform sampler2D paint_rocky_normal_texture : hint_normal, repeat_enable;
uniform sampler2D paint_rocky_roughness_texture : repeat_enable;
uniform sampler2D paint_rocky_height_texture : repeat_enable;
uniform sampler2D paint_cliff_albedo_texture : source_color, repeat_enable;
uniform sampler2D paint_cliff_normal_texture : hint_normal, repeat_enable;
uniform sampler2D paint_cliff_roughness_texture : repeat_enable;
uniform sampler2D paint_cliff_height_texture : repeat_enable;
uniform sampler2D paint_snow_albedo_texture : source_color, repeat_enable;
uniform sampler2D paint_snow_normal_texture : hint_normal, repeat_enable;
uniform sampler2D paint_snow_roughness_texture : repeat_enable;
uniform sampler2D paint_snow_height_texture : repeat_enable;
uniform vec4 lowland_color : source_color = vec4(0.15, 0.21, 0.09, 1.0);
uniform vec4 grass_color : source_color = vec4(0.24, 0.33, 0.15, 1.0);
uniform vec4 rock_color : source_color = vec4(0.27, 0.24, 0.18, 1.0);
uniform vec4 snow_color : source_color = vec4(0.86, 0.84, 0.76, 1.0);
uniform float height_scale = 2.0;
uniform float snow_height = 5.0;
uniform float rock_slope_threshold = 0.44;
uniform float texture_tile_scale = 0.18;
uniform bool macro_texture_tiling_enabled = true;
uniform vec3 texture_focus_position = vec3(0.0);
uniform float close_texture_tile_scale = 0.20;
uniform float medium_texture_tile_scale = 0.03;
uniform float far_texture_tile_scale = 0.01;
uniform float close_texture_radius = 24.0;
uniform float medium_texture_radius = 48.0;
uniform float far_texture_radius = 92.0;
uniform float layer_blend_softness = 0.18;
uniform float texture_normal_strength = 0.75;
uniform float roughness_multiplier = 1.0;
uniform float height_blend_strength = 0.12;
uniform bool texture_bombing_enabled = true;
uniform float texture_bombing_strength = 0.55;
uniform float texture_bombing_cell_scale = 0.65;
uniform int texture_bombing_samples = 2;
uniform int material_performance_preset = 2;
uniform bool far_material_cache_enabled = true;
uniform sampler2D far_material_cache_texture : source_color, filter_linear, repeat_disable;
uniform float terrain_world_size = 64.0;
uniform float macro_variation_strength = 0.18;
uniform float macro_variation_scale = 0.04;
uniform float detail_noise_strength = 0.10;
uniform float detail_noise_scale = 0.45;
uniform float rock_detail_strength = 0.25;
uniform float snow_detail_strength = 0.08;
uniform float material_brightness = 1.2;
uniform float material_contrast = 1.05;

varying float terrain_height;
varying vec3 world_position;
varying vec3 world_normal;

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

vec3 macro_tile_weights() {
	if (!macro_texture_tiling_enabled) {
		return vec3(0.0, 1.0, 0.0);
	}

	float focus_distance = distance(world_position.xz, texture_focus_position.xz);
	float close_radius = max(close_texture_radius, 0.001);
	float medium_radius = max(medium_texture_radius, close_radius + 0.001);
	float far_radius = max(far_texture_radius, medium_radius + 0.001);
	float close_weight = 1.0 - soft_band(close_radius, medium_radius, focus_distance);
	float far_weight = soft_band(medium_radius, far_radius, focus_distance);
	float medium_weight = max(1.0 - close_weight - far_weight, 0.0);
	return vec3(close_weight, medium_weight, far_weight);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 rotate_quarter(vec2 uv, float rotation_index) {
	float r = floor(mod(rotation_index, 4.0));
	if (r < 0.5) {
		return uv;
	}
	if (r < 1.5) {
		return vec2(-uv.y, uv.x);
	}
	if (r < 2.5) {
		return -uv;
	}
	return vec2(uv.y, -uv.x);
}

vec2 bombed_uv_from_cell(vec2 uv, vec2 cell, float cell_size) {
	vec2 local = uv / cell_size - cell - vec2(0.5);
	float h1 = hash12(cell);
	float h2 = hash12(cell + vec2(17.0, 43.0));
	float h3 = hash12(cell + vec2(71.0, 11.0));
	vec2 transformed = rotate_quarter(local, floor(h1 * 4.0));
	transformed.x *= h2 < 0.5 ? -1.0 : 1.0;
	transformed.y *= h3 < 0.5 ? -1.0 : 1.0;
	vec2 random_offset = vec2(hash12(cell + vec2(5.0, 19.0)), hash12(cell + vec2(29.0, 7.0))) - vec2(0.5);
	return (cell + transformed + vec2(0.5)) * cell_size + random_offset * texture_bombing_strength * cell_size;
}

vec4 sample_bombed_cell(sampler2D source_texture, vec2 uv, vec2 cell, float cell_size, float weight, inout float total_weight) {
	total_weight += weight;
	return texture(source_texture, bombed_uv_from_cell(uv, cell, cell_size)) * weight;
}

vec4 sample_bombed_limited(sampler2D source_texture, vec2 uv, int sample_limit) {
	int effective_samples = min(texture_bombing_samples, sample_limit);
	if (!texture_bombing_enabled || effective_samples <= 0) {
		return texture(source_texture, uv);
	}

	float cell_size = max(texture_bombing_cell_scale, 0.025);
	vec2 cell_uv = uv / cell_size;
	vec2 base_cell = floor(cell_uv);
	vec2 local_blend = smoothstep(vec2(0.18), vec2(0.82), fract(cell_uv));
	float total_weight = 0.0;
	vec4 result = sample_bombed_cell(source_texture, uv, base_cell, cell_size, (1.0 - local_blend.x) * (1.0 - local_blend.y), total_weight);
	if (effective_samples == 1) {
		total_weight = 0.0;
		result = sample_bombed_cell(source_texture, uv, base_cell, cell_size, 1.0 - local_blend.x, total_weight);
		result += sample_bombed_cell(source_texture, uv, base_cell + vec2(1.0, 0.0), cell_size, local_blend.x, total_weight);
		return result / max(total_weight, 0.0001);
	}
	result += sample_bombed_cell(source_texture, uv, base_cell + vec2(1.0, 0.0), cell_size, local_blend.x * (1.0 - local_blend.y), total_weight);
	result += sample_bombed_cell(source_texture, uv, base_cell + vec2(0.0, 1.0), cell_size, (1.0 - local_blend.x) * local_blend.y, total_weight);
	result += sample_bombed_cell(source_texture, uv, base_cell + vec2(1.0, 1.0), cell_size, local_blend.x * local_blend.y, total_weight);
	return result / max(total_weight, 0.0001);
}

vec4 sample_bombed(sampler2D source_texture, vec2 uv) {
	return sample_bombed_limited(source_texture, uv, texture_bombing_samples);
}

vec4 sample_macro_bombed(sampler2D source_texture, vec3 tile_weights, vec2 close_uv, vec2 medium_uv, vec2 far_uv, float layer_scale) {
	if (!macro_texture_tiling_enabled) {
		return sample_bombed(source_texture, medium_uv * layer_scale);
	}

	vec4 result = vec4(0.0);
	if (tile_weights.x > 0.001) {
		int close_samples = material_performance_preset >= 2 ? min(texture_bombing_samples, 1) : texture_bombing_samples;
		result += sample_bombed_limited(source_texture, close_uv * layer_scale, close_samples) * tile_weights.x;
	}
	if (tile_weights.y > 0.001) {
		int medium_samples = material_performance_preset == 0 ? texture_bombing_samples : min(texture_bombing_samples, 1);
		result += sample_bombed_limited(source_texture, medium_uv * layer_scale, medium_samples) * tile_weights.y;
	}
	if (tile_weights.z > 0.001) {
		int far_samples = material_performance_preset == 0 ? texture_bombing_samples : 0;
		result += sample_bombed_limited(source_texture, far_uv * layer_scale, far_samples) * tile_weights.z;
	}
	return result;
}

vec2 terrain_cache_uv() {
	float half_size = max(terrain_world_size * 0.5, 0.001);
	return clamp((world_position.xz + vec2(half_size)) / max(terrain_world_size, 0.001), vec2(0.0), vec2(1.0));
}

vec3 sample_triplanar_albedo(sampler2D source_texture, vec3 position, vec3 normal, float tile_scale) {
	vec3 weights = pow(abs(normal), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	vec3 x_sample = texture(source_texture, position.zy * tile_scale).rgb;
	vec3 y_sample = texture(source_texture, position.xz * tile_scale).rgb;
	vec3 z_sample = texture(source_texture, position.xy * tile_scale).rgb;
	return x_sample * weights.x + y_sample * weights.y + z_sample * weights.z;
}

float sample_triplanar_scalar(sampler2D source_texture, vec3 position, vec3 normal, float tile_scale) {
	vec3 weights = pow(abs(normal), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	float x_sample = texture(source_texture, position.zy * tile_scale).r;
	float y_sample = texture(source_texture, position.xz * tile_scale).r;
	float z_sample = texture(source_texture, position.xy * tile_scale).r;
	return x_sample * weights.x + y_sample * weights.y + z_sample * weights.z;
}

vec3 sample_triplanar_normal(sampler2D source_texture, vec3 position, vec3 normal, float tile_scale) {
	vec3 weights = pow(abs(normal), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	vec3 x_sample = texture(source_texture, position.zy * tile_scale).rgb;
	vec3 y_sample = texture(source_texture, position.xz * tile_scale).rgb;
	vec3 z_sample = texture(source_texture, position.xy * tile_scale).rgb;
	vec3 normal_sample = (x_sample * weights.x + y_sample * weights.y + z_sample * weights.z) * 2.0 - 1.0;
	normal_sample.xy *= texture_normal_strength;
	return normalize(normal_sample) * 0.5 + 0.5;
}

float sample_bombed_scalar(sampler2D source_texture, vec2 uv) {
	return sample_bombed(source_texture, uv).r;
}

float sample_macro_bombed_scalar(sampler2D source_texture, vec3 tile_weights, vec2 close_uv, vec2 medium_uv, vec2 far_uv, float layer_scale) {
	return sample_macro_bombed(source_texture, tile_weights, close_uv, medium_uv, far_uv, layer_scale).r;
}

vec3 sample_bombed_normal(sampler2D source_texture, vec2 uv) {
	vec3 normal_sample = sample_bombed(source_texture, uv).rgb * 2.0 - 1.0;
	normal_sample.xy *= texture_normal_strength;
	return normalize(normal_sample) * 0.5 + 0.5;
}

vec3 sample_macro_bombed_normal(sampler2D source_texture, vec3 tile_weights, vec2 close_uv, vec2 medium_uv, vec2 far_uv, float layer_scale) {
	vec3 normal_sample = sample_macro_bombed(source_texture, tile_weights, close_uv, medium_uv, far_uv, layer_scale).rgb * 2.0 - 1.0;
	normal_sample.xy *= texture_normal_strength;
	return normalize(normal_sample) * 0.5 + 0.5;
}

void vertex() {
	terrain_height = VERTEX.y;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_NORMAL_MATRIX * NORMAL).xyz);
}

void fragment() {
	float normalized_height = clamp((terrain_height / max(height_scale, 0.001) + 1.0) * 0.5, 0.0, 1.0);
	float slope = clamp(1.0 - world_normal.y, 0.0, 1.0);
	vec4 painted_weights_rgba = clamp(COLOR, vec4(0.0), vec4(1.0));
	vec2 painted_weights_uv2 = clamp(UV2, vec2(0.0), vec2(1.0));
	float painted_total = painted_weights_rgba.r + painted_weights_rgba.g + painted_weights_rgba.b + painted_weights_rgba.a + painted_weights_uv2.x + painted_weights_uv2.y;
	vec3 color = mix(lowland_color.rgb, grass_color.rgb, soft_band(0.20, 0.78, normalized_height));

	float rock_amount = soft_band(rock_slope_threshold, min(1.0, rock_slope_threshold + 0.25), slope);
	float snow_blend_width = max(height_scale * 0.12, 0.35);
	float snow_amount = snow_enabled ? soft_band(snow_height - snow_blend_width, snow_height + snow_blend_width, terrain_height) : 0.0;

	if (use_procedural_detail && material_mode != 1) {
		float macro_noise = texture(macro_noise_texture, world_position.xz * macro_variation_scale).r * 2.0 - 1.0;
		float detail_noise = texture(detail_noise_texture, world_position.xz * detail_noise_scale).r * 2.0 - 1.0;
		color *= 1.0 + macro_noise * macro_variation_strength;
		color *= 1.0 + detail_noise * detail_noise_strength * (1.0 - snow_amount * 0.45);
		vec3 detailed_rock = rock_color.rgb * (1.0 + detail_noise * rock_detail_strength);
		vec3 detailed_snow = snow_color.rgb * (1.0 + detail_noise * snow_detail_strength);
		color = mix(color, detailed_rock, rock_amount);
		color = mix(color, detailed_snow, snow_amount);
	} else {
		color = mix(color, rock_color.rgb, rock_amount);
		color = mix(color, snow_color.rgb, snow_amount);
	}

	float roughness = mix(0.92, 0.64, rock_amount);

	if (material_mode != 1 && painted_total > 0.001) {
		float painted_lowland = painted_weights_rgba.r / max(painted_total, 0.0001);
		float painted_ground = painted_weights_rgba.g / max(painted_total, 0.0001);
		float painted_upper = painted_weights_rgba.b / max(painted_total, 0.0001);
		float painted_rocky = painted_weights_rgba.a / max(painted_total, 0.0001);
		float painted_cliff = painted_weights_uv2.x / max(painted_total, 0.0001);
		float painted_snow = painted_weights_uv2.y / max(painted_total, 0.0001);
		float paint_opacity = clamp(painted_total, 0.0, 1.0);
		vec3 painted_color = lowland_color.rgb * painted_lowland
			+ grass_color.rgb * (painted_ground + painted_upper)
			+ rock_color.rgb * (painted_rocky + painted_cliff)
			+ snow_color.rgb * painted_snow;
		color = mix(color, painted_color, paint_opacity);
		roughness = mix(roughness, 0.86, paint_opacity);
	}

	if (material_mode == 1) {
		float blend_softness = max(layer_blend_softness, 0.001);
		vec3 tile_weights = macro_tile_weights();
		float base_tile_scale = max(texture_tile_scale, 0.001);
		vec2 close_uv = world_position.xz * max(close_texture_tile_scale, 0.001);
		vec2 medium_uv = world_position.xz * (macro_texture_tiling_enabled ? max(medium_texture_tile_scale, 0.001) : base_tile_scale);
		vec2 far_uv = world_position.xz * max(far_texture_tile_scale, 0.001);
		float cliff_tile_scale = max(texture_tile_scale, 0.001) * 1.10;
		float lowland_weight = 1.0 - soft_band(0.12, 0.28 + blend_softness, normalized_height);
		float ground_weight = soft_band(0.12, 0.30 + blend_softness, normalized_height) * (1.0 - soft_band(0.58, 0.80 + blend_softness, normalized_height));
		float upper_weight = soft_band(0.48, 0.78 + blend_softness, normalized_height) * (1.0 - rock_amount);
		float rocky_weight = rock_amount * (1.0 - soft_band(0.72, 0.92, slope));
		float cliff_weight = soft_band(max(0.0, rock_slope_threshold + 0.18), 0.88, slope);
		float snow_weight = snow_amount;

		float non_snow_weight = 1.0 - snow_weight;
		lowland_weight *= non_snow_weight;
		ground_weight *= non_snow_weight;
		upper_weight *= non_snow_weight;
		rocky_weight *= non_snow_weight;
		cliff_weight *= non_snow_weight;

		float far_cache_min_distance = max(far_texture_radius * 1.45, terrain_world_size * 0.34);
		if (material_performance_preset >= 2) {
			far_cache_min_distance = max(far_texture_radius * 1.05, terrain_world_size * 0.22);
		}
		float far_cache_horizontal_distance = distance(world_position.xz, texture_focus_position.xz);
		float far_cache_tile_threshold = material_performance_preset >= 2 ? 0.92 : 0.97;
		bool use_far_cache = far_material_cache_enabled && material_performance_preset > 0 && tile_weights.z > far_cache_tile_threshold && far_cache_horizontal_distance > far_cache_min_distance;
		if (use_far_cache) {
			color = texture(far_material_cache_texture, terrain_cache_uv()).rgb;
			roughness = clamp(0.88 * roughness_multiplier, 0.04, 1.0);
		} else {
			bool use_height_blend = material_performance_preset == 0 || (material_performance_preset == 1 && tile_weights.x > 0.20);
			if (use_height_blend) {
				float lowland_height = sample_macro_bombed_scalar(lowland_height_texture, tile_weights, close_uv, medium_uv, far_uv, 0.83);
				float ground_height = sample_macro_bombed_scalar(ground_height_texture, tile_weights, close_uv, medium_uv, far_uv, 1.0);
				float upper_height = sample_macro_bombed_scalar(upper_height_texture, tile_weights, close_uv, medium_uv, far_uv, 0.92);
				float rocky_height = sample_macro_bombed_scalar(rocky_height_texture, tile_weights, close_uv, medium_uv, far_uv, 1.15);
				float cliff_height = sample_triplanar_scalar(cliff_height_texture, world_position, world_normal, cliff_tile_scale);
				float snow_height_map = sample_macro_bombed_scalar(snow_height_texture, tile_weights, close_uv, medium_uv, far_uv, 0.72);
				lowland_weight *= mix(1.0, lowland_height, height_blend_strength);
				ground_weight *= mix(1.0, ground_height, height_blend_strength);
				upper_weight *= mix(1.0, upper_height, height_blend_strength);
				rocky_weight *= mix(1.0, rocky_height, height_blend_strength);
				cliff_weight *= mix(1.0, cliff_height, height_blend_strength);
				snow_weight *= mix(1.0, snow_height_map, height_blend_strength);
			}

			float total_weight = max(lowland_weight + ground_weight + upper_weight + rocky_weight + cliff_weight + snow_weight, 0.0001);
			lowland_weight /= total_weight;
			ground_weight /= total_weight;
			upper_weight /= total_weight;
			rocky_weight /= total_weight;
			cliff_weight /= total_weight;
			snow_weight /= total_weight;

			bool use_painted_material = painted_total > 0.001;
			float paint_opacity = clamp(painted_total, 0.0, 1.0);
			float painted_lowland = 0.0;
			float painted_ground = 0.0;
			float painted_upper = 0.0;
			float painted_rocky = 0.0;
			float painted_cliff = 0.0;
			float painted_snow = 0.0;
			if (use_painted_material) {
				float safe_painted_total = max(painted_total, 0.0001);
				painted_lowland = painted_weights_rgba.r / safe_painted_total;
				painted_ground = painted_weights_rgba.g / safe_painted_total;
				painted_upper = painted_weights_rgba.b / safe_painted_total;
				painted_rocky = painted_weights_rgba.a / safe_painted_total;
				painted_cliff = painted_weights_uv2.x / safe_painted_total;
				painted_snow = painted_weights_uv2.y / safe_painted_total;
			}

			vec3 lowland_albedo = sample_macro_bombed(lowland_albedo_texture, tile_weights, close_uv, medium_uv, far_uv, 0.83).rgb;
			vec3 ground_albedo = sample_macro_bombed(ground_albedo_texture, tile_weights, close_uv, medium_uv, far_uv, 1.0).rgb;
			vec3 upper_albedo = sample_macro_bombed(upper_albedo_texture, tile_weights, close_uv, medium_uv, far_uv, 0.92).rgb;
			vec3 rocky_albedo = sample_macro_bombed(rocky_albedo_texture, tile_weights, close_uv, medium_uv, far_uv, 1.15).rgb;
			vec3 cliff_albedo = sample_triplanar_albedo(cliff_albedo_texture, world_position, world_normal, cliff_tile_scale);
			vec3 snow_albedo = sample_macro_bombed(snow_albedo_texture, tile_weights, close_uv, medium_uv, far_uv, 0.72).rgb;
			color = lowland_albedo * lowland_weight + ground_albedo * ground_weight + upper_albedo * upper_weight + rocky_albedo * rocky_weight + cliff_albedo * cliff_weight + snow_albedo * snow_weight;
			bool use_painted_texture_material = use_painted_material && (material_performance_preset == 0 || tile_weights.z < 0.75);
			if (use_painted_texture_material) {
				vec3 paint_lowland_albedo = sample_macro_bombed(paint_lowland_albedo_texture, tile_weights, close_uv, medium_uv, far_uv, 0.83).rgb;
				vec3 paint_ground_albedo = sample_macro_bombed(paint_ground_albedo_texture, tile_weights, close_uv, medium_uv, far_uv, 1.0).rgb;
				vec3 paint_upper_albedo = sample_macro_bombed(paint_upper_albedo_texture, tile_weights, close_uv, medium_uv, far_uv, 0.92).rgb;
				vec3 paint_rocky_albedo = sample_macro_bombed(paint_rocky_albedo_texture, tile_weights, close_uv, medium_uv, far_uv, 1.15).rgb;
				vec3 paint_cliff_albedo = sample_triplanar_albedo(paint_cliff_albedo_texture, world_position, world_normal, cliff_tile_scale);
				vec3 paint_snow_albedo = sample_macro_bombed(paint_snow_albedo_texture, tile_weights, close_uv, medium_uv, far_uv, 0.72).rgb;
				vec3 paint_color = paint_lowland_albedo * painted_lowland + paint_ground_albedo * painted_ground + paint_upper_albedo * painted_upper + paint_rocky_albedo * painted_rocky + paint_cliff_albedo * painted_cliff + paint_snow_albedo * painted_snow;
				color = mix(color, paint_color, paint_opacity);
			} else if (use_painted_material) {
				vec3 paint_color = lowland_albedo * painted_lowland + ground_albedo * painted_ground + upper_albedo * painted_upper + rocky_albedo * painted_rocky + cliff_albedo * painted_cliff + snow_albedo * painted_snow;
				color = mix(color, paint_color, paint_opacity);
			}

			bool use_surface_detail = material_performance_preset == 0 || (material_performance_preset == 1 && tile_weights.z < 0.70) || (material_performance_preset >= 2 && tile_weights.x > 0.92);
			if (use_surface_detail) {
				vec3 lowland_normal = sample_macro_bombed_normal(lowland_normal_texture, tile_weights, close_uv, medium_uv, far_uv, 0.83);
				vec3 ground_normal = sample_macro_bombed_normal(ground_normal_texture, tile_weights, close_uv, medium_uv, far_uv, 1.0);
				vec3 upper_normal = sample_macro_bombed_normal(upper_normal_texture, tile_weights, close_uv, medium_uv, far_uv, 0.92);
				vec3 rocky_normal = sample_macro_bombed_normal(rocky_normal_texture, tile_weights, close_uv, medium_uv, far_uv, 1.15);
				vec3 cliff_normal = sample_triplanar_normal(cliff_normal_texture, world_position, world_normal, cliff_tile_scale);
				vec3 snow_normal = sample_macro_bombed_normal(snow_normal_texture, tile_weights, close_uv, medium_uv, far_uv, 0.72);
				vec3 procedural_normal = lowland_normal * lowland_weight + ground_normal * ground_weight + upper_normal * upper_weight + rocky_normal * rocky_weight + cliff_normal * cliff_weight + snow_normal * snow_weight;
				NORMAL_MAP = procedural_normal;
				if (use_painted_material) {
					vec3 paint_lowland_normal = sample_macro_bombed_normal(paint_lowland_normal_texture, tile_weights, close_uv, medium_uv, far_uv, 0.83);
					vec3 paint_ground_normal = sample_macro_bombed_normal(paint_ground_normal_texture, tile_weights, close_uv, medium_uv, far_uv, 1.0);
					vec3 paint_upper_normal = sample_macro_bombed_normal(paint_upper_normal_texture, tile_weights, close_uv, medium_uv, far_uv, 0.92);
					vec3 paint_rocky_normal = sample_macro_bombed_normal(paint_rocky_normal_texture, tile_weights, close_uv, medium_uv, far_uv, 1.15);
					vec3 paint_cliff_normal = sample_triplanar_normal(paint_cliff_normal_texture, world_position, world_normal, cliff_tile_scale);
					vec3 paint_snow_normal = sample_macro_bombed_normal(paint_snow_normal_texture, tile_weights, close_uv, medium_uv, far_uv, 0.72);
					vec3 paint_normal = paint_lowland_normal * painted_lowland + paint_ground_normal * painted_ground + paint_upper_normal * painted_upper + paint_rocky_normal * painted_rocky + paint_cliff_normal * painted_cliff + paint_snow_normal * painted_snow;
					NORMAL_MAP = mix(procedural_normal, paint_normal, paint_opacity);
				}
				NORMAL_MAP_DEPTH = texture_normal_strength;

				float lowland_roughness = sample_macro_bombed_scalar(lowland_roughness_texture, tile_weights, close_uv, medium_uv, far_uv, 0.83);
				float ground_roughness = sample_macro_bombed_scalar(ground_roughness_texture, tile_weights, close_uv, medium_uv, far_uv, 1.0);
				float upper_roughness = sample_macro_bombed_scalar(upper_roughness_texture, tile_weights, close_uv, medium_uv, far_uv, 0.92);
				float rocky_roughness = sample_macro_bombed_scalar(rocky_roughness_texture, tile_weights, close_uv, medium_uv, far_uv, 1.15);
				float cliff_roughness = sample_triplanar_scalar(cliff_roughness_texture, world_position, world_normal, cliff_tile_scale);
				float snow_roughness = sample_macro_bombed_scalar(snow_roughness_texture, tile_weights, close_uv, medium_uv, far_uv, 0.72);
				float procedural_roughness = lowland_roughness * lowland_weight + ground_roughness * ground_weight + upper_roughness * upper_weight + rocky_roughness * rocky_weight + cliff_roughness * cliff_weight + snow_roughness * snow_weight;
				roughness = procedural_roughness;
				if (use_painted_material) {
					float paint_lowland_roughness = sample_macro_bombed_scalar(paint_lowland_roughness_texture, tile_weights, close_uv, medium_uv, far_uv, 0.83);
					float paint_ground_roughness = sample_macro_bombed_scalar(paint_ground_roughness_texture, tile_weights, close_uv, medium_uv, far_uv, 1.0);
					float paint_upper_roughness = sample_macro_bombed_scalar(paint_upper_roughness_texture, tile_weights, close_uv, medium_uv, far_uv, 0.92);
					float paint_rocky_roughness = sample_macro_bombed_scalar(paint_rocky_roughness_texture, tile_weights, close_uv, medium_uv, far_uv, 1.15);
					float paint_cliff_roughness = sample_triplanar_scalar(paint_cliff_roughness_texture, world_position, world_normal, cliff_tile_scale);
					float paint_snow_roughness = sample_macro_bombed_scalar(paint_snow_roughness_texture, tile_weights, close_uv, medium_uv, far_uv, 0.72);
					float paint_roughness = paint_lowland_roughness * painted_lowland + paint_ground_roughness * painted_ground + paint_upper_roughness * painted_upper + paint_rocky_roughness * painted_rocky + paint_cliff_roughness * painted_cliff + paint_snow_roughness * painted_snow;
					roughness = mix(procedural_roughness, paint_roughness, paint_opacity);
				}
				roughness = clamp(roughness * roughness_multiplier, 0.04, 1.0);
			} else {
				roughness = clamp(0.88 * roughness_multiplier, 0.04, 1.0);
			}
		}
	}

	ALBEDO = adjust_color(color);
	ROUGHNESS = roughness;
	SPECULAR = 0.18;
}
"""

var generated_resource_directory := "res://generated_terrain"
var material_seed := 1345
var material_mode := 1
var height_scale := 2.0
var snow_enabled := true
var snow_height := 5.0
var rock_slope_threshold := 0.44
var lowland_color := Color(0.15, 0.21, 0.09)
var grass_color := Color(0.24, 0.33, 0.15)
var rock_color := Color(0.27, 0.24, 0.18)
var snow_color := Color(0.86, 0.84, 0.76)
var lowland_material_folder := "res://material/sand_03"
var ground_material_folder := "res://material/forest_ground"
var upper_material_folder := "res://material/aerial_grass_rock"
var rocky_material_folder := "res://material/rocky_terrain"
var cliff_material_folder := "res://material/rock_face"
var snow_material_folder := "res://material/snow"
var lowland_layer_enabled := false
var ground_layer_enabled := true
var upper_layer_enabled := false
var rocky_layer_enabled := true
var cliff_layer_enabled := true
var snow_layer_enabled := true
var texture_tile_scale := 0.18
var macro_texture_tiling_enabled := true
var texture_focus_position := Vector3.ZERO
var close_texture_tile_scale := 0.20
var medium_texture_tile_scale := 0.03
var far_texture_tile_scale := 0.01
var close_texture_radius := 24.0
var medium_texture_radius := 48.0
var far_texture_radius := 92.0
var layer_blend_softness := 0.18
var texture_normal_strength := 0.75
var roughness_multiplier := 1.0
var height_blend_strength := 0.12
var texture_bombing_enabled := true
var texture_bombing_strength := 0.55
var texture_bombing_cell_scale := 0.65
var texture_bombing_samples := 2
var material_performance_preset := 2
var far_material_cache_enabled := true
var far_material_cache_resolution := 512
var terrain_world_size := 64.0
var procedural_material_enabled := true
var macro_variation_strength := 0.18
var macro_variation_scale := 0.04
var detail_noise_strength := 0.10
var detail_noise_scale := 0.45
var rock_detail_strength := 0.25
var snow_detail_strength := 0.08
var material_brightness := 1.2
var material_contrast := 1.05

var _legacy_terrain_material: StandardMaterial3D
var _procedural_terrain_material: ShaderMaterial
var _simple_mask_terrain_material: ShaderMaterial
var _terrain_shader: Shader
var _terrain_macro_noise_texture: Texture2D
var _terrain_detail_noise_texture: Texture2D
var _terrain_far_color_cache_texture: Texture2D
var _terrain_far_color_cache_available := false
var _far_color_cache_signature := ""
var _fallback_albedo_texture: Texture2D
var _fallback_normal_texture: Texture2D
var _fallback_scalar_texture: Texture2D
var _material_texture_cache: Dictionary = {}
var _saving_visual_resources := false
var _terrain_shader_code_applied := false


func configure(settings: Dictionary) -> void:
	generated_resource_directory = str(settings.get("generated_resource_directory", generated_resource_directory))
	material_seed = int(settings.get("seed", material_seed))
	material_mode = int(settings.get("material_mode", material_mode))
	height_scale = float(settings.get("height_scale", height_scale))
	snow_enabled = bool(settings.get("snow_enabled", snow_enabled))
	snow_height = float(settings.get("snow_height", snow_height))
	rock_slope_threshold = float(settings.get("rock_slope_threshold", rock_slope_threshold))
	lowland_color = settings.get("lowland_color", lowland_color) as Color
	grass_color = settings.get("grass_color", grass_color) as Color
	rock_color = settings.get("rock_color", rock_color) as Color
	snow_color = settings.get("snow_color", snow_color) as Color
	lowland_material_folder = str(settings.get("lowland_material_folder", lowland_material_folder))
	ground_material_folder = str(settings.get("ground_material_folder", ground_material_folder))
	upper_material_folder = str(settings.get("upper_material_folder", upper_material_folder))
	rocky_material_folder = str(settings.get("rocky_material_folder", rocky_material_folder))
	cliff_material_folder = str(settings.get("cliff_material_folder", cliff_material_folder))
	snow_material_folder = str(settings.get("snow_material_folder", snow_material_folder))
	lowland_layer_enabled = bool(settings.get("lowland_layer_enabled", lowland_layer_enabled))
	ground_layer_enabled = bool(settings.get("ground_layer_enabled", ground_layer_enabled))
	upper_layer_enabled = bool(settings.get("upper_layer_enabled", upper_layer_enabled))
	rocky_layer_enabled = bool(settings.get("rocky_layer_enabled", rocky_layer_enabled))
	cliff_layer_enabled = bool(settings.get("cliff_layer_enabled", cliff_layer_enabled))
	snow_layer_enabled = bool(settings.get("snow_layer_enabled", snow_layer_enabled))
	texture_tile_scale = float(settings.get("texture_tile_scale", texture_tile_scale))
	macro_texture_tiling_enabled = bool(settings.get("macro_texture_tiling_enabled", macro_texture_tiling_enabled))
	var loaded_texture_focus = settings.get("texture_focus_position", texture_focus_position)
	if loaded_texture_focus is Vector3:
		texture_focus_position = loaded_texture_focus as Vector3
	elif loaded_texture_focus is Vector2:
		var focus_2d := loaded_texture_focus as Vector2
		texture_focus_position = Vector3(focus_2d.x, 0.0, focus_2d.y)
	close_texture_tile_scale = float(settings.get("close_texture_tile_scale", close_texture_tile_scale))
	medium_texture_tile_scale = float(settings.get("medium_texture_tile_scale", medium_texture_tile_scale))
	far_texture_tile_scale = float(settings.get("far_texture_tile_scale", far_texture_tile_scale))
	close_texture_radius = float(settings.get("close_texture_radius", close_texture_radius))
	medium_texture_radius = float(settings.get("medium_texture_radius", medium_texture_radius))
	far_texture_radius = float(settings.get("far_texture_radius", far_texture_radius))
	layer_blend_softness = float(settings.get("layer_blend_softness", layer_blend_softness))
	texture_normal_strength = float(settings.get("texture_normal_strength", texture_normal_strength))
	roughness_multiplier = float(settings.get("roughness_multiplier", roughness_multiplier))
	height_blend_strength = float(settings.get("height_blend_strength", height_blend_strength))
	texture_bombing_enabled = bool(settings.get("texture_bombing_enabled", texture_bombing_enabled))
	texture_bombing_strength = float(settings.get("texture_bombing_strength", texture_bombing_strength))
	texture_bombing_cell_scale = float(settings.get("texture_bombing_cell_scale", texture_bombing_cell_scale))
	texture_bombing_samples = int(settings.get("texture_bombing_samples", texture_bombing_samples))
	material_performance_preset = int(settings.get("material_performance_preset", material_performance_preset))
	far_material_cache_enabled = bool(settings.get("far_material_cache_enabled", far_material_cache_enabled))
	far_material_cache_resolution = int(settings.get("far_material_cache_resolution", far_material_cache_resolution))
	terrain_world_size = float(settings.get("terrain_world_size", terrain_world_size))
	procedural_material_enabled = bool(settings.get("procedural_material_enabled", procedural_material_enabled))
	macro_variation_strength = float(settings.get("macro_variation_strength", macro_variation_strength))
	macro_variation_scale = float(settings.get("macro_variation_scale", macro_variation_scale))
	detail_noise_strength = float(settings.get("detail_noise_strength", detail_noise_strength))
	detail_noise_scale = float(settings.get("detail_noise_scale", detail_noise_scale))
	rock_detail_strength = float(settings.get("rock_detail_strength", rock_detail_strength))
	snow_detail_strength = float(settings.get("snow_detail_strength", snow_detail_strength))
	material_brightness = float(settings.get("material_brightness", material_brightness))
	material_contrast = float(settings.get("material_contrast", material_contrast))
	var next_far_cache_signature := _get_far_color_cache_signature()
	if not _far_color_cache_signature.is_empty() and next_far_cache_signature != _far_color_cache_signature:
		_invalidate_far_color_cache()
	_far_color_cache_signature = next_far_cache_signature
	update_materials()


func get_material_for_encoding(encoding: String) -> Material:
	if encoding == TERRAIN_ENCODING_V5_MASKS:
		if procedural_material_enabled:
			return _get_or_create_procedural_terrain_material()
		return _get_or_create_simple_mask_terrain_material()
	return _get_or_create_legacy_terrain_material()


func update_materials() -> void:
	_update_terrain_shader_parameters()


func set_texture_focus_position(focus_position: Vector3) -> void:
	texture_focus_position = focus_position
	_update_texture_focus_parameters()


func reset_noise_textures() -> void:
	_terrain_macro_noise_texture = null
	_terrain_detail_noise_texture = null
	_invalidate_far_color_cache()
	update_materials()


func _invalidate_far_color_cache() -> void:
	_terrain_far_color_cache_texture = _create_solid_texture(grass_color)
	_terrain_far_color_cache_available = false


func _get_far_color_cache_signature() -> String:
	return str([
		material_seed,
		material_mode,
		height_scale,
		snow_enabled,
		snow_height,
		rock_slope_threshold,
		lowland_material_folder,
		ground_material_folder,
		upper_material_folder,
		rocky_material_folder,
		cliff_material_folder,
		snow_material_folder,
		lowland_layer_enabled,
		ground_layer_enabled,
		upper_layer_enabled,
		rocky_layer_enabled,
		cliff_layer_enabled,
		snow_layer_enabled,
		far_texture_tile_scale,
		layer_blend_softness,
		height_blend_strength,
		far_material_cache_resolution,
		terrain_world_size,
	])


func save_visual_resources(resource_directory: String, heightfield: RefCounted = null) -> int:
	if _saving_visual_resources:
		return OK

	_saving_visual_resources = true
	if far_material_cache_enabled:
		_terrain_far_color_cache_texture = _create_far_color_cache_texture(heightfield)
		_terrain_far_color_cache_available = true
		_far_color_cache_signature = _get_far_color_cache_signature()
	update_materials()

	var macro_error := ResourceSaver.save(_get_or_create_terrain_macro_noise_texture(), "%s/%s" % [resource_directory, TERRAIN_MACRO_NOISE_PATH])
	if macro_error != OK:
		_saving_visual_resources = false
		return macro_error
	var detail_error := ResourceSaver.save(_get_or_create_terrain_detail_noise_texture(), "%s/%s" % [resource_directory, TERRAIN_DETAIL_NOISE_PATH])
	if detail_error != OK:
		_saving_visual_resources = false
		return detail_error
	var far_cache_error := ResourceSaver.save(_get_or_create_terrain_far_color_cache_texture(), "%s/%s" % [resource_directory, TERRAIN_FAR_COLOR_CACHE_PATH])
	if far_cache_error != OK:
		_saving_visual_resources = false
		return far_cache_error
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
		_terrain_shader = Shader.new()
		_terrain_shader_code_applied = false
	if not _terrain_shader_code_applied or _terrain_shader.code != TERRAIN_SHADER_CODE:
		_terrain_shader.code = TERRAIN_SHADER_CODE
		_terrain_shader_code_applied = true
	return _terrain_shader


func _update_terrain_shader_parameters() -> void:
	for material in [_procedural_terrain_material, _simple_mask_terrain_material]:
		if material == null:
			continue
		material.shader = _get_or_create_terrain_shader()
		var material_uses_procedural: bool = material == _procedural_terrain_material and procedural_material_enabled
		var material_uses_color_detail := material_uses_procedural and material_mode != 1
		material.set_shader_parameter("use_procedural_detail", material_uses_color_detail)
		material.set_shader_parameter("material_mode", material_mode if material_uses_procedural else 0)
		material.set_shader_parameter("snow_enabled", snow_enabled)
		if material_uses_color_detail:
			material.set_shader_parameter("macro_noise_texture", _get_or_create_terrain_macro_noise_texture())
			material.set_shader_parameter("detail_noise_texture", _get_or_create_terrain_detail_noise_texture())
		_set_layer_shader_parameters(material, "lowland", _get_material_folder_for_layer_slot(0) if material_uses_procedural else lowland_material_folder)
		_set_layer_shader_parameters(material, "ground", _get_material_folder_for_layer_slot(1) if material_uses_procedural else ground_material_folder)
		_set_layer_shader_parameters(material, "upper", _get_material_folder_for_layer_slot(2) if material_uses_procedural else upper_material_folder)
		_set_layer_shader_parameters(material, "rocky", _get_material_folder_for_layer_slot(3) if material_uses_procedural else rocky_material_folder)
		_set_layer_shader_parameters(material, "cliff", _get_material_folder_for_layer_slot(4) if material_uses_procedural else cliff_material_folder)
		_set_layer_shader_parameters(material, "snow", _get_material_folder_for_layer_slot(5) if material_uses_procedural else snow_material_folder)
		_set_layer_shader_parameters(material, "paint_lowland", lowland_material_folder)
		_set_layer_shader_parameters(material, "paint_ground", ground_material_folder)
		_set_layer_shader_parameters(material, "paint_upper", upper_material_folder)
		_set_layer_shader_parameters(material, "paint_rocky", rocky_material_folder)
		_set_layer_shader_parameters(material, "paint_cliff", cliff_material_folder)
		_set_layer_shader_parameters(material, "paint_snow", snow_material_folder)
		material.set_shader_parameter("lowland_layer_enabled", lowland_layer_enabled)
		material.set_shader_parameter("ground_layer_enabled", ground_layer_enabled)
		material.set_shader_parameter("upper_layer_enabled", upper_layer_enabled)
		material.set_shader_parameter("rocky_layer_enabled", rocky_layer_enabled)
		material.set_shader_parameter("cliff_layer_enabled", cliff_layer_enabled)
		material.set_shader_parameter("snow_layer_enabled", snow_layer_enabled)
		material.set_shader_parameter("lowland_color", lowland_color)
		material.set_shader_parameter("grass_color", grass_color)
		material.set_shader_parameter("rock_color", rock_color)
		material.set_shader_parameter("snow_color", snow_color)
		material.set_shader_parameter("height_scale", height_scale)
		material.set_shader_parameter("snow_height", snow_height)
		material.set_shader_parameter("rock_slope_threshold", rock_slope_threshold)
		material.set_shader_parameter("texture_tile_scale", texture_tile_scale)
		material.set_shader_parameter("macro_texture_tiling_enabled", macro_texture_tiling_enabled)
		material.set_shader_parameter("texture_focus_position", texture_focus_position)
		material.set_shader_parameter("close_texture_tile_scale", close_texture_tile_scale)
		material.set_shader_parameter("medium_texture_tile_scale", medium_texture_tile_scale)
		material.set_shader_parameter("far_texture_tile_scale", far_texture_tile_scale)
		material.set_shader_parameter("close_texture_radius", close_texture_radius)
		material.set_shader_parameter("medium_texture_radius", medium_texture_radius)
		material.set_shader_parameter("far_texture_radius", far_texture_radius)
		material.set_shader_parameter("layer_blend_softness", layer_blend_softness)
		material.set_shader_parameter("texture_normal_strength", texture_normal_strength)
		material.set_shader_parameter("roughness_multiplier", roughness_multiplier)
		material.set_shader_parameter("height_blend_strength", height_blend_strength)
		material.set_shader_parameter("texture_bombing_enabled", texture_bombing_enabled)
		material.set_shader_parameter("texture_bombing_strength", texture_bombing_strength)
		material.set_shader_parameter("texture_bombing_cell_scale", texture_bombing_cell_scale)
		material.set_shader_parameter("texture_bombing_samples", texture_bombing_samples)
		material.set_shader_parameter("material_performance_preset", material_performance_preset)
		material.set_shader_parameter("far_material_cache_enabled", far_material_cache_enabled and _terrain_far_color_cache_available)
		material.set_shader_parameter("far_material_cache_texture", _get_or_create_terrain_far_color_cache_texture())
		material.set_shader_parameter("terrain_world_size", terrain_world_size)
		material.set_shader_parameter("macro_variation_strength", macro_variation_strength)
		material.set_shader_parameter("macro_variation_scale", macro_variation_scale)
		material.set_shader_parameter("detail_noise_strength", detail_noise_strength)
		material.set_shader_parameter("detail_noise_scale", detail_noise_scale)
		material.set_shader_parameter("rock_detail_strength", rock_detail_strength)
		material.set_shader_parameter("snow_detail_strength", snow_detail_strength)
		material.set_shader_parameter("material_brightness", material_brightness)
		material.set_shader_parameter("material_contrast", material_contrast)


func _update_texture_focus_parameters() -> void:
	for material in [_procedural_terrain_material, _simple_mask_terrain_material]:
		if material != null:
			material.set_shader_parameter("texture_focus_position", texture_focus_position)


func _set_layer_shader_parameters(material: ShaderMaterial, prefix: String, folder: String) -> void:
	material.set_shader_parameter("%s_albedo_texture" % prefix, _load_material_texture(folder, "_diff_", _get_fallback_albedo_texture()))
	material.set_shader_parameter("%s_normal_texture" % prefix, _load_material_texture(folder, "_nor_gl_", _get_fallback_normal_texture()))
	material.set_shader_parameter("%s_roughness_texture" % prefix, _load_material_texture(folder, "_rough_", _get_fallback_scalar_texture()))
	material.set_shader_parameter("%s_height_texture" % prefix, _load_material_texture(folder, "_disp_", _get_fallback_scalar_texture()))


func _get_material_folder_for_layer_slot(slot: int) -> String:
	var enabled_folders := _get_enabled_material_folders()
	return enabled_folders[mini(slot, enabled_folders.size() - 1)]


func _get_enabled_material_folders() -> Array[String]:
	var enabled_folders: Array[String] = []
	if lowland_layer_enabled:
		enabled_folders.append(lowland_material_folder)
	if ground_layer_enabled:
		enabled_folders.append(ground_material_folder)
	if upper_layer_enabled:
		enabled_folders.append(upper_material_folder)
	if rocky_layer_enabled:
		enabled_folders.append(rocky_material_folder)
	if cliff_layer_enabled:
		enabled_folders.append(cliff_material_folder)
	if snow_layer_enabled:
		enabled_folders.append(snow_material_folder)
	if enabled_folders.is_empty():
		enabled_folders.append(ground_material_folder)
	return enabled_folders


func _load_material_texture(folder: String, token: String, fallback: Texture2D) -> Texture2D:
	var normalized_folder := _normalize_resource_folder(folder)
	var directory := DirAccess.open(normalized_folder)
	if directory == null:
		return fallback

	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		var lower_file_name := file_name.to_lower()
		if not directory.current_is_dir() and not lower_file_name.ends_with(".import") and lower_file_name.contains(token):
			var texture_path := "%s/%s" % [normalized_folder, file_name]
			var loaded_texture := _load_texture_from_path(texture_path)
			directory.list_dir_end()
			return loaded_texture if loaded_texture != null else fallback
		file_name = directory.get_next()
	directory.list_dir_end()
	return fallback


func _load_texture_from_path(texture_path: String) -> Texture2D:
	if _material_texture_cache.has(texture_path):
		return _material_texture_cache[texture_path] as Texture2D

	var loaded_texture := ResourceLoader.load(texture_path, "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
	if loaded_texture != null:
		_material_texture_cache[texture_path] = loaded_texture
	return loaded_texture


func _normalize_resource_folder(folder: String) -> String:
	var normalized_folder := folder.strip_edges()
	if normalized_folder.is_empty():
		return "res://material"
	if normalized_folder.begins_with("res://") or normalized_folder.begins_with("user://"):
		return normalized_folder.trim_suffix("/")
	return "res://%s" % normalized_folder.trim_prefix("/").trim_suffix("/")


func _get_fallback_albedo_texture() -> Texture2D:
	if _fallback_albedo_texture == null:
		_fallback_albedo_texture = _create_solid_texture(Color(0.5, 0.5, 0.5, 1.0))
	return _fallback_albedo_texture


func _get_fallback_normal_texture() -> Texture2D:
	if _fallback_normal_texture == null:
		_fallback_normal_texture = _create_solid_texture(Color(0.5, 0.5, 1.0, 1.0))
	return _fallback_normal_texture


func _get_fallback_scalar_texture() -> Texture2D:
	if _fallback_scalar_texture == null:
		_fallback_scalar_texture = _create_solid_texture(Color(0.75, 0.75, 0.75, 1.0))
	return _fallback_scalar_texture


func _create_solid_texture(color: Color) -> ImageTexture:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _get_or_create_terrain_macro_noise_texture() -> Texture2D:
	if _terrain_macro_noise_texture == null:
		_terrain_macro_noise_texture = _load_external_texture(TERRAIN_MACRO_NOISE_PATH)
		if _terrain_macro_noise_texture == null:
			_terrain_macro_noise_texture = _create_noise_texture(material_seed + 2197, 0.045, 256)
	return _terrain_macro_noise_texture


func _get_or_create_terrain_detail_noise_texture() -> Texture2D:
	if _terrain_detail_noise_texture == null:
		_terrain_detail_noise_texture = _load_external_texture(TERRAIN_DETAIL_NOISE_PATH)
		if _terrain_detail_noise_texture == null:
			_terrain_detail_noise_texture = _create_noise_texture(material_seed + 7919, 0.18, 256)
	return _terrain_detail_noise_texture


func _get_or_create_terrain_far_color_cache_texture() -> Texture2D:
	if _terrain_far_color_cache_texture == null:
		_terrain_far_color_cache_texture = _load_external_texture(TERRAIN_FAR_COLOR_CACHE_PATH)
		_terrain_far_color_cache_available = _terrain_far_color_cache_texture != null
		if _terrain_far_color_cache_texture == null:
			_terrain_far_color_cache_texture = _create_solid_texture(grass_color)
			_terrain_far_color_cache_available = false
	return _terrain_far_color_cache_texture


func _create_far_color_cache_texture(heightfield: RefCounted) -> ImageTexture:
	var texture_size := clampi(far_material_cache_resolution, 128, 2048)
	var image := Image.create(texture_size, texture_size, false, Image.FORMAT_RGB8)
	var lowland_image := _load_material_image(_get_material_folder_for_layer_slot(0), "_diff_")
	var ground_image := _load_material_image(_get_material_folder_for_layer_slot(1), "_diff_")
	var upper_image := _load_material_image(_get_material_folder_for_layer_slot(2), "_diff_")
	var rocky_image := _load_material_image(_get_material_folder_for_layer_slot(3), "_diff_")
	var cliff_image := _load_material_image(_get_material_folder_for_layer_slot(4), "_diff_")
	var snow_image := _load_material_image(_get_material_folder_for_layer_slot(5), "_diff_")
	var half_size := terrain_world_size * 0.5

	for y in texture_size:
		var v := float(y) / float(maxi(1, texture_size - 1))
		var world_z := v * terrain_world_size - half_size
		for x in texture_size:
			var u := float(x) / float(maxi(1, texture_size - 1))
			var world_x := u * terrain_world_size - half_size
			var height := _sample_heightfield_world(heightfield, world_x, world_z)
			var normal := _sample_heightfield_normal(heightfield, world_x, world_z)
			var color := _far_cache_color_for_sample(
				height,
				normal,
				Vector2(world_x, world_z),
				lowland_image,
				ground_image,
				upper_image,
				rocky_image,
				cliff_image,
				snow_image
			)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))

	return ImageTexture.create_from_image(image)


func _sample_heightfield_world(heightfield: RefCounted, world_x: float, world_z: float) -> float:
	if heightfield != null and heightfield.is_valid():
		return heightfield.sample_world(world_x, world_z)
	return 0.0


func _sample_heightfield_normal(heightfield: RefCounted, world_x: float, world_z: float) -> Vector3:
	var sample_step := maxf(terrain_world_size / float(maxi(1, far_material_cache_resolution)), 0.001)
	var left_height := _sample_heightfield_world(heightfield, world_x - sample_step, world_z)
	var right_height := _sample_heightfield_world(heightfield, world_x + sample_step, world_z)
	var back_height := _sample_heightfield_world(heightfield, world_x, world_z - sample_step)
	var forward_height := _sample_heightfield_world(heightfield, world_x, world_z + sample_step)
	return Vector3(left_height - right_height, sample_step * 2.0, back_height - forward_height).normalized()


func _far_cache_color_for_sample(
	height: float,
	normal: Vector3,
	world_xz: Vector2,
	lowland_image: Image,
	ground_image: Image,
	upper_image: Image,
	rocky_image: Image,
	cliff_image: Image,
	snow_image: Image
) -> Color:
	var height_range := maxf(height_scale, 0.001)
	var normalized_height := clampf((height / height_range + 1.0) * 0.5, 0.0, 1.0)
	var slope := clampf(1.0 - normal.y, 0.0, 1.0)
	var rock_amount := _smoothstep(rock_slope_threshold, minf(1.0, rock_slope_threshold + 0.25), slope)
	var snow_blend_width := maxf(height_scale * 0.12, 0.35)
	var snow_amount := _smoothstep(snow_height - snow_blend_width, snow_height + snow_blend_width, height) if snow_enabled else 0.0
	var blend_softness := maxf(layer_blend_softness, 0.001)

	var lowland_weight := 1.0 - _smoothstep(0.12, 0.28 + blend_softness, normalized_height)
	var ground_weight := _smoothstep(0.12, 0.30 + blend_softness, normalized_height) * (1.0 - _smoothstep(0.58, 0.80 + blend_softness, normalized_height))
	var upper_weight := _smoothstep(0.48, 0.78 + blend_softness, normalized_height) * (1.0 - rock_amount)
	var rocky_weight := rock_amount * (1.0 - _smoothstep(0.72, 0.92, slope))
	var cliff_weight := _smoothstep(maxf(0.0, rock_slope_threshold + 0.18), 0.88, slope)
	var snow_weight := snow_amount

	var non_snow_weight := 1.0 - snow_weight
	lowland_weight *= non_snow_weight
	ground_weight *= non_snow_weight
	upper_weight *= non_snow_weight
	rocky_weight *= non_snow_weight
	cliff_weight *= non_snow_weight

	var total_weight := maxf(lowland_weight + ground_weight + upper_weight + rocky_weight + cliff_weight + snow_weight, 0.0001)

	var far_uv := world_xz * maxf(far_texture_tile_scale, 0.001)
	var lowland_sample := _sample_image_repeat(lowland_image, far_uv * 0.83, lowland_color)
	var ground_sample := _sample_image_repeat(ground_image, far_uv, grass_color)
	var upper_sample := _sample_image_repeat(upper_image, far_uv * 0.92, grass_color)
	var rocky_sample := _sample_image_repeat(rocky_image, far_uv * 1.15, rock_color)
	var cliff_sample := _sample_image_repeat(cliff_image, far_uv * 1.10, rock_color)
	var snow_sample := _sample_image_repeat(snow_image, far_uv * 0.72, snow_color)

	var color := (
		lowland_sample * (lowland_weight / total_weight)
		+ ground_sample * (ground_weight / total_weight)
		+ upper_sample * (upper_weight / total_weight)
		+ rocky_sample * (rocky_weight / total_weight)
		+ cliff_sample * (cliff_weight / total_weight)
		+ snow_sample * (snow_weight / total_weight)
	)
	return Color(
		clampf(color.r * material_brightness, 0.0, 1.0),
		clampf(color.g * material_brightness, 0.0, 1.0),
		clampf(color.b * material_brightness, 0.0, 1.0),
		1.0
	)


func _load_material_image(folder: String, token: String) -> Image:
	var normalized_folder := _normalize_resource_folder(folder)
	var directory := DirAccess.open(normalized_folder)
	if directory == null:
		return null

	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		var lower_file_name := file_name.to_lower()
		if not directory.current_is_dir() and not lower_file_name.ends_with(".import") and lower_file_name.contains(token):
			var texture := ResourceLoader.load("%s/%s" % [normalized_folder, file_name], "Texture2D", ResourceLoader.CACHE_MODE_REPLACE) as Texture2D
			var image := _prepare_sample_image(texture.get_image() if texture != null else null)
			directory.list_dir_end()
			return image
		file_name = directory.get_next()
	directory.list_dir_end()
	return null


func _prepare_sample_image(source_image: Image) -> Image:
	if source_image == null or source_image.is_empty():
		return null

	var image := source_image.duplicate()
	if image.is_compressed():
		var decompress_error: int = image.decompress()
		if decompress_error != OK:
			return null
	if image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8 and image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGBA8)
	return image


func _sample_image_repeat(image: Image, uv: Vector2, fallback: Color) -> Color:
	if image == null or image.is_empty() or image.is_compressed():
		return fallback
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return fallback
	var wrapped_u := uv.x - floorf(uv.x)
	var wrapped_v := uv.y - floorf(uv.y)
	var u := posmod(floori(wrapped_u * float(width)), width)
	var v := posmod(floori(wrapped_v * float(height)), height)
	return image.get_pixel(u, v)


func _smoothstep(edge0: float, edge1: float, value: float) -> float:
	if absf(edge1 - edge0) < 0.0001:
		return 0.0
	var x := clampf((value - edge0) / (edge1 - edge0), 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


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
	_terrain_far_color_cache_texture = _load_external_texture(TERRAIN_FAR_COLOR_CACHE_PATH)
	_terrain_far_color_cache_available = _terrain_far_color_cache_texture != null
	_terrain_shader = _load_external_shader(TERRAIN_PROCEDURAL_SHADER_PATH)
	_procedural_terrain_material = _load_external_shader_material(TERRAIN_PROCEDURAL_MATERIAL_PATH)
	_legacy_terrain_material = _load_external_legacy_terrain_material()
	_terrain_shader_code_applied = false
	update_materials()
