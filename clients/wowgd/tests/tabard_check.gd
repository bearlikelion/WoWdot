class_name TabardCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 15000
# Jondor Steelbrow, who designs guild crests as well as selling charters.
const VENDOR_ENTRY: int = 5130
const VENDOR_AT: Vector3 = Vector3(-5016.19, -997.442, 503.966)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
# The gossip icon a tabard designer's own option carries.
const TABARD_ICON: int = 8
const GUILD_NAME: String = "WoWdot Testers"
const PURSE: int = 2000000
const WANTED_EMBLEM: int = 3
const WANTED_COLOR: int = 1

var _failures: PackedStringArray = []
var _main: Main
var _saved: int = -1


# Opens the crest designer, cycles the emblem and saves it on the guild.
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
	var session: WowSession = WowClient.session
	var hud: Hud = _main.world.hud()
	var tabard: TabardFrame = hud.find_child("TabardFrame", true, false)
	var friends: FriendsFrame = hud.find_child("FriendsFrame", true, false)
	var gossip: GossipFrame = hud.find_child("GossipFrame", true, false)
	session.packet_received.connect(func(opcode: String, payload: PackedByteArray) -> void:
		if opcode == "MSG_SAVE_GUILD_EMBLEM":
			_saved = PacketReader.new(payload).u32()
	)
	session.send_chat(WowSession.CHAT_SAY, ".modify money %d" % PURSE)
	await _ensure_guild(session)
	await _teleport(VENDOR_AT)
	var npc: int = 0
	for attempt: int in 8:
		npc = _object_with_entry(VENDOR_ENTRY)
		if npc != 0:
			break
		await _frames(300)
	if npc == 0:
		await _teleport(HOME)
		return _finish("no tabard designer in Ironforge")

	# The designer wanders, so the check walks to wherever it is standing now.
	await _teleport(session.get_object_position(npc))
	NpcDialog.interact(npc)
	if not await _until(func() -> bool: return gossip.visible):
		await _teleport(HOME)
		return _finish("the designer never opened its gossip")
	var row: int = _gossip_row(gossip, TABARD_ICON)
	_check(row >= 0, "the designer offers a crest option")
	if row < 0:
		await _teleport(HOME)
		return _finish("no crest option to pick")
	(gossip.get_node("%%GossipTitleButton%d" % (row + 1)) as BaseButton).pressed.emit()
	_check(await _until(func() -> bool: return tabard.visible), "picking it opens the designer")

	var emblem: TextureRect = tabard.get_node("%TabardFrameEmblemTopLeft")
	var before: String = (emblem.texture as WowTexture).file
	for i: int in WANTED_EMBLEM:
		(tabard.get_node("%TabardFrameCustomization1RightButton") as BaseButton).pressed.emit()
	for i: int in WANTED_COLOR:
		(tabard.get_node("%TabardFrameCustomization2RightButton") as BaseButton).pressed.emit()
	await _frames(5)
	var after: String = (emblem.texture as WowTexture).file
	_check(after != before, "cycling the icon changes the preview")
	_check(
		after == TabardFrame.EMBLEM_PATH % [WANTED_EMBLEM, WANTED_COLOR, "U"],
		"to the art the choices name (%s)" % after,
	)

	(tabard.get_node("%TabardFrameAcceptButton") as BaseButton).pressed.emit()
	var answered: bool = await _until(func() -> bool: return _saved >= 0)
	_check(answered, "saving the crest is answered")
	print("save result: ", _saved)
	_check(_saved == TabardFrame.Result.SUCCESS, "and accepted")
	if _saved == TabardFrame.Result.SUCCESS:
		var back: bool = await _until(func() -> bool: return friends.emblem().size() == 5)
		_check(back, "the guild reports its crest back")
		if back:
			print("guild crest: ", friends.emblem())
			_check(
				friends.emblem()[TabardFrame.Part.EMBLEM] == WANTED_EMBLEM
				and friends.emblem()[TabardFrame.Part.EMBLEM_COLOR] == WANTED_COLOR,
				"with the icon that was chosen",
			)
	await _teleport(HOME)
	_finish("")


# The crest is the guild master's to change, so the character has to lead one.
func _ensure_guild(session: WowSession) -> void:
	if session.get_field(session.get_player_guid(), "PLAYER_GUILDID") != 0:
		return
	var me: String = session.get_object_name(session.get_player_guid())
	session.send_chat(WowSession.CHAT_SAY, '.guild create %s "%s"' % [me, GUILD_NAME])
	var made: bool = await _until(
		func() -> bool: return session.get_field(
			session.get_player_guid(), "PLAYER_GUILDID"
		) != 0
	)
	_check(made, "the character leads a guild to put a crest on")


func _gossip_row(gossip: GossipFrame, icon: int) -> int:
	for i: int in gossip._rows.size():
		if gossip._rows[i].get("icon", -1) == icon:
			return i
	return -1


func _object_with_entry(entry: int) -> int:
	var session: WowSession = WowClient.session
	for guid: int in session.get_object_guids():
		if session.get_field(guid, "OBJECT_FIELD_ENTRY") == entry:
			return guid
	return 0


func _teleport(wow_position: Vector3) -> void:
	WowClient.session.send_chat(
		WowSession.CHAT_SAY, ".go xyz %f %f %f" % [wow_position.x, wow_position.y, wow_position.z]
	)
	await _frames(30)
	await _until(func() -> bool: return _main.world.player().active, TIMEOUT_MSEC)
	await _frames(60)


func _until(condition: Callable, timeout_msec: int = STEP_MSEC) -> bool:
	var until: int = Time.get_ticks_msec() + timeout_msec
	while not condition.call() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	return condition.call()


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
	print("tabard_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
