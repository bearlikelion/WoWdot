class_name WorldMapMarker
extends Control

enum Kind { POI, MAJOR_POI, FLIGHT_KNOWN, FLIGHT_UNKNOWN, QUEST, CORPSE, TEAM_MATE, FLAG_CARRIER }

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
}

var kind: Kind = Kind.POI:
	set(value):
		kind = value
		custom_minimum_size = Vector2.ONE * SIZES[kind]
		size = custom_minimum_size
		queue_redraw()
var title: String = ""
var description: String = ""


func _draw() -> void:
	var radius: float = SIZES[kind] / 2.0
	var center: Vector2 = size / 2.0
	match kind:
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
