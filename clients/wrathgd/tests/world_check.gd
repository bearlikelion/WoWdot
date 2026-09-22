class_name WorldCheck
extends Node

const STEP_TIMEOUT_MSEC: int = 60000
const REALMLIST: String = "127.0.0.1"
const AUTH_PORT: int = 3725
const ACCOUNT: String = "wowgd"
const PASSWORD: String = "wowgd"
const CHARACTER: String = "Wrathcheck"
const HEARTBEATS: int = 10
const STEP_METRES: float = 0.5
const STEP_SECONDS: float = 0.1
const TELEPORT_METRES: float = 20.0
const COPPER: int = 1000
# Arcane Intellect, a buff with a duration, and Curse of Weakness for the debuff side.
const BUFF_SPELL: int = 1459
const DEBUFF_SPELL: int = 702
const LEARN_SPELL: int = 100
const QUEST: int = 783
const QUEST_TITLE: String = "A Threat Within"
const DAMAGE: int = 5
const DUMMY_CREATURE: int = 6
const UNIT_TYPE: int = 3

# Wire values, which WotLK shares with vanilla for these two.
enum MoveFlag { NONE = 0, FORWARD = 1, JUMPING = 0x2000, FLYING = 0x800000, CAN_FLY = 0x1000000 }
const FLIGHT_METRES: float = 10.0
const JUMP_SPEED: float = 7.95

var _session: WowSession = WowSession.new()
var _realms: Array = []
var _characters: Array = []
var _enumerations: int = 0
var _entries: int = 0
var _created: int = -1
var _deleted: int = -1
var _map: int = -1
var _position: Vector3 = Vector3.ZERO
var _teleports: int = 0
var _walked_from_teleport: Vector3 = Vector3.ZERO
var _chat: Array[Dictionary] = []
var _time_syncs: int = 0
var _cast_failures: Array[int] = []
var _combat: CombatEvents = CombatEvents.new(_session)
var _melee: Array[CombatEvents.CombatEvent] = []
var _spawned: int = 0
var _quest_givers: int = 0
var _fly_counter: int = -1
var _failures: PackedStringArray = []


func _ready() -> void:
	_session.realms_received.connect(_on_realms_received)
	_session.characters_received.connect(_on_characters_received)
	_session.character_created.connect(_on_character_created)
	_session.character_deleted.connect(_on_character_deleted)
	_session.world_entered.connect(_on_world_entered)
	_session.player_teleported.connect(_on_player_teleported)
	_session.packet_received.connect(_on_packet_received)
	_session.chat_received.connect(_on_chat_received)
	_session.spell_cast_failed.connect(_on_spell_cast_failed)
	_combat.logged.connect(_on_combat_logged)
	_session.object_created.connect(_on_object_created)
	_session.quest_giver_status_received.connect(func(_guid: int, _status: int) -> void: _quest_givers += 1)
	_run.call_deferred()


func _process(_delta: float) -> void:
	_session.poll()


func _run() -> void:
	if not await _log_in():
		return _finish()
	var guid: int = await _make_character()
	if guid == 0:
		return _finish()
	if not await _enter(guid):
		return _finish()
	var start: Vector3 = _position
	print("entered map %d at %v" % [_map, start])
	await _check_update_fields(guid)
	var walked: Vector3 = await _walk()
	await _jump(walked)
	_session.send_packet("CMSG_QUESTGIVER_STATUS_MULTIPLE_QUERY", PackedByteArray())
	await _until(func() -> bool: return _quest_givers > 0, "the batched quest giver statuses arrive")
	if not await _log_out():
		return _finish()
	if not await _enter(guid):
		return _finish()
	print("came back at %v" % _position)
	await _until(_sees_units, "creatures come into view again after logging back in")
	_check(_position.distance_to(walked) < 1.0, "the server kept the walk's last position")
	_check(_position.distance_to(start) > 3.0, "the kept position is not where the walk began")
	await _auras(guid)
	await _packets()
	if await _gm_command() and await _teleport() and await _log_out() and await _enter(guid):
		print("after the teleport and a second walk, came back at %v" % _position)
		_check(_position.distance_to(_walked_from_teleport) < 1.0,
				"the server took movement after the teleport was acknowledged")
	_check(_time_syncs > 0, "the server asked for a time sync while in the world")
	await _flight(guid)
	if await _log_out():
		await _remove_character(guid)
	_finish()


