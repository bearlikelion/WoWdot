class_name WorldLight
extends RefCounted

# LightIntBand channels of one LightParams row.
enum ColorBand {
	DIFFUSE = 0,
	AMBIENT = 1,
	SKY_TOP = 2,
	SKY_MIDDLE = 3,
	SKY_LOWER = 4,
	SKY_ABOVE_HORIZON = 5,
	SKY_HORIZON = 6,
	FOG = 7,
	SUN = 9,
	SUN_HALO = 10,
	CLOUD_SHADE = 11,
}
# LightFloatBand channels.
enum FloatBand { FOG_END = 0, FOG_START_SCALE = 1, CLOUD_DENSITY = 3 }
# Light.dbc param sets, as offsets from LightColumn.PARAMS.
enum Condition { CLEAR = 0, UNDERWATER = 1, STORM = 2, STORM_UNDERWATER = 3, DEATH = 4 }
enum ParamsColumn { HIGHLIGHT_SKY = 1, SKYBOX = 2 }
enum LightColumn {
	MAP = 1,
	X = 2,
	HEIGHT = 3,
	Z = 4,
	INNER_RADIUS = 5,
	OUTER_RADIUS = 6,
	PARAMS = 7,
}

const COLOR_BANDS_PER_PARAMS: int = 18
const FLOAT_BANDS_PER_PARAMS: int = 6
const KEY_COUNT_COLUMN: int = 1
const FIRST_TIME_COLUMN: int = 2
const FIRST_VALUE_COLUMN: int = 18
# Band times count half minutes.
const HALF_MINUTES_PER_DAY: float = 2880.0
# Light.dbc positions, radii and fog distances are yards times 36, from the map's corner.
const SCALE: float = 36.0
const ZERO_POINT: float = 17066.666
const NO_SHIFT: int = -1
const SKYBOX_PATH_COLUMN: int = 1

var _lights: WowDBC
var _color_bands: WowDBC
var _float_bands: WowDBC
var _params: WowDBC
var _skyboxes: WowDBC
var _map_id: int = -1
var _volumes: Array[Volume] = []
var _default_row: int = -1


func _init(archive: WowArchive) -> void:
	_lights = WowDBC.open(archive, "Light")
	_color_bands = WowDBC.open(archive, "LightIntBand")
	_float_bands = WowDBC.open(archive, "LightFloatBand")
	_params = WowDBC.open(archive, "LightParams")
	_skyboxes = WowDBC.open(archive, "LightSkybox")


# Blends the light volumes around the position, the map's default light taking the rest.
func sample(
	map_id: int, wow_position: Vector3, minute: float, underwater: bool = false,
	storm: float = 0.0, dead: bool = false,
) -> Sample:
	if map_id != _map_id:
		_load_map(map_id)
	var base: Condition = Condition.UNDERWATER if underwater else Condition.CLEAR
	var stormy: Condition = Condition.STORM_UNDERWATER if underwater else Condition.STORM
	if dead:
		base = Condition.DEATH
		storm = 0.0
	var leading: Condition = stormy if storm > 0.5 else base
	var half_minute: float = minute * 2.0
	var result: Sample = Sample.new()
	var weights: Dictionary[int, float] = {}
	var total: float = 0.0
	for volume: Volume in _volumes:
		var distance: float = volume.position.distance_to(wow_position)
		if distance >= volume.outer_radius:
			continue
		var weight: float = 1.0
		if distance > volume.inner_radius:
			weight = (volume.outer_radius - distance) / (volume.outer_radius - volume.inner_radius)
		weights[volume.row] = weight
		total += weight
	if total < 1.0 and _default_row >= 0:
		weights[_default_row] = 1.0 - total
		total = 1.0
	if total <= 0.0:
		return null
	var strongest: float = 0.0
	for row: int in weights:
		var weight: float = weights[row] / total
		_add(result, _params_id(row, base), half_minute, weight * (1.0 - storm))
		if storm > 0.0:
			_add(result, _params_id(row, stormy), half_minute, weight * storm)
		if weight > strongest:
			strongest = weight
			_describe(result, _params_id(row, leading))
	return result


# A light without a set for the condition keeps its clear weather one.
func _params_id(row: int, condition: Condition) -> int:
	var id: int = _lights.get_uint(row, LightColumn.PARAMS + condition)
	return id if id != 0 else _lights.get_uint(row, LightColumn.PARAMS)


