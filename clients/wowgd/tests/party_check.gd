class_name PartyCheck
extends Node

# Kobold Camp Cleanup, given in Coldridge Valley.
const SHARED_QUEST: int = 179
# Wolves do not drop something every time, so the check tries a few of them.
const KILLS_FOR_LOOT: int = 3
const MAIN: PackedScene = preload("res://game/main.tscn")
const TIMEOUT_MSEC: int = 60000
const HOST: String = "127.0.0.1"
const PORT: int = 3724
# The second player: a bare session on its own account (party_check.sh makes the character).
const PARTNER_ACCOUNT: String = "wowgd2"
const PARTNER: String = "Dolgrim"

var _failures: PackedStringArray = []
var _main: Main
var _partner: WowSession = WowSession.new()
var _partner_in_world: bool = false
var _partner_invited: bool = false
var _partner_asked: bool = false


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
	await _frames(60)
	var session: WowSession = WowClient.session
	var hud: Hud = _main.world.hud()
	var me: String = session.get_object_name(session.get_player_guid())
	var popup: StaticPopup = hud.get_node("%UIPanels").get_node("%StaticPopup1")
	var first: PartyMemberFrame = hud.get_node("%PartyFrame").get_node("%PartyMemberFrame1")

	_send_name("CMSG_GROUP_INVITE", me)
	_check(await _until(func() -> bool: return popup.visible, 5000), "an invite raises the popup")
	print("popup: '%s'" % (popup.get_node("%StaticPopup1Text") as Label).text)
	_capture("user://party_invite.png")
	(popup.get_node("%StaticPopup1Button1") as BaseButton).pressed.emit()
	_check(await _until(PartyFrame.in_party, 5000), "accepting joins the party")
	await _frames(30)
	print("party: %s, leader is me: %s, frame '%s'" % [
		PartyFrame.members, PartyFrame.is_leader(), first.get("_name_label").text,
	])
	_check(first.visible and first.member_name == PARTNER, "the partner has a party frame")
	_capture("user://party_frame.png")

	var menu: DropDownList = hud.get_node("%UnitMenu")
	get_viewport().warp_mouse(Vector2(200.0, 120.0))
	await _frames(5)
	(hud.get_node("%PlayerFrame") as UnitFrame).unit_menu_requested.emit(session.get_player_guid())
	await _frames(10)
	_check(_menu_texts(menu).has("Leave party"), "right-clicking my portrait offers leaving")
	_capture("user://party_menu.png")
	menu.hide()
	var partner_guid: int = PartyFrame.members[0]["guid"]
	PartyFrame.leave()
	_check(await _until(_alone, 5000), "leaving empties the party")
	_check(not first.visible, "leaving hides the party frames")

	(hud.get_node("%TargetFrame") as UnitFrame).unit_menu_requested.emit(partner_guid)
	await _frames(10)
	var offers_invite: bool = menu.visible and _menu_texts(menu).has("Invite")
	_check(offers_invite, "right-clicking a player offers an invite")
	menu.hide()

	var chat: ChatFrame = hud.get_node("%ChatFrame1")
	chat.call("_on_text_submitted", "/invite " + PARTNER)
	var reached: bool = await _until(func() -> bool: return _partner_invited, 5000)
	_check(reached, "/invite reaches the partner")
	_partner.send_packet("CMSG_GROUP_ACCEPT", PackedByteArray())
	_check(await _until(PartyFrame.in_party, 5000), "the partner accepting forms the party")
	_check(PartyFrame.is_leader(), "the inviter leads the party")
	await _ready_check(hud, chat)
	await _loot_roll(hud)
	await _share_a_quest(hud)
	chat.call("_on_text_submitted", "/uninvite " + PARTNER)
	_check(await _until(_alone, 5000), "/uninvite removes the partner")
	_finish("")


# Group loot with the lowest threshold puts every drop up for a roll, when a drop comes at all.
func _loot_roll(hud: Hud) -> void:
	var session: WowSession = WowClient.session
	var rolls: LootRolls = hud.find_child("LootRolls", true, false)
	var lines: PackedStringArray = []
	rolls.message_added.connect(func(text: String) -> void: lines.append(text))
	PartyFrame.set_loot_method(PartyFrame.LootMethod.GROUP_LOOT, 0)
	# Only party members in range roll, so the partner is summoned over first.
	session.send_chat(WowSession.CHAT_SAY, ".namego %s" % PARTNER)
	await get_tree().create_timer(3.0).timeout
	for attempt: int in KILLS_FOR_LOOT:
		var prey: int = _nearest_creature()
		if prey == 0:
			break
		await _kill(prey)
		if await _until(func() -> bool: return rolls.get_child_count() > 0, 5000):
			break
	if rolls.get_child_count() == 0:
		print("no drop to roll for after %d kills" % KILLS_FOR_LOOT)
		PartyFrame.set_loot_method(PartyFrame.LootMethod.GROUP_LOOT, 2)
		return
	var frame: GroupLootFrame = rolls.get_child(0)
	frame.rolled.emit(GroupLootFrame.Roll.GREED)
	var answered: bool = await _until(func() -> bool: return not lines.is_empty(), 10000)
	_check(answered, "the roll is answered")
	if answered:
		print("roll line: ", lines[0])
	PartyFrame.set_loot_method(PartyFrame.LootMethod.GROUP_LOOT, 2)


