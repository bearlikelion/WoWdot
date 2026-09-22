extends Node

var session: WowSession = WowSession.new()
var cooldowns: Cooldowns = Cooldowns.new(session, WowAssets.spells)
var clock: GameClock = GameClock.new(session)
var weather: WeatherState = WeatherState.new(session)
var combat: CombatEvents = CombatEvents.new(session)
var pet: Pet = Pet.new(session)
var tutorials: Tutorials = Tutorials.new(session)
var macros: Macros = Macros.new(session)
var targeting: ItemTargeting = ItemTargeting.new(session)
var battlegrounds: Battlegrounds = Battlegrounds.new(session)
var proficiencies: Proficiencies = Proficiencies.new(session)
var equipment_sets: EquipmentSets = EquipmentSets.new(session)
var dungeon_finder: DungeonFinder = DungeonFinder.new(session)
var achievements: Achievements = Achievements.new(session)
var arena_teams: ArenaTeams = ArenaTeams.new(session)


func _ready() -> void:
	KeyBindings.apply()


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
