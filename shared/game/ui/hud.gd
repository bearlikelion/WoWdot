class_name Hud
extends Control

signal action_used(slot: int)
signal spell_used(spell_id: int)
signal unit_selected(guid: int)
signal ticket_requested(text: String)

# WoW lays the interface out on a screen 768 units tall and scales it to the window.
enum UnitMenuItem {
	INVITE, UNINVITE, LEAVE, TRADE, DUEL, RESET_INSTANCES, PET_DISMISS, PET_ABANDON, INSPECT,
}

const UI_HEIGHT: float = 768.0
const MIN_STOCK_SCALE: float = 0.9
const EMOTE_COLOR: Color = Color(1.0, 0.5, 0.25)
const ERROR_COLOR: Color = Color(1.0, 0.1, 0.1)
const NOTICE_COLOR: Color = Color(1.0, 0.82, 0.0)
# TYPEID_ITEM and TYPEID_CONTAINER.
const ITEM_TYPES: Array[int] = [1, 2]
# UIParent_ManageFramePositions lifts the casting bar clear of the bottom action bars.
const CASTING_BAR_LIFT: float = 40.0
# The one reason SMSG_INVENTORY_CHANGE_FAILURE follows with a level.
const EQUIP_ERR_LEVEL: int = 1
const LOGOUT_SECONDS: float = 20.0
const SWING_ERRORS: Dictionary[WowSession.AttackError, String] = {
	WowSession.ATTACK_ERROR_NOT_IN_RANGE: "ERR_BADATTACKPOS",
	WowSession.ATTACK_ERROR_BAD_FACING: "ERR_BADATTACKFACING",
	WowSession.ATTACK_ERROR_NOT_STANDING: "ERR_CANTATTACK_NOTSTANDING",
	WowSession.ATTACK_ERROR_DEAD_TARGET: "ERR_INVALID_ATTACK_TARGET",
	WowSession.ATTACK_ERROR_CANT_ATTACK: "ERR_INVALID_ATTACK_TARGET",
}
# SPELL_FAILED_NO_POWER names the power the player lacks.
const OUT_OF_POWER: Array[String] = [
	"ERR_OUT_OF_MANA", "ERR_OUT_OF_RAGE", "ERR_OUT_OF_FOCUS", "ERR_OUT_OF_ENERGY",
]
# CHAT_TAB_SHOW_DELAY: the dock's tabs wait for the mouse to rest over the chat this long.
const CHAT_TAB_SHOW_DELAY: float = 0.2
# Unit menu ids from here up name a master loot candidate.
const MASTER_LOOT_ID: int = 100
const PLAYER_FLAG_AFK: int = 0x02
const PLAYER_FLAG_DND: int = 0x04
const CHANNEL_LIST_WAIT: float = 1.0
# 1.12 has no ready check, so its question is ours rather than a GlobalStrings line.
const READY_CHECK_QUESTION: String = "Are you ready?"
const SERVER_MESSAGE_KEYS: Dictionary[int, String] = {
	1: "SERVER_MESSAGE_SHUTDOWN_TIME", 2: "SERVER_MESSAGE_RESTART_TIME",
	4: "SERVER_MESSAGE_SHUTDOWN_CANCELLED", 5: "SERVER_MESSAGE_RESTART_CANCELLED",
}
const CHAT_RESTRICTED_KEYS: Dictionary[int, String] = {
	0: "ERR_CHAT_RESTRICTED", 1: "ERR_CHAT_THROTTLED", 2: "ERR_USER_SQUELCHED",
}

var _area: int = 0
var _away: int = 0
var _loot_slot: int = 0
var _loot_candidates: PackedInt64Array = []
var _menu_name: String = ""
var _menu_guid: int = 0
var _duel: Duel
var _named_pet: int = 0
var _spell_failures: Dictionary = {}
var _equip_failures: Dictionary = {}
var _casting_bar_top: float = 0.0
var _chat_hover_time: float = 0.0

