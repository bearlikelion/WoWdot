class_name Main
extends Node

signal world_ready(world: World)

const WORLD: PackedScene = preload("res://game/world/world.tscn")

## Filled from `-- --realmlist= --account= --password= --character=`; no character enters the first.
@export var auto_realmlist: String = ""
@export var auto_account: String = ""
@export var auto_password: String = ""
@export var auto_character: String = ""

var world: World

@onready var _glue: Glue = %Glue


func _ready() -> void:
	_read_command_line()
	WowClient.session.world_entered.connect(_on_world_entered)
	WowClient.session.state_changed.connect(_on_state_changed)
	if not auto_account.is_empty():
		_glue.auto_login(auto_realmlist, auto_account, auto_password, auto_character)


# The loading screen stays up until the tiles around the player have streamed in.
func _process(_delta: float) -> void:
	if world == null or not _glue.visible:
		return
	var progress: float = world.load_progress()
	_glue.set_loading_progress(progress)
	if world.player().active and progress >= 1.0:
		_glue.hide()
		world_ready.emit(world)


func _read_command_line() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		if parts.size() < 2:
			continue
		match parts[0]:
			"realmlist":
				auto_realmlist = parts[1]
			"account":
				auto_account = parts[1]
			"password":
				auto_password = parts[1]
			"character":
				auto_character = parts[1]


func _on_state_changed(state: WowSession.State, _message: String) -> void:
	var left_world: bool = state in [
		WowSession.STATE_CHARACTER_LIST, WowSession.STATE_FAILED, WowSession.STATE_DISCONNECTED,
	]
	if world and left_world:
		world.queue_free()
		world = null
		_glue.show()


func _on_world_entered(map_id: int, position: Vector3, orientation: float) -> void:
	if world == null:
		world = WORLD.instantiate()
		add_child(world)
	world.enter(map_id, position, orientation)
