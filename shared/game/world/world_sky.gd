class_name WorldSky
extends Node

const NOON_MINUTE: float = 720.0
# The light circles the sky once a day and stays high, as stock terrain is lit without shadows.
const LOW_ELEVATION: float = deg_to_rad(45.0)
const HIGH_ELEVATION: float = deg_to_rad(70.0)
const STARS: String = "Environments\\Stars\\Stars.m2"
# Stars and the moon fade in over this long before dusk and out after dawn.
const TWILIGHT_MINUTES: float = 90.0
# Stock 1.12 has no moon art, so the night disc is a plain pale one.
const MOON_COLOR: Color = Color(0.92, 0.95, 1.0)
const MOON_HALO_COLOR: Color = Color(0.12, 0.16, 0.26)
# Stock night light is nearly as strong as daylight, which reads as day on lit, shadowed terrain.
const NIGHT_SUN_ENERGY: float = 0.3
# Storms take this much of the sun's glow off the clouds.
const STORM_CLOUD_DIMMING: float = 0.75
# Weather below this grade is too light to see, as on the server.
const VISIBLE_WEATHER_GRADE: float = 0.27
# How much of a full weather change one refresh makes.
const STORM_STEP: float = 0.05
# Of the camera's far plane, so the dome is never clipped.
const DOME_RADIUS: float = 0.8
const SKY_UNIFORMS: Dictionary[StringName, WorldLight.ColorBand] = {
	&"sky_top": WorldLight.ColorBand.SKY_TOP,
	&"sky_middle": WorldLight.ColorBand.SKY_MIDDLE,
	&"sky_lower": WorldLight.ColorBand.SKY_LOWER,
	&"sky_above_horizon": WorldLight.ColorBand.SKY_ABOVE_HORIZON,
	&"sky_horizon": WorldLight.ColorBand.SKY_HORIZON,
	&"fog_color": WorldLight.ColorBand.FOG,
	&"cloud_sun": WorldLight.ColorBand.CLOUD_SUN,
	&"cloud_slope": WorldLight.ColorBand.CLOUD_SLOPE,
	&"cloud_base": WorldLight.ColorBand.CLOUD_BASE,
}

@export var sun: DirectionalLight3D
@export var environment: WorldEnvironment

const GLOW_SCALE: float = 0.6

var map_id: int = 0
var wow_position: Vector3 = Vector3.ZERO
var underwater: bool = false
var dead: bool = false

var _light: WorldLight
var _storm: float = 0.0
var _dome_path: String = ""
var _dome_materials: Array[BaseMaterial3D] = []

@onready var _refresh: Timer = %Refresh
@onready var _dome: Node3D = %Dome


func _ready() -> void:
	_light = WorldLight.new(WowAssets.archive)
	_refresh.timeout.connect(update)


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		_dome.global_position = camera.global_position


