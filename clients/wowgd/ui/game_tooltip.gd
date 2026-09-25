class_name GameTooltip
extends Control

# LEFT and RIGHT are WoW's ANCHOR_LEFT and ANCHOR_RIGHT, which sit above the owner.
enum TooltipAnchor { DEFAULT, BOTTOM_LEFT, BOTTOM_RIGHT, LEFT, RIGHT, TOP_LEFT }

const LINE: PackedScene = preload("res://ui/tooltip_line.tscn")
const PADDING: Vector2 = Vector2(10.0, 10.0)
const WRAP_WIDTH: float = 260.0
# GameTooltip_SetDefaultAnchor: bottom right, clear of the bags (CONTAINER_OFFSET_Y).
const DEFAULT_OFFSET: Vector2 = Vector2(13.0, 70.0)
const NORMAL: Color = Color(1.0, 0.82, 0.0)
const HIGHLIGHT: Color = Color(1.0, 1.0, 1.0)
const GRAY: Color = Color(0.5, 0.5, 0.5)
# FACTION_BAR_COLORS for hostile, neutral and friendly names.
const HOSTILE_NAME: Color = Color(0.8, 0.3, 0.22)
const NEUTRAL_NAME: Color = Color(0.9, 0.7, 0.0)
const FRIENDLY_NAME: Color = Color(0.0, 0.6, 0.1)
const RED: Color = Color(1.0, 0.13, 0.13)
# ITEM_QUALITY0_COLOR to ITEM_QUALITY6_COLOR, poor to artifact.
const QUALITY_COLORS: Array[Color] = [
	Color(0.62, 0.62, 0.62), Color(1.0, 1.0, 1.0), Color(0.12, 1.0, 0.0), Color(0.0, 0.44, 0.87),
	Color(0.64, 0.21, 0.93), Color(1.0, 0.5, 0.0), Color(0.9, 0.8, 0.5),
]
# The INVTYPE_ string for each item InventoryType; bags and ammo name no slot.
const INVENTORY_TYPES: PackedStringArray = [
	"", "INVTYPE_HEAD", "INVTYPE_NECK", "INVTYPE_SHOULDER", "INVTYPE_BODY", "INVTYPE_CHEST",
	"INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET", "INVTYPE_WRIST", "INVTYPE_HAND",
	"INVTYPE_FINGER", "INVTYPE_TRINKET", "INVTYPE_WEAPON", "INVTYPE_SHIELD", "INVTYPE_RANGED",
	"INVTYPE_CLOAK", "INVTYPE_2HWEAPON", "", "INVTYPE_TABARD", "INVTYPE_ROBE",
	"INVTYPE_WEAPONMAINHAND", "INVTYPE_WEAPONOFFHAND", "INVTYPE_HOLDABLE", "", "INVTYPE_THROWN",
	"INVTYPE_RANGEDRIGHT", "", "INVTYPE_RELIC",
]
const ITEM_STATS: Dictionary[String, String] = {
	"strength": "ITEM_MOD_STRENGTH",
	"agility": "ITEM_MOD_AGILITY",
	"stamina": "ITEM_MOD_STAMINA",
	"intellect": "ITEM_MOD_INTELLECT",
	"spirit": "ITEM_MOD_SPIRIT",
}
const CREATURE_TYPE_NOT_SPECIFIED: int = 10
const SKULL_LEVEL_GAP: int = 10

## Off for ItemRefTooltip, which must not replace the shared one as current.
@export var shared: bool = true

# The HUD's tooltip; like WoW's GameTooltip there is one, shared by every frame.
static var current: GameTooltip

var _owner: Object = null
var _anchor: TooltipAnchor = TooltipAnchor.DEFAULT
var _anchor_to: Control = null
var _creature_types: WowDBC
var _races: WowDBC
var _classes: WowDBC

@onready var _lines: VBoxContainer = %Lines


func _ready() -> void:
	if shared:
		current = self
	var archive: WowArchive = WowAssets.archive
	_creature_types = WowDBC.open(archive, "CreatureType")
	_races = WowDBC.open(archive, "ChrRaces")
	_classes = WowDBC.open(archive, "ChrClasses")


func _exit_tree() -> void:
	if current == self:
		current = null


# Starts a new tooltip for owner; hide_for() later only hides it if the same owner still has it.
func begin(
	tooltip_owner: Object, anchor: TooltipAnchor = TooltipAnchor.DEFAULT, anchor_to: Control = null,
) -> void:
	for line: Node in _lines.get_children():
		_lines.remove_child(line)
		line.queue_free()
	_owner = tooltip_owner
	_anchor = anchor
	_anchor_to = anchor_to


func add_line(text: String, color: Color = HIGHLIGHT, word_wrap: bool = false) -> void:
	add_double_line(text, "", color, HIGHLIGHT, word_wrap)