# 3.3.5 sends a unit's auras as their own packets, so the buff bars read them off the session.
func _auras(guid: int) -> void:
	for spell: int in [BUFF_SPELL, DEBUFF_SPELL]:
		_session.send_chat(WowSession.CHAT_SAY, ".aura %d" % spell)
		if not await _until(func() -> bool: return _aura(guid, spell) != null,
				"aura %d arrives" % spell):
			return
	var buff: Dictionary = _aura(guid, BUFF_SPELL)
	var debuff: Dictionary = _aura(guid, DEBUFF_SPELL)
	_check(not buff["harmful"], "Arcane Intellect reads as a buff")
	_check(debuff["harmful"], "Curse of Weakness reads as a debuff")
	_check(buff["max_duration_msec"] > 0, "the buff carries the duration the server sent")
	print("auras: %d for %.0fs, %d for %.0fs" % [
		BUFF_SPELL, buff["duration_msec"] / 1000.0,
		DEBUFF_SPELL, debuff["duration_msec"] / 1000.0,
	])
	for spell: int in [BUFF_SPELL, DEBUFF_SPELL]:
		_session.send_chat(WowSession.CHAT_SAY, ".unaura %d" % spell)
		_check(await _until(func() -> bool: return _aura(guid, spell) == null,
				"aura %d is taken off again" % spell), "aura %d goes away" % spell)
	var left: PackedStringArray = []
	for aura: Dictionary in UnitAuras.read(_session, guid):
		left.append(str(aura["spell"]))
	print("auras left on the player: %s" % ", ".join(left))


# The packets 3.3.5 lays out differently from 1.12: wide spell ids, the cast count
# before a failure, and the longer quest query.
func _packets() -> void:
	_session.send_chat(WowSession.CHAT_SAY, ".learn %d" % LEARN_SPELL)
	if await _until(func() -> bool: return LEARN_SPELL in _session.get_known_spells(),
			"the learned spell arrives"):
		_session.cast_spell(LEARN_SPELL, 0)
		if await _until(func() -> bool: return not _cast_failures.is_empty(),
				"casting without a target fails"):
			_check(_cast_failures[0] > 0, "the failure carries its reason (%d)" % _cast_failures[0])
	_session.get_quest_info(QUEST)
	if await _until(func() -> bool: return not _session.get_quest_info(QUEST).is_empty(),
			"the quest query is answered"):
		var info: Dictionary = _session.get_quest_info(QUEST)
		_check(info["title"] == QUEST_TITLE, "the quest title reads (%s)" % info["title"])
		_check(info["objective_list"].size() >= 4, "the objectives read")
	# The server only logs the blow when it lands on someone else, so a temporary kobold takes it.
	_session.send_chat(WowSession.CHAT_SAY, ".npc add temp %d" % DUMMY_CREATURE)
	if not await _until(func() -> bool: return _spawned != 0, "a temporary creature spawns"):
		return
	_session.set_selection(_spawned)
	_session.send_chat(WowSession.CHAT_SAY, ".damage %d" % DAMAGE)
	if await _until(func() -> bool: return not _melee.is_empty(), "the GM damage lands as a melee log"):
		_check(_melee[0].amount == DAMAGE and _melee[0].target == _spawned,
				"the melee log carries the amount and target (%d)" % _melee[0].amount)
	_session.send_chat(WowSession.CHAT_SAY, ".npc delete")
	_session.set_selection(0)


func _sees_units() -> bool:
	for guid: int in _session.get_object_guids():
		if _session.get_object_type(guid) == UNIT_TYPE:
			return true
	return false


func _aura(guid: int, spell: int) -> Variant:
	for aura: Dictionary in UnitAuras.read(_session, guid):
		if aura["spell"] == spell:
			return aura
	return null


# GM commands travel as ordinary say, so this proves the chat types are renumbered
# both ways: the command lands and the server's answer reads back.
func _gm_command() -> bool:
	var guid: int = _session.get_player_guid()
	if not _check(_session.get_field(guid, "PLAYER_FIELD_COINAGE") == 0,
			"a new character carries no money"):
		return false
	_session.send_chat(WowSession.CHAT_SAY, ".modify money %d" % COPPER)
	if not await _until(
			func() -> bool: return _session.get_field(guid, "PLAYER_FIELD_COINAGE") == COPPER,
			"a GM command reaches the server"):
		return false
	return _check(_said("You give"), "the server's answer reads back as chat")


# A near teleport holds the player until the ack lands, so the walk after it only
# reaches the server when the ack was right.
func _teleport() -> bool:
	var goal: Vector3 = _position + Vector3(0.0, TELEPORT_METRES, 0.0)
	var seen: int = _teleports
	_session.send_chat(WowSession.CHAT_SAY, ".go xyz %f %f %f" % [goal.x, goal.y, goal.z])
	if not await _until(func() -> bool: return _teleports > seen, "the GM command teleports"):
		return false
	if not _check(_position.distance_to(goal) < 2.0, "the teleport lands where it was asked"):
		return false
	_walked_from_teleport = await _walk()
	return true


