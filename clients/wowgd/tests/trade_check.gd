class_name TradeCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const HOST: String = "127.0.0.1"
# The second player: a bare session on its own account (trade_check.sh makes the character).
const PARTNER_ACCOUNT: String = "wowgd2"
const PARTNER: String = "Dolgrim"
const PORT: int = 3724
const LINEN_CLOTH: int = 2589

var _failures: PackedStringArray = []
var _main: Main
var _partner: WowSession = WowSession.new()
var _partner_in_world: bool = false
var _offered: bool = false
var _duel_flag: int = 0


# Asks the partner to trade, puts an item up, then calls the trade off.
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
	var trade: TradeFrame = hud.find_child("TradeFrame", true, false)
	session.send_chat(WowSession.CHAT_SAY, ".goname %s" % PARTNER)
	await get_tree().create_timer(3.0).timeout
	session.send_chat(WowSession.CHAT_SAY, ".additem %d 1" % LINEN_CLOTH)
	var partner_guid: int = await _until_partner_seen()
	if partner_guid == 0:
		return _finish("the partner never came into view")

	trade.start(partner_guid)
	var asked: bool = await _until(func() -> bool: return _offered)
	_check(asked, "the partner is asked to trade")
	_partner.send_packet("CMSG_BEGIN_TRADE", PackedByteArray())
	var opened: bool = await _until(func() -> bool: return trade.visible)
	_check(opened, "accepting opens the trade window")
	if opened:
		var stored: Vector2i = _first_of(LINEN_CLOTH)
		_check(stored.x >= 0, "the player carries something to trade")
		if stored.x >= 0:
			hud.use_container_item(stored.x, stored.y)
			var name_label: Label = trade.find_child("TradePlayerItem1Name", true, false)
			var shown: bool = await _until(
				func() -> bool: return not name_label.text.is_empty(), 10000
			)
			_check(shown, "the item shows in the first trade slot")
			print("traded item: ", name_label.text)
		trade.cancel()
		await _frames(20)
		_check(not trade.visible, "cancelling closes the trade window")
	await _duel(hud, partner_guid)
	_check(session.get_state() == WowSession.STATE_IN_WORLD, "the server kept the session")
	_finish("")


# The challenge plants a flag, and the partner's answer shows in the duel countdown.
func _duel(hud: Hud, partner_guid: int) -> void:
	var lines: PackedStringArray = []
	WowClient.session.packet_received.connect(func(opcode: String, _p: PackedByteArray) -> void:
		if opcode.begins_with("SMSG_DUEL"):
			lines.append(opcode)
	)
	var duel: Duel = Duel.new(WowClient.session)
	duel.challenge(partner_guid)
	var asked: bool = await _until(
		func() -> bool: return "SMSG_DUEL_REQUESTED" in lines, 15000
	)
	_check(asked, "challenging a player asks for a duel")
	if asked:
		_partner_duel_answer("CMSG_DUEL_CANCELLED")
		var ended: bool = await _until(
			func() -> bool: return "SMSG_DUEL_COMPLETE" in lines, 15000
		)
		_check(ended, "declining ends the duel")


# The partner answers with the flag guid the request carried.
func _partner_duel_answer(opcode: String) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, _duel_flag)
	_partner.send_packet(opcode, payload)


func _first_of(entry: int) -> Vector2i:
	for bag: int in Inventory.BAG_COUNT + 1:
		for slot: int in Inventory.container_size(bag):
			var item: int = Inventory.container_item(bag, slot)
			if item != 0 and Inventory.entry(item) == entry:
				return Vector2i(bag, slot)
	return Vector2i(-1, -1)


# A lambda captures its locals by value, so the search runs in the loop itself.
func _until_partner_seen() -> int:
	var session: WowSession = WowClient.session
	var until: int = Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < until:
		for guid: int in session.get_object_guids():
			if session.get_object_type(guid) == Entities.ObjectType.PLAYER \
			and session.get_object_name(guid) == PARTNER:
				return guid
		await get_tree().process_frame
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
	_partner.packet_received.connect(func(opcode: String, payload: PackedByteArray) -> void:
		if opcode == "SMSG_TRADE_STATUS":
			_offered = true
		elif opcode == "SMSG_DUEL_REQUESTED":
			_duel_flag = PacketReader.new(payload).u64()
	)
	_partner.login(HOST, PORT, PARTNER_ACCOUNT, PARTNER_ACCOUNT)
	return await _until(func() -> bool: return _partner_in_world)


func _until(condition: Callable, timeout_msec: int = TIMEOUT_MSEC) -> bool:
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
	print("trade_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
