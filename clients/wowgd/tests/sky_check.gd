class_name SkyCheck
extends Node

# Logs in, holds the game clock at each hour and saves user://sky_<hour>.png for a look.
const MAIN: PackedScene = preload("res://game/main.tscn")
const HOURS: PackedInt32Array = [0, 6, 12, 18, 21]
const SETTLE_SECONDS: float = 1.0
const NOON: int = 12
const LOOK_UP_PITCH: float = 0.45
const MOON_PITCH: float = 1.2
const WEATHER_SECONDS: float = 8.0

var _main: Main


func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_main.world_ready.connect(_on_world_ready, CONNECT_ONE_SHOT)


func _on_world_ready(world: World) -> void:
	var clock: GameClock = WowClient.clock
	assert(clock._synced)
	print("sky_check server minute %.1f" % clock.minute())
	var sun: DirectionalLight3D = world.get_node("Sun")
	(world.player().get_node("CameraPivot") as Node3D).rotation.x = LOOK_UP_PITCH
	var brightness: Dictionary[int, float] = {}
	for hour: int in HOURS:
		clock.override_minute = hour * 60.0
		await get_tree().create_timer(SETTLE_SECONDS).timeout
		brightness[hour] = sun.light_color.get_luminance()
		print("sky_check %02d:00 sun %s night %s" % [hour, sun.light_color, clock.is_night()])
		get_viewport().get_texture().get_image().save_png("user://sky_%02d.png" % hour)
	assert(brightness[NOON] > brightness[0])
	clock.override_minute = 0.0
	var pivot: Node3D = world.player().get_node("CameraPivot")
	pivot.rotation.x = MOON_PITCH
	for turn: int in 2:
		pivot.rotation.y = turn * PI
		await get_tree().create_timer(SETTLE_SECONDS).timeout
		get_viewport().get_texture().get_image().save_png("user://sky_moon_%d.png" % turn)
	assert(clock.is_night())
	await _check_conditions(world)
	print("sky_check passed")
	get_tree().quit()


# Storm through the server's weather, death and underwater through the sky's own switches.
func _check_conditions(world: World) -> void:
	var session: WowSession = WowClient.session
	var sky: WorldSky = world.get_node("WorldSky")
	var pivot: Node3D = world.player().get_node("CameraPivot")
	pivot.rotation = Vector3(LOOK_UP_PITCH, 0.0, 0.0)
	WowClient.clock.override_minute = NOON * 60.0
	var rain: GPUParticles3D = world.get_node("WorldWeather/Rain")
	var snow: GPUParticles3D = world.get_node("WorldWeather/Snow")
	var loop: AudioStreamPlayer = WowAssets.audio.get_node("%Weather")
	session.send_chat(WowSession.CHAT_SAY, ".wchange 1 1")
	await get_tree().create_timer(WEATHER_SECONDS).timeout
	print("sky_check rain sound %d" % WowClient.weather.sound_id)
	assert(rain.emitting and not snow.emitting and loop.playing)
	get_viewport().get_texture().get_image().save_png("user://sky_rain.png")
	session.send_chat(WowSession.CHAT_SAY, ".wchange 2 1")
	await get_tree().create_timer(WEATHER_SECONDS).timeout
	assert(snow.emitting and not rain.emitting and loop.playing)
	print("sky_check weather grade %.2f storm %.2f" % [WowClient.weather.grade, sky._storm])
	assert(WowClient.weather.grade > 0.9 and sky._storm > 0.9)
	get_viewport().get_texture().get_image().save_png("user://sky_storm.png")
	session.send_chat(WowSession.CHAT_SAY, ".wchange 0 0")
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	assert(WowClient.weather.grade == 0.0 and not snow.emitting and not loop.playing)
	sky._storm = 0.0
	sky.dead = true
	sky.update()
	await get_tree().process_frame
	await get_tree().process_frame
	print("sky_check death dome '%s'" % sky._dome_path)
	get_viewport().get_texture().get_image().save_png("user://sky_death.png")
	sky.dead = false
	var map: WowMap = world.get_node("WowMap")
	for tile: Vector2i in map.loaded_tiles():
		var liquid: MeshInstance3D = map._tiles[tile].get_node_or_null("Liquid")
		if liquid == null:
			continue
		var faces: PackedVector3Array = liquid.mesh.get_faces()
		var mid: int = (faces.size() / 6) * 3
		var centre: Vector3 = (faces[mid] + faces[mid + 1] + faces[mid + 2]) / 3.0
		var surface: Vector3 = liquid.global_transform * centre
		var height: float = map.liquid_height_at(surface)
		print("sky_check liquid at %s height %.1f" % [surface, height])
		assert(not is_nan(height) and height >= surface.y - 0.01)
		break
	var light: WorldLight = sky._light
	var wet: WorldLight.Sample = light.sample(sky.map_id, sky.wow_position, NOON * 60.0, true)
	var dry: WorldLight.Sample = light.sample(sky.map_id, sky.wow_position, NOON * 60.0)
	print("sky_check fog end dry %.0f underwater %.0f" % [dry.fog_end, wet.fog_end])
	assert(wet.fog_end < dry.fog_end)