# The update object that follows login, read through the WotLK field indices.
func _check_update_fields(guid: int) -> void:
	if not await _until(func() -> bool: return _session.has_object(guid),
			"the player object arrives in an update"):
		return
	_check(_session.get_field(guid, "UNIT_FIELD_HEALTH") > 0, "the player's health reads")
	_check(_session.get_field(guid, "UNIT_FIELD_LEVEL") == 1, "the player's level reads as 1")
	var worn: PackedInt32Array = CharacterModels.visible_items(_session, guid)
	var entries: Array[int] = []
	for entry: int in worn:
		if entry != 0:
			entries.append(entry)
	print("visible items: %s" % [entries])
	if _check(not entries.is_empty(), "a new character wears its starting gear"):
		for entry: int in entries:
			_session.get_item_info(entry)
		if await _until(func() -> bool: return not _session.get_item_info(entries[-1]).is_empty(),
				"the item queries answer"):
			var displays: WowDBC = WowDBC.open(WowLoader.get_shared().get_archive(), "ItemDisplayInfo")
			for entry: int in entries:
				var info: Dictionary = _session.get_item_info(entry)
				var row: int = displays.find(info.get("display_id", 0))
				print("item %d %s: display %d torso '%s' legs '%s'" % [entry, info.get("name", ""),
						info.get("display_id", 0), displays.get_string(row, "TextureTorsoUpper") if row >= 0 else "?",
						displays.get_string(row, "TextureLegUpper") if row >= 0 else "?"])
			_check(_session.get_item_info(entries[0]).get("display_id", 0) > 0, "the worn items carry display ids")
	_check(_session.get_field(guid, "OBJECT_FIELD_ENTRY") == 0, "a player carries no entry")
	print("objects in sight: %d" % _session.get_object_guids().size())


func _log_in() -> bool:
	_session.login(REALMLIST, AUTH_PORT, ACCOUNT, PASSWORD)
	if not await _until(func() -> bool: return not _realms.is_empty(),
			"the realm list arrives"):
		return false
	_session.select_realm(0)
	return await _until(
			func() -> bool: return _session.get_state() == WowSession.STATE_CHARACTER_LIST,
			"the world server takes the session")


func _make_character() -> int:
	if not await _list_characters():
		return 0
	# A run that ends early leaves the character behind, and its state would skew these checks.
	if _find(CHARACTER) != 0:
		await _remove_character(_find(CHARACTER))
		if not await _list_characters():
			return 0
	_session.create_character({ "name": CHARACTER, "race": 1, "class": 1, "gender": 0 })
	if not await _until(func() -> bool: return _created >= 0, "the create answer arrives"):
		return 0
	if not _check(_created == 1, "creating %s is accepted (code %d)" % [CHARACTER, _created]):
		return 0
	if not await _list_characters():
		return 0
	var guid: int = _find(CHARACTER)
	_check(guid != 0, "%s is in the character list" % CHARACTER)
	return guid


func _remove_character(guid: int) -> void:
	_deleted = -1
	_session.delete_character(guid)
	if await _until(func() -> bool: return _deleted >= 0, "the delete answer arrives"):
		_check(_deleted == 1, "deleting %s is accepted (code %d)" % [CHARACTER, _deleted])


func _list_characters() -> bool:
	var seen: int = _enumerations
	# AzerothCore's AntiDOS kicks a fourth CMSG_CHAR_ENUM within one second.
	await get_tree().create_timer(1.0).timeout
	_session.request_characters()
	return await _until(func() -> bool: return _enumerations > seen,
			"the character list arrives")


func _enter(guid: int) -> bool:
	var seen: int = _entries
	_session.enter_world(guid)
	return await _until(
			func() -> bool: return _entries > seen and _session.get_state() == WowSession.STATE_IN_WORLD,
			"the world takes the character")


func _log_out() -> bool:
	_session.logout()
	return await _until(
			func() -> bool: return _session.get_state() == WowSession.STATE_CHARACTER_LIST,
			"logging out returns to the character list")


# Walks the wire's +x by a run speed's worth of ground each heartbeat.
func _walk() -> Vector3:
	var at: Vector3 = _position
	_send("MSG_MOVE_START_FORWARD", at, MoveFlag.FORWARD)
	for i: int in HEARTBEATS:
		await _wait(STEP_SECONDS)
		at.x += STEP_METRES
		_send("MSG_MOVE_HEARTBEAT", at, MoveFlag.FORWARD)
	await _wait(STEP_SECONDS)
	_send("MSG_MOVE_STOP", at, MoveFlag.NONE)
	await _wait(STEP_SECONDS)
	return at