@onready var _ui_parent: Control = %UIParent
@onready var _main_menu_bar: MainMenuBar = %MainMenuBar
@onready var _player_frame: PlayerFrame = %PlayerFrame
@onready var _target_frame: TargetFrame = %TargetFrame
@onready var _party: PartyFrame = %PartyFrame
@onready var _unit_menu: DropDownList = %UnitMenu
@onready var _errors: WowMessageFrame = %UIErrorsFrame
@onready var _casting_bar: CastingBar = %CastingBarFrame
@onready var _side_bars: SideActionBars = %MultiBarRight
@onready var _minimap: MinimapCluster = %MinimapCluster
@onready var _chat: ChatFrame = %ChatFrame1
@onready var _chat_frames: Array[DockedChatFrame] = [_chat, %ChatFrame2]
@onready var _panels: PanelManager = %UIPanels
@onready var _character: CharacterFrame = _panels.get_node("%CharacterFrame")
@onready var _bank: BankFrame = _panels.get_node("%BankFrame")
@onready var _stable: PetStableFrame = _panels.get_node("%PetStableFrame")
@onready var _mail: MailFrame = _panels.get_node("%MailFrame")
@onready var _auction: AuctionFrame = _panels.get_node("%AuctionFrame")
@onready var _registrar: GuildRegistrarFrame = _panels.get_node("%GuildRegistrarFrame")
@onready var _petition: PetitionFrame = _panels.get_node("%PetitionFrame")
@onready var _tabard: TabardFrame = _panels.get_node("%TabardFrame")
@onready var _trade: TradeFrame = _panels.get_node("%TradeFrame")
@onready var _friends: FriendsFrame = _panels.get_node("%FriendsFrame")
@onready var _open_mail: OpenMailFrame = _panels.get_node("%OpenMailFrame")
@onready var _item_text: ItemTextFrame = _panels.get_node_or_null("%ItemTextFrame")
@onready var _game_menu: Control = _panels.get_node("%GameMenuFrame")
@onready var _spell_book: SpellBook = _panels.get_node("%SpellBookFrame")
@onready var _talents: TalentFrame = _panels.get_node("%TalentFrame")
@onready var _quest_log: QuestLogFrame = _panels.get_node("%QuestLogFrame")
@onready var _popup: StaticPopup = _panels.get_node("%StaticPopup1")
@onready var _gossip: GossipFrame = _panels.get_node("%GossipFrame")
@onready var _quest_watch: QuestWatchFrame = %QuestWatchFrame
@onready var _merchant: MerchantFrame = _panels.get_node("%MerchantFrame")
@onready var _trainer: ClassTrainerFrame = _panels.get_node("%ClassTrainerFrame")
@onready var _trade_skill: TradeSkillFrame = _panels.get_node("%TradeSkillFrame")
@onready var _dress_up: DressUpFrame = _panels.get_node("%DressUpFrame")
@onready var _inspect: InspectFrame = _panels.get_node("%InspectFrame")
@onready var _taxi: TaxiFrame = _panels.get_node("%TaxiFrame")
@onready var _loot: LootFrame = _panels.get_node("%LootFrame")
@onready var _world_map: WorldMapFrame = _panels.get_node("%WorldMapFrame")
@onready var _quest_frame: QuestFrame = _panels.get_node("%QuestFrame")


