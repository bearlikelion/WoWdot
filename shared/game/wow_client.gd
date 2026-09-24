extends Node

var _t0: int = _tp("client init start")
var session: WowSession = WowSession.new()
var _t1: int = _tp("before spells")
var cooldowns: Cooldowns = Cooldowns.new(session, WowAssets.spells)
var _t2: int = _tp("after spells")
var clock: GameClock = GameClock.new(session)
var weather: WeatherState = WeatherState.new(session)
var combat: CombatEvents = CombatEvents.new(session)
var pet: Pet = Pet.new(session)
var tutorials: Tutorials = Tutorials.new(session)
var account_data: AccountData = AccountData.new(session)
var macros: Macros = Macros.new(session, account_data)
var targeting: ItemTargeting = ItemTargeting.new(session)
var battlegrounds: Battlegrounds = Battlegrounds.new(session)
var proficiencies: Proficiencies = Proficiencies.new(session)
var equipment_sets: EquipmentSets = EquipmentSets.new(session)
var dungeon_finder: DungeonFinder = DungeonFinder.new(session)
var achievements: Achievements = Achievements.new(session)
var arena_teams: ArenaTeams = ArenaTeams.new(session)
var guild_bank: GuildBank = GuildBank.new(session)
var barbershop: Barbershop = Barbershop.new(session)
var calendar: Calendar = Calendar.new(session)
var battlefield: BattlefieldManager = BattlefieldManager.new(session)
var vehicle: Vehicle = Vehicle.new(session)
var difficulty: InstanceDifficulty = InstanceDifficulty.new(session)
var spell_modifiers: SpellModifiers = SpellModifiers.new(session)
var quest_pois: QuestPOIs = QuestPOIs.new(session)
# SMSG_BINDPOINTUPDATE's area, the home a hearthstone's $z names.
var home_area: int = 0


static func _tp(what: String) -> int:
	print("TIMING %d %s" % [Time.get_ticks_msec(), what])
	return 0


func _ready() -> void:
	_tp("client ready")
	KeyBindings.apply()
	account_data.received.connect(_on_account_data_received)
	session.packet_received.connect(_on_packet_received)


func _process(_delta: float) -> void:
	session.poll()


# The name players see, such as Warsong Gulch, where map_name gives the folder the map loads from.
func map_display_name(map_id: int) -> String:
	var maps: WowDBC = WowDBC.open(WowAssets.archive, "Map")
	var row: int = maps.find(map_id)
	return maps.get_string(row, "MapName") if row >= 0 else ""


func map_name(map_id: int) -> String:
	var maps: WowDBC = WowDBC.open(WowAssets.archive, "Map")
	var row: int = maps.find(map_id)
	return maps.get_string(row, "InternalName") if row >= 0 else ""


func _on_account_data_received(type: AccountData.Type, text: String) -> void:
	if type == AccountData.Type.GLOBAL_BINDINGS or type == AccountData.Type.CHARACTER_BINDINGS:
		KeyBindings.from_cache(text)


func _on_packet_received(opcode: String, payload: PackedByteArray) -> void:
	if opcode == "SMSG_BINDPOINTUPDATE" and payload.size() >= 20:
		home_area = payload.decode_u32(16)