# WoW adds ambient and diffuse in gamma space; the sun takes linear ambient up to that sum.
func update() -> void:
	var minute: float = WowClient.clock.minute()
	# The sun steps once a game minute, as each small turn re-lays the shadow map and it swims.
	var day_angle: float = (floorf(minute) - NOON_MINUTE) / GameClock.MINUTES_PER_DAY * TAU
	var elevation: float = lerpf(LOW_ELEVATION, HIGH_ELEVATION, 0.5 + 0.5 * cos(day_angle * 2.0))
	var sun_rotation: Vector3 = Vector3(-elevation, -day_angle, 0.0)
	if not sun.rotation.is_equal_approx(sun_rotation):
		sun.rotation = sun_rotation
	var grade: float = WowClient.weather.grade
	var storm_target: float = grade if grade >= VISIBLE_WEATHER_GRADE else 0.0
	_storm = move_toward(_storm, storm_target, STORM_STEP)
	var sample: WorldLight.Sample = _light.sample(
		map_id, wow_position, minute, underwater, _storm, dead
	)
	if sample == null:
		return
	var ambient: Color = sample.color(WorldLight.ColorBand.AMBIENT)
	var lit: Color = (ambient + sample.color(WorldLight.ColorBand.DIFFUSE)).clamp()
	var sunlight: Color = (lit.srgb_to_linear() - ambient.srgb_to_linear()).linear_to_srgb()
	sun.light_color = Color(sunlight, 1.0)
	var night: float = _night(minute)
	sun.light_energy = lerpf(1.0, NIGHT_SUN_ENERGY, night)
	var settings: Environment = environment.environment
	settings.ambient_light_color = ambient
	settings.fog_light_color = sample.color(WorldLight.ColorBand.FOG)
	settings.fog_depth_begin = sample.fog_start
	settings.fog_depth_end = sample.fog_end
	settings.fog_sky_affect = 1.0 if underwater else 0.0
	# ponytail: Godot's own glow stands in for the stock FFXGlow pass, scaled by the light's glow.
	settings.glow_enabled = sample.glow > 0.0
	settings.glow_intensity = sample.glow * GLOW_SCALE
	var sky: ShaderMaterial = settings.sky.sky_material
	for uniform: StringName in SKY_UNIFORMS:
		sky.set_shader_parameter(uniform, sample.color(SKY_UNIFORMS[uniform]))
	sky.set_shader_parameter(&"cloud_density", lerpf(sample.cloud_density, 1.0, _storm))
	sky.set_shader_parameter(&"cloud_glow", (1.0 - night) * (1.0 - STORM_CLOUD_DIMMING * _storm))
	sky.set_shader_parameter(&"cloud_storm", _storm)
	var disc: Color = sample.color(WorldLight.ColorBand.SUN).lerp(MOON_COLOR, night)
	var halo: Color = sample.color(WorldLight.ColorBand.SUN).lerp(MOON_HALO_COLOR, night)
	sky.set_shader_parameter(&"disc_color", disc)
	sky.set_shader_parameter(&"halo_color", halo)
	var stars: bool = sample.skybox.is_empty() and sample.stars
	_show_dome(STARS if stars else sample.skybox, night if stars else 1.0)


# 0 by day and 1 at night, easing through the twilights.
func _night(minute: float) -> float:
	var dusk: float = smoothstep(
		GameClock.DUSK_MINUTE - TWILIGHT_MINUTES, GameClock.DUSK_MINUTE, minute
	)
	var dawn: float = smoothstep(
		GameClock.DAWN_MINUTE, GameClock.DAWN_MINUTE + TWILIGHT_MINUTES, minute
	)
	return dusk + 1.0 - dawn if minute < NOON_MINUTE else dusk


func _show_dome(path: String, alpha: float) -> void:
	if path != _dome_path:
		_dome_path = path
		_load_dome(path)
	_dome.visible = alpha > 0.0 and not _dome_materials.is_empty()
	for material: BaseMaterial3D in _dome_materials:
		material.albedo_color.a = alpha


# The loader shares its materials, so the dome draws with unfogged, unlit copies.
func _load_dome(path: String) -> void:
	_dome_materials.clear()
	for child: Node in _dome.get_children():
		child.queue_free()
	var model: Node3D = WowAssets.loader.load_m2(path) if not path.is_empty() else null
	if model == null:
		return
	_dome.add_child(model)
	var radius: float = 0.0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		radius = maxf(radius, mesh.get_aabb().get_longest_axis_size() * 0.5)
		for surface: int in mesh.mesh.get_surface_count():
			var material: BaseMaterial3D = mesh.mesh.surface_get_material(surface).duplicate()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.disable_fog = true
			if material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mesh.set_surface_override_material(surface, material)
			_dome_materials.append(material)
	UnitAnimations.set_base(model, ["Stand"])
	var far: float = get_viewport().get_camera_3d().far
	model.scale = Vector3.ONE * (far * DOME_RADIUS / maxf(radius, 0.001))
