class_name PetitionCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
# Ironforge takes a while to stream in for a character that has never been there.
const LOAD_MSEC: int = 120000
const STEP_MSEC: int = 15000
const HOST: String = "127.0.0.1"
const PORT: int = 3724
# The signer: a bare session on its own account (petition_check.sh makes the character).
const PARTNER_ACCOUNT: String = "wowgd2"
const PARTNER: String = "Dolgrim"
# Jondor Steelbrow, the Ironforge guild registrar, who is also the tabard designer.
const REGISTRAR_ENTRY: int = 5130
const REGISTRAR_AT: Vector3 = Vector3(-5016.19, -997.442, 503.966)
const HOME: Vector3 = Vector3(-6248.77, 317.339, 382.778)
# The gossip icon a guild registrar's own option carries.
const PETITION_ICON: int = 7
const GUILD_NAME: String = "Quiche Eaters"
const CHARTER_COST: int = 1000
const PURSE: int = 100000
# PETITION_SIGN_NEED_MORE, the only answer a charter with one signature can get.
const NEED_MORE: int = 4

var _failures: PackedStringArray = []
var _main: Main
var _partner: WowSession = WowSession.new()
var _partner_in_world: bool = false
var _partner_charter: int = 0
var _turn_in_result: int = -1


# Buys a guild charter, has the second character sign it, and hands it back to the registrar.
func _ready() -> void:
	_main = MAIN.instantiate()
	_main.auto_realmlist = HOST
	_main.auto_account = "wowgd"
	_main.auto_password = "wowgd"
	add_child(_main)
	_run.call_deferred()


func _process(_delta: float) -> void:
	_partner.poll()


func _run() -> void:
	if not await _until(func() -> bool: return _main.world and _main.world.player().active):
		return _finish("never reached the world")
	if not await _log_partner_in():
		return _finish("the partner never reached the world")
	var session: WowSession = WowClient.session
	var hud: Hud = _main.world.hud()
	var registrar: GuildRegistrarFrame = hud.find_child("GuildRegistrarFrame", true, false)
	var petition: PetitionFrame = hud.find_child("PetitionFrame", true, false)
	var gossip: GossipFrame = hud.find_child("GossipFrame", true, false)
	session.packet_received.connect(func(opcode: String, payload: PackedByteArray) -> void:
		if opcode == "SMSG_TURN_IN_PETITION_RESULTS":
			_turn_in_result = PacketReader.new(payload).u32()
	)
	session.send_chat(WowSession.CHAT_SAY, ".modify money %d" % PURSE)
	await _leave_guild(session)
	await _teleport(REGISTRAR_AT)
	# Ironforge streams in a grid at a time, so the registrar can take a few seconds to appear.
	var npc: int = 0
	for attempt: int in 8:
		npc = _object_with_entry(REGISTRAR_ENTRY)
		if npc != 0:
			break
		await _frames(300)
	if npc == 0:
		await _teleport(HOME)
		return _finish("no guild registrar in Ironforge")
	await _clear_old_charter(registrar)

	NpcDialog.interact(npc)
	if not await _until(func() -> bool: return gossip.visible):
		await _teleport(HOME)
		return _finish("the registrar never opened its gossip")
	var row: int = _gossip_row(gossip, PETITION_ICON)
	_check(row >= 0, "the registrar offers a petition option")
	if row < 0:
		await _teleport(HOME)
		return _finish("no petition option to pick")
	(gossip.get_node("%%GossipTitleButton%d" % (row + 1)) as BaseButton).pressed.emit()
	_check(await _until(func() -> bool: return registrar.visible), "picking it opens the registrar")

	var purse: int = Inventory.money()
	(registrar.get_node("%GuildRegistrarButton1") as BaseButton).pressed.emit()
	await _frames(10)
	(registrar.get_node("%GuildRegistrarFrameEditBox") as LineEdit).text = GUILD_NAME
	(registrar.get_node("%GuildRegistrarFramePurchaseButton") as BaseButton).pressed.emit()
	var bought: bool = await _until(func() -> bool: return registrar.carried_charter() != 0)
	_check(bought, "buying a charter puts one in the bags")
	if not bought:
		await _teleport(HOME)
		return _finish("no charter was bought")
	_check(purse - Inventory.money() == CHARTER_COST, "and costs what the registrar asked")

	var charter: int = registrar.carried_charter()
	petition.show_signatures(charter)
	var opened: bool = await _until(func() -> bool: return petition.visible)
	_check(opened, "right-clicking the charter opens the petition")
	# The signature list carries no title, so the name follows in its own query answer.
	var named: bool = await _until(func() -> bool: return not petition.charter_name().is_empty())
	_check(named and petition.charter_name() == GUILD_NAME, "which carries the name it was sold")
	_check(petition.signers().is_empty(), "and nobody has signed it yet")

	await _sign_by_partner(session, petition, charter)
	(registrar.get_node("%GuildRegistrarButton2") as BaseButton).pressed.emit()
	var answered: bool = await _until(func() -> bool: return _turn_in_result >= 0)
	_check(answered, "handing the charter back is answered")
	print("turn in result: ", _turn_in_result)
	# Nine signatures are needed and one account can only give one, so this is as far as it goes.
	_check(_turn_in_result == NEED_MORE, "and refused for too few signatures")
	Inventory.destroy(_charter_address(), 1)
	await _until(func() -> bool: return registrar.carried_charter() == 0)
	await _teleport(HOME)
	_finish("")