# The party only rolls for loot it earned, so the player lands the killing blow itself.
func _kill(prey: int) -> void:
	var session: WowSession = WowClient.session
	var player: Player = _main.world.player()
	var prey_node: Node3D = (_main.world.get_node("Entities") as Entities).unit_node(prey)
	_main.world.select(prey)
	player.global_position = prey_node.global_position + Vector3.RIGHT
	player.movement_changed.emit(
		"MSG_MOVE_HEARTBEAT", player.global_position, player.orientation(), 0, 0, Vector3.ZERO,
		-1, PackedByteArray(),
	)
	await get_tree().create_timer(1.0).timeout
	session.send_chat(WowSession.CHAT_SAY, ".modify hp 1")
	await get_tree().create_timer(1.0).timeout
	session.attack(prey)
	await _until(func() -> bool: return session.get_field(prey, "UNIT_FIELD_HEALTH") == 0, 20000)
	session.stop_attack()
	await get_tree().create_timer(1.0).timeout
	LootFrame.loot(prey)


func _nearest_creature() -> int:
	var session: WowSession = WowClient.session
	var here: Vector3 = session.get_object_position(session.get_player_guid())
	var best: int = 0
	var best_range: float = INF
	for guid: int in session.get_object_guids():
		if session.get_object_type(guid) != Entities.ObjectType.UNIT \
		or session.get_field(guid, "UNIT_FIELD_HEALTH") == 0 \
		or not session.get_object_name(guid).contains("Wolf"):
			continue
		var away: float = session.get_object_position(guid).distance_to(here)
		if away < best_range:
			best_range = away
			best = guid
	return best


# The leader asks, the partner answers, and the answer comes back as a line in the chat.
func _ready_check(hud: Hud, chat: ChatFrame) -> void:
	var lines: PackedStringArray = []
	var party: PartyFrame = hud.get_node("%PartyFrame")
	party.message_added.connect(func(text: String) -> void: lines.append(text))
	_partner_asked = false
	chat.call("_on_text_submitted", "/readycheck")
	var asked: bool = await _until(func() -> bool: return _partner_asked, 5000)
	_check(asked, "a ready check reaches the party")
	if not asked:
		return
	_partner.send_packet("MSG_RAID_READY_CHECK", PackedByteArray([1]))
	var answered: bool = await _until(func() -> bool: return not lines.is_empty(), 5000)
	_check(answered, "the partner's answer comes back")
	if answered:
		print("ready check answer: ", lines[0])


# Sharing tells the sharer how the party answered, even when the partner is too far to take it.
func _share_a_quest(hud: Hud) -> void:
	var session: WowSession = WowClient.session
	# GM commands act on the selection, so the corpse from the loot roll is dropped first.
	_main.world.select(session.get_player_guid())
	await get_tree().create_timer(1.0).timeout
	session.send_chat(WowSession.CHAT_SAY, ".quest add %d" % SHARED_QUEST)
	if not await _until(func() -> bool: return not QuestLog.slots().is_empty(), 5000):
		return _check(false, "the quest to share was added")
	var quest_log: QuestLogFrame = hud.find_child("QuestLogFrame", true, false)
	var answers: PackedStringArray = []
	quest_log.share_answered.connect(func(text: String) -> void: answers.append(text))
	await _press(KEY_L)
	await _frames(20)
	if not quest_log.is_visible_in_tree():
		return _check(false, "the quest log opens")
	if not await _until(func() -> bool: return quest_log._selected_slot >= 0, 5000):
		return _check(false, "the quest log selects the quest")
	var push: BaseButton = quest_log.get_node("%QuestFramePushQuestButton")
	_check(not push.disabled, "the share button works in a party")
	push.pressed.emit()
	var answered: bool = await _until(func() -> bool: return not answers.is_empty(), 5000)
	_check(answered, "sharing a quest is answered")
	if answered:
		print("share answer: ", answers[0])
	await _press(KEY_L)
	session.send_chat(WowSession.CHAT_SAY, ".quest remove %d" % SHARED_QUEST)


func _press(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(3)


func _alone() -> bool:
	return not PartyFrame.in_party()


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
		elif opcode == "MSG_RAID_READY_CHECK":
			_partner_asked = true
	)
	_partner.login(HOST, PORT, PARTNER_ACCOUNT, PARTNER_ACCOUNT)
	return await _until(func() -> bool: return _partner_in_world)


func _send_name(opcode: String, player_name: String) -> void:
	var payload: PackedByteArray = player_name.to_utf8_buffer()
	payload.append(0)
	_partner.send_packet(opcode, payload)


func _until(condition: Callable, timeout_msec: int = TIMEOUT_MSEC) -> bool:
	var give_up: int = Time.get_ticks_msec() + timeout_msec
	while not condition.call():
		if Time.get_ticks_msec() > give_up:
			return false
		await get_tree().process_frame
	return true


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().process_frame


func _capture(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("wrote ", ProjectSettings.globalize_path(path))


# The menu's entries, as the visible rows read.
func _menu_texts(menu: DropDownList) -> PackedStringArray:
	var texts: PackedStringArray = []
	for i: int in DropDownList.MAX_BUTTONS:
		if (menu.get_node("%%DropDownList1Button%d" % (i + 1)) as Control).visible:
			texts.append(
				(menu.get_node("%%DropDownList1Button%dNormalText" % (i + 1)) as Label).text
			)
	return texts


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _finish(fatal: String) -> void:
	if not fatal.is_empty():
		_failures.append(fatal)
	for failure: String in _failures:
		printerr("FAIL: ", failure)
	print("party_check: ", "OK" if _failures.is_empty() else "%d failed" % _failures.size())
	get_tree().quit(0 if _failures.is_empty() else 1)