func add_double_line(
	left: String, right: String, left_color: Color = HIGHLIGHT, right_color: Color = HIGHLIGHT,
	word_wrap: bool = false,
) -> void:
	var line: HBoxContainer = LINE.instantiate()
	_lines.add_child(line)
	var left_label: Label = line.get_node("%Left")
	var right_label: Label = line.get_node("%Right")
	if _lines.get_child_count() == 1:
		left_label.theme_type_variation = &"GameTooltipHeaderText"
		right_label.theme_type_variation = &"GameTooltipHeaderText"
	left_label.text = left
	left_label.self_modulate = left_color
	right_label.text = right
	right_label.self_modulate = right_color
	right_label.visible = not right.is_empty()
	if word_wrap:
		var font: Font = left_label.get_theme_font("font")
		var font_size: int = left_label.get_theme_font_size("font_size")
		if font.get_string_size(left, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > WRAP_WIDTH:
			left_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			left_label.custom_minimum_size.x = WRAP_WIDTH


# Sizes the tooltip to its lines and puts it where its anchor says, kept on screen.
func present() -> void:
	show()
	_fit.call_deferred()


func hide_for(tooltip_owner: Object) -> void:
	if _owner == tooltip_owner:
		_owner = null
		hide()


func set_spell(
	tooltip_owner: Object, spell_id: int, anchor: TooltipAnchor = TooltipAnchor.DEFAULT,
) -> void:
	begin(tooltip_owner, anchor, tooltip_owner as Control)
	var spells: SpellInfo = WowAssets.spells
	add_double_line(spells.spell_name(spell_id), spells.rank(spell_id), HIGHLIGHT, GRAY)
	_add_pair(SpellText.cost(spell_id), SpellText.range_text(spell_id))
	_add_pair(SpellText.cast_text(spell_id), SpellText.cooldown_text(spell_id))
	var description: String = SpellText.describe(spell_id)
	if not description.is_empty():
		add_line(description, NORMAL, true)
	present()


func set_aura(tooltip_owner: Control, spell_id: int, anchor: TooltipAnchor) -> void:
	begin(tooltip_owner, anchor, tooltip_owner)
	add_line(WowAssets.spells.spell_name(spell_id))
	var tooltip: String = SpellText.describe(spell_id, "Tooltip")
	if not tooltip.is_empty():
		add_line(tooltip, NORMAL, true)
	present()


# SetBagItem and SetInventoryItem: false while the item query has not answered yet.
func set_item(
	tooltip_owner: Control, item_entry: int, item: int = 0, anchor: TooltipAnchor = TooltipAnchor.RIGHT,
) -> bool:
	var info: Dictionary = WowClient.session.get_item_info(item_entry)
	if info.is_empty():
		hide_for(tooltip_owner)
		return false
	begin(tooltip_owner, anchor, tooltip_owner)
	add_line(info["name"], QUALITY_COLORS[clampi(info["quality"], 0, QUALITY_COLORS.size() - 1)])
	if item and Inventory.is_soulbound(item):
		add_line(WowStrings.get_text("ITEM_SOULBOUND"))
	var inventory_type: int = info["inventory_type"]
	if inventory_type < INVENTORY_TYPES.size() and not INVENTORY_TYPES[inventory_type].is_empty():
		var skills: Proficiencies = WowClient.proficiencies
		var usable: bool = skills.can_use(info["class"], info["subclass"])
		add_double_line(
			WowStrings.get_text(INVENTORY_TYPES[inventory_type]),
			skills.subclass_name(info["class"], info["subclass"]),
			HIGHLIGHT, HIGHLIGHT if usable else RED,
		)
	if info["armor"] > 0:
		add_line(WowStrings.get_text("ARMOR_TEMPLATE") % info["armor"])
	if info["damage_max"] > 0.0:
		var speed: float = info["delay_msec"] / 1000.0
		add_double_line(
			WowStrings.get_text("DAMAGE_TEMPLATE") % [info["damage_min"], info["damage_max"]],
			"%s %.2f" % [WowStrings.get_text("SPEED"), speed],
		)
		var average: float = (info["damage_min"] + info["damage_max"]) / 2.0
		add_line(WowStrings.get_text("DPS_TEMPLATE") % (average / maxf(speed, 0.001)))
	for stat: String in ITEM_STATS:
		var amount: int = info[stat]
		if amount != 0:
			var line: String = WowStrings.get_text(ITEM_STATS[stat])
			add_line(line.replace("%c", "+" if amount > 0 else "-") % absi(amount))
	if info["container_slots"] > 0:
		add_line(WowStrings.get_text("CONTAINER_SLOTS") % [
			info["container_slots"], WowStrings.get_text("INVTYPE_BAG"),
		])
	var session: WowSession = WowClient.session
	var durability: int = session.get_field(item, "ITEM_FIELD_MAXDURABILITY") if item else 0
	if durability > 0:
		add_line(WowStrings.get_text("DURABILITY_TEMPLATE") % [
			session.get_field(item, "ITEM_FIELD_DURABILITY"), durability,
		])
	var required: int = info["required_level"]
	if required > 1:
		var level: int = session.get_field(session.get_player_guid(), "UNIT_FIELD_LEVEL")
		var color: Color = RED if level < required else HIGHLIGHT
		add_line(WowStrings.get_text("ITEM_MIN_LEVEL") % required, color)
	present()
	return true


func set_text(tooltip_owner: Object, title: String, text: String = "", right: String = "") -> void:
	begin(tooltip_owner)
	add_double_line(title, right, HIGHLIGHT, NORMAL)
	if not text.is_empty():
		add_line(text, NORMAL, true)
	present()


# The name in its reaction colour, a title, the level line, and Corpse for the dead.
func set_unit(tooltip_owner: Object, guid: int) -> void:
	var session: WowSession = WowClient.session
	if not session.has_object(guid):
		hide_for(tooltip_owner)
		return
	begin(tooltip_owner)
	var player: int = session.get_player_guid()
	var reaction: UnitReaction.Reaction = UnitReaction.between(session, player, guid)
	var is_player: bool = session.get_object_type(guid) == Entities.ObjectType.PLAYER
	var name_color: Color = FRIENDLY_NAME
	if reaction == UnitReaction.Reaction.HOSTILE:
		name_color = HOSTILE_NAME
	elif is_player:
		name_color = HIGHLIGHT
	elif reaction == UnitReaction.Reaction.NEUTRAL:
		name_color = NEUTRAL_NAME
	add_line(session.get_object_name(guid), name_color)
	var creature: Dictionary = session.get_creature_info(guid)
	if not String(creature.get("subname", "")).is_empty():
		add_line(creature["subname"])
	var level: int = session.get_field(guid, "UNIT_FIELD_LEVEL")
	var player_level: int = session.get_field(player, "UNIT_FIELD_LEVEL")
	var hostile: bool = reaction == UnitReaction.Reaction.HOSTILE
	var level_text: String = str(level)
	if hostile and level >= player_level + SKULL_LEVEL_GAP:
		level_text = "??"
	var kind: String = _unit_kind(guid, is_player, creature)
	var line: String = WowStrings.get_text("TOOLTIP_UNIT_LEVEL") % level_text
	if not kind.is_empty():
		line = WowStrings.get_text("TOOLTIP_UNIT_LEVEL_CLASS") % [level_text, kind]
	add_line(line, UnitReaction.level_color(level, player_level) if hostile else HIGHLIGHT)
	if session.get_field(guid, "UNIT_FIELD_HEALTH") == 0:
		add_line(WowStrings.get_text("CORPSE"), GRAY)
	present()


func _unit_kind(guid: int, is_player: bool, creature: Dictionary) -> String:
	var session: WowSession = WowClient.session
	if is_player:
		var bytes_0: int = session.get_field(guid, "UNIT_FIELD_BYTES_0")
		var race: int = _races.find(bytes_0 & 0xFF)
		var player_class: int = _classes.find((bytes_0 >> 8) & 0xFF)
		var race_name: String = _races.get_text(race, "Name") if race >= 0 else ""
		var class_text: String = ""
		if player_class >= 0:
			class_text = _classes.get_text(player_class, "Name")
		return ("%s %s" % [race_name, class_text]).strip_edges()
	var kind: String = ""
	var type_id: int = creature.get("type", 0)
	var type_row: int = _creature_types.find(type_id)
	if type_row >= 0 and type_id != CREATURE_TYPE_NOT_SPECIFIED:
		kind = _creature_types.get_text(type_row, "Name")
	var rank: int = creature.get("rank", 0)
	if rank == TargetFrame.Rank.ELITE or rank == TargetFrame.Rank.RARE_ELITE:
		kind = ("%s %s" % [WowStrings.get_text("ELITE"), kind]).strip_edges()
	return kind


func _add_pair(left: String, right: String) -> void:
	if not left.is_empty() or not right.is_empty():
		add_double_line(left, right)


func _fit() -> void:
	size = _lines.get_combined_minimum_size() + PADDING * 2.0
	var parent: Control = get_parent_control()
	if parent == null:
		return
	var at: Vector2 = parent.size - size - DEFAULT_OFFSET
	if _anchor != TooltipAnchor.DEFAULT and is_instance_valid(_anchor_to):
		var to_parent: Transform2D = parent.get_global_transform().affine_inverse()
		var owner_rect: Rect2 = to_parent * _anchor_to.get_global_rect()
		match _anchor:
			TooltipAnchor.BOTTOM_LEFT:
				at = owner_rect.position + Vector2(-size.x, owner_rect.size.y)
			TooltipAnchor.BOTTOM_RIGHT:
				at = owner_rect.end
			TooltipAnchor.LEFT:
				at = owner_rect.position - size
			TooltipAnchor.RIGHT:
				at = owner_rect.position + Vector2(owner_rect.size.x, -size.y)
			TooltipAnchor.TOP_LEFT:
				at = owner_rect.position - Vector2(0.0, size.y)
	position = at.clamp(Vector2.ZERO, (parent.size - size).max(Vector2.ZERO))
