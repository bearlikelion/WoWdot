class_name ProtocolGapsCheck
extends Node

const ME: int = 0
const OTHER: int = 77
const FROSTBOLT: int = 116

var _failures: PackedStringArray = []
var _events: Array[CombatEvents.CombatEvent] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	WowClient.combat.logged.connect(_events.append)
	var session: WowSession = WowClient.session
	var spell_name: String = WowAssets.spells.spell_name(FROSTBOLT)

	var dispel: PackedByteArray = [0x01, OTHER, 0x01, 5, 1, 0, 0, 0, 0, 0, 0, 0]
	dispel.encode_u32(8, FROSTBOLT)
	session.packet_received.emit("SMSG_SPELLDISPELLOG", dispel)
	_check(_events.size() == 1 and _events[0].target == OTHER, "dispel log decodes its victim")
	_check(_last_line().contains(spell_name), "dispel line names the aura")

	var kill: PackedByteArray = []
	kill.resize(12)
	kill.encode_u64(0, ME)
	kill.encode_u32(8, FROSTBOLT)
	session.packet_received.emit("SMSG_SPELLINSTAKILLLOG", kill)
	var expected: String = WowStrings.get_text("INSTAKILLSELF") % spell_name
	_check(_last_line() == expected, "instakill on the player reads INSTAKILLSELF")

	var push: PackedByteArray = []
	push.resize(41)
	push.encode_u64(0, ME)
	push.encode_u32(16, 1)
	push.encode_u32(37, 3)
	var looted: String = WowStrings.format(
		WowStrings.get_text("LOOT_ITEM_SELF_MULTIPLE"), ["Linen Cloth", 3],
	)
	_check(LootFrame.push_text(push, "Linen Cloth", ME) == looted, "item push reads as loot")
	push.encode_u32(16, 0)
	_check(LootFrame.push_text(push, "Linen Cloth", ME).is_empty(), "silent item push prints nothing")

	var scores: PackedByteArray = []
	scores.resize(6 + 32 + 8)
	scores.encode_u8(0, 1)
	scores.encode_u8(1, Battlegrounds.Winner.ALLIANCE)
	scores.encode_u32(2, 1)
	scores.encode_u64(6, OTHER)
	scores.encode_u32(18, 4)
	scores.encode_u32(34, 2)
	scores.encode_u32(38, 3)
	session.packet_received.emit("MSG_PVP_LOG_DATA", scores)
	var board: Battlegrounds = WowClient.battlegrounds
	_check(board.winner == Battlegrounds.Winner.ALLIANCE, "score data names the winner")
	_check(board.scores.size() == 1 and board.scores[0]["killing_blows"] == 4, "score row decodes")
	_check(board.scores[0]["stats"] == PackedInt32Array([3, 0]), "score row keeps its stat columns")

	var places: PackedByteArray = []
	places.resize(4 + 16 + 1 + 16)
	places.encode_u32(0, 1)
	places.encode_u64(4, OTHER)
	places.encode_float(12, 1000.0)
	places.encode_u8(20, 1)
	places.encode_u64(21, OTHER + 1)
	places.encode_float(33, -50.0)
	session.packet_received.emit("MSG_BATTLEGROUND_PLAYER_POSITIONS", places)
	_check(board.positions.get(OTHER, Vector2.ZERO).x == 1000.0, "team mate positions decode")
	_check(board.flag_carrier == OTHER + 1, "the flag carrier is named")
	_check(board.positions.get(OTHER + 1, Vector2.ZERO).y == -50.0, "and placed")

	var weapons: PackedByteArray = [2, 0, 0, 0, 0]
	weapons.encode_u32(1, 1 << 7)
	session.packet_received.emit("SMSG_SET_PROFICIENCY", weapons)
	var skills: Proficiencies = WowClient.proficiencies
	_check(skills.can_use(2, 7) and not skills.can_use(2, 8), "proficiency gates weapon subclasses")
	_check(skills.can_use(0, 3), "consumables are never gated")
	_check(not skills.subclass_name(2, 7).is_empty(), "weapon subclasses have names")

	_check(Inventory.keyring_size(39) == 4 and Inventory.keyring_size(40) == 8, "keyring grows at 40")
	_check(Inventory.keyring_size(60) == 12, "and again at 50")
	var key_slot: Vector2i = Inventory.wire_address(Inventory.KEYRING, 2)
	_check(key_slot == Vector2i(255, 83), "keyring slots follow the buyback in the inventory array")

	var item_cooldown: PackedByteArray = []
	item_cooldown.resize(12)
	item_cooldown.encode_u32(8, FROSTBOLT)
	session.packet_received.emit("SMSG_ITEM_COOLDOWN", item_cooldown)
	var timer: Vector2i = WowClient.cooldowns.get_cooldown(FROSTBOLT)
	_check(timer.y == Cooldowns.ITEM_COOLDOWN_MSEC, "item cooldown starts the use spell's timer")

	var played: PackedByteArray = []
	played.resize(8)
	played.encode_u32(0, 90061)
	var total: String = ServerNotices.line("SMSG_PLAYED_TIME", played).get_slice("\n", 0)
	_check(total.contains("1 days, 1 hours, 1 minutes, 1 seconds"), "played time splits into parts")
	var mount: PackedByteArray = [2, 0, 0, 0]
	var mounted: String = WowStrings.get_text("ERR_MOUNT_ALREADYMOUNTED")
	_check(ServerNotices.line("SMSG_MOUNTRESULT", mount) == mounted, "mount result names its error")
	mount[0] = 10
	_check(ServerNotices.line("SMSG_MOUNTRESULT", mount).is_empty(), "a good mount prints nothing")

	if _failures.is_empty():
		print("protocol_gaps_check: OK")
	else:
		for line: String in _failures:
			print("  ", line)
		print("protocol_gaps_check: FAILED")
	get_tree().quit(0 if _failures.is_empty() else 1)


func _last_line() -> String:
	return CombatLogFrame.format(_events[-1]) if not _events.is_empty() else ""


func _check(passed: bool, what: String) -> void:
	if not passed:
		_failures.append(what)