func _ready() -> void:
	WowFonts.apply()
	resized.connect(_fit_ui_parent)
	_fit_ui_parent.call_deferred()
	_main_menu_bar.action_used.connect(action_used.emit)
	_main_menu_bar.panel_toggled.connect(_on_panel_toggled)
	_main_menu_bar.bag_toggled.connect(_panels.toggle_bag)
	_panels.bag_opened.connect(_main_menu_bar.set_bag_open)
	for container: ContainerFrame in _panels.find_children("*", "ContainerFrame", false, false):
		container.item_used.connect(use_container_item)
		container.item_hovered.connect(_on_container_item_hovered)
		container.item_left.connect(_hide_tooltip)
	_spell_book.spell_used.connect(spell_used.emit)
	_quest_log.abandon_requested.connect(_on_abandon_requested)
	_character.unlearn_requested.connect(_on_unlearn_requested)
	_character.watched_changed.connect(_main_menu_bar.show_reputation)
	_quest_log.share_answered.connect(show_notice)
	_bank.open_requested.connect(_panels.show_panel.bind(_bank))
	_bank.error_raised.connect(show_error)
	_bank.bag_toggled.connect(_panels.toggle_bag)
	_bank.visibility_changed.connect(func() -> void:
		if not _bank.visible:
			_panels.close_bank_bags()
	)
	_stable.open_requested.connect(_panels.show_panel.bind(_stable))
	_stable.error_raised.connect(show_error)
	_mail.open_requested.connect(_panels.show_panel.bind(_mail))
	_mail.mail_opened.connect(_open_mail.show_mail)
	_open_mail.open_requested.connect(_panels.show_panel.bind(_open_mail))
	_open_mail.take_money_requested.connect(_mail.take_money)
	_open_mail.take_item_requested.connect(_mail.take_item)
	_open_mail.delete_requested.connect(_mail.delete)
	_open_mail.return_requested.connect(_mail.return_to_sender)
	_open_mail.letter_requested.connect(_mail.keep_letter)
	if _item_text:
		_item_text.open_requested.connect(_panels.show_panel.bind(_item_text))
	_auction.open_requested.connect(_panels.show_panel.bind(_auction))
	_auction.error_raised.connect(show_error)
	for frame: Control in [_registrar, _petition, _tabard]:
		frame.open_requested.connect(_panels.show_panel.bind(frame))
		frame.error_raised.connect(show_error)
		frame.message_added.connect(show_notice)
	_auction.message_added.connect(add_system_line)
	_trade.open_requested.connect(_panels.show_panel.bind(_trade))
	_trade.error_raised.connect(show_error)
	_trade.message_added.connect(add_system_line)
	_trade.trade_offered.connect(_on_trade_offered)
	_friends.message_added.connect(add_system_line)
	_friends.name_requested.connect(_on_friend_name_requested)
	_friends.guild_invited.connect(_on_guild_invited)
	_duel = Duel.new(WowClient.session)
	_duel.challenged.connect(_on_duel_challenged)
	_duel.counted_down.connect(func(seconds: int) -> void:
		show_notice(WowStrings.get_text("DUEL_COUNTDOWN", "%d") % seconds)
	)
	_duel.finished.connect(add_system_line)
	WowClient.session.packet_received.connect(_on_packet_received)
	_chat.emote_requested.connect(_on_emote_requested)
	_chat.ticket_requested.connect(ticket_requested.emit)
	_gossip.open_requested.connect(_panels.show_panel.bind(_gossip))
	_quest_frame.open_requested.connect(_panels.show_panel.bind(_quest_frame))
	_quest_frame.error_raised.connect(show_error)
	_quest_log.watch_toggled.connect(_quest_watch.toggle)
	_quest_watch.watches_changed.connect(_quest_log.set_watched)
	_quest_watch.error_raised.connect(show_error)
	_merchant.open_requested.connect(_panels.show_panel.bind(_merchant))
	_merchant.backpack_requested.connect(_panels.set_backpack_open)
	_merchant.error_raised.connect(show_error)
	_trainer.open_requested.connect(_panels.show_panel.bind(_trainer))
	_trade_skill.open_requested.connect(_panels.show_panel.bind(_trade_skill))
	_dress_up.open_requested.connect(_panels.show_panel.bind(_dress_up))
	ItemButton.dress_up = _dress_up.try_on
	_inspect.open_requested.connect(_panels.show_panel.bind(_inspect))
	WowClient.battlegrounds.queue_changed.connect(_on_battlefield_status)
	(_panels.get_node("%BattlefieldFrame") as BattlefieldFrame).set_portrait(
		_player_frame.portrait_texture()
	)
	_taxi.open_requested.connect(_panels.show_panel.bind(_taxi))
	_taxi.error_raised.connect(show_error)
	_loot.open_requested.connect(_panels.show_panel.bind(_loot))
	_loot.error_raised.connect(show_error)
	_loot.message_added.connect(add_system_line)
	_loot.master_loot_requested.connect(_show_master_loot_menu)
	WowClient.session.taxi_path_discovered.connect(
		func() -> void: show_notice(WowStrings.get_text("ERR_NEWTAXIPATH"))
	)
	TaxiNodes.load_known()
	WowClient.session.quest_kill_added.connect(_on_quest_kill_added)
	WowClient.session.quest_completed.connect(_on_quest_completed)
	_character.item_hovered.connect(_on_equipped_item_hovered)
	_character.item_left.connect(_hide_tooltip)
	_side_bars.action_used.connect(action_used.emit)
	_casting_bar_top = _casting_bar.offset_top
	_main_menu_bar.bottom_bars_toggled.connect(_on_bottom_bars_toggled)
	_on_bottom_bars_toggled(_main_menu_bar.get_node("%MultiBarBottomLeft").visible)
	_player_frame.unit_selected.connect(unit_selected.emit)
	_main_menu_bar.set_portrait(_player_frame.portrait_texture())
	_trade_skill.set_portrait(_player_frame.portrait_texture())
	_dress_up.set_portrait(_player_frame.portrait_texture())
	_party.unit_selected.connect(unit_selected.emit)
	_party.invited.connect(_on_party_invited)
	_party.message_added.connect(add_system_line)
	_party.error_raised.connect(show_error)
	_party.ready_check_started.connect(_on_ready_check_started)
	(%LootRolls as LootRolls).message_added.connect(add_system_line)
	var pet_frame: PetFrame = _player_frame.get_node("%PetFrame")
	pet_frame.unit_selected.connect(unit_selected.emit)
	pet_frame.unit_menu_requested.connect(_show_unit_menu)
	WowClient.pet.changed.connect(_on_pet_changed)
	_player_frame.unit_menu_requested.connect(_show_unit_menu)
	_target_frame.unit_menu_requested.connect(_show_unit_menu)
	_party.unit_menu_requested.connect(_show_unit_menu)
	_unit_menu.entry_selected.connect(_on_unit_menu_pressed)
	WowClient.session.spell_cast_failed.connect(_on_spell_cast_failed)
	WowClient.session.attack_swing_error.connect(_on_attack_swing_error)
	WowClient.session.object_updated.connect(_on_object_updated)
	WowClient.session.item_info_received.connect(func(_entry: int) -> void: _panels.refresh_bags())
	_spell_failures = WowLoader.data_table("spell_failures.json")
	_equip_failures = WowLoader.data_table("equip_failures.json")
	ItemButton.split_prompt = _ask_split
	var tab_at: Vector2 = _chat_frames[0].tab_position()
	for frame: DockedChatFrame in _chat_frames:
		tab_at.x += frame.dock_tab(tab_at)
		frame.tab_selected.connect(_select_chat_frame.bind(frame))
	_select_chat_frame(_chat_frames[0])


func _process(delta: float) -> void:
	var hovered: bool = _chat_frames.any(
		func(frame: DockedChatFrame) -> bool: return frame.is_hovered()
	)
	_chat_hover_time = _chat_hover_time + delta if hovered else 0.0
	for frame: DockedChatFrame in _chat_frames:
		frame.set_hovered(_chat_hover_time > CHAT_TAB_SHOW_DELAY)


func _unhandled_input(event: InputEvent) -> void:
	var typing: bool = get_viewport().gui_get_focus_owner() is LineEdit
	if not event.is_pressed() or event.is_echo() or typing:
		return
	if event.is_action_pressed("ui_cancel"):
		_escape()
	elif _exact(event, "toggle_character"):
		_toggle_character(CharacterFrame.Tab.CHARACTER)
	elif _exact(event, "toggle_skills"):
		_toggle_character(CharacterFrame.Tab.SKILLS)
	elif _exact(event, "toggle_reputation"):
		_toggle_character(CharacterFrame.Tab.REPUTATION)
	elif _exact(event, "toggle_spellbook"):
		_panels.toggle_panel(_spell_book)
	elif _exact(event, "toggle_talents"):
		_panels.toggle_panel(_talents)
	elif _exact(event, "toggle_quest_log"):
		_panels.toggle_panel(_quest_log)
	elif _exact(event, "toggle_world_map"):
		_panels.toggle_panel(_world_map)
	elif _exact(event, "toggle_bags"):
		_panels.open_all_bags()
	elif _exact(event, "toggle_backpack"):
		_panels.toggle_backpack()
	else:
		# TOGGLEBAG1 opens the leftmost bag, the fourth bag slot.
		for i: int in Inventory.BAG_COUNT:
			if _exact(event, "toggle_bag_%d" % (i + 1)):
				_panels.toggle_bag(Inventory.BAG_COUNT - i)
				get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()


