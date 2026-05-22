@tool
extends RefCounted
class_name TerrainHeightfield

const SOURCE_NOISE := 0
const SOURCE_HEIGHTMAP := 1

var width := 0
var height := 0
var terrain_size := 64.0
var height_scale := 2.0
var noise_sample_scale := 1.0
var step := 1.0
var half_size := 32.0
var heights := PackedFloat32Array()
var source_description := ""


func is_valid() -> bool:
	return width > 1 and height > 1 and heights.size() == width * height


func create_from_noise(total_resolution: int, world_size: float, vertical_scale: float, noise: FastNoiseLite, sample_scale: float = 1.0) -> void:
	width = total_resolution + 1
	height = total_resolution + 1
	terrain_size = world_size
	height_scale = vertical_scale
	noise_sample_scale = maxf(0.001, sample_scale)
	step = terrain_size / float(maxi(1, total_resolution))
	half_size = terrain_size * 0.5
	source_description = "Noise"
	heights.resize(width * height)

	for z in height:
		var world_z := float(z) * step - half_size
		for x in width:
			var world_x := float(x) * step - half_size
			heights[_index(x, z)] = noise.get_noise_2d(world_x / noise_sample_scale, world_z / noise_sample_scale) * height_scale if noise != null else 0.0


func create_from_image(
	total_resolution: int,
	world_size: float,
	vertical_scale: float,
	image: Image,
	flip_x: bool,
	flip_z: bool,
	invert: bool
) -> void:
	width = total_resolution + 1
	height = total_resolution + 1
	terrain_size = world_size
	height_scale = vertical_scale
	noise_sample_scale = 1.0
	step = terrain_size / float(maxi(1, total_resolution))
	half_size = terrain_size * 0.5
	source_description = "Heightmap"
	heights.resize(width * height)

	if image == null or image.is_empty():
		heights.fill(0.0)
		return

	var source_width := image.get_width()
	var source_height := image.get_height()
	for z in height:
		var sample_v := float(z) / float(maxi(1, height - 1))
		if flip_z:
			sample_v = 1.0 - sample_v
		for x in width:
			var sample_u := float(x) / float(maxi(1, width - 1))
			if flip_x:
				sample_u = 1.0 - sample_u
			var value := _sample_image_luma(image, sample_u * float(source_width - 1), sample_v * float(source_height - 1))
			if invert:
				value = 1.0 - value
			heights[_index(x, z)] = (value * 2.0 - 1.0) * height_scale


func create_from_r16(
	total_resolution: int,
	world_size: float,
	vertical_scale: float,
	raw_bytes: PackedByteArray,
	source_width: int,
	source_height: int,
	min_height: float,
	max_height: float,
	flip_x: bool,
	flip_z: bool,
	invert: bool
) -> void:
	width = total_resolution + 1
	height = total_resolution + 1
	terrain_size = world_size
	height_scale = vertical_scale
	noise_sample_scale = 1.0
	step = terrain_size / float(maxi(1, total_resolution))
	half_size = terrain_size * 0.5
	source_description = "R16 Heightmap"
	heights.resize(width * height)

	if raw_bytes.is_empty() or source_width <= 1 or source_height <= 1:
		heights.fill(0.0)
		return

	for z in height:
		var sample_v := float(z) / float(maxi(1, height - 1))
		if flip_z:
			sample_v = 1.0 - sample_v
		for x in width:
			var sample_u := float(x) / float(maxi(1, width - 1))
			if flip_x:
				sample_u = 1.0 - sample_u
			var value := _sample_r16(raw_bytes, source_width, source_height, sample_u * float(source_width - 1), sample_v * float(source_height - 1))
			if invert:
				value = 1.0 - value
			heights[_index(x, z)] = lerpf(min_height, max_height, value)


func duplicate_heightfield() -> RefCounted:
	var copy: RefCounted = get_script().new()
	copy.width = width
	copy.height = height
	copy.terrain_size = terrain_size
	copy.height_scale = height_scale
	copy.noise_sample_scale = noise_sample_scale
	copy.step = step
	copy.half_size = half_size
	copy.source_description = source_description
	copy.heights = heights.duplicate()
	return copy


func copy_from(other: RefCounted) -> void:
	if other == null:
		clear()
		return
	width = other.width
	height = other.height
	terrain_size = other.terrain_size
	height_scale = other.height_scale
	noise_sample_scale = other.noise_sample_scale
	step = other.step
	half_size = other.half_size
	source_description = other.source_description
	heights = other.heights.duplicate()


func clear() -> void:
	width = 0
	height = 0
	heights.clear()
	source_description = ""


func sample_grid(x: int, z: int) -> float:
	if not is_valid():
		return 0.0
	return heights[_index(clampi(x, 0, width - 1), clampi(z, 0, height - 1))]