# The server sells a charter only to someone guildless, and guild_check makes its guild again.
func _leave_guild(session: WowSession) -> void:
	if session.get_field(session.get_player_guid(), "PLAYER_GUILDID") == 0:
		return
	session.send_packet("CMSG_GUILD_LEAVE", PackedByteArray())
	var left: bool = await _until(
		func() -> bool: return session.get_field(
			session.get_player_guid(), "PLAYER_GUILDID"
		) == 0
	)
	_check(left, "the founder can leave the guild it was in")


# The partner is brought over, offered the charter, and signs what it is shown.
func _sign_by_partner(session: WowSession, petition: PetitionFrame, charter: int) -> void:
	_partner.packet_received.connect(func(opcode: String, payload: PackedByteArray) -> void:
		if opcode == "SMSG_PETITION_SHOW_SIGNATURES":
			_partner_charter = PacketReader.new(payload).u64()
	)
	# Brought over rather than walked to, so the founder stays standing at the registrar.
	session.send_chat(WowSession.CHAT_SAY, ".namego %s" % PARTNER)
	var partner_guid: int = _partner.get_player_guid()
	var near: bool = await _until(func() -> bool: return session.has_object(partner_guid))
	_check(near, "the partner comes when called over")
	if not near:
		return
	session.set_selection(partner_guid)
	await _frames(30)
	var offered: bool = false
	for attempt: int in 4:
		(petition.get_node("%PetitionFrameRequestButton") as BaseButton).pressed.emit()
		offered = await _until(func() -> bool: return _partner_charter != 0, 5000)
		if offered:
			break
	_check(offered, "the partner is shown the charter")
	if not offered:
		return
	var payload: PackedByteArray = []
	payload.resize(9)
	payload.encode_u64(0, _partner_charter)
	_partner.send_packet("CMSG_PETITION_SIGN", payload)
	var signed: bool = await _until(func() -> bool: return petition.signers().size() > 0)
	_check(signed, "and signing it shows on the charter")
	if signed:
		petition.show_signatures(charter)
		await _frames(30)


# A charter left over from an earlier run stops the server selling another one.
func _clear_old_charter(registrar: GuildRegistrarFrame) -> void:
	if registrar.carried_charter() == 0:
		return
	Inventory.destroy(_charter_address(), 1)
	await _until(func() -> bool: return registrar.carried_charter() == 0)


func _charter_address() -> Vector2i:
	var found: Vector2i = Inventory.find_item(GuildRegistrarFrame.CHARTER_ENTRY)
	return Inventory.wire_address(found.x, found.y)


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


func _log_partner_in() -> bool:
	_partner.realms_received.connect(func(_realms: Array) -> void: _partner.select_realm(0))
	_partner.characters_received.connect(func(characters: Array) -> void:
		for character: Dictionary in characters:
			if character["name"] == PARTNER:
				_partner.enter_world(character["guid"])
	)
	_partner.world_entered.connect(
		func(_map: int, _at: Vector3, _facing: float) -> void: _partner_in_world = true
	)
	_partner.login(HOST, PORT, PARTNER_ACCOUNT, PARTNER_ACCOUNT)
	return await _until(func() -> bool: return _partner_in_world, TIMEOUT_MSEC)


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
	print("petition_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
