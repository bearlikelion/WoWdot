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


func _on_state_changed(state: WowSession.State, _message: String) -> void:
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
	if world == null:
		world = WORLD.instantiate()
		add_child(world)
	world.enter(map_id, position, orientation)
