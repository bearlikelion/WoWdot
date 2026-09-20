class_name RaidCheck
extends Node

const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const STEP_MSEC: int = 10000
const HOST: String = "127.0.0.1"
const PORT: int = 3724
# The second player: a bare session on its own account (raid_check.sh makes the character).
const PARTNER_ACCOUNT: String = "wowgd2"
const PARTNER: String = "Dolgrim"
# Which subgroup to move the partner into, counted from zero as the wire does.
const OTHER_SUBGROUP: int = 1

var _failures: PackedStringArray = []
var _main: Main
var _partner: WowSession = WowSession.new()
var _partner_in_world: bool = false
var _partner_invited: bool = false


# A raid is a party that has been converted: subgroups, assistants and target icons all hang on it.
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
	if not await _until(func() -> bool: return _main.world and _main.world.player().active,
			TIMEOUT_MSEC):
		return _finish("never reached the world")
	if not await _log_partner_in():
		return _finish("the partner never reached the world")
	await _frames(60)

	PartyFrame.invite(PARTNER)
	if not await _until(func() -> bool: return _partner_invited):
		return _finish("the invite never reached the partner")
	_partner.send_packet("CMSG_GROUP_ACCEPT", PackedByteArray())
	if not await _until(PartyFrame.in_party):
		return _finish("the partner never joined the party")
	_check(not PartyFrame.is_raid, "a fresh party is not a raid")

	PartyFrame.convert_to_raid()
	var raided: bool = await _until(func() -> bool: return PartyFrame.is_raid)
	_check(raided, "converting the party makes it a raid")
	if not raided:
		PartyFrame.leave()
		return _finish("no raid to work with")
	var partner_guid: int = _partner.get_player_guid()
	print("raid: %s, own subgroup %d" % [PartyFrame.members, PartyFrame.own_subgroup])

	PartyFrame.move_to_subgroup(PARTNER, OTHER_SUBGROUP)
	_check(
		await _until(
			func() -> bool: return PartyFrame.subgroup_of(partner_guid) == OTHER_SUBGROUP
		),
		"and a member can be moved into another subgroup",
	)

	PartyFrame.set_assistant(partner_guid, true)
	_check(
		await _until(func() -> bool: return PartyFrame.is_assistant(partner_guid)),
		"and made an assistant",
	)

	PartyFrame.set_target_icon(PartyFrame.TargetIcon.SKULL, partner_guid)
	var marked: bool = await _until(
		func() -> bool: return PartyFrame.target_icons.get(PartyFrame.TargetIcon.SKULL, 0) \
			== partner_guid
	)
	_check(marked, "a target takes the skull")
	PartyFrame.target_icons.clear()
	PartyFrame.request_target_icons()
	_check(
		await _until(
			func() -> bool: return PartyFrame.target_icons.get(
				PartyFrame.TargetIcon.SKULL, 0
			) == partner_guid
		),
		"and asking for the whole list gets it back",
	)
	print("icons: %s, partner subgroup %d, assistant %s" % [
		PartyFrame.target_icons, PartyFrame.subgroup_of(partner_guid),
		PartyFrame.is_assistant(partner_guid),
	])

	PartyFrame.leave()
	_check(await _until(func() -> bool: return not PartyFrame.is_raid), "leaving ends the raid")
	_finish("")


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
	_partner.packet_received.connect(func(opcode: String, _payload: PackedByteArray) -> void:
		if opcode == "SMSG_GROUP_INVITE":
			_partner_invited = true
	)
	_partner.login(HOST, PORT, PARTNER_ACCOUNT, PARTNER_ACCOUNT)
	return await _until(func() -> bool: return _partner_in_world, TIMEOUT_MSEC)


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
	print("raid_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
