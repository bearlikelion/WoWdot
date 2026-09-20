class_name WorldWeather
extends Node3D

const RAIN_TEXTURE: String = "textures\\Weather\\RainDrop01.blp"
const SNOW_TEXTURE: String = "textures\\Weather\\Snowflake01.blp"
# Weather below this grade is too light to see, as on the server.
const VISIBLE_GRADE: float = 0.27
const SNOW_COLOR: Color = Color(1.0, 1.0, 1.0, 0.9)
const SAND_COLOR: Color = Color(0.78, 0.62, 0.4, 0.5)
const SNOW_GRAVITY: Vector3 = Vector3(0.3, -1.6, 0.0)
# Sandstorms reuse the flake emitter, blown sideways.
const SAND_GRAVITY: Vector3 = Vector3(14.0, -0.5, 4.0)

@onready var _rain: GPUParticles3D = %Rain
@onready var _snow: GPUParticles3D = %Snow


func _ready() -> void:
	_material(_rain).albedo_texture = WowAssets.loader.load_texture(RAIN_TEXTURE)
	_material(_snow).albedo_texture = WowAssets.loader.load_texture(SNOW_TEXTURE)
	WowClient.weather.changed.connect(_on_weather_changed)
	_on_weather_changed()


func _exit_tree() -> void:
	WowAssets.audio.play_weather(0)


# ponytail: falls through roofs and has no ground splashes, add a height check when it matters.
func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		global_position = camera.global_position


func _material(particles: GPUParticles3D) -> StandardMaterial3D:
	return particles.draw_pass_1.surface_get_material(0)


func _on_weather_changed() -> void:
	var weather: WeatherState = WowClient.weather
	var shown: bool = weather.grade >= VISIBLE_GRADE
	var flakes: bool = weather.type in [WeatherState.Type.SNOW, WeatherState.Type.STORM]
	_rain.emitting = shown and weather.type == WeatherState.Type.RAIN
	_snow.emitting = shown and flakes
	_rain.amount_ratio = weather.grade
	_snow.amount_ratio = weather.grade
	var sand: bool = weather.type == WeatherState.Type.STORM
	_material(_snow).albedo_color = SAND_COLOR if sand else SNOW_COLOR
	var process: ParticleProcessMaterial = _snow.process_material
	process.gravity = SAND_GRAVITY if sand else SNOW_GRAVITY
	WowAssets.audio.play_weather(weather.sound_id if shown else 0)