# False when the spell is not a profession's, and should be cast as usual.
func open_trade_skill(spell_id: int) -> bool:
	return WowAssets.spells.opens_trade_skill(spell_id) and _trade_skill.open_for_spell(spell_id)


func show_player(guid: int) -> void:
	_player_frame.show_unit(guid)


func show_target(guid: int) -> void:
	_target_frame.show_unit(guid)


func target() -> int:
	return _target_frame.guid if _target_frame.visible else 0


# CMSG_TEXT_EMOTE: the text emote, the animation variant, and the unit it is aimed at.
func _on_emote_requested(text_emote: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(16)
	payload.encode_u32(0, text_emote)
	payload.encode_u64(8, target())
	WowClient.session.send_packet("CMSG_TEXT_EMOTE", payload)


# What the server says instead of delivering a chat line.
func _chat_refusal(opcode: String, reader: PacketReader) -> String:
	match opcode:
		"SMSG_NOTIFICATION":
			return reader.cstring()
		"SMSG_SERVER_MESSAGE":
			var key: String = SERVER_MESSAGE_KEYS.get(reader.u32(), "")
			return WowStrings.get_text(key, "%s").replace("%s", reader.cstring())
		"SMSG_CHAT_RESTRICTED":
			return WowStrings.get_text(CHAT_RESTRICTED_KEYS.get(reader.u8(), "ERR_CHAT_RESTRICTED"))
		"SMSG_CHAT_PLAYER_NOT_FOUND":
			return WowStrings.get_text("ERR_CHAT_PLAYER_NOT_FOUND_S").replace("%s", reader.cstring())
		"SMSG_CHAT_WRONG_FACTION":
			return WowStrings.get_text("ERR_CHAT_WRONG_FACTION")
	return ""


# SMSG_TEXT_EMOTE: the client writes the line itself, from EmotesText and EmotesTextData.
func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode == "SMSG_LOGOUT_RESPONSE":
		_on_logout_response(PacketReader.new(payload))
		return
	if opcode == "SMSG_LOGOUT_CANCEL_ACK":
		_popup.stop_count_down()
		return
	if opcode == "SMSG_CHANNEL_NOTIFY":
		var notice: String = Channels.notice(payload)
		if not notice.is_empty():
			add_system_line(notice)
		return
	if opcode == "SMSG_WHO":
		for who: String in ServerNotices.who_lines(payload):
			add_system_line(who)
		return
	if opcode == "SMSG_RAID_INSTANCE_INFO":
		for lockout: String in ServerNotices.raid_lockouts(payload):
			add_system_line(lockout)
		return
	if opcode == "SMSG_CHANNEL_LIST":
		_list_channel(Channels.members(payload))
		return
	if ServerNotices.play(opcode, payload):
		return
	if opcode == "SMSG_BINDER_CONFIRM":
		_ask_bind(PacketReader.new(payload).u64())
		return
	if opcode == "SMSG_SUMMON_REQUEST":
		_ask_summon(PacketReader.new(payload))
		return
	if opcode == "SMSG_QUEST_CONFIRM_ACCEPT":
		_ask_shared_quest(PacketReader.new(payload))
		return
	var server_line: String = ServerNotices.line(opcode, payload)
	if not server_line.is_empty():
		add_system_line(server_line)
		return
	var server_error: String = ServerNotices.error(opcode, payload)
	if not server_error.is_empty():
		show_error(server_error)
		return
	var refusal: String = _chat_refusal(opcode, PacketReader.new(payload))
	if not refusal.is_empty():
		add_system_line(refusal)
		return
	if opcode == "SMSG_INVENTORY_CHANGE_FAILURE":
		_show_equip_error(PacketReader.new(payload))
		return
	if opcode != "SMSG_TEXT_EMOTE":
		return
	var session: WowSession = WowClient.session
	var reader: PacketReader = PacketReader.new(payload)
	var actor: int = reader.u64()
	var text_emote: int = reader.u32()
	reader.u32()
	var target_name: String = reader.text(reader.u32())
	var me: int = session.get_player_guid()
	var line: String = Emotes.message(
		text_emote, session.get_object_name(actor), target_name, actor == me,
		target_name == session.get_object_name(me),
	)
	if not line.is_empty():
		add_chat_line(line, EMOTE_COLOR)


# A refusal code first, then whether the logout is instant, as it is in an inn or a city.
func _on_logout_response(reader: PacketReader) -> void:
	if reader.u32() != 0:
		show_error(WowStrings.get_text("ERR_LOGOUT_FAILED"))
	elif reader.u8() == 0:
		_popup.count_down(
			WowStrings.get_text("CAMP_TIMER"), LOGOUT_SECONDS,
			WowClient.session.send_packet.bind("CMSG_LOGOUT_CANCEL", PackedByteArray()),
		)


# A line in chat while waiting in a queue, and the stock entry prompt when a place opens.
func _on_battlefield_status(_slot: int, status: Battlegrounds.Status, map_id: int) -> void:
	var battleground: String = WowClient.map_display_name(map_id)
	var battlegrounds: Battlegrounds = WowClient.battlegrounds
	if status == Battlegrounds.Status.WAIT_QUEUE:
		var waiting: String = WowStrings.get_text("BATTLEFIELD_IN_QUEUE").get_slice("\n", 0)
		add_system_line(waiting % battleground)
	elif status == Battlegrounds.Status.WAIT_JOIN:
		_popup.ask(
			WowStrings.get_text("CONFIRM_BATTLEFIELD_ENTRY") % battleground,
			battlegrounds.enter.bind(map_id), "ENTER_BATTLE", "LEAVE_QUEUE",
			battlegrounds.abandon.bind(map_id),
		)


func _ask_bind(innkeeper: int) -> void:
	var payload: PackedByteArray = []
	payload.resize(8)
	payload.encode_u64(0, innkeeper)
	var here: String = AreaInfo.area_name(_area)
	_popup.ask(
		WowStrings.format(WowStrings.get_text("CONFIRM_BINDER"), [here]),
		WowClient.session.send_packet.bind("CMSG_BINDER_ACTIVATE", payload), "ACCEPT", "CANCEL",
	)


func _ask_summon(reader: PacketReader) -> void:
	var summoner: int = reader.u64()
	var answer: PackedByteArray = []
	answer.resize(8)
	answer.encode_u64(0, summoner)
	var place: String = AreaInfo.area_name(reader.u32())
	var text: String = WowStrings.get_text("CONFIRM_SUMMON")
	_popup.ask(
		WowStrings.format(text, [WowClient.session.get_object_name(summoner), place]),
		WowClient.session.send_packet.bind("CMSG_SUMMON_RESPONSE", answer), "ACCEPT", "CANCEL",
	)


# A party member starting an escort quest asks the rest whether they are in.
func _ask_shared_quest(reader: PacketReader) -> void:
	var payload: PackedByteArray = []
	payload.resize(4)
	payload.encode_u32(0, reader.u32())
	var title: String = reader.cstring()
	var starter: String = WowClient.session.get_object_name(reader.u64())
	_popup.ask(
		WowStrings.format(WowStrings.get_text("QUEST_ACCEPT"), [starter, title]),
		WowClient.session.send_packet.bind("CMSG_QUEST_CONFIRM_ACCEPT", payload), "YES", "NO",
	)


# Names arrive by query, so the list waits a moment for the ones not met before.
func _list_channel(list: Dictionary) -> void:
	var session: WowSession = WowClient.session
	for member: int in list["guids"]:
		session.get_object_name(member)
	await get_tree().create_timer(CHANNEL_LIST_WAIT).timeout
	var names: PackedStringArray = []
	for member: int in list["guids"]:
		names.append(session.get_object_name(member))
	add_system_line("[%s] %s" % [list["channel"], ", ".join(names)])


func add_chat_line(text: String, color: Color = Color.WHITE) -> void:
	_chat.add_message(text, color)


func add_system_line(text: String) -> void:
	_chat.add_message(text, ChatFrame.COLORS[WowSession.CHAT_SYSTEM])


func show_location(map_dir: String, wow_position: Vector3, facing: float) -> void:
	_minimap.show_location(map_dir, wow_position, facing)
	_world_map.set_player(map_dir, wow_position, facing, _area)


func show_corpse(wow_position: Vector3, map_id: int) -> void:
	_minimap.show_corpse(wow_position, map_id)
	_world_map.set_corpse(map_id, wow_position)


func show_area(area_id: int, player_race: int, map_id: int) -> void:
	_area = area_id
	(%WorldStateHeader as WorldStateHeader).show_place(map_id, area_id)
	_minimap.show_area(area_id, player_race)


func ask_release(on_release: Callable, on_self_resurrect: Callable = Callable()) -> void:
	_popup.ask(
		WowStrings.get_text("DEATH_RELEASE", "You have died."), on_release, "RELEASE_SPIRIT",
		"USE_SOULSTONE" if on_self_resurrect.is_valid() else "CANCEL", on_self_resurrect,
	)


func ask_reclaim(on_reclaim: Callable) -> void:
	_popup.ask(
		WowStrings.get_text("RECOVER_CORPSE", "Do you wish to return to life at your corpse?"),
		on_reclaim, "OKAY", "CANCEL",
	)


func ask_resurrect(caster: String, on_answer: Callable) -> void:
	_popup.ask(
		WowStrings.get_text("RESURRECT_REQUEST", "%s wants to resurrect you.") % caster,
		on_answer.bind(true), "ACCEPT", "DECLINE", on_answer.bind(false),
	)


func ask_spirit_healer(on_accept: Callable) -> void:
	_popup.ask(
		WowStrings.get_text("CONFIRM_XP_LOSS", "Resurrecting here costs experience."),
		on_accept, "OKAY", "CANCEL",
	)


func show_error(text: String) -> void:
	_errors.add_message(text, ERROR_COLOR)


func show_notice(text: String) -> void:
	_errors.add_message(text, NOTICE_COLOR)


func _exact(event: InputEvent, action: String) -> bool:
	return event.is_action_pressed(action, false, true)


# ToggleGameMenu: each Escape does the first of these that applies.
func _escape() -> void:
	if WowClient.targeting.cancel():
		pass
	elif _popup.cancel():
		pass
	elif _game_menu.visible:
		_panels.hide_panel(_game_menu)
	elif _casting_bar.spell_id != 0:
		WowClient.session.cancel_cast(_casting_bar.spell_id)
	elif _panels.close_all_windows():
		pass
	elif target() != 0:
		unit_selected.emit(0)
	else:
		_panels.show_panel(_game_menu)


func _on_abandon_requested(slot: int, title: String) -> void:
	_popup.ask(WowStrings.get_text("ABANDON_QUEST_CONFIRM") % title, _quest_log.abandon.bind(slot))


func _on_quest_kill_added(_quest: int, entry: int, count: int, required: int) -> void:
	var creature: String = WowClient.session.get_creature_template(entry).get("name", "")
	show_notice(WowStrings.get_text("ERR_QUEST_ADD_KILL_SII") % [creature, count, required])


func _on_quest_completed(quest: int, _xp: int, _money: int) -> void:
	var title: String = WowClient.session.get_quest_info(quest).get("title", "")
	show_notice(WowStrings.get_text("ERR_QUEST_COMPLETE_S") % title)


func _on_unlearn_requested(skill_id: int, skill_name: String) -> void:
	var text: String = WowStrings.get_text("UNLEARN_SKILL") % skill_name
	_popup.ask(text, _character.unlearn_skill.bind(skill_id), "UNLEARN", "CANCEL")


# ToggleCharacter: the key for the tab already showing closes the frame.
func _toggle_character(tab: CharacterFrame.Tab) -> void:
	if _character.visible and _character.current_tab() == tab:
		_panels.hide_panel(_character)
		return
	_character.show_tab(tab)
	_panels.show_panel(_character)


func _on_panel_toggled(panel: MainMenuBar.GamePanel) -> void:
	match panel:
		MainMenuBar.GamePanel.CHARACTER:
			_toggle_character(CharacterFrame.Tab.CHARACTER)
		MainMenuBar.GamePanel.SPELLBOOK:
			_panels.toggle_panel(_spell_book)
		MainMenuBar.GamePanel.TALENTS:
			_panels.toggle_panel(_talents)
		MainMenuBar.GamePanel.QUEST_LOG:
			_panels.toggle_panel(_quest_log)
		MainMenuBar.GamePanel.SOCIAL:
			_friends.request_lists()
			_panels.toggle_panel(_friends)
		MainMenuBar.GamePanel.WORLD_MAP:
			_panels.toggle_panel(_world_map)
		MainMenuBar.GamePanel.BAGS:
			_panels.toggle_backpack()
		MainMenuBar.GamePanel.GAME_MENU:
			if _game_menu.visible:
				_panels.hide_panel(_game_menu)
			else:
				_panels.close_all_windows()
				_panels.show_panel(_game_menu)


# UseContainerItem: gear equips, everything else is used.
# The stock frame asks for a name in a popup with an edit box; a targeted player fills it here.
func _on_friend_name_requested(tab: FriendsFrame.Tab) -> void:
	var player_name: String = WowClient.session.get_object_name(target())
	if player_name.is_empty():
		show_error(WowStrings.get_text("ERR_BAD_PLAYER_NAME_S", "") % "")
		return
	_friends.add(player_name)
	if tab == FriendsFrame.Tab.GUILD:
		return
	add_system_line(WowStrings.get_text(
		"FRIEND_ADDED" if tab == FriendsFrame.Tab.FRIENDS else "IGNORE_ADDED", player_name
	))


# RENAME_PET: a pet that has just been tamed asks for a name once.
func _on_pet_changed() -> void:
	var pet: Pet = WowClient.pet
	if pet.guid == _named_pet or not pet.can_rename():
		return
	_named_pet = pet.guid
	_popup.ask_name(WowStrings.get_text("PET_RENAME_LABEL", "Name your pet"), pet.rename)


func _on_guild_invited(inviter: String, guild_name: String) -> void:
	_popup.ask(
		WowStrings.get_text("GUILD_INVITATION", "%s invites you to join %s") % \
		[inviter, guild_name],
		_friends.accept_guild_invite, "ACCEPT", "DECLINE", _friends.decline_guild_invite,
	)


func _on_ready_check_started() -> void:
	_popup.ask(
		READY_CHECK_QUESTION,
		PartyFrame.answer_ready_check.bind(true), "YES", "NO",
		PartyFrame.answer_ready_check.bind(false),
	)


func _on_duel_challenged(challenger: String) -> void:
	_popup.ask(
		WowStrings.get_text("DUEL_REQUESTED", "%s has challenged you to a duel.") % challenger,
		_duel.accept, "ACCEPT", "DECLINE", _duel.decline,
	)


# CMSG_IGNORE_TRADE and CMSG_BUSY_TRADE turn an offer away without asking.
func _on_trade_offered(player_name: String, player_guid: int) -> void:
	if _friends.is_ignored(player_guid):
		WowClient.session.send_packet("CMSG_IGNORE_TRADE", PackedByteArray())
		return
	if _popup.visible:
		WowClient.session.send_packet("CMSG_BUSY_TRADE", PackedByteArray())
		return
	_popup.ask(
		WowStrings.get_text("TRADE_WITH_QUESTION", "Trade with %s?") % player_name,
		_trade.accept_offer, "ACCEPT", "DECLINE", _trade.decline_offer,
	)


# Right-clicking an auctioneer opens the auction house they work for.
func open_auction_house(guid: int) -> void:
	_auction.hello(guid)


# Right-clicking a stable master lists the pets they keep.
func open_stable(guid: int) -> void:
	_stable.list_pets(guid)


# Right-clicking a mailbox in the world opens the inbox.
func open_mailbox(guid: int) -> void:
	_mail.open(guid)


func use_container_item(bag: int, slot: int) -> void:
	var item: int = Inventory.container_item(bag, slot)
	var item_entry: int = Inventory.entry(item)
	if item_entry == 0:
		return
	if _merchant.vendor() != 0:
		_merchant.sell(item)
		return
	if _bank.store(bag, slot):
		return
	if _auction.offer(item):
		return
	if _trade.offer(bag, slot):
		return
	if item_entry == GuildRegistrarFrame.CHARTER_ENTRY:
		_petition.show_signatures(item)
		return
	var address: Vector2i = Inventory.wire_address(bag, slot)
	var session: WowSession = WowClient.session
	var readable: Dictionary = session.get_item_info(item_entry)
	if _item_text and readable.get("page_text", 0) != 0:
		_item_text.read(readable.get("name", ""), readable["page_text"])
		return
	for use_spell: int in readable.get("use_spells", PackedInt32Array()):
		if WowAssets.spells.targets_item(use_spell):
			WowClient.targeting.begin_item(address)
			return
	if session.get_item_info(item_entry).get("inventory_type", 0) != 0:
		session.send_packet("CMSG_AUTOEQUIP_ITEM", PackedByteArray([address.x, address.y]))
	else:
		# Bag and slot, spell slot 0, and a target mask of 0, which is the player.
		session.send_packet("CMSG_USE_ITEM", PackedByteArray([address.x, address.y, 0, 0, 0]))


func _on_container_item_hovered(bag: int, slot: int, button: ItemButton) -> void:
	var item: int = Inventory.container_item(bag, slot)
	if item and GameTooltip.current:
		var anchor: GameTooltip.TooltipAnchor = GameTooltip.TooltipAnchor.LEFT
		GameTooltip.current.set_item(button, Inventory.entry(item), item, anchor)


func _on_equipped_item_hovered(slot: Inventory.Slot, button: ItemButton) -> void:
	if GameTooltip.current == null:
		return
	var item: int = Inventory.equipped(slot)
	if item:
		GameTooltip.current.set_item(button, Inventory.entry(item), item)
	else:
		GameTooltip.current.set_text(button, CharacterFrame.slot_label(slot))


func _hide_tooltip(button: ItemButton) -> void:
	if GameTooltip.current:
		GameTooltip.current.hide_for(button)


# Bags follow the player's slots, their containers and the items in them.
func _on_object_updated(guid: int) -> void:
	var session: WowSession = WowClient.session
	if guid == WowClient.pet.guid:
		_on_pet_changed()
	if guid == session.get_player_guid() or session.get_object_type(guid) in ITEM_TYPES:
		_panels.refresh_bags()
	if guid == session.get_player_guid():
		_note_away(session.get_field(guid, "PLAYER_FLAGS") & (PLAYER_FLAG_AFK | PLAYER_FLAG_DND))


func _note_away(away: int) -> void:
	var changed: int = away ^ _away
	_away = away
	var default_message: String = WowStrings.get_text("DEFAULT_AFK_MESSAGE", "Away")
	if changed & PLAYER_FLAG_AFK:
		add_system_line(WowStrings.format(WowStrings.get_text("MARKED_AFK_MESSAGE"), [default_message])
				if away & PLAYER_FLAG_AFK else WowStrings.get_text("CLEARED_AFK"))
	if changed & PLAYER_FLAG_DND:
		add_system_line(WowStrings.format(WowStrings.get_text("MARKED_DND"), [default_message])
				if away & PLAYER_FLAG_DND else WowStrings.get_text("CLEARED_DND"))


func _on_bottom_bars_toggled(shown: bool) -> void:
	var height: float = _casting_bar.offset_bottom - _casting_bar.offset_top
	_casting_bar.offset_top = _casting_bar_top - (CASTING_BAR_LIFT if shown else 0.0)
	_casting_bar.offset_bottom = _casting_bar.offset_top + height


# FCF_SelectDockFrame: the docked frames share one area and show only the chosen one.
func _select_chat_frame(selected: DockedChatFrame) -> void:
	for frame: DockedChatFrame in _chat_frames:
		frame.set_selected(frame == selected)


func _fit_ui_parent() -> void:
	# With Use UI Scale off, the stock client shrinks the UI to 0.9 on windows taller than 853 pixels.
	var stock_scale: float = clampf(UI_HEIGHT / get_window().size.y, MIN_STOCK_SCALE, 1.0)
	var ui_scale: float = size.y / UI_HEIGHT * stock_scale
	_ui_parent.scale = Vector2(ui_scale, ui_scale)
	_ui_parent.size = size / ui_scale


# Interrupts arrive with reason -1 and are shown by the casting bar instead.
func _on_spell_cast_failed(caster: int, _spell_id: int, reason: int) -> void:
	var session: WowSession = WowClient.session
	if caster != session.get_player_guid() or reason < 0:
		return
	var key: String = _spell_failures.get(str(reason), "")
	if key == "SPELL_FAILED_NO_POWER":
		var power: int = (session.get_field(caster, "UNIT_FIELD_BYTES_0") >> 24) & 0xFF
		key = OUT_OF_POWER[power] if power < OUT_OF_POWER.size() else key
	if not key.is_empty():
		show_error(WowStrings.get_text(key))


# An item dropped anywhere but a slot is destroyed, as it is in the stock client.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("item_address")


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var address: Vector2i = data["item_address"]
	var item: int = Inventory.item_at(address)
	if item == 0:
		return
	var info: Dictionary = WowClient.session.get_item_info(Inventory.entry(item))
	_popup.ask(
		WowStrings.get_text("DELETE_ITEM") % info.get("name", ""),
		Inventory.destroy.bind(address, Inventory.stack_count(item)),
	)


# ponytail: a typed count, where the stock client drags a slider in StackSplitFrame.
func _ask_split(from: Vector2i, to: Vector2i, stack: int) -> void:
	_popup.ask_name(
		"Split how many of %d?" % stack,
		func(text: String) -> void: Inventory.split(from, to, clampi(text.to_int(), 1, stack - 1)),
	)


# Anything past the table shows as a full bag, as the stock client does.
func _show_equip_error(reader: PacketReader) -> void:
	var reason: int = reader.u8()
	if reason == 0:
		return
	var key: String = _equip_failures.get(str(reason), "ERR_BAG_FULL")
	if reason == EQUIP_ERR_LEVEL:
		show_error(WowStrings.get_text(key) % reader.u32())
		return
	show_error(WowStrings.get_text(key))


func _on_attack_swing_error(error: WowSession.AttackError) -> void:
	show_error(WowStrings.get_text(SWING_ERRORS[error]))


func _on_party_invited(inviter: String) -> void:
	_popup.ask(
		WowStrings.get_text("INVITATION") % inviter, PartyFrame.accept, "ACCEPT", "DECLINE",
		PartyFrame.decline,
	)


# UnitPopup: the unit's name over what can be done with them.
func _show_unit_menu(guid: int) -> void:
	var session: WowSession = WowClient.session
	_menu_name = session.get_object_name(guid)
	for member: Dictionary in PartyFrame.members:
		if member["guid"] == guid:
			_menu_name = member["name"]
	var is_player: bool = session.get_object_type(guid) == Entities.ObjectType.PLAYER
	var may_change: bool = not PartyFrame.in_party() or PartyFrame.is_leader()
	var entries: Array[Dictionary] = []
	if guid == WowClient.pet.guid and guid != 0:
		var hunter: bool = WowClient.pet.is_hunter_pet()
		entries.append({
			"text": WowStrings.get_text("PET_ABANDON" if hunter else "PET_DISMISS"),
			"id": UnitMenuItem.PET_ABANDON if hunter else UnitMenuItem.PET_DISMISS,
		})
	elif guid == session.get_player_guid():
		if PartyFrame.in_party():
			entries.append({"text": WowStrings.get_text("PARTY_LEAVE"), "id": UnitMenuItem.LEAVE})
		if may_change:
			entries.append({
				"text": WowStrings.get_text("RESET_INSTANCES"), "id": UnitMenuItem.RESET_INSTANCES,
			})
	elif PartyFrame.has_member(_menu_name):
		if may_change:
			entries.append({
				"text": WowStrings.get_text("PARTY_UNINVITE"), "id": UnitMenuItem.UNINVITE,
			})
	elif is_player and may_change:
		entries.append({"text": WowStrings.get_text("PARTY_INVITE"), "id": UnitMenuItem.INVITE})
	if guid != session.get_player_guid() and is_player:
		entries.append({"text": WowStrings.get_text("INSPECT"), "id": UnitMenuItem.INSPECT})
		entries.append({"text": WowStrings.get_text("TRADE", "Trade"), "id": UnitMenuItem.TRADE})
		entries.append({"text": WowStrings.get_text("DUEL", "Duel"), "id": UnitMenuItem.DUEL})
		_menu_guid = guid
	if entries.is_empty():
		return
	entries.push_front({"text": _menu_name, "title": true})
	entries.append({"text": WowStrings.get_text("CANCEL", "Cancel")})
	_unit_menu.open(entries, get_viewport().get_mouse_position())


func _show_master_loot_menu(slot: int, candidates: PackedInt64Array) -> void:
	_loot_slot = slot
	_loot_candidates = candidates
	var entries: Array[Dictionary] = [{"text": WowStrings.get_text("GIVE_LOOT"), "title": true}]
	for i: int in candidates.size():
		var receiver: String = WowClient.session.get_object_name(candidates[i])
		entries.append({"text": receiver, "id": MASTER_LOOT_ID + i})
	entries.append({"text": WowStrings.get_text("CANCEL", "Cancel")})
	_unit_menu.open(entries, get_viewport().get_mouse_position())


func _on_unit_menu_pressed(id: int) -> void:
	if id >= MASTER_LOOT_ID:
		_loot.give(_loot_slot, _loot_candidates[id - MASTER_LOOT_ID])
		return
	match id as UnitMenuItem:
		UnitMenuItem.INVITE:
			PartyFrame.invite(_menu_name)
		UnitMenuItem.UNINVITE:
			PartyFrame.uninvite(_menu_name)
		UnitMenuItem.LEAVE:
			PartyFrame.leave()
		UnitMenuItem.INSPECT:
			_inspect.inspect(_menu_guid)
		UnitMenuItem.TRADE:
			_trade.start(_menu_guid)
		UnitMenuItem.DUEL:
			_duel.challenge(_menu_guid)
		UnitMenuItem.PET_DISMISS:
			WowClient.pet.dismiss()
		UnitMenuItem.PET_ABANDON:
			_popup.ask(WowStrings.get_text("PET_ABANDON_CONFIRM", "Abandon your pet?"), WowClient.pet.abandon)
		UnitMenuItem.RESET_INSTANCES:
			WowClient.session.send_packet("CMSG_RESET_INSTANCES", PackedByteArray())
