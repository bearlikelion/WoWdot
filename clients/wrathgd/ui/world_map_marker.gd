class_name WorldMapMarker
extends Control

enum Kind {
	POI, MAJOR_POI, FLIGHT_KNOWN, FLIGHT_UNKNOWN, QUEST, CORPSE, TEAM_MATE, FLAG_CARRIER,
	QUEST_POI, QUEST_TURN_IN,
}

# mWoW's map markers: gold landmarks, flight point diamonds, quest givers cyan ringed in gold.
const POI_COLOR: Color = Color("#FFD700")
const FLIGHT_UNKNOWN_COLOR: Color = Color("#46C85A")
const QUEST_COLOR: Color = Color("#00D2FF")
const CORPSE_COLOR: Color = Color("#E8E8E8")
const TEAM_COLOR: Color = Color("#4C8CFF")
const FLAG_COLOR: Color = Color("#FF3B30")
const OUTLINE: Color = Color(0.1, 0.08, 0.02)
const SIZES: Dictionary[Kind, float] = {
	Kind.POI: 8.0, Kind.MAJOR_POI: 16.0, Kind.FLIGHT_KNOWN: 12.0, Kind.FLIGHT_UNKNOWN: 12.0,
	Kind.QUEST: 10.0, Kind.CORPSE: 14.0, Kind.TEAM_MATE: 8.0, Kind.FLAG_CARRIER: 12.0,
	Kind.QUEST_POI: 24.0, Kind.QUEST_TURN_IN: 24.0,
}
# QuestPOITemplate's art: the number sheet's circle, a numeral's cell, and the turn-in mark.
const POI_SHEET: String = "Interface\\WorldMap\\UI-QuestPoi-NumberIcons.blp"
const TURN_IN_ICON: String = "Interface\\WorldMap\\UI-WorldMap-QuestIcon.blp"
const POI_CIRCLE: Rect2 = Rect2(0.875, 0.875, 0.125, 0.125)
const POI_TURN_IN_CIRCLE: Rect2 = Rect2(0.5, 0.375, 0.125, 0.125)
const POI_ICONS_PER_ROW: int = 8
const POI_ICON_SIZE: float = 0.125
const TURN_IN_REGION: Rect2 = Rect2(0.0, 0.0, 0.5, 0.5)
const TURN_IN_SCALE: float = 0.75

var kind: Kind = Kind.POI:
	set(value):
		kind = value
		custom_minimum_size = Vector2.ONE * SIZES[kind]
		size = custom_minimum_size
		queue_redraw()
static var _textures: Dictionary[String, WowTexture] = {}

var title: String = ""
# A quest POI's number, counted from 1.
var number: int = 0
var description: String = ""


func _draw() -> void:
	var radius: float = SIZES[kind] / 2.0
	var center: Vector2 = size / 2.0
	match kind:
		Kind.QUEST_POI:
			var sheet: Texture2D = _texture(POI_SHEET)
			_draw_region(sheet, Rect2(Vector2.ZERO, size), POI_CIRCLE)
			# QuestPOI_DisplayButton: numerals fill the sheet's lower half, eight to a row.
			var cell: int = number - 1
			var numeral: Rect2 = Rect2(
				(cell % POI_ICONS_PER_ROW) * POI_ICON_SIZE,
				0.5 + floori(cell / float(POI_ICONS_PER_ROW)) * POI_ICON_SIZE,
				POI_ICON_SIZE, POI_ICON_SIZE,
			)
			_draw_region(sheet, Rect2(Vector2.ZERO, size), numeral)
		Kind.QUEST_TURN_IN:
			_draw_region(_texture(POI_SHEET), Rect2(Vector2.ZERO, size), POI_TURN_IN_CIRCLE)
			var mark: Vector2 = size * TURN_IN_SCALE
			_draw_region(_texture(TURN_IN_ICON), Rect2((size - mark) / 2.0, mark), TURN_IN_REGION)
		Kind.FLIGHT_KNOWN, Kind.FLIGHT_UNKNOWN:
			var diamond: PackedVector2Array = [
				center + Vector2(0.0, -radius), center + Vector2(radius, 0.0),
				center + Vector2(0.0, radius), center + Vector2(-radius, 0.0),
			]
			var fill: Color = POI_COLOR if kind == Kind.FLIGHT_KNOWN else FLIGHT_UNKNOWN_COLOR
			draw_colored_polygon(diamond, fill)
			diamond.append(diamond[0])
			draw_polyline(diamond, OUTLINE, 1.5, true)
		Kind.TEAM_MATE, Kind.FLAG_CARRIER:
			draw_circle(center, radius, OUTLINE)
			draw_circle(center, radius - 1.0, TEAM_COLOR if kind == Kind.TEAM_MATE else FLAG_COLOR)
		Kind.QUEST:
			draw_circle(center, radius, POI_COLOR)
			draw_circle(center, radius - 2.0, QUEST_COLOR)
		Kind.CORPSE:
			var arm: float = radius * 0.4
			for bar: Rect2 in [
				Rect2(center - Vector2(arm, radius), Vector2(arm * 2.0, radius * 2.0)),
				Rect2(center - Vector2(radius, arm * 0.5), Vector2(radius * 2.0, arm)),
			]:
				draw_rect(bar.grow(1.0), OUTLINE)
				draw_rect(bar, CORPSE_COLOR)
		_:
			draw_circle(center, radius, OUTLINE)
			draw_circle(center, radius - 1.5, POI_COLOR)


func _draw_region(sheet: Texture2D, rect: Rect2, uv: Rect2) -> void:
	var sheet_size: Vector2 = sheet.get_size()
	draw_texture_rect_region(sheet, rect, Rect2(uv.position * sheet_size, uv.size * sheet_size))


static func _texture(path: String) -> WowTexture:
	if not _textures.has(path):
		var texture: WowTexture = WowTexture.new()
		texture.file = path
		_textures[path] = texture
	return _textures[path]