func _describe(result: Sample, params_id: int) -> void:
	var params: int = _params.find(params_id)
	if params < 0:
		return
	result.stars = _params.get_uint(params, ParamsColumn.HIGHLIGHT_SKY) != 0
	var skybox: int = _skyboxes.find(_params.get_uint(params, ParamsColumn.SKYBOX))
	result.skybox = _skyboxes.get_string(skybox, SKYBOX_PATH_COLUMN) if skybox >= 0 else ""


func _load_map(map_id: int) -> void:
	_map_id = map_id
	_volumes.clear()
	_default_row = -1
	for row: int in _lights.row_count():
		if _lights.get_uint(row, LightColumn.MAP) != map_id:
			continue
		var outer: float = _lights.get_float(row, LightColumn.OUTER_RADIUS) / SCALE
		if outer <= 0.0:
			_default_row = row
			continue
		var volume: Volume = Volume.new()
		volume.position = Vector3(
			ZERO_POINT - _lights.get_float(row, LightColumn.Z) / SCALE,
			ZERO_POINT - _lights.get_float(row, LightColumn.X) / SCALE,
			_lights.get_float(row, LightColumn.HEIGHT) / SCALE,
		)
		volume.inner_radius = _lights.get_float(row, LightColumn.INNER_RADIUS) / SCALE
		volume.outer_radius = outer
		volume.row = row
		_volumes.append(volume)


func _add(result: Sample, params: int, half_minute: float, weight: float) -> void:
	var first_color: int = params * COLOR_BANDS_PER_PARAMS - (COLOR_BANDS_PER_PARAMS - 1)
	var first_float: int = params * FLOAT_BANDS_PER_PARAMS - (FLOAT_BANDS_PER_PARAMS - 1)
	for band: ColorBand in ColorBand.values():
		var color: Color = _color(first_color + band, half_minute) * weight
		result.colors[band] = result.colors.get(band, Color(0.0, 0.0, 0.0, 0.0)) + color
	var fog_end: float = _value(_float_bands, first_float + FloatBand.FOG_END, half_minute)
	var start_scale: float = _value(_float_bands, first_float + FloatBand.FOG_START_SCALE, half_minute)
	result.fog_end += fog_end / SCALE * weight
	result.fog_start += fog_end / SCALE * start_scale * weight
	result.cloud_density += weight * _value(
		_float_bands, first_float + FloatBand.CLOUD_DENSITY, half_minute
	)


func _color(band_id: int, half_minute: float) -> Color:
	var red: float = _value(_color_bands, band_id, half_minute, 16)
	var green: float = _value(_color_bands, band_id, half_minute, 8)
	var blue: float = _value(_color_bands, band_id, half_minute, 0)
	return Color(red, green, blue, 0.0) / 255.0


# Keys wrap over midnight; a shift reads that byte of a packed RGB key, none reads a float key.
func _value(bands: WowDBC, band_id: int, half_minute: float, shift: int = NO_SHIFT) -> float:
	var row: int = bands.find(band_id)
	var keys: int = bands.get_uint(row, KEY_COUNT_COLUMN) if row >= 0 else 0
	if keys == 0:
		return 0.0
	var next: int = 0
	for key: int in keys:
		if half_minute < bands.get_uint(row, FIRST_TIME_COLUMN + key):
			next = key
			break
	var previous: int = posmod(next - 1, keys)
	var from_time: float = bands.get_uint(row, FIRST_TIME_COLUMN + previous)
	var to_time: float = bands.get_uint(row, FIRST_TIME_COLUMN + next)
	var span: float = fposmod(to_time - from_time, HALF_MINUTES_PER_DAY)
	var elapsed: float = fposmod(half_minute - from_time, HALF_MINUTES_PER_DAY)
	var weight: float = clampf(elapsed / span, 0.0, 1.0) if span > 0.0 else 0.0
	var from_value: float = _key_value(bands, row, previous, shift)
	return lerpf(from_value, _key_value(bands, row, next, shift), weight)


func _key_value(bands: WowDBC, row: int, key: int, shift: int) -> float:
	if shift != NO_SHIFT:
		return (bands.get_uint(row, FIRST_VALUE_COLUMN + key) >> shift) & 0xFF
	return bands.get_float(row, FIRST_VALUE_COLUMN + key)


class Volume:
	var position: Vector3
	var inner_radius: float
	var outer_radius: float
	var row: int


class Sample:
	var colors: Dictionary[ColorBand, Color] = {}
	var fog_start: float = 0.0
	var fog_end: float = 0.0
	var cloud_density: float = 0.0
	# From the strongest light here: whether the night sky shows stars, and a skybox model.
	var stars: bool = false
	var skybox: String = ""


	func color(band: ColorBand) -> Color:
		return Color(colors.get(band, Color.BLACK), 1.0)