func sample_grid_bilinear(grid_x: float, grid_z: float) -> float:
	if not is_valid():
		return 0.0

	var x0 := clampi(floori(grid_x), 0, width - 1)
	var z0 := clampi(floori(grid_z), 0, height - 1)
	var x1 := clampi(x0 + 1, 0, width - 1)
	var z1 := clampi(z0 + 1, 0, height - 1)
	var tx := clampf(grid_x - float(x0), 0.0, 1.0)
	var tz := clampf(grid_z - float(z0), 0.0, 1.0)
	var top := lerpf(sample_grid(x0, z0), sample_grid(x1, z0), tx)
	var bottom := lerpf(sample_grid(x0, z1), sample_grid(x1, z1), tx)
	return lerpf(top, bottom, tz)


func sample_world(world_x: float, world_z: float) -> float:
	if step <= 0.0:
		return 0.0
	return sample_grid_bilinear((world_x + half_size) / step, (world_z + half_size) / step)


func set_grid(x: int, z: int, value: float) -> void:
	if not is_valid():
		return
	heights[_index(clampi(x, 0, width - 1), clampi(z, 0, height - 1))] = value


func get_min_height() -> float:
	if heights.is_empty():
		return 0.0
	var result := heights[0]
	for value in heights:
		result = minf(result, value)
	return result


func get_max_height() -> float:
	if heights.is_empty():
		return 0.0
	var result := heights[0]
	for value in heights:
		result = maxf(result, value)
	return result


func export_png(path: String) -> int:
	if not is_valid():
		return ERR_UNCONFIGURED

	var min_height := get_min_height()
	var max_height := get_max_height()
	var height_range := maxf(max_height - min_height, 0.0001)
	var image := Image.create(width, height, false, Image.FORMAT_RH)

	for z in height:
		for x in width:
			var normalized := clampf((sample_grid(x, z) - min_height) / height_range, 0.0, 1.0)
			image.set_pixel(x, z, Color(normalized, normalized, normalized, 1.0))

	return image.save_png(path)


func export_exr(path: String, min_height: float = NAN, max_height: float = NAN) -> int:
	if not is_valid():
		return ERR_UNCONFIGURED

	var export_min := get_min_height() if is_nan(min_height) else min_height
	var export_max := get_max_height() if is_nan(max_height) else max_height
	var height_range := maxf(export_max - export_min, 0.0001)
	var image := Image.create(width, height, false, Image.FORMAT_RF)

	for z in height:
		for x in width:
			var normalized := clampf((sample_grid(x, z) - export_min) / height_range, 0.0, 1.0)
			image.set_pixel(x, z, Color(normalized, 0.0, 0.0, 1.0))

	return image.save_exr(path, true)


func export_r16(path: String, min_height: float = NAN, max_height: float = NAN) -> int:
	if not is_valid():
		return ERR_UNCONFIGURED

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	var export_min := get_min_height() if is_nan(min_height) else min_height
	var export_max := get_max_height() if is_nan(max_height) else max_height
	var height_range := maxf(export_max - export_min, 0.0001)
	for z in height:
		for x in width:
			var normalized := clampf((sample_grid(x, z) - export_min) / height_range, 0.0, 1.0)
			file.store_16(clampi(roundi(normalized * 65535.0), 0, 65535))
	file.close()
	return OK


func _index(x: int, z: int) -> int:
	return z * width + x


func _sample_image_luma(image: Image, x: float, y: float) -> float:
	var source_width := image.get_width()
	var source_height := image.get_height()
	var x0 := clampi(floori(x), 0, source_width - 1)
	var y0 := clampi(floori(y), 0, source_height - 1)
	var x1 := clampi(x0 + 1, 0, source_width - 1)
	var y1 := clampi(y0 + 1, 0, source_height - 1)
	var tx := clampf(x - float(x0), 0.0, 1.0)
	var ty := clampf(y - float(y0), 0.0, 1.0)
	var top := lerpf(image.get_pixel(x0, y0).r, image.get_pixel(x1, y0).r, tx)
	var bottom := lerpf(image.get_pixel(x0, y1).r, image.get_pixel(x1, y1).r, tx)
	return lerpf(top, bottom, ty)


func _sample_r16(raw_bytes: PackedByteArray, source_width: int, source_height: int, x: float, y: float) -> float:
	var x0 := clampi(floori(x), 0, source_width - 1)
	var y0 := clampi(floori(y), 0, source_height - 1)
	var x1 := clampi(x0 + 1, 0, source_width - 1)
	var y1 := clampi(y0 + 1, 0, source_height - 1)
	var tx := clampf(x - float(x0), 0.0, 1.0)
	var ty := clampf(y - float(y0), 0.0, 1.0)
	var top := lerpf(_read_r16_normalized(raw_bytes, source_width, x0, y0), _read_r16_normalized(raw_bytes, source_width, x1, y0), tx)
	var bottom := lerpf(_read_r16_normalized(raw_bytes, source_width, x0, y1), _read_r16_normalized(raw_bytes, source_width, x1, y1), tx)
	return lerpf(top, bottom, ty)


func _read_r16_normalized(raw_bytes: PackedByteArray, source_width: int, x: int, y: int) -> float:
	var offset := (y * source_width + x) * 2
	if offset + 1 >= raw_bytes.size():
		return 0.0
	var value := int(raw_bytes[offset]) | (int(raw_bytes[offset + 1]) << 8)
	return float(value) / 65535.0
