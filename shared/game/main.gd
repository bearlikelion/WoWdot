class_name Main
extends Node

signal world_ready(world: World)

const WORLD: PackedScene = preload("res://game/world/world.tscn")

## From `--realm`, `--account`, `--password` and `--character`; no character enters the first.
@export var auto_realmlist: String = ""
@export var auto_account: String = ""
@export var auto_password: String = ""
@export var auto_character: String = ""

var world: World

var _map_id: int = 0
var _intro: bool = false
var _bench: bool = false
var _bench_chat: PackedStringArray = []
var _bench_shots: String = ""
var _bench_size: Vector2i = Vector2i.ZERO
var _bench_camera: Vector2 = Vector2.ZERO

@onready var _glue: Glue = %Glue


func _ready() -> void:
	WowAssets.video.apply()
	WowCursor.show(WowCursor.Kind.POINT)
	_read_command_line()
	WowClient.session.world_entered.connect(_on_world_entered)
	WowClient.session.state_changed.connect(_on_state_changed)
	WowClient.session.transfer_pending.connect(_on_transfer_pending)
	if not auto_realmlist.is_empty():
		_glue.use_realmlist(auto_realmlist)
	if not auto_account.is_empty():
		_glue.auto_login(auto_realmlist, auto_account, auto_password, auto_character)
	if _bench:
		_bench_mark("main ready")
		if _bench_size != Vector2i.ZERO:
			_bench_window()
		WowClient.session.characters_received.connect(_on_bench_characters)
		world_ready.connect(_on_bench_world_ready, CONNECT_ONE_SHOT)


# The loading screen stays up until the tiles around the player have streamed in.
func _process(_delta: float) -> void:
	if world == null:
		return
	# An intro flies while the tiles stream, and its view is the one to show meanwhile.
	var intro: bool = world.intro_playing()
	if intro != _intro:
		_intro = intro
		if intro:
			_glue.hide()
		elif not world.player().active:
			_glue.show_loading(_map_id)
	if intro or not _glue.visible:
		return
	var progress: float = world.load_progress()
	_glue.set_loading_progress(progress)
	if world.player().active and progress >= 1.0:
		_glue.hide()
		world_ready.emit(world)


# Options work before or after `--`, as `--realm=127.0.0.1` or `--realm 127.0.0.1`.
func _read_command_line() -> void:
	var args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for i: int in args.size():
		if not args[i].begins_with("--"):
			continue
		if args[i] == "--bench":
			_bench = true
			continue
		var parts: PackedStringArray = args[i].trim_prefix("--").split("=", true, 1)
		var value: String = parts[1] if parts.size() > 1 else ""
		if parts.size() == 1 and i + 1 < args.size() and not args[i + 1].begins_with("--"):
			value = args[i + 1]
		if value.is_empty():
			continue
		match parts[0]:
			"realm", "realmlist":
				auto_realmlist = value
			"account":
				auto_account = value
			"password":
				auto_password = value
			"character":
				auto_character = value
			"chat":
				_bench_chat = value.split(";", false)
			"resolution":
				_bench_size = Vector2i(int(value.get_slice("x", 0)), int(value.get_slice("x", 1)))
			"camera":
				_bench_camera = Vector2(float(value.get_slice(",", 0)), float(value.get_slice(",", 1)))
			"shot":
				_bench_shots = value


func _on_state_changed(state: WowSession.State, _message: String) -> void:
	if _bench:
		_bench_mark("session state %d" % state)
	var left_world: bool = state in [
		WowSession.STATE_CHARACTER_LIST, WowSession.STATE_FAILED, WowSession.STATE_DISCONNECTED,
	]
	if left_world:
		Channels.forget()
	if world and left_world:
		world.queue_free()
		world = null
		_glue.show()


func _on_transfer_pending(map_id: int, transport_entry: int) -> void:
	if world == null:
		return
	world.begin_transfer(transport_entry)
	_glue.show_loading(map_id)


func _on_world_entered(map_id: int, position: Vector3, orientation: float) -> void:
	_map_id = map_id
	if _bench:
		_bench_mark("world entered map %d" % map_id)
	if world == null:
		world = WORLD.instantiate()
		add_child(world)
	world.enter(map_id, position, orientation)


func _bench_mark(milestone: String) -> void:
	print("bench %d %s" % [Time.get_ticks_msec(), milestone])


func _on_bench_characters(characters: Array) -> void:
	var names: PackedStringArray = []
	for character: Dictionary in characters:
		names.append(character["name"])
	_bench_mark("characters %s" % ",".join(names))


func _on_bench_world_ready(_world: World) -> void:
	_bench_mark("world ready")
	await _bench_settle()
	_bench_mark("world idle")
	for i: int in _bench_chat.size():
		WowClient.session.send_chat(WowSession.CHAT_SAY, _bench_chat[i])
		# The server needs a moment to move the player before the map starts streaming.
		await get_tree().create_timer(2.0).timeout
		await _bench_settle()
		_bench_mark("teleport %d idle" % i)
		if _bench_shots.is_empty():
			continue
		world.hud().visible = false
		if _bench_camera != Vector2.ZERO:
			var pivot: Node3D = world.player().get_node("CameraPivot")
			pivot.rotation.x = deg_to_rad(_bench_camera.x)
			pivot.get_node("SpringArm3D").spring_length = _bench_camera.y
		for _frame: int in 60:
			await get_tree().process_frame
		DirAccess.make_dir_recursive_absolute(_bench_shots)
		get_viewport().get_texture().get_image().save_png(_bench_shots.path_join("%d.png" % i))
		_bench_mark("shot %d" % i)
	if not _bench_shots.is_empty():
		get_tree().quit()
		return
	while true:
		await get_tree().create_timer(5.0).timeout
		_bench_mark("fps %d" % Engine.get_frames_per_second())


# The export opens fullscreen, and leaving it maximizes the window a little later.
func _bench_window() -> void:
	await get_tree().create_timer(0.5).timeout
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = _bench_size


func _bench_settle() -> void:
	while world == null or _glue.visible or not world.player().active \
	or not world.get_node("WowMap").is_idle():
		await get_tree().process_frame
