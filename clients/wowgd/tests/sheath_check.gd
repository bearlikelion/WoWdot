class_name SheathCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STATE_WAIT_MSEC: int = 5000

var _failures: PackedStringArray = []
var _main: Main


# Toggles the player's sheath with Z and checks the main hand weapon moves between hand and back.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_run.call_deferred()


func _run() -> void:
	var ready_at: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while _main.world == null or not _main.world.player().active:
		if Time.get_ticks_msec() > ready_at:
			return _finish("never reached the world")
		await get_tree().process_frame
	await _frames(60)
	var session: WowSession = WowClient.session
	var me: int = session.get_player_guid()
	var entry: int = CharacterModels.visible_items(session, me)[CharacterModels.WEAPON_SLOTS[0]]
	var info: Dictionary = session.get_item_info(entry)
	_check(info.has("sheath"), "item queries carry the sheath type")
	print("main hand ", info.get("name", "?"), " sheath ", info.get("sheath", -1))
	var hand_bone: String = _point_bone(ItemModels.Attachment.HAND_RIGHT)
	var sheathed: ItemModels.Sheath = info.get("sheath", 0)
	var sheath_bone: String = _point_bone(ItemModels.SHEATH_POINTS[sheathed].x) \
	if ItemModels.SHEATH_POINTS.has(sheathed) else hand_bone
	for i: int in 2:
		var before: ItemModels.SheathState = ItemModels.sheath_state(session, me)
		_press("toggle_sheath")
		var changed_by: int = Time.get_ticks_msec() + STATE_WAIT_MSEC
		while ItemModels.sheath_state(session, me) == before and Time.get_ticks_msec() < changed_by:
			await get_tree().process_frame
		await _frames(5)
		var state: ItemModels.SheathState = ItemModels.sheath_state(session, me)
		var bone: String = _weapon_bone(_main.world.player())
		print("sheath state ", state, " main hand on ", bone)
		_check(state != before, "Z changes the sheath state")
		var expected: String = hand_bone if state == ItemModels.SheathState.MELEE else sheath_bone
		_check(bone == expected, "the main hand hangs on %s in state %d" % [expected, state])
	var armed: int = 0
	var entities: Entities = _main.world.get_node("Entities")
	for guid: int in session.get_object_guids():
		var node: Node3D = entities.unit_node(guid)
		if node and session.get_object_type(guid) == Entities.ObjectType.UNIT \
		and not _weapon_bone(node).is_empty():
			armed += 1
	print("armed creatures ", armed)
	_check(armed > 0, "creatures carry their weapons")
	_finish("")


func _point_bone(point: int) -> String:
	var session: WowSession = WowClient.session
	var display: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_DISPLAYID")
	var path: String = WowAssets.creatures.model_path(display)
	var skeleton: Skeleton3D = _main.world.player().find_child("Skeleton", true, false)
	for attachment: Dictionary in WowAssets.loader.get_m2_info(path)["attachments"]:
		if attachment["id"] == point:
			return skeleton.get_bone_name(attachment["bone"])
	return ""


func _weapon_bone(model: Node3D) -> String:
	var skeleton: Skeleton3D = model.find_child("Skeleton", true, false)
	var holder: BoneAttachment3D = skeleton.get_node_or_null("MAIN_HAND") if skeleton else null
	return holder.bone_name if holder else ""


func _press(action: String) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("sheath_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