# 3.3.5 flies on the bit 1.12 used for transports, so a height the server keeps proves the flag.
func _flight(guid: int) -> void:
	_session.send_chat(WowSession.CHAT_SAY, ".gm fly on")
	if not await _until(func() -> bool: return _fly_counter >= 0, "the GM command grants flight"):
		return
	var applied: PackedByteArray = []
	applied.resize(4)
	applied.encode_u32(0, 1)
	var flying: int = MoveFlag.CAN_FLY | MoveFlag.FLYING
	_session.send_movement("CMSG_MOVE_SET_CAN_FLY_ACK", _position, 0.0, MoveFlag.CAN_FLY, 0,
			Vector3.ZERO, 0.0, _fly_counter, applied)
	_session.send_movement("CMSG_MOVE_SET_FLY", _position, 0.0, flying)
	var at: Vector3 = _position
	for i: int in HEARTBEATS:
		await _wait(STEP_SECONDS)
		at.z += FLIGHT_METRES / HEARTBEATS
		_session.send_movement("MSG_MOVE_HEARTBEAT", at, 0.0, flying)
	await _wait(STEP_SECONDS)
	if await _log_out() and await _enter(guid):
		_check(_position.z > at.z - 1.0,
				"the server kept the flight's height (%.1f, flew to %.1f)" % [_position.z, at.z])


# A jump carries the fall time and velocity block, whose flag 3.3.5 renumbered.
func _jump(at: Vector3) -> void:
	_session.send_movement("MSG_MOVE_JUMP", at, 0.0, MoveFlag.JUMPING, 0, Vector3(0.0, 0.0, JUMP_SPEED))
	await _wait(STEP_SECONDS)
	_session.send_movement("MSG_MOVE_HEARTBEAT", at + Vector3(0.0, 0.0, 1.0), 0.0, MoveFlag.JUMPING,
			int(STEP_SECONDS * 1000.0), Vector3(0.0, 0.0, JUMP_SPEED))
	await _wait(STEP_SECONDS)
	_session.send_movement("MSG_MOVE_FALL_LAND", at, 0.0, MoveFlag.NONE, int(STEP_SECONDS * 2000.0))
	await _wait(STEP_SECONDS)
	_check(_session.get_state() == WowSession.STATE_IN_WORLD, "the server takes a jump and its landing")


func _send(opcode: String, at: Vector3, flags: MoveFlag) -> void:
	_session.send_movement(opcode, at, 0.0, flags)


func _find(character_name: String) -> int:
	for character: Dictionary in _characters:
		if character["name"] == character_name:
			return character["guid"]
	return 0


func _on_realms_received(realms: Array) -> void:
	_realms = realms


func _on_characters_received(characters: Array) -> void:
	_characters = characters
	_enumerations += 1


func _on_character_created(success: bool, code: int) -> void:
	_created = 1 if success else code


func _on_character_deleted(success: bool, code: int) -> void:
	_deleted = 1 if success else code


func _said(fragment: String) -> bool:
	for line: Dictionary in _chat:
		if String(line["text"]).contains(fragment):
			return true
	return false


func _on_chat_received(line: Dictionary) -> void:
	_chat.append(line)


func _on_packet_received(opcode: String, _payload: PackedByteArray) -> void:
	if opcode == "SMSG_TIME_SYNC_REQ":
		_time_syncs += 1
	elif opcode == "SMSG_MOVE_SET_CAN_FLY":
		var reader: PacketReader = PacketReader.new(_payload)
		reader.packed_guid()
		_fly_counter = reader.u32()


func _on_object_created(guid: int, type_id: int) -> void:
	if type_id == UNIT_TYPE and _spawned == 0 and _session.get_field(guid, "OBJECT_FIELD_ENTRY") == DUMMY_CREATURE:
		_spawned = guid


func _on_combat_logged(event: CombatEvents.CombatEvent) -> void:
	if event.kind == CombatEvents.Kind.MELEE:
		_melee.append(event)


func _on_spell_cast_failed(_caster: int, _spell_id: int, reason: int) -> void:
	_cast_failures.append(reason)


func _on_player_teleported(position: Vector3, _orientation: float) -> void:
	_position = position
	_teleports += 1


func _on_world_entered(map_id: int, position: Vector3, _orientation: float) -> void:
	_map = map_id
	_position = position
	_entries += 1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _until(condition: Callable, what: String) -> bool:
	var give_up: int = Time.get_ticks_msec() + STEP_TIMEOUT_MSEC
	while not condition.call():
		if _session.get_state() == WowSession.STATE_FAILED:
			_failures.append("%s (session failed)" % what)
			return false
		if Time.get_ticks_msec() > give_up:
			_failures.append(what)
			return false
		await get_tree().process_frame
	return true


func _check(condition: bool, what: String) -> bool:
	if not condition:
		_failures.append(what)
	return condition


func _finish() -> void:
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("world_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
